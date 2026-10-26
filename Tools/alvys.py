#!/usr/bin/env python3
"""Alvys from the command line, against either organization.

  alvys.py [--env test|prod] [--ro] envs
  alvys.py [--env test|prod] [--ro] whoami
  alvys.py [--env test|prod] [--ro] get <path>                     e.g. get trucks?page=0&pageSize=5
  alvys.py [--env test|prod] [--ro] call <METHOD> <path> [json|@file]
  alvys.py [--env test|prod] ui [path] [--headed]                  e.g. ui settings/api-keys

--env defaults to ALVYS_ENV, else test. Paths are relative to the public API root
(https://integrations.alvys.com/api/p/v1/) or, for `ui`, to https://app.alvys.com/. In prod,
anything but GET and .../search POSTs is refused unless --allow-prod-write is given.
"""
import argparse
import json
import os
import re
import sys
import time

import alvys_env
from project_paths import PROJECT_ROOT


def show(status, body):
    print(f"HTTP {status}")
    print(json.dumps(body, indent=2) if not isinstance(body, str) else body)


def whoami(read_write):
    import alvys_api
    env = alvys_env.current()
    claims = alvys_api.claims(alvys_api.token(read_write))
    print(f"env {env.name}: {env.organization} (org {claims.get('org_name')}), "
          f"client {claims.get('client_name')} {claims.get('client_id')}")
    print("token expires", time.strftime("%Y-%m-%d %I:%M %p %Z", time.localtime(claims["exp"])),
          "| subsidiaries:", claims.get("https://alvys.com/claims/app/subsidiaries"))
    groups = {}
    for scope in claims.get("scope", "").split():
        obj, _, verb = scope.partition(":")
        groups.setdefault(obj, []).append(verb)
    print(len(claims.get("scope", "").split()), "scopes:")
    for obj in sorted(groups):
        print(f"  {obj}: {', '.join(sorted(groups[obj]))}")


def payload_arg(text):
    if text is None:
        return None
    if text.startswith("@"):
        with open(text[1:]) as f:
            return json.load(f)
    return json.loads(text)


def ui(path, headed):
    from playwright.sync_api import sync_playwright
    import alvys_ui
    url = "https://app.alvys.com/" + (path or "").lstrip("/")
    shot = os.path.join(PROJECT_ROOT, "tmp", f"alvys-{alvys_env.current().name}-ui.png")
    os.makedirs(os.path.dirname(shot), exist_ok=True)
    with sync_playwright() as pw:
        ctx, page = alvys_ui.open_context(pw, headless=not headed)
        try:
            page.goto(url, wait_until="domcontentloaded", timeout=120000)
            page.wait_for_timeout(10000)
            if alvys_ui.at_login(page):
                alvys_ui.sign_in(page)
                page.goto(url, wait_until="domcontentloaded", timeout=120000)
            page.wait_for_timeout(10000)
            print("URL", page.url.split("?")[0])
            page.screenshot(path=shot, full_page=True)
            print("screenshot", shot)
            print(re.sub(r"\n{3,}", "\n\n", page.inner_text("main") if page.locator("main").count()
                         else page.inner_text("body"))[:4000])
        finally:
            ctx.close()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--env", choices=sorted(alvys_env.ENVIRONMENTS))
    ap.add_argument("--ro", action="store_true", help="use the read-only key")
    ap.add_argument("--allow-prod-write", action="store_true")
    ap.add_argument("--headed", action="store_true")
    ap.add_argument("command", choices=["envs", "whoami", "get", "call", "ui"])
    ap.add_argument("args", nargs="*")
    a = ap.parse_args()
    if a.env:
        alvys_env.use(a.env)
    if a.allow_prod_write:
        os.environ[alvys_env.PROD_WRITE_VAR] = "1"
    rw = not a.ro

    if a.command == "envs":
        current = alvys_env.current().name
        for e in alvys_env.ENVIRONMENTS.values():
            print(f"{'*' if e.name == current else ' '} {e.name:5} {e.organization} (org {e.org_name}), "
                  f"keys {e.rw_cred}/{e.ro_cred}, profile {os.path.basename(e.profile)}")
    elif a.command == "whoami":
        whoami(rw)
    elif a.command == "ui":
        ui(a.args[0] if a.args else "", a.headed)
    else:
        import alvys_api
        if a.command == "get":
            if len(a.args) != 1:
                ap.error("get takes one path")
            method, path, payload = "GET", a.args[0], None
        else:
            if len(a.args) not in (2, 3):
                ap.error("call takes METHOD PATH [json|@file]")
            method, path = a.args[0].upper(), a.args[1]
            payload = payload_arg(a.args[2] if len(a.args) == 3 else None)
        try:
            alvys_env.check_write(method, path)
        except PermissionError as e:
            sys.exit(str(e))
        show(*alvys_api.call(method, path.lstrip("/"), alvys_api.token(rw), payload))


if __name__ == "__main__":
    main()
