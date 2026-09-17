codeunit 80801 "BAASI Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    begin
        RunInstallCode();
    end;

    procedure RunInstallCode()
    begin
        // DeleteSuccessfulSearchEntries();
        InitDeductionPaymentAmounts();
    end;

    /// <summary>
    /// Deductions logged before the Remaining Amount was kept. Every deduction now starts with its
    /// Remaining Amount equal to its Amount and reaches zero only by being applied, so one left at
    /// zero and not applied predates the field. Safe to run on every upgrade.
    /// </summary>
    local procedure InitDeductionPaymentAmounts()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        AlvysDeduction.SetFilter(Amount, '<>%1', 0);
        AlvysDeduction.SetRange("Remaining Amount", 0);
        AlvysDeduction.SetRange("Settlement Applied", false);
        if AlvysDeduction.FindSet(true) then
            repeat
                AlvysDeduction."Remaining Amount" := AlvysDeduction.Amount;
                AlvysDeduction.Modify();
            until AlvysDeduction.Next() = 0;
    end;

    /// <summary>
    /// The settlement poll used to log every deductions/search call. It now logs only the ones that
    /// fail, so the successful entries it left behind are cleared.
    /// </summary>
    local procedure DeleteSuccessfulSearchEntries()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        AlvysEntry.SetRange(Direction, AlvysEntry.Direction::Outbound);
        AlvysEntry.SetRange(URL, SearchURLTok);
        AlvysEntry.SetRange("Error Message", '');
        if AlvysEntry.IsEmpty() then
            exit;
        if not AlvysEntry.Truncate() then
            AlvysEntry.DeleteAll();
    end;

    var
        SearchURLTok: Label 'https://integrations.alvys.com/api/p/v1.0/deductions/search', Locked = true;
}
