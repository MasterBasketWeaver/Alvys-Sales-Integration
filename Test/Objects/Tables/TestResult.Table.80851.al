table 80851 "BAASIT Test Result"
{
    Caption = 'Alvys Test Result';
    DataClassification = SystemMetadata;
    DrillDownPageId = "BAASIT Alvys Test Results";
    LookupPageId = "BAASIT Alvys Test Results";

    // Written from the OnAfterTestRun trigger of codeunit "BAASIT Alvys Test Runner". That trigger
    // runs in its own transaction, so these rows survive the rollback that test isolation performs
    // on everything the tests themselves touched.

    fields
    {
        field(1; "Entry No."; Integer)
        {
            DataClassification = SystemMetadata;
            AutoIncrement = true;
            Editable = false;
        }
        field(2; "Codeunit ID"; Integer)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(3; "Codeunit Name"; Text[100])
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(4; "Method Name"; Text[128])
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(5; Outcome; Enum "BAASIT Test Outcome")
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(6; "Start Time"; DateTime)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(7; "Finish Time"; DateTime)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(8; Duration; Duration)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(9; "Error Message"; Text[2048])
        {
            DataClassification = SystemMetadata;
            Editable = false;
            Tooltip = 'The error the test failed with, as returned by GetLastErrorText.';
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
        key(Outcome; Outcome) { }
    }

    /// <summary>
    /// Counts the logged results with the given outcome, leaving the caller's filters untouched.
    /// </summary>
    procedure CountByOutcome(TestOutcome: Enum "BAASIT Test Outcome"): Integer
    var
        TestResult: Record "BAASIT Test Result";
    begin
        TestResult.SetRange(Outcome, TestOutcome);
        exit(TestResult.Count());
    end;
}
