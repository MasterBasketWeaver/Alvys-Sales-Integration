codeunit 80850 "BAASI Alvys MEM Sales Mgt."
{
    Permissions = TableData "Gen. Journal Line" = RIMD;


    [EventSubscriber(ObjectType::Codeunit, Codeunit::"BAASI Alvys Sales Mgt.", OnBeforeGenJnlLineModify, '', false, false)]
    local procedure AlvysSalesMgtOnBeforeGenJnlLineModify(var GenJnlLine: Record "Gen. Journal Line")
    begin
        if GenJnlLine."Shortcut Dimension 1 Code" <> '' then
            GenJnlLine.Validate(BssiEntityID, GenJnlLine."Shortcut Dimension 1 Code");
    end;

    [EventSubscriber(ObjectType::Page, Page::"BAASI Alvys Deductions", OnBeforeDisplaySettlementMessage, '', false, false)]
    local procedure AlvysSalesMgtOnBeforeDisplaySettlementMessage(var IsHandled: Boolean; var GenJnlLine: Record "Gen. Journal Line"; LineAction: Text)
    begin
        IsHandled := true;
        Message(MEMLineUpdatedMsg, LineAction, GenJnlLine."Line No.", GenJnlLine."Journal Batch Name", GenJnlLine.BssiEntityID);
    end;


    var
        MEMLineUpdatedMsg: Label '%1 line %2 in batch %3, Entity %4', Comment = '%1 = Line Action, %2 = Line No., %3 = Journal Batch Name, %4 = Entity';
}
