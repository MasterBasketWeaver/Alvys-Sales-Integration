table 80863 "BAASIT Held Job Queue Entry"
{
    Caption = 'Held Job Queue Entry';
    DataClassification = SystemMetadata;

    // The job queue entries a test run put on hold, so only those are resumed afterwards and an
    // entry someone had already put on hold stays that way. Kept in a table rather than in memory
    // because an E2E chain holds them in one API call and resumes them in a later one.

    fields
    {
        field(1; "Job Queue Entry ID"; Guid) { DataClassification = SystemMetadata; }
    }

    keys
    {
        key(PK; "Job Queue Entry ID") { Clustered = true; }
    }
}
