codeunit 89968 "BAASIT Fleetrock Driver Tests"
{
    // [FEATURE] [Fleetrock Integration] [Drivers]
    //
    // FindDriver's ActiveOnly check, on driver arrays shaped like Fleetrock's GetDrivers: dates are
    // M/D/YYYY text, a blank end_date means the assignment is open, and a VIN keeps the rows of
    // its earlier drivers with status Deactivated.

    Subtype = Test;
    TestPermissions = Disabled;

    [Test]
    procedure DriverDatesAreReadAsFleetrockSendsThem()
    var
        DriverObj: JsonObject;
    begin
        // [SCENARIO] The dates the other tests build are read back as the same dates, so a failure
        // below is the ActiveOnly check and not the date parsing.
        Initialize();
        DriverObj := Driver('Robin', 'Test', VinTok, ActiveTok, Today() - 30, Today() + 30);

        Assert.AreEqual(Today() - 30, JsonMgt.GetJsonValueAsDate(DriverObj, 'start_date'), 'start_date should be read as sent.');
        Assert.AreEqual(Today() + 30, JsonMgt.GetJsonValueAsDate(DriverObj, 'end_date'), 'end_date should be read as sent.');
    end;

    [Test]
    procedure ActiveDriverWithNoDatesIsFound()
    begin
        // [SCENARIO] An active driver with no start or end date is on the truck now.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, ActiveTok, 0D, 0D));

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'An active driver with no dates should be found.');
    end;

    [Test]
    procedure ActiveDriverThatStartedInThePastIsFound()
    begin
        // [SCENARIO] The shape every active driver in the Fleetrock sandbox has: started a while
        // ago, no end date.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, ActiveTok, Today() - 30, 0D));

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'An active driver who started in the past should be found.');
    end;

    [Test]
    procedure ActiveDriverStartingTodayIsFound()
    begin
        // [SCENARIO] A driver whose assignment starts today is on the truck today.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, ActiveTok, Today(), 0D));

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'An active driver starting today should be found.');
    end;

    [Test]
    procedure ActiveDriverEndingInTheFutureIsFound()
    begin
        // [SCENARIO] A driver whose assignment has not ended yet is still on the truck.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, ActiveTok, Today() - 30, Today() + 30));

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'An active driver whose end date is still ahead should be found.');
    end;

    [Test]
    procedure ActiveDriverStartingInTheFutureIsNotFound()
    begin
        // [SCENARIO] A driver who has not started yet is not on the truck.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, ActiveTok, Today() + 30, 0D));

        Assert.IsFalse(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'A driver starting in the future should not be found.');
    end;

    [Test]
    procedure ActiveDriverWhoseEndDateHasPassedIsNotFound()
    begin
        // [SCENARIO] A driver whose assignment has ended is no longer on the truck.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, ActiveTok, Today() - 60, Today() - 30));

        Assert.IsFalse(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'A driver whose end date has passed should not be found.');
    end;

    [Test]
    procedure DeactivatedDriverIsNotFound()
    begin
        // [SCENARIO] A deactivated driver is not active, whatever the dates say.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', VinTok, DeactivatedTok, Today() - 30, 0D));

        Assert.IsFalse(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'A deactivated driver should not be found.');
    end;

    [Test]
    procedure DriverOnAnotherVinIsNotFound()
    begin
        // [SCENARIO] Only the driver on the asked-for VIN counts.
        Initialize();
        Drivers.Add(Driver('Robin', 'Test', OtherVinTok, ActiveTok, 0D, 0D));

        Assert.IsFalse(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'A driver on another VIN should not be found.');
    end;

    [Test]
    procedure ActiveDriverIsFoundAfterTheDeactivatedOneBeforeIt()
    begin
        // [SCENARIO] As on VIN 123123 in the sandbox: the truck's previous driver, deactivated, comes
        // first, and the current one after it.
        Initialize();
        Drivers.Add(Driver('Old', 'Driver', VinTok, DeactivatedTok, Today() - 60, Today() - 59));
        Drivers.Add(Driver('Current', 'Driver', VinTok, ActiveTok, Today() - 30, 0D));

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, VinTok, true, FoundDriver), 'The active driver should be found past the deactivated one.');
        Assert.AreEqual('Current', JsonMgt.GetJsonValueAsText(FoundDriver, 'first_name'), 'The active driver should be the one returned.');
    end;

    [Test]
    procedure WithoutActiveOnlyTheFirstDriverOnTheVinIsFound()
    begin
        // [SCENARIO] With ActiveOnly off, status and dates are ignored.
        Initialize();
        Drivers.Add(Driver('Old', 'Driver', VinTok, DeactivatedTok, Today() - 60, Today() - 59));

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, VinTok, false, FoundDriver), 'Any driver on the VIN should be found without ActiveOnly.');
        Assert.AreEqual('Old', JsonMgt.GetJsonValueAsText(FoundDriver, 'first_name'), 'The first driver on the VIN should be returned.');
    end;

    [Test]
    procedure LiveActiveDriverIsFound()
    begin
        // [SCENARIO] Against the Fleetrock sandbox: VIN 8888 has two active drivers, both started
        // 4/29/2026 with no end date.
        Initialize();
        Assert.IsTrue(FleetrockMgt.TryToGetDrivers(Drivers), 'GetDrivers should succeed: ' + GetLastErrorText());

        Assert.IsTrue(FleetrockMgt.FindDriver(Drivers, LiveVinTok, true, FoundDriver), StrSubstNo('An active driver should be found on live VIN %1.', LiveVinTok));
    end;

    local procedure Initialize()
    begin
        Clear(Drivers);
        Clear(FoundDriver);
    end;

    local procedure Driver(FirstName: Text; LastName: Text; VIN: Text; Status: Text; StartDate: Date; EndDate: Date): JsonObject
    var
        DriverObj: JsonObject;
    begin
        DriverObj.Add('first_name', FirstName);
        DriverObj.Add('last_name', LastName);
        DriverObj.Add('vin', VIN);
        DriverObj.Add('status', Status);
        DriverObj.Add('start_date', FleetrockDate(StartDate));
        DriverObj.Add('end_date', FleetrockDate(EndDate));
        exit(DriverObj);
    end;

    local procedure FleetrockDate(D: Date): Text
    begin
        if D = 0D then
            exit('');
        exit(Format(D, 0, '<Month>/<Day>/<Year4>'));
    end;

    var
        Assert: Codeunit "Library Assert";
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
        JsonMgt: Codeunit "FRI Json Mgt.";
        Drivers: JsonArray;
        FoundDriver: JsonObject;
        VinTok: Label 'BAASIT-VIN-1', Locked = true;
        OtherVinTok: Label 'BAASIT-VIN-2', Locked = true;
        LiveVinTok: Label '8888', Locked = true;
        ActiveTok: Label 'Active', Locked = true;
        DeactivatedTok: Label 'Deactivated', Locked = true;
}
