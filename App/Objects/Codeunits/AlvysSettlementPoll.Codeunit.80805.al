codeunit 80805 "BAASI Alvys Settlement Poll"
{
    // Alvys has no driver pay webhook event and no settlement resource in the public API, so a
    // settlement can only be found by looking: the IsPaid flag on the deduction turning over is the
    // whole signal. This does by polling what page 80803 does when Alvys posts a settlement in.

    Permissions = tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RIMD;

    trigger OnRun()
    begin
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
        PendingIds: Dictionary of [Text, Integer];
        PaidIds: List of [Text];
        DeductionId: Text;
        EntryNo: Integer;
        EarliestDate, LatestDate : Date;
    begin
        AlvysDeduction.SetRange("Is Paid", false);
        AlvysDeduction.SetFilter("Posted Document No.", '<>%1', '');
        AlvysDeduction.SetFilter(Id, '<>%1', '');
        // A dateless deduction taken as a bound would collapse the range and stop the ones
        // that do carry a date from being asked about at all.
        AlvysDeduction.SetFilter(Date, '<>%1', 0D);
        if not AlvysDeduction.FindSet() then
            exit;

        PendingIds.Set(SearchKey(AlvysDeduction.Id), AlvysDeduction."Entry No.");
        EarliestDate := AlvysDeduction.Date;
        LatestDate := AlvysDeduction.Date;
        if AlvysDeduction.Next() <> 0 then
            repeat
                PendingIds.Set(SearchKey(AlvysDeduction.Id), AlvysDeduction."Entry No.");
                if AlvysDeduction.Date < EarliestDate then
                    EarliestDate := AlvysDeduction.Date;
                if AlvysDeduction.Date > LatestDate then
                    LatestDate := AlvysDeduction.Date;
            until AlvysDeduction.Next() = 0;

        if EarliestDate = 0D then
            exit;

        CollectPaidIds(EarliestDate, LatestDate, PaidIds);

        foreach DeductionId in PaidIds do
            if PendingIds.Get(DeductionId, EntryNo) then
                if AlvysDeduction.Get(EntryNo) then begin
                    AlvysDeduction."Is Paid" := true;
                    AlvysDeduction.Modify(true);
                end;
    end;

    /// <summary>
    /// The search takes no Id filter, so the date range is what narrows it and the caller matches
    /// the Ids it gets back against the deductions it was asking about.
    /// </summary>
    local procedure CollectPaidIds(EarliestDate: Date; LatestDate: Date; var PaidIds: List of [Text])
    var
        ItemObj, ResponseObj : JsonObject;
        ItemsArray: JsonArray;
        JsonTkn: JsonToken;
        DeductionId: Text;
        PageNo, Read, Total : Integer;
    begin
        repeat
            ResponseObj := AlvysSalesMgt.SearchDeductions(EarliestDate, LatestDate, true, PageNo, SearchPageSize());
            if not ResponseObj.Get('Items', JsonTkn) then
                exit;
            ItemsArray := JsonTkn.AsArray();
            if ItemsArray.Count() = 0 then
                exit;
            Total := JsonMgt.GetJsonValueAsInteger(ResponseObj, 'Total');
            foreach JsonTkn in ItemsArray do begin
                ItemObj := JsonTkn.AsObject();
                Read += 1;
                if JsonMgt.GetJsonValueAsBoolean(ItemObj, 'IsPaid') then begin
                    DeductionId := JsonMgt.GetJsonValueAsText(ItemObj, 'Id');
                    if DeductionId <> '' then
                        PaidIds.Add(SearchKey(DeductionId));
                end;
            end;
            PageNo += 1;
        until Read >= Total;
    end;

    local procedure ApplySettledDeductions()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        EntryNos: List of [Integer];
        EntryNo: Integer;
    begin
        AlvysDeduction.SetRange("Is Paid", true);
        AlvysDeduction.SetRange("Settlement Applied", false);
        AlvysDeduction.SetFilter("Posted Document No.", '<>%1', '');
        // Gathered before any is applied: applying one posts the batch when the setup asks for it,
        // and that commits underneath a record set still being read.
        if AlvysDeduction.FindSet() then
            repeat
                EntryNos.Add(AlvysDeduction."Entry No.");
            until AlvysDeduction.Next() = 0;

        foreach EntryNo in EntryNos do
            if AlvysDeduction.Get(EntryNo) then
                ApplySettledDeduction(AlvysDeduction);
    end;

    /// <summary>
    /// Alvys reports no paid date, settlement date or settlement Id against a settled deduction, so
    /// the payment posts under the work date of the run that found it. Only a settlement that went
    /// through is marked applied; one that did not is left for the next run to try again.
    /// </summary>
    internal procedure ApplySettledDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction")
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareApplyDeductionEntry(
            AlvysEntry, AlvysDeduction.Id, AlvysDeduction."Truck Id", AlvysDeduction."Truck Number",
            AlvysDeduction.Amount, WorkDate(), AlvysDeduction.Description, PollMethodTok, PollURLTok);
        AlvysEntry.Insert(true);

        if AlvysEntry."Error Message" <> '' then
            exit;

        AlvysDeduction."Settlement Applied" := true;
        AlvysDeduction."Settlement Applied At" := CurrentDateTime();
        AlvysDeduction.Modify(true);
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
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        PollMethodTok: Label 'POLL', Locked = true;
        PollURLTok: Label 'deductions/search', Locked = true;
}
