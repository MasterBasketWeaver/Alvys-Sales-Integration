codeunit 89962 "BAASIT RO Post Location"
{
    // Another app in the sandbox refuses to post a document without a location, and the Fleetrock
    // import does not assign one. The auto-post test cannot set it between the import and the
    // posting the way the manual test does, so it is set here, just before the import posts.
    //
    // Assigned without validation: validating the location rebuilds the dimension sets from
    // default dimensions and would wipe the asset dimension the import placed on the document.

    EventSubscriberInstance = Manual;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"FRI Get Repair Orders", OnBeforePostSalesHeaderFromRepairOrder, '', false, false)]
    local procedure GetRepairOrdersOnBeforePostSalesHeaderFromRepairOrder(var SalesHeader: Record "Sales Header"; var SalesHeaderStaging: Record "FRI Repair Header"; var IsHandled: Boolean; var Success: Boolean)
    var
        SalesLine: Record "Sales Line";
    begin
        SalesHeader."Location Code" := LocationCodeTok;
        SalesHeader.Modify(true);
        SalesLine.SetRange("Document Type", SalesHeader."Document Type");
        SalesLine.SetRange("Document No.", SalesHeader."No.");
        SalesLine.SetRange(Type, SalesLine.Type::"G/L Account");
        if SalesLine.FindSet(true) then
            repeat
                SalesLine."Location Code" := LocationCodeTok;
                SalesLine.Modify(true);
            until SalesLine.Next() = 0;
    end;

    var
        LocationCodeTok: Label 'TEST', Locked = true;
}
