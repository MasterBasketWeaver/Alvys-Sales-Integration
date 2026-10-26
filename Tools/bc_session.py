#!/usr/bin/env python3
"""Shared BC sandbox browser session helpers.

The signed-in session lives in the Chromium profile at .bcprofile. No 2FA is required
for this account, so expiry is handled automatically: any script calling open_page()
re-authenticates from `cred` (tanager-bc-user, tanager-bc-password: bcadmin@dd-transport.com,
the BC login the Tanager tooling in ~/work/clients/tanager uses) without user interaction.
"""
import os
import subprocess
import time

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = os.environ.get("BC_ENV", "MCSandbox_09222026")
# These scripts live in the repo, but the browser profile, credentials and any screenshots
# they write belong to the project root above it, which is not version controlled.
from project_paths import PROJECT_ROOT, TOOLS

BASE = PROJECT_ROOT
PROFILE = os.path.join(BASE, ".bcprofile")


def log(*a):
    print(*a, flush=True)


def page_url(page_id):
    return f"https://businesscentral.dynamics.com/{TENANT}/{ENV}?page={page_id}"


def cred_get(name):
    """A secret from `cred` (~/.local/bin/cred, systemd-creds for this user)."""
    return subprocess.run(["cred", "get", name], capture_output=True, text=True, check=True).stdout.rstrip("\n")


def read_creds():
    return cred_get("tanager-bc-user"), cred_get("tanager-bc-password")


def _at_login(page):
    return "login.microsoftonline.com" in page.url or "login.live.com" in page.url


def _visible(page, selector):
    loc = page.locator(selector)
    for i in range(loc.count()):
        if loc.nth(i).is_visible():
            return loc.nth(i)
    return None


def do_login(page):
    """Run the username/password flow. This account has no 2FA.

    The steps come in any order: "Pick an account" when the profile remembers one (a saved tile
    can lead back to the email step, so take "Use another account"), the email page keeps a
    hidden password input, and "Stay signed in?" -> Yes keeps the session in the profile."""
    user, pwd = read_creds()
    log("[auth] session expired or absent - signing in automatically...")
    password_sent = False
    deadline = time.time() + 240
    while time.time() < deadline and _at_login(page):
        try:
            body = page.inner_text("body", timeout=5000)
        except Exception:
            time.sleep(2)
            continue
        if "password is incorrect" in body:
            raise RuntimeError("Microsoft rejected the tanager-bc password in cred")
        if "Pick an account" in body:
            page.get_by_text("Use another account").first.click()
        elif "Stay signed in" in body:
            page.locator('#idSIButton9, input[type="submit"][value="Yes"], button:has-text("Yes")').first.click()
        elif "keep your account secure" in body:
            page.get_by_text("Not now").first.click()
        elif not password_sent and _visible(page, 'input[type="password"]'):
            _visible(page, 'input[type="password"]').fill(pwd)
            _visible(page, 'input[type="submit"], button:has-text("Sign in")').click()
            password_sent = True
        elif _visible(page, 'input[type="email"], input[name="loginfmt"]'):
            _visible(page, 'input[type="email"], input[name="loginfmt"]').fill(user)
            _visible(page, 'input[type="submit"], button[type="submit"]').click()
        time.sleep(3)

    if "businesscentral.dynamics.com" not in page.url:
        raise RuntimeError(f"sign-in did not reach BC; at {page.url}")
    log("[auth] signed in.")


def open_page(pw, page_id, headless=True, render_ms=22000):
    """Open a BC page, logging in automatically if the saved session has expired.

    Returns (context, page).
    """
    ctx = pw.chromium.launch_persistent_context(
        PROFILE, headless=headless,
        viewport={"width": 2400, "height": 1000},
        args=["--disable-blink-features=AutomationControlled"],
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto(page_url(page_id), wait_until="domcontentloaded", timeout=120000)

    if _at_login(page):
        do_login(page)
        page.goto(page_url(page_id), wait_until="domcontentloaded", timeout=120000)

    page.wait_for_timeout(render_ms)
    return ctx, page
