page 80851 "BAASIT Alvys Test Results"
{
    SourceTable = "BAASIT Test Result";
    ApplicationArea = All;
    UsageCategory = Lists;
    Caption = 'Alvys Test Results';
    Editable = false;
    InsertAllowed = false;
    ModifyAllowed = false;
    LinksAllowed = false;
    AnalysisModeEnabled = false;
    PageType = List;

    layout
    {
        area(Content)
        {
            repeater(Results)
            {
                field("Codeunit Name"; Rec."Codeunit Name") { }
                field("Method Name"; Rec."Method Name") { }
                field(Outcome; Rec.Outcome)
                {
                    StyleExpr = this.OutcomeStyle;
                }
                field(Duration; Rec.Duration) { }
                field("Error Message"; Rec."Error Message") { }
                field("Start Time"; Rec."Start Time") { }
                field("Finish Time"; Rec."Finish Time") { }
                field("Codeunit ID"; Rec."Codeunit ID") { }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action(RunTests)
            {
                ApplicationArea = All;
                Caption = 'Run Tests';
                Tooltip = 'Clear the previous results and run every Alvys test codeunit through the test runner.';
                Image = ExecuteBatch;

                trigger OnAction()
                begin
                    this.RunTestSuite();
                end;
            }
            action(ClearResults)
            {
                ApplicationArea = All;
                Caption = 'Clear Results';
                Tooltip = 'Delete the logged results of previous test runs.';
                Image = ClearLog;

                trigger OnAction()
                begin
                    Rec.DeleteAll();
                    CurrPage.Update(false);
                end;
            }
        }
        area(Promoted)
        {
            actionref(RunTests_Promoted; RunTests) { }
            actionref(ClearResults_Promoted; ClearResults) { }
        }
    }

    trigger OnAfterGetRecord()
    begin
        if Rec.Outcome = Rec.Outcome::Failure then
            this.OutcomeStyle := 'Unfavorable'
        else
            this.OutcomeStyle := 'Favorable';
    end;

    /// <summary>
    /// Runs the suite through the shared run codeunit, so a run started here is identical to one
    /// triggered over the API, then reports the summary it recorded.
    /// </summary>
    local procedure RunTestSuite()
    var
        TestRun: Record "BAASIT Test Run";
        TestRunMgt: Codeunit "BAASIT Test Run Mgt.";
    begin
        TestRunMgt.RunSuite();
        TestRun.GetSingleton();

        CurrPage.Update(false);
        Message(this.RunFinishedMsg, TestRun."Tests Run", TestRun.Successful, TestRun.Failed);
    end;

    var
        OutcomeStyle: Text;
        RunFinishedMsg: Label 'The test run finished.\\Tests run: %1\Successful: %2\Failed: %3', Comment = '%1 = total number of tests, %2 = number of successful tests, %3 = number of failed tests';
}
