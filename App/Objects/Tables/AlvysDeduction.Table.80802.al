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
            Editable = false;
        }
        field(2; Id; Text[50])
        {
            Editable = false;
        }
        field(3; Type; Text[30])
        {
            Editable = false;
        }
        field(4; "Group Id"; Text[50])
        {
            Editable = false;
        }
        field(5; Description; Text[250])
        {
            Editable = false;
        }
        field(6; Category; Text[100])
        {
            Editable = false;
        }
        field(7; Amount; Decimal)
        {
            Editable = false;
        }
        field(8; "Currency Id"; Integer)
        {
            Editable = false;
            Tooltip = 'The ISO 4217 numeric currency code returned by Alvys.';
        }
        field(9; "Truck Id"; Text[50])
        {
            Editable = false;
        }
        field(10; "Date"; Date)
        {
            Editable = false;
        }
        field(11; "Is Paid"; Boolean)
        {
            Editable = false;
        }
        field(12; "Created By"; Code[50])
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = Lookup(User."User Name" where("User Security ID" = field(SystemCreatedBy)));
        }
        field(14; "Driver Id"; Text[50])
        {
            Editable = false;
        }
        field(20; "Document Type"; Enum "Sales Document Type")
        {
            Editable = false;
        }
        field(21; "Document No."; Code[20])
        {
            Editable = false;
        }
        field(23; "Posted Document No."; Code[20])
        {
            Editable = false;
            Tooltip = 'The number of the posted Sales Invoice the deduction ended up on. Blank while the originating document is still unposted.';
        }
        field(30; "Alvys Created At"; DateTime)
        {
            Editable = false;
            Tooltip = 'The date and time the deduction was created in Alvys.';
        }
        field(31; "Alvys Created By"; Code[100])
        {
            Editable = false;
            Tooltip = 'The user who created the deduction in Alvys.';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(K1; "Document Type", "Document No.") { }
        key(K2; "Posted Document No.") { }
        key(K3; "Alvys Created At") { }
        key(K4; "SystemCreatedAt") { }
    }
}
