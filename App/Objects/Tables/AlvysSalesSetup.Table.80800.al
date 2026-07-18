table 80800 "BAASI Alvys Sales Setup"
{
    Caption = 'Alvys Sales Setup';
    DataClassification = CustomerContent;
    DrillDownPageId = "BAASI Alvys Sales Setup";
    LookupPageId = "BAASI Alvys Sales Setup";

    fields
    {
        field(1; "Primary Key"; Code[1])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(2; "Integration URL"; Text[1024])
        {
            DataClassification = CustomerContent;
            Tooltip = 'The URL for the Alvys Integration API.';
        }
        field(3; "Client ID"; Text[100])
        {
            DataClassification = CustomerContent;
            Tooltip = 'The Client ID used to authenticate with the Alvys API.';
        }
        field(4; "Client Secret"; Text[250])
        {
            DataClassification = CustomerContent;
            Tooltip = 'The Client Secret used to authenticate with the Alvys API.';
        }
        field(5; "Access Token"; Blob)
        {
            DataClassification = CustomerContent;
        }
        field(6; "Access Token Expiry Date"; DateTime)
        {
            DataClassification = CustomerContent;
            Editable = false;
            Tooltip = 'The date and time that the stored access token expires.';
        }
        field(7; "Tractor Code Dimension"; Code[20])
        {
            DataClassification = CustomerContent;
            TableRelation = Dimension.Code;
            Tooltip = 'The dimension whose value is used as the truck number when calling the Alvys API.';
        }
    }
    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }

    procedure SetAccessToken(NewAccessToken: Text)
    var
        OutStrm: OutStream;
    begin
        Clear(Rec."Access Token");
        if NewAccessToken = '' then
            exit;
        Rec."Access Token".CreateOutStream(OutStrm, TextEncoding::UTF8);
        OutStrm.WriteText(NewAccessToken);
    end;

    procedure GetAccessToken(): Text
    var
        InStrm: InStream;
        s: Text;
    begin
        Rec.CalcFields("Access Token");
        if not Rec."Access Token".HasValue() then
            exit('');
        Rec."Access Token".CreateInStream(InStrm, TextEncoding::UTF8);
        InStrm.ReadText(s);
        exit(s);
    end;

    procedure HasAccessToken(): Boolean
    begin
        Rec.CalcFields("Access Token");
        exit(Rec."Access Token".HasValue());
    end;
}
