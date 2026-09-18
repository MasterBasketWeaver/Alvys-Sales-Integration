codeunit 89959 "BAASIT Fleetrock RO Helper"
{
    // The Fleetrock repair order lifecycle the end-to-end tests drive: create one, move it to
    // Invoiced so the import job picks it up, read it back, and walk it back far enough to delete.
    // Shared so the chained run and codeunit "BAASIT Fleetrock E2E Tests" drive Fleetrock the same
    // way, and a change to how Fleetrock wants to be driven is made once.

    /// <summary>
    /// Creates a repair order through the AddRO API for the given unit with one labor task
    /// (2h x $75.00) and one part (2 x $27.50), so the grand total is $205.00. AddRO defaults the
    /// invoiced and paid dates to the finished date, so the order comes back as Paid until
    /// SetRepairOrderToInvoiced moves it to Invoiced.
    /// </summary>
    procedure CreateRepairOrder(UnitVin: Text) ROId: Text
    var
        JsonBody, ROJson, TaskJson, PartJson, ResponseObj : JsonObject;
        ROArray, TaskArray, PartArray : JsonArray;
    begin
        GetSetup();

        PartJson.Add('part_subtotal', '55.00');
        PartJson.Add('part_quantity', '2');
        PartJson.Add('part_description', 'BC test part');
        PartArray.Add(PartJson);

        TaskJson.Add('labor_subtotal', '150.00');
        TaskJson.Add('labor_hours', '2');
        TaskJson.Add('labor_complaint', 'BC test app repair');
        TaskJson.Add('parts', PartArray);
        TaskArray.Add(TaskJson);

        ROJson.Add('vin', UnitVin);
        ROJson.Add('date_started', FormatFleetrockDate(CalcDate('<-2D>', Today())));
        ROJson.Add('date_finished', FormatFleetrockDate(CalcDate('<-1D>', Today())));
        ROJson.Add('invoice_number', StrSubstNo('BCTEST-%1', Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>')));
        ROJson.Add('notes', 'Created by the BC test app');
        ROJson.Add('tasks', TaskArray);
        ROArray.Add(ROJson);

        JsonBody.Add('customer_id', FleetrockSetup.Username);
        JsonBody.Add('vendor_id', FleetrockSetup."Vendor Username");
        JsonBody.Add('repair_orders', ROArray);

        ResponseObj := PostToFleetrock('AddRO', JsonBody);
        ROId := JsonMgt.GetJsonValueAsText(ResponseObj, 'ro_id');
        Assert.AreNotEqual('', ROId, 'AddRO should return the id of the created repair order.');
    end;

    /// <summary>
    /// Creates a repair order with a task per repair and several parts on each. Every task and
    /// every part becomes a line on the imported sales invoice, so this is how a busy repair order
    /// is produced for inspection.
    ///
    /// The cause and correction codes AddRO takes are validated against Fleetrock's own code lists
    /// and refused when they are not in them, so the detail here is in the fields it takes free:
    /// the system code, which is what the invoice line is described by, and the complaint.
    ///
    /// Labor is 2h at $75.00 a task and parts are 2 at $12.50 each, so the grand total is
    /// TaskCount * $150.00 plus PartCount * $25.00. AddRO drops an odometer reading, a cost centre
    /// and additional charges on the way in, so they are not sent.
    /// </summary>
    procedure CreateDetailedRepairOrder(UnitVin: Text; TaskCount: Integer; PartsPerTask: Integer) ROId: Text
    var
        JsonBody, ROJson, TaskJson, PartJson, ResponseObj : JsonObject;
        ROArray, TaskArray, PartArray : JsonArray;
        TaskNo, PartNo : Integer;
    begin
        GetSetup();

        for TaskNo := 1 to TaskCount do begin
            Clear(TaskJson);
            Clear(PartArray);
            for PartNo := 1 to PartsPerTask do begin
                Clear(PartJson);
                PartJson.Add('part_number', StrSubstNo('BCTEST-P%1-%2', TaskNo, PartNo));
                PartJson.Add('part_description', StrSubstNo('%1 (task %2, part %3)', PartDescription(PartNo), TaskNo, PartNo));
                PartJson.Add('part_type', 'Part');
                PartJson.Add('part_quantity', '2');
                PartJson.Add('part_price', '12.50');
                PartJson.Add('part_subtotal', '25.00');
                PartJson.Add('part_location', StrSubstNo('BIN-%1', TaskNo));
                PartArray.Add(PartJson);
            end;

            TaskJson.Add('labor_type', 'Repair');
            TaskJson.Add('labor_system_code', StrSubstNo('%1 (task %2)', TaskDescription(TaskNo), TaskNo));
            TaskJson.Add('labor_complaint', StrSubstNo('Task %1: %2 reported by the driver on the pre-trip inspection.', TaskNo, TaskDescription(TaskNo)));
            TaskJson.Add('labor_hours', '2');
            TaskJson.Add('labor_hourly_rate', '75.00');
            TaskJson.Add('labor_subtotal', '150.00');
            TaskJson.Add('parts', PartArray);
            TaskArray.Add(TaskJson);
        end;

        ROJson.Add('vin', UnitVin);
        ROJson.Add('date_started', FormatFleetrockDate(CalcDate('<-2D>', Today())));
        ROJson.Add('date_finished', FormatFleetrockDate(CalcDate('<-1D>', Today())));
        ROJson.Add('invoice_number', StrSubstNo('BCTEST-%1', Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2><Seconds,2>')));
        ROJson.Add('po_number', StrSubstNo('PO-%1', Format(CurrentDateTime(), 0, '<Year4><Month,2><Day,2><Hours24,2><Minutes,2>')));
        ROJson.Add('engine_hours', '9120');
        ROJson.Add('notes', StrSubstNo('Created by the BC test app: %1 tasks, %2 parts each, for inspection in Business Central.', TaskCount, PartsPerTask));
        ROJson.Add('tasks', TaskArray);
        ROArray.Add(ROJson);

        JsonBody.Add('customer_id', FleetrockSetup.Username);
        JsonBody.Add('vendor_id', FleetrockSetup."Vendor Username");
        JsonBody.Add('repair_orders', ROArray);

        ResponseObj := PostToFleetrock('AddRO', JsonBody);
        ROId := JsonMgt.GetJsonValueAsText(ResponseObj, 'ro_id');
        Assert.AreNotEqual('', ROId, 'AddRO should return the id of the created repair order.');
    end;

    local procedure TaskDescription(TaskNo: Integer): Text
    var
        Descriptions: List of [Text];
    begin
        Descriptions.Add('Engine oil and filter service');
        Descriptions.Add('Front brake pads and rotors');
        Descriptions.Add('Air dryer cartridge replacement');
        Descriptions.Add('Steer tire replacement');
        Descriptions.Add('Trailer light repair');
        Descriptions.Add('DPF clean and regeneration');
        Descriptions.Add('Coolant system service');
        Descriptions.Add('Fifth wheel lubrication');
        exit(Descriptions.Get(1 + (TaskNo - 1) mod Descriptions.Count()));
    end;

    local procedure PartDescription(PartNo: Integer): Text
    var
        Descriptions: List of [Text];
    begin
        Descriptions.Add('Oil filter');
        Descriptions.Add('Brake pad set');
        Descriptions.Add('Air dryer cartridge');
        Descriptions.Add('Wheel seal');
        Descriptions.Add('Marker lamp');
        exit(Descriptions.Get(1 + (PartNo - 1) mod Descriptions.Count()));
    end;

    /// <summary>
    /// Waits until Fleetrock has every task and part AddRO was given. AddRO returns as soon as the
    /// repair order exists, and its totals are right immediately, but the tasks and their parts
    /// appear over the next few seconds -- so an import run straight afterwards sees a short order
    /// and builds a sales invoice missing lines, with nothing logged as an error anywhere.
    /// </summary>
    procedure WaitForRepairOrderDetail(ROId: Text; TaskCount: Integer; PartsPerTask: Integer)
    var
        Deadline: DateTime;
        TimeoutMs, IntervalMs, Tasks, Parts : Integer;
    begin
        TimeoutMs := 180000;
        IntervalMs := 5000;
        Deadline := CurrentDateTime() + TimeoutMs;
        repeat
            CountRepairOrderDetail(ROId, Tasks, Parts);
            if (Tasks >= TaskCount) and (Parts >= TaskCount * PartsPerTask) then
                exit;
            Sleep(IntervalMs);
        until CurrentDateTime() > Deadline;
        Error(DetailNeverArrivedErr, ROId, TaskCount, TaskCount * PartsPerTask, Tasks, Parts);
    end;

    local procedure CountRepairOrderDetail(ROId: Text; var Tasks: Integer; var Parts: Integer)
    var
        ROObj, TaskObj : JsonObject;
        TaskArray: JsonArray;
        TasksTkn, TaskTkn, PartsTkn : JsonToken;
    begin
        Tasks := 0;
        Parts := 0;
        ROObj := GetRepairOrder(ROId);
        if not ROObj.Get('tasks', TasksTkn) then
            exit;
        TaskArray := TasksTkn.AsArray();
        Tasks := TaskArray.Count();
        foreach TaskTkn in TaskArray do begin
            TaskObj := TaskTkn.AsObject();
            if TaskObj.Get('parts', PartsTkn) then
                Parts += PartsTkn.AsArray().Count();
        end;
    end;

    /// <summary>
    /// Resolves a Fleetrock unit number to the VIN AddRO wants, so a caller can name the truck the
    /// way Alvys and the tractor code dimension do.
    /// </summary>
    procedure GetUnitVin(UnitNumber: Text) Vin: Text
    var
        UnitsArray: JsonArray;
        UnitTkn: JsonToken;
        UnitObj: JsonObject;
    begin
        if not FleetrockMgt.TryToGetUnits(UnitsArray) then
            Error(UnitLookupFailedErr, GetLastErrorText());
        foreach UnitTkn in UnitsArray do begin
            UnitObj := UnitTkn.AsObject();
            if JsonMgt.GetJsonValueAsText(UnitObj, 'unit_number').ToUpper() = UnitNumber.ToUpper() then
                exit(JsonMgt.GetJsonValueAsText(UnitObj, 'vin'));
        end;
        Error(UnitNotFoundErr, UnitNumber);
    end;

    /// <summary>
    /// Moves the repair order to Invoiced as of yesterday. The paid date is removed first and the
    /// invoiced date set in a second call, because Fleetrock stores a combined update with an
    /// unpredictable timestamp. Dates are sent date-only and parsed by Fleetrock as US Eastern,
    /// so yesterday's date is always safely inside the import window regardless of time zone.
    /// </summary>
    procedure SetRepairOrderToInvoiced(ROId: Text)
    begin
        UpdateRepairOrder(ROId, 'date_invoice_paid', 'delete');
        UpdateRepairOrder(ROId, 'date_invoiced', FormatFleetrockDate(CalcDate('<-1D>', Today())));
    end;

    /// <summary>
    /// Waits until Fleetrock reports the invoiced date it was just given. SetRepairOrderToInvoiced
    /// returns as soon as the status flips, but date_invoiced follows a moment later -- and an
    /// import that reads the order in between stages it with no invoiced date at all, which sends
    /// the sales invoice to the fallback posting date rather than the date it was invoiced on.
    /// </summary>
    procedure WaitForInvoicedDate(ROId: Text)
    var
        ROObj: JsonObject;
        Deadline: DateTime;
        TimeoutMs, IntervalMs : Integer;
        InvoicedDate: Text;
    begin
        TimeoutMs := 180000;
        IntervalMs := 5000;
        Deadline := CurrentDateTime() + TimeoutMs;
        repeat
            ROObj := GetRepairOrder(ROId);
            InvoicedDate := JsonMgt.GetJsonValueAsText(ROObj, 'date_invoiced');
            if InvoicedDate <> '' then
                exit;
            Sleep(IntervalMs);
        until CurrentDateTime() > Deadline;
        Error(InvoicedDateNeverArrivedErr, ROId);
    end;

    /// <summary>
    /// Removes the repair order from Fleetrock once the test is done. Fleetrock refuses to delete
    /// an invoiced order, so the invoiced and finished dates are removed first to walk the status
    /// back. The API rejects removing the started date, so In Progress is as far back as an order
    /// can go -- which is enough for the delete to be accepted.
    /// </summary>
    procedure DeleteRepairOrder(ROId: Text)
    begin
        // Fleetrock puts the paid date back when the invoiced date is set, the same way AddRO
        // defaults both to the finished date, and it refuses to drop the invoiced date while a paid
        // date is there. So the paid date comes off first, exactly as SetRepairOrderToInvoiced does.
        UpdateRepairOrder(ROId, 'date_invoice_paid', 'delete');
        UpdateRepairOrder(ROId, 'date_invoiced', 'delete');
        UpdateRepairOrder(ROId, 'date_finished', 'delete');
        UpdateRepairOrder(ROId, 'status', 'deleted');
    end;

    procedure UpdateRepairOrder(ROId: Text; FieldName: Text; FieldValue: Text)
    var
        JsonBody, ROJson : JsonObject;
        ROArray: JsonArray;
    begin
        GetSetup();
        ROJson.Add('ro_id', ROId);
        ROJson.Add(FieldName, FieldValue);
        ROArray.Add(ROJson);
        JsonBody.Add('username', FleetrockSetup.Username);
        JsonBody.Add('repair_orders', ROArray);
        PostToFleetrock('UpdateRO', JsonBody);
    end;

    procedure GetRepairOrder(ROId: Text) ROObj: JsonObject
    var
        ROArray: JsonArray;
        JTkn: JsonToken;
    begin
        GetSetup();
        ROArray := RestAPIMgt.GetResponseAsJsonArray(
            StrSubstNo('%1/API/GetRO?username=%2&token=%3&id=%4', FleetrockSetup."Integration URL", FleetrockSetup.Username, FleetrockMgt.CheckToGetAPIToken(), ROId),
            'repair_orders');
        Assert.AreEqual(1, ROArray.Count(), StrSubstNo('Fleetrock should return repair order %1.', ROId));
        ROArray.Get(0, JTkn);
        ROObj := JTkn.AsObject();
    end;

    /// <summary>
    /// Posts a JSON body to a Fleetrock API endpoint and returns the first entry of its
    /// "response" array, failing the test if Fleetrock reports an error.
    /// </summary>
    procedure PostToFleetrock(Endpoint: Text; var JsonBody: JsonObject) ResponseObj: JsonObject
    begin
        ResponseObj := PostToFleetrock(Endpoint, JsonBody, false);
    end;

    procedure PostToFleetrock(Endpoint: Text; var JsonBody: JsonObject; UseVendorAccount: Boolean) ResponseObj: JsonObject
    var
        ResponseArray: JsonArray;
        JTkn: JsonToken;
    begin
        GetSetup();
        ResponseArray := RestAPIMgt.GetResponseAsJsonArray(
            StrSubstNo('%1/API/%2?token=%3', FleetrockSetup."Integration URL", Endpoint, FleetrockMgt.CheckToGetAPIToken(UseVendorAccount)),
            'response', 'POST', JsonBody);
        Assert.AreEqual(1, ResponseArray.Count(), StrSubstNo('%1 should return one response entry.', Endpoint));
        ResponseArray.Get(0, JTkn);
        ResponseObj := JTkn.AsObject();
        Assert.AreEqual('success', JsonMgt.GetJsonValueAsText(ResponseObj, 'result'),
            StrSubstNo('%1 should succeed: %2', Endpoint, JsonMgt.GetJsonValueAsText(ResponseObj, 'message')));
    end;

    /// <summary>
    /// Pulls the import error logged on the staging record for the repair order, so a failed
    /// import surfaces its cause in the test failure message.
    /// </summary>
    procedure GetStagingError(ROId: Text): Text
    var
        RepairHeaderStaging: Record "FRI Repair Header";
    begin
        RepairHeaderStaging.SetRange(id, ROId);
        if RepairHeaderStaging.FindLast() then
            if RepairHeaderStaging."Error Message" <> '' then
                exit(StrSubstNo(' Staging error: %1', RepairHeaderStaging."Error Message"));
    end;

    procedure FormatFleetrockDate(D: Date): Text
    begin
        exit(Format(D, 0, '<Month>/<Day>/<Year4>'));
    end;

    local procedure GetSetup()
    begin
        if not LoadedSetup then begin
            FleetrockSetup.Get();
            LoadedSetup := true;
        end;
    end;

    var
        FleetrockSetup: Record "FRI Fleetrock Setup";
        Assert: Codeunit "Library Assert";
        FleetrockMgt: Codeunit "FRI Fleetrock Mgt.";
        JsonMgt: Codeunit "FRI Json Mgt.";
        RestAPIMgt: Codeunit "FRI REST API Mgt.";
        LoadedSetup: Boolean;

        DetailNeverArrivedErr: Label 'Fleetrock repair order %1 still shows %4 of %2 tasks and %5 of %3 parts.', Comment = '%1 = Repair Order Id, %2 = expected tasks, %3 = expected parts, %4 = tasks found, %5 = parts found';
        InvoicedDateNeverArrivedErr: Label 'Fleetrock repair order %1 still reports no invoiced date.', Comment = '%1 = Repair Order Id';
        UnitLookupFailedErr: Label 'Fleetrock unit lookup failed: %1', Comment = '%1 = the error text';
        UnitNotFoundErr: Label 'No Fleetrock unit was found with unit number %1.', Comment = '%1 = Unit Number';
}
