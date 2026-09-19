page 89958 "BAASIT Alvys E2E Stmt Case API"
{
    // The cases the statement-date chain's seed phase raised, and what the poll phase found.
    //
    //   GET .../api/bryana/alvys/v1.0/companies({companyId})/alvysE2eStmtCases

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysE2eStmtCase';
    EntitySetName = 'alvysE2eStmtCases';
    SourceTable = "BAASIT E2E Stmt Case";
    ODataKeyFields = SystemId;
    Caption = 'Alvys E2E Statement Case';
    DelayedInsert = true;
    Editable = false;
    InsertAllowed = false;
    DeleteAllowed = false;
    ModifyAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { }
                field(caseCode; Rec."Case Code") { }
                field(repairOrderId; Rec."Repair Order Id") { }
                field(postedInvoiceNo; Rec."Posted Invoice No.") { }
                field(invoicePostingDate; Rec."Invoice Posting Date") { }
                field(deductionId; Rec."Deduction Id") { }
                field(groupId; Rec."Group Id") { }
                field(description; Rec.Description) { }
                field(amount; Rec.Amount) { }
                field(truckNumber; Rec."Truck Number") { }
                field(ownerOperatorId; Rec."Owner Operator Id") { }
                field(invoiceClosed; Rec."Invoice Closed") { }
                field(invoiceClosedAt; Rec."Invoice Closed At") { }
                field(fleetrockPaidDate; Rec."Fleetrock Paid Date") { }
            }
        }
    }
}
