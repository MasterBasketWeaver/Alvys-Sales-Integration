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
        }

        area(Promoted)
        {
            group(Category_Process)
            {
                Caption = 'Process';

                actionref("Refresh Access Token_Promoted"; "Refresh Access Token")
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
