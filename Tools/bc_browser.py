#!/usr/bin/env python3
"""Drive a persistent-profile Chromium against the BC sandbox web client.

The Chromium profile lives at ~/projects/alvys/.bcprofile so the signed-in session
is reused across sessions -- after one successful interactive sign-in, `shot` runs
headless with no further auth.

Usage:
  bc_browser.py login          headed; auto-fills credentials from BC_credentials.txt,
                               pauses for 2FA if Microsoft asks for it
  bc_browser.py shot [pageid]  headless; screenshots a BC page using the saved session
"""
import os
import sys
import time
from playwright.sync_api import sync_playwright

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = "MCSandbox_061226"
from project_paths import PROJECT_ROOT

BASE = PROJECT_ROOT  # above the repo: kept out of git
PROFILE = os.path.join(BASE, ".bcprofile")
CREDS = os.path.join(BASE, "BC_credentials.txt")
SHOT = os.path.join(BASE, "bc_shot.png")

mode = sys.argv[1] if len(sys.argv) > 1 else "shot"
page_id = sys.argv[2] if len(sys.argv) > 2 else "80800"
URL = f"https://businesscentral.dynamics.com/{TENANT}/{ENV}?page={page_id}"


def log(*a):
    print(*a, flush=True)


def read_creds():
    with open(CREDS) as f:
        lines = [ln.strip() for ln in f if ln.strip()]
    return lines[0], lines[1]


# Text fragments that mean "Microsoft wants a second factor from a human"
TWOFA_MARKERS = [
    "Enter code", "verification code", "Approve sign in", "Approve this request",
    "verify your identity", "Open your Authenticator app", "We texted your phone",
    "authentication method", "More information required", "Verify your identity",
]

headless = mode != "login"
args = ["--disable-blink-features=AutomationControlled"]
if not headless and not os.environ.get("DISPLAY"):
    args += ["--ozone-platform=wayland"]

with sync_playwright() as p:
    ctx = p.chromium.launch_persistent_context(
        PROFILE, headless=headless,
        viewport={"width": 1600, "height": 1000}, args=args,
    )
    page = ctx.pages[0] if ctx.pages else ctx.new_page()
    page.goto(URL, wait_until="domcontentloaded", timeout=120000)

    if mode == "login":
        user, pwd = read_creds()

        if "login.microsoftonline.com" in page.url or "login.live.com" in page.url:
            log("[*] At Microsoft sign-in, entering username...")
            try:
                page.fill('input[type="email"], input[name="loginfmt"]', user, timeout=30000)
                page.click('input[type="submit"], button[type="submit"]')
            except Exception as e:
                log("[!] username step:", e)

            log("[*] Entering password...")
            try:
                page.wait_for_selector('input[type="password"]', timeout=60000)
                page.fill('input[type="password"]', pwd)
                page.click('input[type="submit"], button[type="submit"]')
            except Exception as e:
                log("[!] password step:", e)

            # Now: either 2FA, "Stay signed in?", or straight through to BC.
            log("[*] Submitted. Watching for 2FA / consent prompts...")
            announced_2fa = False
            deadline = time.time() + 420
            while time.time() < deadline:
                if "businesscentral.dynamics.com" in page.url:
                    break
                try:
                    body = page.inner_text("body", timeout=5000)
                except Exception:
                    time.sleep(2)
                    continue

                # "Stay signed in?" -> Yes, so the session persists in the profile
                if "Stay signed in" in body:
                    log("[*] 'Stay signed in?' -> clicking Yes (persists session)")
                    try:
                        page.click('input[type="submit"][value="Yes"], #idSIButton9', timeout=10000)
                    except Exception:
                        pass
                    time.sleep(3)
                    continue

                if not announced_2fa and any(m.lower() in body.lower() for m in TWOFA_MARKERS):
                    page.screenshot(path=os.path.join(BASE, "bc_2fa.png"))
                    log("=" * 60)
                    log("2FA REQUIRED -- action needed in the browser window.")
                    log("Screen text:")
                    log(body[:600])
                    log("=" * 60)
                    announced_2fa = True

                time.sleep(3)

            if "businesscentral.dynamics.com" not in page.url:
                page.screenshot(path=SHOT)
                log("[!] Did not reach BC in time. URL:", page.url)
                ctx.close()
                sys.exit(2)

    log("[*] Reached BC, waiting for the web client to render...")
    page.wait_for_timeout(25000)
    page.screenshot(path=SHOT)
    log("URL:", page.url)
    log("TITLE:", page.title())
    log("SHOT:", SHOT)
    ctx.close()
