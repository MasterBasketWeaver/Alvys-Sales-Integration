page 80853 "BAASIT Alvys Test Result API"
{
    // Read-only detail for the most recent run:
    //
    //   GET .../api/bryana/alvys/v1.0/companies({companyId})/alvysTestResults
    //
    // Filter to failures with ?$filter=outcome eq 'Failure' to get just the errors.

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysTestResult';
    EntitySetName = 'alvysTestResults';
    SourceTable = "BAASIT Test Result";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Test Result';
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
                field(entryNo; Rec."Entry No.") { }
                field(codeunitId; Rec."Codeunit ID") { }
                field(codeunitName; Rec."Codeunit Name") { }
                field(methodName; Rec."Method Name") { }
                field(outcome; Rec.Outcome) { }
                field(duration; Rec.Duration) { }
                field(errorMessage; Rec."Error Message") { }
                field(startedAt; Rec."Start Time") { }
                field(finishedAt; Rec."Finish Time") { }
            }
        }
    }
}
