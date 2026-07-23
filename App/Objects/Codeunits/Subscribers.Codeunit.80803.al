codeunit 80803 "BAASI Subscribers"
{
    /// <summary>
    /// Checks that a newly created invoice has a Tractor Code dimension value.
    /// Done so that after the posting is complete, the invoice can be pushed to Alvys as a one-time truck deduction.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterInsertInvoiceHeader, '', false, false)]
    local procedure SalesPostOnAfterInsertInvoiceHeader(var SalesHeader: Record "Sales Header"; var SalesInvHeader: Record "Sales Invoice Header")
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
    begin
        SingleInstance.SetSalesDocuments('', '');
        SingleInstance.ClearDeductionRecIds();
        if AlvysSetup.Get() and AlvysSetup.Enabled then begin
            AlvysSetup.TestField("Tractor Code Dimension");
            if SalesHeader."Document Type" in [SalesHeader."Document Type"::Order, SalesHeader."Document Type"::Invoice] then
                if (AlvysSalesMgt.GetTractorCodeDimensionValue(SalesHeader."Dimension Set ID") <> '') and (AlvysSalesMgt.GetTractorCodeDimensionValue(SalesInvHeader."Dimension Set ID") <> '') then
                    SingleInstance.SetSalesDocuments(SalesHeader."No.", SalesInvHeader."No.");
        end
    end;

    /// <summary>
    /// Pushes a posted sales invoice to Alvys as a one-time truck deduction. The deduction is
    /// created once the posting has produced the invoice, so it carries both the document it was
    /// posted from and the posted invoice it ended up on.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterFinalizePostingOnBeforeCommit, '', false, false)]
    local procedure SalesPostOnAfterFinalizePostingOnBeforeCommit(var SalesHeader: Record "Sales Header"; var SalesInvoiceHeader: Record "Sales Invoice Header"; PreviewMode: Boolean)
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        SalesHeaderDocNo: Code[20];
        SalesInvHeaderDocNo: Code[20];
        DeductionId, Description : Text;
    begin
        // A posting run does not always produce an invoice -- a shipment or a credit memo leaves the
        // invoice number blank -- and a preview is rolled back, so neither may reach Alvys.
        if SalesInvoiceHeader."No." = '' then
            exit;
        if not AlvysSetup.Get() or not AlvysSetup.Enabled then
            exit;
        SingleInstance.GetSalesDocuments(SalesHeaderDocNo, SalesInvHeaderDocNo);
        if (SalesHeaderDocNo <> SalesHeader."No.") or (SalesInvHeaderDocNo <> SalesInvoiceHeader."No.") then
            exit;

        // Alvys deductions are negative: the invoice is deducted from the owner operator's pay.
        SalesInvoiceHeader.CalcFields("Amount Including VAT");
        if SalesInvoiceHeader."FRI Fleetrock Repair Order No." <> '' then
            Description := StrSubstNo(DescriptionLoadNoTxt, SalesInvoiceHeader."Shortcut Dimension 1 Code", SalesInvoiceHeader."No.", SalesInvoiceHeader."FRI Fleetrock Repair Order No.")
        else
            Description := StrSubstNo(DescriptionTxt, SalesInvoiceHeader."Shortcut Dimension 1 Code", SalesInvoiceHeader."No.");
        DeductionId := AlvysSalesMgt.CreateDeductionForTruck(SalesHeader, SalesInvoiceHeader, SalesInvoiceHeader."Posting Date", -SalesInvoiceHeader."Amount Including VAT", CategoryTok, Description, PreviewMode);
        SingleInstance.SetSalesDocuments('', '');
        if DeductionId <> '' then
            SingleInstance.AddDeductionRecId(SalesHeader.RecordId(), DeductionId);
    end;

    /// <summary>
    /// Clears the list of deduction record IDs after the posting is complete, to indicate that the deductions have been pushed to Alvys and the list is no longer needed.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnAfterFinalizePosting, '', false, false)]
    local procedure SalesPostOnAfterFinalizePosting()
    begin
        SingleInstance.ClearDeductionRecIds();
    end;







    /// <summary>
    /// Catches the posting of a sales document and ensures that if the posting fails, any deductions created in Alvys are deleted.
    /// This is done so that if the posting fails, the deduction is not left in Alvys without a corresponding invoice.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Sales-Post", OnBeforePostSalesDoc, '', false, false)]
    local procedure SalesPostOnBeforePostSalesDoc(sender: Codeunit "Sales-Post"; var SalesHeader: Record "Sales Header"; CommitIsSuppressed: Boolean; PreviewMode: Boolean; var HideProgressWindow: Boolean; var IsHandled: Boolean; var CalledBy: Integer)
    var
        AlvysSetup: Record "BAASI Alvys Sales Setup";
        SalesPost: Codeunit "Sales-Post";
        DeductionsRecIds: Dictionary of [RecordId, Text];
        RecId: RecordId;
        DeductionId: Text;
        Result: Boolean;
    begin
        if not AlvysSetup.Get() or not AlvysSetup.Enabled then
            exit;
        if SingleInstance.GetHandledSalesPosting() or CommitIsSuppressed or PreviewMode then
            exit;
        SingleInstance.SetHandledSalesPosting(true);
        SalesPost := sender;
        ClearLastError();
        Commit();
        Result := SalesPost.Run(SalesHeader);
        SingleInstance.SetHandledSalesPosting(false);
        if not Result then begin
            RecId := SalesHeader.RecordId();
            DeductionsRecIds := SingleInstance.GetDeductionRecIds();
            if DeductionsRecIds.ContainsKey(RecId) then begin
                DeductionId := DeductionsRecIds.Get(RecId);
                if AlvysSalesMgt.DoesDeductionExist(DeductionId) then
                    AlvysSalesMgt.DeleteDeduction(DeductionId);
                DeductionsRecIds.Remove(RecId);
            end;
            Error(GetLastErrorText());
        end;
        IsHandled := true;
    end;







    /// <summary>
    /// Events to handle populating and opening related deductions in the posting preview. The deductions are stored in a temporary table so that they can be displayed in a page without being committed to the database.
    /// </summary>
    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Gen. Jnl.-Post Preview", OnBeforeRunPreview, '', false, false)]
    local procedure GenJnlPostPreviewOnBeforeRunPreview()
    begin
        SingleInstance.ClearAlvysDeduction();
    end;

    [EventSubscriber(ObjectType::Table, Database::"BAASI Alvys Deduction", OnAfterInsertEvent, '', false, false)]
    local procedure AlvysDeductionOnAfterInsertEvent(var Rec: Record "BAASI Alvys Deduction"; RunTrigger: Boolean)
    begin
        if Rec.IsTemporary() then
            exit;
        SingleInstance.AddAlvysDeduction(Rec);
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Posting Preview Event Handler", OnAfterFillDocumentEntry, '', false, false)]
    local procedure PostingPreviewEventHandlerOnAfterFillDocumentEntry(var DocumentEntry: Record "Document Entry")
    var
        TempAlvysDeduction: Record "BAASI Alvys Deduction" temporary;
    begin
        SingleInstance.GetAlvysDeductions(TempAlvysDeduction);
        if TempAlvysDeduction.FindSet() then
            repeat
                DocumentEntry.Init();
                DocumentEntry."Entry No." := Database::"BAASI Alvys Deduction";
                DocumentEntry."Table ID" := Database::"BAASI Alvys Deduction";
                DocumentEntry."Table Name" := TempAlvysDeduction.TableCaption();
                DocumentEntry."No. of Records" := TempAlvysDeduction.Count();
                DocumentEntry.Insert(false);
            until TempAlvysDeduction.Next() = 0;
    end;

    [EventSubscriber(ObjectType::Codeunit, Codeunit::"Posting Preview Event Handler", OnAfterShowEntries, '', false, false)]
    local procedure PostingPreviewEventHandlerOnAfterShowEntries(TableNo: Integer)
    var
        TempAlvysDeduction: Record "BAASI Alvys Deduction" temporary;
    begin
        if TableNo = Database::"BAASI Alvys Deduction" then begin
            SingleInstance.GetAlvysDeductions(TempAlvysDeduction);
            Page.Run(Page::"BAASI Alvys Deductions", TempAlvysDeduction);
        end
    end;





    var
        AlvysSalesMgt: Codeunit "BAASI Alvys Sales Mgt.";
        SingleInstance: Codeunit "BAASI Single Instance";

        CategoryTok: Label 'Owner Operator Invoice', Locked = true;
        DescriptionTxt: Label 'BC Invoice %1 %2', Comment = '%1 = Entity Code, %2 = Posted Sales Invoice No.';
        DescriptionLoadNoTxt: Label 'BC Invoice %1 %2 FR Repair Order %3 ', Comment = '%1 = Entity Code, %2 = Sales Invoice Header No., %3 = Fleetrock Repair Order No.';
}
