codeunit 89971 "BAASIT Post Batch Diag Run"
{
    TableNo = "Gen. Journal Line";

    trigger OnRun()
    var
        GenJnlPostBatch: Codeunit "Gen. Jnl.-Post Batch";
    begin
        GenJnlPostBatch.SetPreviewMode(true);
        GenJnlPostBatch.Run(Rec);
    end;
}
