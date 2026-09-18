page 89956 "BAASIT Alvys E2E API"
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
                field(autoPostRepairOrders; Rec."Auto-Post Repair Orders") { }
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
        RunPhase(Enum::"BAASIT E2E Phase"::Seed, Enum::"BAASIT E2E Poll Mode"::Manual, false, true);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Phase one with Fleetrock auto-posting the imported invoice, for a chain that will be finished
    /// by a manual poll.
    /// </summary>
    [ServiceEnabled]
    procedure seedManualAutoPost(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Seed, Enum::"BAASIT E2E Poll Mode"::Manual, true, true);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Phase one, for a chain that will be finished by a job queue poll.
    /// </summary>
    [ServiceEnabled]
    procedure seedJobQueue(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Seed, Enum::"BAASIT E2E Poll Mode"::"Job Queue", false, true);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Phase one with Fleetrock auto-posting the imported invoice, for a chain that will be finished
    /// by a job queue poll.
    /// </summary>
    [ServiceEnabled]
    procedure seedJobQueueAutoPost(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Seed, Enum::"BAASIT E2E Poll Mode"::"Job Queue", true, true);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Phase two, once the deduction has been settled in the Alvys web UI. The poll mode is the one
    /// the chain was seeded for, so it is not passed again here.
    /// </summary>
    [ServiceEnabled]
    procedure poll(var ActionContext: WebServiceActionContext)
    begin
        RunPhase(Enum::"BAASIT E2E Phase"::Poll, Rec."Poll Mode", Rec."Auto-Post Repair Orders", false);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Creates one busy repair order in Fleetrock -- eight tasks of three parts each -- imports it
    /// and posts it, for looking at in Business Central rather than for a test. What it produced is
    /// read back off the entity, so it lands in the same fields a seeded chain uses.
    /// </summary>
    [ServiceEnabled]
    procedure seedDetailedRepairOrder(var ActionContext: WebServiceActionContext)
    var
        DetailedRepairOrder: Codeunit "BAASIT Detailed Repair Order";
        ROId: Text;
        InvoiceNo, PostedInvoiceNo : Code[20];
    begin
        DetailedRepairOrder.Create(8, 3, ROId, InvoiceNo, PostedInvoiceNo);
        RecordDetailedRepairOrder(ROId, InvoiceNo, PostedInvoiceNo);
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// The same, for a named Fleetrock unit number and a chosen number of tasks and parts per task,
    /// so a repair order can be produced for whichever truck is being looked at.
    /// </summary>
    [ServiceEnabled]
    procedure seedDetailedRepairOrderForUnit(unitNumber: Text[50]; taskCount: Integer; partsPerTask: Integer; var ActionContext: WebServiceActionContext)
    var
        DetailedRepairOrder: Codeunit "BAASIT Detailed Repair Order";
        ROId: Text;
        InvoiceNo, PostedInvoiceNo : Code[20];
    begin
        DetailedRepairOrder.Create(unitNumber, taskCount, partsPerTask, ROId, InvoiceNo, PostedInvoiceNo);
        RecordDetailedRepairOrder(ROId, InvoiceNo, PostedInvoiceNo);
        SetActionContext(ActionContext);
    end;

    local procedure RecordDetailedRepairOrder(ROId: Text; InvoiceNo: Code[20]; PostedInvoiceNo: Code[20])
    var
        E2ERun: Record "BAASIT E2E Run";
    begin
        E2ERun.GetSingleton();
        E2ERun."Repair Order Id" := CopyStr(ROId, 1, MaxStrLen(E2ERun."Repair Order Id"));
        E2ERun."Sales Invoice No." := InvoiceNo;
        E2ERun."Posted Invoice No." := PostedInvoiceNo;
        E2ERun."Seeded At" := CurrentDateTime();
        E2ERun.Modify();
        Commit();

        Rec.GetSingleton();
    end;

    /// <summary>
    /// Runs the settlement poll the way the job queue runs it -- through the codeunit's OnRun, so
    /// ScheduledRun is set and a deduction that fails is logged rather than taking the run down.
    /// The setup page's own action calls PollSettledDeductions directly instead, which is the
    /// by-hand path, so this is the one to use when the scheduled behaviour is what is being
    /// checked.
    /// </summary>
    [ServiceEnabled]
    procedure runSettlementPollAsJobQueue(var ActionContext: WebServiceActionContext)
    begin
        if not Codeunit.Run(Codeunit::"BAASI Alvys Settlement Poll") then
            Error(PollFailedErr, GetLastErrorText());
        Commit();
        Rec.GetSingleton();
        SetActionContext(ActionContext);
    end;

    /// <summary>
    /// Unpicks split parts logged against a deduction they never belonged to. A part of a split carries the Group Id of the deduction it came from, so
    /// a logged part whose Group Id is not the parent's was never in that group -- which is what a
    /// poll before the grouping fix produced, attaching everything the deduction search returned to
    /// one split deduction. Each of those rows is the only record Business Central has of a
    /// deduction it never raised, so removing it puts the deduction back to untracked.
    ///
    /// The parent is then recomputed from the parts it really has. Nothing else is touched: the
    /// journal lines and postings those rows produced stay, and so does every Alvys sales entry.
    /// </summary>
    [ServiceEnabled]
    procedure undoMislinkedSplitParts(var ActionContext: WebServiceActionContext)
    var
        SplitDeduction, SplitPart : Record "BAASI Alvys Deduction";
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        MislinkedPartEntryNos, SurvivingPartEntryNos : List of [Integer];
        EntryNo: Integer;
    begin
        SplitPart.SetFilter("Split From Entry No.", '<>%1', 0);
        if SplitPart.FindSet() then
            repeat
                if SplitDeduction.Get(SplitPart."Split From Entry No.") then
                    if SplitDeduction."Group Id" <> SplitPart."Group Id" then
                        MislinkedPartEntryNos.Add(SplitPart."Entry No.")
                    else
                        if not SurvivingPartEntryNos.Contains(SplitPart."Entry No.") then
                            SurvivingPartEntryNos.Add(SplitPart."Entry No.");
            until SplitPart.Next() = 0;

        foreach EntryNo in MislinkedPartEntryNos do
            if SplitPart.Get(EntryNo) then
                SplitPart.Delete(true);

        foreach EntryNo in SurvivingPartEntryNos do
            AlvysSalesMgt.UpdateSplitDeduction(EntryNo);
        Commit();

        Rec.GetSingleton();
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
        E2ERun.Reset(E2ERun."Poll Mode", E2ERun."Auto-Post Repair Orders");

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

    /// <summary>
    /// Resumes the job queues a chain held, for a chain that stopped before its poll phase could
    /// resume them.
    /// </summary>
    [ServiceEnabled]
    procedure resumeJobQueues(var ActionContext: WebServiceActionContext)
    var
        JobQueueHold: Codeunit "BAASIT Job Queue Hold";
    begin
        JobQueueHold.ResumeJobQueues();
        Rec.GetSingleton();
        SetActionContext(ActionContext);
    end;

    local procedure RunPhase(Phase: Enum "BAASIT E2E Phase"; PollMode: Enum "BAASIT E2E Poll Mode"; AutoPostRepairOrders: Boolean; ResetRun: Boolean)
    var
        E2ERun: Record "BAASIT E2E Run";
        TestRunMgt: Codeunit "BAASIT Test Run Mgt.";
    begin
        E2ERun.GetSingleton();
        if ResetRun then
            E2ERun.Reset(PollMode, AutoPostRepairOrders);
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

    var
        PollFailedErr: Label 'The settlement poll failed: %1', Comment = '%1 = the error text';
}
