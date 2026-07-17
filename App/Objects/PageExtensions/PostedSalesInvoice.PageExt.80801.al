pageextension 80801 "BAASI Posted Sales Invoice" extends "Posted Sales Invoice"
{
    layout
    {
        addlast(General)
        {
            field("BAASI Has Alvys Deductions"; Rec."BAASI Has Alvys Deductions")
            {
                ApplicationArea = All;
            }
        }
    }
}
