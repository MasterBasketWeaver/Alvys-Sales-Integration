#!/usr/bin/env python3
"""Statement-date end-to-end run: Fleetrock -> Business Central -> Alvys web UI -> BC -> Fleetrock.

    alvys-e2e-statements.py [truck]        truck 7777 (default) or TEST420

Three repair orders are raised in Fleetrock on the truck and posted in Business Central, which
sends three deductions to Alvys. In the Alvys web UI one is paid whole, one is split once and one
is split twice. A split replaces the deduction with two new ones named "<description> (part 1)" and
"(part 2)" by Alvys; below those are called parts. They are paid over three pay periods so that
they land on statements with three different dates:

    period 1   WHOLE, SPLIT part 1, MULTI part 2
    period 2   SPLIT part 2, MULTI part 1 part 1
    period 3   MULTI part 1 part 2

Which statement paid each part is read from the Alvys API and handed to Business Central, whose
poll phase then checks that each part's payment posted on that statement's date and that each
invoice closed, and its Fleetrock repair order was marked paid, on the date its last part was
paid. The Fleetrock paid dates are checked here too, straight from the Fleetrock API.

Alvys pays a deduction only through its web UI, and closes a pay period for a truck once a
statement has been generated in it, so a run uses up three periods on the truck. The periods have
to end on or after the invoices' posting date, or Business Central posts the payment on the invoice
date instead and the dates stop telling the parts apart; with fewer than three such periods left
the run stops before touching Alvys. Periods open up a week at a time.

Nothing rolls back. The repair orders, invoices, deductions and statements stay in all three
systems.
"""
import json
import sys
import time
import urllib.parse
import urllib.request
from datetime import date, datetime

import requests

import alvys_api
import alvys_ui
from bc_auth import get_access_token
from project_paths import PROJECT_ROOT

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = "MCSandbox_061226"
COMPANY = "Texas Transportation Group"
API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/bryana/alvys/v1.0"
BASE_API = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}/api/v2.0"
FLEETROCK = "https://test.fleetrock.com/API"

# The trucks whose deductions can be paid from the Driver Settlements screen, and the owner
# operator each is settled under.
OWNER_OPERATORS = {"7777": "Nat Jimenez", "TEST420": "Adam Test"}

PAID_TIMEOUT_S = 3600


def log(*a):
    print(*a, flush=True)


def die(msg, resp=None):
    log(f"\nERROR: {msg}")
    if resp is not None:
        log(f"  HTTP {resp.status_code}: {resp.text[:1500]}")
    sys.exit(1)


class BC:
    def __init__(self):
        self.h = {"Authorization": f"Bearer {get_access_token(interactive=False)}", "Content-Type": "application/json"}
        r = requests.get(f"{BASE_API}/companies?$filter=name eq '{COMPANY}'", headers=self.h, timeout=120)
        if r.status_code != 200 or not r.json().get("value"):
            die("company lookup", r)
        self.company = r.json()["value"][0]["id"]
        r = requests.get(f"{API}/companies({self.company})/alvysE2eRuns", headers=self.h, timeout=120)
        if r.status_code != 200 or not r.json().get("value"):
            die("e2e run lookup", r)
        self.run_id = r.json()["value"][0]["id"]

    def action(self, name, body=None):
        r = requests.post(f"{API}/companies({self.company})/alvysE2eRuns({self.run_id})/Microsoft.NAV.{name}",
                          headers=self.h, json=body or {}, timeout=1800)
        if r.status_code not in (200, 204):
            die(f"action {name}", r)

    def get(self, entity_set):
        r = requests.get(f"{API}/companies({self.company})/{entity_set}", headers=self.h, timeout=120)
        if r.status_code != 200:
            die(f"read {entity_set}", r)
        return r.json().get("value", [])

    def post(self, entity_set, body):
        r = requests.post(f"{API}/companies({self.company})/{entity_set}", headers=self.h, json=body, timeout=120)
        if r.status_code not in (200, 201):
            die(f"write {entity_set}", r)

    def report(self, phase):
        ok = True
        for res in self.get("alvysTestResults?$orderby=entryNo"):
            passed = (res.get("outcome") or "").lower() == "success"
            ok = ok and passed
            log(f"    [{'PASS' if passed else 'FAIL'}] {res.get('methodName')}")
            if res.get("errorMessage"):
                log(f"           {res['errorMessage'][:900]}")
        if not ok:
            die(f"{phase} phase failed")


def norm(text):
    return " ".join((text or "").split())


def period_end(label):
    """End date of a pay period label: "Sep 14 - 20, 2026", "Sep 28 - Oct 4, 2026" or
    "Dec 29, 2025 - Jan 4, 2026"."""
    start, end = [part.strip() for part in label.split(" - ")]
    if not end[0].isalpha():
        end = start.split()[0] + " " + end
    return datetime.strptime(end, "%b %d, %Y").date()


def cents(amount):
    return round(amount + 1e-9, 2)


def search_all(tok, path, payload):
    items, page = [], 0
    while True:
        status, body = alvys_api.call("POST", path, tok, dict(payload, Page=page, PageSize=100))
        if status != 200:
            die(f"{path} -> {status} {str(body)[:300]}")
        batch = body.get("Items", [])
        items += batch
        if not batch or len(items) >= body.get("Total", 0):
            return items
        page += 1


def group_items(tok, group_id):
    items = search_all(tok, "deductions/search", {"IncludePaid": True, "DateRange": {"Start": "2026-01-01T00:00:00"}})
    return [d for d in items if d.get("GroupId") == group_id]


def wait_for_parts(tok, group_id, count, what):
    deadline = time.time() + 300
    while time.time() < deadline:
        items = group_items(tok, group_id)
        if len(items) == count:
            return items
        time.sleep(10)
    die(f"Alvys never showed {count} deductions in the group of {what}")


def part(items, description):
    for d in items:
        if norm(d.get("Description")) == norm(description):
            return d
    die(f"no deduction described {description!r} in Alvys")


def split(owner, truck, description, first, second, bc):
    log(f"      splitting {norm(description)!r} into {first:.2f} / {second:.2f}")
    alvys_ui.split_deduction(owner, truck, description, first, second)
    # The poll runs between splits so Business Central logs each level of a split as it happens,
    # the way the job queue would, rather than seeing only the final parts.
    bc.action("runSettlementPollAsJobQueue")


def statements_by_line(tok, owner_operator_id):
    statements = search_all(tok, "driver-settlement-statements/search", {
        "DriverId": owner_operator_id,
        "StatementDateRange": {"Start": "2020-01-01T00:00:00Z", "End": "2030-12-31T00:00:00Z"}})
    lines = {}
    for statement in statements:
        for item in statement.get("LineItems", []):
            for sub in item.get("SubLines", []):
                lines[(norm(sub.get("Description")), cents(sub["Amount"]["Amount"]))] = (
                    statement["Number"], statement["StatementDate"])
    return lines


def fleetrock_paid_date(ro_id):
    with open(f"{PROJECT_ROOT}/Fleetrock_credentials.txt") as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    username, api_key = lines[1], lines[4]
    url = f"{FLEETROCK}/GetRO?username={urllib.parse.quote(username)}&token={api_key}&id={ro_id}"
    body = json.load(urllib.request.urlopen(url, timeout=120))
    ro = body.get("repair_orders", [body])[0]
    paid = ro.get("date_invoice_paid") or ""
    return datetime.strptime(paid.split()[0], "%m/%d/%Y").date() if paid else None


def main():
    truck = sys.argv[1] if len(sys.argv) > 1 else "7777"
    if truck not in OWNER_OPERATORS:
        die(f"truck {truck} is not one whose deductions can be paid in the UI; use one of {', '.join(OWNER_OPERATORS)}")
    owner = OWNER_OPERATORS[truck]
    bc = BC()
    tok = alvys_api.token(read_write=False)

    log(f"[1/6] Seeding three repair orders on truck {truck} (owner operator {owner})")
    bc.action("resetChain")
    bc.action("seedStatementCases", {"unitNumber": truck})
    bc.report("seed")
    cases = {c["caseCode"]: c for c in bc.get("alvysE2eStmtCases")}
    if set(cases) != {"WHOLE", "SPLIT", "MULTI"}:
        die(f"the seed phase recorded cases {sorted(cases)}")
    for code, c in cases.items():
        log(f"      {code:5}  RO {c['repairOrderId']}  invoice {c['postedInvoiceNo']} ({c['invoicePostingDate']})  {c['amount']}")

    log("[2/6] Choosing three pay periods")
    invoice_date = max(date.fromisoformat(c["invoicePostingDate"]) for c in cases.values())
    periods = [p for p in alvys_ui.list_pay_periods(owner, truck) if period_end(p) >= invoice_date]
    if len(periods) < 3:
        die(f"truck {truck} has {len(periods)} open pay period(s) ending on or after {invoice_date}: {periods}. "
            "A run needs three; use the other truck, or wait for Alvys to open the next week.")
    periods = sorted(periods, key=period_end)[:3]
    for i, p in enumerate(periods, 1):
        log(f"      period {i}: {p} -> statement date {period_end(p)}")

    log("[3/6] Splitting in the Alvys web UI")
    whole, single, multi = cases["WHOLE"], cases["SPLIT"], cases["MULTI"]
    amount = abs(single["amount"])
    first = cents(amount * 0.6)
    split(owner, truck, single["description"], first, cents(amount - first), bc)
    single_items = wait_for_parts(tok, single["groupId"], 2, "SPLIT")

    amount = abs(multi["amount"])
    first = cents(amount * 0.7)
    split(owner, truck, multi["description"], first, cents(amount - first), bc)
    multi_items = wait_for_parts(tok, multi["groupId"], 2, "MULTI")
    part_one = part(multi_items, multi["description"] + " (part 1)")
    sub = cents(amount * 0.5)
    split(owner, truck, part_one["Description"], sub, cents(first - sub), bc)
    multi_items = wait_for_parts(tok, multi["groupId"], 3, "MULTI part 1")

    leaves = {
        ("WHOLE", 1): whole["description"],
        ("SPLIT", 1): part(single_items, single["description"] + " (part 1)")["Description"],
        ("SPLIT", 2): part(single_items, single["description"] + " (part 2)")["Description"],
        ("MULTI", 1): part(multi_items, multi["description"] + " (part 2)")["Description"],
        ("MULTI", 2): part(multi_items, multi["description"] + " (part 1) (part 1)")["Description"],
        ("MULTI", 3): part(multi_items, multi["description"] + " (part 1) (part 2)")["Description"],
    }
    rounds = {0: [("WHOLE", 1), ("SPLIT", 1), ("MULTI", 1)], 1: [("SPLIT", 2), ("MULTI", 2)], 2: [("MULTI", 3)]}

    log("[4/6] Paying the deductions in the Alvys web UI")
    expected_date = {}
    for i, keys in rounds.items():
        descriptions = [leaves[k] for k in keys]
        log(f"      period {i + 1} ({periods[i]}): {', '.join(norm(d) for d in descriptions)}")
        if not alvys_ui.settle_rows(owner, truck, descriptions, pay_period=periods[i]):
            die(f"could not generate the statement for {periods[i]}")
        for k in keys:
            expected_date[k] = period_end(periods[i])

    log("      waiting for Alvys to mark every deduction paid (seen taking from under a minute to about 30 minutes)")
    amounts = {}
    for k, description in leaves.items():
        group = cases[k[0]]["groupId"]
        amounts[k] = cents(part(group_items(tok, group), description)["Amount"]["Amount"])
    owner_operator_id = whole["ownerOperatorId"]
    deadline = time.time() + PAID_TIMEOUT_S
    while True:
        paid = {k for k, d in leaves.items() if part(group_items(tok, cases[k[0]]["groupId"]), d).get("IsPaid")}
        found = statements_by_line(tok, owner_operator_id)
        on_statement = {k for k, d in leaves.items() if (norm(d), amounts[k]) in found}
        if len(paid) == len(leaves) and len(on_statement) == len(leaves):
            break
        if time.time() > deadline:
            die(f"after {PAID_TIMEOUT_S // 60} minutes {len(paid)} of {len(leaves)} parts are paid and "
                f"{len(on_statement)} on a statement")
        log(f"      ... {len(paid)}/{len(leaves)} paid, {len(on_statement)}/{len(leaves)} on a statement")
        time.sleep(30)

    log("[5/6] Recording the statement Alvys paid each deduction on")
    for k, description in leaves.items():
        number, statement_date = found[(norm(description), amounts[k])]
        if date.fromisoformat(statement_date) != expected_date[k]:
            die(f"{norm(description)!r} landed on statement {number} dated {statement_date}, "
                f"not the {expected_date[k]} period it was settled in")
        log(f"      {norm(description)!r:70} {amounts[k]:>9.2f}  statement {number}  {statement_date}")
        bc.post("alvysE2eStmtLeaves", {"caseCode": k[0], "description": description, "amount": amounts[k],
                                       "expectedStatementNo": number, "expectedStatementDate": statement_date})

    log("[6/6] Polling into Business Central and checking Fleetrock")
    bc.action("pollStatementCases")
    bc.report("poll")
    for c in bc.get("alvysE2eStmtCases"):
        last = max(d for k, d in expected_date.items() if k[0] == c["caseCode"])
        fr_paid = fleetrock_paid_date(c["repairOrderId"])
        if fr_paid != last:
            die(f"Fleetrock repair order {c['repairOrderId']} shows paid {fr_paid}, expected {last}")
        log(f"      {c['caseCode']:5}  invoice {c['postedInvoiceNo']} closed {c['invoiceClosedAt']}  "
            f"Fleetrock RO {c['repairOrderId']} paid {fr_paid}")
    for leaf in bc.get("alvysE2eStmtLeaves"):
        log(f"      {norm(leaf['description'])!r:70} statement {leaf['statementNo']} {leaf['statementDate']}  "
            f"payment posted {leaf['paymentPostingDate']}")
    log("\nStatement-date chain completed.")


if __name__ == "__main__":
    main()
