#!/usr/bin/env python3
"""Trigger an action, open 'Share details' > 'Copy error details', read the clipboard."""
import os
import sys
from playwright.sync_api import sync_playwright
import bc_session
from bc_session import BASE, page_url, do_login, log, PROFILE

page_id = sys.argv[1]
caption = sys.argv[2]

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PROFILE, headless=True,
        viewport={"width": 1600, "height": 1000},
        args=["--disable-blink-features=AutomationControlled"],
    )
    ctx.grant_permissions(["clipboard-read", "clipboard-write"],
                          origin="https://businesscentral.dynamics.com")
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto(page_url(page_id), wait_until="domcontentloaded", timeout=120000)
    if "login.microsoftonline.com" in page.url:
        do_login(page)
        page.goto(page_url(page_id), wait_until="domcontentloaded", timeout=120000)
    page.wait_for_timeout(22000)

    frame = None
    for fr in page.frames:
        loc = fr.locator(f'[aria-label="{caption}"]').first
        try:
            if loc.count():
                loc.click(timeout=12000)
                frame = fr
                log("[*] triggered:", caption)
                break
        except Exception:
            continue

    page.wait_for_timeout(15000)
    frame.locator('button:has-text("Share details")').first.click(timeout=15000)
    page.wait_for_timeout(4000)
    frame.locator('*:text-is("Copy error details")').first.click(timeout=15000)
    page.wait_for_timeout(4000)

    txt = page.evaluate("async () => await navigator.clipboard.readText()")
    log("===== ERROR DETAILS =====")
    log(txt)
    ctx.close()
