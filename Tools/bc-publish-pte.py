#!/usr/bin/env python3
"""Compile an AL project and install it as a per-tenant extension (PTE).

Usage: bc-publish-pte.py <project-path>

The dev endpoint (bc-publish.sh) cannot replace a PTE, so this goes through the automation API's
extensionUpload instead and waits for the deployment to finish. A PTE upload is refused unless its
version is higher than the one installed. A dev-published copy of the same app has to be
uninstalled and unpublished first, and this does that rather than failing on it.

The deployment status gives no error text when it fails; read it from page 2508 (Extension
Deployment Status) -> the row -> Summary "View Details".
"""
import json
import os
import subprocess
import sys
import time

import requests

from bc_auth import get_access_token

TENANT = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV = os.environ.get("BC_ENV", "MCSandbox_09222026")
COMPANY = os.environ.get("BC_COMPANY", "Alvy's Test")
ROOT = f"https://api.businesscentral.dynamics.com/v2.0/{TENANT}/{ENV}"
ALC = "/home/bryan/.vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/linux/alc"


def die(msg, resp=None):
    print(f"ERROR: {msg}")
    if resp is not None:
        print(f"  HTTP {resp.status_code}: {resp.text[:1500]}")
    sys.exit(1)


project = os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else "App")
manifest = json.load(open(os.path.join(project, "app.json")))
version = tuple(int(p) for p in manifest["version"].split("."))
app_file = os.path.join(project, "output", f"{manifest['publisher']}_{manifest['name']}_{manifest['version']}.app")

print(f"[1/4] Compiling {manifest['name']} {manifest['version']}...")
os.makedirs(os.path.dirname(app_file), exist_ok=True)
subprocess.run([ALC, f"/project:{project}", f"/packagecachepath:{os.path.join(project, '.alpackages')}", f"/out:{app_file}"], check=False)
if not os.path.isfile(app_file):
    die("compilation failed; no .app produced")

H = {"Authorization": f"Bearer {get_access_token(interactive=False)}"}
J = {**H, "Content-Type": "application/json"}

r = requests.get(f"{ROOT}/api/v2.0/companies?$filter=name eq '{COMPANY.replace(chr(39), chr(39) * 2)}'", headers=H, timeout=120)
if r.status_code != 200 or not r.json().get("value"):
    die(f"company '{COMPANY}' not found", r)
AUT = f"{ROOT}/api/microsoft/automation/v2.0/companies({r.json()['value'][0]['id']})"


def published():
    r = requests.get(f"{AUT}/extensions", headers=H, timeout=120)
    if r.status_code != 200:
        die("extension list", r)
    return [e for e in r.json()["value"] if e["id"] == manifest["id"]]


def wait_until(check, what, timeout_s=600):
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if check():
            return
        time.sleep(10)
    die(f"timed out waiting for {what}")


print("[2/4] Checking what is installed...")
for ext in published():
    installed = (ext["versionMajor"], ext["versionMinor"], ext["versionBuild"], ext["versionRevision"])
    kind = ext["publishedAs"].strip()
    print(f"  {kind} {'.'.join(map(str, installed))}{' (installed)' if ext['isInstalled'] else ''}")
    if kind == "Dev":
        pkg = ext["packageId"]
        if ext["isInstalled"]:
            r = requests.post(f"{AUT}/extensions({pkg})/Microsoft.NAV.uninstall", headers=J, timeout=300)
            if r.status_code not in (200, 204):
                die("uninstalling the dev copy", r)
            wait_until(lambda: not any(e["packageId"] == pkg and e["isInstalled"] for e in published()), "the dev copy to uninstall")
        r = requests.post(f"{AUT}/extensions({pkg})/Microsoft.NAV.unpublish", headers=J, timeout=300)
        if r.status_code not in (200, 204):
            die("unpublishing the dev copy", r)
        wait_until(lambda: not any(e["packageId"] == pkg for e in published()), "the dev copy to unpublish")
        print("  dev copy uninstalled and unpublished")
    elif ext["isInstalled"] and installed >= version:
        die(f"{kind} {'.'.join(map(str, installed))} is installed; a PTE upload needs a higher version than that")

print("[3/4] Uploading...")
r = requests.post(f"{AUT}/extensionUpload", headers=J, json={"schedule": "Current version", "schemaSyncMode": "Add"}, timeout=120)
if r.status_code not in (200, 201):
    die("creating the upload", r)
upload_id = r.json()["systemId"]
with open(app_file, "rb") as f:
    r = requests.patch(f"{AUT}/extensionUpload({upload_id})/extensionContent",
                       headers={**H, "Content-Type": "application/octet-stream", "If-Match": "*"}, data=f.read(), timeout=600)
if r.status_code not in (200, 204):
    die("sending the .app", r)
r = requests.post(f"{AUT}/extensionUpload({upload_id})/Microsoft.NAV.upload", headers=J, timeout=600)
if r.status_code not in (200, 204):
    die("starting the deployment", r)

print("[4/4] Waiting for the deployment...")
wanted = ".".join(map(str, version))
deadline = time.time() + 1200
while time.time() < deadline:
    time.sleep(15)
    r = requests.get(f"{AUT}/extensionDeploymentStatus", headers=H, timeout=120)
    rows = [d for d in r.json().get("value", []) if d.get("name") == manifest["name"] and d.get("appVersion") == wanted]
    if rows:
        status = rows[0]["status"]
        print(f"  {status}")
        if status == "Completed":
            break
        if status == "Failed":
            die("deployment failed; see page 2508 -> the row -> Summary 'View Details' for why")
else:
    die("timed out waiting for the deployment")

for ext in published():
    if ext["isInstalled"]:
        print(f"Installed: {ext['publishedAs'].strip()} {ext['versionMajor']}.{ext['versionMinor']}.{ext['versionBuild']}.{ext['versionRevision']}")
