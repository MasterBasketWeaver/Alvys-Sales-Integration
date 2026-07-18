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
                field("Client ID"; Rec."Client ID")
                {
                    ShowMandatory = true;
                }
                field("Client Secret"; Rec."Client Secret")
                {
                    ShowMandatory = true;
                }
                field("Tractor Code Dimension"; Rec."Tractor Code Dimension")
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

            // TEMP: manual test harness for the deduction endpoints. Remove before release.
            action("Test Create Driver Deduction")
            {
                ApplicationArea = All;
                Caption = 'TEMP: Test Create Driver Deduction';
                ToolTip = 'Temporary test action. Creates a one-time deduction in Alvys against a hardcoded test driver.';
                Image = NewDocument;

                trigger OnAction()
                var
                    AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
                begin
                    // Amount must be negative and greater than 1.00 in absolute value.
                    LastDriverDeductionID := AlvysSalesMgt.CreateDeductionForDriver('DR2516397705002552078', WorkDate(), -25.0, 'Drug Test', 'BC test driver deduction');
                    Message(DeductionCreatedMsg, LastDriverDeductionID);
                end;
            }

            action("Test Get Driver Deduction")
            {
                ApplicationArea = All;
                Caption = 'TEMP: Test Get Driver Deduction';
                ToolTip = 'Temporary test action. Reads back the deduction created by the driver test action above.';
                Image = View;

                trigger OnAction()
                begin
                    TestGetDeduction(LastDriverDeductionID, 'DR2516397705002552078', true);
                end;
            }

            action("Test Create Truck Deduction")
            {
                ApplicationArea = All;
                Caption = 'TEMP: Test Create Truck Deduction';
                ToolTip = 'Temporary test action. Creates a one-time deduction in Alvys against a hardcoded test truck.';
                Image = NewDocument;

                trigger OnAction()
                var
                    AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
                begin
                    // Amount must be negative and greater than 1.00 in absolute value.
                    LastTruckDeductionID := AlvysSalesMgt.CreateDeductionForTruck('TR2516627931370728085', WorkDate(), -35.0, 'Drug Test', 'BC test truck deduction');
                    Message(DeductionCreatedMsg, LastTruckDeductionID);
                end;
            }

            action("Test Get Truck Deduction")
            {
                ApplicationArea = All;
                Caption = 'TEMP: Test Get Truck Deduction';
                ToolTip = 'Temporary test action. Reads back the deduction created by the truck test action above.';
                Image = View;

                trigger OnAction()
                begin
                    TestGetDeduction(LastTruckDeductionID, 'TR2516627931370728085', false);
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
                actionref("Test Create Driver Deduction_Promoted"; "Test Create Driver Deduction")
                {
                }
                actionref("Test Get Driver Deduction_Promoted"; "Test Get Driver Deduction")
                {
                }
                actionref("Test Create Truck Deduction_Promoted"; "Test Create Truck Deduction")
                {
                }
                actionref("Test Get Truck Deduction_Promoted"; "Test Get Truck Deduction")
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

    /// <summary>
    /// TEMP: shared body of the two read-back test actions. Falls back to the newest logged
    /// deduction for the asset, so the action still works in a fresh session where nothing
    /// was created yet.
    /// </summary>
    local procedure TestGetDeduction(LastDeductionID: Text; AssetID: Text; IsDriver: Boolean)
    var
        AlvysDeduction: Record "BAASI Alvys Deduction";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        ResponseObj: JsonObject;
        DeductionID, ResponseText : Text;
    begin
        DeductionID := LastDeductionID;
        if DeductionID = '' then begin
            if IsDriver then
                AlvysDeduction.SetRange("Driver Id", AssetID)
            else
                AlvysDeduction.SetRange("Truck Id", AssetID);
            if AlvysDeduction.FindLast() then
                DeductionID := AlvysDeduction.Id;
        end;
        if DeductionID = '' then
            Error(NoTestDeductionErr);
        ResponseObj := AlvysSalesMgt.GetDeduction(DeductionID);
        ResponseObj.WriteTo(ResponseText);
        Message(DeductionFetchedMsg, DeductionID, ResponseText);
    end;

    var
        AccessTokenTxt: Text;
        LastDriverDeductionID: Text;
        LastTruckDeductionID: Text;
        DeductionCreatedMsg: Label 'Created deduction %1.', Comment = '%1 = Deduction Id';
        DeductionFetchedMsg: Label 'Deduction %1:\%2', Comment = '%1 = Deduction Id, %2 = Response Text';
        NoTestDeductionErr: Label 'No test deduction is available. Run the create test action first.';
}
