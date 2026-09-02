table 80856 "BAASIT E2E Run"
{
    Caption = 'Alvys E2E Run';
    DataClassification = SystemMetadata;

    // Singleton carrying one chained end-to-end run across the phases it is made of. The chain
    // cannot run as a single test: the deduction it creates has to be settled by hand in the Alvys
    // web UI before the poll has anything to find, and a test method cannot stop and wait for that.
    // So the run is seeded by one phase, settled outside Business Central, and finished by another,
    // and what the first phase produced is kept here for the last one to pick up.

    fields
    {
        field(1; "Primary Key"; Code[10]) { DataClassification = SystemMetadata; }
        field(2; "Poll Mode"; Enum "BAASIT E2E Poll Mode") { DataClassification = SystemMetadata; }
        field(3; "Repair Order Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(4; "Sales Invoice No."; Code[20]) { DataClassification = SystemMetadata; }
        field(5; "Posted Invoice No."; Code[20]) { DataClassification = SystemMetadata; }
        field(6; "Deduction Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(7; "Deduction Entry No."; Integer) { DataClassification = SystemMetadata; }
        field(8; "Truck Id"; Text[50]) { DataClassification = SystemMetadata; }
        field(9; "Truck Number"; Text[50]) { DataClassification = SystemMetadata; }
        field(10; Amount; Decimal) { DataClassification = SystemMetadata; }
        field(11; "Seeded At"; DateTime) { DataClassification = SystemMetadata; }
        field(12; "Polled At"; DateTime) { DataClassification = SystemMetadata; }
        field(13; "Customer No."; Code[20]) { DataClassification = SystemMetadata; }
        field(14; "Invoice Remaining Amount"; Decimal) { DataClassification = SystemMetadata; }
        field(15; "Invoice Closed"; Boolean) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Primary Key") { Clustered = true; }
    }

    procedure GetSingleton()
    begin
        if Rec.Get('') then
            exit;
        Rec.Init();
        Rec."Primary Key" := '';
        Rec.Insert();
    end;

    /// <summary>
    /// Clears what a previous chain left behind, so a seed phase never inherits the deduction or
    /// the invoice of the run before it and a later phase cannot quietly assert against stale data.
    /// </summary>
    procedure Reset(NewPollMode: Enum "BAASIT E2E Poll Mode")
    begin
        GetSingleton();
        Rec."Poll Mode" := NewPollMode;
        Clear(Rec."Repair Order Id");
        Clear(Rec."Sales Invoice No.");
        Clear(Rec."Posted Invoice No.");
        Clear(Rec."Deduction Id");
        Clear(Rec."Deduction Entry No.");
        Clear(Rec."Truck Id");
        Clear(Rec."Truck Number");
        Clear(Rec.Amount);
        Clear(Rec."Seeded At");
        Clear(Rec."Polled At");
        Clear(Rec."Customer No.");
        Clear(Rec."Invoice Remaining Amount");
        Clear(Rec."Invoice Closed");
        Rec.Modify();
    end;
}
