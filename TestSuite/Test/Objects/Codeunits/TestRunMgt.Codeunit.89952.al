codeunit 89952 "BAASIT Test Run Mgt."
{
    // The one place that starts a test run. Both the "Alvys Test Results" page and the API page
    // call this, so a run triggered over the API is identical to one started from the web client.

    /// <summary>
    /// Clears the previous results, runs the suite through the test runner, and records the
    /// summary on the test run singleton.
    /// </summary>
    procedure RunSuite()
    begin
        RunSuite(false);
    end;

    /// <summary>
    /// As RunSuite, but with a choice of runner: with KeepData the suite runs through the
    /// no-rollback runner, so everything the run creates stays in Business Central, and the tests
    /// leave their repair orders in Fleetrock and their deductions in Alvys as well.
    /// </summary>
    procedure RunSuite(KeepData: Boolean)
    var
        JobQueueHold: Codeunit "BAASIT Job Queue Hold";
        TestResult: Record "BAASIT Test Result";
        TestRun: Record "BAASIT Test Run";
        TestMode: Codeunit "BAASIT Test Mode";
#if PRODUCTION
        ProductionTestRunner: Codeunit "BAASIT Production Test Runner";
#endif
        StartedAt: DateTime;
    begin
        TestResult.DeleteAll();
        TestRun.GetSingleton();
        StartedAt := CurrentDateTime();
        TestMode.SetKeepData(KeepData);

        // A test runner cannot start inside the write transaction opened above; holding the job
        // queues commits it.
        JobQueueHold.HoldJobQueues();

#if PRODUCTION
        ProductionTestRunner.Run(SuiteCodeunits(), not KeepData, false);
#else
        if KeepData then
            Codeunit.Run(Codeunit::"BAASIT Test Runner No Rollback")
        else
            Codeunit.Run(Codeunit::"BAASIT Alvys Test Runner");
#endif
        TestMode.SetKeepData(false);
        JobQueueHold.ResumeJobQueues();

        TestRun."Started At" := StartedAt;
        TestRun."Finished At" := CurrentDateTime();
        TestRun.Duration := TestRun."Finished At" - StartedAt;
        TestRun.Successful := TestResult.CountByOutcome(TestResult.Outcome::Success);
        TestRun.Failed := TestResult.CountByOutcome(TestResult.Outcome::Failure);
        TestRun."Tests Run" := TestRun.Successful + TestRun.Failed;
        TestRun.Modify();
    end;

    /// <summary>
    /// Runs one phase of the chained end-to-end suite, through the runner that keeps its data: the
    /// invoice and the deduction a phase leaves behind are what the next phase asserts against, so
    /// the isolation the ordinary suite relies on would take the chain with it.
    /// </summary>
    procedure RunE2EPhase(Phase: Enum "BAASIT E2E Phase")
    var
        JobQueueHold: Codeunit "BAASIT Job Queue Hold";
        TestResult: Record "BAASIT Test Result";
        TestRun: Record "BAASIT Test Run";
        E2EContext: Codeunit "BAASIT E2E Context";
#if PRODUCTION
        ProductionTestRunner: Codeunit "BAASIT Production Test Runner";
#endif
        StartedAt: DateTime;
    begin
        TestResult.DeleteAll();
        TestRun.GetSingleton();
        StartedAt := CurrentDateTime();
        E2EContext.SetPhase(Phase);

        // A test runner cannot start inside the write transaction opened above; holding the job
        // queues commits it. They stay held from the seed phase through the settlement in Alvys,
        // when the poll job would otherwise find the deduction first, and are resumed once the
        // poll phase has run.
        JobQueueHold.HoldJobQueues();

#if PRODUCTION
        ProductionTestRunner.Run(E2ECodeunits(), false, true);
#else
        Codeunit.Run(Codeunit::"BAASIT E2E Test Runner");
#endif
        E2EContext.SetPhase(Enum::"BAASIT E2E Phase"::None);
        if Phase in [Phase::Poll, Phase::"Statement Poll"] then
            JobQueueHold.ResumeJobQueues();

        TestRun."Started At" := StartedAt;
        TestRun."Finished At" := CurrentDateTime();
        TestRun.Duration := TestRun."Finished At" - StartedAt;
        TestRun.Successful := TestResult.CountByOutcome(TestResult.Outcome::Success);
        TestRun.Failed := TestResult.CountByOutcome(TestResult.Outcome::Failure);
        TestRun."Tests Run" := TestRun.Successful + TestRun.Failed;
        TestRun.Modify();
    end;

    /// <summary>
    /// The test codeunits of the suite, in the order they run. Every runner reads this list, so no
    /// test codeunit can be left out of one runner and not another.
    /// </summary>
    procedure SuiteCodeunits() CodeunitIds: List of [Integer]
    begin
        CodeunitIds.Add(Codeunit::"BAASIT Alvys Sales Tests");
        CodeunitIds.Add(Codeunit::"BAASIT Fleetrock E2E Tests");
        CodeunitIds.Add(Codeunit::"BAASIT Fleetrock TZ Tests");
        CodeunitIds.Add(Codeunit::"BAASIT Alvys Dim Import Tests");
        CodeunitIds.Add(Codeunit::"BAASIT Fleetrock Driver Tests");
        // The chained end-to-end codeunits are deliberately not here. Their phases have a manual
        // settlement in the Alvys web UI between them, so they cannot run unattended as part of the
        // suite; RunE2EPhase runs them a phase at a time instead.
    end;

    /// <summary>
    /// The chained end-to-end test codeunits, whose methods RunE2EPhase picks one phase from.
    /// </summary>
    procedure E2ECodeunits() CodeunitIds: List of [Integer]
    begin
        CodeunitIds.Add(Codeunit::"BAASIT Alvys Poll E2E Tests");
        CodeunitIds.Add(Codeunit::"BAASIT Alvys Stmt E2E Tests");
    end;
}
