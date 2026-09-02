#!/usr/bin/env python3
"""Shared BC sandbox browser session helpers.

The signed-in session lives in the Chromium profile at .bcprofile. No 2FA is required
for this account, so expiry is handled automatically: any script calling open_page()
re-authenticates from BC_credentials.txt without user interaction.
"""
import os
import time

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = "MCSandbox_061226"
# These scripts live in the repo, but the browser profile, credentials and any screenshots
# they write belong to the project root above it, which is not version controlled.
from project_paths import PROJECT_ROOT, TOOLS

BASE = PROJECT_ROOT
PROFILE = os.path.join(BASE, ".bcprofile")
CREDS = os.path.join(BASE, "BC_credentials.txt")


def log(*a):
    print(*a, flush=True)


def page_url(page_id):
    return f"https://businesscentral.dynamics.com/{TENANT}/{ENV}?page={page_id}"


def read_creds():
    with open(CREDS) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    return lines[0], lines[1]


def _at_login(page):
    return "login.microsoftonline.com" in page.url or "login.live.com" in page.url


def do_login(page):
    """Run the username/password flow. This account has no 2FA."""
    user, pwd = read_creds()
    log("[auth] session expired or absent - signing in automatically...")

    page.fill('input[type="email"], input[name="loginfmt"]', user, timeout=60000)
    page.click('input[type="submit"], button[type="submit"]')

    page.wait_for_selector('input[type="password"]', timeout=60000)
    page.fill('input[type="password"]', pwd)
    page.click('input[type="submit"], button[type="submit"]')

    # "Stay signed in?" -> Yes, so the profile keeps the session
    deadline = time.time() + 180
    while time.time() < deadline:
        if "businesscentral.dynamics.com" in page.url:
            break
        try:
            body = page.inner_text("body", timeout=5000)
        except Exception:
            time.sleep(2)
            continue
        if "Stay signed in" in body:
            try:
                page.click('input[type="submit"][value="Yes"], #idSIButton9', timeout=10000)
            except Exception:
                pass
        time.sleep(2)

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
