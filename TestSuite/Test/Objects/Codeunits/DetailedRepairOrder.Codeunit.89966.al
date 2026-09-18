codeunit 89966 "BAASIT Detailed Repair Order"
{
    // Produces one busy repair order to look at in Business Central: created in Fleetrock with a
    // task per repair and several parts on each, invoiced there, imported, and posted. It is the
    // seed phase of the chained run without the Alvys leg or its assertions, for when someone
    // wants a posted invoice with a lot on it rather than a test.

    /// <summary>
    /// Runs the whole thing and hands back the repair order, the invoice it was imported as and the
    /// invoice it posted to. Auto-posting is turned off for the import so the location the sandbox
    /// insists on can be set before posting, and the company's own setting is put back after.
    /// </summary>
    procedure Create(TaskCount: Integer; PartsPerTask: Integer; var ROId: Text; var InvoiceNo: Code[20]; var PostedInvoiceNo: Code[20])
    begin
        Create(UnitNumberTok, TaskCount, PartsPerTask, ROId, InvoiceNo, PostedInvoiceNo);
    end;

    /// <summary>
    /// The same, for a named Fleetrock unit rather than the one the chained run uses. The unit is
    /// named by its unit number -- what the tractor code dimension and the Alvys truck carry -- and
    /// the VIN AddRO wants is looked up from it.
    /// </summary>
    procedure Create(UnitNumber: Text; TaskCount: Integer; PartsPerTask: Integer; var ROId: Text; var InvoiceNo: Code[20]; var PostedInvoiceNo: Code[20])
    var
        FleetrockSetup: Record "FRI Fleetrock Setup";
        JobQueueEntry: Record "Job Queue Entry";
        SalesInvHeader: Record "Sales Invoice Header";
        GetRepairOrders: Codeunit "FRI Get Repair Orders";
        ThreeDays: Duration;
        OriginalAutoPost: Boolean;
    begin
        ROId := ROHelper.CreateDetailedRepairOrder(ROHelper.GetUnitVin(UnitNumber), TaskCount, PartsPerTask);
        ROHelper.WaitForRepairOrderDetail(ROId, TaskCount, PartsPerTask);
        ROHelper.SetRepairOrderToInvoiced(ROId);
        ROHelper.WaitForInvoicedDate(ROId);

        FleetrockSetup.Get();
        OriginalAutoPost := FleetrockSetup."Auto-post Repair Orders";
        if OriginalAutoPost then begin
            FleetrockSetup."Auto-post Repair Orders" := false;
            FleetrockSetup.Modify();
        end;

        JobQueueEntry.Init();
        JobQueueEntry."Parameter String" := InvoicedTok;
        ThreeDays := 3 * 24 * 60 * 60 * 1000;
        GetRepairOrders.SetStartDateTime(CurrentDateTime() - ThreeDays);
        GetRepairOrders.Run(JobQueueEntry);

        if OriginalAutoPost then begin
            FleetrockSetup.Get();
            FleetrockSetup."Auto-post Repair Orders" := OriginalAutoPost;
            FleetrockSetup.Modify();
        end;
        Commit();

        InvoiceNo := PostImportedInvoice(ROId);

        SalesInvHeader.SetRange("FRI Fleetrock Repair Order No.", ROId);
        if not SalesInvHeader.FindFirst() then
            Error(NoPostedInvoiceErr, ROId, ROHelper.GetStagingError(ROId));
        PostedInvoiceNo := SalesInvHeader."No.";
    end;

    /// <summary>
    /// Posts the imported invoice the way codeunit "BAASIT Alvys Poll E2E Tests" does, including the
    /// TEST location another app in the sandbox insists on, set without validation so the asset
    /// dimension the import placed on the document survives.
    /// </summary>
    local procedure PostImportedInvoice(ROId: Text) InvoiceNo: Code[20]
    var
        SalesHeader: Record "Sales Header";
        SalesLine: Record "Sales Line";
    begin
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Invoice);
        SalesHeader.SetRange("FRI Fleetrock Repair Order No.", ROId);
        if not SalesHeader.FindFirst() then
            Error(NoInvoiceErr, ROId, ROHelper.GetStagingError(ROId));
        InvoiceNo := SalesHeader."No.";

        SalesHeader."Location Code" := LocationTok;
        SalesHeader.Modify(true);
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Invoice);
        SalesLine.SetRange("Document No.", InvoiceNo);
        SalesLine.SetRange(Type, SalesLine.Type::"G/L Account");
        if SalesLine.FindSet(true) then
            repeat
                SalesLine."Location Code" := LocationTok;
                SalesLine.Modify(true);
            until SalesLine.Next() = 0;

        // The import left a write transaction open and posting cannot start inside one.
        Commit();
        if not Codeunit.Run(Codeunit::"Sales-Post", SalesHeader) then
            Error(PostingFailedErr, InvoiceNo, GetLastErrorText());
    end;

    var
        ROHelper: Codeunit "BAASIT Fleetrock RO Helper";

        UnitNumberTok: Label '567', Locked = true;
        LocationTok: Label 'TEST', Locked = true;
        InvoicedTok: Label 'invoiced', Locked = true;
        NoInvoiceErr: Label 'No sales invoice was created for repair order %1.%2', Comment = '%1 = Repair Order Id, %2 = staging error';
        NoPostedInvoiceErr: Label 'No posted sales invoice was found for repair order %1.%2', Comment = '%1 = Repair Order Id, %2 = staging error';
        PostingFailedErr: Label 'Posting invoice %1 failed: %2', Comment = '%1 = Sales Invoice No., %2 = the posting error';
}
