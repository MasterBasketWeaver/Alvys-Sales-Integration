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
            Tooltip = 'The truck number the deduction was created for. This is the value of the Fleetrock Setup''s Truck Dimension Code on the document, and is what the Alvys truck was resolved from.';
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
        field(18; "Settlement Posted"; Boolean)
        {
            Editable = false;
            Tooltip = 'Whether the payment journal line that applies the settlement has been posted, whether it was posted automatically or by hand.';
        }
        field(19; "Posted DateTime"; DateTime)
        {
            Editable = false;
            Tooltip = 'The date and time the payment journal line that applies the settlement was posted.';
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
        // Alvys pays a deduction off in parts by splitting it: the original is deleted there and
        // replaced by parts under new Ids that keep its Group Id. The original is kept here, and
        // each part is logged as its own deduction pointing back at it.
        field(34; "Split in Alvys"; Boolean)
        {
            Editable = false;
            Tooltip = 'Whether the deduction has been split in Alvys. A split deduction no longer exists in Alvys and is not settled itself; its parts are logged as deductions of their own and carry the settlement.';
        }
        field(33; "Remaining Amount"; Decimal)
        {
            Editable = false;
            Tooltip = 'How much of the deduction has not been written to the payment journal yet. For a deduction split in Alvys this is the total of the parts still to be applied.';
        }
        field(35; "Split From Entry No."; Integer)
        {
            Editable = false;
            TableRelation = "BAASI Alvys Deduction"."Entry No.";
            Tooltip = 'The deduction this one was split from in Alvys. Blank for a deduction Business Central raised itself.';
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
        // A posted settlement journal line carries only the deduction Id back to its deduction.
        key(K5; Id) { }
        key(K6; "Split From Entry No.") { }
    }

    procedure SplitParts(var SplitPart: Record "BAASI Alvys Deduction"): Boolean
    begin
        SplitPart.Reset();
        SplitPart.SetRange("Split From Entry No.", "Entry No.");
        exit(SplitPart.FindSet());
    end;
}
