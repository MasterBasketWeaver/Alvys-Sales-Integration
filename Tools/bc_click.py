#!/usr/bin/env python3
"""Click a BC action by caption, then screenshot and dump the resulting page text.

Usage: bc_click.py <pageid> "<Action Caption>" [outname]
Re-authenticates automatically if the saved session has expired.

The BC web client renders inside an iframe, so actions are located by scanning
every frame for an element carrying the caption as its aria-label.
"""
import os
import sys
from playwright.sync_api import sync_playwright
from bc_session import BASE, open_page, log

page_id = sys.argv[1]
caption = sys.argv[2]
SHOT = os.path.join(BASE, sys.argv[3] if len(sys.argv) > 3 else "bc_click.png")


def click_action(page, caption):
    for fi, fr in enumerate(page.frames):
        for sel in (f'[aria-label="{caption}"]', f'span:text-is("{caption}")'):
            try:
                loc = fr.locator(sel).first
                if loc.count() == 0:
                    continue
                loc.click(timeout=15000)
                log(f"[*] clicked in frame {fi} via {sel}")
                return True
            except Exception as e:
                log(f"[-] frame {fi} {sel}: {str(e).splitlines()[0]}")
    return False


with sync_playwright() as p:
    ctx, page = open_page(p, page_id)
    log("[*] Page:", page.title())
    log("[*] Clicking:", caption)

    if not click_action(page, caption):
        page.screenshot(path=SHOT)
        log("[!] could not click. SHOT:", SHOT)
        ctx.close()
        sys.exit(4)

    page.wait_for_timeout(20000)
    page.screenshot(path=SHOT)
    log("SHOT:", SHOT)
    ctx.close()
