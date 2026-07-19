tableextension 80801 "BAASI Sales Invoice Header" extends "Sales Invoice Header"
{
    fields
    {
        field(80800; "BAASI Has Alvys Deductions"; Boolean)
        {
            Caption = 'Has Alvys Deductions';
            FieldClass = FlowField;
            CalcFormula = exist("BAASI Alvys Deduction" where("Posted Document No." = field("No.")));
            Editable = false;
            Tooltip = 'If enabled, one or more Alvys deductions exist for the posted invoice.';
        }
    }
}
