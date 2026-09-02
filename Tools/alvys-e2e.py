#!/usr/bin/env python3
"""Drive the chained Alvys end-to-end test: Fleetrock -> Business Central -> Alvys -> back again.

    alvys-e2e.py [manual|jobqueue|both]      (default: both)
    alvys-e2e.py resume                      poll only, for a chain already settled in Alvys
    alvys-e2e.py reset                       clear the run and empty the Alvys payment journal

The chain cannot run as one Business Central test. Alvys will not mark a deduction paid over its
API -- deductions/{id} serves GET and DELETE only, and the token carries no deduction:update scope
-- so the settlement has to happen in the Alvys web UI, and an AL test cannot stop and wait for
that. So this script runs it in three steps:

    1. seed   POST alvysE2eRuns/Microsoft.NAV.seed{Manual,JobQueue}
              Creates a repair order in Fleetrock, imports it, posts it, and checks the deduction
              reached Alvys unpaid. What it produced is read back off the entity.
    2. settle Approves that truck's deductions into a draft statement in the Alvys UI and
              generates it, which is what turns IsPaid over. Then waits for Alvys to catch up.
    3. poll   POST alvysE2eRuns/Microsoft.NAV.poll
              Runs the settlement poll the way this run was seeded for -- called directly for
              Manual, through the codeunit's OnRun for Job Queue -- and checks the settlement paid
              off the very invoice the chain started from.

Both poll modes are run by default, one chain each: a settled deduction can only be applied once,
so a single chain cannot exercise both.

Nothing rolls back. The invoice, the deduction and the repair order stay in all three systems.
"""
import sys

import requests

import alvys_api
from alvys_ui import settle_truck_deductions
from bc_auth import get_access_token

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = "MCSandbox_061226"
COMPANY = "Texas Transportation Group"
API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/bryana/alvys/v1.0"
BASE_API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/v2.0"

# The owner operator the seeded truck belongs to in Alvys. The deduction names the truck, and the
# settlement is run from the owner operator's row, so the two are looked up together.
OWNER_OPERATOR = "Adam Test"

MODES = {"manual": ("seedManual", "Manual"), "jobqueue": ("seedJobQueue", "Job Queue")}


def die(msg, resp=None):
    print(f"\nERROR: {msg}")
    if resp is not None:
        print(f"  HTTP {resp.status_code}: {resp.text[:1500]}")
    sys.exit(1)


class BC:
    def __init__(self):
        self.h = {"Authorization": f"Bearer {get_access_token()}", "Content-Type": "application/json"}
        r = requests.get(f"{BASE_API}/companies?$filter=name eq '{COMPANY}'", headers=self.h, timeout=120)
        if r.status_code != 200:
            die("company lookup", r)
        companies = r.json().get("value", [])
        if not companies:
            die(f"company '{COMPANY}' not found in {ENV}")
        self.company = companies[0]["id"]
        self.run_id = self._run_id()

    def _run_id(self):
        r = requests.get(f"{API}/companies({self.company})/alvysE2eRuns", headers=self.h, timeout=120)
        if r.status_code != 200:
            die("e2e run lookup", r)
        rows = r.json().get("value", [])
        if not rows:
            die("alvysE2eRuns returned no singleton")
        return rows[0]["id"]

    def action(self, name):
        r = requests.post(
            f"{API}/companies({self.company})/alvysE2eRuns({self.run_id})/Microsoft.NAV.{name}",
            headers=self.h, json={}, timeout=1800)
        if r.status_code not in (200, 204):
            die(f"action {name}", r)

    def run(self):
        r = requests.get(f"{API}/companies({self.company})/alvysE2eRuns({self.run_id})",
                         headers=self.h, timeout=120)
        if r.status_code != 200:
            die("e2e run read", r)
        return r.json()

    def results(self):
        r = requests.get(f"{API}/companies({self.company})/alvysTestResults?$orderby=entryNo",
                         headers=self.h, timeout=120)
        if r.status_code != 200:
            die("results read", r)
        return r.json().get("value", [])


def report(bc, phase):
    ok = True
    for res in bc.results():
        outcome = (res.get("outcome") or "").lower()
        mark = "PASS" if outcome == "success" else "FAIL"
        if outcome != "success":
            ok = False
        print(f"    [{mark}] {res.get('methodName')}")
        if res.get("errorMessage"):
            print(f"           {res['errorMessage'][:900]}")
    if not ok:
        die(f"{phase} phase failed")
    return ok


def run_chain(bc, mode):
    seed_action, label = MODES[mode]
    print(f"\n{'=' * 72}\n{label} poll\n{'=' * 72}")

    # Every chain starts from a clean payment journal: a previous chain that failed after applying
    # its settlement leaves a line behind, and posting the batch would post that too.
    print(f"[0/3] Resetting the run and clearing the Alvys payment journal")
    bc.action("resetChain")

    print(f"[1/3] Seeding: Fleetrock repair order -> BC invoice -> Alvys deduction")
    bc.action(seed_action)
    report(bc, "seed")
    run = bc.run()
    deduction_id = run.get("deductionId")
    truck = run.get("truckNumber")
    print(f"      repair order {run.get('repairOrderId')}")
    print(f"      posted invoice {run.get('postedInvoiceNo')}  amount {run.get('amount')}")
    print(f"      deduction {deduction_id} on truck #{truck}")
    if not deduction_id or not truck:
        die("the seed phase recorded no deduction to settle")

    print(f"[2/3] Settling deduction in the Alvys web UI (owner operator {OWNER_OPERATOR}, truck #{truck})")
    if not settle_truck_deductions(OWNER_OPERATOR, truck):
        die("could not generate the settlement statement in the Alvys UI")
    print("      statement generated; waiting for Alvys to mark the deduction paid")
    if not alvys_api.wait_until_paid(deduction_id, log=print):
        die(f"Alvys did not mark deduction {deduction_id} paid in time")
    print("      deduction is settled in Alvys")

    print(f"[3/3] Polling the settlement back into Business Central ({label})")
    bc.action("poll")
    report(bc, "poll")
    run = bc.run()
    print(f"      invoice {run.get('postedInvoiceNo')}: remaining {run.get('invoiceRemainingAmount')}, "
          f"closed={run.get('invoiceClosed')}")
    return run


def resume(bc):
    """Finish a chain whose deduction is already settled in Alvys. Generating a statement can leave
    it Queued for a long time, so a run that timed out waiting is picked up here rather than seeding
    a second repair order."""
    run = bc.run()
    deduction_id = run.get("deductionId")
    if not deduction_id:
        die("no chain to resume; the run singleton has no deduction")
    print(f"Resuming chain: deduction {deduction_id}, invoice {run.get('postedInvoiceNo')}")
    if not alvys_api.is_paid(deduction_id):
        die(f"deduction {deduction_id} is still not settled in Alvys")
    label = "Job Queue" if run.get("pollMode") in ("Job Queue", "Job_Queue", 1) else "Manual"
    print(f"[3/3] Polling the settlement back into Business Central ({label})")
    bc.action("poll")
    report(bc, "poll")
    run = bc.run()
    print(f"      invoice {run.get('postedInvoiceNo')}: remaining {run.get('invoiceRemainingAmount')}, "
          f"closed={run.get('invoiceClosed')}")
    return [(label, run)]


def main():
    which = (sys.argv[1] if len(sys.argv) > 1 else "both").lower()
    if which == "reset":
        BC().action("resetChain")
        print("Run cleared and the Alvys payment journal emptied.")
        return
    if which == "resume":
        bc = BC()
        finished = resume(bc)
        print(f"\n{'=' * 72}\nSummary\n{'=' * 72}")
        for label, run in finished:
            print(f"  {label:10} invoice {run.get('postedInvoiceNo'):>14}  "
                  f"remaining {str(run.get('invoiceRemainingAmount')):>6}  closed={run.get('invoiceClosed')}")
        return
    modes = list(MODES) if which == "both" else [which]
    for m in modes:
        if m not in MODES:
            die(f"unknown mode '{m}'; use manual, jobqueue or both")

    bc = BC()
    finished = []
    for m in modes:
        finished.append((MODES[m][1], run_chain(bc, m)))

    print(f"\n{'=' * 72}\nSummary\n{'=' * 72}")
    for label, run in finished:
        print(f"  {label:10} invoice {run.get('postedInvoiceNo'):>14}  "
              f"remaining {str(run.get('invoiceRemainingAmount')):>6}  closed={run.get('invoiceClosed')}")
    print("\nAll chains completed.")


if __name__ == "__main__":
    main()
