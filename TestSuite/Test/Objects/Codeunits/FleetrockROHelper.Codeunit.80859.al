codeunit 80859 "BAASIT Fleetrock RO Helper"
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
    var
        ResponseArray: JsonArray;
        JTkn: JsonToken;
    begin
        GetSetup();
        ResponseArray := RestAPIMgt.GetResponseAsJsonArray(
            StrSubstNo('%1/API/%2?token=%3', FleetrockSetup."Integration URL", Endpoint, FleetrockMgt.CheckToGetAPIToken()),
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
}
