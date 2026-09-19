table 89964 "BAASIT E2E Stmt Case"
{
    Caption = 'Alvys E2E Statement Case';
    DataClassification = SystemMetadata;

    // One deduction of the statement-date chain: raised whole, split once, or split twice in the
    // Alvys UI. The seed phase fills in what Business Central produced, and the poll phase records
    // what the invoice and the Fleetrock repair order ended up with.

    fields
    {
        field(1; "Case Code"; Code[20]) { DataClassification = SystemMetadata; }
        field(2; "Repair Order Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(3; "Posted Invoice No."; Code[20]) { DataClassification = SystemMetadata; }
        field(4; "Invoice Posting Date"; Date) { DataClassification = SystemMetadata; }
        field(5; "Deduction Entry No."; Integer) { DataClassification = SystemMetadata; }
        field(6; "Deduction Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(7; "Group Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(8; Description; Text[250]) { DataClassification = SystemMetadata; }
        field(9; Amount; Decimal) { DataClassification = SystemMetadata; }
        field(10; "Customer No."; Code[20]) { DataClassification = SystemMetadata; }
        field(11; "Truck Number"; Text[50]) { DataClassification = SystemMetadata; }
        field(12; "Owner Operator Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(13; "Invoice Closed"; Boolean) { DataClassification = SystemMetadata; }
        field(14; "Invoice Closed At"; Date) { DataClassification = SystemMetadata; }
        field(15; "Fleetrock Paid Date"; Date) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Case Code") { Clustered = true; }
    }
}
