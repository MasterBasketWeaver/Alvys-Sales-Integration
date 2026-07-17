table 80801 "BAASI Alvys Sales Entry"
{
    Caption = 'Alvys Sales Entry';
    DataClassification = CustomerContent;
    DrillDownPageId = "BAASI Alvys Sales Entries";
    LookupPageId = "BAASI Alvys Sales Entries";

    fields
    {
        field(1; "Entry No."; Integer)
        {
            DataClassification = CustomerContent;
            Editable = false;
        }

    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }



    // procedure DisplayErrorMessage()
    // var
    //     Lines: List of [Text];
    //     Line: Text;
    //     ErrorStack: TextBuilder;
    // begin
    //     if Rec."Error Stack" <> '' then begin
    //         ErrorStack.AppendLine(Rec."Error Message");
    //         ErrorStack.AppendLine('');
    //         ErrorStack.AppendLine('Error Stack:');
    //         if Rec."Error Stack".Contains('\') then begin
    //             Lines := Rec."Error Stack".Split('\');
    //             foreach Line in Lines do
    //                 if Line <> '' then
    //                     ErrorStack.AppendLine(Line);
    //         end else
    //             ErrorStack.AppendLine(Rec."Error Stack");
    //         Message(ErrorStack.ToText());
    //     end else
    //         Message(Rec."Error Message");
    // end;
}