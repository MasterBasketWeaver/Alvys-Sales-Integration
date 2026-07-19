codeunit 80803 "BAASI Subscribers"
{
    Permissions = tabledata "BAASI Alvys Deduction" = RIMD;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnBeforeInsertInvoiceHeader, '', false, false)]
    local procedure SalesPostOnBeforeInsertInvoiceHeader(var SalesInvHeader: Record "Sales Invoice Header"; SalesHeader: Record "Sales Header")
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
    begin
        AlvysDeduction.SetRange("Document Type", SalesHeader."Document Type");
        AlvysDeduction.SetRange("Document No.", SalesHeader."No.");
        AlvysDeduction.SetRange("Posted Document No.", '');
        if AlvysDeduction.FindSet() then
            repeat
                AlvysDeduction."Posted Document No." := SalesInvHeader."No.";
                AlvysDeduction.Modify(true);
            until AlvysDeduction.Next() = 0;
    end;
}
