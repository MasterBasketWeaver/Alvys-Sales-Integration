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
        DeductionID := AlvysSalesMgt.CreateDeductionForTruck('TR2516627931370728085', WorkDate(), -1.25, 'Test', 'BC test app - truck deduction');

        // [THEN] Alvys returns an Id and the deduction is logged against the truck
        Assert.AreNotEqual('', DeductionID, 'CreateDeductionForTruck should return the Alvys deduction Id.');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionID, 1, MaxStrLen(AlvysDeduction.Id)));
        Assert.IsTrue(AlvysDeduction.FindLast(), 'The created deduction should be logged in the Alvys Deduction table.');
        Assert.AreEqual('TR2516627931370728085', AlvysDeduction."Truck Id", 'The logged deduction should carry the truck Id.');
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
        DeductionID := AlvysSalesMgt.CreateDeductionForTruck(SalesHeader, SalesInvHeader, WorkDate(), -4.5, 'Test', 'BC test app - posted invoice deduction');

        // [THEN] The deduction is created against the truck the dimension resolves to
        Assert.AreNotEqual('', DeductionID, 'CreateDeductionForTruck should return the Alvys deduction Id.');
        AlvysDeduction.SetRange(Id, CopyStr(DeductionID, 1, MaxStrLen(AlvysDeduction.Id)));
        Assert.IsTrue(AlvysDeduction.FindLast(), 'The created deduction should be logged in the Alvys Deduction table.');
        Assert.AreEqual('TR2516627931370728085', AlvysDeduction."Truck Id", 'The truck should be resolved from the tractor code dimension on the posted invoice.');
        Assert.AreEqual(-4.5, AlvysDeduction.Amount, 'The logged deduction should carry the requested amount.');

        // [THEN] Both the originating document and the posted invoice are recorded on it
        Assert.AreEqual(SalesHeader."Document Type"::Order, AlvysDeduction."Document Type", 'The deduction should carry the document type it was posted from.');
        Assert.AreEqual('ALVYS-TEST-ORD', AlvysDeduction."Document No.", 'The deduction should carry the number of the document it was posted from.');
        Assert.AreEqual('ALVYS-TEST-INV', AlvysDeduction."Posted Document No.", 'The deduction should carry the posted invoice number.');
    end;

    [Test]
    procedure CreateDeductionForTruckFromPostedInvoiceWithoutTractorCodeFails()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        SalesHeader: Record "Sales Header";
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        // [SCENARIO] A posted invoice without the tractor code dimension has no truck to deduct from.
        Initialize();

        // [GIVEN] An order and an invoice whose dimension set does not hold the tractor code
        SalesHeader."Document Type" := SalesHeader."Document Type"::Order;
        SalesHeader."No." := 'ALVYS-TEST-ORD';
        SalesInvHeader."No." := 'ALVYS-TEST-INV';
        SalesInvHeader."Dimension Set ID" := 0;

        // [WHEN] A deduction is created for the posted invoice
        asserterror AlvysSalesMgt.CreateDeductionForTruck(SalesHeader, SalesInvHeader, WorkDate(), -4.5, 'Test', 'BC test app - no tractor code');

        // [THEN] The call is rejected before it reaches Alvys
        AlvysSetup.Get();
        Assert.ExpectedError(StrSubstNo('The document does not have a value for the %1 dimension.', AlvysSetup."Tractor Code Dimension"));
    end;

    [Test]
    procedure CreateDeductionWithBlankAssetIDFails()
    begin
        // [SCENARIO] A deduction cannot be created without a truck or driver Id.
        Initialize();

        // [WHEN] A deduction is created with a blank truck Id
        asserterror AlvysSalesMgt.CreateDeductionForTruck('', WorkDate(), -1.25, 'Test', 'BC test app - blank truck');

        // [THEN] The call is rejected before it reaches Alvys
        Assert.ExpectedError('The TruckId cannot be blank when creating a deduction.');
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
        DeductionID := AlvysSalesMgt.CreateDeductionForTruck('TR2516627931370728085', WorkDate(), -3.75, 'Test', 'BC test app - read back');

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
