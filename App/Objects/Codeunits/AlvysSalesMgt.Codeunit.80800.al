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
        RequestHeaders, ContentHeaders : HttpHeaders;
        JsonBody, ResponseObj : JsonObject;
        SendTime: DateTime;
        ExpiresIn: Integer;
        ExpiryDuration: Duration;
        AccessToken, ErrorText, ResponseText : Text;
        Sent: Boolean;
    begin
        AlvysSalesSetup.TestField("Client ID");
        AlvysSalesSetup.TestField("Client Secret");
        SendTime := CurrentDateTime();
        JsonBody.Add('client_id', AlvysSalesSetup."Client ID");
        JsonBody.Add('client_secret', AlvysSalesSetup."Client Secret");
        JsonBody.Add('audience', AudienceLbl);
        JsonBody.Add('grant_type', 'client_credentials');
        PrepareHeaders('', RequestHeaders, ContentHeaders);
        // the token request is not logged, as the request body contains the client secret
        // and the response contains the access token
        Sent := RESTAPIMgt.TryGetResponseAsJsonObject('POST', TokenURLLbl, JsonBody, RequestHeaders, ContentHeaders, ResponseObj, ResponseText, ErrorText);
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
    begin
        exit(GetTruckID(TruckNumber, Enum::"Sales Document Type"::Quote, ''));
    end;

    procedure GetTruckID(TruckNumber: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]): Text
    var
        JsonBody, ResponseObj, ItemObj : JsonObject;
        ItemsArray: JsonArray;
        JsonTkn: JsonToken;
        TruckID, URL : Text;
    begin
        GetAndCheckSetup();
        if TruckNumber = '' then
            Error(MissingTruckNumberErr);
        JsonBody.Add('Page', 1);
        JsonBody.Add('PageSize', 100);
        JsonBody.Add('TruckNumber', TruckNumber);
        URL := StrSubstNo(TruckSearchURLTok, AlvysSetup."Integration URL", APIVersionTok);
        ResponseObj := SendAPIRequest('POST', URL, JsonBody, DocType, DocNo);
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


    procedure CreateDeduction(TruckID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text)
    begin
        CreateDeduction(TruckID, Date, Amount, Category, Description, Enum::"Sales Document Type"::Quote, '', false);
    end;

    procedure CreateDeduction(var SalesHeader: Record "Sales Header"; Date: Date; Amount: Decimal; Category: Text; Description: Text)
    var
        TruckID: Text;
    begin
        TruckID := GetTruckID(GetTractorCodeDimensionValue(SalesHeader."Dimension Set ID"), SalesHeader."Document Type", SalesHeader."No.");
        CreateDeduction(TruckID, Date, Amount, Category, Description, SalesHeader."Document Type", SalesHeader."No.", false);
    end;

    procedure CreateDeduction(var SalesInvHeader: Record "Sales Invoice Header"; Date: Date; Amount: Decimal; Category: Text; Description: Text)
    var
        TruckID: Text;
    begin
        TruckID := GetTruckID(GetTractorCodeDimensionValue(SalesInvHeader."Dimension Set ID"), Enum::"Sales Document Type"::Invoice, SalesInvHeader."No.");
        CreateDeduction(TruckID, Date, Amount, Category, Description, Enum::"Sales Document Type"::Invoice, SalesInvHeader."No.", true);
    end;

    procedure CreateDeduction(TruckID: Text; Date: Date; Amount: Decimal; Category: Text; Description: Text; DocType: Enum "Sales Document Type"; DocNo: Code[20]; Posted: Boolean)
    var
        JsonBody, ResponseObj : JsonObject;
        URL: Text;
    begin
        GetAndCheckSetup();
        JsonBody.Add('Date', Format(Date, 0, '<Year4>-<Month,2>-<Day,2>'));
        JsonBody.Add('Amount', Amount);
        JsonBody.Add('Category', Category);
        JsonBody.Add('Description', Description);
        JsonBody.Add('TruckId', TruckID);
        URL := StrSubstNo(DeductionURLTok, AlvysSetup."Integration URL", APIVersionTok);
        ResponseObj := SendAPIRequest('POST', URL, JsonBody, DocType, DocNo);
        InsertDeduction(ResponseObj, DocType, DocNo, Posted);
    end;

    local procedure InsertDeduction(var ResponseObj: JsonObject; DocType: Enum "Sales Document Type"; DocNo: Code[20]; Posted: Boolean)
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
        AlvysDeduction.Date := DT2Date(JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'Date'));
        AlvysDeduction."Is Paid" := JsonMgt.GetJsonValueAsBoolean(ResponseObj, 'IsPaid');
        AlvysDeduction."Created At" := JsonMgt.GetJsonValueAsDateTime(ResponseObj, 'CreatedAt');
        AlvysDeduction."Created By" := CopyStr(JsonMgt.GetJsonValueAsText(ResponseObj, 'CreatedBy'), 1, MaxStrLen(AlvysDeduction."Created By"));
        AlvysDeduction."Document Type" := DocType;
        AlvysDeduction."Document No." := DocNo;
        AlvysDeduction.Posted := Posted;
        AlvysDeduction.Insert(true);
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


    local procedure SendAPIRequest(Method: Text; URL: Text; var JsonBody: JsonObject; DocType: Enum "Sales Document Type"; DocNo: Code[20]): JsonObject
    var
        RequestHeaders, ContentHeaders : HttpHeaders;
        ResponseObj: JsonObject;
        AccessToken, ErrorText, RequestBody, ResponseText : Text;
        Sent: Boolean;
    begin
        AccessToken := CheckToGetAccessToken();
        JsonBody.WriteTo(RequestBody);
        PrepareHeaders(AccessToken, RequestHeaders, ContentHeaders);
        Sent := RESTAPIMgt.TryGetResponseAsJsonObject(Method, URL, JsonBody, RequestHeaders, ContentHeaders, ResponseObj, ResponseText, ErrorText);
        InsertEntry(DocType, DocNo, URL, Method, RequestBody, ResponseText, ErrorText, Sent, true);
        if not Sent then
            Error(ErrorText);
        exit(ResponseObj);
    end;

    local procedure PrepareHeaders(AccessToken: Text; var RequestHeaders: HttpHeaders; var ContentHeaders: HttpHeaders)
    begin
        if AccessToken <> '' then
            RequestHeaders.Add('Authorization', StrSubstNo(BearerTok, AccessToken));
        ContentHeaders.Add('Content-Type', 'application/json');
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
        RESTAPIMgt: Codeunit "BAAPI REST API Mgt.";
        LoadedSetup: Boolean;
        BearerTok: Label 'Bearer %1', Locked = true, Comment = '%1 = Access Token';
        TokenURLLbl: Label 'https://auth.alvys.com/oauth/token', Locked = true;
        AudienceLbl: Label 'https://api.alvys.com/public/', Locked = true;
        APIVersionTok: Label 'v1', Locked = true;
        TruckSearchURLTok: Label '%1/api/p/%2/trucks/search', Locked = true, Comment = '%1 = Integration URL, %2 = API Version';
        DeductionURLTok: Label '%1/api/p/%2/deductions/once', Locked = true, Comment = '%1 = Integration URL, %2 = API Version';
        TokenMissingErr: Label 'access_token not found in response:\%1', Comment = '%1 = Response Text';
        NoTruckFoundErr: Label 'No Alvys truck was found with truck number %1.', Comment = '%1 = Truck Number';
        MissingTruckNumberErr: Label 'The truck number cannot be blank.';
        MissingTractorCodeErr: Label 'The document does not have a value for the %1 dimension.', Comment = '%1 = Tractor Code Dimension';
}
