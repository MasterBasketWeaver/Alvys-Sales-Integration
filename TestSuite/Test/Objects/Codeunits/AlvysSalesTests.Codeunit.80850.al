codeunit 80850 "BAASIT Alvys Sales Tests"
{
    // [FEATURE] [Alvys Sales Integration]
    //
    // These are integration tests: they call the live Alvys API with the credentials seeded by
    // Initialize(). Business Central data is rolled back when the test run ends, but deductions
    // created here stay in the Alvys tenant, so they are all written against the "Test" category.

    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure GetBearerTokenReturnsAccessToken()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        AccessToken: Text;
    begin
        // [SCENARIO] Requesting a bearer token returns a token and stores it on the setup record.
        Initialize();

        // [WHEN] A bearer token is requested
        AccessToken := AlvysSalesMgt.GetBearerToken();

        // [THEN] A token is returned and cached with an expiry in the future
        Assert.AreNotEqual('', AccessToken, 'GetBearerToken should return an access token.');
        AlvysSetup.Get();
        Assert.AreEqual(AccessToken, AlvysSetup.GetAccessToken(), 'The returned token should be stored on the setup record.');
        Assert.IsTrue(AlvysSetup."Access Token Expiry Date" > CurrentDateTime(), 'The stored token should not be expired.');
    end;

    [Test]
    procedure CheckToGetAccessTokenReusesCachedToken()
    var
        FirstToken, SecondToken : Text;
    begin
        // [SCENARIO] A cached, unexpired token is reused instead of requesting a new one.
        Initialize();

        // [GIVEN] A token has already been fetched
        FirstToken := AlvysSalesMgt.GetBearerToken();

        // [WHEN] A token is requested again through the caching entry point
        SecondToken := AlvysSalesMgt.CheckToGetAccessToken();

        // [THEN] The cached token is handed back unchanged
        Assert.AreEqual(FirstToken, SecondToken, 'The cached token should be reused while it is still valid.');
    end;

    [Test]
    procedure GetTruckIDReturnsTruckForTruckNumber()
    var
        TruckID: Text;
    begin
        // [SCENARIO] A truck number is resolved to the Alvys truck Id. Alvys pages are 0-indexed,
        // so a search that asks for page 1 returns nothing and this test fails.
        Initialize();

        // [WHEN] The truck number is looked up
        TruckID := AlvysSalesMgt.GetTruckID('1');

        // [THEN] The matching truck Id is returned
        Assert.AreEqual('TR2516627931370728085', TruckID, 'GetTruckID should resolve truck number 1 to its Alvys Id.');
    end;

    [Test]
    procedure GetTruckIDWithBlankTruckNumberFails()
    begin
        // [SCENARIO] A truck cannot be looked up without a truck number.
        Initialize();

        // [WHEN] The truck is looked up with a blank number
        asserterror AlvysSalesMgt.GetTruckID('');

        // [THEN] The call is rejected before it reaches Alvys
        Assert.ExpectedError('The truck number cannot be blank.');
    end;

    [Test]
    procedure CreateDeductionForTruckCreatesDeduction()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        DeductionID: Text;
    begin
        // [SCENARIO] Creating a truck deduction posts it to Alvys and logs it in Business Central.
        Initialize();

        // [WHEN] A deduction is created for a truck
        DeductionID := AlvysSalesMgt.CreateDeductionForTruck('TR2516627931370728085', '1', WorkDate(), -1.25, 'Test', 'BC test app - truck deduction');

        // [THEN] Alvys returns an Id and the deduction is logged against the truck
        Assert.AreNotEqual('', DeductionID, 'CreateDeductionForTruck should return the Alvys deduction Id.');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionID, 1, MaxStrLen(AlvysDeduction.Id)));
        Assert.IsTrue(AlvysDeduction.FindLast(), 'The created deduction should be logged in the Alvys Deduction table.');
        Assert.AreEqual('TR2516627931370728085', AlvysDeduction."Truck Id", 'The logged deduction should carry the truck Id.');
        Assert.AreEqual('1', AlvysDeduction."Truck Number", 'The logged deduction should carry the truck number it was created for.');
        Assert.AreEqual('', AlvysDeduction."Driver Id", 'A truck deduction should not carry a driver Id.');
        Assert.AreEqual(-1.25, AlvysDeduction.Amount, 'The logged deduction should carry the requested amount.');
        Assert.AreEqual('Test', AlvysDeduction.Category, 'The logged deduction should carry the requested category.');
    end;

    [Test]
    procedure CreateDeductionForDriverCreatesDeduction()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        DeductionID: Text;
    begin
        // [SCENARIO] Creating a driver deduction posts it to Alvys and logs it in Business Central.
        Initialize();

        // [WHEN] A deduction is created for a driver
        DeductionID := AlvysSalesMgt.CreateDeductionForDriver('DR2516627925609719241', WorkDate(), -2.5, 'Test', 'BC test app - driver deduction');

        // [THEN] Alvys returns an Id and the deduction is logged against the driver
        Assert.AreNotEqual('', DeductionID, 'CreateDeductionForDriver should return the Alvys deduction Id.');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionID, 1, MaxStrLen(AlvysDeduction.Id)));
        Assert.IsTrue(AlvysDeduction.FindLast(), 'The created deduction should be logged in the Alvys Deduction table.');
        Assert.AreEqual('DR2516627925609719241', AlvysDeduction."Driver Id", 'The logged deduction should carry the driver Id.');
        Assert.AreEqual('', AlvysDeduction."Truck Id", 'A driver deduction should not carry a truck Id.');
        Assert.AreEqual('', AlvysDeduction."Truck Number", 'A driver deduction should not carry a truck number.');
        Assert.AreEqual(-2.5, AlvysDeduction.Amount, 'The logged deduction should carry the requested amount.');
    end;

    [Test]
    procedure CreateDeductionForTruckFromPostedInvoiceLinksBothDocuments()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        SalesHeader: Record "Sales Header";
        SalesInvHeader: Record "Sales Invoice Header";
        DeductionID: Text;
    begin
        // [SCENARIO] The deduction created for a posted invoice resolves its truck from the invoice
        // dimension and is logged against both the order it posted from and the posted invoice.
        Initialize();

        // [GIVEN] An order and the invoice it posted to, carrying the tractor code of truck number 1
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := 'ALVYS-TEST-ORD';
        SalesInvHeader."No." := 'ALVYS-TEST-INV';
        SalesInvHeader."Dimension Set ID" := TractorCodeDimensionSetID('1');

        // [WHEN] A deduction is created for the posted invoice
        DeductionID := AlvysSalesMgt.CreateDeductionForTruck(SalesHeader, SalesInvHeader, WorkDate(), -4.5, 'Test', 'BC test app - posted invoice deduction', false);

        // [THEN] The deduction is created against the truck the dimension resolves to
        Assert.AreNotEqual('', DeductionID, 'CreateDeductionForTruck should return the Alvys deduction Id.');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionID, 1, MaxStrLen(AlvysDeduction.Id)));
        Assert.IsTrue(AlvysDeduction.FindLast(), 'The created deduction should be logged in the Alvys Deduction table.');
        Assert.AreEqual('TR2516627931370728085', AlvysDeduction."Truck Id", 'The truck should be resolved from the tractor code dimension on the posted invoice.');
        Assert.AreEqual(-4.5, AlvysDeduction.Amount, 'The logged deduction should carry the requested amount.');

        // [THEN] The truck number the Id was resolved from is the tractor code on the posted invoice
        Assert.AreEqual('1', AlvysDeduction."Truck Number", 'The deduction should carry the tractor code dimension value from the posted invoice as its truck number.');

        // [THEN] Both the originating document and the posted invoice are recorded on it
        Assert.AreEqual(Enum::"BAASI Alvys Entry Doc. Type"::"Sales Order", AlvysDeduction."Document Type", 'The deduction should carry the document type it was posted from.');
        Assert.AreEqual('ALVYS-TEST-ORD', AlvysDeduction."Document No.", 'The deduction should carry the number of the document it was posted from.');
        Assert.AreEqual('ALVYS-TEST-INV', AlvysDeduction."Posted Document No.", 'The deduction should carry the posted invoice number.');
    end;

    [Test]
    procedure CreateDeductionForTruckFromPostedInvoiceWithoutTractorCodeFails()
    var
        SalesHeader: Record "Sales Header";
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        // [SCENARIO] A posted invoice without the tractor code dimension has no truck to deduct from.
        Initialize();

        // [GIVEN] An order and an invoice that carry no dimensions at all
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := 'ALVYS-TEST-ORD';
        SalesInvHeader."No." := 'ALVYS-TEST-INV';
        SalesInvHeader."Dimension Set ID" := 0;

        // [WHEN] A deduction is created for the posted invoice
        asserterror AlvysSalesMgt.CreateDeductionForTruck(SalesHeader, SalesInvHeader, WorkDate(), -4.5, 'Test', 'BC test app - no tractor code', false);

        // [THEN] The call is rejected before it reaches Alvys: without dimensions there is no
        // tractor code, so the truck number resolves to blank
        Assert.ExpectedError('The truck number cannot be blank.');
    end;

    [Test]
    procedure CreateDeductionWithBlankAssetIDFails()
    begin
        // [SCENARIO] A deduction cannot be created without a truck or driver Id.
        Initialize();

        // [WHEN] A deduction is created with a blank truck Id
        asserterror AlvysSalesMgt.CreateDeductionForTruck('', '1', WorkDate(), -1.25, 'Test', 'BC test app - blank truck');

        // [THEN] The call is rejected before it reaches Alvys
        Assert.ExpectedError('The TruckId cannot be blank when creating a deduction.');
    end;

    [Test]
    procedure MapDocumentTypeMapsOrdersAndInvoices()
    var
        SalesHeader: Record "Sales Header";
    begin
        // [SCENARIO] The sales document types that have a counterpart in Alvys are mapped onto the
        // document type stored on the logged entry.
        Initialize();

        // [WHEN] An order and an invoice are mapped
        // [THEN] Each maps onto its matching entry document type
        Assert.AreEqual(
            Enum::"BAASI Alvys Entry Doc. Type"::"Sales Order",
            AlvysSalesMgt.MapDocumentType(SalesHeader."Document Type"::Order),
            'A sales order should map to the Sales Order entry document type.');
        Assert.AreEqual(
            Enum::"BAASI Alvys Entry Doc. Type"::"Sales Invoice",
            AlvysSalesMgt.MapDocumentType(SalesHeader."Document Type"::Invoice),
            'A sales invoice should map to the Sales Invoice entry document type.');
    end;

    [Test]
    procedure MapDocumentTypeRejectsUnsupportedDocumentTypes()
    var
        SalesHeader: Record "Sales Header";
    begin
        // [SCENARIO] Sales document types with no counterpart in Alvys are rejected rather than
        // silently logged against the wrong type. Quote doubles as the placeholder for calls that
        // have no sales document behind them, so it must not map to a real entry type either.
        Initialize();

        // [WHEN] A quote is mapped
        asserterror AlvysSalesMgt.MapDocumentType(SalesHeader."Document Type"::Quote);

        // [THEN] The mapping is rejected
        Assert.ExpectedError('Sales documents of type Quote are not supported. Only orders and invoices can be sent to Alvys.');

        // [WHEN] A credit memo is mapped
        asserterror AlvysSalesMgt.MapDocumentType(SalesHeader."Document Type"::"Credit Memo");

        // [THEN] The mapping is rejected
        Assert.ExpectedError('Sales documents of type Credit Memo are not supported. Only orders and invoices can be sent to Alvys.');
    end;

    [Test]
    procedure GetDeductionReturnsCreatedDeduction()
    var
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        AmountObj, ResponseObj : JsonObject;
        JsonTkn: JsonToken;
        DeductionID: Text;
    begin
        // [SCENARIO] A deduction created in Alvys can be read back by its Id.
        Initialize();

        // [GIVEN] A deduction created in Alvys
        DeductionID := AlvysSalesMgt.CreateDeductionForTruck('TR2516627931370728085', '1', WorkDate(), -3.75, 'Test', 'BC test app - read back');

        // [WHEN] The deduction is read back by Id
        ResponseObj := AlvysSalesMgt.GetDeduction(DeductionID);

        // [THEN] Alvys returns the same deduction
        Assert.AreEqual(DeductionID, JsonMgt.GetJsonValueAsText(ResponseObj, 'Id'), 'GetDeduction should return the requested deduction.');
        Assert.AreEqual('TR2516627931370728085', JsonMgt.GetJsonValueAsText(ResponseObj, 'TruckId'), 'The deduction should be linked to the truck it was created for.');
        Assert.AreEqual('BC test app - read back', JsonMgt.GetJsonValueAsText(ResponseObj, 'Description'), 'The deduction should carry the description it was created with.');
        Assert.IsTrue(ResponseObj.Get('Amount', JsonTkn), 'The deduction should carry an amount.');
        AmountObj := JsonTkn.AsObject();
        Assert.AreEqual(-3.75, JsonMgt.GetJsonValueAsDecimal(AmountObj, 'Amount'), 'The deduction should carry the amount it was created with.');
    end;

    [Test]
    procedure GetDeductionWithBlankIDFails()
    begin
        // [SCENARIO] A deduction cannot be read back without an Id.
        Initialize();

        // [WHEN] A deduction is read back with a blank Id
        asserterror AlvysSalesMgt.GetDeduction('');

        // [THEN] The call is rejected before it reaches Alvys
        Assert.ExpectedError('The deduction Id cannot be blank.');
    end;

    [Test]
    procedure InboundAPIPageLogsEntryAsInbound()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] A driver pay call from Alvys is logged to the entry table as an inbound entry,
        // with the method and URL of the endpoint it arrived on.
        Initialize();

        // [WHEN] Alvys posts a driver pay payload to the API page
        InsertInboundEntry(LoggedDeductionId(PostedSalesInvoiceNo()), AlvysEntry);

        // [THEN] The entry is logged against the inbound direction, on the apply-deduction endpoint
        Assert.AreEqual(AlvysEntry.Direction::Inbound, AlvysEntry.Direction, 'An entry created through the API page should be inbound.');
        Assert.AreEqual('POST', AlvysEntry.Method, 'The inbound entry should be logged with the method of the endpoint.');
        Assert.AreEqual('/api/tanager/alvys/v1.0/alvysApplyDeductions', AlvysEntry.URL, 'The inbound entry should be logged with the URL of the endpoint.');
        Assert.AreEqual('', AlvysEntry."Error Message", 'A payload that matches a posted invoice should not log an error.');
    end;

    [Test]
    procedure InboundAPIPageRebuildsPayloadFromParameters()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        RequestBody: JsonObject;
        DeductionId: Text;
    begin
        // [SCENARIO] The page takes the six driver pay fields rather than a payload, so the request
        // body on the entry is rebuilt from them and has to carry every one back.
        Initialize();
        DeductionId := LoggedDeductionId(PostedSalesInvoiceNo());

        // [WHEN] Alvys posts a driver pay payload to the API page
        InsertInboundEntry(DeductionId, AlvysEntry);

        // [THEN] Every parameter is logged, under the field name Alvys sends it as
        Assert.IsTrue(RequestBody.ReadFrom(AlvysEntry.GetRequestBody()), 'The logged request body should be valid JSON.');
        Assert.AreEqual(DeductionId, JsonMgt.GetJsonValueAsText(RequestBody, 'DeductionId'), 'The logged payload should carry the deduction Id.');
        Assert.AreEqual('TR2516627931370728085', JsonMgt.GetJsonValueAsText(RequestBody, 'TruckId'), 'The logged payload should carry the truck Id.');
        Assert.AreEqual('1', JsonMgt.GetJsonValueAsText(RequestBody, 'TruckNumber'), 'The logged payload should carry the truck number.');
        Assert.AreEqual(-55.0, JsonMgt.GetJsonValueAsDecimal(RequestBody, 'Amount'), 'The logged payload should carry the amount.');
        Assert.AreEqual(Format(WorkDate(), 0, 9), JsonMgt.GetJsonValueAsText(RequestBody, 'SettlementDate'), 'The logged payload should carry the settlement date.');
        Assert.AreEqual('Settlement 12345', JsonMgt.GetJsonValueAsText(RequestBody, 'Description'), 'The logged payload should carry the description.');
    end;

    [Test]
    procedure InboundAPIPageMatchesDeductionToPostedInvoice()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        PostedDocumentNo: Code[20];
    begin
        // [SCENARIO] Alvys sends the deduction Id and nothing that identifies the receivable, so the
        // deduction is what the posted invoice on the entry is resolved from.
        Initialize();

        // [GIVEN] A deduction logged against a posted sales invoice
        PostedDocumentNo := PostedSalesInvoiceNo();

        // [WHEN] Alvys settles that deduction
        InsertInboundEntry(LoggedDeductionId(PostedDocumentNo), AlvysEntry);

        // [THEN] The entry points at the posted invoice the deduction was raised against
        Assert.AreEqual(AlvysEntry."Document Type"::"Posted Sales Invoice", AlvysEntry."Document Type", 'An apply-deduction entry should be logged against a posted sales invoice.');
        Assert.AreEqual(PostedDocumentNo, AlvysEntry."Document No.", 'The entry should carry the posted invoice the deduction was raised against.');
    end;

    [Test]
    procedure InboundAPIPageLogsUnknownDeduction()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] A payload that cannot be matched is still logged, since the entry table is the
        // record of what Alvys sent. The reason goes on the entry instead of the document number.
        Initialize();

        // [WHEN] Alvys settles a deduction Business Central has never seen
        InsertInboundEntry('4ba92c0d-736d-4b44-85d0-12c9fc9bad71', AlvysEntry);

        // [THEN] The call is logged, with no document and the reason it could not be matched
        Assert.AreNotEqual(0, AlvysEntry."Entry No.", 'An unmatched payload should still be logged.');
        Assert.AreEqual('', AlvysEntry."Document No.", 'An unmatched payload should not be pointed at a document.');
        Assert.IsTrue(AlvysEntry."Error Message".Contains('4ba92c0d-736d-4b44-85d0-12c9fc9bad71'), 'The error should name the deduction that could not be found.');
    end;

    [Test]
    procedure InboundAPIPageLogsUnpostedDeduction()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        DeductionId: Text;
    begin
        // [SCENARIO] A deduction still sitting on an unposted document has no posted invoice for the
        // settlement to apply against, so the entry says so rather than guessing at a document.
        Initialize();

        // [GIVEN] A deduction whose originating document has not been posted
        DeductionId := LoggedDeductionId('');

        // [WHEN] Alvys settles it
        InsertInboundEntry(DeductionId, AlvysEntry);

        // [THEN] The call is logged, with no document and the reason it could not be matched
        Assert.AreEqual('', AlvysEntry."Document No.", 'A deduction with no posted invoice should not be pointed at a document.');
        Assert.IsTrue(AlvysEntry."Error Message".Contains('has not been posted'), 'The error should say the originating document is unposted.');
    end;

    [Test]
    procedure InboundAPIPageLogsBlankDeduction()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] A payload with no deduction Id has nothing to match on. It is logged with the
        // reason, the same as any other payload that cannot be matched, so the API page refuses it.
        Initialize();

        // [WHEN] A payload arrives with no deduction Id
        InsertInboundEntry('', AlvysEntry);

        // [THEN] The call is logged, with no document and the reason it could not be matched
        Assert.AreNotEqual(0, AlvysEntry."Entry No.", 'A payload with no deduction Id should still be logged.');
        Assert.AreEqual('', AlvysEntry."Document No.", 'A payload with no deduction Id should not be pointed at a document.');
        Assert.AreEqual('The payload has no deduction Id, so there is nothing to match it to a posted invoice.', AlvysEntry."Error Message", 'The error should say the deduction Id is blank.');
    end;

    [Test]
    procedure InboundAPIPageRefusesPayloadNamingNoTruck()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] Alvys names the truck by either field, so a payload carrying neither identifies
        // no truck at all and is refused.
        Initialize();

        // [WHEN] A payload arrives with a blank truck Id and a blank truck number
        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), '', '', -55.0, WorkDate(), AlvysEntry);

        // [THEN] The call is logged with the reason it names no truck
        Assert.AreEqual('The payload names no truck: the truck Id and the truck number are both blank.', AlvysEntry."Error Message", 'The error should say the payload names no truck.');
    end;

    [Test]
    procedure InboundAPIPageAcceptsEitherTruckField()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] Either truck field on its own names the truck, so neither one alone is refused.
        Initialize();

        // [WHEN] A payload arrives with the truck Id only, and another with the truck number only
        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), 'TR2516627931370728085', '', -55.0, WorkDate(), AlvysEntry);

        // [THEN] Neither is refused
        Assert.AreEqual('', AlvysEntry."Error Message", 'A payload naming the truck by Id should not be refused.');

        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), '', '1', -55.0, WorkDate(), AlvysEntry);
        Assert.AreEqual('', AlvysEntry."Error Message", 'A payload naming the truck by number should not be refused.');
    end;

    [Test]
    procedure InboundAPIPageRefusesAmountThatAppliesNothing()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] A settlement has to apply an amount. An amount left out of the payload arrives
        // as zero, so a missing amount and one that would apply nothing are refused the same way.
        Initialize();

        // [WHEN] A payload arrives with no amount, and another with a positive one
        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), 'TR2516627931370728085', '1', 0, WorkDate(), AlvysEntry);

        // [THEN] Both are logged with the reason the amount cannot be applied
        Assert.IsTrue(AlvysEntry."Error Message".Contains('less than zero'), 'A payload with no amount should be refused.');

        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), 'TR2516627931370728085', '1', 55.0, WorkDate(), AlvysEntry);
        Assert.IsTrue(AlvysEntry."Error Message".Contains('less than zero'), 'A payload with a positive amount should be refused.');
    end;

    [Test]
    procedure InboundAPIPageRefusesPayloadWithNoSettlementDate()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] The settlement date is what the applied entry is dated by, so a payload without
        // one is refused rather than dated on a guess.
        Initialize();

        // [WHEN] A payload arrives with no settlement date
        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), 'TR2516627931370728085', '1', -55.0, 0D, AlvysEntry);

        // [THEN] The call is logged with the reason
        Assert.AreEqual('The payload has no settlement date.', AlvysEntry."Error Message", 'The error should say the settlement date is missing.');
    end;

    [Test]
    procedure InboundPayloadOmitsTruckFieldThatDidNotArrive()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        RequestBody: JsonObject;
        JsonToken: JsonToken;
    begin
        // [SCENARIO] The logged body is the record of what Alvys sent, so a truck field that did not
        // arrive is left out of it rather than written back as a blank Alvys never sent.
        Initialize();

        // [WHEN] A payload arrives naming the truck by number only
        InsertInboundEntryWith(LoggedDeductionId(PostedSalesInvoiceNo()), '', '1', -55.0, WorkDate(), AlvysEntry);

        // [THEN] The logged body carries the truck number and no truck Id key at all
        Assert.IsTrue(RequestBody.ReadFrom(AlvysEntry.GetRequestBody()), 'The logged request body should be valid JSON.');
        Assert.IsFalse(RequestBody.Get('TruckId', JsonToken), 'A truck Id that did not arrive should not be written to the logged body.');
        Assert.IsTrue(RequestBody.Get('TruckNumber', JsonToken), 'The truck number that arrived should be written to the logged body.');
    end;

    [Test]
    procedure InboundPayloadOmitsDescriptionThatDidNotArrive()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        RequestBody: JsonObject;
        JsonToken: JsonToken;
    begin
        // [SCENARIO] The description is optional, so a payload without one logs a body without the
        // key rather than a blank description.
        Initialize();

        // [WHEN] A payload arrives with no description
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareApplyDeductionEntry(AlvysEntry, LoggedDeductionId(PostedSalesInvoiceNo()), 'TR2516627931370728085', '1', -55.0, WorkDate(), '');
        AlvysEntry.Insert(true);

        // [THEN] The logged body has no description key
        Assert.IsTrue(RequestBody.ReadFrom(AlvysEntry.GetRequestBody()), 'The logged request body should be valid JSON.');
        Assert.IsFalse(RequestBody.Get('Description', JsonToken), 'A description that did not arrive should not be written to the logged body.');
    end;

    /// <summary>
    /// The API page refuses every payload that logs a reason, so only a matched settlement is
    /// answered 201. Which HTTP status comes back is a page-level concern and cannot be reached
    /// from a test session; the OData contract test covers that. What is checked here is the
    /// error text behind it, and that a matched settlement leaves none.
    /// </summary>
    [Test]
    procedure MatchedDeductionLeavesNoErrorToRefuseOn()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] A payload that does match a posted invoice carries no error, so the API page
        // has nothing to refuse it on and Alvys is answered 201.
        Initialize();

        // [WHEN] Alvys settles a deduction that is linked to a posted invoice
        InsertInboundEntry(LoggedDeductionId(PostedSalesInvoiceNo()), AlvysEntry);

        // [THEN] The entry carries a document and no error
        Assert.AreNotEqual('', AlvysEntry."Document No.", 'A matched deduction should be pointed at its posted invoice.');
        Assert.AreEqual('', AlvysEntry."Error Message", 'A matched deduction should leave nothing for the page to refuse on.');
    end;

    [Test]
    procedure UnpostedReasonNamesTheDocumentToPost()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        DeductionId: Text;
    begin
        // [SCENARIO] The settlement can be applied once the deduction's document is posted, so the
        // reason names that document — the actionable part — rather than the deduction alone.
        Initialize();

        // [GIVEN] A deduction sitting on an unposted document
        DeductionId := LoggedDeductionId('');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        AlvysDeduction.FindLast();
        AlvysDeduction."Document No." := 'S-INV1006';
        AlvysDeduction.Modify(true);

        // [WHEN] Alvys settles it
        InsertInboundEntry(DeductionId, AlvysEntry);

        // [THEN] The reason names the document to post
        Assert.IsTrue(AlvysEntry."Error Message".Contains('Sales Invoice'), 'The reason should name the document type to post.');
        Assert.IsTrue(AlvysEntry."Error Message".Contains('S-INV1006'), 'The reason should name the document number to post.');
    end;

    [Test]
    procedure ReasonsFitTheErrorMessageField()
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        DeductionId: Text;
    begin
        // [SCENARIO] The reason is truncated into the entry field before it is raised, so the
        // truncated text is what reaches Alvys. A reason that outgrows the field would be cut off
        // mid-sentence on the wire, silently. Each one is checked against the ceiling here.
        Initialize();

        // [WHEN] A deduction is settled against a document that has not been posted
        DeductionId := LoggedDeductionId('');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id)));
        AlvysDeduction.FindLast();
        AlvysDeduction."Document No." := 'S-INV1006';
        AlvysDeduction.Modify(true);
        InsertInboundEntry(DeductionId, AlvysEntry);

        // [THEN] The reason fits, and so does every other one
        Assert.IsTrue(StrLen(AlvysEntry."Error Message") < MaxStrLen(AlvysEntry."Error Message"), 'The unposted reason should fit the error message field without truncation.');

        InsertInboundEntry('4ba92c0d-736d-4b44-85d0-12c9fc9bad71', AlvysEntry);
        Assert.IsTrue(StrLen(AlvysEntry."Error Message") < MaxStrLen(AlvysEntry."Error Message"), 'The unknown deduction reason should fit the error message field without truncation.');

        InsertInboundEntry('', AlvysEntry);
        Assert.IsTrue(StrLen(AlvysEntry."Error Message") < MaxStrLen(AlvysEntry."Error Message"), 'The blank deduction reason should fit the error message field without truncation.');

        InsertInboundEntry(LoggedDeductionId('S-INV-GONE'), AlvysEntry);
        Assert.IsTrue(StrLen(AlvysEntry."Error Message") < MaxStrLen(AlvysEntry."Error Message"), 'The missing invoice reason should fit the error message field without truncation.');
    end;

    [Test]
    procedure InboundAPIPageAssignsNextEntryNo()
    var
        FirstEntry, SecondEntry : Record "BAASI Alvys Sales Entry";
        DeductionId: Text;
    begin
        // [SCENARIO] The API page numbers inbound entries itself, since the caller cannot.
        Initialize();
        DeductionId := LoggedDeductionId(PostedSalesInvoiceNo());

        // [WHEN] Two driver pay payloads arrive
        InsertInboundEntry(DeductionId, FirstEntry);
        InsertInboundEntry(DeductionId, SecondEntry);

        // [THEN] Each entry is given the next number in the log
        Assert.AreNotEqual(0, FirstEntry."Entry No.", 'An inbound entry should be given an entry number.');
        Assert.AreEqual(FirstEntry."Entry No." + 1, SecondEntry."Entry No.", 'The second inbound entry should take the next entry number.');
    end;

    [Test]
    procedure OutboundCallsAreLoggedAsOutbound()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
    begin
        // [SCENARIO] Calls Business Central sends to Alvys keep the outbound direction, so the log
        // separates the two legs.
        Initialize();

        // [WHEN] A truck is looked up in Alvys
        AlvysSalesMgt.GetTruckID('1');

        // [THEN] The call is logged as outbound
        AlvysEntry.FindLast();
        Assert.AreEqual(AlvysEntry.Direction::Outbound, AlvysEntry.Direction, 'A call sent to Alvys should be logged as outbound.');
    end;

    [Test]
    procedure InboundEntriesAreSeparableFromOutboundEntries()
    var
        AlvysEntry: Record "BAASI Alvys Sales Entry";
        InboundEntry: Record "BAASI Alvys Sales Entry";
        InboundEntryNo: Integer;
    begin
        // [SCENARIO] The direction filter the API page carries returns the inbound entries only,
        // never the outbound log.
        Initialize();

        // [GIVEN] An outbound call and an inbound call have both been logged
        AlvysSalesMgt.GetTruckID('1');
        InsertInboundEntry(LoggedDeductionId(PostedSalesInvoiceNo()), InboundEntry);
        InboundEntryNo := InboundEntry."Entry No.";

        // [WHEN] The log is read through the filter the API page applies
        AlvysEntry.SetRange(Direction, AlvysEntry.Direction::Inbound);

        // [THEN] Only inbound entries come back, and the inbound entry is among them
        Assert.IsTrue(AlvysEntry.FindSet(), 'The direction filter should return the inbound entry.');
        repeat
            Assert.AreEqual(AlvysEntry.Direction::Inbound, AlvysEntry.Direction, 'The API page filter should not expose outbound entries.');
        until AlvysEntry.Next() = 0;

        AlvysEntry.SetRange("Entry No.", InboundEntryNo);
        Assert.IsFalse(AlvysEntry.IsEmpty(), 'The inbound entry should be readable through the page filter.');
    end;

    /// <summary>
    /// Settles a deduction the way the API page does when Alvys posts one, and hands back the entry
    /// it created. The page's insert trigger is a single call to PrepareApplyDeductionEntry, so
    /// going through the codeunit exercises the same matching, numbering and direction logic; the
    /// OData plumbing around it cannot be reached from a test session.
    ///
    /// The remaining five parameters are the driver pay payload as described in the technical
    /// scope. The field names are still Alvys' to confirm, so this is the shape the page has to
    /// survive, not a contract.
    /// </summary>
    local procedure InsertInboundEntry(DeductionId: Text; var AlvysEntry: Record "BAASI Alvys Sales Entry")
    begin
        InsertInboundEntryWith(DeductionId, 'TR2516627931370728085', '1', -55.0, WorkDate(), AlvysEntry);
    end;

    /// <summary>
    /// The same call with the payload fields the checks are about left open, for the tests that send
    /// one of them blank. The description is not among them: it is optional either way.
    /// </summary>
    local procedure InsertInboundEntryWith(DeductionId: Text; TruckId: Text; TruckNumber: Text; Amount: Decimal; SettlementDate: Date; var AlvysEntry: Record "BAASI Alvys Sales Entry")
    begin
        AlvysEntry.Init();
        AlvysSalesMgt.PrepareApplyDeductionEntry(AlvysEntry, DeductionId, TruckId, TruckNumber, Amount, SettlementDate, 'Settlement 12345');
        AlvysEntry.Insert(true);
    end;

    /// <summary>
    /// Logs a deduction against a posted sales invoice and hands back its Alvys Id, so the inbound
    /// call has something to match on. Pass a blank document number for a deduction whose
    /// originating document has not been posted yet. Nothing is sent to Alvys: these tests are
    /// about how Business Central resolves an Id it has already recorded.
    /// </summary>
    local procedure LoggedDeductionId(PostedDocumentNo: Code[20]): Text
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        LastDeduction: Record "BAASI Alvys Deduction";
        DeductionId: Text;
    begin
        DeductionId := DelChr(Format(CreateGuid()), '=', '{}');
        AlvysDeduction.Init();
        if LastDeduction.FindLast() then
            AlvysDeduction."Entry No." := LastDeduction."Entry No." + 1
        else
            AlvysDeduction."Entry No." := 1;
        AlvysDeduction.Id := CopyStr(DeductionId, 1, MaxStrLen(AlvysDeduction.Id));
        AlvysDeduction."Truck Id" := 'TR2516627931370728085';
        AlvysDeduction."Truck Number" := '1';
        AlvysDeduction.Amount := -55.0;
        AlvysDeduction.Date := WorkDate();
        AlvysDeduction."Document Type" := AlvysDeduction."Document Type"::"Sales Invoice";
        AlvysDeduction."Posted Document No." := PostedDocumentNo;
        AlvysDeduction.Insert(true);
        exit(DeductionId);
    end;

    /// <summary>
    /// A posted sales invoice in the company to hang a deduction off. Any one will do: these tests
    /// check that the entry is pointed at the invoice the deduction names, not which invoice it is.
    /// </summary>
    local procedure PostedSalesInvoiceNo(): Code[20]
    var
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        Assert.IsTrue(SalesInvHeader.FindLast(), 'The company needs at least one posted sales invoice for the inbound tests to match against.');
        exit(SalesInvHeader."No.");
    end;

    /// <summary>
    /// Checks that the environment carries the endpoint and credentials the integration needs, and
    /// clears any cached token so each test starts from a fresh authentication. The credentials are
    /// deliberately read from the setup record rather than written here, to keep the Alvys client
    /// secret out of source control.
    /// </summary>
    local procedure Initialize()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
    begin
        AlvysSetup.Get();
        AlvysSetup.TestField("Integration URL");
        AlvysSetup.TestField("Client ID");
        AlvysSetup.TestField("Client Secret");
        AlvysSetup.TestField("Tractor Code Dimension");
        AlvysSetup.SetAccessToken('');
        AlvysSetup."Access Token Expiry Date" := 0DT;
        AlvysSetup.Modify();

        Clear(AlvysSalesMgt);
    end;

    /// <summary>
    /// Builds a dimension set holding the tractor code dimension set up for the integration, so a
    /// document can be pointed at a truck without a posted document existing. The dimension value is
    /// created if the company does not already have one; test isolation rolls it back afterwards.
    /// </summary>
    local procedure TractorCodeDimensionSetID(TractorCode: Code[20]): Integer
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        DimValue: Record "Dimension Value";
        TempDimSetEntry: Record "Dimension Set Entry" temporary;
        DimMgt: Codeunit DimensionManagement;
    begin
        AlvysSetup.Get();
        AlvysSetup.TestField("Tractor Code Dimension");
        if not DimValue.Get(AlvysSetup."Tractor Code Dimension", TractorCode) then begin
            DimValue.Init();
            DimValue.Validate("Dimension Code", AlvysSetup."Tractor Code Dimension");
            DimValue.Validate(Code, TractorCode);
            DimValue.Insert(true);
        end;

        TempDimSetEntry.Init();
        TempDimSetEntry."Dimension Code" := DimValue."Dimension Code";
        TempDimSetEntry."Dimension Value Code" := DimValue.Code;
        TempDimSetEntry."Dimension Value ID" := DimValue."Dimension Value ID";
        TempDimSetEntry.Insert();
        exit(DimMgt.GetDimensionSetID(TempDimSetEntry));
    end;

    var
        Assert: Codeunit "Library Assert";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
}
