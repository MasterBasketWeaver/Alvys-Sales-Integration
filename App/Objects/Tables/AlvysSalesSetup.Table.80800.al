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
        // field(8; "Entity Code Dimension"; Code[20])
        // {
        //     DataClassification = CustomerContent;
        //     TableRelation = Dimension.Code;
        //     Tooltip = 'The dimension whose value is used as the entity code when calling the Alvys API.';
        // }
        field(10; "Enabled"; Boolean)
        {
            DataClassification = CustomerContent;
            Tooltip = 'Specifies if the integration is enabled or not.';
        }
        field(11; "Bal. Account No."; Code[20])
        {
            DataClassification = CustomerContent;
            TableRelation = "G/L Account"."No." where(Blocked = const(false), "Direct Posting" = const(true));
            Tooltip = 'The G/L account the payment side of a settled deduction is posted to.';
        }
        field(12; "Payment Journal Template"; Code[10])
        {
            DataClassification = CustomerContent;
            TableRelation = "Gen. Journal Template".Name;
            Tooltip = 'The general journal template a settled deduction is written to.';

            trigger OnValidate()
            begin
                // The batch is only meaningful under the template it belongs to, so a template
                // change leaves the batch to be picked again rather than pointing at nothing.
                if Rec."Payment Journal Template" <> xRec."Payment Journal Template" then
                    Rec."Payment Journal Batch" := '';
            end;
        }
        field(13; "Payment Journal Batch"; Code[10])
        {
            DataClassification = CustomerContent;
            TableRelation = "Gen. Journal Batch".Name where("Journal Template Name" = field("Payment Journal Template"));
            Tooltip = 'The general journal batch a settled deduction is written to.';
        }
        field(14; "Auto-Post Deductions"; Boolean)
        {
            DataClassification = CustomerContent;
            Tooltip = 'Specifies whether the payment journal batch is posted as soon as a settled deduction is written to it.';
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
