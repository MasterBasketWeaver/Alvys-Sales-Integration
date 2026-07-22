enum 80801 "BAASI Alvys Entry Direction"
{
    Extensible = true;
    Caption = 'Alvys Entry Direction';

    // Outbound is the zero value so entries logged before this field existed keep the direction
    // they were actually sent in, without an upgrade step.
    value(0; Outbound) { }
    value(1; Inbound) { }
}
