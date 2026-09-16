codeunit 89964 "BAASIT Job Queue Hold"
{
    // The Fleetrock import and the settlement poll act on the same repair orders, invoices and
    // deductions the tests create. Left running, the job queue can import a test's repair order or
    // apply its settlement before the test gets to, so both are held for the length of a run.

    procedure HoldJobQueues()
    var
        HeldEntry: Record "BAASIT Held Job Queue Entry";
        JobQueueEntry: Record "Job Queue Entry";
        EntryIds: List of [Guid];
        EntryId: Guid;
    begin
        JobQueueEntry.SetRange("Object Type to Run", JobQueueEntry."Object Type to Run"::Codeunit);
        JobQueueEntry.SetFilter("Object ID to Run", '%1|%2', Codeunit::"FRI Get Repair Orders", Codeunit::"BAASI Alvys Settlement Poll");
        JobQueueEntry.SetRange(Status, JobQueueEntry.Status::Ready);
        // Gathered first: holding an entry takes it out of the Status filter being read.
        if JobQueueEntry.FindSet() then
            repeat
                EntryIds.Add(JobQueueEntry.ID);
            until JobQueueEntry.Next() = 0;

        foreach EntryId in EntryIds do
            if JobQueueEntry.Get(EntryId) then
                if JobQueueEntry.Status = JobQueueEntry.Status::Ready then begin
                    JobQueueEntry.SetStatus(JobQueueEntry.Status::"On Hold");
                    HeldEntry."Job Queue Entry ID" := EntryId;
                    if HeldEntry.Insert() then;
                end;
        Commit();
    end;

    procedure ResumeJobQueues()
    var
        HeldEntry: Record "BAASIT Held Job Queue Entry";
        JobQueueEntry: Record "Job Queue Entry";
    begin
        if HeldEntry.FindSet() then
            repeat
                if JobQueueEntry.Get(HeldEntry."Job Queue Entry ID") then
                    if JobQueueEntry.Status = JobQueueEntry.Status::"On Hold" then
                        JobQueueEntry.SetStatus(JobQueueEntry.Status::Ready);
            until HeldEntry.Next() = 0;
        HeldEntry.DeleteAll();
        Commit();
    end;
}
