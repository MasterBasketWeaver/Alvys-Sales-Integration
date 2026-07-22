page 80803 "BAASI Alvys Apply Ded. API"
{
    // Receives the driver pay event Alvys fires once a settlement is processed, so the deduction
    // pushed out of Business Central can be cleared against the open receivable.
    //
    //   POST .../api/tanager/alvys/v1.0/companies({companyId})/alvysApplyDeductions
    //
    // Custom API pages are exposed automatically, so this needs no web service registration.
    // The call is logged to the same entry table the outbound calls use, as Direction Inbound.
    // Matching the payload to the sales invoice and generating the payment journal is a separate
    // step, still blocked on the offset G/L account.

    PageType = API;
    APIPublisher = 'tanager';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysApplyDeduction';
    EntitySetName = 'alvysApplyDeductions';
    SourceTable = "BAASI Alvys Sales Entry";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Apply Deduction';
    SourceTableView = where(Direction = const(Inbound));
    DelayedInsert = true;
    InsertAllowed = true;
    ModifyAllowed = false;
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
                field(entryNo; Rec."Entry No.")
                {
                    Editable = false;
                }
                field(direction; Rec.Direction)
                {
                    Editable = false;
                }
                // The entry fields are read-only on the table, since the outbound log is written by
                // code only. The inbound call has to be able to set them, hence the override.
                field(documentType; Rec."Document Type")
                {
                    Editable = true;
                }
                field(documentNo; Rec."Document No.")
                {
                    Editable = true;
                }
                field(url; Rec.URL)
                {
                    Editable = true;
                }
                field(method; Rec.Method)
                {
                    Editable = true;
                }
                field(requestBody; RequestBodyTxt)
                {
                    Caption = 'Request Body';
                }
                field(response; Rec.Response)
                {
                    Editable = true;
                }
                field(errorMessage; Rec."Error Message")
                {
                    Editable = true;
                }
                field(systemCreatedAt; Rec.SystemCreatedAt)
                {
                    Editable = false;
                }
            }
        }
    }

    var
        RequestBodyTxt: Text;

    trigger OnAfterGetRecord()
    begin
        RequestBodyTxt := Rec.GetRequestBody();
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
    begin
        AlvysSalesMgt.PrepareInboundEntry(Rec, RequestBodyTxt);
    end;
}
