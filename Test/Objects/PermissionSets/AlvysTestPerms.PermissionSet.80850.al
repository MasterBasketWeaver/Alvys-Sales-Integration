permissionset 80850 "BAASIT Test Perms."
{
    Caption = 'Alvys Sales Integration Test Permissions';
    Assignable = true;
    Permissions = tabledata "BAASIT Test Result" = RIMD,
        table "BAASIT Test Result" = X,
        page "BAASIT Alvys Test Results" = X,
        codeunit "BAASIT Alvys Sales Tests" = X,
        codeunit "BAASIT Alvys Test Runner" = X;
}
