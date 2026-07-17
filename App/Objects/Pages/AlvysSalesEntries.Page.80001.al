page 80801 "BAASI Alvys Sales Entries"
{
    SourceTable = "BAASI Alvys Sales Entry";
    ApplicationArea = all;
    UsageCategory = Administration;
    Caption = 'Alvys Sales Entries';
    Editable = false;
    LinksAllowed = false;
    AnalysisModeEnabled = false;
    PageType = List;
    SourceTableView = sorting("Entry No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Entries)
            {
                field("Entry No."; Rec."Entry No.") { }
            }
        }
    }
}