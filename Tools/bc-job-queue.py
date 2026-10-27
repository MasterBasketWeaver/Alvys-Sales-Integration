#!/usr/bin/env python3
"""Show, hold or resume the Alvys job queue entries (codeunits 80800..80849) in one company.

Usage: bc-job-queue.py show|hold|resume [--company NAME]
       BC_ENV picks the environment (default MCSandbox_09222026); the company defaults to
       Texas Transportation Group.

hold sets every Ready entry On Hold and records which ones it changed; resume sets only those
back to Ready, so an entry someone had put On Hold on purpose stays that way. Exits non-zero
when an entry does not end up in the expected status.

BC has no API for job queue entries, so this drives page 672 in the web client (headless, the
.bcprofile session, signing in again from `cred` when it has expired).
"""
import json
import os
import re
import sys
import time
import urllib.parse

from playwright.sync_api import sync_playwright

import bc_session
from project_paths import PROJECT_ROOT

OBJECT_IDS = "80800..80849"
STATUSES = ("Ready", "On Hold", "In Process", "Error", "Finished", "On Hold with Inactivity Timeout")

args = sys.argv[1:]
company = "Texas Transportation Group"
if "--company" in args:
    i = args.index("--company")
    company = args[i + 1]
    del args[i:i + 2]
if len(args) != 1 or args[0] not in ("show", "hold", "resume"):
    sys.exit(__doc__)
action = args[0]

STATE = os.path.join(PROJECT_ROOT, "held-job-queues.json")
state_key = f"{bc_session.ENV}/{company}"
filter_ = f"'Object ID to Run' IS '{OBJECT_IDS}'"
URL = (f"https://businesscentral.dynamics.com/{bc_session.TENANT}/{bc_session.ENV}"
       f"?company={urllib.parse.quote(company)}&page=672&filter={urllib.parse.quote(filter_)}")


def load_state():
    try:
        with open(STATE) as f:
            return json.load(f)
    except FileNotFoundError:
        return {}


def save_state(state):
    with open(STATE, "w") as f:
        json.dump(state, f, indent=2)


def content_frame(page):
    best, size = page.main_frame, 0
    for fr in page.frames:
        try:
            n = len(fr.inner_text("body", timeout=3000))
        except Exception:
            continue
        if n > size:
            best, size = fr, n
    return best


def dismiss_interruptions(fr):
    # "We had trouble completing the request" (Retry) and "We paused while you were away" (Refresh).
    for label in ("Retry", "Refresh"):
        b = fr.get_by_role("button", name=label)
        if b.count() and b.first.is_visible():
            b.first.click()
            time.sleep(5)
            return True
    return False


def read_entries(fr):
    """{(object id, description): (row index, status)} for the grid's job queue rows."""
    # The header row is repeated (a hidden sticky copy); the first occurrence lines up with the cells.
    column = {}
    ths = fr.locator("table thead th")
    for i in range(ths.count()):
        abbr = ths.nth(i).get_attribute("abbr")
        if abbr and abbr not in column:
            column[abbr] = i
    if not {"Status", "Object ID to Run", "Description"} <= set(column):
        return {}
    entries = {}
    trs = fr.locator("table tbody tr")
    for i in range(trs.count()):
        tds = trs.nth(i).locator("td")
        cell = lambda name: tds.nth(column[name]).inner_text().strip() if tds.count() > column[name] else ""
        object_id, status = cell("Object ID to Run"), cell("Status")
        if re.fullmatch(r"808[0-4]\d", object_id) and status in STATUSES:
            earliest = cell("Earliest Start Date/Time") if "Earliest Start Date/Time" in column else ""
            entries[(object_id, cell("Description"))] = (i, status, earliest)
    return entries


def load_grid(page, timeout_s=120):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        time.sleep(5)
        fr = content_frame(page)
        if dismiss_interruptions(fr):
            continue
        body = fr.inner_text("body", timeout=5000)
        if read_entries(fr) or "(There is nothing to show in this view)" in body:
            time.sleep(3)
            return fr
    raise RuntimeError("page 672 did not show the job queue entries")


def set_status(fr, row, object_id, menu_item):
    tr = fr.locator("table tbody tr").nth(row)
    # Select the row through its object id cell: the first column is a hidden selector and the
    # status column opens the card.
    tr.locator("td").filter(has_text=re.compile(rf"^\s*{object_id}\s*$")).first.click()
    time.sleep(2)
    fr.get_by_role("menuitem", name=menu_item).first.click()
    time.sleep(6)


def show(entries, label):
    if not entries:
        print(f"  {label}: no Alvys job queue entries")
    for (object_id, description), (_, status, earliest) in sorted(entries.items()):
        print(f"  {label}: {object_id} {description}: {status} (earliest start {earliest or 'blank'}, user's time zone)")


with sync_playwright() as pw:
    ctx = pw.chromium.launch_persistent_context(bc_session.PROFILE, headless=True, viewport={"width": 2400, "height": 1000},
                                                args=["--disable-blink-features=AutomationControlled"])
    try:
        page = ctx.pages[0] if ctx.pages else ctx.new_page()
        page.goto(URL, wait_until="commit", timeout=120000)
        time.sleep(8)
        if bc_session._at_login(page):
            bc_session.do_login(page)
            page.goto(URL, wait_until="commit", timeout=120000)
        fr = load_grid(page)
        before = read_entries(fr)
        print(f"Alvys job queue entries in {bc_session.ENV} / {company}:")
        show(before, "before")
        if action == "show":
            sys.exit(0)

        state = load_state()
        if action == "hold":
            targets = [key for key, (_, status, _) in before.items() if status == "Ready"]
            menu_item, wanted = "Set On Hold", "On Hold"
            # Keep entries an earlier hold recorded and has not resumed yet.
            state[state_key] = sorted({tuple(k) for k in state.get(state_key, [])} | set(targets))
        else:
            targets = [tuple(k) for k in state.get(state_key, []) if tuple(k) in before and before[tuple(k)][1] == "On Hold"]
            menu_item, wanted = "Set Status to Ready", "Ready"
            missing = [tuple(k) for k in state.get(state_key, []) if tuple(k) not in before]
            for key in missing:
                print(f"  recorded entry no longer on the page: {key[0]} {key[1]}")
        save_state(state)

        for key in targets:
            set_status(fr, before[key][0], key[0], menu_item)
            fr = content_frame(page)

        page.reload(wait_until="commit")
        fr = load_grid(page)
        after = read_entries(fr)
        show(after, "after")
        failed = [key for key in targets if after.get(key, (None, None, None))[1] != wanted]
        if action == "resume" and not failed:
            state.pop(state_key, None)
            save_state(state)
        if failed:
            sys.exit(f"ERROR: not {wanted}: " + ", ".join(f"{k[0]} {k[1]}" for k in failed))
        print(f"{len(targets)} entr{'y' if len(targets) == 1 else 'ies'} set to {wanted}.")
    finally:
        ctx.close()
