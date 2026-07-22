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
                field("Created At"; Rec.SystemCreatedAt) { }
                field("Created By"; Rec."Created By") { }
                field("Alvys Created At"; Rec."Alvys Created At") { }
                field("Alvys Created By"; Rec."Alvys Created By") { }
                field(Id; Rec.Id) { }
                field(Type; Rec.Type) { }
                field(Description; Rec.Description) { }
                field(Category; Rec.Category) { }
                field(Amount; Rec.Amount) { }
                field("Currency Id"; Rec."Currency Id") { }
                field("Truck Id"; Rec."Truck Id") { }
                field("Driver Id"; Rec."Driver Id") { }
                field(Date; Rec.Date) { }
                field("Is Paid"; Rec."Is Paid") { }
                field("Document Type"; Rec."Document Type") { }
                field("Document No."; Rec."Document No.") { }
                field("Posted Document No."; Rec."Posted Document No.") { }
            }
        }
    }
}
