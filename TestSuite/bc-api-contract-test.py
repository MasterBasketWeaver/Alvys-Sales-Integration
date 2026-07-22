#!/usr/bin/env python3
"""Contract test for the inbound Alvys API page (page 80803, alvysApplyDeductions).

The page takes the six driver pay parameters and derives the rest of the entry from them. The AL
suite in the test app covers that derivation: entry numbering, the Inbound direction stamp, and
matching the deduction Id to the posted invoice. It cannot cover the OData layer in front of it,
because the suite runs in a web-service session and TestPage needs a NAV client session.

So this hits the real endpoint over HTTP and asserts the things Alvys actually depends on:

  1. The property names and EDM types published in $metadata. These are the wire contract now,
     and renaming a page control silently rewrites them.
  2. That a payload matching a posted invoice is accepted, and comes back pointed at that invoice.
  3. That a failure Alvys could clear by retrying -- a deduction whose document is not posted yet
     -- is refused with a 400, and that the entry is logged anyway. The refusal rolls the
     transaction back, so the entry only survives because the page commits it first. That commit
     is the whole reason this check exists.
  4. That a failure retrying cannot clear -- an unknown or blank deduction Id -- is answered 201
     with the reason on the entry instead. Refusing it would buy nothing but a retry for as long
     as Alvys keeps trying, and a duplicate log row for each attempt.
  5. That each of the six parameters marks the record dirty on its own. They are bound to page
     variables rather than table fields, so each rests on its own OnValidate; without it the
     delayed insert never fires and the call is answered 201 with nothing written.
  6. That the derived fields are refused as inputs, and that the parameters survive the round trip
     -- they are not stored field by field, but rebuilt from the logged request body.
  7. That the entity set exposes inbound entries only, and that modify and delete stay closed.

Both failure paths need a deduction in a particular state, which nothing here can create through
the shipping app, so the test app carries a seed endpoint. Nothing rolls these rows back either,
so the run finishes by deleting every entry and deduction it created. The seed and cleanup
endpoints live in the test app on purpose: the entry table is an append-only audit log.

Run it after publishing both apps:  python3 TestSuite/bc-api-contract-test.py
Exits non-zero on the first failed assertion.
"""
import json
import re
import sys
import uuid
from pathlib import Path

import requests

# Authentication is shared with the build and publish scripts, which live outside this repo.
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools"))

from bc_auth import get_access_token  # noqa: E402

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = "MCSandbox_061226"
COMPANY = "Texas Transportation Group"
BASE = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}"
API = f"{BASE}/api/tanager/alvys/v1.0"

# The published shape of the entity. Property name -> EDM type. Alvys builds its payload against
# this, so a change here is a breaking change and has to be agreed with them first.
EXPECTED_PROPERTIES = {
    "id": "Edm.Guid",
    "entryNo": "Edm.Int32",
    # The driver pay payload Alvys posts.
    "deductionId": "Edm.String",
    "truckId": "Edm.String",
    "truckNumber": "Edm.String",
    "amount": "Edm.Decimal",
    "settlementDate": "Edm.Date",
    "description": "Edm.String",
    # What Business Central made of it, read back.
    "direction": "Microsoft.NAV.baasiAlvysEntryDirection",
    "documentType": "Microsoft.NAV.baasiAlvysEntryDocType",
    "documentNo": "Edm.String",
    "errorMessage": "Edm.String",
    "systemCreatedAt": "Edm.DateTimeOffset",
}

# The six parameters the page takes.
PARAMETERS = ["deductionId", "truckId", "truckNumber", "amount", "settlementDate", "description"]

# Everything else on the entry is derived, so a caller must not be able to set it. entryNo is not
# in the list: it is the primary key, and OData accepts a key on insert. It is checked separately,
# on the stronger guarantee that the numbering overrides whatever was sent.
READ_ONLY_PROPERTIES = ["direction", "documentType", "documentNo", "errorMessage"]

# OData encodes the spaces in an enum value, so this is the string Alvys sees on the wire.
POSTED_SALES_INVOICE = "Posted_x0020_Sales_x0020_Invoice"

# The driver pay payload as described in section 4.2 of the technical scope. The field names are
# still Alvys' to confirm, so this is the shape the page has to carry, not a contract. deductionId
# is filled in per call: a matched one is seeded, an unmatched one is invented.
DRIVER_PAY_PAYLOAD = {
    "deductionId": "",
    "truckId": "TR2516627931370728085",
    "truckNumber": "1",
    "amount": -55.0,
    "settlementDate": "2026-07-22",
    "description": "Settlement 12345",
}

ZERO_GUID = "00000000-0000-0000-0000-000000000000"

failures = []
checks = 0
# Deductions this run seeded, so the cleanup at the end deletes only its own rows. Entries are not
# tracked individually: the refusal path commits them, so the sweep goes by entry number instead.
seeded_ids = []
baseline_entry_no = 0


def check(condition, message):
    global checks
    checks += 1
    if condition:
        print(f"  [PASS] {message}")
    else:
        print(f"  [FAIL] {message}")
        failures.append(message)


def settle(entity_set, headers, **overrides):
    """POSTs a driver pay payload, with any field overridden or added."""
    payload = dict(DRIVER_PAY_PAYLOAD, **overrides)
    return requests.post(entity_set, headers=headers, data=json.dumps(payload), timeout=120)


def main():
    global baseline_entry_no

    token = get_access_token()
    headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}

    resp = requests.get(f"{BASE}/api/v2.0/companies?$filter=name eq '{COMPANY}'",
                        headers=headers, timeout=120)
    resp.raise_for_status()
    companies = resp.json().get("value", [])
    if not companies:
        sys.exit(f"ERROR: company '{COMPANY}' not found.")
    company_id = companies[0]["id"]
    entity_set = f"{API}/companies({company_id})/alvysApplyDeductions"
    # The seed and cleanup endpoints live in the test app, under its own publisher.
    test_api = f"{BASE}/api/bryana/alvys/v1.0/companies({company_id})"
    cleanup_set = f"{test_api}/alvysEntryCleanups"
    seed_set = f"{test_api}/alvysDeductionSeeds"

    # Everything above this number is this run's, and gets deleted at the end.
    resp = requests.get(cleanup_set, headers=headers, timeout=120)
    resp.raise_for_status()
    baseline_entry_no = max((r.get("entryNo", 0) for r in resp.json().get("value", [])), default=0)

    print("\n[1/8] Published entity shape")
    resp = requests.get(f"{API}/$metadata", headers=headers, timeout=120)
    resp.raise_for_status()
    entity = re.search(r'<EntityType Name="alvysApplyDeduction".*?</EntityType>', resp.text, re.S)
    if not entity:
        sys.exit("ERROR: the alvysApplyDeduction entity is not published. Is the app installed?")
    published = dict(re.findall(r'<Property Name="(\w+)" Type="([\w.]+)"', entity.group(0)))

    for name, edm_type in EXPECTED_PROPERTIES.items():
        check(name in published, f"property '{name}' is published")
        if name in published:
            check(published[name] == edm_type,
                  f"property '{name}' is {edm_type} (got {published[name]})")
    check(not set(published) - set(EXPECTED_PROPERTIES),
          f"no unexpected properties (extra: {sorted(set(published) - set(EXPECTED_PROPERTIES))})")
    key = re.search(r'<PropertyRef Name="(\w+)"', entity.group(0))
    check(key and key.group(1) == "id", "the entity is keyed on 'id'")

    print("\n[2/8] A matched deduction is accepted")
    matched_id = str(uuid.uuid4())
    resp = requests.post(seed_set, headers=headers,
                         data=json.dumps({"deductionId": matched_id}), timeout=120)
    if resp.status_code != 201:
        sys.exit(f"ERROR: could not seed a deduction ({resp.status_code}: {resp.text[:300]})")
    seeded = resp.json()
    seeded_ids.append(seeded["id"])
    posted_invoice_no = seeded["postedDocumentNo"]
    print(f"  (seeded deduction {matched_id} against posted invoice {posted_invoice_no})")

    resp = settle(entity_set, headers, deductionId=matched_id)
    check(resp.status_code == 201, f"POST returns 201 (got {resp.status_code}: {resp.text[:200]})")
    if resp.status_code != 201:
        cleanup(headers, cleanup_set, seed_set)
        report()
    created = resp.json()
    check(created.get("direction") == "Inbound", "the entry is stamped Inbound")
    check(created.get("entryNo", 0) > 0, "an entry number is assigned")
    check(created.get("documentType") == POSTED_SALES_INVOICE,
          f"the entry is stamped Posted Sales Invoice (got {created.get('documentType')})")
    check(created.get("documentNo") == posted_invoice_no,
          f"the entry points at the deduction's posted invoice "
          f"(got {created.get('documentNo')!r}, want {posted_invoice_no!r})")
    check(not created.get("errorMessage"),
          f"a matched deduction logs no error (got {created.get('errorMessage')!r})")

    print("\n[3/8] A failure Alvys can clear by retrying is refused")
    # A deduction whose document is not posted yet will match once it is, so the same payload sent
    # again can succeed. That is the one failure worth a 400.
    #
    # The refusal raises an error, which rolls the transaction back. The entry survives only
    # because the page commits it before erroring; without that commit this check fails and every
    # settlement Alvys could not apply would vanish from the log.
    retryable_id = str(uuid.uuid4())
    resp = requests.post(seed_set, headers=headers,
                         data=json.dumps({"deductionId": retryable_id, "unposted": True}),
                         timeout=120)
    if resp.status_code != 201:
        sys.exit(f"ERROR: could not seed an unposted deduction "
                 f"({resp.status_code}: {resp.text[:300]})")
    seeded_ids.append(resp.json()["id"])

    resp = settle(entity_set, headers, deductionId=retryable_id)
    check(resp.status_code == 400,
          f"an unposted deduction is refused so Alvys retries (got {resp.status_code})")
    check(retryable_id in resp.text,
          f"the 400 names the deduction it could not apply (got {resp.text[:200]})")

    logged = find_entry(entity_set, headers, retryable_id)
    check(logged is not None, "the refused call is logged despite the error rolling back")
    if logged:
        check(logged.get("documentNo") == "",
              f"the refused entry has no document number (got {logged.get('documentNo')!r})")
        check("has not been posted" in (logged.get("errorMessage") or ""),
              f"the refused entry says why (got {logged.get('errorMessage')!r})")

    print("\n[4/8] A failure retrying cannot clear is accepted and logged")
    # A deduction Business Central has no record of will never match, so refusing it would buy
    # nothing but a retry for as long as Alvys keeps trying, and a duplicate log row for each.
    unmatched_id = str(uuid.uuid4())
    resp = settle(entity_set, headers, deductionId=unmatched_id)
    check(resp.status_code == 201,
          f"an unknown deduction is accepted, not refused (got {resp.status_code}: "
          f"{resp.text[:160]})")
    if resp.status_code == 201:
        unmatched = resp.json()
        check(unmatched.get("documentNo") == "",
              f"an unknown deduction gets no document number (got {unmatched.get('documentNo')!r})")
        check(unmatched_id in (unmatched.get("errorMessage") or ""),
              f"the response carries the reason it could not be applied "
              f"(got {unmatched.get('errorMessage')!r})")

    # A blank deduction Id has nothing to match on and never will, so it is treated the same way.
    resp = settle(entity_set, headers, deductionId="")
    check(resp.status_code == 201, f"a blank deduction Id is accepted (got {resp.status_code})")
    if resp.status_code == 201:
        check("cannot be blank" in (resp.json().get("errorMessage") or ""),
              f"a blank deduction Id logs its reason (got {resp.json().get('errorMessage')!r})")

    print("\n[5/8] Each parameter marks the record dirty")
    # A parameter that lost its OnValidate leaves the record clean, so the delayed insert never
    # fires, OnInsertRecord never runs, and the call is answered 201 with nothing written. Since an
    # unmatchable payload is now answered 201 too, the status alone cannot tell those apart: what
    # separates them is whether a row was actually persisted.
    for prop in PARAMETERS:
        resp = requests.post(entity_set, headers=headers,
                             data=json.dumps({prop: DRIVER_PAY_PAYLOAD[prop] or unmatched_id}),
                             timeout=120)
        single = resp.json() if resp.status_code == 201 else {}
        check(single.get("id", ZERO_GUID) != ZERO_GUID and single.get("entryNo", 0) > 0,
              f"'{prop}' alone is persisted, not just acknowledged "
              f"(got {resp.status_code}, id {single.get('id')})")

    print("\n[6/8] Derived fields are not inputs")
    # Sent alongside a payload that would otherwise be accepted, so a 400 means the property was
    # refused rather than the settlement failing to match.
    for prop in READ_ONLY_PROPERTIES:
        resp = settle(entity_set, headers, deductionId=matched_id, **{prop: "x"})
        check(resp.status_code >= 400, f"'{prop}' is refused as an input (got {resp.status_code})")

    # entryNo is the primary key, so OData accepts it on insert rather than refusing it. The log
    # numbers its own entries, so what matters is that a caller cannot choose the number: sending
    # one must not collide with, or renumber, the entries already in the log.
    resp = settle(entity_set, headers, deductionId=matched_id, entryNo=1)
    numbered = resp.json() if resp.status_code == 201 else {}
    check(numbered.get("entryNo", 0) > 1,
          f"a caller-supplied entry number is overridden (got {numbered.get('entryNo')})")

    print("\n[7/8] Round trip by key")
    resp = requests.get(f"{entity_set}({created['id']})", headers=headers, timeout=120)
    check(resp.status_code == 200, f"GET by id returns 200 (got {resp.status_code})")
    if resp.status_code == 200:
        fetched = resp.json()
        # The parameters are not stored field by field; they are rebuilt from the request body the
        # entry logged. Reading a row back has to take that body apart again and return every one.
        for prop, value in dict(DRIVER_PAY_PAYLOAD, deductionId=matched_id).items():
            check(fetched.get(prop) == value,
                  f"'{prop}' survives the round trip (got {fetched.get(prop)!r}, want {value!r})")
        check(fetched.get("entryNo") == created.get("entryNo"), "the entry number is stable")

    print("\n[8/8] Exposure limits")
    resp = requests.get(entity_set, headers=headers, timeout=120)
    check(resp.status_code == 200, f"the entity set is readable (got {resp.status_code})")
    if resp.status_code == 200:
        rows = resp.json().get("value", [])
        check(all(r.get("direction") == "Inbound" for r in rows),
              f"the entity set exposes inbound entries only ({len(rows)} rows)")

    etag = created.get("@odata.etag", "*")
    modify_headers = dict(headers, **{"If-Match": etag})
    resp = requests.patch(f"{entity_set}({created['id']})", headers=modify_headers,
                          data=json.dumps({"description": "changed"}), timeout=120)
    check(resp.status_code >= 400, f"modify is refused (got {resp.status_code})")
    resp = requests.delete(f"{entity_set}({created['id']})", headers=modify_headers, timeout=120)
    check(resp.status_code >= 400, f"delete is refused (got {resp.status_code})")

    print("\nCleanup")
    cleanup(headers, cleanup_set, seed_set)
    report()


def find_entry(entity_set, headers, deduction_id):
    """The entry logged for a deduction Id, or None. Read back through the shipping endpoint."""
    resp = requests.get(entity_set, headers=headers, timeout=120)
    if resp.status_code != 200:
        return None
    for row in resp.json().get("value", []):
        if row.get("deductionId") == deduction_id:
            return row
    return None


def cleanup(headers, cleanup_set, seed_set):
    """Deletes the entries and deductions this run created, through the test app's endpoints."""
    resp = requests.get(cleanup_set, headers=headers, timeout=120)
    entries = [r for r in resp.json().get("value", [])
               if r.get("entryNo", 0) > baseline_entry_no] if resp.status_code == 200 else []

    removed = 0
    for row in entries:
        resp = requests.delete(f"{cleanup_set}({row['id']})", headers=headers, timeout=120)
        if resp.status_code in (200, 204):
            removed += 1
        else:
            print(f"  [WARN] entry {row['entryNo']} not deleted "
                  f"({resp.status_code}: {resp.text[:120]})")
    check(removed == len(entries),
          f"every entry this run created was deleted ({removed}/{len(entries)})")

    removed = 0
    for seed_id in seeded_ids:
        resp = requests.delete(f"{seed_set}({seed_id})", headers=headers, timeout=120)
        if resp.status_code in (200, 204):
            removed += 1
        else:
            print(f"  [WARN] deduction {seed_id} not deleted "
                  f"({resp.status_code}: {resp.text[:120]})")
    check(removed == len(seeded_ids),
          f"every deduction this run seeded was deleted ({removed}/{len(seeded_ids)})")


def report():
    print(f"\n{checks - len(failures)}/{checks} checks passed.")
    if failures:
        print("\nFailed:")
        for failure in failures:
            print(f"  - {failure}")
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
