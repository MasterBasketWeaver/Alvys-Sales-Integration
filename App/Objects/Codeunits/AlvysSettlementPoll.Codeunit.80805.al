codeunit 80805 "BAASI Alvys Settlement Poll"
{
    // Alvys has no driver pay webhook event and no settlement resource in the public API, so a
    // settlement can only be found by looking: the IsPaid flag on the deduction, or on the parts it
    // was split into, turning over is the whole signal.

    Permissions = tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RIMD;

    trigger OnRun()
    begin
        // How the job queue reaches the poll. A scheduled run must not lose the rest of its work to
        // one deduction Business Central or another extension refuses, so it logs what stopped that
        // one and carries on. A run started by hand from the setup page calls PollSettledDeductions
        // directly, leaving this false, so whoever pressed the action is shown the error instead.
        ScheduledRun := true;
        PollSettledDeductions();
    end;

    procedure PollSettledDeductions()
    begin
        RefreshPaidDeductions();
        ApplySettledDeductions();
    end;

    local procedure RefreshPaidDeductions()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        Items: JsonArray;
        EarliestDate: Date;
    begin
        AlvysDeduction.SetRange("Is Paid", false);
        AlvysDeduction.SetFilter("Posted Document No.", '<>%1', '');
        AlvysDeduction.SetFilter(Id, '<>%1', '');
        // A dateless deduction taken as a bound would collapse the range and stop the ones
        // that do carry a date from being asked about at all.
        AlvysDeduction.SetFilter(Date, '<>%1', 0D);
        if not AlvysDeduction.FindSet() then
            exit;

        EarliestDate := AlvysDeduction.Date;
        repeat
            if AlvysDeduction.Date < EarliestDate then
                EarliestDate := AlvysDeduction.Date;
        until AlvysDeduction.Next() = 0;

        // Left open-ended: the parts of a split deduction can be edited onto a later date than the
        // deduction Business Central raised.
        CollectDeductions(EarliestDate, Items);
        RefreshFromSearch(Items);
    end;

    /// <summary>
    /// The search takes no Id filter, so the date range is what narrows it and the caller matches
    /// the Ids it gets back against the deductions it was asking about. Unpaid deductions are
    /// collected too: an unpaid part is what says a split deduction is only partly settled.
    /// </summary>
    local procedure CollectDeductions(StartDate: Date; var Items: JsonArray)
    var
        ResponseObj: JsonObject;
        ItemsArray: JsonArray;
        JsonTkn: JsonToken;
        ErrorText: Text;
        PageNo, Read, Total : Integer;
    begin
        repeat
            if not AlvysSalesMgt.SearchDeductions(StartDate, 0D, true, PageNo, SearchPageSize(), ResponseObj, ErrorText) then begin
                // The error below rolls the logged entry back with it; a scheduled run has nobody
                // watching, so keep the record of why the poll stopped.
                if ScheduledRun then
                    Commit();
                Error(ErrorText);
            end;
            if not ResponseObj.Get('Items', JsonTkn) then
                exit;
            ItemsArray := JsonTkn.AsArray();
            if ItemsArray.Count() = 0 then
                exit;
            Total := JsonMgt.GetJsonValueAsInteger(ResponseObj, 'Total');
            foreach JsonTkn in ItemsArray do begin
                Items.Add(JsonTkn);
                Read += 1;
            end;
            PageNo += 1;
        until Read >= Total;
    end;

    /// <summary>
    /// Brings the deductions Business Central is waiting on into line with what the search
    /// returned.
    ///
    /// A deduction still returned under its own Id is refreshed from it. One that is not has been
    /// split in Alvys: splitting deletes the deduction and creates the parts under new Ids that keep
    /// its Group Id, so the parts are read out of that group and logged as deductions of their own,
    /// pointing back at the one they were split from. They are settled in their own right from then
    /// on, and what happens to them is carried back up to it.
    ///
    /// A part that has itself been split is handled the same way on a later run, by the part rather
    /// than by the deduction above it: a split is only ever read by the record that disappeared, so
    /// each part is logged once and under the record it came from.
    /// </summary>
    internal procedure RefreshFromSearch(var Items: JsonArray)
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        ItemObj: JsonObject;
        ItemTkn: JsonToken;
        ItemsById: Dictionary of [Text, JsonObject];
        GroupItems: Dictionary of [Text, List of [Text]];
        GroupIds: List of [Text];
        EntryNos: List of [Integer];
        ItemId, GroupId : Text;
        EntryNo: Integer;
    begin
        foreach ItemTkn in Items do begin
            ItemObj := ItemTkn.AsObject();
            ItemId := SearchKey(JsonMgt.GetJsonValueAsText(ItemObj, 'Id'));
            if ItemId <> '' then begin
                ItemsById.Set(ItemId, ItemObj);
                GroupId := SearchKey(JsonMgt.GetJsonValueAsText(ItemObj, 'GroupId'));
                if GroupId <> '' then begin
                    if not GroupItems.ContainsKey(GroupId) then
                        GroupItems.Add(GroupId, GroupIds);
                    GroupItems.Get(GroupId, GroupIds);
                    if not GroupIds.Contains(ItemId) then begin
                        GroupIds.Add(ItemId);
                        GroupItems.Set(GroupId, GroupIds);
                    end;
                end;
            end;
        end;

        AlvysDeduction.SetRange("Is Paid", false);
        AlvysDeduction.SetFilter("Posted Document No.", '<>%1', '');
        AlvysDeduction.SetFilter(Id, '<>%1', '');
        // Gathered before any is refreshed: logging the parts of a split inserts into the set being
        // read.
        if AlvysDeduction.FindSet() then
            repeat
                EntryNos.Add(AlvysDeduction."Entry No.");
            until AlvysDeduction.Next() = 0;

        foreach EntryNo in EntryNos do
            if AlvysDeduction.Get(EntryNo) then begin
                ItemId := SearchKey(AlvysDeduction.Id);
                if ItemsById.Get(ItemId, ItemObj) then
                    RefreshDeduction(AlvysDeduction, ItemObj)
                else
                    if not AlvysDeduction."Split in Alvys" then
                        LogSplitParts(AlvysDeduction, ItemsById, GroupItems);
            end;
    end;

    local procedure RefreshDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction"; var ItemObj: JsonObject)
    begin
        if not JsonMgt.GetJsonValueAsBoolean(ItemObj, 'IsPaid') then
            exit;
        AlvysDeduction."Is Paid" := true;
        AlvysDeduction.Modify(true);
        AlvysSalesMgt.UpdateSplitDeduction(AlvysDeduction."Entry No.");
    end;

    /// <summary>
    /// Logs the parts of a deduction the search no longer returns, from the other deductions in its
    /// group. A part already logged is left alone, so a run that finds nothing new changes nothing.
    /// A group that has nothing in it but the deduction's own history leaves it as it is: the
    /// deduction may have been deleted in Alvys rather than split, and there is nothing to settle it
    /// with either way.
    /// </summary>
    local procedure LogSplitParts(var AlvysDeduction: Record "BAASI Alvys Deduction"; var ItemsById: Dictionary of [Text, JsonObject]; var GroupItems: Dictionary of [Text, List of [Text]])
    var
        SplitPart: Record "BAASI Alvys Deduction";
        ItemObj: JsonObject;
        GroupIds: List of [Text];
        ItemId: Text;
        Logged: Boolean;
    begin
        if AlvysDeduction."Group Id" = '' then
            exit;
        if not GroupItems.Get(SearchKey(AlvysDeduction."Group Id"), GroupIds) then
            exit;

        foreach ItemId in GroupIds do
            if not DeductionExists(ItemId) then begin
                ItemsById.Get(ItemId, ItemObj);
                AlvysSalesMgt.InsertSplitPart(AlvysDeduction, ItemObj, SplitPart);
                Logged := true;
            end;
        if not Logged then
            exit;

        AlvysDeduction."Split in Alvys" := true;
        AlvysDeduction.Modify(true);
        AlvysSalesMgt.UpdateSplitDeduction(SplitPart."Entry No.");
    end;

    local procedure DeductionExists(DeductionId: Text): Boolean
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        AlvysDeduction.SetRange(Id, CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        exit(not AlvysDeduction.IsEmpty());
    end;

    local procedure ApplySettledDeductions()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        EntryNos: List of [Integer];
        EntryNo: Integer;
    begin
        AlvysDeduction.SetRange("Is Paid", true);
        AlvysDeduction.SetRange("Settlement Applied", false);
        // A deduction split in Alvys is settled by its parts, each of which is applied in its own
        // right, so applying it as well would pay the invoice down twice.
        AlvysDeduction.SetRange("Split in Alvys", false);
        AlvysDeduction.SetFilter("Posted Document No.", '<>%1', '');
        // Gathered before any is applied: applying one posts the batch when the setup asks for it,
        // and that commits underneath a record set still being read.
        if AlvysDeduction.FindSet() then
            repeat
                EntryNos.Add(AlvysDeduction."Entry No.");
            until AlvysDeduction.Next() = 0;

        foreach EntryNo in EntryNos do
            if AlvysDeduction.Get(EntryNo) then
                if ScheduledRun then begin
                    ClearLastError();
                    Commit();
                    if not Codeunit.Run(Codeunit::"BAASI Apply Settled Deduction", AlvysDeduction) then
                        LogFailedSettlement(EntryNo, GetLastErrorText(), GetLastErrorCallStack());
                end else
                    ApplySettledDeduction(AlvysDeduction);
    end;

    /// <summary>
    /// Records a settlement an error stopped outright, for a scheduled run that has swallowed it to
    /// stay alive. The failure rolled its own attempt back, so the entry is committed to survive
    /// whatever the rest of the run does. The deduction keeps Settlement Applied false and is left
    /// for the next poll to try again.
    /// </summary>
    local procedure LogFailedSettlement(EntryNo: Integer; ErrorText: Text; ErrorStack: Text)
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        if not AlvysDeduction.Get(EntryNo) then
            exit;
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareFailedSettlementEntry(AlvysEntry, AlvysDeduction, WorkDate(), ErrorText, ErrorStack, 'GET', 'deductions/search');
        AlvysSalesMgt.InsertSettlementEntry(AlvysEntry);
        Commit();
    end;

    /// <summary>
    /// Alvys reports no paid date, settlement date or settlement Id against a settled deduction, so
    /// the payment posts under the work date of the run that found it. Only a settlement that went
    /// through is marked applied; one that did not is left for the next run to try again.
    /// </summary>
    internal procedure ApplySettledDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction"): Text
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareApplyDeductionEntry(AlvysEntry, AlvysDeduction, WorkDate(), 'GET', 'deductions/search');
        AlvysSalesMgt.InsertSettlementEntry(AlvysEntry);

        exit(AlvysEntry."Error Message");
    end;

    local procedure SearchKey(DeductionId: Text): Text
    begin
        exit(UpperCase(DeductionId));
    end;

    local procedure SearchPageSize(): Integer
    begin
        exit(100);
    end;

    var
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        ScheduledRun: Boolean;
        JsonMgt: Codeunit "BAAPI Json Mgt.";
}
