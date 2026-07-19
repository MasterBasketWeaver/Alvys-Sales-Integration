table 80852 "BAASIT Test Run"
{
    Caption = 'Alvys Test Run';
    DataClassification = SystemMetadata;

    // Singleton holding the summary of the most recent run. It exists so the API has something to
    // GET for the result of a run and something to bind the "run" action to; the per-method detail
    // lives in "BAASIT Test Result".

    fields
    {
        field(1; "Primary Key"; Code[10])
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(2; "Started At"; DateTime)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(3; "Finished At"; DateTime)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(4; Duration; Duration)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(5; "Tests Run"; Integer)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(6; Successful; Integer)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
        field(7; Failed; Integer)
        {
            DataClassification = SystemMetadata;
            Editable = false;
        }
    }

    keys
    {
        key(PK; "Primary Key")
        {
            Clustered = true;
        }
    }

    /// <summary>
    /// Fetches the singleton, creating it on first use so the API entity is always present.
    /// </summary>
    procedure GetSingleton()
    begin
        if Rec.Get('') then
            exit;

        Rec.Init();
        Rec."Primary Key" := '';
        Rec.Insert();
    end;
}
