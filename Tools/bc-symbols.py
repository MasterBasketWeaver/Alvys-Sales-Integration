#!/usr/bin/env python3
"""Download AL symbol packages (.app) from the BC dev endpoint into .alpackages.

Mirrors what VS Code's "AL: Download Symbols" does, but headless — using the
persistent device-code token from bc_auth.py.

Pulls the Microsoft platform/application symbols plus every entry in the
project's app.json "dependencies" list.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

from bc_auth import get_access_token, TENANT_ID

ENV      = "MCSandbox_061226"
# Optional argv[1] selects a different AL project; defaults to the Alvys app.
PROJECT  = (sys.argv[1] if len(sys.argv) > 1 else
            os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "App"))
DEV_BASE = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT_ID}/{ENV}/dev"

# Microsoft symbols are not listed in app.json dependencies; they come from the
# "application"/"platform" versions. Empty versionText = latest on the tenant.
MS_PACKAGES = [
    ("Microsoft", "System"),
    ("Microsoft", "System Application"),
    ("Microsoft", "Business Foundation"),
    ("Microsoft", "Application"),
    ("Microsoft", "Base Application"),
]


def download(token, publisher, name, version, outdir):
    qs = urllib.parse.urlencode({
        "publisher":   publisher,
        "appName":     name,
        "versionText": version or "",
        "tenant":      "default",
    })
    req = urllib.request.Request(
        f"{DEV_BASE}/packages?{qs}",
        headers={"Authorization": f"Bearer {token}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            disp = resp.headers.get("Content-Disposition", "")
            m = re.search(r'filename="?([^";]+)"?', disp)
            fname = m.group(1) if m else f"{publisher}_{name}_{version or 'latest'}.app"
            data = resp.read()
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", errors="replace")[:300]
        print(f"  FAILED {publisher}_{name}: HTTP {e.code} {body}")
        return False

    path = os.path.join(outdir, fname)
    with open(path, "wb") as f:
        f.write(data)
    print(f"  {fname} ({len(data) / 1_048_576:.1f} MB)")
    return True


def main():
    with open(os.path.join(PROJECT, "app.json")) as f:
        app = json.load(f)

    outdir = os.path.join(PROJECT, ".alpackages")
    os.makedirs(outdir, exist_ok=True)

    token = get_access_token()
    print(f"Downloading symbols from {ENV} -> {outdir}")

    targets = [(p, n, "") for p, n in MS_PACKAGES]
    targets += [(d["publisher"], d["name"], d.get("version", ""))
                for d in app.get("dependencies", [])]

    ok = sum(download(token, p, n, v, outdir) for p, n, v in targets)
    print(f"\n{ok}/{len(targets)} symbol packages downloaded.")
    return 0 if ok == len(targets) else 1


if __name__ == "__main__":
    sys.exit(main())
