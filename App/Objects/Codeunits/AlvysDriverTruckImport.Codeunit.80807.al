codeunit 80807 "BAASI Alvys Driver/Truck Imp."
{
    // Neither an Alvys truck nor an Alvys driver names the other, so each is imported into its own
    // dimension on its own. A truck's dimension value is named after the driver Fleetrock has on
    // the truck's VIN, the same way the Fleetrock repair order import names the ones it creates.

    Permissions = tabledata "BAASI Alvys Sales Setup" = R,
        tabledata "FRI Fleetrock Setup" = R,
        tabledata "Dimension Value" = RIM;

    trigger OnRun()
    begin
        // How the job queue reaches the import. A failed Alvys call is committed to the entry log
        // before the error, since a scheduled run has nobody watching it fail; a run from the setup
        // page leaves this false and shows the error instead.
        ScheduledRun := true;
        ImportTrucksAndDrivers();
    end;

    procedure ImportTrucksAndDrivers()
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        FleetrockSetup: Record "FRI Fleetrock Setup";
        Items, FleetrockUnits, FleetrockDrivers : JsonArray;
        ErrorText: Text;
    begin
        AlvysSetup.Get();
        if not FleetrockSetup.Get() then
            Clear(FleetrockSetup);
        if (FleetrockSetup."Truck Dimension Code" = '') and (AlvysSetup."Driver Code Dimension" = '') then
            Error(NoDimensionsErr, FleetrockSetup.FieldCaption("Truck Dimension Code"), FleetrockSetup.TableCaption(), AlvysSetup.FieldCaption("Driver Code Dimension"), AlvysSetup.TableCaption());

        if FleetrockSetup."Truck Dimension Code" <> '' then begin
            if not AlvysSalesMgt.GetTrucks(Items, ErrorText) then
                RaiseListError(ErrorText);
            // A company without Fleetrock still gets its trucks, only unnamed.
            if not FleetrockMgt.TryToGetUnits(FleetrockUnits) then
                Clear(FleetrockUnits);
            ImportTrucks(FleetrockSetup."Truck Dimension Code", Items, FleetrockUnits, FleetrockDrivers);
        end;

        if AlvysSetup."Driver Code Dimension" <> '' then begin
            if not AlvysSalesMgt.GetDrivers(Items, ErrorText) then
                RaiseListError(ErrorText);
            ImportDrivers(AlvysSetup."Driver Code Dimension", Items);
        end;
    end;

    /// <summary>
    /// One dimension value per truck, coded by truck number and named after the truck's Fleetrock
    /// driver. FleetrockDrivers may be passed empty; it is read from Fleetrock the first time a
    /// truck is found among FleetrockUnits.
    /// </summary>
    internal procedure ImportTrucks(DimensionCode: Code[20]; var TrucksArray: JsonArray; var FleetrockUnits: JsonArray; var FleetrockDrivers: JsonArray)
    var
        DimValue, OldDimValue : Record "Dimension Value";
        TruckObj: JsonObject;
        T: JsonToken;
        TruckNum: Text;
        AlvysID: Code[50];
        TruckCode: Code[20];
        Inactive, IsNew : Boolean;
    begin
        foreach T in TrucksArray do begin
            TruckObj := T.AsObject();
            AlvysID := AlvysIDOf(TruckObj);
            TruckNum := JsonMgt.GetJsonValueAsText(TruckObj, 'TruckNum').Trim();
            // A deduction looks its truck up in Alvys by this code, so a truck number cut short to
            // fit would never be found; such a truck is never matched or created by number.
            if StrLen(TruckNum) <= MaxStrLen(TruckCode) then
                TruckCode := CopyStr(TruckNum.ToUpper(), 1, MaxStrLen(TruckCode))
            else
                TruckCode := '';
            // Repair, In Shop and the other working statuses still take invoices.
            Inactive := JsonMgt.GetJsonValueAsText(TruckObj, 'Status').ToUpper() = InactiveTruckStatusTok;
            if FindOrInitDimValue(DimValue, OldDimValue, DimensionCode, AlvysID, TruckCode, Inactive, IsNew) then begin
                FleetrockMgt.SetDimensionValueDriverName(DimValue, DimValue.Code, FleetrockUnits, FleetrockDrivers);
                SaveDimValue(DimValue, OldDimValue, Inactive, IsNew);
            end;
        end;
    end;

    /// <summary>
    /// One dimension value per driver, coded by the driver's name, the way the existing driver
    /// dimension values are. An existing value's Name is left alone: those carry other data there.
    /// A driver renamed in Alvys keeps the value it has, found by its Alvys ID.
    /// </summary>
    internal procedure ImportDrivers(DimensionCode: Code[20]; var DriversArray: JsonArray)
    var
        DimValue, OldDimValue : Record "Dimension Value";
        DriverObj: JsonObject;
        T: JsonToken;
        DriverName: Text;
        AlvysID: Code[50];
        DriverCode: Code[20];
        Inactive, IsNew : Boolean;
    begin
        foreach T in DriversArray do begin
            DriverObj := T.AsObject();
            AlvysID := AlvysIDOf(DriverObj);
            DriverName := JsonMgt.GetJsonValueAsText(DriverObj, 'Name').Trim();
            DriverCode := CopyStr(DriverName.ToUpper(), 1, MaxStrLen(DriverCode));
            Inactive := IsInactiveDriver(DriverObj);
            if FindOrInitDimValue(DimValue, OldDimValue, DimensionCode, AlvysID, DriverCode, Inactive, IsNew) then begin
                if (DimValue.Name = '') and (DriverName <> '') then
                    DimValue.Validate(Name, CopyStr(DriverName, 1, MaxStrLen(DimValue.Name)));
                SaveDimValue(DimValue, OldDimValue, Inactive, IsNew);
            end;
        end;
    end;

    local procedure IsInactiveDriver(var DriverObj: JsonObject): Boolean
    var
        JsonTkn: JsonToken;
    begin
        if not DriverObj.Get('IsActive', JsonTkn) then
            exit(false);
        if not JsonTkn.IsValue() or JsonTkn.AsValue().IsNull() then
            exit(false);
        exit(not JsonTkn.AsValue().AsBoolean());
    end;

    local procedure AlvysIDOf(var ItemObj: JsonObject): Code[50]
    begin
        exit(CopyStr(JsonMgt.GetJsonValueAsText(ItemObj, 'Id').Trim().ToUpper(), 1, 50));
    end;

    /// <summary>
    /// The Alvys ID decides which dimension value a truck or driver is: the one in DimensionCode
    /// that already carries it. Failing that, the value coded ValueCode is linked to it, provided no
    /// other Alvys record has that value. Only then is a value
    /// created, and only for something active: an inactive one blocks the value it already has,
    /// and nothing is ever unblocked, so a value blocked by hand in Business Central stays blocked.
    /// </summary>
    local procedure FindOrInitDimValue(var DimValue: Record "Dimension Value"; var OldDimValue: Record "Dimension Value"; DimensionCode: Code[20]; AlvysID: Code[50]; ValueCode: Code[20]; Inactive: Boolean; var IsNew: Boolean): Boolean
    begin
        IsNew := false;
        if AlvysID = '' then
            exit(false);

        DimValue.Reset();
        DimValue.SetCurrentKey("BAASI Alvys ID");
        DimValue.SetRange("BAASI Alvys ID", AlvysID);
        DimValue.SetRange("Dimension Code", DimensionCode);
        if DimValue.FindFirst() then begin
            DimValue.Reset();
            OldDimValue := DimValue;
            exit(true);
        end;
        DimValue.Reset();
        if ValueCode = '' then
            exit(false);

        if DimValue.Get(DimensionCode, ValueCode) then begin
            // Two drivers whose names agree in their first 20 characters share a code; the first
            // one imported keeps it.
            if DimValue."BAASI Alvys ID" <> '' then
                exit(false);
            OldDimValue := DimValue;
            DimValue.Validate("BAASI Alvys ID", AlvysID);
            exit(true);
        end;

        if Inactive then
            exit(false);
        DimValue.Init();
        DimValue.Validate("Dimension Code", DimensionCode);
        DimValue.Validate(Code, ValueCode);
        DimValue.Validate("BAASI Alvys ID", AlvysID);
        IsNew := true;
        exit(true);
    end;

    local procedure SaveDimValue(var DimValue: Record "Dimension Value"; OldDimValue: Record "Dimension Value"; Inactive: Boolean; IsNew: Boolean)
    begin
        if Inactive and not DimValue.Blocked then
            DimValue.Validate(Blocked, true);
        if IsNew then
            DimValue.Insert(true)
        else
            if (DimValue.Name <> OldDimValue.Name) or (DimValue.Blocked <> OldDimValue.Blocked) or (DimValue."BAASI Alvys ID" <> OldDimValue."BAASI Alvys ID") then
                DimValue.Modify(true);
    end;

    local procedure RaiseListError(ErrorText: Text)
    begin
        if ScheduledRun then
            Commit();
        Error(ErrorText);
    end;

    var
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        ScheduledRun: Boolean;
        InactiveTruckStatusTok: Label 'INACTIVE', Locked = true;
        NoDimensionsErr: Label 'Neither %1 in %2 nor %3 in %4 is set, so there is nothing to import trucks or drivers into.', Comment = '%1 = Truck Dimension Code caption, %2 = Fleetrock Setup caption, %3 = Driver Code Dimension caption, %4 = Alvys Sales Setup caption';
}
