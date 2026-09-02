#!/usr/bin/env python3
"""Trigger an action, then probe + expand the resulting BC error dialog for details."""
import os
import sys
from playwright.sync_api import sync_playwright
from bc_session import BASE, open_page, log

page_id = sys.argv[1]
caption = sys.argv[2]
SHOT = os.path.join(BASE, "bc_err_details.png")

JS_DUMP = """() => {
    const out = [];
    for (const el of document.querySelectorAll('a,button,span,div[role="button"]')) {
        const t = (el.innerText || '').trim();
        if (!t || t.length > 60) continue;
        if (/details|Show more|Copy|Technical/i.test(t)) {
            const r = el.getBoundingClientRect();
            out.push({tag: el.tagName, txt: t.slice(0,60),
                      cls: (el.className||'').toString().slice(0,60),
                      vis: r.width>0 && r.height>0});
        }
    }
    return out;
}"""

with sync_playwright() as p:
    ctx, page = open_page(p, page_id)

    for fi, fr in enumerate(page.frames):
        try:
            loc = fr.locator(f'[aria-label="{caption}"]').first
            if loc.count():
                loc.click(timeout=12000)
                log(f"[*] triggered '{caption}' in frame {fi}")
                break
        except Exception:
            continue

    page.wait_for_timeout(15000)

    for fi, fr in enumerate(page.frames):
        try:
            cands = fr.evaluate(JS_DUMP)
        except Exception:
            continue
        if cands:
            log(f"[frame {fi}] detail-ish elements: {cands}")
            for c in cands:
                if not c["vis"]:
                    continue
                try:
                    fr.locator(f'{c["tag"].lower()}:text-is("{c["txt"]}")').first.click(timeout=8000)
                    log(f"[*] expanded: {c['txt']}")
                    page.wait_for_timeout(6000)
                except Exception as e:
                    log(f"[-] could not click {c['txt']}: {str(e).splitlines()[0]}")

    page.wait_for_timeout(3000)
    page.screenshot(path=SHOT, full_page=True)
    for fi, fr in enumerate(page.frames):
        try:
            txt = fr.inner_text("body", timeout=8000).strip()
        except Exception:
            continue
        if "cannot be performed" in txt or "Details" in txt:
            log(f"===== frame {fi} =====")
            log(txt[:5000])
    log("SHOT:", SHOT)
    ctx.close()
