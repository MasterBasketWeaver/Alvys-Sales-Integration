codeunit 80858 "BAASIT E2E Test Runner"
{
    // Runs one phase of the chained end-to-end suite. Isolation is off because the chain has to
    // survive the run: the invoice, the deduction and the run record the seed phase leaves behind
    // are what the poll phase, in a later session, asserts against.

    Subtype = TestRunner;
    TestIsolation = Disabled;

    trigger OnRun()
    begin
        Codeunit.Run(Codeunit::"BAASIT Alvys Poll E2E Tests");
    end;

    trigger OnBeforeTestRun(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; Permissions: TestPermissions): Boolean
    begin
        if not E2EContext.ShouldRun(FunctionName) then
            exit(false);
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
        E2EContext: Codeunit "BAASIT E2E Context";
        StartTime: DateTime;
}
