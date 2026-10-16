codeunit 89972 "BAASIT Assert"
{
    // Stands in for Microsoft's "Library Assert", which ships with the test framework and so is not
    // available in production environments. It keeps that codeunit's procedure names, equality rules
    // and failure messages, so the tests read and fail the same way in either build.

    procedure IsTrue(Condition: Boolean; Msg: Text)
    begin
        if not Condition then
            Error(IsTrueFailedErr, Msg);
    end;

    procedure IsFalse(Condition: Boolean; Msg: Text)
    begin
        if Condition then
            Error(IsFalseFailedErr, Msg);
    end;

    procedure AreEqual(Expected: Variant; Actual: Variant; Msg: Text)
    begin
        if not Equal(Expected, Actual) then
            Error(AreEqualFailedErr, Expected, TypeName(Expected), Actual, TypeName(Actual), Msg);
    end;

    procedure AreNotEqual(Expected: Variant; Actual: Variant; Msg: Text)
    begin
        if Equal(Expected, Actual) then
            Error(AreNotEqualFailedErr, Expected, TypeName(Expected), Actual, TypeName(Actual), Msg);
    end;

    procedure Fail(Msg: Text)
    begin
        Error(FailFailedErr, Msg);
    end;

    /// <summary>
    /// Checks the last error contains the expected text. Call it straight after the try function
    /// that was expected to fail, before anything else can raise or clear an error.
    /// </summary>
    procedure ExpectedError(Expected: Text)
    begin
        if GetLastErrorText() = '' then
            Error(NoErrorRaisedErr, Expected);
        if StrPos(GetLastErrorText(), Expected) = 0 then
            Error(ExpectedErrorFailedErr, Expected, GetLastErrorText());
    end;

    procedure RecordIsEmpty(RecVariant: Variant)
    var
        RecRef: RecordRef;
    begin
        RecRef.GetTable(RecVariant);
        if not RecRef.IsEmpty() then
            Error(RecordIsEmptyErr, RecRef.Caption(), RecRef.GetFilters());
    end;

    local procedure Equal(Left: Variant; Right: Variant): Boolean
    var
        LeftNumber, RightNumber : Decimal;
    begin
        // Numbers compare by value whatever their type, so an Integer literal can be checked against
        // a Decimal field; anything else must be the same kind of value and format the same.
        if IsNumber(Left) and IsNumber(Right) then begin
            LeftNumber := Left;
            RightNumber := Right;
            exit(LeftNumber = RightNumber);
        end;
        exit((TypeName(Left) = TypeName(Right)) and (Format(Left, 0, 2) = Format(Right, 0, 2)));
    end;

    local procedure IsNumber(Value: Variant): Boolean
    begin
        exit(Value.IsDecimal() or Value.IsInteger() or Value.IsChar());
    end;

    local procedure TypeName(Value: Variant): Text
    begin
        case true of
            Value.IsBoolean():
                exit('Boolean');
            Value.IsOption(), Value.IsInteger(), Value.IsByte():
                exit('Integer');
            Value.IsBigInteger():
                exit('BigInteger');
            Value.IsDecimal():
                exit('Decimal');
            Value.IsText(), Value.IsCode(), Value.IsChar(), Value.IsTextConstant():
                exit('Text');
            Value.IsDate():
                exit('Date');
            Value.IsTime():
                exit('Time');
            Value.IsDuration():
                exit('Duration');
            Value.IsDateTime():
                exit('DateTime');
            Value.IsDateFormula():
                exit('DateFormula');
            Value.IsGuid():
                exit('GUID');
            Value.IsRecordId():
                exit('RecordID');
        end;
        Error(UnsupportedTypeErr);
    end;

    var
        IsTrueFailedErr: Label 'Assert.IsTrue failed. %1', Locked = true;
        IsFalseFailedErr: Label 'Assert.IsFalse failed. %1', Locked = true;
        AreEqualFailedErr: Label 'Assert.AreEqual failed. Expected:<%1> (%2). Actual:<%3> (%4). %5.', Locked = true;
        AreNotEqualFailedErr: Label 'Assert.AreNotEqual failed. Expected any value except:<%1> (%2). Actual:<%3> (%4). %5.', Locked = true;
        FailFailedErr: Label 'Assert.Fail failed. %1', Locked = true;
        NoErrorRaisedErr: Label 'Assert.ExpectedError failed. Expected: %1. No error was raised.', Locked = true;
        ExpectedErrorFailedErr: Label 'Assert.ExpectedError failed. Expected: %1. Actual: %2.', Locked = true;
        RecordIsEmptyErr: Label 'Assert.RecordIsEmpty failed. Table <%1> with filter <%2> must not contain records.', Locked = true;
        UnsupportedTypeErr: Label 'Equality assertions only support Boolean, Option, Integer, BigInteger, Decimal, Code, Text, Date, DateFormula, Time, Duration, DateTime, GUID and RecordID values.', Locked = true;
}
