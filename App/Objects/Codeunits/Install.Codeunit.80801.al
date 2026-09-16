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
