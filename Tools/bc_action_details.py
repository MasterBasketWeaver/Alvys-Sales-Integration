#!/usr/bin/env python3
"""Click a BC action, then expand any error dialog's 'Share details' and dump the text."""
import os
import sys
from playwright.sync_api import sync_playwright
from bc_session import BASE, open_page, log

page_id = sys.argv[1]
caption = sys.argv[2]
SHOT = os.path.join(BASE, sys.argv[3] if len(sys.argv) > 3 else "bc_details.png")


def click_in_frames(page, selectors, label):
    for fi, fr in enumerate(page.frames):
        for sel in selectors:
            try:
                loc = fr.locator(sel).first
                if loc.count() == 0:
                    continue
                loc.click(timeout=12000)
                log(f"[*] {label}: clicked frame {fi} via {sel}")
                return True
            except Exception:
                continue
    return False


with sync_playwright() as p:
    ctx, page = open_page(p, page_id)
    log("[*] Page:", page.title())

    click_in_frames(page, [f'[aria-label="{caption}"]'], f"action '{caption}'")
    page.wait_for_timeout(15000)

    click_in_frames(page, ['a:has-text("Share details")',
                           '[aria-label="Share details"]',
                           'span:text-is("Share details")'], "Share details")
    page.wait_for_timeout(8000)
    page.screenshot(path=SHOT, full_page=True)

    for fi, fr in enumerate(page.frames):
        try:
            txt = fr.inner_text("body", timeout=8000).strip()
        except Exception:
            continue
        if txt and len(txt) > 40:
            log(f"===== frame {fi} =====")
            log(txt[:4000])
    log("SHOT:", SHOT)
    ctx.close()
