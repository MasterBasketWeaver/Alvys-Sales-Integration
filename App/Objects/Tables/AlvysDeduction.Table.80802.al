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
            Tooltip = 'Whether Alvys has settled the deduction. Stamped when the deduction is created and refreshed by the settlement poll; it says what Alvys reports, not what Business Central has done about it.';
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
        field(15; "Truck Number"; Text[50])
        {
            Editable = false;
            Tooltip = 'The truck number the deduction was created for. This is the Tractor Code dimension value on the document, and is what the Alvys truck was resolved from.';
        }
        // Kept apart from "Is Paid" so a settlement that could not be applied stays eligible for the
        // next poll to pick up again.
        field(16; "Settlement Applied"; Boolean)
        {
            Editable = false;
            Tooltip = 'Whether the settled deduction has been written to the payment journal. Set once the settlement has been applied, so that a later poll does not apply it a second time.';
        }
        field(17; "Settlement Applied At"; DateTime)
        {
            Editable = false;
            Tooltip = 'The date and time the settlement was written to the payment journal.';
        }
        field(20; "Document Type"; Enum "BAASI Alvys Entry Doc. Type")
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
        // The inbound apply-deduction call arrives with the Alvys deduction Id and nothing else to
        // match on, so that lookup runs on every settlement Alvys processes.
        key(K5; Id) { }
    }
}
