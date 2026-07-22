codeunit 80804 "BAASI Single Instance"
{
    SingleInstance = true;

    procedure SetSalesDocuments(NewSalesHeaderDocNo: Code[20]; NewSalesInvHeaderDocNo: Code[20])
    begin
        SalesHeaderDocNo := NewSalesHeaderDocNo;
        SalesInvHeaderDocNo := NewSalesInvHeaderDocNo;
    end;

    procedure GetSalesDocuments(var NewSalesHeaderDocNo: Code[20]; var NewSalesInvHeaderDocNo: Code[20])
    begin
        NewSalesHeaderDocNo := SalesHeaderDocNo;
        NewSalesInvHeaderDocNo := SalesInvHeaderDocNo;
    end;


    procedure ClearAlvysDeduction()
    begin
        TempAlvysDeduction.Reset();
        TempAlvysDeduction.DeleteAll(false);
    end;

    procedure AddAlvysDeduction(var AlvysDeduction: Record "BAASI Alvys Deduction")
    begin
        TempAlvysDeduction := AlvysDeduction;
        TempAlvysDeduction.Insert(false);
    end;

    procedure GetAlvysDeductions(var AlvysDeduction: Record "BAASI Alvys Deduction")
    begin
        AlvysDeduction.Reset();
        AlvysDeduction.DeleteAll();
        if TempAlvysDeduction.FindSet() then
            repeat
                AlvysDeduction := TempAlvysDeduction;
                AlvysDeduction.Insert(false);
            until TempAlvysDeduction.Next() = 0;
    end;


    var
        TempAlvysDeduction: Record "BAASI Alvys Deduction" temporary;
        SalesHeaderDocNo, SalesInvHeaderDocNo : Code[20];
}