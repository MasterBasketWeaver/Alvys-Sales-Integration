codeunit 80852 "BAASIT Test Run Mgt."
{
    // The one place that starts a test run. Both the "Alvys Test Results" page and the API page
    // call this, so a run triggered over the API is identical to one started from the web client.

    /// <summary>
    /// Clears the previous results, runs the suite through the test runner, and records the
    /// summary on the test run singleton.
    /// </summary>
    procedure RunSuite()
    var
        TestResult: Record "BAASIT Test Result";
        TestRun: Record "BAASIT Test Run";
        StartedAt: DateTime;
    begin
        TestResult.DeleteAll();
        TestRun.GetSingleton();
        StartedAt := CurrentDateTime();

        // A test runner cannot start inside the write transaction opened above.
        Commit();

        Codeunit.Run(Codeunit::"BAASIT Alvys Test Runner");

        TestRun."Started At" := StartedAt;
        TestRun."Finished At" := CurrentDateTime();
        TestRun.Duration := TestRun."Finished At" - StartedAt;
        TestRun.Successful := TestResult.CountByOutcome(TestResult.Outcome::Success);
        TestRun.Failed := TestResult.CountByOutcome(TestResult.Outcome::Failure);
        TestRun."Tests Run" := TestRun.Successful + TestRun.Failed;
        TestRun.Modify();
    end;
}
