page 89957 "BAASIT Alvys Dim. Value API"
{
    // Read-only view of the dimension values with the Alvys ID the Driver/Truck Import puts on
    // them, which no page in the app shows:
    //
    //   GET .../api/bryana/alvys/v1.0/companies({companyId})/alvysDimensionValues
    //       ?$filter=dimensionCode eq 'TRACTOR'

    PageType = API;
    APIPublisher = 'bryana';
    APIGroup = 'alvys';
    APIVersion = 'v1.0';
    EntityName = 'alvysDimensionValue';
    EntitySetName = 'alvysDimensionValues';
    SourceTable = "Dimension Value";
    ODataKeyFields = SystemId;
    Caption = 'Alvys Dimension Value';
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
                field(dimensionCode; Rec."Dimension Code") { }
                field(code; Rec.Code) { }
                field(name; Rec.Name) { }
                field(blocked; Rec.Blocked) { }
                field(alvysId; Rec."BAASI Alvys ID") { }
                field(systemModifiedAt; Rec.SystemModifiedAt) { }
            }
        }
    }
}
