page 80855 "BAASIT Alvys Ded. Seed API"
{
    // Creates a deduction linked to a posted sales invoice, so the OData contract test has
    // something for the apply-deduction endpoint to match on.
    //
    //   POST   .../api/bryana/alvys/v1.0/companies({companyId})/alvysDeductionSeeds
    //   DELETE .../api/bryana/alvys/v1.0/companies({companyId})/alvysDeductionSeeds({id})
    //
    // The apply-deduction endpoint now refuses a payload it cannot match, so without a seeded
    // deduction every call the contract test can build comes back 400 and the success path goes
    // untested. The AL suite seeds its own and rolls it back; the contract test runs against the
    // live endpoint, so it needs an endpoint to do the same and deletes what it created.
    //
    // Test app only, deliberately. The shipping app has no business writing deductions that were
    // never sent to Alvys.

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysDeductionSeed';
    EntitySetName = 'alvysDeductionSeeds';
    SourceTable = "BAASI Alvys Deduction";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Deduction Seed';
    DelayedInsert = true;
    InsertAllowed = true;
    ModifyAllowed = false;
    DeleteAllowed = true;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { }
                field(entryNo; Rec."Entry No.")
                {
                    Editable = false;
                }
                // Read-only on the table, as the deduction log is written by code only.
                field(deductionId; Rec.Id)
                {
                    Editable = true;
                }
                field(postedDocumentNo; Rec."Posted Document No.")
                {
                    Editable = true;
                }
                // Seeds a deduction whose originating document has not been posted, which is the
                // one failure the apply-deduction endpoint treats as retryable. Defaults to false,
                // so a caller that says nothing gets a deduction linked to a posted invoice.
                field(unposted; UnpostedBool)
                {
                    Caption = 'Unposted';
                }
            }
        }
    }

    var
        UnpostedBool: Boolean;

    trigger OnInsertRecord(BelowxRec: Boolean): Boolean
    var
        LastDeduction: Record "BAASI Alvys Deduction";
        SalesInvHeader: Record "Sales Invoice Header";
    begin
        LastDeduction.LockTable(true);
        if LastDeduction.FindLast() then
            Rec."Entry No." := LastDeduction."Entry No." + 1
        else
            Rec."Entry No." := 1;

        // The caller has no way to choose a posted invoice, so a blank one takes the last invoice
        // in the company and hands it back in the response to assert against. Which invoice it is
        // does not matter: the contract test checks that the entry is pointed at the invoice the
        // deduction names, not at any particular document.
        if (Rec."Posted Document No." = '') and not UnpostedBool then begin
            SalesInvHeader.FindLast();
            Rec."Posted Document No." := SalesInvHeader."No.";
        end;
        Rec."Document Type" := Rec."Document Type"::"Sales Invoice";
    end;
}
