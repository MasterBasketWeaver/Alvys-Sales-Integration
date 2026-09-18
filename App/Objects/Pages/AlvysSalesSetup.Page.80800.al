page 80800 "BAASI Alvys Sales Setup"
{
    SourceTable = "BAASI Alvys Sales Setup";
    ApplicationArea = all;
    UsageCategory = Administration;
    Caption = 'Alvys Sales Setup';


    layout
    {
        area(Content)
        {
            group(Options)
            {
                field(Enabled; Rec.Enabled) { }
                Group(Dimensions)
                {
                    // field("Entity Code Dimension"; Rec."Entity Code Dimension")
                    // {
                    //     ShowMandatory = true;
                    // }
                    field("Tractor Code Dimension"; Rec."Tractor Code Dimension")
                    {
                        ShowMandatory = true;
                    }
                }
                group("Payment Journal")
                {
                    field("Payment Journal Template"; Rec."Payment Journal Template")
                    {
                        ShowMandatory = true;
                    }
                    field("Payment Journal Batch"; Rec."Payment Journal Batch")
                    {
                        ShowMandatory = true;
                    }
                    field("Bal. Account No."; Rec."Bal. Account No.")
                    {
                        ShowMandatory = true;
                    }
                    field("Auto-Post Deductions"; Rec."Auto-Post Deductions") { }
                }
                group(Integration)
                {

                    field("Integration URL"; Rec."Integration URL")
                    {
                        ShowMandatory = true;
                    }
                    field("Client ID"; Rec."Client ID")
                    {
                        ShowMandatory = true;
                    }
                    field("Client Secret"; Rec."Client Secret")
                    {
                        ShowMandatory = true;
                    }

                    group(Token)
                    {
                        field("Access Token"; AccessTokenTxt)
                        {
                            Caption = 'Access Token';
                            ToolTip = 'The access token used to authenticate requests to the Alvys API.';
                            Editable = false;
                            ExtendedDatatype = Masked;
                        }
                        field("Access Token Expiry Date"; Rec."Access Token Expiry Date")
                        {
                            Editable = false;
                        }
                    }
                }

            }
        }
    }

    actions
    {
        area(Processing)
        {
            action("Refresh Access Token")
            {
                ApplicationArea = All;
                ToolTip = 'Gets a new access token from Alvys and saves it to the setup.';
                Image = Refresh;

                trigger OnAction()
                var
                    AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
                begin
                    Rec.TestField("Integration URL");
                    Rec.TestField("Client ID");
                    Rec.TestField("Client Secret");
                    AlvysSalesMgt.GetBearerToken(Rec);
                    CurrPage.Update(false);
                end;
            }

            action("Poll Settled Deductions")
            {
                ApplicationArea = All;
                ToolTip = 'Asks Alvys which outstanding deductions have been settled, and writes the settlements to the payment journal. This normally runs on a schedule; use this to run it now.';
                Image = Payment;

                trigger OnAction()
                var
                    AlvysSettlementPoll: Codeunit "BAASI Alvys Settlement Poll";
                begin
                    AlvysSettlementPoll.PollSettledDeductions();
                end;
            }
        }

        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref("Refresh Access Token_Promoted"; "Refresh Access Token")
                {
                }
                actionref("Poll Settled Deductions_Promoted"; "Poll Settled Deductions")
                {
                }
            }
        }
    }


    trigger OnOpenPage()
    begin
        if not Rec.Get() then begin
            Rec.Init();
            Rec.Insert(true);
        end;
    end;

    trigger OnAfterGetCurrRecord()
    begin
        AccessTokenTxt := Rec.GetAccessToken();
    end;

    var
        AccessTokenTxt: Text;
}
