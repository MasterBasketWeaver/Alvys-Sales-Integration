page 80803 "BAASI Alvys Apply Ded. API"
{
    // Receives the driver pay event Alvys fires once a settlement is processed, so the deduction
    // pushed out of Business Central can be cleared against the open receivable.
    //
    //   POST .../api/tanager/alvys/v1.0/companies({companyId})/alvysApplyDeductions
    //
    // Custom API pages are exposed automatically, so this needs no web service registration.
    //
    // The page takes the six driver pay fields and nothing else. They are page variables rather
    // than table fields: the entry table logs the call, it does not store the payload field by
    // field. Everything the entry needs beyond them — the document, the request body, the method
    // and URL — is derived in PrepareApplyDeductionEntry.
    //
    // A payload that names no truck, applies nothing, or carries no settlement date is refused the
    // same way one that cannot be matched to an invoice is: the entry is logged, and the call is
    // answered 400 with the reason. The checks live with the matching in PrepareApplyDeductionEntry,
    // so the log is written on every path.
    //
    // Generating the payment journal from the matched invoice is a separate step, still blocked on
    // the offset G/L account.

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
                // The payload Alvys posts. Each one is bound to a page variable, so setting it
                // leaves the record untouched as far as the framework is concerned and the delayed
                // insert never fires. Stamping the direction marks the record dirty, so a call that
                // sends any single field is still persisted rather than answered 201 and dropped.
                field(deductionId; DeductionIdTxt)
                {
                    Caption = 'Deduction Id';

                    trigger OnValidate()
                    begin
                        MarkDirty();
                    end;
                }
                field(truckId; TruckIdTxt)
                {
                    Caption = 'Truck Id';

                    trigger OnValidate()
                    begin
                        MarkDirty();
                    end;
                }
                field(truckNumber; TruckNumberTxt)
                {
                    Caption = 'Truck Number';

                    trigger OnValidate()
                    begin
                        MarkDirty();
                    end;
                }
                field(amount; AmountDec)
                {
                    Caption = 'Amount';

                    trigger OnValidate()
                    begin
                        MarkDirty();
                    end;
                }
                field(settlementDate; SettlementDateVar)
                {
                    Caption = 'Settlement Date';

                    trigger OnValidate()
                    begin
                        MarkDirty();
                    end;
                }
                field(description; DescriptionTxt)
                {
                    Caption = 'Description';

                    trigger OnValidate()
                    begin
                        MarkDirty();
                    end;
                }
                // Read back only. These say what Business Central made of the payload: which posted
                // invoice the deduction was matched to, and why it could not be matched.
                field(direction; Rec.Direction)
                {
                    Editable = false;
                }
                field(documentType; Rec."Document Type")
                {
                    Editable = false;
                }
                field(documentNo; Rec."Document No.")
                {
                    Editable = false;
                }
                field(errorMessage; Rec."Error Message")
                {
                    Editable = false;
                }
                field(systemCreatedAt; Rec.SystemCreatedAt)
                {
                    Editable = false;
                }
            }
        }
    }

    var
        DeductionIdTxt: Text;
        TruckIdTxt: Text;
        TruckNumberTxt: Text;
        DescriptionTxt: Text;
        AmountDec: Decimal;
        SettlementDateVar: Date;

    /// <summary>
    /// Marks the record dirty so DelayedInsert fires. See the comment on the payload fields.
    /// </summary>
    local procedure MarkDirty()
    begin
        Rec.Direction := Rec.Direction::Inbound;
    end;

    trigger OnAfterGetRecord()
    var
        JsonMgt: Codeunit "BAAPI Json Mgt.";
        RequestBody: JsonObject;
    begin
        // The payload is stored on the entry as the body it arrived as, so reading a row back has
        // to take it apart again.
        Clear(DeductionIdTxt);
        Clear(TruckIdTxt);
        Clear(TruckNumberTxt);
        Clear(DescriptionTxt);
        Clear(AmountDec);
        Clear(SettlementDateVar);
        if not RequestBody.ReadFrom(Rec.GetRequestBody()) then
            exit;
        DeductionIdTxt := JsonMgt.GetJsonValueAsText(RequestBody, 'DeductionId');
        TruckIdTxt := JsonMgt.GetJsonValueAsText(RequestBody, 'TruckId');
        TruckNumberTxt := JsonMgt.GetJsonValueAsText(RequestBody, 'TruckNumber');
        DescriptionTxt := JsonMgt.GetJsonValueAsText(RequestBody, 'Description');
        AmountDec := JsonMgt.GetJsonValueAsDecimal(RequestBody, 'Amount');
        // The shared Json codeunit has no date getter, and the body carries the date the way the
        // JSON writer emitted it, so read it back in the same XML format.
        if not Evaluate(SettlementDateVar, JsonMgt.GetJsonValueAsText(RequestBody, 'SettlementDate'), 9) then
            Clear(SettlementDateVar);
    end;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
    begin
        AlvysSalesMgt.PrepareApplyDeductionEntry(Rec, DeductionIdTxt, TruckIdTxt, TruckNumberTxt, AmountDec, SettlementDateVar, DescriptionTxt);

        // The entry is written whichever way the call is answered: the log is the record of what
        // Alvys sent, and a call that failed is the one most worth having. Inserting here rather
        // than leaving it to the framework keeps every path identical up to this point.
        Rec.Insert(true);

        // A settlement that matched is the only call answered 201. Every failure is refused, with
        // the reason it could not be applied as the error text.
        if Rec."Error Message" = '' then
            exit(false);

        // The error rolls the transaction back and would take the entry above with it, so it is
        // committed first. Every failure path passes through here, so this guards the whole log;
        // the success path above commits with the framework's own transaction once this returns.
        Commit();
        Error(Rec."Error Message");
    end;
}
