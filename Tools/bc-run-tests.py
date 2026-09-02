#!/usr/bin/env python3
"""Run the Alvys test suite through the test-run API page (80852) and print the results.

Usage: bc-run-tests.py [--keep-data]

The run is synchronous: the POST returns once every test has finished. Per-method detail is
then read back from the alvysTestResults entity (page 80853). No browser involved -- this is
the way to run the suite; do not drive page 80851 in the web client.
"""
import sys

import requests
from bc_auth import get_access_token

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = "MCSandbox_061226"
COMPANY = "Texas Transportation Group"
API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/bryana/alvys/v1.0"
BASE_API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/v2.0"

keep_data = "--keep-data" in sys.argv
action = "runKeepData" if keep_data else "run"

token = get_access_token()
headers = {"Authorization": f"Bearer {token}", "Content-Type": "application/json"}


def die(resp, what):
    print(f"ERROR: {what} failed (HTTP {resp.status_code})")
    print(resp.text[:2000])
    sys.exit(1)


# --- Company id ---
r = requests.get(f"{BASE_API}/companies?$filter=name eq '{COMPANY}'", headers=headers, timeout=120)
if r.status_code != 200:
    die(r, "company lookup")
companies = r.json().get("value", [])
if not companies:
    print(f"ERROR: company '{COMPANY}' not found in {ENV}.")
    sys.exit(1)
company_id = companies[0]["id"]

# --- Test run singleton key ---
r = requests.get(f"{API}/companies({company_id})/alvysTestRuns", headers=headers, timeout=120)
if r.status_code != 200:
    die(r, "test run lookup")
runs = r.json().get("value", [])
if not runs:
    print("ERROR: no test run singleton returned by alvysTestRuns.")
    sys.exit(1)
run_id = runs[0]["id"]

# --- Run (synchronous; the suite takes a while, so allow a long read timeout) ---
print(f"Running suite via {action} in {COMPANY}...")
r = requests.post(
    f"{API}/companies({company_id})/alvysTestRuns({run_id})/Microsoft.NAV.{action}",
    headers=headers, json={}, timeout=1800,
)
if r.status_code not in (200, 204):
    die(r, "test run")

# --- Summary ---
r = requests.get(f"{API}/companies({company_id})/alvysTestRuns({run_id})", headers=headers, timeout=120)
if r.status_code != 200:
    die(r, "summary read")
s = r.json()
print(f"\nTests run:  {s.get('testsRun')}")
print(f"Successful: {s.get('successful')}")
print(f"Failed:     {s.get('failed')}")
print(f"Duration:   {s.get('duration')}")

# --- Per-method detail ---
r = requests.get(
    f"{API}/companies({company_id})/alvysTestResults?$orderby=entryNo",
    headers=headers, timeout=120,
)
if r.status_code != 200:
    die(r, "results read")
results = r.json().get("value", [])

print()
for t in results:
    mark = "PASS" if t.get("outcome") == "Success" else "FAIL"
    print(f"  [{mark}] {t.get('codeunitName')} :: {t.get('methodName')}  ({t.get('duration')})")
    if t.get("errorMessage"):
        print(f"         {t['errorMessage']}")

sys.exit(1 if s.get("failed") else 0)
