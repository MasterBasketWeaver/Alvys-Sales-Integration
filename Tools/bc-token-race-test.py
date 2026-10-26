#!/usr/bin/env python3
"""Refresh the Alvys access token from several BC sessions at once and report any that fail.

Usage: bc-token-race-test.py [--sessions N] [--rounds N]

Every Alvys job queue entry refreshes the token when it has expired, so two of them starting
together both save it. A session that saved over a setup row another session had changed since it
read it failed with "Sorry, we just updated this page" (the settlement poll stopped that way in
Production on 2026-10-22). An AL test cannot show this: inside one transaction BC does not raise
the conflict. So each refresh here is its own API call, and therefore its own session, through the
test app's setup API page (89960). Runs in BC_ENV / BC_COMPANY like bc-run-tests.py.
"""
import argparse
import os
import sys
from concurrent.futures import ThreadPoolExecutor

import requests
from bc_auth import get_access_token

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = os.environ.get("BC_ENV", "MCSandbox_09222026")
COMPANY = os.environ.get("BC_COMPANY", "Alvy's Test")
API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/bryana/alvys/v1.0"
BASE_API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/v2.0"

parser = argparse.ArgumentParser()
parser.add_argument("--sessions", type=int, default=6)
parser.add_argument("--rounds", type=int, default=3)
args = parser.parse_args()

headers = {"Authorization": f"Bearer {get_access_token(interactive=False)}",
           "Content-Type": "application/json", "Accept-Encoding": "gzip"}

r = requests.get(f"{BASE_API}/companies?$filter=name eq '{COMPANY.replace("'", "''")}'", headers=headers, timeout=120)
r.raise_for_status()
company_id = r.json()["value"][0]["id"]
r = requests.get(f"{API}/companies({company_id})/alvysSalesSetups", headers=headers, timeout=120)
r.raise_for_status()
setup_id = r.json()["value"][0]["id"]
refresh_url = f"{API}/companies({company_id})/alvysSalesSetups({setup_id})/Microsoft.NAV.refreshAccessToken"


def refresh(_):
    resp = requests.post(refresh_url, headers=headers, json={}, timeout=300)
    if resp.status_code in (200, 204):
        return None
    try:
        return f"HTTP {resp.status_code}: {resp.json()['error']['message']}"
    except Exception:
        return f"HTTP {resp.status_code}: {resp.text[:300]}"


failures = []
for n in range(1, args.rounds + 1):
    with ThreadPoolExecutor(args.sessions) as pool:
        errors = [e for e in pool.map(refresh, range(args.sessions)) if e]
    print(f"round {n}: {args.sessions - len(errors)}/{args.sessions} refreshed", flush=True)
    for e in errors:
        print(f"  {e}", flush=True)
    failures += errors

print(f"\n{ENV} / {COMPANY}: {len(failures)} of {args.sessions * args.rounds} refreshes failed")
sys.exit(1 if failures else 0)
