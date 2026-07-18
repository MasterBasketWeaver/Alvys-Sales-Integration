page 80801 "BAASI Alvys Sales Entries"
{
    SourceTable = "BAASI Alvys Sales Entry";
    ApplicationArea = all;
    UsageCategory = Administration;
    Caption = 'Alvys Sales Entries';
    Editable = false;
    LinksAllowed = false;
    AnalysisModeEnabled = false;
    PageType = List;
    SourceTableView = sorting("Entry No.") order(descending);

    layout
    {
        area(Content)
        {
            repeater(Entries)
            {
                field("Entry No."; Rec."Entry No.") { }
                field("User ID"; Rec."User ID") { }
                field("Document Type"; Rec."Document Type") { }
                field("Document No."; Rec."Document No.") { }
                field(Method; Rec.Method) { }
                field(URL; Rec.URL) { }
                field(Response; Rec.Response) { }
                field("Error Message"; Rec."Error Message")
                {
                    trigger OnDrillDown()
                    begin
                        Rec.DisplayErrorMessage();
                    end;
                }
            }
        }
    }

    actions
    {
        area(Processing)
        {
            action("Show Request Body")
            {
                ApplicationArea = All;
                ToolTip = 'Shows the request body that was sent to Alvys.';
                Image = ViewDetails;

                trigger OnAction()
                begin
                    Rec.DisplayRequestBody();
                end;
            }
            action("Show Error")
            {
                ApplicationArea = All;
                ToolTip = 'Shows the error message and error stack for the entry.';
                Image = ErrorLog;

                trigger OnAction()
                begin
                    Rec.DisplayErrorMessage();
                end;
            }
        }

        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref("Show Request Body_Promoted"; "Show Request Body")
                {
                }
                actionref("Show Error_Promoted"; "Show Error")
                {
                }
            }
        }
    }
}
