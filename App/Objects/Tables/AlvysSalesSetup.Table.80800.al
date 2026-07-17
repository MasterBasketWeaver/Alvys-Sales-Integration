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
    }
    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }
}
