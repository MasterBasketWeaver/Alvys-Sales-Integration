codeunit 80854 "BAASIT Test Runner No Rollback"
{
    // The no-rollback twin of codeunit "BAASIT Alvys Test Runner": TestIsolation is a compile-time
    // property, so keeping data after a run needs its own runner. Everything a run creates stays
    // in Business Central, and the tests read the keep-data flag (codeunit "BAASIT Test Mode") to
    // also leave their repair orders in Fleetrock and their deductions in Alvys. Use it to inspect
    // the documents a run produces; the regular runner remains the default.

    Subtype = TestRunner;
    TestIsolation = Disabled;

    trigger OnRun()
    begin
        // Keep this list identical to the one in codeunit "BAASIT Alvys Test Runner", so both
        // runners always cover the same suite.
        Codeunit.Run(Codeunit::"BAASIT Alvys Sales Tests");
        Codeunit.Run(Codeunit::"BAASIT Fleetrock E2E Tests");
    end;

    trigger OnBeforeTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions): Boolean
    begin
        this.StartTime := CurrentDateTime();
        exit(true);
    end;

    trigger OnAfterTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions; Success: Boolean)
    var
        TestResult: Record "BAASIT Test Result";
        FinishTime: DateTime;
    begin
        if FunctionName = '' then
            exit;

        FinishTime := CurrentDateTime();

        TestResult.Init();
        TestResult."Codeunit ID" := CodeunitId;
        TestResult."Codeunit Name" := CopyStr(CodeunitName, 1, MaxStrLen(TestResult."Codeunit Name"));
        TestResult."Method Name" := CopyStr(FunctionName, 1, MaxStrLen(TestResult."Method Name"));
        TestResult."Start Time" := this.StartTime;
        TestResult."Finish Time" := FinishTime;
        TestResult.Duration := FinishTime - this.StartTime;

        if Success then
            TestResult.Outcome := TestResult.Outcome::Success
        else begin
            TestResult.Outcome := TestResult.Outcome::Failure;
            TestResult."Error Message" := CopyStr(GetLastErrorText(), 1, MaxStrLen(TestResult."Error Message"));
        end;

        TestResult.Insert(true);
    end;

    var
        StartTime: DateTime;
}
