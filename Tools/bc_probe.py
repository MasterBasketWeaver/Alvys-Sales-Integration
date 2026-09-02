#!/usr/bin/env python3
"""Dump DOM candidates matching a caption, to work out a reliable selector."""
import sys
from playwright.sync_api import sync_playwright
from bc_session import open_page, log

page_id = sys.argv[1]
needle = sys.argv[2]

with sync_playwright() as p:
    ctx, page = open_page(p, page_id)
    log("[*] Page:", page.title(), "| frames:", len(page.frames))

    for fi, fr in enumerate(page.frames):
        try:
            info = fr.evaluate(
                """(needle) => {
                    const out = [];
                    for (const el of document.querySelectorAll('*')) {
                        const own = Array.from(el.childNodes)
                            .filter(n => n.nodeType === 3)
                            .map(n => n.textContent.trim()).join('');
                        if (own && own.includes(needle)) {
                            const r = el.getBoundingClientRect();
                            out.push({
                                tag: el.tagName,
                                cls: (el.className || '').toString().slice(0, 80),
                                id: el.id || '',
                                role: el.getAttribute('role') || '',
                                aria: el.getAttribute('aria-label') || '',
                                vis: r.width > 0 && r.height > 0,
                                box: [Math.round(r.x), Math.round(r.y),
                                      Math.round(r.width), Math.round(r.height)],
                            });
                        }
                    }
                    return out;
                }""",
                needle,
            )
        except Exception as e:
            log(f"[frame {fi}] eval failed: {e}")
            continue
        if info:
            log(f"[frame {fi}] url={fr.url[:80]}")
            for m in info:
                log("   ", m)
    ctx.close()
