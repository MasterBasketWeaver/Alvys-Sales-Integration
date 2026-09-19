#!/usr/bin/env python3
"""Playwright helpers for the Alvys web UI.

Alvys will not mark a deduction paid over its API -- deductions/{id} serves GET and DELETE only,
and the token carries no deduction:update scope -- so settling one has to go through the browser.
This drives the Driver Settlements module to do that: approve the deduction into a draft statement
and generate the statement, which is what turns IsPaid over.

The session lives in the .alvysprofile persistent Chromium profile in the project root, signed in
once with "Remember this device for 30 days"; see alvys-login.py when that lapses.
"""
import os
import re

from playwright.sync_api import sync_playwright

from project_paths import PROJECT_ROOT

BASE = PROJECT_ROOT
PROFILE = os.path.join(BASE, ".alvysprofile")
SETTLEMENTS_URL = "https://app.alvys.com/accounting/driver-settlements"


def log(*a):
    print(*a, flush=True)


def open_context(pw, headless=True):
    ctx = pw.chromium.launch_persistent_context(
        PROFILE, headless=headless, viewport={"width": 1900, "height": 1200},
        args=["--disable-blink-features=AutomationControlled"],
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    return ctx, page


def goto_settlements(page, tab="Open"):
    page.goto(SETTLEMENTS_URL, wait_until="domcontentloaded", timeout=120000)
    page.wait_for_timeout(15000)
    if "login" in page.url or "auth0" in page.url:
        raise RuntimeError("Alvys session has expired; run tools/alvys-login.py to sign in again.")
    if tab != "Open":
        page.click(f"text={tab}", timeout=20000)
        page.wait_for_timeout(6000)


ENTITY_ORDER = ["Driver", "Owner Op.", "Truck"]


def set_entity(page, value="Owner Op."):
    """Switch the Driver/Owner Op./Truck selector. It is a button[role=combobox] whose popup
    options are not clickable text nodes, so the choice is made with the keyboard: open it, step
    down to the wanted option, and commit."""
    ctl = page.locator('button[role="combobox"]').first
    if not ctl.count():
        return False
    try:
        current = ctl.inner_text().strip()
        if current.startswith(value.rstrip(".")):
            return True
        steps = ENTITY_ORDER.index(value) - ENTITY_ORDER.index(current if current in ENTITY_ORDER else "Driver")
        ctl.click(timeout=15000)
        page.wait_for_timeout(1800)
        for _ in range(abs(steps)):
            page.keyboard.press("ArrowDown" if steps > 0 else "ArrowUp")
            page.wait_for_timeout(350)
        page.keyboard.press("Enter")
        page.wait_for_timeout(6000)
        return ctl.inner_text().strip().startswith(value.rstrip("."))
    except Exception as e:
        log("[-] set_entity:", str(e).splitlines()[0][:90])
        return False


def show_all_drivers(page, on=True):
    """The toggle is a button[role=switch]; its aria-checked says which way it is set, so this is
    idempotent rather than a blind click."""
    page.keyboard.press("Escape")
    page.wait_for_timeout(700)
    sw = page.locator('button[role="switch"]').first
    if not sw.count():
        return False
    try:
        checked = (sw.get_attribute("aria-checked") or "").lower() == "true"
        if checked != on:
            sw.click(timeout=15000)
            page.wait_for_timeout(6000)
        return True
    except Exception as e:
        log("[-] show_all_drivers:", str(e).splitlines()[0][:90])
        return False


def search(page, term):
    box = page.locator('input[placeholder*="Search truck"]').first
    if not box.count():
        return False
    box.click(timeout=15000)
    box.fill("")
    box.type(str(term), delay=60)
    page.wait_for_timeout(6000)
    return True


def page_text(page):
    try:
        return " ".join(page.evaluate("() => document.body ? document.body.innerText : ''").split())
    except Exception:
        return ""


def open_row(page, name):
    """Open the settlement view for the named driver / owner operator from the grid."""
    row = page.locator(f'text="{name}"').last
    row.click(timeout=20000)
    page.wait_for_timeout(12000)
    return True


def click_visible_text(page, text, parent_levels=1, timeout_ms=20000):
    """Click the on-screen element whose own text is exactly `text`.

    The settlement modal needs this for its truck tabs: they are divs rather than buttons, the text
    node itself carries pointer-events-none so the click has to land on an ancestor, and the toolbar
    keeps an invisible measurement copy of every tab parked at left:-9999px that ordinary selectors
    match first. So the visible node is found by geometry and clicked by coordinate.
    """
    box = page.evaluate(
        """([txt, levels]) => {
            for (const el of document.querySelectorAll('*')) {
                const own = Array.from(el.childNodes).filter(n => n.nodeType === 3)
                    .map(n => n.textContent.trim()).join('');
                if (own !== txt) continue;
                let e = el;
                for (let i = 0; i < levels && e.parentElement; i++) e = e.parentElement;
                const r = e.getBoundingClientRect();
                if (r.width > 0 && r.height > 0 && r.x > 0 && r.y > 0) {
                    return {x: r.x + r.width / 2, y: r.y + r.height / 2};
                }
            }
            return null;
        }""",
        [text, parent_levels],
    )
    if not box:
        return False
    page.mouse.click(box["x"], box["y"])
    page.wait_for_timeout(1500)
    return True


def select_truck(page, truck):
    ok = click_visible_text(page, f"Truck #{truck}")
    page.wait_for_timeout(9000)
    return ok


def modal_tab(page, name):
    """Click one of the modal's Open/Draft/Statements/Errors tabs. The page behind the modal has
    tabs by the same name, so only an enabled one inside the modal is taken."""
    tabs = page.locator(f'button[role="tab"]:has-text("{name}")')
    for i in range(tabs.count()):
        t = tabs.nth(i)
        try:
            if t.is_enabled() and t.is_visible():
                t.click(timeout=15000)
                page.wait_for_timeout(8000)
                return True
        except Exception:
            continue
    return False


def select_all(page):
    return click_visible_text(page, "Select All")


def approve(page):
    """Click the Approve button. Its label carries the selected count ("Approve 3 Items"), so it is
    matched by prefix rather than exact text."""
    btn = page.locator('button:has-text("Approve")').first
    if not btn.count():
        return False
    btn.click(timeout=20000)
    page.wait_for_timeout(12000)
    return True


def generate_statement(page):
    """Generate the draft statement. This is the step that turns the deduction's IsPaid over in
    Alvys, and so the only thing that gives the settlement poll anything to find.

    Two clicks: the button on the draft, then Generate in the confirmation dialog that lists which
    truck statements will be produced. The dialog's button is matched exactly, or it would also
    match the "Generate Statement" button behind it.
    """
    btn = page.locator('button:has-text("Generate Statement")').first
    if not btn.count():
        log("[-] no Generate Statement button on the draft")
        return False
    btn.click(timeout=20000)
    page.wait_for_timeout(4000)

    confirm = page.get_by_role("button", name="Generate", exact=True)
    if confirm.count():
        confirm.first.click(timeout=20000)
    else:
        log("[-] no confirmation dialog appeared")
        return False
    page.wait_for_timeout(20000)
    return True


def row_element(page, description, selector):
    """Click `selector` in the Open-tab row whose description cell reads `description`.

    The tab is an AG Grid whose pinned columns sit in separate containers, so one visible row is
    several [role=row] elements sharing a row-index, found here within the description cell's own
    grid. The click is dispatched from the page because the grid's invisible horizontal-scroll
    spacer sits over the pinned column and swallows a real mouse click.
    """
    return page.evaluate(
        """([desc, sel]) => {
            // Alvys keeps the double space before a split part's "(part n)"; the page collapses it.
            const norm = t => t.replace(/\\s+/g, ' ').trim();
            for (const cell of document.querySelectorAll('[role=dialog] [role=gridcell]')) {
                if (norm(cell.innerText) !== norm(desc)) continue;
                const row = cell.closest('[role=row][row-index]');
                const grid = cell.closest('.ag-root');
                if (!row || !grid) continue;
                const idx = row.getAttribute('row-index');
                for (const r of grid.querySelectorAll(`[role=row][row-index="${idx}"]`)) {
                    const el = r.querySelector(sel);
                    if (el) { el.click(); return true; }
                }
            }
            return false;
        }""",
        [description, selector],
    )


def click_in_row(page, description, selector, attempts=5):
    """The grid fills in a few seconds after the tab opens, so a row not there yet is retried."""
    for _ in range(attempts):
        if row_element(page, description, selector):
            return True
        page.wait_for_timeout(3000)
    return False


def open_row_menu(page, description):
    if not click_in_row(page, description, 'button[aria-label="Open context menu"]'):
        return False
    page.wait_for_timeout(1500)
    return True


def split_row(page, description, first_amount, second_amount):
    """Split an open deduction in two. Alvys takes the parts as positive amounts even for a
    deduction, and names them "<description> (part 1)" and "(part 2)"."""
    if not open_row_menu(page, description):
        raise RuntimeError(f"no open row described {description!r}")
    page.get_by_role("menuitem", name="Split").click(timeout=15000)
    page.wait_for_timeout(2500)
    for name, amount in (("split1Amount", first_amount), ("split2Amount", second_amount)):
        box = page.locator(f'input[name="{name}"]')
        box.click(timeout=15000)
        box.fill(f"{abs(amount):.2f}")
    page.get_by_role("button", name="Save", exact=True).click(timeout=15000)
    page.wait_for_timeout(10000)


def select_rows(page, descriptions):
    for description in descriptions:
        if not click_in_row(page, description, 'input[type=checkbox]'):
            raise RuntimeError(f"no open row described {description!r}")
        page.wait_for_timeout(800)


def open_truck(page, driver_name, truck_number):
    goto_settlements(page)
    if not show_all_drivers(page):
        raise RuntimeError("could not turn on Show all drivers")
    if not set_entity(page):
        raise RuntimeError("could not switch the grid to Owner Op.")
    if not search(page, driver_name):
        raise RuntimeError("could not find the settlements search box")
    open_row(page, driver_name)
    if not select_truck(page, truck_number):
        raise RuntimeError(f"no Truck #{truck_number} tab for {driver_name}")
    if not modal_tab(page, "Open"):
        raise RuntimeError("could not open the Open tab")


def pay_period_picker(page):
    """The Open tab's pay-period dropdown, a combobox whose label is the selected period."""
    return page.locator('[role=dialog] button[role=combobox]').filter(has_text=re.compile(r"\d{4}")).last


def pay_periods(page):
    """The pay periods the truck can still be settled into, oldest first. Alvys closes a period for
    a truck once a statement has been generated in it, and offers only a week or two ahead."""
    picker = pay_period_picker(page)
    picker.click(timeout=15000)
    page.wait_for_timeout(2500)
    options = page.evaluate("() => Array.from(document.querySelectorAll('[role=option]')).map(e => e.innerText.trim())")
    page.keyboard.press("Escape")
    page.wait_for_timeout(1000)
    return options


def select_pay_period(page, label):
    picker = pay_period_picker(page)
    if picker.inner_text().strip() == label:
        return
    picker.click(timeout=15000)
    page.wait_for_timeout(2500)
    page.get_by_role("option", name=label, exact=True).click(timeout=15000)
    page.wait_for_timeout(8000)
    if picker.inner_text().strip() != label:
        raise RuntimeError(f"could not select pay period {label!r}")


def list_pay_periods(driver_name, truck_number, headless=True):
    with sync_playwright() as p:
        ctx, page = open_context(p, headless)
        try:
            open_truck(page, driver_name, truck_number)
            return pay_periods(page)
        finally:
            ctx.close()


def split_deduction(driver_name, truck_number, description, first_amount, second_amount, headless=True):
    with sync_playwright() as p:
        ctx, page = open_context(p, headless)
        try:
            open_truck(page, driver_name, truck_number)
            split_row(page, description, first_amount, second_amount)
        finally:
            ctx.close()


def settle_rows(driver_name, truck_number, descriptions, pay_period=None, headless=True):
    """Settle only the named open deductions, leaving the rest of the truck's Open tab alone, on a
    statement for the pay period given, or the one the tab offers first."""
    with sync_playwright() as p:
        ctx, page = open_context(p, headless)
        try:
            open_truck(page, driver_name, truck_number)
            if pay_period:
                select_pay_period(page, pay_period)
            select_rows(page, descriptions)
            if not approve(page):
                raise RuntimeError("could not approve the selected items")
            modal_tab(page, "Draft")
            # One click only: a statement can sit queued for half an hour with its rows still
            # showing in the draft, and clicking again then would risk generating it twice.
            return generate_statement(page)
        finally:
            ctx.close()


def settle_truck_deductions(driver_name, truck_number, headless=True):
    """Settle every open deduction on one truck: approve them into a draft statement and generate
    it. Generating is what turns IsPaid over in Alvys, and Alvys takes up to a minute to get there,
    so callers should wait on the deduction rather than trust the click -- see
    alvys_api.wait_until_paid.
    """
    with sync_playwright() as p:
        ctx, page = open_context(p, headless)
        try:
            goto_settlements(page)
            if not show_all_drivers(page):
                raise RuntimeError("could not turn on Show all drivers")
            if not set_entity(page):
                raise RuntimeError("could not switch the grid to Owner Op.")
            if not search(page, driver_name):
                raise RuntimeError("could not find the settlements search box")
            open_row(page, driver_name)
            if not select_truck(page, truck_number):
                raise RuntimeError(f"no Truck #{truck_number} tab for {driver_name}")
            if not modal_tab(page, "Open"):
                raise RuntimeError("could not open the Open tab")
            if not select_all(page):
                raise RuntimeError("nothing to select on the Open tab")
            if not approve(page):
                raise RuntimeError("could not approve the selected items")
            modal_tab(page, "Draft")
            return generate_statement(page)
        finally:
            ctx.close()
