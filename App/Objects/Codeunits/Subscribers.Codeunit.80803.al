codeunit 80803 "BAASI Subscribers"
{
    /// <summary>
    /// Pushes a posted sales invoice to Alvys as a one-time truck deduction. The deduction is
    /// created once the posting has produced the invoice, so it carries both the document it was
    /// posted from and the posted invoice it ended up on.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterPostSalesDoc, '', false, false)]
    local procedure SalesPostOnAfterPostSalesDoc(var SalesHeader: Record "Sales Header"; SalesInvHdrNo: Code[20]; PreviewMode: Boolean)
    var
        SalesInvHeader: Record "Sales Invoice Header";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
    begin
        // A posting run does not always produce an invoice -- a shipment or a credit memo leaves the
        // invoice number blank -- and a preview is rolled back, so neither may reach Alvys.
        if PreviewMode or (SalesInvHdrNo = '') then
            exit;
        if not SalesInvHeader.Get(SalesInvHdrNo) then
            exit;

        // Alvys deductions are negative: the invoice is deducted from the owner operator's pay.
        SalesInvHeader.CalcFields("Amount Including VAT");
        AlvysSalesMgt.CreateDeductionForTruck(SalesHeader, SalesInvHeader, SalesInvHeader."Posting Date", -SalesInvHeader."Amount Including VAT", CategoryTok, StrSubstNo(DescriptionTxt, SalesInvHeader."No."));
    end;

    var
        CategoryTok: Label 'Owner Operator Invoice', Locked = true;
        DescriptionTxt: Label 'BC Invoice %1', Comment = '%1 = Posted Sales Invoice No.';
}
