table 89951 "BAASIT Test Result"
{
    Caption = 'Alvys Test Result';
    DataClassification = SystemMetadata;
    DrillDownPageId = "BAASIT Alvys Test Results";
    LookupPageId = "BAASIT Alvys Test Results";

    // Written from the OnAfterTestRun trigger of the test runners. That trigger runs in its own
    // transaction, so these rows survive the rollback that test isolation performs on everything the
    // tests themselves touched. The production build's runner writes them after each test's own
    // Codeunit.Run has rolled back, for the same reason.

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
        field(10; "Error Call Stack"; Text[2048])
        {
            DataClassification = SystemMetadata;
            Editable = false;
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
    /// Logs one test method's outcome, with the last error when it failed.
    /// </summary>
    procedure Log(CodeunitId: Integer; CodeunitName: Text; FunctionName: Text; StartTime: DateTime; Success: Boolean)
    begin
        Rec.Init();
        Rec."Entry No." := 0;
        Rec."Codeunit ID" := CodeunitId;
        Rec."Codeunit Name" := CopyStr(CodeunitName, 1, MaxStrLen(Rec."Codeunit Name"));
        Rec."Method Name" := CopyStr(FunctionName, 1, MaxStrLen(Rec."Method Name"));
        Rec."Start Time" := StartTime;
        Rec."Finish Time" := CurrentDateTime();
        Rec.Duration := Rec."Finish Time" - StartTime;
        if Success then
            Rec.Outcome := Rec.Outcome::Success
        else begin
            Rec.Outcome := Rec.Outcome::Failure;
            Rec."Error Message" := CopyStr(GetLastErrorText(), 1, MaxStrLen(Rec."Error Message"));
            Rec."Error Call Stack" := CopyStr(GetLastErrorCallStack(), 1, MaxStrLen(Rec."Error Call Stack"));
        end;
        Rec.Insert(true);
    end;

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
