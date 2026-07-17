pageextension 80800 "BAASI Sales Invoice" extends "Sales Invoice"
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
