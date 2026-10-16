#if not PRODUCTION
codeunit 89958 "BAASIT E2E Test Runner"
{
    // Runs one phase of the chained end-to-end suite. Isolation is off because the chain has to
    // survive the run: the invoice, the deduction and the run record the seed phase leaves behind
    // are what the poll phase, in a later session, asserts against.

    Subtype = TestRunner;
    TestIsolation = Disabled;

    trigger OnRun()
    var
        TestRunMgt: Codeunit "BAASIT Test Run Mgt.";
        CodeunitId: Integer;
    begin
        foreach CodeunitId in TestRunMgt.E2ECodeunits() do
            Codeunit.Run(CodeunitId);
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
    begin
        if FunctionName = '' then
            exit;
        TestResult.Log(CodeunitId, CodeunitName, FunctionName, this.StartTime, Success);
    end;

    var
        E2EContext: Codeunit "BAASIT E2E Context";
        StartTime: DateTime;
}
#endif
