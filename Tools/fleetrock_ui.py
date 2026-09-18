#!/usr/bin/env python3
"""Playwright helpers for the Fleetrock web UI.

Fleetrock's API will not set tax on a repair order: AddRO and UpdateRO both accept
labor_tax_rate, part_tax_rate and additional_charges_tax_rate, report success, and leave them
at zero, and there is no task or part level endpoint. The UI is the only way to enter a tax
rate, so a taxed repair order for the import tests has to be created through the browser.

The session lives in the .frprofile persistent Chromium profile in the project root, signed in
from the customer account in Fleetrock_credentials.txt.
"""
import os
import re

from project_paths import PROJECT_ROOT

BASE = PROJECT_ROOT
PROFILE = os.path.join(BASE, ".frprofile")
CREDS = os.path.join(BASE, "Fleetrock_credentials.txt")
ROOT_URL = "https://test.fleetrock.com"


def log(*a):
    print(*a, flush=True)


def read_customer_creds():
    """The customer account's web username and password, the first two values in the file."""
    with open(CREDS) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    return lines[1], lines[2]


def open_context(pw, headless=True):
    ctx = pw.chromium.launch_persistent_context(
        PROFILE, headless=headless, viewport={"width": 1900, "height": 1200},
        args=["--disable-blink-features=AutomationControlled"],
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    return ctx, page


def signed_in(page):
    return "signin" not in page.url.lower() and "login" not in page.url.lower()


def sign_in(page):
    """Signs the customer account in. The form is WebForms, so the fields are addressed by their
    generated ids, and Remember Me is ticked so the profile keeps the session."""
    user, pwd = read_customer_creds()
    page.goto(ROOT_URL + "/signin", wait_until="domcontentloaded", timeout=120000)
    page.wait_for_timeout(4000)
    page.fill("#MainContent_Username", user)
    page.fill("#MainContent_Password", pwd)
    try:
        page.check("#RememberMeClient", timeout=5000)
    except Exception:
        pass
    page.click("#MainContent_ButtonLogIn")
    page.wait_for_timeout(12000)
    if not signed_in(page):
        raise RuntimeError(f"Fleetrock sign-in did not leave the sign-in page; at {page.url}")
    return page.url


def open_signed_in(pw, headless=True):
    """A context already signed in, signing in only when the saved session has lapsed."""
    ctx, page = open_context(pw, headless=headless)
    page.goto(ROOT_URL + "/signin", wait_until="domcontentloaded", timeout=120000)
    page.wait_for_timeout(5000)
    if not signed_in(page):
        sign_in(page)
    return ctx, page


CREATE_RO_URL = ROOT_URL + "/Account/RepairOrders/Create"


def create_repair_order(page, unit_number):
    """Creates a repair order for a unit and returns its Fleetrock Id.

    The Create page opens a modal with a Unit # dropdown; the Id lands in the query string of
    the page it leaves you on.
    """
    page.goto(CREATE_RO_URL, wait_until="domcontentloaded", timeout=120000)
    page.wait_for_timeout(8000)
    page.click("text=None")
    page.wait_for_timeout(2500)
    page.locator("li a").filter(has_text=unit_number).first.click()
    page.wait_for_timeout(2000)
    page.click("#MainContent_ButtonRO1")
    page.wait_for_timeout(18000)
    match = re.search(r"[?&]ID=(\d+)", page.url)
    if not match:
        raise RuntimeError(f"no repair order id in {page.url}")
    return match.group(1)


def add_taxed_task(page, ro_id, complaint, labor_rate, labor_hours, tax_rate):
    """Adds a labor task carrying a tax rate, which is the part the API cannot do.

    Labor Tax is a percentage and the field is prefilled with the account's default, so it is
    overwritten rather than appended to.
    """
    page.goto(f"{CREATE_RO_URL}?ID={ro_id}", wait_until="domcontentloaded", timeout=120000)
    page.wait_for_timeout(9000)
    page.click("text=Add Task")
    page.wait_for_timeout(6000)
    page.fill("#MainContent_TextBoxComplaint", complaint)
    page.fill("#MainContent_TBLaborPriceEdit", str(labor_rate))
    page.fill("#MainContent_TBLaborTaxEdit", str(tax_rate))
    page.fill("#MainContent_TextBoxLaborHours", str(labor_hours))
    page.click("#MainContent_ButtonAddTask")
    page.wait_for_timeout(15000)
    return summary_totals(page)


def summary_totals(page):
    """The Summary panel's totals, keyed by their label."""
    totals = {}
    for line in page.inner_text("body").split("\n"):
        for label in ("Labor Total", "Parts Total", "Tax Total", "Grand Total"):
            if line.strip().startswith(label):
                totals[label] = line.split("$")[-1].strip()
    return totals
