codeunit 80855 "BAASIT Test Mode"
{
    // Session-wide flag that tells the tests which runner the suite was started through. When
    // keep-data is set, the run uses the no-rollback runner and the tests skip their external
    // clean-up, so the repair order stays in Fleetrock and the deduction stays in Alvys alongside
    // the Business Central documents.

    SingleInstance = true;

    procedure SetKeepData(NewKeepData: Boolean)
    begin
        KeepData := NewKeepData;
    end;

    procedure GetKeepData(): Boolean
    begin
        exit(KeepData);
    end;

    /// <summary>
    /// Whether a test method should be left out of this run rather than run and failed.
    ///
    /// Some tests only hold while a company setting is what they expect, and auto-posting deductions
    /// is the one that matters. The inbound tests in codeunit "BAASIT Alvys Sales Tests" are about
    /// the matching; with auto-posting on a matched settlement also posts, which is neither what
    /// they assert nor something they set up a postable document for. Leaving them out keeps the
    /// total honest -- it counts what the run could actually apply, rather than reporting failures
    /// for a setting nobody got wrong. Codeunit "BAASIT Fleetrock E2E Tests" covers posting either
    /// way, on the invoice its own run posted, so nothing goes uncovered.
    ///
    /// A blank method name is the callback for the test codeunit as a whole and is never skipped:
    /// skipping it would take every test in the codeunit with it.
    /// </summary>
    procedure SkipTest(CodeunitId: Integer; FunctionName: Text): Boolean
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
    begin
        if FunctionName = '' then
            exit(false);
        if CodeunitId <> Codeunit::"BAASIT Alvys Sales Tests" then
            exit(false);
        if not RequiresAutoPostOff(FunctionName) then
            exit(false);
        if not AlvysSetup.Get() then
            exit(false);
        exit(AlvysSetup."Auto-Post Deductions");
    end;

    /// <summary>
    /// The inbound tests that expect a matched settlement to leave no error behind. They are named
    /// rather than detected, because a test runner is told nothing about a method beyond its name.
    /// Keep this in step with the tests that call RequirePaymentJournalSetup; a name that falls out
    /// of step fails loudly on that call rather than silently posting, which is the way round it
    /// should be.
    /// </summary>
    local procedure RequiresAutoPostOff(FunctionName: Text): Boolean
    begin
        exit(FunctionName in ['InboundAPIPageLogsEntryAsInbound',
                              'InboundAPIPageAcceptsEitherTruckField',
                              'MatchedDeductionLeavesNoErrorToRefuseOn']);
    end;

    var
        KeepData: Boolean;
}
