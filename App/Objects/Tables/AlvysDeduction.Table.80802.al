table 80802 "BAASI Alvys Deduction"
{
    Caption = 'Alvys Deduction';
    DataClassification = CustomerContent;
    DrillDownPageId = "BAASI Alvys Deductions";
    LookupPageId = "BAASI Alvys Deductions";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(2; Id; Text[50])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(3; Type; Text[30])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(4; "Group Id"; Text[50])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(5; Description; Text[250])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(6; Category; Text[100])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(7; Amount; Decimal)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(8; "Currency Code"; Integer)
        {
            DataClassification = CustomerContent;
            Editable = false;
            Tooltip = 'The ISO 4217 numeric currency code returned by Alvys.';
        }
        field(9; "Truck Id"; Text[50])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(10; "Date"; Date)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(11; "Is Paid"; Boolean)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(12; "Created At"; DateTime)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(13; "Created By"; Text[100])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(20; "Document Type"; Enum "Sales Document Type")
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(21; "Document No."; Code[20])
        {
            DataClassification = CustomerContent;
            Editable = false;
        }
        field(22; Posted; Boolean)
        {
            DataClassification = CustomerContent;
            Editable = false;
            Tooltip = 'If enabled, the deduction is linked to a posted Sales Invoice.';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Document; "Document Type", "Document No.", Posted) { }
    }
}
