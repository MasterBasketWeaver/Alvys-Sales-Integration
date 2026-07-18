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
        AccessToken, ErrorText, RequestBody, ResponseText : Text;
        Sent: Boolean;
    begin
        AlvysSalesSetup.TestField("Client ID");
        AlvysSalesSetup.TestField("Client Secret");
        SendTime := CurrentDateTime();
        JsonBody.Add('client_id', AlvysSalesSetup."Client ID");
        JsonBody.Add('client_secret', AlvysSalesSetup."Client Secret");
        JsonBody.Add('audience', AudienceLbl);
        JsonBody.Add('grant_type', 'client_credentials');
        JsonBody.WriteTo(RequestBody);
        // the token request is not logged, as the request body contains the client secret
        // and the response contains the access token
        Sent := SendHttpRequest('POST', TokenURLLbl, 'application/json', '', RequestBody, ResponseObj, ResponseText, ErrorText);
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

    procedure GetTruckID(TruckNumber: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareTruckSearchBody(TruckNumber, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'trucks/search', 'application/json', JsonBody, DocType, DocNo);
        exit(ExtractTruckID(ResponseObj, TruckNumber));
    end;

    local procedure PrepareTruckSearchBody(TruckNumber: Text; var JsonBody: JsonObject)
    begin
        GetAndCheckSetup();
        if TruckNumber = '' then
            Error(MissingTruckNumberErr);
        JsonBody.Add('Page', 1);
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


    procedure CreateDeductionForTruck(TruckID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text): Text
    begin
        exit(CreateDeductionForAsset(TruckIdTok, TruckID, Date, Amount, Category, Description));
    end;

    procedure CreateDeductionForTruck(var SalesHeader: Record "Sales Header"; Date: Date; Amount: Decimal; Category: Text; Description: Text)
    var
        TruckID: Text;
    begin
        TruckID := GetTruckID(GetTractorCodeDimensionValue(SalesHeader."Dimension Set ID"), SalesHeader."Document Type", SalesHeader."No.");
        CreateDeductionForTruck(TruckID, Date, Amount, Category, Description, SalesHeader."Document Type", SalesHeader."No.", false);
    end;

    procedure CreateDeductionForTruck(var SalesInvHeader: Record "Sales Invoice Header"; Date: Date; Amount: Decimal; Category: Text; Description: Text)
    var
        TruckID: Text;
    begin
        TruckID := GetTruckID(GetTractorCodeDimensionValue(SalesInvHeader."Dimension Set ID"), Enum::"Sales Document Type"::Invoice, SalesInvHeader."No.");
        CreateDeductionForTruck(TruckID, Date, Amount, Category, Description, Enum::"Sales Document Type"::Invoice, SalesInvHeader."No.", true);
    end;

    procedure CreateDeductionForTruck(TruckID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; Posted: Boolean): Text
    begin
        exit(CreateDeductionForAsset(TruckIdTok, TruckID, Date, Amount, Category, Description, DocType, DocNo, Posted));
    end;

    procedure CreateDeductionForDriver(DriverID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text): Text
    begin
        exit(CreateDeductionForAsset(DriverIdTok, DriverID, Date, Amount, Category, Description));
    end;

    procedure CreateDeductionForDriver(DriverID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; Posted: Boolean): Text
    begin
        exit(CreateDeductionForAsset(DriverIdTok, DriverID, Date, Amount, Category, Description, DocType, DocNo, Posted));
    end;

    /// <summary>
    /// Shared create-deduction core. Alvys treats DriverId and TruckId as mutually exclusive, so
    /// exactly one of them is written to the body, named by AssetIdFieldName. Returns the Id of the
    /// deduction Alvys created.
    /// </summary>
    local procedure CreateDeductionForAsset(AssetIdFieldName: Text; AssetID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareDeductionBody(AssetIdFieldName, AssetID, Date, Amount, Category, Description, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'deductions/once', 'application/json', JsonBody);
        exit(InsertDeduction(ResponseObj));
    end;

    local procedure CreateDeductionForAsset(AssetIdFieldName: Text; AssetID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; Posted: Boolean): Text
    var
        JsonBody, ResponseObj : JsonObject;
    begin
        PrepareDeductionBody(AssetIdFieldName, AssetID, Date, Amount, Category, Description, JsonBody);
        ResponseObj := SendAPIRequest('POST', AlvysSetup."Integration URL" + 'deductions/once', 'application/json', JsonBody, DocType, DocNo);
        exit(InsertDeduction(ResponseObj, DocType, DocNo, Posted));
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


    /// <summary>
    /// Reads a single deduction back from Alvys by its Id. The response is returned as-is rather
    /// than inserted, so that re-reading a deduction does not duplicate the logged entry.
    /// </summary>
    procedure GetDeduction(DeductionID: Text): JsonObject
    var
        JsonBody: JsonObject;
    begin
        exit(SendAPIRequest('GET', GetDeductionURL(DeductionID), 'application/json', JsonBody));
    end;

    procedure GetDeduction(DeductionID: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]): JsonObject
    var
        JsonBody: JsonObject;
    begin
        exit(SendAPIRequest('GET', GetDeductionURL(DeductionID), 'application/json', JsonBody, DocType, DocNo));
    end;

    local procedure GetDeductionURL(DeductionID: Text): Text
    begin
        GetAndCheckSetup();
        if DeductionID = '' then
            Error(MissingDeductionIDErr);
        exit(AlvysSetup."Integration URL" + 'deductions/' + DeductionID);
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject): Text
    begin
        exit(InsertDeduction(ResponseObj, NoDocumentType(), '', false));
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject; DocType: Enum "Sales Document Type"; DocNo: Code[20]; Posted: Boolean): Text
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
            AlvysDeduction."Currency Code" := JsonMgt.GetJsonValueAsInteger(AmountObj, 'Currency');
        end;
        AlvysDeduction."Truck Id" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'TruckId'), 1, MaxStrLen(AlvysDeduction."Truck Id"));
        AlvysDeduction."Driver Id" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'DriverId'), 1, MaxStrLen(AlvysDeduction."Driver Id"));
        AlvysDeduction.Date := DT2Date(JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'Date'));
        AlvysDeduction."Is Paid" := JsonMgt.GetJsonValueAsBoolean(ResponseObj, 'IsPaid');
        AlvysDeduction."Created At" := JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'CreatedAt');
        AlvysDeduction."Created By" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'CreatedBy'), 1, MaxStrLen(AlvysDeduction."Created By"));
        AlvysDeduction."Document Type" := DocType;
        AlvysDeduction."Document No." := DocNo;
        AlvysDeduction.Posted := Posted;
        AlvysDeduction.Insert(true);
        exit(AlvysDeduction.Id);
    end;


    procedure GetTractorCodeDimensionValue(DimSetID: Integer): Text
    var
        DimSetEntry: Record "Dimension Set Entry";
    begin
        GetAndCheckSetup();
        AlvysSetup.TestField("Tractor Code Dimension");
        DimSetEntry.SetRange("Dimension Set ID", DimSetID);
        DimSetEntry.SetRange("Dimension Code", AlvysSetup."Tractor Code Dimension");
        if not DimSetEntry.FindFirst() then
            Error(MissingTractorCodeErr, AlvysSetup."Tractor Code Dimension");
        exit(DimSetEntry."Dimension Value Code");
    end;


    local procedure SendAPIRequest(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject): JsonObject
    var
        ResponseObj: JsonObject;
        ErrorText, RequestBody, ResponseText : Text;
        Sent: Boolean;
    begin
        Sent := SendAndParse(Method, URL, ContentType, JsonBody, ResponseObj, RequestBody, ResponseText, ErrorText);
        InsertEntry(URL, Method, RequestBody, ResponseText, ErrorText, Sent, true);
        if not Sent then
            Error(ErrorText);
        exit(ResponseObj);
    end;

    local procedure SendAPIRequest(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject; DocType: Enum "Sales Document Type"; DocNo: Code[20]): JsonObject
    var
        ResponseObj: JsonObject;
        ErrorText, RequestBody, ResponseText : Text;
        Sent: Boolean;
    begin
        Sent := SendAndParse(Method, URL, ContentType, JsonBody, ResponseObj, RequestBody, ResponseText, ErrorText);
        InsertEntry(DocType, DocNo, URL, Method, RequestBody, ResponseText, ErrorText, Sent, true);
        if not Sent then
            Error(ErrorText);
        exit(ResponseObj);
    end;

    /// <summary>
    /// Authenticates and sends the request. Never raises; the caller logs the outcome and decides
    /// whether to surface ErrorText as an error.
    /// </summary>
    local procedure SendAndParse(Method: Text; URL: Text; ContentType: Text; var JsonBody: JsonObject; var ResponseObj: JsonObject; var RequestBody: Text; var ResponseText: Text; var ErrorText: Text): Boolean
    begin
        if JsonBody.Keys().Count() > 0 then
            JsonBody.WriteTo(RequestBody);
        exit(SendHttpRequest(Method, URL, ContentType, CheckToGetAccessToken(), RequestBody, ResponseObj, ResponseText, ErrorText));
    end;

    /// <summary>
    /// Builds and sends the request directly rather than going through the shared REST codeunit.
    /// That codeunit stages headers on caller-supplied HttpHeaders and copies them across with
    /// GetValues/Get(1), but two staged HttpHeaders share one value pool, so Content-Type gets
    /// handed the Authorization value and BC rejects the request. Setting the headers straight on
    /// the request message and its content avoids the staging step entirely.
    /// Never raises; failures are reported through ErrorText.
    /// </summary>
    local procedure SendHttpRequest(Method: Text; URL: Text; ContentType: Text; AccessToken: Text; RequestBody: Text; var ResponseObj: JsonObject; var ResponseText: Text; var ErrorText: Text): Boolean
    var
        Client: HttpClient;
        Content: HttpContent;
        RequestMsg: HttpRequestMessage;
        ResponseMsg: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        RequestHeaders: HttpHeaders;
    begin
        Clear(ResponseObj);
        ErrorText := '';
        ResponseText := '';
        RequestMsg.SetRequestUri(URL);
        RequestMsg.Method(Method);
        RequestMsg.GetHeaders(RequestHeaders);
        if AccessToken <> '' then
            RequestHeaders.Add('Authorization', StrSubstNo(BearerTok, AccessToken));
        RequestHeaders.Add('Accept', 'application/json');
        if RequestBody <> '' then begin
            Content.WriteFrom(RequestBody);
            // content headers must be set before the content is assigned: assigning copies it
            Content.GetHeaders(ContentHeaders);
            if ContentHeaders.Contains('Content-Type') then
                ContentHeaders.Remove('Content-Type');
            ContentHeaders.Add('Content-Type', ContentType);
            RequestMsg.Content(Content);
        end;
        if not Client.Send(RequestMsg, ResponseMsg) then begin
            ErrorText := StrSubstNo(UnableToSendErr, GetLastErrorText());
            exit(false);
        end;
        ResponseMsg.Content().ReadAs(ResponseText);
        if not ResponseMsg.IsSuccessStatusCode() then begin
            if ResponseText = '' then
                ResponseText := StrSubstNo('%1 - %2', ResponseMsg.HttpStatusCode(), ResponseMsg.ReasonPhrase());
            ErrorText := ResponseText;
            exit(false);
        end;
        if not ResponseObj.ReadFrom(ResponseText) then begin
            ErrorText := StrSubstNo(UnableToReadErr, ResponseText);
            exit(false);
        end;
        exit(true);
    end;

    /// <summary>
    /// The placeholder Document Type stored for calls that have no sales document behind them.
    /// Kept in one place so the choice of placeholder is not spread across call sites.
    /// </summary>
    local procedure NoDocumentType(): Enum "Sales Document Type"
    begin
        exit(Enum::"Sales Document Type"::Quote);
    end;

    /// <summary>
    /// Logs a call that is not tied to a sales document. Such calls are recorded against the
    /// no-document placeholder, so the Document No. on the entry stays blank.
    /// </summary>
    local procedure InsertEntry(URL: Text; Method: Text; RequestBody: Text; ResponseText: Text; ErrorText: Text; Success: Boolean; LogResponse: Boolean)
    begin
        InsertEntry(NoDocumentType(), '', URL, Method, RequestBody, ResponseText, ErrorText, Success, LogResponse);
    end;

    local procedure InsertEntry(DocType: Enum "Sales Document Type"; DocNo: Code[20]; URL: Text; Method: Text; RequestBody: Text; ResponseText: Text; ErrorText: Text; Success: Boolean; LogResponse: Boolean)
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        EntryNo: Integer;
    begin
        AlvysEntry.LockTable(true);
        if AlvysEntry.FindLast() then
            EntryNo := AlvysEntry."Entry No.";
        AlvysEntry.Init();
        AlvysEntry."Entry No." := EntryNo + 1;
        AlvysEntry."User ID" := CopyStr(UserId(), 1, MaxStrLen(AlvysEntry."User ID"));
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
        LoadedSetup: Boolean;
        BearerTok: Label 'Bearer %1', Locked = true, Comment = '%1 = Access Token';
        TokenURLLbl: Label 'https://auth.alvys.com/oauth/token', Locked = true;
        AudienceLbl: Label 'https://api.alvys.com/public/', Locked = true;
        TokenMissingErr: Label 'access_token not found in response:\%1', Comment = '%1 = Response Text';
        UnableToSendErr: Label 'Unable to send request:\%1', Comment = '%1 = Error Text';
        UnableToReadErr: Label 'Unable to read response:\%1', Comment = '%1 = Response Text';
        NoTruckFoundErr: Label 'No Alvys truck was found with truck number %1.', Comment = '%1 = Truck Number';
        MissingTruckNumberErr: Label 'The truck number cannot be blank.';
        TruckIdTok: Label 'TruckId', Locked = true;
        DriverIdTok: Label 'DriverId', Locked = true;
        MissingAssetIDErr: Label 'The %1 cannot be blank when creating a deduction.', Comment = '%1 = TruckId or DriverId';
        MissingDeductionIDErr: Label 'The deduction Id cannot be blank.';
        MissingTractorCodeErr: Label 'The document does not have a value for the %1 dimension.', Comment = '%1 = Tractor Code Dimension';
}
