codeunit 89970 "BAASIT Post Batch Diag"
{
    // Records what the journal line record looks like at each point of Gen. Jnl.-Post Batch and of
    // Multi-Entity Management's journal handling, to find where the settlement line drops out of the
    // posting. Kept in memory rather than a table because the run is a preview, whose rollback
    // would take any logged rows with it.
    SingleInstance = true;

    var
        Entries: List of [Text];
        Checkpoints: List of [Text];
        Active: Boolean;

    procedure Start()
    begin
        Clear(Entries);
        Clear(Checkpoints);
        Active := true;
    end;

    procedure Resume()
    begin
        Active := true;
    end;

    procedure Stop()
    begin
        Active := false;
    end;

    procedure Add(Checkpoint: Text; Detail: Text)
    begin
        if not Active then
            exit;
        Checkpoints.Add(Checkpoint);
        Entries.Add(Detail);
    end;

    procedure WriteResults()
    var
        TestResult: Record "BAASIT Test Result";
        i: Integer;
    begin
        TestResult.DeleteAll();
        for i := 1 to Entries.Count() do begin
            TestResult.Init();
            TestResult."Entry No." := 0;
            TestResult."Codeunit Name" := 'Post Batch Diag';
            TestResult."Method Name" := CopyStr(StrSubstNo('%1 %2', i, Checkpoints.Get(i)), 1, MaxStrLen(TestResult."Method Name"));
            TestResult."Error Message" := CopyStr(Entries.Get(i), 1, MaxStrLen(TestResult."Error Message"));
            TestResult."Error Call Stack" := CopyStr(Entries.Get(i), MaxStrLen(TestResult."Error Message") + 1, MaxStrLen(TestResult."Error Call Stack"));
            TestResult.Insert();
        end;
    end;

    procedure Describe(var GenJnlLine: Record "Gen. Journal Line"): Text
    var
        BatchLine: Record "Gen. Journal Line";
        Detail: TextBuilder;
        OriginalGroup, Group : Integer;
    begin
        Detail.Append(StrSubstNo('IsTemporary=%1; current=%2/%3/%4; ', GenJnlLine.IsTemporary(), GenJnlLine."Journal Template Name", GenJnlLine."Journal Batch Name", GenJnlLine."Line No."));
        OriginalGroup := GenJnlLine.FilterGroup();
        for Group := 0 to 10 do begin
            GenJnlLine.FilterGroup(Group);
            if GenJnlLine.GetFilters() <> '' then
                Detail.Append(StrSubstNo('filtergroup %1: %2; ', Group, GenJnlLine.GetFilters()));
        end;
        GenJnlLine.FilterGroup(OriginalGroup);
        if not GenJnlLine.IsTemporary() then
            Detail.Append(StrSubstNo('lines under these filters=%1; ', GenJnlLine.Count()));

        BatchLine.SetRange("Journal Template Name", GenJnlLine."Journal Template Name");
        BatchLine.SetRange("Journal Batch Name", GenJnlLine."Journal Batch Name");
        Detail.Append(StrSubstNo('lines in batch=%1', BatchLine.Count()));
        if BatchLine.FindSet() then
            repeat
                Detail.Append(StrSubstNo('; [%1]', DescribeLine(BatchLine)));
            until BatchLine.Next() = 0;
        exit(Detail.ToText());
    end;

    procedure DescribeLine(GenJnlLine: Record "Gen. Journal Line"): Text
    var
        RecRef: RecordRef;
        FldRef: FieldRef;
        Detail: TextBuilder;
        i: Integer;
    begin
        Detail.Append(StrSubstNo('%1/%2/%3 amount=%4 date=%5 dim1=%6', GenJnlLine."Journal Template Name", GenJnlLine."Journal Batch Name", GenJnlLine."Line No.", GenJnlLine.Amount, GenJnlLine."Posting Date", GenJnlLine."Shortcut Dimension 1 Code"));
        RecRef.GetTable(GenJnlLine);
        for i := 1 to RecRef.FieldCount() do begin
            FldRef := RecRef.FieldIndex(i);
            if (FldRef.Number() >= 70200000) and (FldRef.Number() < 70300000) and (FldRef.Class() = FieldClass::Normal) then
                if not (Format(FldRef.Value()) in ['', '0', 'No', '{00000000-0000-0000-0000-000000000000}']) then
                    Detail.Append(StrSubstNo(' %1=%2', FldRef.Name(), Format(FldRef.Value())));
        end;
        exit(Detail.ToText());
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Post Batch", OnBeforeCode, '', false, false)]
    local procedure PostBatchOnBeforeCode(var GenJournalLine: Record "Gen. Journal Line"; PreviewMode: Boolean; CommitIsSuppressed: Boolean)
    begin
        if Active then
            Add('Post Batch OnBeforeCode', StrSubstNo('preview=%1; %2', PreviewMode, Describe(GenJournalLine)));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Post Batch", OnBeforeProcessLines, '', false, false)]
    local procedure PostBatchOnBeforeProcessLines(var GenJournalLine: Record "Gen. Journal Line"; PreviewMode: Boolean; CommitIsSuppressed: Boolean)
    begin
        if Active then
            Add('Post Batch OnBeforeProcessLines', StrSubstNo('preview=%1; %2', PreviewMode, Describe(GenJournalLine)));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Post Batch", OnAfterCode, '', false, false)]
    local procedure PostBatchOnAfterCode(var GenJournalLine: Record "Gen. Journal Line"; PreviewMode: Boolean)
    begin
        if Active then
            Add('Post Batch OnAfterCode', Describe(GenJournalLine));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::BssiMEMJournalsCUEvents, Bssi_RegKeyValidationJournalsCUEvents, '', false, false)]
    local procedure MEMRegKeyValidation(var Handled: Boolean)
    begin
        if Active then
            Add('MEM Bssi_RegKeyValidationJournalsCUEvents', StrSubstNo('Handled on arrival=%1', Handled));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::BssiMEMJournalsCUEvents, Bssi_OnBeforeProcessLines_AfterCopyBalLine, '', false, false)]
    local procedure MEMOnBeforeProcessLinesAfterCopyBalLine(var GenJournalLine: Record "Gen. Journal Line")
    begin
        if Active then
            Add('MEM Bssi_OnBeforeProcessLines_AfterCopyBalLine', Describe(GenJournalLine));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::BssiMEMJournalsCUEvents, BssiOnBeforeApplyHeaderEntity, '', false, false)]
    local procedure MEMOnBeforeApplyHeaderEntity(var GenJournalLine: Record "Gen. Journal Line"; var BalGenJournalLine: Record "Gen. Journal Line")
    begin
        if Active then
            Add('MEM BssiOnBeforeApplyHeaderEntity', Describe(GenJournalLine));
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::BssiMEMJournalsCUEvents, BssiOnAfterApplyHeaderEntity, '', false, false)]
    local procedure MEMOnAfterApplyHeaderEntity(var GenJournalLine: Record "Gen. Journal Line"; var BalGenJournalLine: Record "Gen. Journal Line")
    begin
        if Active then
            Add('MEM BssiOnAfterApplyHeaderEntity', Describe(GenJournalLine));
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnAfterInsertEvent, '', false, false)]
    local procedure GenJnlLineOnAfterInsert(var Rec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        if Active then
            Add('Gen. Journal Line inserted', StrSubstNo('temporary=%1 trigger=%2 %3', Rec.IsTemporary(), RunTrigger, DescribeLine(Rec)));
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnAfterModifyEvent, '', false, false)]
    local procedure GenJnlLineOnAfterModify(var Rec: Record "Gen. Journal Line"; var xRec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        if Active then
            Add('Gen. Journal Line modified', StrSubstNo('temporary=%1 trigger=%2 %3', Rec.IsTemporary(), RunTrigger, DescribeLine(Rec)));
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnAfterDeleteEvent, '', false, false)]
    local procedure GenJnlLineOnAfterDelete(var Rec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        if Active then
            Add('Gen. Journal Line deleted', StrSubstNo('temporary=%1 trigger=%2 %3', Rec.IsTemporary(), RunTrigger, DescribeLine(Rec)));
    end;

    [EventSubscriber(ObjectType::Table, Database::"Gen. Journal Line", OnAfterRenameEvent, '', false, false)]
    local procedure GenJnlLineOnAfterRename(var Rec: Record "Gen. Journal Line"; var xRec: Record "Gen. Journal Line"; RunTrigger: Boolean)
    begin
        if Active then
            Add('Gen. Journal Line renamed', StrSubstNo('temporary=%1 from %2/%3/%4 to %5', Rec.IsTemporary(), xRec."Journal Template Name", xRec."Journal Batch Name", xRec."Line No.", DescribeLine(Rec)));
    end;
}
