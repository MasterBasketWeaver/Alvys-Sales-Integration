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
        AlvysDeduction.SetRange(Posted, false);
        while AlvysDeduction.FindFirst() do begin
            AlvysDeduction."Document Type" := AlvysDeduction."Document Type"::Invoice;
            AlvysDeduction."Document No." := SalesInvHeader."No.";
            AlvysDeduction.Posted := true;
            AlvysDeduction.Modify(true);
        end;
    end;
}
