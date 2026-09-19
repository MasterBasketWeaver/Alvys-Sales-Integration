codeunit 89969 "BAASIT Alvys Stmt E2E Tests"
{
    // [FEATURE] [Fleetrock Integration] [Alvys Sales Integration] [Settlement Poll] [Statements]
    //
    // The statement date carried from Alvys through to Business Central and Fleetrock, for real:
    // three repair orders are invoiced in Fleetrock and posted here, and their deductions are paid
    // in the Alvys web UI -- one whole, one split once, one split twice -- with the parts spread
    // over three pay periods, so that each lands on a statement with a date of its own. The poll
    // then has to post each part's payment on the date of the statement that paid it, and close
    // each invoice, and the repair order in Fleetrock, on the date its last part was paid.
    //
    // As in codeunit "BAASIT Alvys Poll E2E Tests", the web UI step cannot happen inside a test,
    // so the chain is split into a seed phase and a poll phase with the Alvys step in between,
    // driven by Tools/alvys-e2e-statements.py. What Alvys says paid each part is written by that
    // script into table "BAASIT E2E Stmt Leaf", read from the Alvys API rather than worked out
    // here, so the poll phase checks the integration against Alvys' own answer.
    //
    // Nothing rolls back: the chain runs through codeunit "BAASIT E2E Test Runner" with isolation
    // off, because what the seed phase creates has to survive into the poll phase.

    Subtype = Test;
    TestPermissions = Disabled;

    /// <summary>
    /// Phase one: a repair order per case, posted, and its deduction sitting unpaid in Alvys.
    /// </summary>
    [Test]
    procedure RepairOrdersReachAlvysForEachStatementCase()
    var
        E2ERun: Record "BAASIT E2E Run";
        StmtCase: Record "BAASIT E2E Stmt Case";
        StmtLeaf: Record "BAASIT E2E Stmt Leaf";
        CaseCode: Text;
    begin
        // [SCENARIO] Three repair orders invoiced in Fleetrock for the truck under test each reach
        // Alvys as an unpaid deduction, ready to be paid whole, split once and split twice.
        Initialize();

        // [GIVEN] The truck the run is for
        E2ERun.GetSingleton();
        Assert.AreNotEqual('', E2ERun."Statement Unit No.", 'The run should name the Fleetrock unit to raise the repair orders for.');
        StmtCase.DeleteAll();
        StmtLeaf.DeleteAll();
        Commit();

        // [WHEN] A repair order per case is created, invoiced, imported and posted
        // [THEN] Each posting raises an unpaid deduction on that truck in Alvys
        foreach CaseCode in CaseCodes() do
            SeedCase(CopyStr(CaseCode, 1, 20), E2ERun."Statement Unit No.");
    end;

    /// <summary>
    /// Phase two: every part has been paid in Alvys, on the statement the script recorded against
    /// it, and the poll has to carry each statement's date through to the payment, the invoice and
    /// the repair order.
    /// </summary>
    [Test]
    procedure EachPartPostsOnItsStatementDateInBCAndFleetrock()
    var
        StmtCase: Record "BAASIT E2E Stmt Case";
        StmtLeaf: Record "BAASIT E2E Stmt Leaf";
        AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
        Watermark: Integer;
        WasAutoPost: Boolean;
    begin
        // [SCENARIO] Each deduction, and each part of a split one, posts its payment on the date of
        // the Alvys statement that paid it; each invoice closes, and its Fleetrock repair order is
        // marked paid, on the date of the last of its parts to be paid.
        Initialize();

        // [GIVEN] The cases the seed phase raised, and what Alvys says paid each of their parts
        Assert.AreEqual(3, StmtCase.Count(), 'The seed phase should have raised three cases; run the seed phase first.');
        Assert.AreEqual(6, StmtLeaf.Count(), 'The script should have recorded the six parts Alvys paid; run the Alvys step first.');
        StmtLeaf.SetRange("Expected Statement Date", 0D);
        Assert.IsTrue(StmtLeaf.IsEmpty(), 'Every recorded part should carry the date of the statement that paid it.');
        StmtLeaf.Reset();

        // [WHEN] The poll runs, with the settlements posted as it applies them
        WasAutoPost := SetAutoPostDeductions(true);
        Watermark := LastCustLedgerEntryNo();
        Commit();
        AlvysSettlementPoll.PollSettledDeductions();
        SetAutoPostDeductions(WasAutoPost);
        Commit();

        // [THEN] Each part is linked to its statement and its payment posted on that statement's date
        StmtLeaf.FindSet();
        repeat
            AssertPartPostedOnItsStatementDate(StmtLeaf, Watermark);
        until StmtLeaf.Next() = 0;

        // [THEN] Each invoice, and its repair order in Fleetrock, is paid on its last part's date
        StmtCase.FindSet();
        repeat
            AssertCasePaidOnItsLastStatementDate(StmtCase);
        until StmtCase.Next() = 0;
        Commit();
    end;

    local procedure SeedCase(CaseCode: Code[20]; UnitNumber: Text)
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        SalesInvHeader: Record "Sales Invoice Header";
        StmtCase: Record "BAASIT E2E Stmt Case";
        DetailedRepairOrder: Codeunit "BAASIT Detailed Repair Order";
        ResponseObj: JsonObject;
        ROId: Text;
        InvoiceNo, PostedInvoiceNo : Code[20];
    begin
        DetailedRepairOrder.Create(UnitNumber, 1, 1, ROId, InvoiceNo, PostedInvoiceNo);
        SalesInvHeader.Get(PostedInvoiceNo);

        AlvysDeduction.SetRange("Posted Document No.", PostedInvoiceNo);
        Assert.IsTrue(AlvysDeduction.FindLast(), StrSubstNo('Posting invoice %1 should raise a deduction.', PostedInvoiceNo));
        Assert.AreEqual(UnitNumber, AlvysDeduction."Truck Number", 'The deduction should be raised on the truck under test.');
        Assert.AreNotEqual('', AlvysDeduction."Owner Operator Id", 'The deduction should record the owner operator its statements belong to.');
        ResponseObj := AlvysSalesMgt.GetDeduction(AlvysDeduction.Id);
        Assert.IsFalse(ApiJsonMgt.GetJsonValueAsBoolean(ResponseObj, 'IsPaid'), 'A deduction just raised should be unpaid in Alvys.');

        StmtCase.Init();
        StmtCase."Case Code" := CaseCode;
        StmtCase."Repair Order Id" := CopyStr(ROId, 1, MaxStrLen(StmtCase."Repair Order Id"));
        StmtCase."Posted Invoice No." := PostedInvoiceNo;
        StmtCase."Invoice Posting Date" := SalesInvHeader."Posting Date";
        StmtCase."Customer No." := SalesInvHeader."Bill-to Customer No.";
        StmtCase."Deduction Entry No." := AlvysDeduction."Entry No.";
        StmtCase."Deduction Id" := AlvysDeduction.Id;
        StmtCase."Group Id" := AlvysDeduction."Group Id";
        StmtCase.Description := AlvysDeduction.Description;
        StmtCase.Amount := AlvysDeduction.Amount;
        StmtCase."Truck Number" := AlvysDeduction."Truck Number";
        StmtCase."Owner Operator Id" := AlvysDeduction."Owner Operator Id";
        StmtCase.Insert();
        Commit();
    end;

    local procedure AssertPartPostedOnItsStatementDate(var StmtLeaf: Record "BAASIT E2E Stmt Leaf"; Watermark: Integer)
    var
        Part: Record "BAASI Alvys Deduction";
        StmtCase: Record "BAASIT E2E Stmt Case";
        CustLedgEntry: Record "Cust. Ledger Entry";
    begin
        StmtCase.Get(StmtLeaf."Case Code");
        FindPart(StmtCase, StmtLeaf.Description, Part);

        Assert.IsTrue(Part."Is Paid", StrSubstNo('%1 should be paid.', Part.Description));
        Assert.AreEqual(StmtLeaf."Expected Statement No.", Part."Statement No.", StrSubstNo('%1 should be linked to the statement Alvys paid it on.', Part.Description));
        Assert.AreEqual(StmtLeaf."Expected Statement Date", Part."Statement Date", StrSubstNo('%1 should take the date of statement %2.', Part.Description, StmtLeaf."Expected Statement No."));
        Assert.IsTrue(Part."Settlement Applied", StrSubstNo('%1 should be applied.', Part.Description));
        Assert.IsTrue(Part."Settlement Posted", StrSubstNo('%1 should be posted.', Part.Description));

        // The parts' amounts are all different, so the amount picks out this part's payment.
        CustLedgEntry.SetRange("Customer No.", StmtCase."Customer No.");
        CustLedgEntry.SetRange("Document Type", CustLedgEntry."Document Type"::Payment);
        CustLedgEntry.SetFilter("Entry No.", '>%1', Watermark);
        CustLedgEntry.SetAutoCalcFields(Amount);
        CustLedgEntry.SetRange(Amount, Part.Amount);
        Assert.AreEqual(1, CustLedgEntry.Count(), StrSubstNo('%1 should be posted as one payment of %2.', Part.Description, Part.Amount));
        CustLedgEntry.FindFirst();
        Assert.AreEqual(StmtLeaf."Expected Statement Date", CustLedgEntry."Posting Date", StrSubstNo('The payment for %1 should post on the date of statement %2.', Part.Description, StmtLeaf."Expected Statement No."));

        StmtLeaf."Statement No." := Part."Statement No.";
        StmtLeaf."Statement Date" := Part."Statement Date";
        StmtLeaf."Payment Posting Date" := CustLedgEntry."Posting Date";
        StmtLeaf."Payment Posted" := true;
        StmtLeaf.Modify();
    end;

    local procedure AssertCasePaidOnItsLastStatementDate(var StmtCase: Record "BAASIT E2E Stmt Case")
    var
        CustLedgEntry: Record "Cust. Ledger Entry";
        StmtLeaf: Record "BAASIT E2E Stmt Leaf";
        ROObj: JsonObject;
        LastDate: Date;
    begin
        StmtLeaf.SetRange("Case Code", StmtCase."Case Code");
        StmtLeaf.FindSet();
        repeat
            if StmtLeaf."Expected Statement Date" > LastDate then
                LastDate := StmtLeaf."Expected Statement Date";
        until StmtLeaf.Next() = 0;

        CustLedgEntry.SetRange("Document Type", CustLedgEntry."Document Type"::Invoice);
        CustLedgEntry.SetRange("Document No.", StmtCase."Posted Invoice No.");
        Assert.IsTrue(CustLedgEntry.FindFirst(), StrSubstNo('Invoice %1 should have a customer ledger entry.', StmtCase."Posted Invoice No."));
        Assert.IsFalse(CustLedgEntry.Open, StrSubstNo('Invoice %1 should be paid off once all its parts are paid.', StmtCase."Posted Invoice No."));
        Assert.AreEqual(LastDate, CustLedgEntry."Closed at Date", StrSubstNo('Invoice %1 should close on the date of the last statement that paid it.', StmtCase."Posted Invoice No."));

        ROObj := ROHelper.GetRepairOrder(StmtCase."Repair Order Id");
        StmtCase."Fleetrock Paid Date" := FleetrockDate(JsonMgt.GetJsonValueAsText(ROObj, 'date_invoice_paid'));
        Assert.AreEqual(LastDate, StmtCase."Fleetrock Paid Date", StrSubstNo('Repair order %1 should be marked paid in Fleetrock on the date invoice %2 closed.', StmtCase."Repair Order Id", StmtCase."Posted Invoice No."));

        StmtCase."Invoice Closed" := not CustLedgEntry.Open;
        StmtCase."Invoice Closed At" := CustLedgEntry."Closed at Date";
        StmtCase.Modify();
    end;

    /// <summary>
    /// The deduction the case raised or the part of it that was paid. Alvys names a part by adding
    /// " (part n)" to what it split, after the space the description Business Central sends ends
    /// in, so the spacing is compared loosely.
    /// </summary>
    local procedure FindPart(var StmtCase: Record "BAASIT E2E Stmt Case"; Description: Text; var Part: Record "BAASI Alvys Deduction")
    begin
        Part.SetRange("Group Id", StmtCase."Group Id");
        Part.SetRange("Split in Alvys", false);
        if Part.FindSet() then
            repeat
                if DelChr(Part.Description, '=', ' ') = DelChr(Description, '=', ' ') then
                    exit;
            until Part.Next() = 0;
        Assert.Fail(StrSubstNo('No deduction or part described %1 was logged for case %2.', Description, StmtCase."Case Code"));
    end;

    /// <summary>
    /// Fleetrock returns dates as M/D/YYYY h:mm:ss AM.
    /// </summary>
    local procedure FleetrockDate(DateTimeText: Text): Date
    var
        Parts: List of [Text];
        Day, Month, Year : Integer;
    begin
        Assert.AreNotEqual('', DateTimeText, 'The repair order should have a paid date in Fleetrock.');
        Parts := DateTimeText.Split(' ').Get(1).Split('/');
        Evaluate(Month, Parts.Get(1));
        Evaluate(Day, Parts.Get(2));
        Evaluate(Year, Parts.Get(3));
        exit(DMY2Date(Day, Month, Year));
    end;

    local procedure CaseCodes() Codes: List of [Text]
    begin
        Codes.Add('WHOLE');
        Codes.Add('SPLIT');
        Codes.Add('MULTI');
    end;

    /// <summary>
    /// Sets auto-posting of settlements and returns what it was. Nothing here rolls back, so the
    /// caller puts the company's own setting back.
    /// </summary>
    local procedure SetAutoPostDeductions(AutoPost: Boolean) WasAutoPost: Boolean
    begin
        AlvysSetup.Get();
        WasAutoPost := AlvysSetup."Auto-Post Deductions";
        if WasAutoPost = AutoPost then
            exit;
        AlvysSetup."Auto-Post Deductions" := AutoPost;
        AlvysSetup.Modify();
    end;

    local procedure LastCustLedgerEntryNo(): Integer
    var
        CustLedgEntry: Record "Cust. Ledger Entry";
    begin
        if CustLedgEntry.FindLast() then
            exit(CustLedgEntry."Entry No.");
    end;

    local procedure Initialize()
    begin
        AlvysSetup.Get();
        AlvysSetup.TestField(Enabled);
        AlvysSetup.TestField("Payment Journal Template");
        AlvysSetup.TestField("Payment Journal Batch");
        AlvysSetup.TestField("Bal. Account No.");
        FleetrockSetup.Get();
        FleetrockSetup.TestField("Truck Dimension Code");
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
}
