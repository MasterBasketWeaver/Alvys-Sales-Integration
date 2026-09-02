tableextension 80802 "BAASI Gen. Journal Line Ext" extends "Gen. Journal Line"
{
    fields
    {
        field(80000; "BAASI Alvys Deduction Id"; Text[50])
        {
            Caption = 'Alvys Deduction Id';
            Tooltip = 'Specifies the related Alvys deduction the journal line is associated with.';
            TableRelation = "BAASI Alvys Deduction"."Id";
            ValidateTableRelation = false;
            DataClassification = CustomerContent;

            trigger OnValidate()
            var
                GenJnlLine: Record "Gen. Journal Line";
            begin
                GenJnlLine.SetFilter("Line No.", '<>%1', Rec."Line No.");
                GenJnlLine.SetRange("BAASI Alvys Deduction Id", Rec."BAASI Alvys Deduction Id");
                if GenJnlLine.FindFirst() then
                    Error('The Alvys Deduction Id %1 has already been assigned to journal line %2 in journal template %3, batch %4.', GenJnlLine."BAASI Alvys Deduction Id", GenJnlLine."Line No.", GenJnlLine."Journal Template Name", GenJnlLine."Journal Batch Name");
            end;
        }
    }
}