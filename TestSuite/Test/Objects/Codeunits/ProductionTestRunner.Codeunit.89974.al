#if PRODUCTION
codeunit 89974 "BAASIT Production Test Runner"
{
    // Business Central runs Test and TestRunner codeunits only in sandboxes; in production every run
    // fails with "Test Automation is not enabled on this system". The PRODUCTION build therefore
    // compiles the test codeunits as ordinary codeunits and runs them through this instead.
    //
    // Each test method runs in its own Codeunit.Run of this codeunit (OnRun), which catches its error
    // the way OnAfterTestRun reports Success = false. A method that passes raises PassedRolledBackErr
    // at the end when the run rolls back, so its changes are undone like a failing one's. That is
    // finer than the sandbox's per-codeunit isolation, but it cannot undo what a test committed.
    //
    // Single instance, so the rollback choice made by Run is still there in the nested OnRun.

    SingleInstance = true;
    TableNo = "BAASIT Test Result";

    trigger OnRun()
    var
        TestDispatch: Codeunit "BAASIT Test Dispatch";
    begin
        if not TestDispatch.Run(Rec."Codeunit ID", Rec."Method Name") then
            Error(UnknownTestErr, Rec."Method Name", Rec."Codeunit ID");
        if RollBack then
            Error(PassedRolledBackErr);
    end;

    /// <summary>
    /// Runs every test method of the given codeunits, in source order, logging each outcome. With
    /// OnlyE2EPhase only the methods of the current end-to-end phase run.
    /// </summary>
    procedure Run(CodeunitIds: List of [Integer]; NewRollBack: Boolean; OnlyE2EPhase: Boolean)
    var
        TestResult: Record "BAASIT Test Result";
        TestDispatch: Codeunit "BAASIT Test Dispatch";
        E2EContext: Codeunit "BAASIT E2E Context";
        CodeunitId: Integer;
        MethodName: Text;
        StartTime: DateTime;
        Success: Boolean;
    begin
        RollBack := NewRollBack;
        foreach CodeunitId in CodeunitIds do
            foreach MethodName in TestDispatch.TestMethods(CodeunitId) do
                if (not OnlyE2EPhase) or E2EContext.ShouldRun(MethodName) then begin
                    // Codeunit.Run can only report an error from outside a write transaction.
                    Commit();
                    ClearLastError();
                    TestResult.Init();
                    TestResult."Codeunit ID" := CodeunitId;
                    TestResult."Method Name" := CopyStr(MethodName, 1, MaxStrLen(TestResult."Method Name"));
                    StartTime := CurrentDateTime();
                    Success := Codeunit.Run(Codeunit::"BAASIT Production Test Runner", TestResult);
                    if not Success and (GetLastErrorText() = PassedRolledBackErr) then
                        Success := true;
                    TestResult.Log(CodeunitId, CodeunitName(CodeunitId), MethodName, StartTime, Success);
                end;
        Commit();
    end;

    local procedure CodeunitName(CodeunitId: Integer): Text
    var
        AllObj: Record AllObj;
    begin
        if AllObj.Get(AllObj."Object Type"::Codeunit, CodeunitId) then
            exit(AllObj."Object Name");
    end;

    var
        RollBack: Boolean;
        PassedRolledBackErr: Label 'The test passed; its changes are being rolled back.', Locked = true;
        UnknownTestErr: Label 'Test method %1 of codeunit %2 is not in codeunit "BAASIT Test Dispatch". Republish with Tools/bc-publish-tests-production.py, which regenerates it.', Locked = true;
}
#endif
