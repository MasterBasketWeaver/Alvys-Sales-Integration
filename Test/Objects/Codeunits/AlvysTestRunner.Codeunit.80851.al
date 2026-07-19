codeunit 80851 "BAASIT Alvys Test Runner"
{
    // Runs the Alvys test codeunits and logs the outcome of every test method to the
    // "BAASIT Test Result" table, so the whole suite can be run and read from inside Business
    // Central -- from page "BAASIT Alvys Test Results" -- without the AL Test Tool.
    //
    // Implementing OnAfterTestRun also suppresses the platform's own results message, which is
    // what lets the calling page report the run itself.

    Subtype = TestRunner;
    TestIsolation = Codeunit;

    trigger OnRun()
    begin
        // All Alvys tests belong in codeunit "BAASIT Alvys Sales Tests" -- add new [Test] methods
        // there rather than creating further test codeunits, so this stays a single explicit line
        // and no test can be silently left out of a run.
        Codeunit.Run(Codeunit::"BAASIT Alvys Sales Tests");
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
        // A blank method name is the callback for the test codeunit as a whole; the individual
        // methods have already been logged by then, so there is nothing to add.
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
