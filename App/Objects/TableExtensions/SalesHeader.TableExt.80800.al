tableextension 80800 "BAASI Sales Header" extends "Sales Header"
{
    fields
    {
        field(80800; "BAASI Has Alvys Deductions"; Boolean)
        {
            Caption = 'Has Alvys Deductions';
            FieldClass = FlowField;
            CalcFormula = exist("BAASI Alvys Deduction" where("Document Type" = field("Document Type"), "Document No." = field("No."), Posted = const(false)));
            Editable = false;
            Tooltip = 'If enabled, one or more Alvys deductions exist for the document.';
        }
    }
}
