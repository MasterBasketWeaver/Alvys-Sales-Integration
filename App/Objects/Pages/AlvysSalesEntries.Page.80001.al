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
                field("Created At"; Rec.SystemCreatedAt) { }
                field("Created By"; Rec."Created By") { }
                field(Direction; Rec.Direction) { }
                field("Document Type"; Rec."Document Type") { }
                field("Document No."; Rec."Document No.")
                {
                    trigger OnDrillDown()
                    var
                        SalesHeader: Record "Sales Header";
                        SalesInvHeader: Record "Sales Invoice Header";
                    begin
                        Case Rec."Document Type" of
                            Rec."Document Type"::"Posted Sales Invoice":
                                if SalesInvHeader.Get(Rec."Document No.") then
                                    Page.Run(Page::"Posted Sales Invoice", SalesInvHeader);
                            Rec."Document Type"::"Sales Invoice":
                                if SalesHeader.Get(Enum::"Sales Document Type"::Invoice, Rec."Document No.") then
                                    Page.Run(Page::"Sales Invoice", SalesHeader);
                            Rec."Document Type"::"Sales Order":
                                if SalesHeader.Get(Enum::"Sales Document Type"::Order, Rec."Document No.") then
                                    Page.Run(Page::"Sales Order", SalesHeader);
                        End;
                    end;
                }
                field(Method; Rec.Method) { }
                field(URL; Rec.URL) { }
                field("Request Body"; Rec.GetRequestBody())
                {
                    Editable = false;
                }
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
                Enabled = HasRequestBody;

                trigger OnAction()
                begin
                    Message(Rec.GetRequestBody());
                end;
            }
            action("Show Response")
            {
                ApplicationArea = All;
                ToolTip = 'Shows the response that was received from Alvys.';
                Image = ViewDetails;
                Enabled = Rec.Response <> '';

                trigger OnAction()
                begin
                    Message(Rec.Response);
                end;
            }
            action("Show Error")
            {
                ApplicationArea = All;
                ToolTip = 'Shows the error message and error stack for the entry.';
                Image = ErrorLog;
                Enabled = Rec."Error Message" <> '';

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

                actionref("Show Request Body_Promoted"; "Show Request Body") { }
                actionref("Show Response_Promoted"; "Show Response") { }
                actionref("Show Error_Promoted"; "Show Error") { }
            }
        }
    }

    trigger OnAfterGetCurrRecord()
    begin
        HasRequestBody := Rec.GetRequestBody() <> '';
    end;

    var
        HasRequestBody: Boolean;
}
