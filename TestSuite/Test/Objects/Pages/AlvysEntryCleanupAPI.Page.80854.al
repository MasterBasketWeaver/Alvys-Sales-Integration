page 80854 "BAASIT Alvys Entry Cleanup API"
{
    // Deletes the entries the OData contract test leaves behind. That test posts against the live
    // endpoint rather than a test session, so nothing rolls its rows back the way the AL suite
    // rolls back its own.
    //
    //   DELETE .../api/bryana/alvys/v1.0/companies({companyId})/alvysEntryCleanups({id})
    //
    // This lives in the test app on purpose. The entry table is an append-only audit log, and the
    // app that ships to production must not carry a way to delete from it. The filter below is the
    // second guard: only inbound entries are reachable, so the outbound log cannot be touched even
    // from here.

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysEntryCleanup';
    EntitySetName = 'alvysEntryCleanups';
    SourceTable = "BAASI Alvys Sales Entry";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Entry Cleanup';
    SourceTableView = where(Direction = const(Inbound));
    // Editable must stay true: page-level Editable = false disables delete as well, and the
    // endpoint exists to delete. Insert and modify are closed individually instead.
    DeleteAllowed = true;
    InsertAllowed = false;
    ModifyAllowed = false;
    Extensible = false;

    layout
    {
        area(Content)
        {
            repeater(Group)
            {
                field(id; Rec.SystemId) { }
                field(entryNo; Rec."Entry No.") { }
                field(direction; Rec.Direction) { }
                field(documentNo; Rec."Document No.") { }
                field(url; Rec.URL) { }
                field(systemCreatedAt; Rec.SystemCreatedAt) { }
            }
        }
    }
}
