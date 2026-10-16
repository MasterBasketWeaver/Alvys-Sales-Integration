#if not PRODUCTION
codeunit 89951 "BAASIT Alvys Test Runner"
{
    // Runs the Alvys test codeunits and logs the outcome of every test method to the
    // "BAASIT Test Result" table, so the whole suite can be run and read from inside Business
    // Central -- from page "BAASIT Alvys Test Results" -- without the AL Test Tool.
    //
    // Implementing OnAfterTestRun also suppresses the platform's own results message, which is
    // what lets the calling page report the run itself.
    //
    // Production has no test automation, so the PRODUCTION build leaves the test runners out and
    // runs the same codeunits through "BAASIT Production Test Runner" instead.

    Subtype = TestRunner;
    TestIsolation = Codeunit;

    trigger OnRun()
    var
        TestRunMgt: Codeunit "BAASIT Test Run Mgt.";
        CodeunitId: Integer;
    begin
        foreach CodeunitId in TestRunMgt.SuiteCodeunits() do
            Codeunit.Run(CodeunitId);
    end;

    trigger OnBeforeTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions): Boolean
    begin
        // // Returning false leaves the test out of the run entirely: it is not executed and
        // // OnAfterTestRun never fires for it, so it is not logged and not counted.
        // if TestMode.SkipTest(CodeunitId, FunctionName) then
            // exit(false);
        this.StartTime := CurrentDateTime();
        exit(true);
    end;

    trigger OnAfterTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions; Success: Boolean)
    var
        TestResult: Record "BAASIT Test Result";
    begin
        // A blank method name is the callback for the test codeunit as a whole; the individual
        // methods have already been logged by then, so there is nothing to add.
        if FunctionName = '' then
            exit;
        TestResult.Log(CodeunitId, CodeunitName, FunctionName, this.StartTime, Success);
    end;

    var
        // TestMode: Codeunit "BAASIT Test Mode";
        StartTime: DateTime;
}
#endif
