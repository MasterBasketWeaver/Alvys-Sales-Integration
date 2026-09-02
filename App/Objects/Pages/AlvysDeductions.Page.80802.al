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
                field("Truck Number"; Rec."Truck Number") { }
                field("Driver Id"; Rec."Driver Id") { }
                field(Date; Rec.Date) { }
                field("Is Paid"; Rec."Is Paid") { }
                field("Settlement Applied"; Rec."Settlement Applied") { }
                field("Settlement Applied At"; Rec."Settlement Applied At") { }
                field("Document Type"; Rec."Document Type") { }
                field("Document No."; Rec."Document No.")
                {
                    trigger OnDrillDown()
                    var
                        SalesHeader: Record "Sales Header";
                    begin
                        Case Rec."Document Type" of
                            Rec."Document Type"::"Sales Invoice":
                                if SalesHeader.Get(Enum::"Sales Document Type"::Invoice, Rec."Document No.") then
                                    Page.Run(Page::"Sales Invoice", SalesHeader);
                            Rec."Document Type"::"Sales Order":
                                if SalesHeader.Get(Enum::"Sales Document Type"::Order, Rec."Document No.") then
                                    Page.Run(Page::"Sales Order", SalesHeader);
                        End;
                    end;
                }
                field("Posted Document No."; Rec."Posted Document No.")
                {
                    trigger OnDrillDown()
                    var
                        SalesInvHeader: Record "Sales Invoice Header";
                    begin
                        if SalesInvHeader.Get(Rec."Document No.") then
                            Page.Run(Page::"Posted Sales Invoice", SalesInvHeader);
                    end;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action("Apply Settled Deduction")
            {
                Caption = 'Apply Settled Deduction';
                Tooltip = 'Manually create and post a journal line to apply the deduction payment to related Posted Sales Invoice.';
                Image = Payment;
                ApplicationArea = All;

                trigger OnAction()
                var
                    AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
                    ErrorText: Text;
                begin
                    Rec.TestField("Is Paid", true);
                    Rec.TestField("Settlement Applied", false);
                    Rec.TestField("Posted Document No.");
                    ErrorText := AlvysSettlementPoll.ApplySettledDeduction(Rec);
                    if ErrorText <> '' then
                        Error(ErrorText);
                end;
            }
        }
        area(Promoted)
        {
            actionref("Apply Settled Deduction Promoted"; "Apply Settled Deduction") { }
        }
    }
}
