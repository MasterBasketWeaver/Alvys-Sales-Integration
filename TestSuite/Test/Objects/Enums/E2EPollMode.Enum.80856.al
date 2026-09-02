enum 80856 "BAASIT E2E Poll Mode"
{
    Extensible = false;
    Caption = 'Alvys E2E Poll Mode';

    // Which way the settled deduction is polled back in the last phase of the chain. The two run
    // different code in the poll: Manual calls PollSettledDeductions directly, the way the setup
    // page action does, and raises whatever stops it; Job Queue goes through the codeunit's OnRun,
    // the way the job queue does, and logs a failure instead of raising it.
    value(0; Manual) { Caption = 'Manual'; }
    value(1; "Job Queue") { Caption = 'Job Queue'; }
}
