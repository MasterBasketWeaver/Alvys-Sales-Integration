codeunit 80857 "BAASIT E2E Context"
{
    // Which phase of the chained end-to-end run the current run is executing. The runner reads it
    // to leave the other phase's test out, so one API call runs one phase and reports only that
    // phase's result.

    SingleInstance = true;

    procedure SetPhase(NewPhase: Enum "BAASIT E2E Phase")
    begin
        Phase := NewPhase;
    end;

    procedure GetPhase(): Enum "BAASIT E2E Phase"
    begin
        exit(Phase);
    end;

    /// <summary>
    /// Whether a test method belongs to the phase being run. A blank method name is the callback
    /// for the codeunit as a whole and is always kept: skipping it would take the phase with it.
    /// </summary>
    procedure ShouldRun(FunctionName: Text): Boolean
    begin
        if FunctionName = '' then
            exit(true);
        case Phase of
            Phase::Seed:
                exit(FunctionName = 'RepairOrderReachesAlvysAsADeduction');
            Phase::Poll:
                exit(FunctionName = 'SettledDeductionIsPolledBackAndPaysTheInvoice');
        end;
        exit(false);
    end;

    var
        Phase: Enum "BAASIT E2E Phase";
}
