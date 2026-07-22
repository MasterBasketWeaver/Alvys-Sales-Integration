#!/usr/bin/env python3
"""Contract test for the inbound Alvys API page (page 80803, alvysApplyDeductions).

The AL suite in the test app covers the logic behind the page: entry numbering, the Inbound
direction stamp, the request body Blob. It cannot cover the OData layer in front of it, because
the suite runs in a web-service session and TestPage needs a NAV client session.

So this hits the real endpoint over HTTP and asserts the things Alvys actually depends on:

  1. The property names and EDM types published in $metadata. These are the wire contract now,
     and renaming a page control silently rewrites them.
  2. That every property Alvys has to write is writable. The entry fields are Editable = false on
     the table, so each writable property rests on an explicit override on the page.
  3. That the request body survives the round trip. It is bound to a page variable rather than a
     table field, so it depends on the framework populating that variable before OnInsertRecord.
  4. That the entity set exposes inbound entries only, never the outbound log.
  5. That modify and delete stay closed.

Nothing rolls these rows back the way the AL suite rolls back its own, so the run finishes by
deleting every entry it created through the cleanup endpoint in the test app. That endpoint is
deliberately not part of the app that ships: the entry table is an append-only audit log.

Run it after publishing both apps:  python3 TestSuite/bc-api-contract-test.py
Exits non-zero on the first failed assertion.
"""
import json
import re
import sys
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
    "direction": "Microsoft.NAV.baasiAlvysEntryDirection",
    "documentType": "Microsoft.NAV.baasiAlvysEntryDocType",
    "documentNo": "Edm.String",
    "url": "Edm.String",
    "method": "Edm.String",
    "requestBody": "Edm.String",
    "response": "Edm.String",
    "errorMessage": "Edm.String",
    "systemCreatedAt": "Edm.DateTimeOffset",
}

# Properties Alvys has to be able to write. Each one needs Editable = true on the page, because
# the entry table marks them read-only for the outbound log.
WRITABLE_PROPERTIES = ["documentType", "documentNo", "url", "method", "requestBody",
                       "response", "errorMessage"]

# The driver pay payload as described in section 4.2 of the technical scope. The field names are
# still Alvys' to confirm, so this is the shape the page has to carry, not a contract.
DRIVER_PAY_PAYLOAD = json.dumps({
    "DeductionId": "4ba92c0d-736d-4b44-85d0-12c9fc9bad71",
    "TruckId": "TR2516627931370728085",
    "TruckNumber": "1",
    "Amount": 55.0,
    "SettlementDate": "2026-07-22",
    "Description": "Settlement 12345",
})

ZERO_GUID = "00000000-0000-0000-0000-000000000000"

failures = []
checks = 0
# Every entry this run creates, so the cleanup at the end deletes only its own rows.
created_ids = []


def check(condition, message):
    global checks
    checks += 1
    if condition:
        print(f"  [PASS] {message}")
    else:
        print(f"  [FAIL] {message}")
        failures.append(message)


def main():
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
    # The cleanup endpoint lives in the test app, under its own publisher.
    cleanup_set = f"{BASE}/api/bryana/alvys/v1.0/companies({company_id})/alvysEntryCleanups"

    print("\n[1/6] Published entity shape")
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

    print("\n[2/6] Inbound POST")
    payload = {
        "documentType": "Posted Sales Invoice",
        "documentNo": "PS-INV101026",
        "url": "/api/tanager/alvys/v1.0/alvysApplyDeductions",
        "method": "POST",
        "requestBody": DRIVER_PAY_PAYLOAD,
        "response": "",
        "errorMessage": "",
    }
    resp = requests.post(entity_set, headers=headers, data=json.dumps(payload), timeout=120)
    check(resp.status_code == 201, f"POST returns 201 (got {resp.status_code}: {resp.text[:200]})")
    if resp.status_code != 201:
        cleanup(headers, cleanup_set)
        report()
    created = resp.json()
    created_ids.append(created["id"])
    check(created.get("direction") == "Inbound", "the entry is stamped Inbound")
    check(created.get("entryNo", 0) > 0, "an entry number is assigned")
    check(created.get("requestBody") == DRIVER_PAY_PAYLOAD,
          "the request body comes back byte-for-byte")

    print("\n[3/6] Writable properties")
    # A property that lost its Editable override fails the whole POST, so send each one on its own
    # to name the property that broke rather than just reporting a 400.
    for prop in WRITABLE_PROPERTIES:
        value = DRIVER_PAY_PAYLOAD if prop == "requestBody" else (
            "Posted Sales Invoice" if prop == "documentType" else "x")
        resp = requests.post(entity_set, headers=headers,
                             data=json.dumps({prop: value}), timeout=120)
        check(resp.status_code == 201,
              f"'{prop}' is writable (got {resp.status_code}: {resp.text[:120]})")
        if resp.status_code == 201 and resp.json().get("id", ZERO_GUID) != ZERO_GUID:
            created_ids.append(resp.json()["id"])

    # requestBody is bound to a page variable rather than a table field, so a call that sends
    # nothing else leaves the record untouched and the delayed insert never fires. That answered
    # 201 while persisting nothing, which would lose payloads silently. Guard the fix.
    resp = requests.post(entity_set, headers=headers,
                         data=json.dumps({"requestBody": DRIVER_PAY_PAYLOAD}), timeout=120)
    body_only = resp.json() if resp.status_code == 201 else {}
    persisted = body_only.get("id", ZERO_GUID) != ZERO_GUID
    check(resp.status_code == 201 and persisted,
          f"a payload-only POST is persisted, not just acknowledged (id {body_only.get('id')})")
    if persisted:
        created_ids.append(body_only["id"])
        check(body_only.get("entryNo", 0) > 0, "a payload-only POST is given an entry number")
        check(body_only.get("direction") == "Inbound", "a payload-only POST is stamped Inbound")

    print("\n[4/6] Round trip by key")
    resp = requests.get(f"{entity_set}({created['id']})", headers=headers, timeout=120)
    check(resp.status_code == 200, f"GET by id returns 200 (got {resp.status_code})")
    if resp.status_code == 200:
        fetched = resp.json()
        check(fetched.get("requestBody") == DRIVER_PAY_PAYLOAD,
              "the request body survives the Blob round trip")
        check(fetched.get("entryNo") == created.get("entryNo"), "the entry number is stable")

    print("\n[5/6] Exposure limits")
    resp = requests.get(entity_set, headers=headers, timeout=120)
    check(resp.status_code == 200, f"the entity set is readable (got {resp.status_code})")
    if resp.status_code == 200:
        rows = resp.json().get("value", [])
        check(all(r.get("direction") == "Inbound" for r in rows),
              f"the entity set exposes inbound entries only ({len(rows)} rows)")

    etag = created.get("@odata.etag", "*")
    modify_headers = dict(headers, **{"If-Match": etag})
    resp = requests.patch(f"{entity_set}({created['id']})", headers=modify_headers,
                          data=json.dumps({"method": "PUT"}), timeout=120)
    check(resp.status_code >= 400, f"modify is refused (got {resp.status_code})")
    resp = requests.delete(f"{entity_set}({created['id']})", headers=modify_headers, timeout=120)
    check(resp.status_code >= 400, f"delete is refused (got {resp.status_code})")

    print("\n[6/6] Cleanup")
    cleanup(headers, cleanup_set)
    report()


def cleanup(headers, cleanup_set):
    """Deletes the entries this run created, through the test app's cleanup endpoint."""
    if not created_ids:
        return
    removed = 0
    for entry_id in created_ids:
        resp = requests.delete(f"{cleanup_set}({entry_id})", headers=headers, timeout=120)
        if resp.status_code in (200, 204):
            removed += 1
        else:
            print(f"  [WARN] entry {entry_id} not deleted ({resp.status_code}: {resp.text[:120]})")
    check(removed == len(created_ids),
          f"every entry this run created was deleted ({removed}/{len(created_ids)})")


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
