page 80852 "BAASIT Alvys Test Run API"
{
    // Custom API pages are exposed automatically, so this needs no web service registration.
    //
    //   POST .../api/bryana/alvys/v1.0/companies({companyId})/alvysTestRuns({id})/Microsoft.NAV.run
    //
    // The run is synchronous: the call returns once every test has finished, with the summary in
    // the response body. Per-method detail is on the alvysTestResults entity.

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysTestRun';
    EntitySetName = 'alvysTestRuns';
    SourceTable = "BAASIT Test Run";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Test Run';
    DelayedInsert = true;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { }
                field(startedAt; Rec."Started At") { }
                field(finishedAt; Rec."Finished At") { }
                field(duration; Rec.Duration) { }
                field(testsRun; Rec."Tests Run") { }
                field(successful; Rec.Successful) { }
                field(failed; Rec.Failed) { }
            }
        }
    }

    [ServiceEnabled]
    procedure run(var ActionContext: WebServiceActionContext)
    var
        TestRunMgt: Codeunit "BAASIT Test Run Mgt.";
    begin
        TestRunMgt.RunSuite();
        Rec.GetSingleton();

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"BAASIT Alvys Test Run API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;

    trigger OnOpenPage()
    begin
        // Make sure the singleton exists, so the entity set is never empty for a caller that is
        // looking up the key before posting the action.
        Rec.GetSingleton();
    end;
}
