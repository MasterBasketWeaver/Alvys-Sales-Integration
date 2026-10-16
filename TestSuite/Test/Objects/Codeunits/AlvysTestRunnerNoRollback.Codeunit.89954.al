#if not PRODUCTION
codeunit 89954 "BAASIT Test Runner No Rollback"
{
    // The no-rollback twin of codeunit "BAASIT Alvys Test Runner": TestIsolation is a compile-time
    // property, so keeping data after a run needs its own runner. Everything a run creates stays
    // in Business Central, and the tests read the keep-data flag (codeunit "BAASIT Test Mode") to
    // also leave their repair orders in Fleetrock and their deductions in Alvys. Use it to inspect
    // the documents a run produces; the regular runner remains the default.

    Subtype = TestRunner;
    TestIsolation = Disabled;

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
        if FunctionName = '' then
            exit;
        TestResult.Log(CodeunitId, CodeunitName, FunctionName, this.StartTime, Success);
    end;

    var
        // TestMode: Codeunit "BAASIT Test Mode";
        StartTime: DateTime;
}
#endif
