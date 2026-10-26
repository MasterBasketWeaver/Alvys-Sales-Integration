page 89960 "BAASIT Alvys Sales Setup API"
{
    // Reads and edits the Alvys Sales Setup without the web client:
    //
    //   GET   .../api/bryana/alvys/v1.0/companies({companyId})/alvysSalesSetups
    //   PATCH .../api/bryana/alvys/v1.0/companies({companyId})/alvysSalesSetups({id})
    //   POST  .../api/bryana/alvys/v1.0/companies({companyId})/alvysSalesSetups({id})/Microsoft.NAV.refreshAccessToken
    //
    // clientSecret is write-only: it always reads back blank, clientSecretSet says whether one is
    // stored, and a blank value in a PATCH leaves the stored secret alone.

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysSalesSetup';
    EntitySetName = 'alvysSalesSetups';
    SourceTable = "BAASI Alvys Sales Setup";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Sales Setup';
    DelayedInsert = true;
    InsertAllowed = true;
    ModifyAllowed = true;
    DeleteAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId)
                {
                    Editable = false;
                }
                field(enabled; Rec.Enabled) { }
                field(integrationUrl; Rec."Integration URL") { }
                field(clientId; Rec."Client ID") { }
                field(clientSecret; ClientSecretTxt)
                {
                    trigger OnValidate()
                    begin
                        if ClientSecretTxt <> '' then
                            Rec.Validate("Client Secret", ClientSecretTxt);
                    end;
                }
                field(clientSecretSet; ClientSecretSet)
                {
                    Editable = false;
                }
                field(driverCodeDimension; Rec."Driver Code Dimension") { }
                field(paymentJournalTemplate; Rec."Payment Journal Template") { }
                field(paymentJournalBatch; Rec."Payment Journal Batch") { }
                field(balAccountNo; Rec."Bal. Account No.") { }
                field(autoPostDeductions; Rec."Auto-Post Deductions") { }
                field(accessTokenExpiryDate; Rec."Access Token Expiry Date")
                {
                    Editable = false;
                }
                field(systemModifiedAt; Rec.SystemModifiedAt)
                {
                    Editable = false;
                }
            }
        }
    }

    trigger OnAfterGetRecord()
    begin
        ClientSecretTxt := '';
        ClientSecretSet := Rec."Client Secret" <> '';
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    begin
        Rec."Primary Key" := '';
    end;

    /// <summary>
    /// Same as the setup card's Refresh Access Token action.
    /// </summary>
    [ServiceEnabled]
    procedure refreshAccessToken(var ActionContext: WebServiceActionContext)
    var
        AlvysSalesSetup: Record "BAASI Alvys Sales Setup";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
    begin
        AlvysSalesSetup.Get();
        AlvysSalesSetup.TestField("Integration URL");
        AlvysSalesSetup.TestField("Client ID");
        AlvysSalesSetup.TestField("Client Secret");
        AlvysSalesMgt.GetBearerToken(AlvysSalesSetup);

        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"BAASIT Alvys Sales Setup API");
        ActionContext.AddEntityKey(AlvysSalesSetup.FieldNo(SystemId), AlvysSalesSetup.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;

    var
        ClientSecretTxt: Text[250];
        ClientSecretSet: Boolean;
}
