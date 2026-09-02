#!/usr/bin/env python3
"""Click a BC action (expanding 'More options' if needed) and dump the resulting dialog text.

Usage: bc_action_msg.py <pageid> "<Action Caption>" [shotname]
"""
import os
import sys
from playwright.sync_api import sync_playwright
from bc_session import BASE, open_page, log

page_id = sys.argv[1]
caption = sys.argv[2]
SHOT = os.path.join(BASE, sys.argv[3] if len(sys.argv) > 3 else "bc_msg.png")


def try_click(page, sel):
    for fi, fr in enumerate(page.frames):
        try:
            loc = fr.locator(sel).first
            if loc.count():
                loc.click(timeout=12000)
                return fi
        except Exception:
            continue
    return None


with sync_playwright() as p:
    ctx, page = open_page(p, page_id)
    log("[*] Page:", page.title())

    hit = try_click(page, f'[aria-label="{caption}"]')
    if hit is None:
        log("[*] not visible, expanding 'More options'...")
        try_click(page, '[aria-label="More options"]')
        page.wait_for_timeout(4000)
        hit = try_click(page, f'[aria-label="{caption}"]')

    if hit is None:
        log("[*] still hidden, opening the 'Actions' menu...")
        try_click(page, '[aria-label="Actions"]')
        page.wait_for_timeout(4000)
        hit = try_click(page, f'[aria-label="{caption}"]')

    if hit is None:
        page.screenshot(path=SHOT)
        log("[!] action not found. SHOT:", SHOT)
        ctx.close()
        sys.exit(4)

    log(f"[*] clicked '{caption}' in frame {hit}")
    page.wait_for_timeout(18000)
    page.screenshot(path=SHOT)

    for fi, fr in enumerate(page.frames):
        try:
            txt = fr.inner_text("body", timeout=8000).strip()
        except Exception:
            continue
        for line in txt.splitlines():
            s = line.strip()
            if any(k in s for k in ("TokenLen", "Expiry", "ReusedCached", "cannot be", "error", "Error")):
                log("  >>", s)
    log("SHOT:", SHOT)
    ctx.close()
