permissionset 80800 "BAASI Alvys Perms."
{
    Caption = 'Alvys Sales Permissions';
    Assignable = true;
    Permissions = tabledata "BAASI Alvys Sales Entry" = RIMD,
        tabledata "BAASI Alvys Sales Setup" = RIMD,
        tabledata "BAASI Alvys Deduction" = RIMD,
        tabledata "Gen. Journal Template" = R,
        tabledata "Gen. Journal Batch" = R,
        tabledata "Gen. Journal Line" = RIMD,
        table "BAASI Alvys Sales Entry" = X,
        table "BAASI Alvys Sales Setup" = X,
        table "BAASI Alvys Deduction" = X,
        page "BAASI Alvys Sales Entries" = X,
        page "BAASI Alvys Sales Setup" = X,
        page "BAASI Alvys Deductions" = X,
        page "BAASI Alvys Apply Ded. API" = X,
        codeunit "BAASI Alvys Sales Mgt." = X,
        codeunit "BAASI Install" = X,
        codeunit "BAASI Subscribers" = X,
        codeunit "BAASI Upgrade" = X,
        codeunit "BAAPI Json Mgt." = X,
        codeunit "BAAPI REST API Mgt." = X,
        codeunit "Gen. Jnl.-Post Batch" = X;
}
