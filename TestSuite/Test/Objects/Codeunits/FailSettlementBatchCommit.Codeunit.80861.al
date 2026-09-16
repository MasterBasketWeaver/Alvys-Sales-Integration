codeunit 80861 "BAASIT Fail Settl Batch Commit"
{
    // Bound by a test to make a payment batch fail at the last point before it commits, after every
    // line in it has posted. What the deduction looked like at that moment is kept, so the test can
    // tell a mark that was rolled back from one that was never made.

    EventSubscriberInstance = Manual;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Post Batch", OnBeforeCommit, '', false, false)]
    local procedure GenJnlPostBatchOnBeforeCommit(GLRegNo: Integer; var GenJournalLine: Record "Gen. Journal Line"; var GenJnlPostLine: Codeunit "Gen. Jnl.-Post Line")
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        AlvysDeduction.SetRange(Id, CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        if AlvysDeduction.FindLast() then
            PostedBeforeCommit := AlvysDeduction."Settlement Posted";
        Error(SimulatedFailureErr);
    end;

    procedure SetDeductionId(NewDeductionId: Text)
    begin
        DeductionId := NewDeductionId;
    end;

    procedure SettlementPostedBeforeCommit(): Boolean
    begin
        exit(PostedBeforeCommit);
    end;

    var
        DeductionId: Text;
        PostedBeforeCommit: Boolean;
        SimulatedFailureErr: Label 'Simulated failure before the settlement batch commits.', Locked = true;
}
