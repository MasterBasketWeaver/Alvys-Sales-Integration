page 89959 "BAASIT Alvys E2E Stmt Leaf API"
{
    // The parts Alvys paid in the statement-date chain. The driving script posts one per part with
    // the statement Alvys says paid it; the poll phase fills in what Business Central did with it.
    //
    //   POST .../api/bryana/alvys/v1.0/companies({companyId})/alvysE2eStmtLeaves
    //   GET  .../api/bryana/alvys/v1.0/companies({companyId})/alvysE2eStmtLeaves

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysE2eStmtLeaf';
    EntitySetName = 'alvysE2eStmtLeaves';
    SourceTable = "BAASIT E2E Stmt Leaf";
    ODataKeyFields = SystemId;
    Caption = 'Alvys E2E Statement Leaf';
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
                field(id; Rec.SystemId) { Editable = false; }
                field(caseCode; Rec."Case Code") { }
                field(description; Rec.Description) { }
                field(amount; Rec.Amount) { }
                field(expectedStatementNo; Rec."Expected Statement No.") { }
                field(expectedStatementDate; Rec."Expected Statement Date") { }
                field(statementNo; Rec."Statement No.") { Editable = false; }
                field(statementDate; Rec."Statement Date") { Editable = false; }
                field(paymentPostingDate; Rec."Payment Posting Date") { Editable = false; }
                field(paymentPosted; Rec."Payment Posted") { Editable = false; }
            }
        }
    }
}
