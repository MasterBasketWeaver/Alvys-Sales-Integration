codeunit 80805 "BAASI Alvys Settlement Poll"
{
    // Alvys sends no webhook when a deduction is paid, so a settlement can only be found by
    // looking: the IsPaid flag on the deduction, or on the parts it was split into, turning over is
    // what says it was paid. The deduction itself carries no paid date and no link to what paid it,
    // so the statement is found separately, to post the payment on the statement's date.

    Permissions = tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RIMD,
        tabledata "Sales Invoice Header" = R;

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
        LinkPaidDeductionsToStatements();
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
        EntryNos: List of [Integer];
        ItemId: Text;
        EntryNo: Integer;
    begin
        foreach ItemTkn in Items do begin
            ItemObj := ItemTkn.AsObject();
            ItemId := SearchKey(JsonMgt.GetJsonValueAsText(ItemObj, 'Id'));
            if ItemId <> '' then
                ItemsById.Set(ItemId, ItemObj);
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
                        LogSplitParts(AlvysDeduction, Items);
            end;
    end;

    local procedure RefreshDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction"; var ItemObj: JsonObject)
    var
        IsPaid: Boolean;
    begin
        IsPaid := JsonMgt.GetJsonValueAsBoolean(ItemObj, 'IsPaid');
        // Deductions logged before the owner operator was kept get it here, while still unpaid, so
        // their statement can be searched for once they are paid.
        if (AlvysDeduction."Owner Operator Id" = '') or IsPaid then begin
            if AlvysDeduction."Owner Operator Id" = '' then
                AlvysDeduction."Owner Operator Id" := CopyStr(JsonMgt.GetJsonValueAsText(ItemObj, 'OwnerOperatorId'), 1, MaxStrLen(AlvysDeduction."Owner Operator Id"));
            AlvysDeduction."Is Paid" := IsPaid;
            AlvysDeduction.Modify(true);
        end;
        if IsPaid then
            AlvysSalesMgt.UpdateSplitDeduction(AlvysDeduction."Entry No.");
    end;

    /// <summary>
    /// Logs the parts of a deduction the search no longer returns, from the other deductions in its
    /// group. A part already logged is left alone, so a run that finds nothing new changes nothing.
    /// A group that has nothing in it but the deduction's own history leaves it as it is: the
    /// deduction may have been deleted in Alvys rather than split, and there is nothing to settle it
    /// with either way.
    /// </summary>
    local procedure LogSplitParts(var AlvysDeduction: Record "BAASI Alvys Deduction"; var Items: JsonArray)
    var
        SplitPart: Record "BAASI Alvys Deduction";
        ItemObj: JsonObject;
        ItemTkn: JsonToken;
        GroupId, ItemId : Text;
        Logged: Boolean;
    begin
        if AlvysDeduction."Group Id" = '' then
            exit;
        GroupId := SearchKey(AlvysDeduction."Group Id");

        // Read straight off the search rather than out of a lookup keyed by group: a Dictionary of
        // [Text, List of [Text]] hands every key the same list, because an AL list is a reference,
        // and one deduction going missing then logged the whole search as its parts.
        foreach ItemTkn in Items do begin
            ItemObj := ItemTkn.AsObject();
            if SearchKey(JsonMgt.GetJsonValueAsText(ItemObj, 'GroupId')) = GroupId then begin
                ItemId := SearchKey(JsonMgt.GetJsonValueAsText(ItemObj, 'Id'));
                if (ItemId <> '') and not DeductionExists(ItemId) then begin
                    AlvysSalesMgt.InsertSplitPart(AlvysDeduction, ItemObj, SplitPart);
                    Logged := true;
                end;
            end;
        end;
        if not Logged then
            exit;

        AlvysDeduction."Split in Alvys" := true;
        AlvysDeduction.Modify(true);
        AlvysSalesMgt.UpdateSplitDeduction(SplitPart."Entry No.");
    end;

    /// <summary>
    /// Whether the deduction is already logged. Matched case-insensitively with the @ filter,
    /// because a record filter here is case-sensitive while the Id being looked up has been through
    /// SearchKey -- which upper-cases, since an AL dictionary key is case-sensitive too. A
    /// case-sensitive match found nothing, and every part of a split was logged again on each run.
    /// </summary>
    local procedure DeductionExists(DeductionId: Text): Boolean
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        // Concatenated rather than passed as a placeholder: SetFilter quotes a substituted value,
        // and the quoting defeats the @ -- the filter then matches nothing at all.
        AlvysDeduction.SetFilter(Id, '@' + CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        exit(not AlvysDeduction.IsEmpty());
    end;

    local procedure LinkPaidDeductionsToStatements()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        AlvysDeduction.SetRange("Is Paid", true);
        AlvysDeduction.SetRange("Settlement Applied", false);
        AlvysDeduction.SetRange("Split in Alvys", false);
        AlvysDeduction.SetFilter("Posted Document No.", '<>%1', '');
        LinkStatements(AlvysDeduction);
    end;

    /// <summary>
    /// Finds the settlement statement that paid each deduction in the set not yet linked to one,
    /// searching the statements of each owner operator involved. A deduction no statement lists --
    /// one marked paid in Alvys without a statement -- is left unlinked and posts on the work date.
    /// </summary>
    internal procedure LinkStatements(var AlvysDeduction: Record "BAASI Alvys Deduction")
    var
        Unlinked: Record "BAASI Alvys Deduction";
        Statements: JsonArray;
        EarliestDates: Dictionary of [Text, Date];
        OwnerOperatorId: Text;
        EarliestDate, DeductionDate : Date;
    begin
        Unlinked.CopyFilters(AlvysDeduction);
        Unlinked.SetRange("Statement No.", 0);
        Unlinked.SetFilter("Owner Operator Id", '<>%1', '');
        if not Unlinked.FindSet() then
            exit;
        repeat
            DeductionDate := Unlinked.Date;
            if DeductionDate = 0D then
                DeductionDate := WorkDate();
            if not EarliestDates.Get(Unlinked."Owner Operator Id", EarliestDate) or (DeductionDate < EarliestDate) then
                EarliestDates.Set(Unlinked."Owner Operator Id", DeductionDate);
        until Unlinked.Next() = 0;

        foreach OwnerOperatorId in EarliestDates.Keys() do
            CollectStatements(OwnerOperatorId, EarliestDates.Get(OwnerOperatorId), Statements);
        MatchStatements(Unlinked, Statements);
    end;

    /// <summary>
    /// A statement's date is the end of the pay period it was generated for, which is chosen when it
    /// is generated and bears no fixed relation to the deduction's date: a statement dated nine
    /// months before the deduction it paid has been seen, and one dated weeks ahead of the day it
    /// was generated. So the range is wide on both sides, and kept affordable by asking for one
    /// owner operator's statements at a time.
    /// </summary>
    local procedure CollectStatements(OwnerOperatorId: Text; EarliestDeductionDate: Date; var Statements: JsonArray)
    var
        ResponseObj: JsonObject;
        ItemsArray: JsonArray;
        JsonTkn: JsonToken;
        ErrorText: Text;
        PageNo, Read, Total : Integer;
    begin
        repeat
            if not AlvysSalesMgt.SearchDriverStatements(OwnerOperatorId, CalcDate('<-1Y>', EarliestDeductionDate), CalcDate('<+1Y>', Today()), PageNo, SearchPageSize(), ResponseObj, ErrorText) then begin
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
                Statements.Add(JsonTkn);
                Read += 1;
            end;
            PageNo += 1;
        until Read >= Total;
    end;

    /// <summary>
    /// A statement line does not carry the Id of the deduction it paid, only its description and
    /// amount, so that is what a deduction is matched on, within its own owner operator's
    /// statements. The description names the posted invoice, and a part of a split adds its
    /// "(part n)" to it, so it tells deductions apart; the amount guards against a description
    /// edited to match another. A line is used for one deduction only.
    /// </summary>
    internal procedure MatchStatements(var AlvysDeduction: Record "BAASI Alvys Deduction"; var Statements: JsonArray)
    var
        Unlinked: Record "BAASI Alvys Deduction";
        StatementObj, DriverObj, LineObj, SubLineObj, AmountObj : JsonObject;
        StatementTkn, LineTkn, SubLineTkn, JsonTkn : JsonToken;
        LineKeys: List of [Text];
        StatementNos: List of [Integer];
        StatementDates: List of [Date];
        Used: List of [Boolean];
        EntryNos: List of [Integer];
        DriverId: Text;
        StatementNo, EntryNo, i : Integer;
        StatementDate: Date;
    begin
        foreach StatementTkn in Statements do begin
            StatementObj := StatementTkn.AsObject();
            StatementNo := JsonMgt.GetJsonValueAsInteger(StatementObj, 'Number');
            DriverId := '';
            if StatementObj.Get('Driver', JsonTkn) then begin
                DriverObj := JsonTkn.AsObject();
                DriverId := JsonMgt.GetJsonValueAsText(DriverObj, 'Id');
            end;
            if (StatementNo <> 0) and Evaluate(StatementDate, JsonMgt.GetJsonValueAsText(StatementObj, 'StatementDate'), 9) then
                if StatementObj.Get('LineItems', JsonTkn) then
                    foreach LineTkn in JsonTkn.AsArray() do begin
                        LineObj := LineTkn.AsObject();
                        if LineObj.Get('SubLines', JsonTkn) then
                            foreach SubLineTkn in JsonTkn.AsArray() do begin
                                SubLineObj := SubLineTkn.AsObject();
                                if SubLineObj.Get('Amount', JsonTkn) then begin
                                    AmountObj := JsonTkn.AsObject();
                                    LineKeys.Add(StatementLineKey(DriverId, JsonMgt.GetJsonValueAsText(SubLineObj, 'Description'), JsonMgt.GetJsonValueAsDecimal(AmountObj, 'Amount')));
                                    StatementNos.Add(StatementNo);
                                    StatementDates.Add(StatementDate);
                                    Used.Add(false);
                                end;
                            end;
                    end;
        end;
        if LineKeys.Count() = 0 then
            exit;

        // Gathered first: linking one takes it out of the Statement No. filter being read.
        Unlinked.CopyFilters(AlvysDeduction);
        Unlinked.SetRange("Statement No.", 0);
        if Unlinked.FindSet() then
            repeat
                EntryNos.Add(Unlinked."Entry No.");
            until Unlinked.Next() = 0;

        foreach EntryNo in EntryNos do
            if Unlinked.Get(EntryNo) then
                for i := 1 to LineKeys.Count() do
                    if not Used.Get(i) then
                        if LineKeys.Get(i) = StatementLineKey(Unlinked."Owner Operator Id", Unlinked.Description, Unlinked.Amount) then begin
                            Used.Set(i, true);
                            Unlinked."Statement No." := StatementNos.Get(i);
                            Unlinked."Statement Date" := StatementDates.Get(i);
                            Unlinked.Modify(true);
                            break;
                        end;
    end;

    local procedure StatementLineKey(DriverId: Text; Description: Text; Amount: Decimal): Text
    begin
        exit(UpperCase(DriverId) + '|' + Description.Trim() + '|' + Format(Amount, 0, 9));
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
        AlvysSalesMgt.PrepareFailedSettlementEntry(AlvysEntry, AlvysDeduction, SettlementDate(AlvysDeduction), ErrorText, ErrorStack, 'GET', 'deductions/search');
        AlvysSalesMgt.InsertSettlementEntry(AlvysEntry);
        Commit();
    end;

    /// <summary>
    /// Only a settlement that went through is marked applied; one that did not is left for the next
    /// run to try again.
    /// </summary>
    internal procedure ApplySettledDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction"): Text
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareApplyDeductionEntry(AlvysEntry, AlvysDeduction, SettlementDate(AlvysDeduction), 'GET', 'deductions/search');
        AlvysSalesMgt.InsertSettlementEntry(AlvysEntry);

        exit(AlvysEntry."Error Message");
    end;

    /// <summary>
    /// The date the payment posts on: the date of the statement that paid the deduction, or the work
    /// date of the run applying it when no statement lists it. Never earlier than the invoice,
    /// though: Business Central will not apply a payment to an invoice posted after it, and a
    /// statement can be generated for a pay period that ended before the invoice was posted.
    /// </summary>
    local procedure SettlementDate(var AlvysDeduction: Record "BAASI Alvys Deduction") PostingDate: Date
    var
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        PostingDate := AlvysDeduction."Statement Date";
        if PostingDate = 0D then
            PostingDate := WorkDate();
        if SalesInvHeader.Get(AlvysDeduction."Posted Document No.") then
            if PostingDate < SalesInvHeader."Posting Date" then
                PostingDate := SalesInvHeader."Posting Date";
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
