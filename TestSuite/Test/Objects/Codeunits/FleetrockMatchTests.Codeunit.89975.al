codeunit 89975 "BAASIT Fleetrock Match Tests"
{
    // [FEATURE] [Fleetrock Integration] [Customer/Vendor Matching]
    //
    // How a Fleetrock repair order's customer or a purchase order's supplier is matched to an
    // existing BC customer or vendor before the import creates a new one. Every record is created
    // by the test under a No. and name carrying a fresh token, so the company's own customers and
    // vendors can't match; the matching scans them all, though, so they must not share the token.

#if not PRODUCTION
    Subtype = Test;
    TestPermissions = Disabled;
#endif

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerIsFoundByExactSourceNo()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
    begin
        // [SCENARIO] A customer whose Source No. is the Fleetrock company id is found by it, even
        // when its name has nothing in common with the Fleetrock name.
        Initialize();
        CustomerNo := CreateCustomer('1', UniqueName('Customer'), 'CID-' + Token, false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('CID-' + Token, UniqueName('Other name'), Customer), 'The customer should be found by its Source No.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the Source No. should be found.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerIsFoundBySourceNoInAnotherCase()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
    begin
        // [SCENARIO] Source No. is compared ignoring case and surrounding spaces.
        Initialize();
        CustomerNo := CreateCustomer('1', UniqueName('Customer'), UniqueName('Mixed Case Source'), false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('  ' + UpperCase(UniqueName('Mixed Case Source')) + ' ', '', Customer), 'The customer should be found by its Source No. in another case.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the Source No. should be found.');

        Customer.Get(CustomerNo);
        Assert.AreEqual(UniqueName('Mixed Case Source'), Customer."FRI Fleetrock Source No.", 'A Source No. found in another case should be left as it is.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerIsFoundByNameIgnoringCaseAndGetsSourceNo()
    var
        Customer: Record Customer;
        AllCustomers: Record Customer;
        CustomerNo: Code[20];
        CustomerCount: Integer;
    begin
        // [SCENARIO] A customer with no Source No. whose Name is the Fleetrock name in another case
        // is used, and the Source No. is written onto it so the next import finds it directly.
        Initialize();
        CustomerNo := CreateCustomer('1', UpperCase(UniqueName('Name Match')), '', false);
        CustomerCount := AllCustomers.Count();

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer(UniqueName('Name Match'), UniqueName('Name Match'), Customer), 'The customer should be found by name.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the matching name should be found.');

        Customer.Get(CustomerNo);
        Assert.AreEqual(UniqueName('Name Match'), Customer."FRI Fleetrock Source No.", 'The Source No. should be written onto the customer found by name.');
        Assert.AreEqual(CustomerCount, AllCustomers.Count(), 'No customer should be created.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerFoundByNameWithCompanyIdGetsTheCompanyId()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
    begin
        // [SCENARIO] When the repair order has a customer company id, the customer is still found
        // by the Fleetrock customer name, and the company id becomes its Source No.
        Initialize();
        CustomerNo := CreateCustomer('1', UpperCase(UniqueName('Company')), '', false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('CID-' + Token, UniqueName('Company'), Customer), 'The customer should be found by name.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the matching name should be found.');

        Customer.Get(CustomerNo);
        Assert.AreEqual('CID-' + Token, Customer."FRI Fleetrock Source No.", 'The company id should be written onto the customer found by name.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerFoundByNameKeepsItsOtherSourceNo()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
    begin
        // [SCENARIO] A customer found by name that already carries another Source No. is used but
        // keeps that Source No., so the import it came from still finds it.
        Initialize();
        CustomerNo := CreateCustomer('1', UniqueName('Linked'), 'CID-OLD-' + Token, false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('CID-NEW-' + Token, LowerCase(UniqueName('Linked')), Customer), 'The customer should be found by name.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the matching name should be found.');

        Customer.Get(CustomerNo);
        Assert.AreEqual('CID-OLD-' + Token, Customer."FRI Fleetrock Source No.", 'The existing Source No. should not be overwritten.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerWithFilterCharactersIsFoundByName()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
    begin
        // [SCENARIO] Names holding BC filter characters are matched literally: a customer whose
        // name differs only by the wildcards is not taken for the one with them.
        Initialize();
        CreateCustomer('1', 'A&B (TEST) CO.''S FLEET ' + Token, '', false);
        CustomerNo := CreateCustomer('2', SpecialName(), '', false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer(LowerCase(SpecialName()), LowerCase(SpecialName()), Customer), 'The customer should be found by a name with filter characters.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with exactly that name should be found.');

        Customer.Get(CustomerNo);
        Assert.AreEqual(LowerCase(SpecialName()), Customer."FRI Fleetrock Source No.", 'The Source No. should be written as Fleetrock sent it.');

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer(UpperCase(SpecialName()), '', Customer), 'The customer should be found by a Source No. with filter characters.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with exactly that Source No. should be found.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerNameWithTrailingSpacesOrTooLongIsFound()
    var
        Customer: Record Customer;
        CustomerNo, LongCustomerNo : Code[20];
        LongName: Text;
    begin
        // [SCENARIO] Trailing spaces don't stop a match, and a Fleetrock name longer than a BC name
        // matches the customer holding as much of it as fits.
        Initialize();
        CustomerNo := CreateCustomer('1', UniqueName('Spaces'), '', false);
        LongName := 'BAASIT ' + Token + ' ' + PadStr('', 100, 'x') + ' and the rest';
        LongCustomerNo := CreateCustomer('2', UpperCase(CopyStr(LongName, 1, MaxStrLen(Customer.Name))), '', false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('', UniqueName('Spaces') + '   ', Customer), 'The customer should be found despite trailing spaces.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the name should be found.');

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer(LongName, LongName, Customer), 'The customer should be found by a name longer than the Name field.');
        Assert.AreEqual(LongCustomerNo, Customer."No.", 'The customer holding the start of the long name should be found.');
        Customer.Get(LongCustomerNo);
        Assert.AreEqual(CopyStr(LongName, 1, MaxStrLen(Customer."FRI Fleetrock Source No.")), Customer."FRI Fleetrock Source No.", 'The long Source No. should be cut to the field length.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure UnblockedCustomerIsPreferredThenLowestNo()
    var
        Customer: Record Customer;
        SecondNo: Code[20];
    begin
        // [SCENARIO] Among customers with the same name an unblocked one wins over a blocked one
        // with a lower No., and among unblocked ones the lowest No. wins.
        Initialize();
        CreateCustomer('1', UniqueName('Duplicate'), '', true);
        SecondNo := CreateCustomer('2', UpperCase(UniqueName('Duplicate')), '', false);
        CreateCustomer('3', UniqueName('Duplicate'), '', false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('', UniqueName('Duplicate'), Customer), 'A customer should be found by name.');
        Assert.AreEqual(SecondNo, Customer."No.", 'The unblocked customer with the lowest No. should be found.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure SourceNoMatchWinsOverNameMatch()
    var
        Customer: Record Customer;
        SourceNoCustomerNo: Code[20];
    begin
        // [SCENARIO] A customer found by Source No. is used even when another customer, with a lower
        // No., has the Fleetrock name.
        Initialize();
        CreateCustomer('1', UniqueName('Both'), '', false);
        SourceNoCustomerNo := CreateCustomer('2', UniqueName('Renamed'), 'CID-' + Token, false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer('cid-' + Token, UniqueName('Both'), Customer), 'A customer should be found.');
        Assert.AreEqual(SourceNoCustomerNo, Customer."No.", 'The customer with the Source No. should win over the one with the name.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure RepairOrderCustomerNameFindsUppercaseCustomer()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
        FleetrockName: Text;
    begin
        // [SCENARIO] The Texas Transportation Group case: the repair order has no customer company
        // id and customer_name "Double Diamond Transport Inc.", and the BC customer is named in
        // capitals. It is found with the Source No. set, and by name when the Source No. is blank.
        Initialize();
        FleetrockName := 'Double Diamond Transport Inc. ' + Token;
        CustomerNo := CreateCustomer('1', UpperCase(FleetrockName), FleetrockName, false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer(FleetrockName, FleetrockName, Customer), 'The customer should be found by its Source No.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the Source No. should be found.');

        Customer.Get(CustomerNo);
        Customer."FRI Fleetrock Source No." := '';
        Customer.Modify(false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingCustomer(FleetrockName, FleetrockName, Customer), 'The customer should be found by name.');
        Assert.AreEqual(CustomerNo, Customer."No.", 'The customer with the name in capitals should be found.');
        Customer.Get(CustomerNo);
        Assert.AreEqual(FleetrockName, Customer."FRI Fleetrock Source No.", 'The Source No. should be written onto the customer found by name.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure CustomerIsNotFoundWithoutAMatch()
    var
        Customer: Record Customer;
        CustomerNo: Code[20];
    begin
        // [SCENARIO] With neither the Source No. nor the name matching, nothing is found and no
        // customer is changed, so the import creates a new one.
        Initialize();
        CustomerNo := CreateCustomer('1', UniqueName('Someone'), '', false);

        Assert.IsFalse(FleetrockMgt.FindOrLinkExistingCustomer('CID-' + Token, UniqueName('Someone Else'), Customer), 'No customer should be found.');
        Assert.IsFalse(FleetrockMgt.FindOrLinkExistingCustomer('', '', Customer), 'No customer should be found for a blank Source No. and name.');

        Customer.Get(CustomerNo);
        Assert.AreEqual('', Customer."FRI Fleetrock Source No.", 'A customer that did not match should not get a Source No.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure VendorIsFoundByExactSourceNo()
    var
        Vendor: Record Vendor;
        VendorNo: Code[20];
    begin
        // [SCENARIO] A vendor whose Source No. is the Fleetrock supplier name is found by it, even
        // when its own name was changed in BC.
        Initialize();
        VendorNo := CreateVendor('1', UniqueName('Renamed Vendor'), UniqueName('Supplier'), false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingVendor(UniqueName('Supplier'), UniqueName('Supplier'), Vendor), 'The vendor should be found by its Source No.');
        Assert.AreEqual(VendorNo, Vendor."No.", 'The vendor with the Source No. should be found.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure VendorIsFoundBySourceNoInAnotherCase()
    var
        Vendor: Record Vendor;
        VendorNo: Code[20];
    begin
        // [SCENARIO] Source No. is compared ignoring case and surrounding spaces.
        Initialize();
        VendorNo := CreateVendor('1', UniqueName('Renamed Vendor'), UniqueName('Supplier'), false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingVendor(UpperCase(UniqueName('Supplier')) + ' ', UpperCase(UniqueName('Supplier')) + ' ', Vendor), 'The vendor should be found by its Source No. in another case.');
        Assert.AreEqual(VendorNo, Vendor."No.", 'The vendor with the Source No. should be found.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure VendorIsFoundByNameIgnoringCaseAndGetsSourceNo()
    var
        Vendor: Record Vendor;
        AllVendors: Record Vendor;
        VendorNo: Code[20];
        VendorCount: Integer;
    begin
        // [SCENARIO] A vendor with no Source No. whose Name is the supplier name in another case is
        // used, and the Source No. is written onto it.
        Initialize();
        VendorNo := CreateVendor('1', UpperCase(UniqueName('Name Match')), '', false);
        VendorCount := AllVendors.Count();

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingVendor(UniqueName('Name Match'), UniqueName('Name Match'), Vendor), 'The vendor should be found by name.');
        Assert.AreEqual(VendorNo, Vendor."No.", 'The vendor with the matching name should be found.');

        Vendor.Get(VendorNo);
        Assert.AreEqual(UniqueName('Name Match'), Vendor."FRI Fleetrock Source No.", 'The Source No. should be written onto the vendor found by name.');
        Assert.AreEqual(VendorCount, AllVendors.Count(), 'No vendor should be created.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure VendorWithFilterCharactersIsFoundByName()
    var
        Vendor: Record Vendor;
        VendorNo: Code[20];
    begin
        // [SCENARIO] Supplier names holding BC filter characters are matched literally.
        Initialize();
        CreateVendor('1', 'A&B (TEST) CO.''S FLEET ' + Token, '', false);
        VendorNo := CreateVendor('2', SpecialName(), '', false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingVendor(LowerCase(SpecialName()), LowerCase(SpecialName()), Vendor), 'The vendor should be found by a name with filter characters.');
        Assert.AreEqual(VendorNo, Vendor."No.", 'The vendor with exactly that name should be found.');

        Vendor.Get(VendorNo);
        Assert.AreEqual(LowerCase(SpecialName()), Vendor."FRI Fleetrock Source No.", 'The Source No. should be written as Fleetrock sent it.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure UnblockedVendorIsPreferredThenLowestNo()
    var
        Vendor: Record Vendor;
        SecondNo: Code[20];
    begin
        // [SCENARIO] Among vendors with the same name an unblocked one wins over a blocked one with
        // a lower No., and among unblocked ones the lowest No. wins.
        Initialize();
        CreateVendor('1', UniqueName('Duplicate'), '', true);
        SecondNo := CreateVendor('2', UniqueName('Duplicate'), '', false);
        CreateVendor('3', LowerCase(UniqueName('Duplicate')), '', false);

        Assert.IsTrue(FleetrockMgt.FindOrLinkExistingVendor(UniqueName('Duplicate'), UniqueName('Duplicate'), Vendor), 'A vendor should be found by name.');
        Assert.AreEqual(SecondNo, Vendor."No.", 'The unblocked vendor with the lowest No. should be found.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure VendorIsNotFoundWithoutAMatch()
    var
        Vendor: Record Vendor;
        VendorNo: Code[20];
    begin
        // [SCENARIO] With neither the Source No. nor the name matching, nothing is found and no
        // vendor is changed, so the import creates a new one.
        Initialize();
        VendorNo := CreateVendor('1', UniqueName('Someone'), '', false);

        Assert.IsFalse(FleetrockMgt.FindOrLinkExistingVendor(UniqueName('Someone Else'), UniqueName('Someone Else'), Vendor), 'No vendor should be found.');

        Vendor.Get(VendorNo);
        Assert.AreEqual('', Vendor."FRI Fleetrock Source No.", 'A vendor that did not match should not get a Source No.');

        Cleanup();
    end;

#if not PRODUCTION
    [Test]
#endif
    procedure PurchaseOrderImportUsesVendorFoundByName()
    var
        PurchHeaderStaging: Record "FRI Purchase Header";
        PurchaseHeader: Record "Purchase Header";
        Vendor: Record Vendor;
        AllVendors: Record Vendor;
        VendorNo, DocNo : Code[20];
        VendorCount: Integer;
    begin
        // [SCENARIO] The purchase order import, which calls Fleetrock only to fill in a vendor it
        // creates, uses the vendor whose name matches the supplier in another case and links it.
        // The repair order import can't be tested this way: it reads the customer from Fleetrock's
        // GetUsers whether or not the customer exists.
        Initialize();
        VendorNo := CreateVendor('1', UpperCase(UniqueName('PO Supplier')), '', false);
        VendorCount := AllVendors.Count();

        // [GIVEN] A staged purchase order from that supplier, never imported before
        PurchHeaderStaging.id := CopyStr('T' + Token, 1, MaxStrLen(PurchHeaderStaging.id));
        PurchHeaderStaging.supplier_name := CopyStr(UniqueName('PO Supplier'), 1, MaxStrLen(PurchHeaderStaging.supplier_name));
        PurchHeaderStaging.Opened := CurrentDateTime();

        // [WHEN] The purchase order is created from it
        if not FleetrockMgt.TryToCreatePurchaseOrder(PurchHeaderStaging, DocNo) then
            Assert.Fail(StrSubstNo('The purchase order should be created: %1', GetLastErrorText()));

        // [THEN] It is for the existing vendor, which now has the Source No., and no vendor was created
        PurchaseHeader.Get(PurchaseHeader."Document Type"::Order, DocNo);
        Assert.AreEqual(VendorNo, PurchaseHeader."Buy-from Vendor No.", 'The purchase order should be for the vendor found by name.');
        Vendor.Get(VendorNo);
        Assert.AreEqual(UniqueName('PO Supplier'), Vendor."FRI Fleetrock Source No.", 'The Source No. should be written onto the vendor found by name.');
        Assert.AreEqual(VendorCount, AllVendors.Count(), 'No vendor should be created.');

        if TestMode.GetKeepData() then
            exit;
        PurchaseHeader.Delete(true);
        Cleanup();
    end;

    local procedure Initialize()
    begin
        Token := CopyStr(DelChr(Format(CreateGuid()), '=', '{}-'), 1, 12);
    end;

    local procedure UniqueName(Name: Text): Text
    begin
        exit('BAASIT ' + Name + ' ' + Token);
    end;

    local procedure SpecialName(): Text
    begin
        exit('A&B (Test) Co.''s *Fleet* |?<>=.@ ' + Token);
    end;

    local procedure TestNo(Suffix: Text): Code[20]
    begin
        exit(CopyStr('BAASIT' + Token + Suffix, 1, 20));
    end;

    local procedure CreateCustomer(Suffix: Text; CustomerName: Text; SourceNo: Text; IsBlocked: Boolean): Code[20]
    var
        Customer: Record Customer;
    begin
        Customer.Init();
        Customer."No." := TestNo(Suffix);
        Customer.Name := CopyStr(CustomerName, 1, MaxStrLen(Customer.Name));
        Customer."FRI Fleetrock Source No." := CopyStr(SourceNo, 1, MaxStrLen(Customer."FRI Fleetrock Source No."));
        if IsBlocked then
            Customer.Blocked := Customer.Blocked::All;
        Customer.Insert(false);
        exit(Customer."No.");
    end;

    local procedure CreateVendor(Suffix: Text; VendorName: Text; SourceNo: Text; IsBlocked: Boolean): Code[20]
    var
        Vendor: Record Vendor;
        FleetrockSetup: Record "FRI Fleetrock Setup";
        VendorPostingGroup: Record "Vendor Posting Group";
    begin
        Vendor.Init();
        Vendor."No." := TestNo(Suffix);
        Vendor.Name := CopyStr(VendorName, 1, MaxStrLen(Vendor.Name));
        Vendor."FRI Fleetrock Source No." := CopyStr(SourceNo, 1, MaxStrLen(Vendor."FRI Fleetrock Source No."));
        if IsBlocked then
            Vendor.Blocked := Vendor.Blocked::All;
        // Posting groups only for the purchase order test, which puts the vendor on a document.
        if FleetrockSetup.Get() then begin
            Vendor."Vendor Posting Group" := FleetrockSetup."Vendor Posting Group";
            Vendor."Gen. Bus. Posting Group" := FleetrockSetup."Gen. Busi. Posting Group";
        end;
        if Vendor."Vendor Posting Group" = '' then
            if VendorPostingGroup.FindFirst() then
                Vendor."Vendor Posting Group" := VendorPostingGroup.Code;
        Vendor.Insert(false);
        exit(Vendor."No.");
    end;

    // A keep-data run has no rollback, and these fixtures tell nothing worth keeping.
    local procedure Cleanup()
    var
        Customer: Record Customer;
        Vendor: Record Vendor;
    begin
        Customer.SetRange("No.", TestNo(''), TestNo('ZZ'));
        Customer.DeleteAll(false);
        Vendor.SetRange("No.", TestNo(''), TestNo('ZZ'));
        Vendor.DeleteAll(false);
    end;

    var
        Assert: Codeunit "BAASIT Assert";
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
        TestMode: Codeunit "BAASIT Test Mode";
        Token: Text[12];
}
