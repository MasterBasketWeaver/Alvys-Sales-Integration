page 80856 "BAASIT Alvys E2E API"
{
    // Drives one phase of the chained end-to-end run and reads back what it produced.
    //
    //   POST .../api/bryana/alvys/v1.0/companies({companyId})/alvysE2eRuns({id})/Microsoft.NAV.seed
    //   POST .../api/bryana/alvys/v1.0/companies({companyId})/alvysE2eRuns({id})/Microsoft.NAV.poll
    //
    // Two calls rather than one run, because the deduction the seed phase creates has to be settled
    // in the Alvys web UI in between, and Alvys exposes no way to do that over its API. Script
    // tools/alvys-e2e.py calls seed, settles the deduction in the browser, then calls poll.
    //
    // Reading the entity back between calls is how the settlement step learns which deduction to
    // go and settle.

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysE2eRun';
    EntitySetName = 'alvysE2eRuns';
    SourceTable = "BAASIT E2E Run";
    ODataKeyFields = SystemId;
    Caption = 'Alvys E2E Run';
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
                field(pollMode; Rec."Poll Mode") { }
                field(repairOrderId; Rec."Repair Order Id") { }
                field(salesInvoiceNo; Rec."Sales Invoice No.") { }
                field(postedInvoiceNo; Rec."Posted Invoice No.") { }
                field(deductionId; Rec."Deduction Id") { }
                field(deductionEntryNo; Rec."Deduction Entry No.") { }
                field(truckId; Rec."Truck Id") { }
                field(truckNumber; Rec."Truck Number") { }
                field(amount; Rec.Amount) { }
                field(customerNo; Rec."Customer No.") { }
                field(seededAt; Rec."Seeded At") { }
                field(polledAt; Rec."Polled At") { }
                field(invoiceRemainingAmount; Rec."Invoice Remaining Amount") { }
                field(invoiceClosed; Rec."Invoice Closed") { }
            }
        }
    }

    /// <summary>
    /// Phase one, for a chain that will be finished by a manual poll.
    /// </summary>
    [ServiceEnabled]
    procedure seedManual(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Seed, Enum::"BAASIT E2E Poll Mode"::Manual, true);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Phase one, for a chain that will be finished by a job queue poll.
    /// </summary>
    [ServiceEnabled]
    procedure seedJobQueue(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Seed, Enum::"BAASIT E2E Poll Mode"::"Job Queue", true);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Phase two, once the deduction has been settled in the Alvys web UI. The poll mode is the one
    /// the chain was seeded for, so it is not passed again here.
    /// </summary>
    [ServiceEnabled]
    procedure poll(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Poll, Rec."Poll Mode", false);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Clears what earlier chains left behind so a fresh one starts clean: the run singleton, and
    /// the settlement lines sitting unposted in the Alvys payment journal.
    ///
    /// A chain that fails after the poll has applied its settlement cannot simply be run again --
    /// the deduction is already marked applied and the poll will not touch it twice, and its line
    /// stays in the batch where the next run's posting would pick it up. Emptying the batch is
    /// scoped to the one the Alvys setup names, which exists for these settlements and nothing
    /// else, and this lives in the test app because the shipping app has no business deleting a
    /// journal someone may be part way through.
    /// </summary>
    [ServiceEnabled]
    procedure resetChain(var ActionContext: WebServiceActionContext)
    var
        AlvysSalesSetup: Record "BAASI Alvys Sales Setup";
        E2ERun: Record "BAASIT E2E Run";
        GenJnlLine: Record "Gen. Journal Line";
    begin
        E2ERun.GetSingleton();
        E2ERun.Reset(E2ERun."Poll Mode");

        AlvysSalesSetup.Get();
        if (AlvysSalesSetup."Payment Journal Template" <> '') and (AlvysSalesSetup."Payment Journal Batch" <> '') then begin
            GenJnlLine.SetRange("Journal Template Name", AlvysSalesSetup."Payment Journal Template");
            GenJnlLine.SetRange("Journal Batch Name", AlvysSalesSetup."Payment Journal Batch");
            GenJnlLine.DeleteAll(true);
        end;
        Commit();

        Rec.GetSingleton();
        SetActionContext(ActionContext);
    end;

    local procedure RunPhase(Phase: Enum "BAASIT E2E Phase"; PollMode: Enum "BAASIT E2E Poll Mode"; ResetRun: Boolean)
    var
        E2ERun: Record "BAASIT E2E Run";
        TestRunMgt: Codeunit "BAASIT Test Run Mgt.";
    begin
        E2ERun.GetSingleton();
        if ResetRun then
            E2ERun.Reset(PollMode);
        TestRunMgt.RunE2EPhase(Phase);
        Rec.GetSingleton();
    end;

    local procedure SetActionContext(var ActionContext: WebServiceActionContext)
    begin
        ActionContext.SetObjectType(ObjectType::Page);
        ActionContext.SetObjectId(Page::"BAASIT Alvys E2E API");
        ActionContext.AddEntityKey(Rec.FieldNo(SystemId), Rec.SystemId);
        ActionContext.SetResultCode(WebServiceActionResultCode::Updated);
    end;

    trigger OnOpenPage()
    begin
        Rec.GetSingleton();
    end;
}
