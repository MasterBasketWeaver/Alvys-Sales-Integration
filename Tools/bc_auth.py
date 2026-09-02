#!/usr/bin/env python3
"""BC OAuth device-code flow with PERSISTENT token cache.

One-time interactive 2FA, then silent refresh (~90 days, until Conditional
Access forces re-auth). Import get_access_token() from other scripts.

Uses the Azure CLI first-party public client, which exists in every tenant,
so no app registration or admin consent is required.
"""
import msal
import json
import os
import sys

TENANT_ID  = "0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
CLIENT_ID  = "41839ce3-4041-4bac-8c17-0941f25d7aaf"  # AL dev tools (preauthorized for the BC API)
SCOPES     = ["https://api.businesscentral.dynamics.com/Financials.ReadWrite.All"]
AUTHORITY  = f"https://login.microsoftonline.com/{TENANT_ID}"

from project_paths import PROJECT_ROOT

BASE       = PROJECT_ROOT                               # above the repo: kept out of git
CACHE_FILE = os.path.join(BASE, "bc_token_cache.bin")   # persistent MSAL cache
TOKEN_FILE = os.path.join(BASE, "bc_token.json")        # legacy/compat dump


def _load_cache():
    cache = msal.SerializableTokenCache()
    if os.path.exists(CACHE_FILE):
        cache.deserialize(open(CACHE_FILE, "r").read())
    return cache


def _save_cache(cache):
    if cache.has_state_changed:
        with open(CACHE_FILE, "w") as f:
            f.write(cache.serialize())
        os.chmod(CACHE_FILE, 0o600)


def _app(cache):
    return msal.PublicClientApplication(CLIENT_ID, authority=AUTHORITY, token_cache=cache)


def get_access_token(interactive=True):
    """Return a valid access token, refreshing silently when possible.

    Order: silent from cache -> migrate legacy refresh_token -> device flow.
    Set interactive=False to fail instead of prompting (for headless jobs).
    """
    cache = _load_cache()
    app = _app(cache)
    result = None

    # 1) silent from persisted cache
    accounts = app.get_accounts()
    if accounts:
        result = app.acquire_token_silent(SCOPES, account=accounts[0])

    # 2) seed cache from the legacy bc_token.json refresh_token (no re-2FA)
    if not result and os.path.exists(TOKEN_FILE):
        try:
            legacy = json.load(open(TOKEN_FILE))
            rt = legacy.get("refresh_token")
            if rt:
                result = app.acquire_token_by_refresh_token(rt, SCOPES)
                if "access_token" not in result:
                    result = None
        except Exception:
            result = None

    # 3) interactive device-code flow (the only step that needs your 2FA)
    if not result:
        if not interactive:
            _save_cache(cache)
            raise RuntimeError("No cached token and interactive=False")
        flow = app.initiate_device_flow(scopes=SCOPES)
        if "error" in flow:
            raise RuntimeError(f"device flow init failed: {flow}")
        print("\n" + "=" * 60)
        print(flow["message"])
        print("=" * 60 + "\n")
        result = app.acquire_token_by_device_flow(flow)

    _save_cache(cache)

    if "access_token" not in result:
        raise RuntimeError(f"{result.get('error')}: {result.get('error_description')}")

    return result["access_token"]


if __name__ == "__main__":
    tok = get_access_token()
    print(f"[OK] access token acquired ({len(tok)} chars); cache -> {CACHE_FILE}")
