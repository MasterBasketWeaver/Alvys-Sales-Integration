"""Which Alvys organization the Alvys tools talk to.

ALVYS_ENV picks it (`test` by default); `alvys.py --env` sets it for one command. Each environment
has its own API keys in `cred` and its own browser profile, because the app.alvys.com login belongs
to both organizations and Auth0 asks which one after every sign-in.
"""
import os
from dataclasses import dataclass

from project_paths import PROJECT_ROOT


@dataclass(frozen=True)
class AlvysEnv:
    name: str
    organization: str
    org_name: str
    rw_cred: str
    ro_cred: str
    profile: str
    production: bool


ENVIRONMENTS = {
    "test": AlvysEnv("test", "TTG - Test", "tt777", "alvys-api-rw", "alvys-api-ro",
                     os.path.join(PROJECT_ROOT, ".alvysprofile"), False),
    # Alvys production has a single key for us, the Argo Analytics AI client, used for reads too.
    "prod": AlvysEnv("prod", "Texas Transportation Group", "ta597", "alvys-prod-argo", "alvys-prod-argo",
                     os.path.join(PROJECT_ROOT, ".alvysprofile-prod"), True),
}

PROD_WRITE_VAR = "ALVYS_ALLOW_PROD_WRITE"


def current():
    name = os.environ.get("ALVYS_ENV", "test").lower()
    if name not in ENVIRONMENTS:
        raise SystemExit(f"ALVYS_ENV={name!r}: expected one of {', '.join(ENVIRONMENTS)}")
    return ENVIRONMENTS[name]


def use(name):
    os.environ["ALVYS_ENV"] = name
    return current()


def require_test(what):
    env = current()
    if env.production:
        raise SystemExit(f"{what} creates and settles test data; it refuses ALVYS_ENV={env.name}.")


def check_write(method, path):
    """Production holds real owner operators' deductions, so anything that changes data there needs
    ALVYS_ALLOW_PROD_WRITE=1. Alvys searches are POSTs and stay allowed."""
    env = current()
    if not env.production or os.environ.get(PROD_WRITE_VAR) == "1":
        return
    if method.upper() == "GET" or (method.upper() == "POST" and path.rstrip("/").endswith("search")):
        return
    raise PermissionError(f"{method} {path} would change Alvys production; set {PROD_WRITE_VAR}=1 to allow it.")
