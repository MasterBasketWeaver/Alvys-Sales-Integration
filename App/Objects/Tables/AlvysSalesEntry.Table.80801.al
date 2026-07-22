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
            Editable = false;
        }
        field(3; "Document Type"; Enum "BAASI Alvys Entry Doc. Type")
        {
            Editable = false;
        }
        field(4; "Document No."; Code[20])
        {
            Editable = false;
        }
        field(5; URL; Text[1024])
        {
            Editable = false;
        }
        field(6; Method; Text[20])
        {
            Editable = false;
        }
        field(7; "Request Body"; Blob)
        {
        }
        field(8; Response; Text[2048])
        {
            Editable = false;
        }
        field(9; "Error Message"; Text[512])
        {
            Editable = false;
        }
        field(10; "Error Stack"; Blob) { }
        field(11; "Created By"; Code[50])
        {
            Editable = false;
            FieldClass = FlowField;
            CalcFormula = Lookup(User."User Name" where("User Security ID" = field(SystemCreatedBy)));
        }
    }

    keys
    {
        key(PK; "Entry No.")
        {
            Clustered = true;
        }
    }


    procedure SetRequestBody(RequestBody: Text)
    var
        OutStrm: OutStream;
    begin
        Clear(Rec."Request Body");
        if RequestBody = '' then
            exit;
        Rec."Request Body".CreateOutStream(OutStrm, TextEncoding::UTF8);
        OutStrm.WriteText(RequestBody);
    end;

    procedure GetRequestBody(): Text
    var
        InStrm: InStream;
        s: Text;
    begin
        Rec.CalcFields("Request Body");
        if not Rec."Request Body".HasValue() then
            exit('');
        Rec."Request Body".CreateInStream(InStrm, TextEncoding::UTF8);
        InStrm.ReadText(s);
        exit(s);
    end;

    procedure SetErrorStack(ErrorStack: Text)
    var
        OutStrm: OutStream;
    begin
        Clear(Rec."Error Stack");
        if ErrorStack = '' then
            exit;
        Rec."Error Stack".CreateOutStream(OutStrm, TextEncoding::UTF8);
        OutStrm.WriteText(ErrorStack);
    end;

    procedure GetErrorStack(): Text
    var
        InStrm: InStream;
        s: Text;
    begin
        Rec.CalcFields("Error Stack");
        if not Rec."Error Stack".HasValue() then
            exit('');
        Rec."Error Stack".CreateInStream(InStrm, TextEncoding::UTF8);
        InStrm.ReadText(s);
        exit(s);
    end;

    procedure DisplayRequestBody()
    var
        RequestBody: Text;
    begin
        RequestBody := Rec.GetRequestBody();
        if RequestBody <> '' then
            Message(RequestBody);
    end;

    procedure DisplayErrorMessage()
    var
        Lines: List of [Text];
        Line, ErrorStackText : Text;
        ErrorStack: TextBuilder;
    begin
        ErrorStackText := Rec.GetErrorStack();
        if ErrorStackText <> '' then begin
            ErrorStack.AppendLine(Rec."Error Message");
            ErrorStack.AppendLine('');
            ErrorStack.AppendLine('Error Stack:');
            if ErrorStackText.Contains('\') then begin
                Lines := ErrorStackText.Split('\');
                foreach Line in Lines do
                    if Line <> '' then
                        ErrorStack.AppendLine(Line);
            end else
                ErrorStack.AppendLine(ErrorStackText);
            Message(ErrorStack.ToText());
        end else
            Message(Rec."Error Message");
    end;
}
