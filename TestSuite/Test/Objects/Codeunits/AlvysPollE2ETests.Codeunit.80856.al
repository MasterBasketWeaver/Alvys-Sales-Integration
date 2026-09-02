codeunit 80856 "BAASIT Alvys Poll E2E Tests"
{
    // [FEATURE] [Fleetrock Integration] [Alvys Sales Integration] [Settlement Poll]
    //
    // The whole round trip, driven for real rather than simulated: a repair order is created and
    // invoiced in Fleetrock, imported into Business Central and posted, which pushes a deduction to
    // Alvys; the deduction is settled by hand in the Alvys web UI; and the settlement is polled
    // back into Business Central, where it pays the very invoice the chain started from.
    //
    // Alvys will not mark a deduction paid over its API -- deductions/{id} serves GET and DELETE
    // only, and the token carries no deduction:update scope -- so the settlement has to happen in
    // the web UI. A test method cannot stop and wait for that, so the chain is split in two phases
    // with the settlement in between, and codeunit "BAASIT E2E Run" carries what the seed phase
    // produced through to the poll phase. Script tools/alvys-e2e.py drives the three steps in order.
    //
    // Both ways of polling are covered by running the chain twice, once per value of
    // "BAASIT E2E Poll Mode": a settled deduction can only be applied once, so a single chain
    // cannot exercise both.
    //
    // Nothing here rolls back. The chain runs through codeunit "BAASIT E2E Test Runner" with
    // isolation disabled, because the invoice and the deduction have to survive one phase to be
    // asserted against by the next.

    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>
    /// Phase one: Fleetrock through to a deduction sitting unpaid in Alvys, with everything the
    /// poll phase needs recorded on the run singleton.
    /// </summary>
    [Test]
    procedure RepairOrderReachesAlvysAsADeduction()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        E2ERun: Record "BAASIT E2E Run";
        JobQueueEntry: Record "Job Queue Entry";
        SalesHeader: Record "Sales Header";
        SalesInvHeader: Record "Sales Invoice Header";
        SalesLine: Record "Sales Line";
        GetRepairOrders: Codeunit "FRI Get Repair Orders";
        ROObj, ResponseObj : JsonObject;
        ROId: Text;
        InvoiceNo: Code[20];
        ThreeDays: Duration;
    begin
        // [SCENARIO] A repair order invoiced in Fleetrock is imported, posted, and reaches Alvys as
        // an unpaid truck deduction that the settlement poll will later be able to find.
        Initialize();

        // [GIVEN] A repair order in Fleetrock for the unit whose number matches an Alvys truck
        ROId := ROHelper.CreateRepairOrder(UnitVinTok);

        // [GIVEN] The repair order is invoiced in Fleetrock as of yesterday
        ROHelper.SetRepairOrderToInvoiced(ROId);
        ROObj := ROHelper.GetRepairOrder(ROId);
        Assert.AreEqual('Invoiced', JsonMgt.GetJsonValueAsText(ROObj, 'status'), 'The repair order should be Invoiced in Fleetrock after the update.');

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

        // [GIVEN] The sandbox's TEST location on the header and lines: another app in the
        // environment requires a location to post, and the integration does not assign one. The
        // location is assigned without validation, because validating it rebuilds the dimension
        // sets from default dimensions and would wipe the asset dimension the integration placed
        // on the document -- which is the truck the deduction is raised for.
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

        // [WHEN] The invoice is posted. The import left a write transaction open and posting
        // cannot start inside one, so it is committed first.
        Commit();
        Assert.IsTrue(Codeunit.Run(Codeunit::"Sales-Post", SalesHeader), StrSubstNo('Posting the invoice should succeed: %1', GetLastErrorText()));

        // [THEN] The posted invoice carries the repair order and its total
        SalesInvHeader.SetRange("FRI Fleetrock Repair Order No.", ROId);
        Assert.IsTrue(SalesInvHeader.FindFirst(), StrSubstNo('A posted sales invoice should exist for repair order %1.', ROId));
        SalesInvHeader.CalcFields("Amount Including VAT");
        Assert.AreEqual(205.0, SalesInvHeader."Amount Including VAT", 'The posted invoice total should match the repair order grand total.');

        // [THEN] Posting logged a deduction against the posted invoice
        AlvysDeduction.SetRange("Posted Document No.", SalesInvHeader."No.");
        Assert.IsTrue(AlvysDeduction.FindLast(), 'Posting the invoice should log a deduction in the Alvys Deduction table.');
        Assert.AreEqual(-205.0, AlvysDeduction.Amount, 'The deduction amount should be the negated invoice total.');
        Assert.AreNotEqual('', AlvysDeduction."Truck Id", 'The deduction should carry the Alvys truck id resolved from the unit number.');

        // [THEN] The deduction is in Alvys, and unpaid -- the poll has to have something to find
        ResponseObj := AlvysSalesMgt.GetDeduction(AlvysDeduction.Id);
        Assert.AreEqual(Format(AlvysDeduction.Id), JsonMgt.GetJsonValueAsText(ResponseObj, 'Id'), 'Alvys should return the deduction created by the posting.');
        Assert.IsFalse(ApiJsonMgt.GetJsonValueAsBoolean(ResponseObj, 'IsPaid'), 'A deduction Alvys has not settled yet should come back unpaid.');
        Assert.IsFalse(AlvysDeduction."Is Paid", 'The deduction should be logged unpaid in Business Central.');
        Assert.IsFalse(AlvysDeduction."Settlement Applied", 'Nothing should have been applied for a deduction that has not been settled.');

        // [THEN] The chain is recorded for the settlement step and the poll phase to pick up
        E2ERun.GetSingleton();
        E2ERun."Repair Order Id" := CopyStr(ROId, 1, MaxStrLen(E2ERun."Repair Order Id"));
        E2ERun."Sales Invoice No." := InvoiceNo;
        E2ERun."Posted Invoice No." := SalesInvHeader."No.";
        E2ERun."Deduction Id" := AlvysDeduction.Id;
        E2ERun."Deduction Entry No." := AlvysDeduction."Entry No.";
        E2ERun."Truck Id" := AlvysDeduction."Truck Id";
        E2ERun."Truck Number" := AlvysDeduction."Truck Number";
        E2ERun.Amount := AlvysDeduction.Amount;
        E2ERun."Customer No." := SalesInvHeader."Bill-to Customer No.";
        E2ERun."Seeded At" := CurrentDateTime();
        E2ERun.Modify();
        Commit();
    end;

    /// <summary>
    /// Phase two: the deduction the seed phase created has been settled in the Alvys web UI, and
    /// the poll has to notice, apply it, and leave the invoice paid.
    /// </summary>
    [Test]
    procedure SettledDeductionIsPolledBackAndPaysTheInvoice()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        CustLedgEntry: Record "Cust. Ledger Entry";
        E2ERun: Record "BAASIT E2E Run";
        GenJnlLine: Record "Gen. Journal Line";
        SalesInvHeader: Record "Sales Invoice Header";
        AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
        ResponseObj: JsonObject;
    begin
        // [SCENARIO] Alvys has settled the deduction, and polling brings the settlement back into
        // Business Central as a payment that closes the invoice the chain started from.
        Initialize();

        // [GIVEN] The chain the seed phase left behind
        E2ERun.GetSingleton();
        Assert.AreNotEqual('', E2ERun."Deduction Id", 'The seed phase should have recorded the deduction it created; run the seed phase first.');
        Assert.AreNotEqual('', Format(E2ERun."Posted Invoice No."), 'The seed phase should have recorded the posted invoice it created.');
        Assert.IsTrue(AlvysDeduction.Get(E2ERun."Deduction Entry No."), 'The deduction the seed phase logged should still exist.');
        Assert.IsTrue(SalesInvHeader.Get(E2ERun."Posted Invoice No."), 'The posted invoice the seed phase created should still exist.');

        // [GIVEN] Alvys reports the deduction settled -- the step that happens in the web UI, and
        // the one thing this phase cannot do for itself
        ResponseObj := AlvysSalesMgt.GetDeduction(E2ERun."Deduction Id");
        Assert.IsTrue(ApiJsonMgt.GetJsonValueAsBoolean(ResponseObj, 'IsPaid'),
            StrSubstNo('Deduction %1 should be settled in Alvys before the poll runs; generate the driver settlement statement in the Alvys UI first.', E2ERun."Deduction Id"));

        // [GIVEN] Business Central has not applied it yet
        Assert.IsFalse(AlvysDeduction."Settlement Applied", 'The settlement should not have been applied before the poll runs.');

        // [WHEN] The poll runs the way this run is meant to exercise it. Manual is what the setup
        // page action does; Job Queue goes through the codeunit's OnRun, which is how the job queue
        // starts it and what turns error logging on.
        case E2ERun."Poll Mode" of
            E2ERun."Poll Mode"::Manual:
                AlvysSettlementPoll.PollSettledDeductions();
            E2ERun."Poll Mode"::"Job Queue":
                Assert.IsTrue(Codeunit.Run(Codeunit::"BAASI Alvys Settlement Poll"),
                    StrSubstNo('A scheduled poll should not raise: %1', GetLastErrorText()));
        end;

        // [THEN] The poll noticed Alvys had settled it, and applied it exactly once
        AlvysDeduction.Get(E2ERun."Deduction Entry No.");
        Assert.IsTrue(AlvysDeduction."Is Paid", 'The poll should have refreshed the deduction as paid from Alvys.');
        Assert.IsTrue(AlvysDeduction."Settlement Applied", 'The poll should have applied the settlement.');
        Assert.AreNotEqual(0DT, AlvysDeduction."Settlement Applied At", 'Applying the settlement should stamp when it happened.');

        // [THEN] The settlement was logged as polled rather than as a call Alvys made
        AlvysEntry.SetRange("Document No.", E2ERun."Posted Invoice No.");
        AlvysEntry.SetRange(Direction, AlvysEntry.Direction::Inbound);
        Assert.IsTrue(AlvysEntry.FindLast(), 'The applied settlement should be logged as an inbound entry.');
        Assert.AreEqual('', AlvysEntry."Error Message", StrSubstNo('The settlement should apply cleanly: %1', AlvysEntry."Error Message"));
        Assert.AreEqual('POLL', AlvysEntry.Method, 'A polled settlement should be logged as polled, not as an HTTP call that never arrived.');

        // [WHEN] The payment is posted. With auto-posting on the poll has already done it; with it
        // off the line is waiting in the journal, and posting it here is what lets this phase
        // answer the question it exists to answer -- whether the invoice ends up paid.
        GenJnlLine.SetRange("Journal Template Name", AlvysSetup."Payment Journal Template");
        GenJnlLine.SetRange("Journal Batch Name", AlvysSetup."Payment Journal Batch");
        GenJnlLine.SetRange("Applies-to Doc. No.", E2ERun."Posted Invoice No.");
        if not AlvysSetup."Auto-Post Deductions" then begin
            Assert.IsTrue(GenJnlLine.FindLast(), 'The settlement should be written to the payment journal.');
            Assert.AreEqual(AlvysDeduction.Amount, GenJnlLine.Amount, 'The journal line should carry the settled amount.');
            Assert.AreEqual(SalesInvHeader."Bill-to Customer No.", GenJnlLine."Account No.", 'The journal line should be for the invoice bill-to customer.');
            Assert.AreEqual(SalesInvHeader."Dimension Set ID", GenJnlLine."Dimension Set ID", 'The journal line should carry the dimensions of the invoice it settles.');
            // Posting posts the whole batch, not just this line, so anything else sitting in it
            // is posted too -- and a stale or half-built line fails with a G/L inconsistency that
            // says nothing about where it came from. Naming the foreign lines here turns that into
            // something a reader can act on.
            Assert.AreEqual('', ForeignJournalLines(E2ERun."Posted Invoice No."),
                StrSubstNo('The payment journal should hold nothing but this settlement before it is posted. Found: %1', ForeignJournalLines(E2ERun."Posted Invoice No.")));
            Commit();
            Assert.IsTrue(Codeunit.Run(Codeunit::"Gen. Jnl.-Post Batch", GenJnlLine), StrSubstNo('Posting the settlement should succeed: %1', GetLastErrorText()));
        end else
            Assert.IsTrue(GenJnlLine.IsEmpty(), 'A posted settlement should leave no line behind in the payment journal.');

        // [THEN] A customer payment was posted for the settled amount and applied to the invoice
        CustLedgEntry.SetRange("Customer No.", SalesInvHeader."Bill-to Customer No.");
        CustLedgEntry.SetRange("Document Type", CustLedgEntry."Document Type"::Payment);
        Assert.IsTrue(CustLedgEntry.FindLast(), 'Posting the settlement should create a customer payment entry.');
        CustLedgEntry.CalcFields(Amount);
        Assert.AreEqual(AlvysDeduction.Amount, CustLedgEntry.Amount, 'The posted payment should carry the settled amount.');

        // [THEN] The invoice the chain started from is paid off and closed
        CustLedgEntry.Reset();
        CustLedgEntry.SetRange("Document Type", CustLedgEntry."Document Type"::Invoice);
        CustLedgEntry.SetRange("Document No.", E2ERun."Posted Invoice No.");
        Assert.IsTrue(CustLedgEntry.FindLast(), StrSubstNo('A customer ledger entry should exist for invoice %1.', E2ERun."Posted Invoice No."));
        CustLedgEntry.CalcFields("Remaining Amount");
        Assert.AreEqual(0.0, CustLedgEntry."Remaining Amount", 'The settlement should leave nothing outstanding on the invoice it was raised against.');
        Assert.IsFalse(CustLedgEntry.Open, 'The invoice should be closed once the settlement has paid it off.');

        // [THEN] What the run ended up with, for the script that drives the phases to report
        E2ERun."Polled At" := CurrentDateTime();
        E2ERun."Invoice Remaining Amount" := CustLedgEntry."Remaining Amount";
        E2ERun."Invoice Closed" := not CustLedgEntry.Open;
        E2ERun.Modify();
        Commit();
    end;

    /// <summary>
    /// Describes every line in the payment journal that is not this settlement's, so a batch that
    /// will not post says what is in the way rather than only that something is.
    /// </summary>
    local procedure ForeignJournalLines(PostedInvoiceNo: Code[20]) Description: Text
    var
        GenJnlLine: Record "Gen. Journal Line";
    begin
        GenJnlLine.SetRange("Journal Template Name", AlvysSetup."Payment Journal Template");
        GenJnlLine.SetRange("Journal Batch Name", AlvysSetup."Payment Journal Batch");
        GenJnlLine.SetFilter("Applies-to Doc. No.", '<>%1', PostedInvoiceNo);
        if not GenJnlLine.FindSet() then
            exit('');
        repeat
            Description += StrSubstNo('[line %1: %2 %3 %4 %5 amount %6 applies-to %7] ',
                GenJnlLine."Line No.", GenJnlLine."Posting Date", GenJnlLine."Document No.",
                GenJnlLine."Account Type", GenJnlLine."Account No.", GenJnlLine.Amount,
                GenJnlLine."Applies-to Doc. No.");
        until GenJnlLine.Next() = 0;
    end;

    /// <summary>
    /// Both integrations have to be configured in the company the chain runs in, rather than seeded
    /// here: the run drives the real Fleetrock tenant and the real Alvys API, and the two have to
    /// agree on the dimension that carries the truck or the posting will not raise a deduction.
    /// </summary>
    local procedure Initialize()
    begin
        AlvysSetup.Get();
        AlvysSetup.TestField(Enabled);
        AlvysSetup.TestField("Integration URL");
        AlvysSetup.TestField("Client ID");
        AlvysSetup.TestField("Client Secret");
        AlvysSetup.TestField("Tractor Code Dimension");
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

    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
        Assert: Codeunit "Library Assert";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        ApiJsonMgt: Codeunit "BAAPI Json Mgt.";
        JsonMgt: Codeunit "FRI Json Mgt.";
        ROHelper: Codeunit "BAASIT Fleetrock RO Helper";
        UnitVinTok: Label '1234567890', Locked = true;
        LocationTok: Label 'TEST', Locked = true;
}
