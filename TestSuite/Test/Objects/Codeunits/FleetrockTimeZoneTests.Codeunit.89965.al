codeunit 89965 "BAASIT Fleetrock TZ Tests"
{
    // [FEATURE] [Fleetrock Integration] [Time Zone]
    //
    // Fleetrock's UpdateRO reads dates as wall-clock time in the calling account's profile time zone,
    // while GetRO returns them in UTC. The round-trip tests rely on both Fleetrock test accounts
    // having their profile Time Zone set to Eastern Standard Time.

    Subtype = Test;
    TestPermissions = Disabled;
    Permissions = tabledata "Sales Invoice Header" = RIMD;

    [Test]
    procedure CustomerTimeZoneConvertsCustomerUpdateDates()
    var
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
    begin
        // [GIVEN] Customer Time Zone is Eastern and Vendor Time Zone is Pacific
        Initialize();
        SetTimeZones(EasternTok, PacificTok);

        // [THEN] Customer account dates are Eastern, in both daylight saving and standard time
        Assert.AreEqual('2026-07-01T12:00:00', FleetrockMgt.FormatDateTimeForUpdate(UtcDateTime('2026-07-01T16:00:00'), false), 'A summer UTC datetime should be sent as Eastern Daylight Time.');
        Assert.AreEqual('2026-01-15T12:00:00', FleetrockMgt.FormatDateTimeForUpdate(UtcDateTime('2026-01-15T17:00:00'), false), 'A winter UTC datetime should be sent as Eastern Standard Time.');
        RestoreTimeZones();
    end;

    [Test]
    procedure VendorTimeZoneConvertsVendorUpdateDates()
    var
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
    begin
        // [GIVEN] Customer Time Zone is Eastern and Vendor Time Zone is Pacific
        Initialize();
        SetTimeZones(EasternTok, PacificTok);

        // [THEN] Vendor account dates use the vendor's time zone, not the customer's
        Assert.AreEqual('2026-07-01T09:00:00', FleetrockMgt.FormatDateTimeForUpdate(UtcDateTime('2026-07-01T16:00:00'), true), 'A vendor account datetime should be sent as Pacific Daylight Time.');
        Assert.AreEqual('2026-01-15T09:00:00', FleetrockMgt.FormatDateTimeForUpdate(UtcDateTime('2026-01-15T17:00:00'), true), 'A vendor account datetime should be sent as Pacific Standard Time.');
        RestoreTimeZones();
    end;

    [Test]
    procedure BlankTimeZonesSendUtc()
    var
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
    begin
        // [GIVEN] Neither time zone is set
        Initialize();
        SetTimeZones('', '');

        // [THEN] Both accounts send the datetime unchanged, as UTC
        Assert.AreEqual('2026-07-01T16:00:00', FleetrockMgt.FormatDateTimeForUpdate(UtcDateTime('2026-07-01T16:00:00'), false), 'With no Customer Time Zone the datetime should be sent as UTC.');
        Assert.AreEqual('2026-07-01T16:00:00', FleetrockMgt.FormatDateTimeForUpdate(UtcDateTime('2026-07-01T16:00:00'), true), 'With no Vendor Time Zone the datetime should be sent as UTC.');
        RestoreTimeZones();
    end;

    [Test]
    procedure PaidDateIsStoredInFleetrockAsThePaymentTime()
    var
        ImportEntry: Record "FRI Import/Export Entry";
        SalesInvHeader: Record "Sales Invoice Header";
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
        ROObj: JsonObject;
        ROId: Text;
        PaidDateTime: DateTime;
    begin
        // [SCENARIO] Marking a repair order paid from BC stores the actual payment time in Fleetrock,
        // rather than one shifted by the customer account's UTC offset.
        Initialize();
        SetTimeZones(EasternTok, EasternTok);

        // [GIVEN] An invoiced repair order in Fleetrock and a posted invoice for it
        ROId := ROHelper.CreateRepairOrder(UnitVinTok);
        ROHelper.SetRepairOrderToInvoiced(ROId);
        SalesInvHeader.Init();
        SalesInvHeader."No." := CopyStr('TZ-' + ROId, 1, MaxStrLen(SalesInvHeader."No."));
        SalesInvHeader."FRI Fleetrock Repair Order No." := CopyStr(ROId, 1, MaxStrLen(SalesInvHeader."FRI Fleetrock Repair Order No."));
        SalesInvHeader.Insert();

        // [WHEN] The payment is sent to Fleetrock
        PaidDateTime := UtcDateTime(CopyStr(Format(CurrentDateTime(), 0, 9), 1, 19));
        FleetrockMgt.UpdatePaidRepairOrder(ROId, PaidDateTime, SalesInvHeader);
        if ImportEntry.FindLast() then;
        Assert.IsTrue(SalesInvHeader."FRI Sent Payment", StrSubstNo('The payment should be sent to Fleetrock: %1', ImportEntry."Error Message"));

        // [THEN] Fleetrock returns the paid date as the same UTC time
        ROObj := ROHelper.GetRepairOrder(ROId);
        Assert.AreEqual('Paid', JsonMgt.GetJsonValueAsText(ROObj, 'status'), 'The repair order should be Paid in Fleetrock.');
        Assert.AreEqual(FormatAsFleetrockUtc(PaidDateTime), JsonMgt.GetJsonValueAsText(ROObj, 'date_invoice_paid'), 'The Fleetrock paid date should be the payment time in UTC.');

        RestoreTimeZones();
        if not TestMode.GetKeepData() then
            ROHelper.DeleteRepairOrder(ROId);
    end;

    [Test]
    procedure VendorUpdateDateIsStoredInFleetrockAsTheSentTime()
    var
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
        JsonBody, ROJson, ROObj : JsonObject;
        ROArray: JsonArray;
        ROId: Text;
        ExpectedFinish: DateTime;
    begin
        // [SCENARIO] A date the vendor account sends is stored in Fleetrock as the intended UTC time.
        Initialize();
        SetTimeZones(EasternTok, EasternTok);

        // [GIVEN] A repair order in Fleetrock
        ROId := ROHelper.CreateRepairOrder(UnitVinTok);

        // [WHEN] The vendor account sets the expected finish to tomorrow at 15:30 UTC
        ExpectedFinish := UtcDateTime(Format(CalcDate('<+1D>', Today()), 0, 9) + 'T15:30:00');
        ROJson.Add('ro_id', ROId);
        ROJson.Add('date_expected_finish', FleetrockMgt.FormatDateTimeForUpdate(ExpectedFinish, true));
        ROArray.Add(ROJson);
        JsonBody.Add('username', FleetrockSetup."Vendor Username");
        JsonBody.Add('repair_orders', ROArray);
        ROHelper.PostToFleetrock('UpdateRO', JsonBody, true);

        // [THEN] Fleetrock returns the expected finish as the same UTC time
        ROObj := ROHelper.GetRepairOrder(ROId);
        Assert.AreEqual(FormatAsFleetrockUtc(ExpectedFinish), JsonMgt.GetJsonValueAsText(ROObj, 'date_expected_finish'), 'The Fleetrock expected finish should be the sent time in UTC.');

        RestoreTimeZones();
        if not TestMode.GetKeepData() then
            ROHelper.DeleteRepairOrder(ROId);
    end;

    local procedure Initialize()
    begin
        FleetrockSetup.Get();
        FleetrockSetup.TestField("Integration URL");
        FleetrockSetup.TestField(Username);
        FleetrockSetup.TestField("API Key");
        FleetrockSetup.TestField("Vendor Username");
        FleetrockSetup.TestField("Vendor API Key");
        FleetrockSetup.TestField("Use API Token", false);
        OriginalCustomerTimeZone := FleetrockSetup."Customer Time Zone";
        OriginalVendorTimeZone := FleetrockSetup."Vendor Time Zone";
    end;

    local procedure SetTimeZones(CustomerTimeZone: Text; VendorTimeZone: Text)
    begin
        FleetrockSetup.Get();
        FleetrockSetup.Validate("Customer Time Zone", CustomerTimeZone);
        FleetrockSetup.Validate("Vendor Time Zone", VendorTimeZone);
        FleetrockSetup.Modify();
    end;

    // A keep-data run has no rollback, so the company's own settings are put back explicitly.
    local procedure RestoreTimeZones()
    begin
        SetTimeZones(OriginalCustomerTimeZone, OriginalVendorTimeZone);
    end;

    local procedure UtcDateTime(IsoText: Text) Result: DateTime
    begin
        Assert.IsTrue(Evaluate(Result, IsoText + 'Z', 9), StrSubstNo('%1 should be a valid ISO datetime.', IsoText));
    end;

    // Fleetrock returns dates as M/D/YYYY h:mm:ss AM in UTC. Format 9 is always UTC, so the parts
    // are taken from it rather than from the session's time zone.
    local procedure FormatAsFleetrockUtc(Value: DateTime): Text
    var
        Iso: Text;
        Year, Month, Day, Hour, Minute, Second : Integer;
        AmPm: Text;
    begin
        Iso := Format(Value, 0, 9);
        Evaluate(Year, CopyStr(Iso, 1, 4));
        Evaluate(Month, CopyStr(Iso, 6, 2));
        Evaluate(Day, CopyStr(Iso, 9, 2));
        Evaluate(Hour, CopyStr(Iso, 12, 2));
        Evaluate(Minute, CopyStr(Iso, 15, 2));
        Evaluate(Second, CopyStr(Iso, 18, 2));
        AmPm := 'AM';
        if Hour >= 12 then
            AmPm := 'PM';
        Hour := Hour mod 12;
        if Hour = 0 then
            Hour := 12;
        exit(StrSubstNo('%1/%2/%3 %4:%5:%6 %7', Month, Day, Year, Hour, PadTwo(Minute), PadTwo(Second), AmPm));
    end;

    local procedure PadTwo(Value: Integer): Text
    begin
        exit(PadStr('', 2 - StrLen(Format(Value)), '0') + Format(Value));
    end;

    var
        FleetrockSetup: Record "FRI Fleetrock Setup";
        Assert: Codeunit "Library Assert";
        JsonMgt: Codeunit "FRI Json Mgt.";
        ROHelper: Codeunit "BAASIT Fleetrock RO Helper";
        TestMode: Codeunit "BAASIT Test Mode";
        OriginalCustomerTimeZone, OriginalVendorTimeZone : Text[180];
        EasternTok: Label 'Eastern Standard Time', Locked = true;
        PacificTok: Label 'Pacific Standard Time', Locked = true;
        UnitVinTok: Label '1234567890', Locked = true;
}
