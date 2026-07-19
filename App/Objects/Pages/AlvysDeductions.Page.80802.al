page 80802 "BAASI Alvys Deductions"
{
    SourceTable = "BAASI Alvys Deduction";
    ApplicationArea = all;
    UsageCategory = Lists;
    Caption = 'Alvys Deductions';
    Editable = false;
    LinksAllowed = false;
    AnalysisModeEnabled = false;
    PageType = List;
    SourceTableView = sorting("Entry No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Deductions)
            {
                field("Entry No."; Rec."Entry No.") { }
                field(Id; Rec.Id) { }
                field(Type; Rec.Type) { }
                field(Description; Rec.Description) { }
                field(Category; Rec.Category) { }
                field(Amount; Rec.Amount) { }
                field("Currency Code"; Rec."Currency Code") { }
                field("Truck Id"; Rec."Truck Id") { }
                field("Driver Id"; Rec."Driver Id") { }
                field(Date; Rec.Date) { }
                field("Is Paid"; Rec."Is Paid") { }
                field("Created At"; Rec."Created At") { }
                field("Created By"; Rec."Created By") { }
                field("Document Type"; Rec."Document Type") { }
                field("Document No."; Rec."Document No.") { }
                field("Posted Document No."; Rec."Posted Document No.") { }
            }
        }
    }
}
