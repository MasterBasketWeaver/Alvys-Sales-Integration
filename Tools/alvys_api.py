#!/usr/bin/env python3
"""Minimal Alvys public API client.

The organization comes from ALVYS_ENV (see alvys_env.py): its read-write client from `cred`, or
with read_write=False its read-only one. auth0 rejects Python's
default user agent, so requests go out as curl.
"""
import base64
import json
import time
import urllib.error
import urllib.request

import alvys_env

API = "https://integrations.alvys.com/api/p/v1/"
TOKEN_URL = "https://auth.alvys.com/oauth/token"
AUDIENCE = "https://api.alvys.com/public/"
UA = "curl/8.5.0"


def credentials(read_write=True):
    from bc_session import cred_get
    env = alvys_env.current()
    prefix = env.rw_cred if read_write else env.ro_cred
    return cred_get(prefix + "-client-id"), cred_get(prefix + "-client-secret")


def token(read_write=True):
    client_id, secret = credentials(read_write)
    body = json.dumps({"client_id": client_id, "client_secret": secret,
                       "audience": AUDIENCE, "grant_type": "client_credentials"}).encode()
    req = urllib.request.Request(TOKEN_URL, data=body,
                                 headers={"Content-Type": "application/json", "User-Agent": UA})
    tok = json.load(urllib.request.urlopen(req))["access_token"]
    env = alvys_env.current()
    org = claims(tok).get("org_name")
    if org != env.org_name:
        raise RuntimeError(f"the {env.name} key's token is for Alvys org {org!r}, expected {env.org_name!r}")
    return tok


def call(method, path, tok, payload=None):
    alvys_env.check_write(method, path)
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(API + path, data=data, method=method,
                                 headers={"Authorization": "Bearer " + tok,
                                          "Accept": "application/json",
                                          "Content-Type": "application/json",
                                          "User-Agent": UA})
    try:
        r = urllib.request.urlopen(req)
        raw = r.read().decode()
        return r.status, (json.loads(raw) if raw.strip() else None)
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode()


def get_deduction(deduction_id, tok=None):
    tok = tok or token()
    status, body = call("GET", f"deductions/{deduction_id}", tok)
    if status != 200 or not isinstance(body, dict):
        raise RuntimeError(f"GET deductions/{deduction_id} -> {status} {str(body)[:200]}")
    return body


def is_paid(deduction_id, tok=None):
    return bool(get_deduction(deduction_id, tok).get("IsPaid"))


def wait_until_paid(deduction_id, timeout_s=3000, interval_s=30, log=print):
    """Alvys flips IsPaid only once the generated statement leaves Queued for Processed, which can
    be seconds or many minutes, so the settlement is waited on rather than assumed. Alvys\' own
    guidance is that a statement stuck Queued beyond 30-45 minutes is a support case."""
    tok = token()
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        if is_paid(deduction_id, tok):
            return True
        log(f"    ... deduction {deduction_id} not settled yet")
        time.sleep(interval_s)
    return False


def claims(tok):
    payload = tok.split(".")[1]
    payload += "=" * (-len(payload) % 4)
    return json.loads(base64.urlsafe_b64decode(payload))


def scopes(tok):
    return claims(tok).get("scope", "")
