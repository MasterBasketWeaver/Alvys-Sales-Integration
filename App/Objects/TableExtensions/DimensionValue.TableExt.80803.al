tableextension 80803 "BAASI Dimension Value" extends "Dimension Value"
{
    fields
    {
        field(80800; "BAASI Alvys ID"; Code[50])
        {
            Caption = 'Alvys ID';
            Tooltip = 'Specifies the Id of the Alvys truck or driver the dimension value was imported from.';
            DataClassification = CustomerContent;
            Editable = false;

            trigger OnValidate()
            var
                OtherDimValue: Record "Dimension Value";
            begin
                if Rec.BAASIFindByAlvysID(Rec."BAASI Alvys ID", OtherDimValue) then
                    Error(AlvysIDInUseErr, Rec."BAASI Alvys ID", OtherDimValue."Dimension Code", OtherDimValue.Code);
            end;
        }
    }

    keys
    {
        // Not Unique: every dimension value that did not come from Alvys shares the blank ID, which a
        // unique index would refuse. The field's OnValidate keeps a non-blank ID to one value per
        // dimension.
        key(BAASIAlvysID; "BAASI Alvys ID") { }
    }

    /// <summary>
    /// Finds the dimension value, other than this one, that carries AlvysID in this one's dimension.
    /// Other dimensions are not looked at: a truck and a driver are separate Alvys records, and
    /// nothing stops Alvys from giving the two the same Id.
    /// </summary>
    procedure BAASIFindByAlvysID(AlvysID: Code[50]; var OtherDimValue: Record "Dimension Value"): Boolean
    begin
        if AlvysID = '' then
            exit(false);
        OtherDimValue.Reset();
        OtherDimValue.SetCurrentKey("BAASI Alvys ID");
        OtherDimValue.SetRange("BAASI Alvys ID", AlvysID);
        OtherDimValue.SetRange("Dimension Code", Rec."Dimension Code");
        OtherDimValue.SetFilter(Code, '<>%1', Rec.Code);
        exit(OtherDimValue.FindFirst());
    end;

    var
        AlvysIDInUseErr: Label 'Alvys ID %1 is already on dimension value %2 %3.', Comment = '%1 = Alvys ID, %2 = Dimension Code, %3 = Dimension Value Code';
}
