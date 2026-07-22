codeunit 80800 "BAASI Alvys Sales Mgt."
{
    Permissions = tabledata "BAASI Alvys Sales Setup" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RIMD,
        tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "Dimension Set Entry" = R;


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
        JsonBody.Add('audience', AudienceLbl);
        JsonBody.Add('grant_type', 'client_credentials');
        JsonBody.WriteTo(RequestBody);
        // the token request is not logged, as the request body contains the client secret
        // and the response contains the access token
        PrepareHeaderValues('', RequestHeaderValues);
        Sent := RESTAPIMgt.TrySendJsonRequest('POST', TokenURLLbl, 'application/json', RequestBody, RequestHeaderValues, ResponseObj, ResponseText, ErrorText);
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
        TruckNumber := CopyStr(GetTractorCodeDimensionValue(SalesInvHeader."Dimension Set ID"), 1, MaxStrLen(AlvysDeduction."Truck Number"));
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

    local procedure InsertDeduction(var ResponseObj: JsonObject; TruckNumber: Text[50]): Text
    begin
        exit(InsertDeduction(ResponseObj, TruckNumber, Enum::"BAASI Alvys Entry Doc. Type"::" ", '', ''));
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject; TruckNumber: Text[50]; DocType: Enum "BAASI Alvys Entry Doc. Type"; DocNo: Code[20]; PostedDocNo: Code[20]): Text
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
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
        AlvysDeduction."Alvys Created At" := JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'CreatedAt');
        AlvysDeduction."Alvys Created By" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'CreatedBy'), 1, MaxStrLen(AlvysDeduction."Created By"));
        AlvysDeduction."Document Type" := DocType;
        AlvysDeduction."Document No." := DocNo;
        AlvysDeduction."Posted Document No." := PostedDocNo;
        AlvysDeduction.Insert(true);
        exit(AlvysDeduction.Id);
    end;


    procedure GetTractorCodeDimensionValue(DimSetID: Integer): Text
    var
        DimSetEntry: Record "Dimension Set Entry";
    begin
        if DimSetID = 0 then
            exit('');
        GetAndCheckSetup();
        AlvysSetup.TestField("Tractor Code Dimension");
        if not DimSetEntry.Get(DimSetID, AlvysSetup."Tractor Code Dimension") then
            Error(MissingTractorCodeErr, AlvysSetup."Tractor Code Dimension");
        exit(DimSetEntry."Dimension Value Code");
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
            RequestHeaderValues.Add('Authorization', StrSubstNo(BearerTok, AccessToken));
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

    /// <summary>
    /// Logs a call that is not tied to a sales document. Such calls are recorded against the
    /// blank document type, so the Document No. on the entry stays blank.
    /// </summary>
    local procedure InsertEntry(URL: Text; Method: Text; RequestBody: Text; ResponseText: Text; ErrorText: Text; Success: Boolean; LogResponse: Boolean)
    begin
        InsertEntry(Enum::"BAASI Alvys Entry Doc. Type"::" ", '', URL, Method, RequestBody, ResponseText, ErrorText, Success, LogResponse);
    end;

    /// <summary>
    /// Fills in the parts of an inbound entry the caller cannot supply: Alvys posts the payload to
    /// the API page, so it has no way to number the entry or to mark which way the call went.
    /// Called from the page's insert trigger, before the record reaches the table.
    /// </summary>
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
        AlvysEntry.SetRequestBody(RequestBody);
        if LogResponse then
            AlvysEntry.Response := CopyStr(ResponseText, 1, MaxStrLen(AlvysEntry.Response));
        if not Success then begin
            AlvysEntry."Error Message" := CopyStr(ErrorText, 1, MaxStrLen(AlvysEntry."Error Message"));
            AlvysEntry.SetErrorStack(GetLastErrorCallStack());
        end;
        AlvysEntry.Insert(true);
    end;






    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        RESTAPIMgt: Codeunit "BAAPI REST API Mgt.";
        LoadedSetup: Boolean;
        BearerTok: Label 'Bearer %1', Locked = true, Comment = '%1 = Access Token';
        TokenURLLbl: Label 'https://auth.alvys.com/oauth/token', Locked = true;
        AudienceLbl: Label 'https://api.alvys.com/public/', Locked = true;
        TokenMissingErr: Label 'access_token not found in response:\%1', Comment = '%1 = Response Text';
        NoTruckFoundErr: Label 'No Alvys truck was found with truck number %1.', Comment = '%1 = Truck Number';
        MissingTruckNumberErr: Label 'The truck number cannot be blank.';
        TruckIdTok: Label 'TruckId', Locked = true;
        DriverIdTok: Label 'DriverId', Locked = true;
        MissingAssetIDErr: Label 'The %1 cannot be blank when creating a deduction.', Comment = '%1 = TruckId or DriverId';
        MissingDeductionIDErr: Label 'The deduction Id cannot be blank.';
        MissingTractorCodeErr: Label 'The document does not have a value for the %1 dimension.', Comment = '%1 = Tractor Code Dimension';
        UnsupportedDocTypeErr: Label 'Sales documents of type %1 are not supported. Only orders and invoices can be sent to Alvys.', Comment = '%1 = Sales Document Type';
}
