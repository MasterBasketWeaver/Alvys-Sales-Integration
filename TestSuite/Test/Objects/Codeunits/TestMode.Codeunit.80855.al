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

    var
        KeepData: Boolean;
}
