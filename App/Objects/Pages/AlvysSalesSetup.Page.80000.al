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

            group(Integration)
            {
                field("Integration URL"; Rec."Integration URL")
                {
                    ShowMandatory = true;
                }

                group(Token)
                {
                    field("API Token"; Rec."API Token")
                    {
                        Visible = Rec."Use API Token";
                    }
                    field("API Token Expiry Date"; Rec."API Token Expiry Date")
                    {
                        Visible = Rec."Use API Token";
                    }
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
}