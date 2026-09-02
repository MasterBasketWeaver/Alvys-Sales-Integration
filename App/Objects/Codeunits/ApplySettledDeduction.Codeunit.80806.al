codeunit 80806 "BAASI Apply Settled Deduction"
{
    // Runs one settlement so the scheduled poll can catch whatever stopped it and carry on with the
    // rest. Codeunit.Run rather than a try method: applying a settlement posts the payment batch
    // when the setup asks for it, and that commits, which a try method does not allow.

    TableNo = "BAASI Alvys Deduction";

    Permissions = tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RIMD;

    trigger OnRun()
    var
        AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
    begin
        AlvysSettlementPoll.ApplySettledDeduction(Rec);
    end;
}
