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
                field("Group Id"; Rec."Group Id") { }
                field(Type; Rec.Type) { }
                field(Description; Rec.Description) { }
                field(Category; Rec.Category) { }
                field(Amount; Rec.Amount) { }
                field("Remaining Amount"; Rec."Remaining Amount")
                {
                    trigger OnDrillDown()
                    var
                        SplitPart: Record "BAASI Alvys Deduction";
                    begin
                        SplitPart.SetRange("Split From Entry No.", Rec."Entry No.");
                        SplitPart.SetRange("Is Paid", true);
                        if SplitPart.IsEmpty() then
                            exit;
                        Page.Run(Page::"BAASI Alvys Deductions", SplitPart);
                    end;
                }
                field("Split in Alvys"; Rec."Split in Alvys") { }
                field("Split From Entry No."; Rec."Split From Entry No.")
                {
                    BlankZero = true;

                    trigger OnDrillDown()
                    var
                        SplitDeduction: Record "BAASI Alvys Deduction";
                    begin
                        if SplitDeduction.Get(Rec."Split From Entry No.") then
                            Page.Run(Page::"BAASI Alvys Deductions", SplitDeduction);
                    end;
                }
                field("Currency Id"; Rec."Currency Id") { }
                field("Truck Id"; Rec."Truck Id") { }
                field("Truck Number"; Rec."Truck Number") { }
                field("Driver Id"; Rec."Driver Id") { }
                field("Owner Operator Id"; Rec."Owner Operator Id") { }
                field(Date; Rec.Date) { }
                field("Is Paid"; Rec."Is Paid") { }
                field("Statement No."; Rec."Statement No.") { }
                field("Statement Date"; Rec."Statement Date") { }
                field("Settlement Applied"; Rec."Settlement Applied") { }
                field("Settlement Applied At"; Rec."Settlement Applied At") { }
                field("Settlement Posted"; Rec."Settlement Posted") { }
                field("Posted DateTime"; Rec."Posted DateTime") { }
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
                Tooltip = 'Creates a journal line applying a deduction Alvys has paid to its posted sales invoice, dated on the Alvys statement that paid it, or on the work date if no statement lists it. If auto-post has been configured in the Alvys Sales Setup table then it will also post the newly created journal line.';
                Image = Payment;
                ApplicationArea = All;

                trigger OnAction()
                var
                    AlvysSalesSetup: Record "BAASI Alvys Sales Setup";
                    AlvysDeduction: Record "BAASI Alvys Deduction";
                    GenJnlLine: Record "Gen. Journal Line";
                    AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
                    ErrorText, LineAction : Text;
                    NewLine, IsHandled : Boolean;
                begin
                    Rec.TestField("Is Paid", true);
                    // A split deduction no longer exists in Alvys; its parts carry the settlement.
                    Rec.TestField("Split in Alvys", false);
                    Rec.TestField("Settlement Posted", false);
                    Rec.TestField("Posted Document No.");

                    GenJnlLine.SetRange("BAASI Alvys Deduction Id", Rec."Id");
                    NewLine := GenJnlLine.IsEmpty();

                    if Rec."Statement No." = 0 then begin
                        AlvysDeduction.SetRange("Entry No.", Rec."Entry No.");
                        AlvysSettlementPoll.LinkStatements(AlvysDeduction);
                        Rec.Get(Rec."Entry No.");
                    end;
                    ErrorText := AlvysSettlementPoll.ApplySettledDeduction(Rec);
                    if ErrorText <> '' then
                        Error(ErrorText);

                    AlvysSalesSetup.Get();
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

        LineUpdatedMsg: Label '%1 line %2 in batch %3', Comment = '%1 = Line Action, %2 = Line No., %3 = Journal Batch Name';
        InsertedLbl: Label 'Inserted';
        UpdatedLbl: Label 'Updated';
}
