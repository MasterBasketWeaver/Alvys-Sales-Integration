permissionset 80800 "BAASI Alvys Perms."
{
    Caption = 'Alvys Sales Permissions';
    Assignable = true;
    Permissions = tabledata "BAASI Alvys Sales Entry" = RIMD,
        tabledata "BAASI Alvys Sales Setup" = RIMD,
        table "BAASI Alvys Sales Entry" = X,
        table "BAASI Alvys Sales Setup" = X,
        page "BAASI Alvys Sales Entries" = X,
        page "BAASI Alvys Sales Setup" = X,
        codeunit "BAASI Alvys Sales Mgt." = X,
        codeunit "BAASI Install" = X,
        codeunit "BAASI Subscribers" = X,
        codeunit "BAASI Upgrade" = X,
        codeunit "BAAPI Json Mgt." = X,
        codeunit "BAAPI REST API Mgt." = X;
}