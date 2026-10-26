#!/usr/bin/env python3
"""Sign the ALVYS_ENV browser profile in to Alvys when it no longer remembers this device.

Usage: [ALVYS_ENV=prod] alvys-login.py [code]

Pass the current code from the authenticator app; without one it is asked for once the password
step is done, so it is entered fresh. "Remember this device for 30 days" is ticked, so the
alvys_ui scripts sign themselves back in without a code until that lapses.
"""
import sys

from playwright.sync_api import sync_playwright

import alvys_ui

code = sys.argv[1] if len(sys.argv) > 1 else None

with sync_playwright() as p:
    ctx, page = alvys_ui.open_context(p)
    try:
        page.goto(alvys_ui.SETTLEMENTS_URL, wait_until="domcontentloaded", timeout=120000)
        page.wait_for_timeout(10000)
        if not alvys_ui.at_login(page):
            print("Already signed in.")
            sys.exit(0)
        try:
            alvys_ui.sign_in(page, code)
        except RuntimeError:
            if code or alvys_ui.OTP_URL_PART not in page.url:
                raise
            alvys_ui.sign_in(page, input("Authenticator code: ").strip())
        print("Signed in; this device is remembered for 30 days.")
    finally:
        ctx.close()
