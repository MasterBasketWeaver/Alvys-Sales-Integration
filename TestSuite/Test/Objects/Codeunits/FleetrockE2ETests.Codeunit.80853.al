codeunit 80853 "BAASIT Fleetrock E2E Tests"
{
    // [FEATURE] [Fleetrock Integration] [Alvys Sales Integration]
    //
    // End-to-end integration test across the live Fleetrock test tenant, Business Central and the
    // live Alvys API: a repair order is created and invoiced in Fleetrock, imported by the
    // Fleetrock Integration job queue codeunit, posted, and verified all the way to the truck
    // deduction in Alvys. Business Central data is rolled back when the test run ends, the
    // repair order is walked back from Invoiced and deleted in Fleetrock, and the deduction is
    // deleted from Alvys, so nothing accumulates in either tenant. When the suite runs through
    // the no-rollback runner (codeunit "BAASIT Test Runner No Rollback"), the external clean-up
    // is skipped too, so the documents can be inspected in all three systems afterwards.

    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure InvoicedRepairOrderIsImportedPostedAndDeducted()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        CustLedgEntry: Record "Cust. Ledger Entry";
        DimSetEntry: Record "Dimension Set Entry";
        GenJnlLine: Record "Gen. Journal Line";
        JobQueueEntry: Record "Job Queue Entry";
        RepairHeaderStaging: Record "FRI Repair Header";
        SalesHeader: Record "Sales Header";
        SalesInvHeader: Record "Sales Invoice Header";
        SalesLine: Record "Sales Line";
        GetRepairOrders: Codeunit "FRI Get Repair Orders";
        ROObj, ResponseObj, AmountObj : JsonObject;
        JsonTkn: JsonToken;
        ROId: Text;
        InvoiceNo: Code[20];
        ThreeDays: Duration;
    begin
        // [SCENARIO] A repair order created and invoiced in Fleetrock is imported by the invoiced
        // job as a sales invoice carrying the repair order's amounts and the unit's asset
        // dimension; posting the invoice succeeds and creates a truck deduction in both Business
        // Central and Alvys.
        Initialize();

        // [GIVEN] A repair order in Fleetrock for unit 567 with one task (2h x $75.00 labor) and
        // one part (2 x $27.50), so the grand total is $205.00
        ROId := ROHelper.CreateRepairOrder(UnitVinTok);

        // [GIVEN] The repair order is invoiced in Fleetrock as of yesterday
        ROHelper.SetRepairOrderToInvoiced(ROId);
        ROObj := ROHelper.GetRepairOrder(ROId);
        Assert.AreEqual('Invoiced', JsonMgt.GetJsonValueAsText(ROObj, 'status'), 'The repair order should be Invoiced in Fleetrock after the update.');
        Assert.AreEqual(205.0, JsonMgt.GetJsonValueAsDecimal(ROObj, 'grand_total'), 'The Fleetrock grand total should match the task and part amounts the order was created with.');
        Assert.AreEqual('567', JsonMgt.GetJsonValueAsText(ROObj, 'unit_number'), 'The repair order should be for unit 567.');

        // [WHEN] The invoiced import job runs over a window that covers the invoiced date
        JobQueueEntry.Init();
        JobQueueEntry."Parameter String" := 'invoiced';
        ThreeDays := 3 * 24 * 60 * 60 * 1000;
        GetRepairOrders.SetStartDateTime(CurrentDateTime() - ThreeDays);
        GetRepairOrders.Run(JobQueueEntry);

        // [THEN] A sales invoice was created for the repair order
        SalesHeader.SetRange("Document Type", SalesHeader."Document Type"::Invoice);
        SalesHeader.SetRange("FRI Fleetrock Repair Order No.", ROId);
        Assert.IsTrue(SalesHeader.FindFirst(), StrSubstNo('A sales invoice should have been created for repair order %1.%2', ROId, ROHelper.GetStagingError(ROId)));
        InvoiceNo := SalesHeader."No.";
        Assert.AreEqual(ROId, Format(SalesHeader."External Document No."), 'The repair order id should be carried as the external document number when the order has no PO number.');

        // The staging record carries the invoiced datetime shifted to the user's time zone, and
        // the posting date is derived from it, so the date is compared against the staging record
        // rather than recomputed here.
        RepairHeaderStaging.SetRange(id, ROId);
        Assert.IsTrue(RepairHeaderStaging.FindLast(), 'A staging record should exist for the imported repair order.');
        Assert.IsTrue(RepairHeaderStaging."Invoiced At" <> 0DT, 'The staging record should carry the invoiced datetime.');
        Assert.AreEqual(DT2Date(RepairHeaderStaging."Invoiced At"), SalesHeader."Posting Date", 'The posting date should be the date the repair order was invoiced in Fleetrock.');

        // [THEN] The invoice is for the customer the Fleetrock order belongs to
        Assert.AreEqual(GetFleetrockCustomerNo(), SalesHeader."Sell-to Customer No.", 'The invoice should be for the customer mapped to the Fleetrock customer account.');

        // [THEN] The invoice carries the unit number as the asset dimension
        Assert.IsTrue(DimSetEntry.Get(SalesHeader."Dimension Set ID", FleetrockSetup."Asset Dimension Code"), 'The invoice should carry the asset dimension.');
        Assert.AreEqual('567', Format(DimSetEntry."Dimension Value Code"), 'The asset dimension value should be the Fleetrock unit number.');

        // [THEN] The invoice has one labor line and one part line with the repair order's amounts
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Invoice);
        SalesLine.SetRange("Document No.", InvoiceNo);
        SalesLine.SetRange(Type, SalesLine.Type::"G/L Account");
        Assert.AreEqual(2, SalesLine.Count(), 'The invoice should have exactly one labor line and one part line.');
        SalesLine.SetRange("No.", FleetrockSetup."Labor G/L Account No.");
        Assert.IsTrue(SalesLine.FindFirst(), 'The invoice should have a labor line.');
        Assert.AreEqual(2.0, SalesLine.Quantity, 'The labor line quantity should be the labor hours.');
        Assert.AreEqual(75.0, SalesLine."Unit Price", 'The labor line unit price should be the hourly rate.');
        Assert.AreEqual(150.0, SalesLine."Line Amount", 'The labor line amount should be the labor subtotal.');
        SalesLine.SetRange("No.", FleetrockSetup."Parts G/L Account No.");
        Assert.IsTrue(SalesLine.FindFirst(), 'The invoice should have a part line.');
        Assert.AreEqual(2.0, SalesLine.Quantity, 'The part line quantity should be the part quantity.');
        Assert.AreEqual(27.5, SalesLine."Unit Price", 'The part line unit price should be the part price.');
        Assert.AreEqual(55.0, SalesLine."Line Amount", 'The part line amount should be the part subtotal.');

        // [THEN] The invoice totals match the Fleetrock repair order
        SalesHeader.CalcFields(Amount, "Amount Including VAT");
        Assert.AreEqual(205.0, SalesHeader.Amount, 'The invoice amount should match the repair order labor and part totals.');
        Assert.AreEqual(JsonMgt.GetJsonValueAsDecimal(ROObj, 'grand_total'), SalesHeader."Amount Including VAT", 'The invoice total should match the Fleetrock grand total.');

        // [GIVEN] The sandbox's TEST location on the header and lines: another app in the
        // environment requires a location to post, and the integration does not assign one.
        // The location is assigned without validation, because validating it rebuilds the
        // dimension sets from default dimensions and would wipe the asset dimension the
        // integration placed on the document.
        SalesHeader."Location Code" := 'TEST';
        SalesHeader.Modify(true);
        SalesLine.Reset();
        SalesLine.SetRange("Document Type", SalesLine."Document Type"::Invoice);
        SalesLine.SetRange("Document No.", InvoiceNo);
        SalesLine.SetRange(Type, SalesLine.Type::"G/L Account");
        SalesLine.FindSet(true);
        repeat
            SalesLine."Location Code" := 'TEST';
            SalesLine.Modify(true);
        until SalesLine.Next() = 0;

        // [WHEN] The invoice is posted. The import left a write transaction open, and posting
        // cannot start inside one, so it is committed first -- the same way the integration's own
        // auto-post does it. Test isolation still rolls the committed data back after the run.
        Commit();
        Assert.IsTrue(Codeunit.Run(Codeunit::"Sales-Post", SalesHeader), StrSubstNo('Posting the invoice should succeed: %1', GetLastErrorText()));

        // [THEN] The posted invoice carries the repair order number and total
        SalesInvHeader.SetRange("FRI Fleetrock Repair Order No.", ROId);
        Assert.IsTrue(SalesInvHeader.FindFirst(), StrSubstNo('A posted sales invoice should exist for repair order %1.', ROId));
        SalesInvHeader.CalcFields("Amount Including VAT");
        Assert.AreEqual(205.0, SalesInvHeader."Amount Including VAT", 'The posted invoice total should match the repair order grand total.');

        // [THEN] A deduction for the truck was logged in Business Central against both documents
        AlvysDeduction.SetRange("Posted Document No.", SalesInvHeader."No.");
        Assert.IsTrue(AlvysDeduction.FindLast(), 'Posting the invoice should log a deduction in the Alvys Deduction table.');
        Assert.AreEqual('567', AlvysDeduction."Truck Number", 'The deduction should be for the truck matching the Fleetrock unit number.');
        Assert.AreEqual('TR2516219714834333288', AlvysDeduction."Truck Id", 'The deduction should carry the Alvys truck id resolved from the unit number.');
        Assert.AreEqual(-205.0, AlvysDeduction.Amount, 'The deduction amount should be the negated invoice total.');
        Assert.AreEqual('Owner Operator Invoice', AlvysDeduction.Category, 'The deduction should use the owner operator invoice category.');
        Assert.AreEqual(Enum::"BAASI Alvys Entry Doc. Type"::"Sales Invoice", AlvysDeduction."Document Type", 'The deduction should carry the document type it was posted from.');
        Assert.AreEqual(InvoiceNo, AlvysDeduction."Document No.", 'The deduction should carry the invoice it was posted from.');

        // [THEN] The deduction exists in Alvys with the same truck and amount
        ResponseObj := AlvysSalesMgt.GetDeduction(AlvysDeduction.Id);
        Assert.AreEqual(Format(AlvysDeduction.Id), JsonMgt.GetJsonValueAsText(ResponseObj, 'Id'), 'Alvys should return the deduction created by the posting.');
        Assert.AreEqual('TR2516219714834333288', JsonMgt.GetJsonValueAsText(ResponseObj, 'TruckId'), 'The Alvys deduction should be linked to the truck.');
        Assert.IsTrue(ResponseObj.Get('Amount', JsonTkn), 'The Alvys deduction should carry an amount.');
        AmountObj := JsonTkn.AsObject();
        Assert.AreEqual(-205.0, JsonMgt.GetJsonValueAsDecimal(AmountObj, 'Amount'), 'The Alvys deduction amount should be the negated invoice total.');

        // [WHEN] Alvys settles that deduction and posts the driver pay call back to Business Central.
        // The deduction carries the invoice it was raised from, so the settlement resolves its own
        // invoice rather than being pointed at one -- the leg the unit tests cannot cover, because
        // there the deduction and the invoice are only linked by hand.
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareApplyDeductionEntry(AlvysEntry, AlvysDeduction.Id, AlvysDeduction."Truck Id", AlvysDeduction."Truck Number", AlvysDeduction.Amount, SalesInvHeader."Posting Date", 'Settlement for repair order ' + ROId);
        AlvysEntry.Insert(true);

        // [THEN] The settlement matched the invoice the deduction was raised from
        Assert.AreEqual('', AlvysEntry."Error Message", StrSubstNo('The settlement should apply cleanly: %1', AlvysEntry."Error Message"));
        Assert.AreEqual(SalesInvHeader."No.", AlvysEntry."Document No.", 'The settlement should be matched to the invoice the deduction was raised from.');

        // [THEN] The payment reached the payment journal, or the customer ledger when the setup
        // posts it. Auto-posting is configuration rather than something this test may seed, so both
        // settings are checked for the outcome they should produce.
        GenJnlLine.SetRange("Journal Template Name", AlvysSetup."Payment Journal Template");
        GenJnlLine.SetRange("Journal Batch Name", AlvysSetup."Payment Journal Batch");
        GenJnlLine.SetRange("Applies-to Doc. No.", SalesInvHeader."No.");
        if AlvysSetup."Auto-Post Deductions" then begin
            Assert.IsTrue(GenJnlLine.IsEmpty(), 'A posted settlement should leave no line behind in the payment journal.');
            CustLedgEntry.SetRange("Customer No.", SalesInvHeader."Bill-to Customer No.");
            CustLedgEntry.SetRange("Document Type", CustLedgEntry."Document Type"::Payment);
            Assert.IsTrue(CustLedgEntry.FindLast(), 'Posting the settlement should create a customer payment entry.');
            CustLedgEntry.CalcFields(Amount);
            Assert.AreEqual(AlvysDeduction.Amount, CustLedgEntry.Amount, 'The posted payment should carry the settled amount.');
        end else begin
            Assert.IsTrue(GenJnlLine.FindLast(), 'The settlement should be written to the payment journal.');
            Assert.AreEqual(AlvysDeduction.Amount, GenJnlLine.Amount, 'The journal line should carry the settled amount.');
            Assert.AreEqual(SalesInvHeader."Bill-to Customer No.", GenJnlLine."Account No.", 'The journal line should be for the invoice bill-to customer.');
            Assert.AreEqual(SalesInvHeader."Dimension Set ID", GenJnlLine."Dimension Set ID", 'The journal line should carry the dimensions of the invoice it settles.');
        end;

        // On a keep-data run the external clean-up is skipped along with the rollback, so the
        // repair order, the documents and the deduction survive for inspection.
        if TestMode.GetKeepData() then
            exit;

        // [THEN] The deduction can be deleted from Alvys again, so test runs do not accumulate
        // deductions in the tenant; the logged BC record rolls back with the rest of the test data
        AlvysSalesMgt.DeleteDeduction(AlvysDeduction.Id);
        Assert.IsFalse(AlvysSalesMgt.DoesDeductionExist(AlvysDeduction.Id), 'The deduction should be deleted from Alvys after the test.');

        // [THEN] The repair order can be walked back from Invoiced and deleted in Fleetrock
        ROHelper.DeleteRepairOrder(ROId);
        ROObj := ROHelper.GetRepairOrder(ROId);
        Assert.AreEqual('Deleted', JsonMgt.GetJsonValueAsText(ROObj, 'status'), 'The repair order should be deleted in Fleetrock after the test.');
    end;

    /// <summary>
    /// Requires both integrations to be properly configured in the company the suite runs in,
    /// rather than seeding any setup: the Alvys integration must be enabled with its credentials
    /// and tractor code dimension, and the Fleetrock integration must carry its credentials and
    /// use that same dimension as its asset dimension so posting hands the truck to Alvys.
    /// Auto-posting must be off because the test verifies the posting step itself, and the
    /// Fleetrock test tenant only accepts the raw API key, not a generated token.
    /// </summary>
    local procedure Initialize()
    begin
        AlvysSetup.Get();
        AlvysSetup.TestField(Enabled);
        AlvysSetup.TestField("Integration URL");
        AlvysSetup.TestField("Client ID");
        AlvysSetup.TestField("Client Secret");
        AlvysSetup.TestField("Tractor Code Dimension");
        // The run settles the deduction the posting creates, so the company needs the journal that
        // settlement is written to as well.
        AlvysSetup.TestField("Payment Journal Template");
        AlvysSetup.TestField("Payment Journal Batch");
        AlvysSetup.TestField("Bal. Account No.");

        FleetrockSetup.Get();
        FleetrockSetup.TestField("Integration URL");
        FleetrockSetup.TestField(Username);
        FleetrockSetup.TestField("API Key");
        FleetrockSetup.TestField("Vendor Username");
        FleetrockSetup.TestField("Asset Dimension Code", AlvysSetup."Tractor Code Dimension");
        FleetrockSetup.TestField("Auto-post Repair Orders", false);
        FleetrockSetup.TestField("Use API Token", false);

        Clear(AlvysSalesMgt);
    end;

    local procedure GetFleetrockCustomerNo(): Code[20]
    var
        Customer: Record Customer;
    begin
        Customer.SetRange("FRI Fleetrock Source No.", 'Double Diamond - Test');
        Assert.IsTrue(Customer.FindFirst(), 'A customer mapped to the Fleetrock customer account should exist after the import.');
        exit(Customer."No.");
    end;

    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
        Assert: Codeunit "Library Assert";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        JsonMgt: Codeunit "FRI Json Mgt.";
        ROHelper: Codeunit "BAASIT Fleetrock RO Helper";
        TestMode: Codeunit "BAASIT Test Mode";
        UnitVinTok: Label '1234567890', Locked = true;
}
