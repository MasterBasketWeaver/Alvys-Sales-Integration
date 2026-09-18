codeunit 89967 "BAASIT Alvys Dim Import Tests"
{
    // [FEATURE] [Alvys Sales Integration] [Driver/Truck Import]
    //
    // Imports into two dimensions created by the test rather than the setup's own, so every value
    // starts out missing and nothing a test asserts on depends on the company's data. The two
    // tests named for Alvys call the live Alvys and Fleetrock APIs, the second one importing into
    // the company's own truck and driver dimensions; the runner's test isolation rolls that back.

    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure ImportTrucksCreatesValuePerTruckNumber()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] Each Alvys truck becomes a tractor dimension value coded by its truck number.
        Initialize();

        // [GIVEN] Two trucks, one numbered in lower case
        Trucks.Add(Truck('bt-101', ActiveTok));
        Trucks.Add(Truck('BT-102', ActiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] Both are there, unblocked, under the truck number in upper case
        Assert.IsTrue(DimValue.Get(TruckDimTok, 'BT-101'), 'A lower case truck number should be imported in upper case.');
        Assert.IsFalse(DimValue.Blocked, 'An active truck should not be blocked.');
        Assert.IsTrue(DimValue.Get(TruckDimTok, 'BT-102'), 'Every truck should be imported.');
    end;

    [Test]
    procedure ImportTrucksNamesTruckAfterFleetrockDriver()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck is named after the driver Fleetrock has on the truck's VIN, through the
        // Fleetrock app's own SetDimensionValueDriverName.
        Initialize();

        // [GIVEN] A truck that Fleetrock knows as a unit, with a driver on its VIN
        Trucks.Add(Truck('BT-201', ActiveTok));
        FleetrockUnits.Add(FleetrockUnit('BT-201', 'VIN-BT-201'));
        FleetrockDrivers.Add(FleetrockDriver('Pat', 'Lee', 'VIN-BT-201'));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] The truck is named after the driver
        DimValue.Get(TruckDimTok, 'BT-201');
        Assert.AreEqual('Pat Lee', DimValue.Name, 'The truck should be named after its Fleetrock driver.');
    end;

    [Test]
    procedure ImportTrucksNamesTruckAfterActiveFleetrockDriverOnly()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] Fleetrock keeps a VIN's earlier drivers, deactivated, ahead of its current one.
        // A truck is named after the active driver, and a truck with none keeps its name.
        Initialize();

        // [GIVEN] One truck whose deactivated driver comes before its active one, and one whose
        // only driver is deactivated
        InsertDimValue(TruckDimTok, 'BT-211', 'Keep Me', false);
        Trucks.Add(Truck('BT-210', ActiveTok));
        Trucks.Add(Truck('BT-211', ActiveTok));
        FleetrockUnits.Add(FleetrockUnit('BT-210', 'VIN-BT-210'));
        FleetrockUnits.Add(FleetrockUnit('BT-211', 'VIN-BT-211'));
        FleetrockDrivers.Add(FleetrockDriverWithStatus('Old', 'Driver', 'VIN-BT-210', DeactivatedTok));
        FleetrockDrivers.Add(FleetrockDriver('Current', 'Driver', 'VIN-BT-210'));
        FleetrockDrivers.Add(FleetrockDriverWithStatus('Gone', 'Driver', 'VIN-BT-211', DeactivatedTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] The first is named after its active driver and the second is left alone
        DimValue.Get(TruckDimTok, 'BT-210');
        Assert.AreEqual('Current Driver', DimValue.Name, 'The truck should be named after its active Fleetrock driver.');
        DimValue.Get(TruckDimTok, 'BT-211');
        Assert.AreEqual('Keep Me', DimValue.Name, 'A truck whose only Fleetrock driver is deactivated should keep its name.');
    end;

    [Test]
    procedure ImportTrucksRenamesTruckWhenFleetrockDriverChanges()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck handed to another driver in Fleetrock is renamed on the next import.
        Initialize();

        // [GIVEN] A truck already named after its previous driver
        InsertDimValue(TruckDimTok, 'BT-301', 'Old Driver', false);
        Trucks.Add(Truck('BT-301', ActiveTok));
        FleetrockUnits.Add(FleetrockUnit('BT-301', 'VIN-BT-301'));
        FleetrockDrivers.Add(FleetrockDriver('New', 'Driver', 'VIN-BT-301'));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] It carries the new driver's name
        DimValue.Get(TruckDimTok, 'BT-301');
        Assert.AreEqual('New Driver', DimValue.Name, 'The truck should be renamed after its current Fleetrock driver.');
    end;

    [Test]
    procedure ImportTrucksKeepsNameWhenFleetrockHasNoDriver()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
        LastModified: DateTime;
    begin
        // [SCENARIO] A truck Fleetrock cannot name keeps the name it has, and is not rewritten.
        Initialize();

        // [GIVEN] A named truck, already linked, that is not a Fleetrock unit
        InsertDimValue(TruckDimTok, 'BT-401', 'Keep Me', false);
        DimValue.Get(TruckDimTok, 'BT-401');
        DimValue.Validate("BAASI Alvys ID", 'TR-BT-401');
        DimValue.Modify(true);
        LastModified := DimValue.SystemModifiedAt;
        Trucks.Add(Truck('BT-401', ActiveTok));
        FleetrockUnits.Add(FleetrockUnit('SOME-OTHER-UNIT', 'VIN-OTHER'));
        FleetrockDrivers.Add(FleetrockDriver('Not', 'This One', 'VIN-OTHER'));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] Its name and its record are untouched
        DimValue.Get(TruckDimTok, 'BT-401');
        Assert.AreEqual('Keep Me', DimValue.Name, 'A truck Fleetrock has no driver for should keep its name.');
        Assert.AreEqual(LastModified, DimValue.SystemModifiedAt, 'A truck with nothing to change should not be modified.');
    end;

    [Test]
    procedure ImportTrucksBlocksInactiveTruck()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] An inactive Alvys truck blocks its dimension value, and is not created if missing.
        Initialize();

        // [GIVEN] An inactive truck already in Business Central, and one that is not
        InsertDimValue(TruckDimTok, 'BT-501', '', false);
        Trucks.Add(Truck('BT-501', InactiveTok));
        Trucks.Add(Truck('BT-502', InactiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] The existing one is blocked and the other is not created
        DimValue.Get(TruckDimTok, 'BT-501');
        Assert.IsTrue(DimValue.Blocked, 'An inactive truck should block its dimension value.');
        Assert.IsFalse(DimValue.Get(TruckDimTok, 'BT-502'), 'An inactive truck should not be created.');
    end;

    [Test]
    procedure ImportTrucksDoesNotBlockTruckInShop()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck in the shop still takes invoices, so only Inactive blocks a truck.
        Initialize();

        // [GIVEN] Trucks in the shop and in repair
        Trucks.Add(Truck('BT-601', 'In Shop'));
        Trucks.Add(Truck('BT-602', 'Repair'));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] Both are created, unblocked
        Assert.IsTrue(DimValue.Get(TruckDimTok, 'BT-601'), 'A truck in the shop should be imported.');
        Assert.IsFalse(DimValue.Blocked, 'A truck in the shop should not be blocked.');
        Assert.IsTrue(DimValue.Get(TruckDimTok, 'BT-602'), 'A truck in repair should be imported.');
        Assert.IsFalse(DimValue.Blocked, 'A truck in repair should not be blocked.');
    end;

    [Test]
    procedure ImportTrucksDoesNotUnblockTruck()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck blocked in Business Central stays blocked though Alvys has it active.
        Initialize();

        // [GIVEN] A blocked truck that Alvys has active
        InsertDimValue(TruckDimTok, 'BT-701', '', true);
        Trucks.Add(Truck('BT-701', ActiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] It is still blocked
        DimValue.Get(TruckDimTok, 'BT-701');
        Assert.IsTrue(DimValue.Blocked, 'The import should never unblock a dimension value.');
    end;

    [Test]
    procedure ImportTrucksSkipsTruckNumberTooLongForCode()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck number longer than a dimension value code is left out rather than cut
        // short, since a deduction could never find the truck by the shortened number.
        Initialize();

        // [GIVEN] A 21 character truck number and a blank one
        Trucks.Add(Truck('BT-800-TOO-LONG-12345', ActiveTok));
        Trucks.Add(Truck('', ActiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] Nothing is created
        DimValue.SetRange("Dimension Code", TruckDimTok);
        Assert.RecordIsEmpty(DimValue);
    end;

    [Test]
    procedure ImportDriversCreatesValueCodedByName()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] Each Alvys driver becomes a driver dimension value coded by the driver's name in
        // upper case, and named as Alvys has it.
        Initialize();

        // [GIVEN] An active driver
        Drivers.Add(Driver('Robin Test', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The driver is there, under the upper case name
        Assert.IsTrue(DimValue.Get(DriverDimTok, 'ROBIN TEST'), 'The driver should be coded by name in upper case.');
        Assert.AreEqual('Robin Test', DimValue.Name, 'A new driver should be named as Alvys has it.');
        Assert.IsFalse(DimValue.Blocked, 'An active driver should not be blocked.');
    end;

    [Test]
    procedure ImportDriversKeepsExistingName()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] A driver already in Business Central keeps its Name, which carries other data.
        Initialize();

        // [GIVEN] A driver whose dimension value is named with a number
        InsertDimValue(DriverDimTok, 'ROBIN TEST', '7130', false);
        Drivers.Add(Driver('Robin Test', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The name is untouched
        DimValue.Get(DriverDimTok, 'ROBIN TEST');
        Assert.AreEqual('7130', DimValue.Name, 'An existing driver''s name should be kept.');
    end;

    [Test]
    procedure ImportDriversFillsBlankName()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] A driver whose dimension value has no name is given the Alvys name.
        Initialize();

        // [GIVEN] An unnamed driver dimension value
        InsertDimValue(DriverDimTok, 'ROBIN TEST', '', false);
        Drivers.Add(Driver('Robin Test', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] It is named
        DimValue.Get(DriverDimTok, 'ROBIN TEST');
        Assert.AreEqual('Robin Test', DimValue.Name, 'A blank name should be filled from Alvys.');
    end;

    [Test]
    procedure ImportDriversBlocksInactiveDriver()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] An inactive Alvys driver blocks its dimension value, and is not created if missing.
        Initialize();

        // [GIVEN] An inactive driver already in Business Central, and one that is not
        InsertDimValue(DriverDimTok, 'GONE DRIVER', '', false);
        Drivers.Add(Driver('Gone Driver', false));
        Drivers.Add(Driver('Never Here', false));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The existing one is blocked and the other is not created
        DimValue.Get(DriverDimTok, 'GONE DRIVER');
        Assert.IsTrue(DimValue.Blocked, 'An inactive driver should block its dimension value.');
        Assert.IsFalse(DimValue.Get(DriverDimTok, 'NEVER HERE'), 'An inactive driver should not be created.');
    end;

    [Test]
    procedure ImportDriversCutsLongNameToCode()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] A driver's name longer than a code is cut to fit; the full name is kept as Name.
        Initialize();

        // [GIVEN] A driver with a 27 character name
        Drivers.Add(Driver('Maximiliano Longname-Garcia', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The code is the first 20 characters, and the name is whole
        Assert.IsTrue(DimValue.Get(DriverDimTok, 'MAXIMILIANO LONGNAME'), 'A long name should be cut to the code length.');
        Assert.AreEqual('Maximiliano Longname-Garcia', DimValue.Name, 'The full name should be kept.');
    end;

    [Test]
    procedure DriverDimensionCannotBeTruckDimension()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
    begin
        // [SCENARIO] The driver dimension and Fleetrock's truck dimension must differ, or drivers
        // would be sent to Alvys as truck numbers.
        Initialize();
        FleetrockSetup.Get();
        FleetrockSetup."Truck Dimension Code" := TruckDimTok;
        FleetrockSetup.Modify();
        AlvysSetup.Get();

        // [WHEN] The driver dimension is set to the truck dimension
        asserterror AlvysSetup.Validate("Driver Code Dimension", TruckDimTok);

        // [THEN] It is refused
        Assert.ExpectedError('cannot be the same dimension');
    end;

    [Test]
    procedure TruckDimensionCannotBeDriverDimension()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
    begin
        // [SCENARIO] The same check holds when the truck dimension is the one changed, from the
        // Fleetrock setup.
        Initialize();
        AlvysSetup.Get();
        AlvysSetup."Driver Code Dimension" := DriverDimTok;
        AlvysSetup.Modify();
        FleetrockSetup.Get();

        // [WHEN] The truck dimension is set to the driver dimension
        asserterror FleetrockSetup.Validate("Truck Dimension Code", DriverDimTok);

        // [THEN] It is refused
        Assert.ExpectedError('cannot be the same dimension');
    end;

    [Test]
    procedure DriverAndTruckDimensionsCanBothBeBlank()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
    begin
        // [SCENARIO] Two blank dimensions are not the same dimension.
        Initialize();
        FleetrockSetup.Get();
        FleetrockSetup."Truck Dimension Code" := '';
        FleetrockSetup.Modify();
        AlvysSetup.Get();
        AlvysSetup."Driver Code Dimension" := '';
        AlvysSetup.Modify();

        // [WHEN] Each is validated blank
        AlvysSetup.Validate("Driver Code Dimension", '');
        FleetrockSetup.Validate("Truck Dimension Code", '');

        // [THEN] Neither is refused
        Assert.AreEqual('', AlvysSetup."Driver Code Dimension", 'A blank driver dimension should be accepted.');
        Assert.AreEqual('', FleetrockSetup."Truck Dimension Code", 'A blank truck dimension should be accepted.');
    end;

    [Test]
    procedure ImportNeedsADimension()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
    begin
        // [SCENARIO] With neither dimension set there is nothing to import into.
        Initialize();
        FleetrockSetup.Get();
        FleetrockSetup."Truck Dimension Code" := '';
        FleetrockSetup.Modify();
        AlvysSetup.Get();
        AlvysSetup."Driver Code Dimension" := '';
        AlvysSetup.Modify();

        // [WHEN] The import runs
        asserterror DimensionImport.ImportTrucksAndDrivers();

        // [THEN] It says why
        Assert.ExpectedError('nothing to import');
    end;

    [Test]
    procedure GetTrucksAndDriversReturnEveryRecord()
    var
        Trucks, Drivers : JsonArray;
        Item: JsonToken;
        ItemObj: JsonObject;
        ErrorText: Text;
        FoundTruck, FoundInactiveDriver : Boolean;
    begin
        // [SCENARIO] The Alvys list endpoints return every truck and driver, inactive ones included.
        Initialize();

        // [WHEN] Trucks and drivers are read from Alvys
        Assert.IsTrue(AlvysSalesMgt.GetTrucks(Trucks, ErrorText), 'GET trucks should succeed: ' + ErrorText);
        Assert.IsTrue(AlvysSalesMgt.GetDrivers(Drivers, ErrorText), 'GET drivers should succeed: ' + ErrorText);

        // [THEN] The known test truck and the known inactive driver are among them
        foreach Item in Trucks do begin
            ItemObj := Item.AsObject();
            if JsonMgt.GetJsonValueAsText(ItemObj, 'TruckNum') = LiveTruckTok then
                FoundTruck := true;
        end;
        foreach Item in Drivers do begin
            ItemObj := Item.AsObject();
            if JsonMgt.GetJsonValueAsText(ItemObj, 'Name') = LiveInactiveDriverTok then
                FoundInactiveDriver := true;
        end;
        Assert.IsTrue(FoundTruck, StrSubstNo('Truck %1 should be returned by GET trucks.', LiveTruckTok));
        Assert.IsTrue(FoundInactiveDriver, StrSubstNo('Inactive driver %1 should be returned by GET drivers.', LiveInactiveDriverTok));
    end;

    [Test]
    procedure JobQueueImportsTrucksAndDriversFromAlvys()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
        DimValue: Record "Dimension Value";
        Trucks, Drivers : JsonArray;
        ErrorText: Text;
        TruckID, DriverID, InactiveDriverID : Code[50];
    begin
        // [SCENARIO] The job queue codeunit reads Alvys and Fleetrock and fills the company's own
        // truck and driver dimensions, linking each value to its Alvys record. Truck TEST420 is a
        // Fleetrock unit whose VIN has only a deactivated Fleetrock driver on it; no Alvys truck in
        // the sandbox has an active one.
        Initialize();
        FleetrockSetup.Get();
        FleetrockSetup.TestField("Truck Dimension Code");
        AlvysSetup.Get();
        AlvysSetup.TestField("Driver Code Dimension");
        Assert.IsTrue(AlvysSalesMgt.GetTrucks(Trucks, ErrorText), ErrorText);
        Assert.IsTrue(AlvysSalesMgt.GetDrivers(Drivers, ErrorText), ErrorText);
        TruckID := FindLiveID(Trucks, 'TruckNum', LiveTruckTok);
        DriverID := FindLiveID(Drivers, 'Name', LiveDriverTok);
        InactiveDriverID := FindLiveID(Drivers, 'Name', LiveInactiveDriverTok);
        if DimValue.Get(FleetrockSetup."Truck Dimension Code", LiveTruckTok) then begin
            DimValue.Name := '';
            DimValue.Modify();
        end;

        // [WHEN] The job queue codeunit runs
        Codeunit.Run(Codeunit::"BAASI Alvys Driver/Truck Imp.");

        // [THEN] The test truck carries its Alvys ID and is not named after its deactivated driver
        DimValue.SetRange("BAASI Alvys ID", TruckID);
        DimValue.SetRange("Dimension Code", FleetrockSetup."Truck Dimension Code");
        Assert.IsTrue(DimValue.FindFirst(), StrSubstNo('Truck %1 should be linked to its Alvys ID.', LiveTruckTok));
        Assert.AreEqual(LiveTruckTok, DimValue.Code, 'The truck should be coded by its truck number.');
        Assert.AreEqual('', DimValue.Name, StrSubstNo('The truck should not be named after its deactivated Fleetrock driver %1.', LiveDeactivatedTruckDriverTok));
        // [THEN] The test truck's owner operator is linked, and the inactive driver is on no open value
        DimValue.SetRange("BAASI Alvys ID", DriverID);
        DimValue.SetRange("Dimension Code", AlvysSetup."Driver Code Dimension");
        Assert.IsFalse(DimValue.IsEmpty(), StrSubstNo('Driver %1 should be linked to its Alvys ID.', LiveDriverTok));
        DimValue.SetRange("BAASI Alvys ID", InactiveDriverID);
        DimValue.SetRange(Blocked, false);
        Assert.IsTrue(DimValue.IsEmpty(), 'An inactive driver should not be on an unblocked dimension value.');
    end;

    [Test]
    procedure ImportLinksNewValueToAlvysID()
    var
        DimValue: Record "Dimension Value";
        Trucks, Drivers, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A value the import creates carries the Id of the Alvys record it came from.
        Initialize();
        Trucks.Add(TruckWithID('TR900', 'BT-900', ActiveTok));
        Drivers.Add(DriverWithID('DR900', 'Robin Test', true));

        // [WHEN] Trucks and drivers are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] Both values carry their Alvys ID
        DimValue.Get(TruckDimTok, 'BT-900');
        Assert.AreEqual('TR900', DimValue."BAASI Alvys ID", 'A new truck should carry its Alvys ID.');
        DimValue.Get(DriverDimTok, 'ROBIN TEST');
        Assert.AreEqual('DR900', DimValue."BAASI Alvys ID", 'A new driver should carry its Alvys ID.');
    end;

    [Test]
    procedure ImportLinksExistingValueByCode()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] A value already coded for the driver, and linked to nothing, is linked to the
        // driver rather than a second value being made.
        Initialize();
        InsertDimValue(DriverDimTok, 'ROBIN TEST', '7130', false);
        Drivers.Add(DriverWithID('DR901', 'Robin Test', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The existing value is linked, and is the only one
        DimValue.Get(DriverDimTok, 'ROBIN TEST');
        Assert.AreEqual('DR901', DimValue."BAASI Alvys ID", 'The existing value should be linked to the driver.');
        Assert.AreEqual(1, CountValues(DriverDimTok), 'No second value should be made for the driver.');
    end;

    [Test]
    procedure RenamedDriverKeepsItsValue()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] A driver renamed in Alvys is found by Alvys ID, not given a value under the new name.
        Initialize();
        InsertLinkedDimValue(DriverDimTok, 'ROBIN MAIDEN', 'DR902');
        Drivers.Add(DriverWithID('DR902', 'Robin Married', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The driver keeps the value it had
        Assert.IsTrue(DimValue.Get(DriverDimTok, 'ROBIN MAIDEN'), 'The renamed driver should keep its value.');
        Assert.IsFalse(DimValue.Get(DriverDimTok, 'ROBIN MARRIED'), 'No value should be made under the new name.');
    end;

    [Test]
    procedure RenumberedTruckKeepsItsValue()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck renumbered in Alvys is found by Alvys ID, not given a value under the new
        // number, and is still blocked when it goes inactive.
        Initialize();
        InsertLinkedDimValue(TruckDimTok, 'BT-903', 'TR903');
        Trucks.Add(TruckWithID('TR903', 'BT-903-NEW', InactiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] The truck's value is the one it had, now blocked
        DimValue.Get(TruckDimTok, 'BT-903');
        Assert.IsTrue(DimValue.Blocked, 'The truck''s own value should be blocked.');
        Assert.IsFalse(DimValue.Get(TruckDimTok, 'BT-903-NEW'), 'No value should be made under the new number.');
    end;

    [Test]
    procedure LongTruckNumberIsStillMatchedByAlvysID()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck number too long for a code cannot be matched by number, but a truck
        // already linked is still found by its Alvys ID.
        Initialize();
        InsertLinkedDimValue(TruckDimTok, 'BT-904', 'TR904');
        Trucks.Add(TruckWithID('TR904', 'BT-904-TOO-LONG-12345', InactiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] The linked value is updated
        DimValue.Get(TruckDimTok, 'BT-904');
        Assert.IsTrue(DimValue.Blocked, 'The linked truck should be found by Alvys ID and blocked.');
    end;

    [Test]
    procedure DriverWhoseCodeIsTakenIsSkipped()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] Two drivers whose names agree in their first 20 characters cannot share a value:
        // the one already linked keeps it and the other is left out, without failing the run.
        Initialize();
        InsertLinkedDimValue(DriverDimTok, 'ROBIN TEST', 'DR905');
        Drivers.Add(DriverWithID('DR906', 'Robin Test', true));
        Drivers.Add(DriverWithID('DR907', 'Someone Else', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The value keeps its driver, and the next driver is still imported
        DimValue.Get(DriverDimTok, 'ROBIN TEST');
        Assert.AreEqual('DR905', DimValue."BAASI Alvys ID", 'A linked value should not be taken by another driver.');
        Assert.IsTrue(DimValue.Get(DriverDimTok, 'SOMEONE ELSE'), 'The run should carry on past the skipped driver.');
    end;

    [Test]
    procedure AlvysIDOnAnotherDimensionDoesNotStopNewValue()
    var
        DimValue: Record "Dimension Value";
        Drivers: JsonArray;
    begin
        // [SCENARIO] A truck and a driver are separate Alvys records that can be given the same Id,
        // so an Alvys ID on a truck value does not keep a driver value from being made with it.
        Initialize();
        InsertLinkedDimValue(TruckDimTok, 'BT-908', 'DUP908');
        Drivers.Add(DriverWithID('DUP908', 'Robin Test', true));

        // [WHEN] The drivers are imported
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] The driver value is made with the ID, and the truck value keeps it too
        Assert.IsTrue(DimValue.Get(DriverDimTok, 'ROBIN TEST'), 'An Alvys ID in another dimension should not stop the driver being imported.');
        Assert.AreEqual('DUP908', DimValue."BAASI Alvys ID", 'The driver value should carry its Alvys ID.');
        DimValue.Get(TruckDimTok, 'BT-908');
        Assert.AreEqual('DUP908', DimValue."BAASI Alvys ID", 'The truck value should keep its Alvys ID.');
    end;

    [Test]
    procedure AlvysIDOnAnotherDimensionDoesNotStopLinkByCode()
    var
        DimValue: Record "Dimension Value";
        Trucks, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] The same holds for an existing value linked by its code.
        Initialize();
        InsertLinkedDimValue(DriverDimTok, 'ROBIN TEST', 'DUP912');
        InsertDimValue(TruckDimTok, 'BT-912', '', false);
        Trucks.Add(TruckWithID('DUP912', 'BT-912', ActiveTok));

        // [WHEN] The trucks are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);

        // [THEN] The truck value is linked
        DimValue.Get(TruckDimTok, 'BT-912');
        Assert.AreEqual('DUP912', DimValue."BAASI Alvys ID", 'The existing truck value should be linked though a driver has the same ID.');
    end;

    [Test]
    procedure RecordWithoutAlvysIDIsSkipped()
    var
        Trucks, Drivers, FleetrockUnits, FleetrockDrivers : JsonArray;
    begin
        // [SCENARIO] A truck or driver without an Alvys ID cannot be linked, so it is not imported.
        Initialize();
        Trucks.Add(TruckWithID('', 'BT-909', ActiveTok));
        Drivers.Add(DriverWithID('', 'Robin Test', true));

        // [WHEN] Trucks and drivers are imported
        DimensionImport.ImportTrucks(TruckDimTok, Trucks, FleetrockUnits, FleetrockDrivers);
        DimensionImport.ImportDrivers(DriverDimTok, Drivers);

        // [THEN] Nothing is created
        Assert.AreEqual(0, CountValues(TruckDimTok), 'A truck without an Alvys ID should not be imported.');
        Assert.AreEqual(0, CountValues(DriverDimTok), 'A driver without an Alvys ID should not be imported.');
    end;

    [Test]
    procedure AlvysIDCannotBeOnTwoValues()
    var
        DimValue: Record "Dimension Value";
    begin
        // [SCENARIO] The Alvys ID key is not unique, since unlinked values share the blank ID, so
        // the field itself refuses an ID another value already has.
        Initialize();
        InsertLinkedDimValue(DriverDimTok, 'FIRST', 'DR910');
        InsertDimValue(DriverDimTok, 'SECOND', '', false);
        DimValue.Get(DriverDimTok, 'SECOND');

        // [WHEN] The same ID is put on a second value
        asserterror DimValue.Validate("BAASI Alvys ID", 'DR910');

        // [THEN] It is refused
        Assert.ExpectedError('is already on dimension value');
    end;

    [Test]
    procedure AlvysIDCanBeOnValuesInDifferentDimensions()
    var
        DimValue: Record "Dimension Value";
    begin
        // [SCENARIO] Only values in the same dimension are checked for the ID.
        Initialize();
        InsertLinkedDimValue(TruckDimTok, 'FIRST', 'DUP911');
        InsertDimValue(DriverDimTok, 'SECOND', '', false);
        DimValue.Get(DriverDimTok, 'SECOND');

        // [WHEN] The same ID is put on a value in the other dimension
        DimValue.Validate("BAASI Alvys ID", 'DUP911');
        DimValue.Modify(true);

        // [THEN] Both carry it
        DimValue.SetRange("BAASI Alvys ID", 'DUP911');
        Assert.AreEqual(2, DimValue.Count(), 'The same Alvys ID should be allowed in two dimensions.');
    end;

    local procedure Initialize()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
    begin
        AlvysSetup.Get();
        AlvysSetup.TestField("Integration URL");
        AlvysSetup.TestField("Client ID");
        AlvysSetup.TestField("Client Secret");
        FleetrockSetup.Get();
        // Test isolation rolls back per codeunit, not per test, so the setup dimensions a test
        // blanks would otherwise still be blank for the live import test after it.
        if not IsInitialized then begin
            CompanyTruckDimension := FleetrockSetup."Truck Dimension Code";
            CompanyDriverDimension := AlvysSetup."Driver Code Dimension";
            IsInitialized := true;
        end;
        FleetrockSetup."Truck Dimension Code" := CompanyTruckDimension;
        FleetrockSetup.Modify();
        AlvysSetup."Driver Code Dimension" := CompanyDriverDimension;
        AlvysSetup.Modify();
        CreateDimension(TruckDimTok);
        CreateDimension(DriverDimTok);
        Clear(DimensionImport);
        Clear(AlvysSalesMgt);
    end;

    local procedure CreateDimension(DimensionCode: Code[20])
    var
        Dimension: Record Dimension;
        DimValue: Record "Dimension Value";
    begin
        if not Dimension.Get(DimensionCode) then begin
            Dimension.Init();
            Dimension.Validate(Code, DimensionCode);
            Dimension.Insert(true);
        end;
        DimValue.SetRange("Dimension Code", DimensionCode);
        DimValue.DeleteAll();
    end;

    local procedure InsertDimValue(DimensionCode: Code[20]; ValueCode: Code[20]; ValueName: Text[50]; IsBlocked: Boolean)
    var
        DimValue: Record "Dimension Value";
    begin
        DimValue.Init();
        DimValue.Validate("Dimension Code", DimensionCode);
        DimValue.Validate(Code, ValueCode);
        DimValue.Validate(Name, ValueName);
        DimValue.Validate(Blocked, IsBlocked);
        DimValue.Insert(true);
    end;

    local procedure Truck(TruckNum: Text; Status: Text): JsonObject
    begin
        exit(TruckWithID('TR-' + TruckNum, TruckNum, Status));
    end;

    local procedure TruckWithID(AlvysID: Text; TruckNum: Text; Status: Text): JsonObject
    var
        TruckObj: JsonObject;
    begin
        TruckObj.Add('Id', AlvysID);
        TruckObj.Add('TruckNum', TruckNum);
        TruckObj.Add('Status', Status);
        exit(TruckObj);
    end;

    local procedure Driver(DriverName: Text; IsActive: Boolean): JsonObject
    begin
        exit(DriverWithID('DR-' + DriverName, DriverName, IsActive));
    end;

    local procedure DriverWithID(AlvysID: Text; DriverName: Text; IsActive: Boolean): JsonObject
    var
        DriverObj: JsonObject;
    begin
        DriverObj.Add('Id', AlvysID);
        DriverObj.Add('Name', DriverName);
        DriverObj.Add('IsActive', IsActive);
        exit(DriverObj);
    end;

    local procedure InsertLinkedDimValue(DimensionCode: Code[20]; ValueCode: Code[20]; AlvysID: Code[50])
    var
        DimValue: Record "Dimension Value";
    begin
        InsertDimValue(DimensionCode, ValueCode, '', false);
        DimValue.Get(DimensionCode, ValueCode);
        DimValue.Validate("BAASI Alvys ID", AlvysID);
        DimValue.Modify(true);
    end;

    local procedure CountValues(DimensionCode: Code[20]): Integer
    var
        DimValue: Record "Dimension Value";
    begin
        DimValue.SetRange("Dimension Code", DimensionCode);
        exit(DimValue.Count());
    end;

    local procedure FindLiveID(var Items: JsonArray; KeyName: Text; KeyValue: Text): Code[50]
    var
        Item: JsonToken;
        ItemObj: JsonObject;
    begin
        foreach Item in Items do begin
            ItemObj := Item.AsObject();
            if JsonMgt.GetJsonValueAsText(ItemObj, KeyName) = KeyValue then
                exit(CopyStr(JsonMgt.GetJsonValueAsText(ItemObj, 'Id'), 1, 50));
        end;
        Error('Alvys returned no record with %1 %2.', KeyName, KeyValue);
    end;

    local procedure FleetrockUnit(UnitNumber: Text; VIN: Text): JsonObject
    var
        UnitObj: JsonObject;
    begin
        UnitObj.Add('unit_number', UnitNumber);
        UnitObj.Add('vin', VIN);
        exit(UnitObj);
    end;

    local procedure FleetrockDriver(FirstName: Text; LastName: Text; VIN: Text): JsonObject
    begin
        exit(FleetrockDriverWithStatus(FirstName, LastName, VIN, ActiveTok));
    end;

    local procedure FleetrockDriverWithStatus(FirstName: Text; LastName: Text; VIN: Text; Status: Text): JsonObject
    var
        DriverObj: JsonObject;
    begin
        DriverObj.Add('first_name', FirstName);
        DriverObj.Add('last_name', LastName);
        DriverObj.Add('vin', VIN);
        DriverObj.Add('status', Status);
        exit(DriverObj);
    end;

    var
        Assert: Codeunit "Library Assert";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        DimensionImport: Codeunit "BAASI Alvys Driver/Truck Imp.";
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        CompanyTruckDimension, CompanyDriverDimension : Code[20];
        IsInitialized: Boolean;
        TruckDimTok: Label 'BAASIT-TRUCK', Locked = true;
        DriverDimTok: Label 'BAASIT-DRIVER', Locked = true;
        ActiveTok: Label 'Active', Locked = true;
        InactiveTok: Label 'Inactive', Locked = true;
        DeactivatedTok: Label 'Deactivated', Locked = true;
        LiveTruckTok: Label 'TEST420', Locked = true;
        LiveDeactivatedTruckDriverTok: Label 'Aother Name', Locked = true;
        LiveDriverTok: Label 'Adam Test', Locked = true;
        LiveInactiveDriverTok: Label 'Jordan L Strong', Locked = true;
}
