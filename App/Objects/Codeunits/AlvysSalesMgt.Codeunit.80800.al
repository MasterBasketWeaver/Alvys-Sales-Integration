codeunit 80800 "BAASI Alvys Sales Mgt."
{
    Permissions = tabledata "BAASI Alvys Sales Setup" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RIMD,
        tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "Dimension Set Entry" = R,
        tabledata "FRI Fleetrock Setup" = R,
        tabledata "Sales Invoice Header" = R,
        tabledata "Gen. Journal Template" = R,
        tabledata "Gen. Journal Batch" = R,
        tabledata "Gen. Journal Line" = RIMD;


    local procedure GetAndCheckSetup()
    begin
        if LoadedSetup then
            exit;
        AlvysSetup.Get();
        AlvysSetup.TestField("Integration URL");
        AlvysSetup.TestField("Client ID");
        AlvysSetup.TestField("Client Secret");
        // AlvysSetup.TestField("Entity Code Dimension");
        LoadedSetup := true;
    end;

    procedure CheckToGetAccessToken(): Text
    begin
        GetAndCheckSetup();
        if AlvysSetup.HasAccessToken() and (AlvysSetup."Access Token Expiry Date" <> 0DT) and (CurrentDateTime() < AlvysSetup."Access Token Expiry Date") then
            exit(AlvysSetup.GetAccessToken());
        exit(GetBearerToken(AlvysSetup));
    end;

    procedure GetBearerToken(): Text
    begin
        GetAndCheckSetup();
        exit(GetBearerToken(AlvysSetup));
    end;

    procedure GetBearerToken(var AlvysSalesSetup: Record "BAASI Alvys Sales Setup"): Text
    var
        RequestHeaders: HttpHeaders;
        ContentHeaders: HttpHeaders;
        JsonBody, ResponseObj : JsonObject;
        SendTime: DateTime;
        ExpiresIn: Integer;
        ExpiryDuration: Duration;
        RequestHeaderValues: Dictionary of [Text, Text];
        AccessToken, ErrorText, RequestBody, ResponseText : Text;
        Sent: Boolean;
    begin
        SendTime := CurrentDateTime();
        JsonBody.Add('client_id', AlvysSalesSetup."Client ID");
        JsonBody.Add('client_secret', AlvysSalesSetup."Client Secret");
        JsonBody.Add('audience', 'https://api.alvys.com/public/');
        JsonBody.Add('grant_type', 'client_credentials');
        JsonBody.WriteTo(RequestBody);
        // the token request is not logged, as the request body contains the client secret
        // and the response contains the access token
        PrepareHeaderValues('', RequestHeaderValues);
        Sent := RESTAPIMgt.TrySendJsonRequest('POST', 'https://auth.alvys.com/oauth/token', 'application/json', RequestBody, RequestHeaderValues, ResponseObj, ResponseText, ErrorText);
        if not Sent then
            Error(ErrorText);
        AccessToken := JsonMgt.GetJsonValueAsText(ResponseObj, 'access_token');
        if AccessToken = '' then
            Error(TokenMissingErr, ResponseText);
        ExpiresIn := JsonMgt.GetJsonValueAsInteger(ResponseObj, 'expires_in');
        ExpiryDuration := ExpiresIn * 1000;
        AlvysSalesSetup.SetAccessToken(AccessToken);
        AlvysSalesSetup.Validate("Access Token Expiry Date", SendTime + ExpiryDuration);
        AlvysSalesSetup.Modify(true);
        exit(AccessToken);
    end;


    procedure GetTruckID(TruckNumber: Text): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareTruckSearchBody(TruckNumber, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'trucks/search', 'application/json', JsonBody);
        exit(ExtractTruckID(ResponseObj, TruckNumber));
    end;

    procedure GetTruckID(TruckNumber: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; PostedDocNo: Code[20]): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareTruckSearchBody(TruckNumber, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'trucks/search', 'application/json', JsonBody, MapDocumentType(DocType), DocNo, PostedDocNo);
        exit(ExtractTruckID(ResponseObj, TruckNumber));
    end;

    local procedure PrepareTruckSearchBody(TruckNumber: Text; var JsonBody: JsonObject)
    begin
        GetAndCheckSetup();
        if TruckNumber = '' then
            Error(MissingTruckNumberErr);
        // Alvys pages are 0-indexed: asking for page 1 skips the only page of results and 404s.
        JsonBody.Add('Page', 0);
        JsonBody.Add('PageSize', 100);
        JsonBody.Add('TruckNumber', TruckNumber);
    end;

    local procedure ExtractTruckID(var ResponseObj: JsonObject; TruckNumber: Text): Text
    var
        ItemObj: JsonObject;
        ItemsArray: JsonArray;
        JsonTkn: JsonToken;
        TruckID: Text;
    begin
        if not ResponseObj.Get('Items', JsonTkn) then
            Error(NoTruckFoundErr, TruckNumber);
        ItemsArray := JsonTkn.AsArray();
        if ItemsArray.Count() = 0 then
            Error(NoTruckFoundErr, TruckNumber);
        ItemsArray.Get(0, JsonTkn);
        ItemObj := JsonTkn.AsObject();
        TruckID := JsonMgt.GetJsonValueAsText(ItemObj, 'Id');
        if TruckID = '' then
            Error(NoTruckFoundErr, TruckNumber);
        exit(TruckID);
    end;







    procedure GetTrucks(var TrucksArray: JsonArray; var ErrorText: Text): Boolean
    begin
        exit(GetList(TrucksPathTok, TrucksArray, ErrorText));
    end;

    procedure GetDrivers(var DriversArray: JsonArray; var ErrorText: Text): Boolean
    begin
        exit(GetList(DriversPathTok, DriversArray, ErrorText));
    end;

    /// <summary>
    /// GET trucks and GET drivers return every record, active or not, as one bare array: they take
    /// no paging, and the IsActive filter on trucks/search is ignored. The import asks on every run,
    /// so only a failed call is logged, leaving the caller to commit the entry before raising.
    /// </summary>
    local procedure GetList(Path: Text; var ResponseArray: JsonArray; var ErrorText: Text): Boolean
    var
        RequestHeaderValues: Dictionary of [Text, Text];
        URL, ResponseText : Text;
    begin
        GetAndCheckSetup();
        Clear(ResponseArray);
        URL := AlvysSetup."Integration URL" + Path;
        PrepareHeaderValues(CheckToGetAccessToken(), RequestHeaderValues);
        if RESTAPIMgt.TrySendRequest('GET', URL, '', '', RequestHeaderValues, ResponseText, ErrorText) then begin
            if ResponseArray.ReadFrom(ResponseText) then
                exit(true);
            ErrorText := StrSubstNo(UnexpectedListResponseErr, Path, ResponseText);
        end;
        InsertEntry(Enum::"BAASI Alvys Entry Doc. Type"::" ", '', URL, 'GET', '', ResponseText, ErrorText, false, true);
        exit(false);
    end;

    /// <summary>
    /// Creates a deduction for the truck on a posted sales document. Both headers are needed: the
    /// truck and the dimension come off the posted invoice, while the sales header is what says
    /// which document the invoice was posted from, so the deduction can be traced back to it.
    /// </summary>
    procedure CreateDeductionForTruck(var SalesHeader: Record "Sales Header"; var SalesInvHeader: Record "Sales Invoice Header"; Date: Date; Amount: Decimal; Category: Text; Description: Text; PreviewMode: Boolean): Text
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        TruckNumber: Text[50];
        TruckID: Text;
    begin
        TruckNumber := CopyStr(GetTruckDimensionValue(SalesInvHeader."Dimension Set ID"), 1, MaxStrLen(AlvysDeduction."Truck Number"));
        TruckID := GetTruckID(TruckNumber, SalesHeader."Document Type", SalesHeader."No.", SalesInvHeader."No.");
        exit(CreateDeductionForTruck(TruckID, TruckNumber, Date, Amount, Category, Description, SalesHeader."Document Type", SalesHeader."No.", SalesInvHeader."No.", PreviewMode));
    end;

    procedure CreateDeductionForTruck(TruckID: Text; TruckNumber: Text[50]; Date: Date; Amount: Decimal; Category: Text; Description: Text): Text
    begin
        exit(CreateDeduction(TruckIdTok, TruckID, TruckNumber, Date, Amount, Category, Description));
    end;

    procedure CreateDeductionForTruck(TruckID: Text; TruckNumber: Text[50]; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; PostedDocNo: Code[20]; PreviewMode: Boolean): Text
    begin
        exit(CreateDeduction(TruckIdTok, TruckID, TruckNumber, Date, Amount, Category, Description, DocType, DocNo, PostedDocNo, PreviewMode));
    end;

    procedure CreateDeductionForDriver(DriverID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text): Text
    begin
        exit(CreateDeduction(DriverIdTok, DriverID, '', Date, Amount, Category, Description));
    end;

    procedure CreateDeductionForDriver(DriverID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; PostedDocNo: Code[20]): Text
    begin
        exit(CreateDeduction(DriverIdTok, DriverID, '', Date, Amount, Category, Description, DocType, DocNo, PostedDocNo, false));
    end;

    /// <summary>
    /// Shared create-deduction core. Alvys treats DriverId and TruckId as mutually exclusive, so
    /// exactly one of them is written to the body, named by AssetIdFieldName. TruckNumber is not
    /// part of the request -- Alvys identifies the truck by its Id -- and is only carried through so
    /// the logged deduction records which truck number the Id was resolved from. Returns the Id of
    /// the deduction Alvys created.
    /// </summary>
    local procedure CreateDeduction(AssetIdFieldName: Text; AssetID: Text; TruckNumber: Text[50]; Date: Date; Amount: Decimal; Category: Text; Description: Text): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareDeductionBody(AssetIdFieldName, AssetID, Date, Amount, Category, Description, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'deductions/once', 'application/json', JsonBody);
        exit(InsertDeduction(ResponseObj, TruckNumber));
    end;

    local procedure CreateDeduction(AssetIdFieldName: Text; AssetID: Text; TruckNumber: Text[50]; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; PostedDocNo: Code[20]; PreviewMode: Boolean): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareDeductionBody(AssetIdFieldName, AssetID, Date, Amount, Category, Description, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'deductions/once', 'application/json', JsonBody, MapDocumentType(DocType), DocNo, PostedDocNo);
        if PreviewMode then
            DeleteDeduction(JsonMgt.GetJsonValueAsText(ResponseObj, 'Id'));
        exit(InsertDeduction(ResponseObj, TruckNumber, MapDocumentType(DocType), DocNo, PostedDocNo));
    end;

    local procedure PrepareDeductionBody(AssetIdFieldName: Text; AssetID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text; var JsonBody: JsonObject)
    begin
        GetAndCheckSetup();
        if AssetID = '' then
            Error(MissingAssetIDErr, AssetIdFieldName);
        JsonBody.Add('Date', Format(Date, 0, '<Year4>-<Month,2>-<Day,2>'));
        JsonBody.Add('Amount', Amount);
        JsonBody.Add('Category', Category);
        JsonBody.Add('Description', Description);
        JsonBody.Add(AssetIdFieldName, AssetID);
    end;



    procedure DeleteDeduction(DeductionID: Text): Text
    var
        JsonBody, ResponseObj : JsonObject;
        s: Text;
    begin
        if DeductionID = '' then
            exit('');
        ResponseObj := SendAPIRequest('DELETE', AlvysSetup."Integration URL" + 'deductions/' + DeductionID, 'application/json', JsonBody);
        ResponseObj.WriteTo(s);
        exit(s);
    end;


    /// <summary>
    /// Checks if a deduction exists in Alvys by its Id. Returns true if it does, false if it does not.
    /// </summary>
    procedure DoesDeductionExist(DeductionID: Text): Boolean
    var
        JsonBody: JsonObject;
        Result: Boolean;
    begin
        SendAPIRequest('GET', GetDeductionURL(DeductionID), 'application/json', JsonBody, false, Result);
        exit(Result);
    end;

    /// <summary>
    /// Reads a single deduction back from Alvys by its Id. The response is returned as-is rather
    /// than inserted, so that re-reading a deduction does not duplicate the logged entry.
    /// </summary>
    procedure GetDeduction(DeductionID: Text): JsonObject
    var
        JsonBody: JsonObject;
        Result: Boolean;
    begin
        exit(SendAPIRequest('GET', GetDeductionURL(DeductionID), 'application/json', JsonBody, false, Result));
    end;

    procedure GetDeduction(DeductionID: Text; var ResponseObj: JsonObject): Boolean
    var
        JsonBody: JsonObject;
        Result: Boolean;
    begin
        ResponseObj := SendAPIRequest('GET', GetDeductionURL(DeductionID), 'application/json', JsonBody, false, Result);
        exit(Result);
    end;

    procedure GetDeduction(DeductionID: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; PostedDocNo: Code[20]): JsonObject
    var
        JsonBody: JsonObject;
    begin
        exit(SendAPIRequest('GET', GetDeductionURL(DeductionID), 'application/json', JsonBody, MapDocumentType(DocType), DocNo, PostedDocNo));
    end;

    local procedure GetDeductionURL(DeductionID: Text): Text
    begin
        GetAndCheckSetup();
        if DeductionID = '' then
            Error(MissingDeductionIDErr);
        exit(AlvysSetup."Integration URL" + 'deductions/' + DeductionID);
    end;

    /// <summary>
    /// One page of deductions over the range their effective dates fall in. Alvys leaves paid
    /// deductions out unless IncludePaid asks for them. The caller reads Total off the response and
    /// asks for the next page until it has them all.
    /// </summary>
    procedure SearchDeductions(StartDate: Date; EndDate: Date; IncludePaid: Boolean; PageNo: Integer; PageSize: Integer): JsonObject
    var
        ResponseObj: JsonObject;
        ErrorText: Text;
    begin
        if not SearchDeductions(StartDate, EndDate, IncludePaid, PageNo, PageSize, ResponseObj, ErrorText) then
            Error(ErrorText);
        exit(ResponseObj);
    end;

    /// <summary>
    /// The search runs on every poll, so only a failed call is logged. A failure returns false with
    /// the reason in ErrorText, leaving the caller to commit the logged entry before raising.
    /// </summary>
    procedure SearchDeductions(StartDate: Date; EndDate: Date; IncludePaid: Boolean; PageNo: Integer; PageSize: Integer; var ResponseObj: JsonObject; var ErrorText: Text): Boolean
    var
        DateRangeObj, JsonBody : JsonObject;
        URL, RequestBody, ResponseText : Text;
    begin
        GetAndCheckSetup();
        if StartDate = 0D then
            Error(MissingSearchDateErr);
        DateRangeObj.Add('Start', SearchTimestamp(StartDate, StartOfDayTok));
        if EndDate <> 0D then
            DateRangeObj.Add('End', SearchTimestamp(EndDate, EndOfDayTok));
        JsonBody.Add('Page', PageNo);
        JsonBody.Add('PageSize', PageSize);
        JsonBody.Add('IncludePaid', IncludePaid);
        JsonBody.Add('DateRange', DateRangeObj);
        URL := AlvysSetup."Integration URL" + 'deductions/search';
        if SendAndParse('POST', URL, 'application/json', JsonBody, ResponseObj, RequestBody, ResponseText, ErrorText) then
            exit(true);
        InsertEntry(Enum::"BAASI Alvys Entry Doc. Type"::" ", '', URL, 'POST', RequestBody, ResponseText, ErrorText, false, true);
        exit(false);
    end;

    /// <summary>
    /// Alvys returns effective dates at midnight, so an end bound taken at midnight too would drop
    /// the deductions dated that day.
    /// </summary>
    local procedure SearchTimestamp(SearchDate: Date; TimeOfDay: Text): Text
    begin
        exit(Format(SearchDate, 0, '<Year4>-<Month,2>-<Day,2>') + TimeOfDay);
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject; TruckNumber: Text[50]): Text
    begin
        exit(InsertDeduction(ResponseObj, TruckNumber, Enum::"BAASI Alvys Entry Doc. Type"::" ", '', ''));
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject; TruckNumber: Text[50]; DocType: Enum "BAASI Alvys Entry Doc. Type"; DocNo: Code[20]; PostedDocNo: Code[20]): Text
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        InsertDeduction(ResponseObj, TruckNumber, DocType, DocNo, PostedDocNo, AlvysDeduction);
        exit(AlvysDeduction.Id);
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject; TruckNumber: Text[50]; DocType: Enum "BAASI Alvys Entry Doc. Type"; DocNo: Code[20]; PostedDocNo: Code[20]; var AlvysDeduction: Record "BAASI Alvys Deduction")
    var
        AmountObj: JsonObject;
        JsonTkn: JsonToken;
        EntryNo: Integer;
    begin
        AlvysDeduction.LockTable(true);
        if AlvysDeduction.FindLast() then
            EntryNo := AlvysDeduction."Entry No.";
        AlvysDeduction.Init();
        AlvysDeduction."Entry No." := EntryNo + 1;
        AlvysDeduction.Id := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'Id'), 1, MaxStrLen(AlvysDeduction.Id));
        AlvysDeduction.Type := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'Type'), 1, MaxStrLen(AlvysDeduction.Type));
        AlvysDeduction."Group Id" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'GroupId'), 1, MaxStrLen(AlvysDeduction."Group Id"));
        AlvysDeduction.Description := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'Description'), 1, MaxStrLen(AlvysDeduction.Description));
        AlvysDeduction.Category := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'Category'), 1, MaxStrLen(AlvysDeduction.Category));
        if ResponseObj.Get('Amount', JsonTkn) then begin
            AmountObj := JsonTkn.AsObject();
            AlvysDeduction.Amount := JsonMgt.GetJsonValueAsDecimal(AmountObj, 'Amount');
            AlvysDeduction."Currency Id" := JsonMgt.GetJsonValueAsInteger(AmountObj, 'Currency');
        end;
        AlvysDeduction."Truck Id" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'TruckId'), 1, MaxStrLen(AlvysDeduction."Truck Id"));
        AlvysDeduction."Truck Number" := TruckNumber;
        AlvysDeduction."Driver Id" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'DriverId'), 1, MaxStrLen(AlvysDeduction."Driver Id"));
        AlvysDeduction.Date := DT2Date(JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'Date'));
        AlvysDeduction."Is Paid" := JsonMgt.GetJsonValueAsBoolean(ResponseObj, 'IsPaid');
        AlvysDeduction."Remaining Amount" := AlvysDeduction.Amount;
        AlvysDeduction."Alvys Created At" := JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'CreatedAt');
        AlvysDeduction."Alvys Created By" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'CreatedBy'), 1, MaxStrLen(AlvysDeduction."Created By"));
        AlvysDeduction."Document Type" := DocType;
        AlvysDeduction."Document No." := DocNo;
        AlvysDeduction."Posted Document No." := PostedDocNo;
        AlvysDeduction.Insert(true);
    end;

    /// <summary>
    /// Logs one part of a deduction Alvys split, as a deduction in its own right pointing back at
    /// the one it was split from. The part carries the split deduction's document, so it can be
    /// applied to the same posted invoice, and everything else comes from Alvys' own record of it.
    /// </summary>
    internal procedure InsertSplitPart(var SplitDeduction: Record "BAASI Alvys Deduction"; var ItemObj: JsonObject; var SplitPart: Record "BAASI Alvys Deduction")
    begin
        InsertDeduction(ItemObj, SplitDeduction."Truck Number", SplitDeduction."Document Type", SplitDeduction."Document No.", SplitDeduction."Posted Document No.", SplitPart);
        SplitPart."Split From Entry No." := SplitDeduction."Entry No.";
        SplitPart.Modify(true);
    end;

    /// <summary>
    /// Carries what has happened to the parts of a split deduction up to the deduction they were
    /// split from, and on up if that one was itself a part of an earlier split. A split deduction is
    /// not settled itself -- Alvys deleted it -- so what it reports is what its parts report
    /// together: paid once every part is paid, applied once every part is applied, and remaining
    /// whatever its parts have left to apply.
    /// </summary>
    internal procedure UpdateSplitDeduction(SplitPartEntryNo: Integer)
    var
        SplitDeduction, SplitPart, Sibling : Record "BAASI Alvys Deduction";
        RemainingAmount: Decimal;
        AllPaid, AllApplied, AllPosted : Boolean;
    begin
        if not SplitPart.Get(SplitPartEntryNo) then
            exit;
        if SplitPart."Split From Entry No." = 0 then
            exit;
        if not SplitDeduction.Get(SplitPart."Split From Entry No.") then
            exit;

        AllPaid := true;
        AllApplied := true;
        AllPosted := true;
        Sibling.SetRange("Split From Entry No.", SplitDeduction."Entry No.");
        if Sibling.FindSet() then
            repeat
                RemainingAmount += Sibling."Remaining Amount";
                AllPaid := AllPaid and Sibling."Is Paid";
                AllApplied := AllApplied and Sibling."Settlement Applied";
                AllPosted := AllPosted and Sibling."Settlement Posted";
            until Sibling.Next() = 0;

        SplitDeduction."Is Paid" := AllPaid;
        SplitDeduction."Remaining Amount" := RemainingAmount;
        SplitDeduction."Settlement Applied" := AllApplied;
        if AllApplied and (SplitDeduction."Settlement Applied At" = 0DT) then
            SplitDeduction."Settlement Applied At" := CurrentDateTime();
        SplitDeduction."Settlement Posted" := AllPosted;
        if AllPosted and (SplitDeduction."Posted DateTime" = 0DT) then
            SplitDeduction."Posted DateTime" := CurrentDateTime();
        SplitDeduction.Modify(true);

        UpdateSplitDeduction(SplitDeduction."Entry No.");
    end;


    procedure GetTruckDimensionValue(DimSetID: Integer): Text
    var
        DimSetEntry: Record "Dimension Set Entry";
        TruckDimensionCode: Code[20];
    begin
        if DimSetID = 0 then
            exit('');
        GetAndCheckSetup();
        TruckDimensionCode := GetTruckDimensionCode();
        if not DimSetEntry.Get(DimSetID, TruckDimensionCode) then
            Error(MissingTruckDimensionErr, TruckDimensionCode);
        exit(DimSetEntry."Dimension Value Code");
    end;

    procedure GetTruckDimensionCode(): Code[20]
    var
        FleetrockSetup: Record "FRI Fleetrock Setup";
    begin
        FleetrockSetup.Get();
        FleetrockSetup.TestField("Truck Dimension Code");
        exit(FleetrockSetup."Truck Dimension Code");
    end;


    local procedure SendAPIRequest(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject): JsonObject
    var
        Result: Boolean;
    begin
        exit(SendAPIRequest(Method, URL, ContentType, JsonBody, Enum::"BAASI Alvys Entry Doc. Type"::" ", '', '', true, Result));
    end;

    local procedure SendAPIRequest(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject; ThrowError: Boolean; var Result: Boolean): JsonObject
    begin
        exit(SendAPIRequest(Method, URL, ContentType, JsonBody, Enum::"BAASI Alvys Entry Doc. Type"::" ", '', '', ThrowError, Result));
    end;

    local procedure SendAPIRequest(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject; DocType: Enum "BAASI Alvys Entry Doc. Type"; DocNo: Code[20]; PostedDocNo: Code[20]): JsonObject
    var
        Result: Boolean;
    begin
        exit(SendAPIRequest(Method, URL, ContentType, JsonBody, DocType, DocNo, PostedDocNo, true, Result));
    end;

    local procedure SendAPIRequest(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject; DocType: Enum "BAASI Alvys Entry Doc. Type"; DocNo: Code[20]; PostedDocNo: Code[20]; ThrowError: Boolean; var Result: Boolean): JsonObject
    var
        ResponseObj: JsonObject;
        ErrorText, RequestBody, ResponseText : Text;
        Sent: Boolean;
    begin
        Sent := SendAndParse(Method, URL, ContentType, JsonBody, ResponseObj, RequestBody, ResponseText, ErrorText);
        InsertEntry(DocType, EntryDocumentNo(DocNo, PostedDocNo), URL, Method, RequestBody, ResponseText, ErrorText, Sent, true);
        if not Sent and ThrowError then
            Error(ErrorText);
        Result := Sent;
        exit(ResponseObj);
    end;

    /// <summary>
    /// Authenticates and sends the request through the shared REST codeunit. Never raises; the
    /// caller logs the outcome and decides whether to surface ErrorText as an error.
    /// </summary>
    local procedure SendAndParse(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject; var ResponseObj: JsonObject; var RequestBody: Text; var ResponseText: Text; var ErrorText: Text): Boolean
    var
        RequestHeaderValues: Dictionary of [Text, Text];
    begin
        if JsonBody.Keys().Count() > 0 then
            JsonBody.WriteTo(RequestBody);
        PrepareHeaderValues(CheckToGetAccessToken(), RequestHeaderValues);
        exit(RESTAPIMgt.TrySendJsonRequest(Method, URL, ContentType, RequestBody, RequestHeaderValues, ResponseObj, ResponseText, ErrorText));
    end;

    local procedure PrepareHeaderValues(AccessToken: Text; var RequestHeaderValues: Dictionary of [Text, Text])
    begin
        Clear(RequestHeaderValues);
        if AccessToken <> '' then
            RequestHeaderValues.Add('Authorization', StrSubstNo('Bearer %1', AccessToken));
        RequestHeaderValues.Add('Accept', 'application/json');
    end;

    /// <summary>
    /// Translates the sales document type into the type stored on the entry. A non-blank
    /// PostedDocNo means the call came from a posted invoice and outranks DocType. Otherwise only
    /// orders and invoices are logged against a document; anything else has no counterpart in Alvys.
    /// </summary>
    internal procedure MapDocumentType(DocType: Enum "Sales Document Type"): Enum "BAASI Alvys Entry Doc. Type"
    begin
        case DocType of
            DocType::Order:
                exit(Enum::"BAASI Alvys Entry Doc. Type"::"Sales Order");
            DocType::Invoice:
                exit(Enum::"BAASI Alvys Entry Doc. Type"::"Sales Invoice");
        end;
        Error(UnsupportedDocTypeErr, DocType);
    end;

    /// <summary>
    /// The document number stored on the entry: the posted invoice number once one exists,
    /// otherwise the number of the document the call originated from.
    /// </summary>
    local procedure EntryDocumentNo(DocNo: Code[20]; PostedDocNo: Code[20]): Code[20]
    begin
        if PostedDocNo <> '' then
            exit(PostedDocNo);
        exit(DocNo);
    end;



    internal procedure PrepareInboundEntry(var AlvysEntry: Record "BAASI Alvys Sales Entry"; RequestBody: Text)
    var
        LastEntry: Record "BAASI Alvys Sales Entry";
    begin
        LastEntry.LockTable(true);
        if LastEntry.FindLast() then
            AlvysEntry."Entry No." := LastEntry."Entry No." + 1
        else
            AlvysEntry."Entry No." := 1;
        AlvysEntry.Direction := AlvysEntry.Direction::Inbound;
        AlvysEntry.SetRequestBody(RequestBody);
    end;





    // /// <summary>
    // /// Fills in an apply-deduction entry from the payload fields the API page carries. The page
    // /// takes the six driver pay fields only, so everything else on the entry is derived here: the
    // /// document the deduction was raised against, the request body rebuilt from the fields, and the
    // /// method and URL of the endpoint the call arrived on.
    // ///
    // /// A payload that cannot be matched to a posted invoice is still logged, with the reason in the
    // /// error message. The entry table is the audit log of what Alvys sent, so losing the record of
    // /// a call that failed would be the wrong way round.
    // ///
    // /// A payload that does match is written to the configured payment journal as a customer payment
    // /// applied to the invoice, and the batch is posted when the setup asks for it.
    // ///
    // /// Every failure is answered 400, with the reason as the error text.
    // /// </summary>
    // internal procedure PrepareInboundSettlementEntry(var AlvysEntry: Record "BAASI Alvys Sales Entry"; DeductionId: Text; TruckId: Text; TruckNumber: Text; Amount: Decimal; SettlementDate: Date; Description: Text; Method: Text; URL: Text)
    // var
        // AlvysDeduction: Record "BAASI Alvys Deduction";
        // ErrorText: Text;
    // begin
        // if FindOriginalDeduction(AlvysDeduction, DeductionId, ErrorText) then begin
            // ApplyPayloadToDeduction(AlvysDeduction, TruckId, TruckNumber, Amount, Description);
            // PrepareApplyDeductionEntry(AlvysEntry, AlvysDeduction, SettlementDate, Method, URL);
            // exit;
        // end;

        // AlvysEntry.Method := CopyStr(Method, 1, MaxStrLen(AlvysEntry.Method));
        // AlvysEntry.URL := CopyStr(URL, 1, MaxStrLen(AlvysEntry.URL));
        // AlvysEntry."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(AlvysEntry."Error Message"));
        // PrepareInboundEntry(AlvysEntry, ApplyDeductionRequestBody(DeductionId, TruckId, TruckNumber, Amount, SettlementDate, Description));
    // end;

    // /// <summary>
    // /// The settlement is for the deduction Business Central raised when the invoice was posted, so it
    // /// is matched to that record rather than logged as a new one.
    // /// </summary>
    // local procedure FindOriginalDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction"; DeductionId: Text; var ErrorText: Text): Boolean
    // begin
        // if DeductionId = '' then begin
            // ErrorText := ApplyBlankDeductionErr;
            // exit(false);
        // end;
        // AlvysDeduction.SetRange(Id, CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        // if not AlvysDeduction.FindLast() then begin
            // ErrorText := StrSubstNo(NoDeductionFoundErr, DeductionId);
            // exit(false);
        // end;
        // AlvysDeduction.SetRange(Id);
        // exit(true);
    // end;

    // /// <summary>
    // /// Laid over the original in memory only: the checks and the logged body have to reflect what
    // /// Alvys sent, but a refused payload is committed with its entry and must not overwrite the
    // /// deduction. It is written to the record only by the Modify of a settlement that applied.
    // /// </summary>
    // local procedure ApplyPayloadToDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction"; TruckId: Text; TruckNumber: Text; Amount: Decimal; Description: Text)
    // begin
        // AlvysDeduction."Truck Id" := CopyStr(TruckId, 1, MaxStrLen(AlvysDeduction."Truck Id"));
        // AlvysDeduction."Truck Number" := CopyStr(TruckNumber, 1, MaxStrLen(AlvysDeduction."Truck Number"));
        // AlvysDeduction.Amount := Amount;
        // AlvysDeduction.Description := CopyStr(Description, 1, MaxStrLen(AlvysDeduction.Description));
    // end;

    internal procedure PrepareApplyDeductionEntry(var AlvysEntry: Record "BAASI Alvys Sales Entry"; var AlvysDeduction: Record "BAASI Alvys Deduction"; SettlementDate: Date; Method: Text; URL: Text)
    var
        AlvysSalesSetup: Record "BAASI Alvys Sales Setup";
        SalesInvHeader: Record "Sales Invoice Header";
        ErrorText: Text;
    begin
        ErrorText := ApplyDeductionSetupError(AlvysSalesSetup);
        if ErrorText = '' then begin
            if AlvysDeduction."Posted Document No." <> '' then begin
                AlvysEntry.Method := CopyStr(Method, 1, MaxStrLen(AlvysEntry.Method));
                AlvysEntry.URL := CopyStr(AlvysSalesSetup."Integration URL" + URL, 1, MaxStrLen(AlvysEntry.URL));
                AlvysEntry."Document Type" := AlvysEntry."Document Type"::"Posted Sales Invoice";
                AlvysEntry."Document No." := AlvysDeduction."Posted Document No.";
                if not SalesInvHeader.Get(AlvysDeduction."Posted Document No.") then
                    LogMissingInvoiceAndRaise(AlvysEntry, AlvysDeduction, SettlementDate);
                ErrorText := ApplyDeductionInvoiceError(AlvysDeduction);
                if ErrorText = '' then
                    ErrorText := ApplyDeductionPayloadError(AlvysDeduction."Truck Id", AlvysDeduction."Truck Number", AlvysDeduction.Amount, SettlementDate);
                if ErrorText = '' then
                    ErrorText := ApplyDeductionPayment(AlvysDeduction, AlvysSalesSetup, AlvysEntry."Document No.", AlvysDeduction.Amount, SettlementDate);
            end else
                ErrorText := StrSubstNo(MissingPostedDocumentNoErr, AlvysDeduction."Entry No.");
        end;
        if ErrorText <> '' then
            AlvysEntry."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(AlvysEntry."Error Message"));

        PrepareInboundEntry(AlvysEntry, ApplyDeductionRequestBody(AlvysDeduction.Id, AlvysDeduction."Truck Id", AlvysDeduction."Truck Number", AlvysDeduction.Amount, SettlementDate, AlvysDeduction.Description));
        AlvysEntry."Deduction Id" := AlvysDeduction.Id;
    end;

    /// <summary>
    /// The error rolls back everything since the last commit, so the entry is committed first to
    /// survive it.
    /// </summary>
    local procedure LogMissingInvoiceAndRaise(var AlvysEntry: Record "BAASI Alvys Sales Entry"; var AlvysDeduction: Record "BAASI Alvys Deduction"; SettlementDate: Date)
    var
        ErrorText: Text;
    begin
        ErrorText := StrSubstNo(NoSalesInvoiceFoundErr, AlvysDeduction."Posted Document No.", AlvysDeduction.Id);
        AlvysEntry."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(AlvysEntry."Error Message"));
        PrepareInboundEntry(AlvysEntry, ApplyDeductionRequestBody(AlvysDeduction.Id, AlvysDeduction."Truck Id", AlvysDeduction."Truck Number", AlvysDeduction.Amount, SettlementDate, AlvysDeduction.Description));
        AlvysEntry."Deduction Id" := AlvysDeduction.Id;
        InsertSettlementEntry(AlvysEntry);
        Commit();
        Error(ErrorText);
    end;

    /// <summary>
    /// A settlement that keeps failing is retried on every poll, so an error already logged for the
    /// same deduction is not logged again. Returns whether the entry was inserted.
    /// </summary>
    internal procedure InsertSettlementEntry(var AlvysEntry: Record "BAASI Alvys Sales Entry"): Boolean
    var
        LoggedEntry: Record "BAASI Alvys Sales Entry";
    begin
        if AlvysEntry."Error Message" <> '' then begin
            LoggedEntry.SetRange("Deduction Id", AlvysEntry."Deduction Id");
            LoggedEntry.SetRange("Error Message", AlvysEntry."Error Message");
            if not LoggedEntry.IsEmpty() then
                exit(false);
        end;
        AlvysEntry.Insert(true);
        exit(true);
    end;

    /// <summary>
    /// Logs a settlement that was stopped before it could be attempted, by a validation this
    /// codeunit does not raise itself -- one from Business Central or another extension. The
    /// scheduled poll catches those so a single deduction cannot take the rest of the run with it,
    /// and this records what was tried and what stopped it, in the same shape as a settlement that
    /// failed one of the checks above.
    /// </summary>
    internal procedure PrepareFailedSettlementEntry(var AlvysEntry: Record "BAASI Alvys Sales Entry"; var AlvysDeduction: Record "BAASI Alvys Deduction"; SettlementDate: Date; ErrorText: Text; ErrorStack: Text; Method: Text; URL: Text)
    begin
        AlvysEntry.Method := CopyStr(Method, 1, MaxStrLen(AlvysEntry.Method));
        AlvysEntry.URL := CopyStr(URL, 1, MaxStrLen(AlvysEntry.URL));
        AlvysEntry."Document Type" := AlvysEntry."Document Type"::"Posted Sales Invoice";
        AlvysEntry."Document No." := AlvysDeduction."Posted Document No.";
        AlvysEntry."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(AlvysEntry."Error Message"));
        PrepareInboundEntry(AlvysEntry, ApplyDeductionRequestBody(AlvysDeduction.Id, AlvysDeduction."Truck Id", AlvysDeduction."Truck Number", AlvysDeduction.Amount, SettlementDate, AlvysDeduction.Description));
        AlvysEntry."Deduction Id" := AlvysDeduction.Id;
        AlvysEntry.SetErrorStack(ErrorStack);
    end;

    /// <summary>
    /// Checks the posted invoice can still take the settlement. The caller has already made sure the
    /// invoice exists.
    /// </summary>
    local procedure ApplyDeductionInvoiceError(var AlvysDeduction: Record "BAASI Alvys Deduction"): Text
    var
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        SalesInvHeader.Get(AlvysDeduction."Posted Document No.");

        SalesInvHeader.CalcFields(Closed, Cancelled, Reversed);
        if SalesInvHeader.Closed then
            exit(StrSubstNo(SalesInvAlreadyClosedErr, SalesInvHeader."No."));
        if SalesInvHeader.Cancelled or SalesInvHeader.Reversed then
            exit(StrSubstNo(SalesInvCancelledOrReversedErr, SalesInvHeader."No."));

        // Deductions are held negative and the receivable positive.
        SalesInvHeader.CalcFields("Remaining Amount");
        if SalesInvHeader."Remaining Amount" < Abs(AlvysDeduction.Amount) then
            exit(StrSubstNo(SalesInvRemainingAmountErr, SalesInvHeader."No.", SalesInvHeader."Remaining Amount", Abs(AlvysDeduction.Amount)));

        exit('');
    end;

    /// <summary>
    /// Checks the deduction carries what a settlement has to be applied from, and returns the reason
    /// it does not. The truck may be named by either field, so only a deduction naming it by
    /// neither is refused.
    /// </summary>
    local procedure ApplyDeductionPayloadError(TruckId: Text; TruckNumber: Text; Amount: Decimal; SettlementDate: Date): Text
    begin
        if (TruckId = '') and (TruckNumber = '') then
            exit(ApplyMissingTruckErr);

        // A settlement clears a deduction, and deductions are held negative, so the amount that
        // applies one is negative too; zero would apply nothing.
        if Amount >= 0 then
            exit(StrSubstNo(ApplyInvalidAmountErr, Amount));

        if SettlementDate = 0D then
            exit(ApplyMissingSettlementDateErr);

        exit('');
    end;

    /// <summary>
    /// Checks the setup names the journal a settlement is written to and the account its payment
    /// side is posted to, and hands the setup back to whoever passed the check. The reason is
    /// returned rather than raised: a settlement is logged whatever stopped it, and a TestField here
    /// would roll the entry back along with the reason it carries.
    /// </summary>
    local procedure ApplyDeductionSetupError(var AlvysSalesSetup: Record "BAASI Alvys Sales Setup"): Text
    begin
        if not AlvysSalesSetup.Get() then
            exit(ApplySetupMissingErr);

        if AlvysSalesSetup."Payment Journal Template" = '' then
            exit(StrSubstNo(ApplySetupFieldBlankErr, AlvysSalesSetup.FieldCaption("Payment Journal Template")));

        if AlvysSalesSetup."Payment Journal Batch" = '' then
            exit(StrSubstNo(ApplySetupFieldBlankErr, AlvysSalesSetup.FieldCaption("Payment Journal Batch")));

        if AlvysSalesSetup."Bal. Account No." = '' then
            exit(StrSubstNo(ApplySetupFieldBlankErr, AlvysSalesSetup.FieldCaption("Bal. Account No.")));

        exit('');
    end;

    /// <summary>
    /// Writes the settlement to the configured payment journal and posts the batch when the setup
    /// asks for it. Returns the reason posting failed, or a blank text when there is nothing to
    /// report.
    ///
    /// A batch that will not post is caught rather than raised. The line is already written, so the
    /// settlement is not lost by the failure — it is left in the journal for someone to correct and
    /// post by hand, and the reason goes to the entry log.
    /// </summary>
    local procedure ApplyDeductionPayment(var AlvysDeduction: Record "BAASI Alvys Deduction"; var AlvysSalesSetup: Record "BAASI Alvys Sales Setup"; DocumentNo: Code[20]; Amount: Decimal; SettlementDate: Date): Text
    var
        GenJnlLine: Record "Gen. Journal Line";
    begin
        InsertPaymentJournalLine(GenJnlLine, AlvysSalesSetup, DocumentNo, Amount, SettlementDate, AlvysDeduction."Id");
        AlvysDeduction.Validate("Settlement Applied", true);
        AlvysDeduction.Validate("Settlement Applied At", CurrentDateTime());
        AlvysDeduction.Validate("Remaining Amount", 0);
        AlvysDeduction.Modify(true);
        UpdateSplitDeduction(AlvysDeduction."Entry No.");
        if not AlvysSalesSetup."Auto-Post Deductions" then
            exit('');

        // Codeunit.Run rolls its own work back when it fails, and the line written above is inside
        // that transaction, so it is committed first. Posting is the last thing this call does, so
        // the commit hands nothing else over early.
        ClearLastError();
        Commit();
        if not Codeunit.Run(Codeunit::"Gen. Jnl.-Post Batch", GenJnlLine) then
            exit(StrSubstNo(ApplyPostingFailedErr, AlvysSalesSetup."Payment Journal Template", AlvysSalesSetup."Payment Journal Batch", GetLastErrorText()));
        exit('');
    end;

    internal procedure MarkSettlementPosted(DeductionId: Text)
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        AlvysDeduction.SetRange(Id, CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        if AlvysDeduction.FindSet(true) then
            repeat
                AlvysDeduction.Validate("Settlement Posted", true);
                AlvysDeduction.Validate("Posted DateTime", CurrentDateTime());
                AlvysDeduction.Modify(true);
                UpdateSplitDeduction(AlvysDeduction."Entry No.");
            until AlvysDeduction.Next() = 0;
    end;

    /// <summary>
    /// Builds the payment that clears the settled deduction: a customer line on the bill-to customer
    /// of the invoice, balanced against the configured G/L account and applied to the invoice.
    ///
    /// The settlement arrives negative, and the line carries it through unchanged. A customer line
    /// credits the customer when its amount is negative, which is what pays the receivable down; a
    /// cash receipts template refuses a positive one outright.
    ///
    /// The line is set up the way the payment journal page sets one up by hand, so it takes the
    /// batch's defaults and its document number from the batch's number series.
    ///
    /// It also takes the invoice's dimensions rather than the customer's. The settlement belongs to
    /// the entity and the tractor the invoice was raised under, and the balancing account carries a
    /// mandatory entity dimension the customer's own defaults do not supply, so a line dimensioned
    /// from the customer will not post at all.
    /// </summary>
    local procedure InsertPaymentJournalLine(var GenJnlLine: Record "Gen. Journal Line"; var AlvysSalesSetup: Record "BAASI Alvys Sales Setup"; SalesInvHdrNo: Code[20]; SettlementAmount: Decimal; SettlementDate: Date; AlvysDeductionId: Text[50])
    var
        SalesInvHeader: Record "Sales Invoice Header";
        LastGenJnlLine: Record "Gen. Journal Line";
        LineNo, OldLineNo : Integer;
    begin
        SalesInvHeader.Get(SalesInvHdrNo);

        GenJnlLine.Reset();
        GenJnlLine.SetRange("BAASI Alvys Deduction Id", AlvysDeductionId);
        if not GenJnlLine.FindFirst() then begin
            LastGenJnlLine.SetRange("Journal Template Name", AlvysSalesSetup."Payment Journal Template");
            LastGenJnlLine.SetRange("Journal Batch Name", AlvysSalesSetup."Payment Journal Batch");
            if LastGenJnlLine.FindLast() then
                LineNo := LastGenJnlLine."Line No." + 10000
            else
                LineNo := 10000;

            GenJnlLine.Init();
            GenJnlLine.Validate("Journal Template Name", AlvysSalesSetup."Payment Journal Template");
            GenJnlLine.Validate("Journal Batch Name", AlvysSalesSetup."Payment Journal Batch");
            GenJnlLine."Line No." := LineNo;
            GenJnlLine.SetUpNewLine(LastGenJnlLine, 0, true);

            OldLineNo := LineNo;
            // Required due to the SetUpNewLine() reset the LineNo. to something that might not be valid
            GenJnlLine."Line No." := NextPaymentJournalLineNo(AlvysSalesSetup, LineNo);
            GenJnlLine.Validate("BAASI Alvys Deduction Id", AlvysDeductionId);
            GenJnlLine.Insert(true);

            // Remove second that is being incorrectly inserted in the above process
            if GenJnlLine."Line No." <> OldLineNo then begin
                LineNo := GenJnlLine."Line No.";
                if GenJnlLine.Get(AlvysSalesSetup."Payment Journal Template", AlvysSalesSetup."Payment Journal Batch", OldLineNo) then
                    GenJnlLine.Delete(true);
                GenJnlLine.Get(AlvysSalesSetup."Payment Journal Template", AlvysSalesSetup."Payment Journal Batch", LineNo);
            end
        end;
        GenJnlLine.Validate("Posting Date", SettlementDate);
        GenJnlLine.Validate("Document Type", GenJnlLine."Document Type"::Payment);
        GenJnlLine.Validate("Account Type", GenJnlLine."Account Type"::Customer);
        GenJnlLine.Validate("Account No.", SalesInvHeader."Bill-to Customer No.");
        GenJnlLine.Validate("Bal. Account Type", GenJnlLine."Bal. Account Type"::"G/L Account");
        GenJnlLine.Validate("Bal. Account No.", AlvysSalesSetup."Bal. Account No.");
        GenJnlLine.Validate(Amount, SettlementAmount);
        // After the accounts, which rebuild the dimension set from their own defaults, but before
        // the Applies-to fields: Multi-Entity Management subscribes to their validation and reads
        // the entity off the line, so by then the line has to carry the invoice's entity rather
        // than the batch's default, or a decentralized receivable refuses the application.
        //
        // Entity is this company's global dimension 1, and posting reads a global dimension off the
        // line's shortcut field rather than out of the dimension set. Setting the set alone leaves
        // that field blank and the balancing account refuses the line for a missing entity, so the
        // shortcuts are brought along too. Gen. Journal Line does not do this on validate the way
        // some other tables do.
        GenJnlLine.Validate("Dimension Set ID", SalesInvHeader."Dimension Set ID");
        GenJnlLine.Validate("Applies-to Doc. Type", GenJnlLine."Applies-to Doc. Type"::Invoice);
        GenJnlLine.Validate("Applies-to Doc. No.", SalesInvHeader."No.");

        OnBeforeGenJnlLineModify(GenJnlLine);

        // // Set the BssiEntityID field so that the line ends up in the correct Entity journal batch
        // if GenJnlLine."Shortcut Dimension 1 Code" <> '' then begin
        //     RecRef.GetTable(GenJnlLine);
        //     // BssiEntityID field ID
        //     if RecRef.FieldExist(70210826) then begin
        //         RecRef.Field(70210826).Validate(GenJnlLine."Shortcut Dimension 1 Code");
        //         RecRef.SetTable(GenJnlLine);
        //     end;
        // end;

        GenJnlLine.Modify(true);
    end;

    local procedure NextPaymentJournalLineNo(AlvysSalesSetup: Record "BAASI Alvys Sales Setup"; ReservedLineNo: Integer): Integer
    var
        GenJnlLine: Record "Gen. Journal Line";
    begin
        GenJnlLine.SetRange("Journal Template Name", AlvysSalesSetup."Payment Journal Template");
        GenJnlLine.SetRange("Journal Batch Name", AlvysSalesSetup."Payment Journal Batch");
        GenJnlLine.SetFilter("Line No.", '>=%1', ReservedLineNo);
        if GenJnlLine.FindLast() then
            exit(GenJnlLine."Line No." + 10000);
        exit(ReservedLineNo);
    end;

    /// <summary>
    /// The settlement as logged on the entry, keyed by Alvys' own field names. Blank truck fields and
    /// a blank description are left out rather than written empty.
    /// </summary>
    local procedure ApplyDeductionRequestBody(DeductionId: Text; TruckId: Text; TruckNumber: Text; Amount: Decimal; SettlementDate: Date; Description: Text): Text
    var
        JsonBody: JsonObject;
        RequestBody: Text;
    begin
        JsonBody.Add('DeductionId', DeductionId);
        if TruckId <> '' then
            JsonBody.Add('TruckId', TruckId);
        if TruckNumber <> '' then
            JsonBody.Add('TruckNumber', TruckNumber);
        JsonBody.Add('Amount', Amount);
        JsonBody.Add('SettlementDate', SettlementDate);
        if Description <> '' then
            JsonBody.Add('Description', Description);
        JsonBody.WriteTo(RequestBody);
        exit(RequestBody);
    end;

    local procedure InsertEntry(DocType: Enum "BAASI Alvys Entry Doc. Type"; DocNo: Code[20]; URL: Text; Method: Text; RequestBody: Text; ResponseText: Text; ErrorText: Text; Success: Boolean; LogResponse: Boolean)
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        GLEntry: Record "G/L Entry";
        EntryNo: Integer;
    begin
        AlvysEntry.LockTable(true);
        if AlvysEntry.FindLast() then
            EntryNo := AlvysEntry."Entry No.";
        AlvysEntry.Init();
        AlvysEntry."Entry No." := EntryNo + 1;
        AlvysEntry.Direction := AlvysEntry.Direction::Outbound;
        AlvysEntry."Document Type" := DocType;
        AlvysEntry."Document No." := DocNo;
        AlvysEntry.URL := CopyStr(URL, 1, MaxStrLen(AlvysEntry.URL));
        AlvysEntry.Method := CopyStr(Method, 1, MaxStrLen(AlvysEntry.Method));
        AlvysEntry."Deduction Id" := CopyStr(DeductionIdFromURL(URL), 1, MaxStrLen(AlvysEntry."Deduction Id"));
        if AlvysEntry."Deduction Id" <> '' then
            SetDocumentFromDeduction(AlvysEntry);
        AlvysEntry.SetRequestBody(RequestBody);
        if LogResponse then
            AlvysEntry.Response := CopyStr(ResponseText, 1, MaxStrLen(AlvysEntry.Response));
        if not Success then begin
            AlvysEntry."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(AlvysEntry."Error Message"));
            AlvysEntry.SetErrorStack(GetLastErrorCallStack());
        end;
        AlvysEntry.Insert(true);
    end;





    /// <summary>
    /// The deduction Id out of a URL that names one, the way deductions/{id} does for a GET or a
    /// DELETE. Anything else in that position -- deductions/search, deductions/once -- is not an Id,
    /// so the segment is taken only when it parses as a GUID.
    /// </summary>
    local procedure DeductionIdFromURL(URL: Text): Text
    var
        DeductionGuid: Guid;
        Candidate: Text;
        Position: Integer;
    begin
        Position := URL.ToLower().IndexOf(DeductionsPathTok);
        if Position = 0 then
            exit('');
        Candidate := URL.Substring(Position + StrLen(DeductionsPathTok));
        Candidate := StopAt(Candidate, '/');
        Candidate := StopAt(Candidate, '?');
        Candidate := StopAt(Candidate, '#');
        if Evaluate(DeductionGuid, Candidate) then
            exit(Candidate);
    end;

    local procedure StopAt(Value: Text; Separator: Text): Text
    var
        Position: Integer;
    begin
        Position := Value.IndexOf(Separator);
        if Position = 0 then
            exit(Value);
        exit(CopyStr(Value, 1, Position - 1));
    end;

    /// <summary>
    /// Names the document behind a deduction on an entry whose caller could not: a call made about a
    /// deduction Id alone, such as reading or deleting it, knows nothing of the invoice it came from.
    /// The logged deduction is what links the two. A caller that named a document itself is left
    /// alone, the posted invoice is preferred over the document it posted from, and a document that
    /// no longer exists is not named.
    /// </summary>
    local procedure SetDocumentFromDeduction(var AlvysEntry: Record "BAASI Alvys Sales Entry")
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        SalesHeader: Record "Sales Header";
        SalesInvHeader: Record "Sales Invoice Header";
        SalesDocType: Enum "Sales Document Type";
    begin
        if (AlvysEntry."Document Type" <> AlvysEntry."Document Type"::" ") or (AlvysEntry."Document No." <> '') then
            exit;
        AlvysDeduction.SetFilter(Id, '@' + AlvysEntry."Deduction Id");
        if not AlvysDeduction.FindSet() then
            exit;
        repeat
            if SalesInvHeader.Get(AlvysDeduction."Posted Document No.") then begin
                AlvysEntry."Document Type" := AlvysEntry."Document Type"::"Posted Sales Invoice";
                AlvysEntry."Document No." := SalesInvHeader."No.";
                exit;
            end;
            if SalesDocumentType(AlvysDeduction."Document Type", SalesDocType) then
                if SalesHeader.Get(SalesDocType, AlvysDeduction."Document No.") then begin
                    AlvysEntry."Document Type" := AlvysDeduction."Document Type";
                    AlvysEntry."Document No." := SalesHeader."No.";
                    exit;
                end;
        until AlvysDeduction.Next() = 0;
    end;

    local procedure SalesDocumentType(DocType: Enum "BAASI Alvys Entry Doc. Type"; var SalesDocType: Enum "Sales Document Type"): Boolean
    begin
        case DocType of
            DocType::"Sales Order":
                SalesDocType := SalesDocType::Order;
            DocType::"Sales Invoice":
                SalesDocType := SalesDocType::Invoice;
            else
                exit(false);
        end;
        exit(true);
    end;


    [BusinessEvent(false, false)]
    local procedure OnBeforeGenJnlLineModify(var GenJnlLine: Record "Gen. Journal Line")
    begin
    end;






    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        RESTAPIMgt: Codeunit "BAAPI REST API Mgt.";
        LoadedSetup: Boolean;


        TokenMissingErr: Label 'access_token not found in response:\%1', Comment = '%1 = Response Text';
        NoTruckFoundErr: Label 'No Alvys truck was found with truck number %1.', Comment = '%1 = Truck Number';
        MissingTruckNumberErr: Label 'The truck number cannot be blank.';
        TruckIdTok: Label 'TruckId', Locked = true;
        DeductionsPathTok: Label 'deductions/', Locked = true;
        DriverIdTok: Label 'DriverId', Locked = true;
        TrucksPathTok: Label 'trucks', Locked = true;
        DriversPathTok: Label 'drivers', Locked = true;
        UnexpectedListResponseErr: Label 'Alvys did not return a list of %1:\%2', Comment = '%1 = trucks or drivers, %2 = Response Text';
        MissingAssetIDErr: Label 'The %1 cannot be blank when creating a deduction.', Comment = '%1 = TruckId or DriverId';
        MissingDeductionIDErr: Label 'The deduction Id cannot be blank.';
        MissingSearchDateErr: Label 'A deduction search needs a date to start from.';
        StartOfDayTok: Label 'T00:00:00Z', Locked = true;
        EndOfDayTok: Label 'T23:59:59Z', Locked = true;
        ApplyBlankDeductionErr: Label 'The payload has no deduction Id, so there is nothing to match it to a posted invoice.';
        ApplyMissingTruckErr: Label 'The payload names no truck: the truck Id and the truck number are both blank.';
        ApplyInvalidAmountErr: Label 'The payload has an amount of %1. A settlement has to apply an amount less than zero.', Comment = '%1 = Amount';
        ApplyMissingSettlementDateErr: Label 'The payload has no settlement date.';
        ApplySetupMissingErr: Label 'The Alvys Sales Setup has not been filled in, so the settlement has no journal to be written to.';
        ApplySetupFieldBlankErr: Label 'The Alvys Sales Setup has no %1, so the settlement has no journal to be written to.', Comment = '%1 = the blank setup field''s caption';
        ApplyPostingFailedErr: Label 'The settlement was written to journal batch %1 %2, but the batch could not be posted: %3', Comment = '%1 = Payment Journal Template, %2 = Payment Journal Batch, %3 = the posting error';
        NoDeductionFoundErr: Label 'No Alvys deduction was found with Id %1.', Comment = '%1 = Deduction Id';
        MissingTruckDimensionErr: Label 'The document does not have a value for the %1 dimension.', Comment = '%1 = Truck Dimension Code';
        UnsupportedDocTypeErr: Label 'Sales documents of type %1 are not supported. Only orders and invoices can be sent to Alvys.', Comment = '%1 = Sales Document Type';
        NoSalesInvoiceFoundErr: Label 'Posted sales invoice %1, recorded on deduction %2, no longer exists.', Comment = '%1 = Posted Sales Invoice No., %2 = Deduction Id';
        MissingPostedDocumentNoErr: Label 'Deduction %1 must have a Posted Document No. specified before it can be applied.', Comment = '%1 = Deduction Entry No.';
        SalesInvAlreadyClosedErr: Label 'Sales Invoice %1 has already been closed.', Comment = '%1 = Sales Invoice No.';
        SalesInvCancelledOrReversedErr: Label 'Sales Invoice %1 has already been cancelled or reversed.', Comment = '%1 = Sales Invoice No.';
        SalesInvRemainingAmountErr: Label 'Sales Invoice %1''s remaining amount of %2 is less than the deduction amount of %3.', Comment = '%1 = Sales Invoice No., %2 = Remaining Amount, %3 = Deduction Amount';
}
