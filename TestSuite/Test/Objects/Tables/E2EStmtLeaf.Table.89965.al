table 89965 "BAASIT E2E Stmt Leaf"
{
    Caption = 'Alvys E2E Statement Leaf';
    DataClassification = SystemMetadata;

    // One deduction as it was finally paid in Alvys: a case that was never split, or a part of one
    // that was. The driving script writes what Alvys says paid it -- the statement it landed on and
    // that statement's date -- and the poll phase checks Business Central and Fleetrock against it.

    fields
    {
        field(1; "Line No."; Integer) { DataClassification = SystemMetadata; AutoIncrement = true; }
        field(2; "Case Code"; Code[20]) { DataClassification = SystemMetadata; }
        field(3; Description; Text[250]) { DataClassification = SystemMetadata; }
        field(4; Amount; Decimal) { DataClassification = SystemMetadata; }
        field(5; "Expected Statement No."; Integer) { DataClassification = SystemMetadata; }
        field(6; "Expected Statement Date"; Date) { DataClassification = SystemMetadata; }
        field(7; "Statement No."; Integer) { DataClassification = SystemMetadata; }
        field(8; "Statement Date"; Date) { DataClassification = SystemMetadata; }
        field(9; "Payment Posting Date"; Date) { DataClassification = SystemMetadata; }
        field(10; "Payment Posted"; Boolean) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Line No.") { Clustered = true; }
    }
}
