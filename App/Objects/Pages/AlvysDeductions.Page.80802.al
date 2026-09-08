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
                        SalesInvHeader: Record "Sales Invoice Header";
                    begin
                        if Rec."Posted Document No." <> '' then begin
                            if SalesInvHeader.Get(Rec."Posted Document No.") then
                                Page.Run(Page::"Posted Sales Invoice", SalesInvHeader);
                        end else
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
                        if SalesInvHeader.Get(Rec."Posted Document No.") then
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
                Tooltip = 'Checks if the Deduction has been paid in Alvys, and if so creates a journal line to apply the deduction payment to related Posted Sales Invoice. IF auto-post has been configured in the Alvys Sales Setup table then it will also post the newly created journal line.';
                Image = Payment;
                ApplicationArea = All;

                trigger OnAction()
                var
                    AlvysSalesSetup: Record "BAASI Alvys Sales Setup";
                    GenJnlLine: Record "Gen. Journal Line";
                    AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
                    ErrorText, LineAction : Text;
                    NewLine, IsHandled : Boolean;
                begin
                    Rec.TestField("Is Paid", true);
                    Rec.TestField("Settlement Applied", false);
                    Rec.TestField("Posted Document No.");

                    GenJnlLine.SetRange("BAASI Alvys Deduction Id", Rec."Id");
                    NewLine := GenJnlLine.IsEmpty();

                    ErrorText := AlvysSettlementPoll.ApplySettledDeduction(Rec);
                    if ErrorText <> '' then
                        Error(ErrorText);

                    if not AlvysSalesSetup."Auto-Post Deductions" then begin
                        GenJnlLine.SetRange("BAASI Alvys Deduction Id", Rec."Id");
                        GenJnlLine.FindFirst();
                        if NewLine then
                            LineAction := InsertedLbl
                        else
                            LineAction := UpdatedLbl;

                        OnBeforeDisplaySettlementMessage(IsHandled, GenJnlLine, LineAction);
                        if not IsHandled then
                            Message(LineUpdatedMsg, LineAction, GenJnlLine."Line No.", GenJnlLine."Journal Batch Name");

                        // RecRef.GetTable(GenJnlLine);
                        // if RecRef.FieldExist(70210826) then
                        //     Message(MEMLineUpdatedMsg, LineAction, GenJnlLine."Line No.", GenJnlLine."Journal Batch Name", RecRef.Field(70210826).Value())
                        // else
                    end;
                end;
            }
        }
        area(Promoted)
        {
            actionref("Apply Settled Deduction Promoted"; "Apply Settled Deduction") { }
        }
    }


    [BusinessEvent(false, false)]
    local procedure OnBeforeDisplaySettlementMessage(var IsHandled: Boolean; var GenJnlLine: Record "Gen. Journal Line"; LineAction: Text)
    begin
    end;


    var
        MEMLineUpdatedMsg: Label '%1 line %2 in batch %3, Entity %4', Comment = '%1 = Line Action, %2 = Line No., %3 = Journal Batch Name, %4 = Entity';
        LineUpdatedMsg: Label '%1 line %2 in batch %3', Comment = '%1 = Line Action, %2 = Line No., %3 = Journal Batch Name';
        InsertedLbl: Label 'Inserted';
        UpdatedLbl: Label 'Updated';
}
