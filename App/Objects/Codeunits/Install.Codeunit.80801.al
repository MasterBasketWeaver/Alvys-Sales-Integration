codeunit 80801 "BAASI Install"
{
    Subtype = Install;

    trigger OnInstallAppPerCompany()
    begin
        RunInstallCode();
    end;

    procedure RunInstallCode()
    begin

    end;
}