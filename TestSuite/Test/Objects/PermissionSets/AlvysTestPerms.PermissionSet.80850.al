permissionset 80850 "BAASIT Test Perms."
{
    Caption = 'Alvys Sales Integration Test Permissions';
    Assignable = true;
    Permissions = tabledata "BAASIT Test Result" = RIMD,
        tabledata "BAASIT Test Run" = RIMD,
        tabledata "BAASI Alvys Sales Entry" = RD,
        tabledata "BAASI Alvys Deduction" = RID,
        tabledata "Sales Invoice Header" = R,
        table "BAASIT Test Result" = X,
        table "BAASIT Test Run" = X,
        page "BAASIT Alvys Test Results" = X,
        page "BAASIT Alvys Test Run API" = X,
        page "BAASIT Alvys Test Result API" = X,
        page "BAASIT Alvys Entry Cleanup API" = X,
        page "BAASIT Alvys Ded. Seed API" = X,
        codeunit "BAASIT Alvys Sales Tests" = X,
        codeunit "BAASIT Fleetrock E2E Tests" = X,
        codeunit "BAASIT Alvys Test Runner" = X,
        codeunit "BAASIT Test Runner No Rollback" = X,
        codeunit "BAASIT Test Mode" = X,
        codeunit "BAASIT Test Run Mgt." = X;
}
