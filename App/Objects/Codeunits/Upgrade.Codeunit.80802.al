codeunit 80802 "BAASI Upgrade"
{
    Subtype = Upgrade;

    trigger OnUpgradePerCompany()
    var
        Install: Codeunit "BAASI Install";
    begin
        Install.RunInstallCode();
    end;
}