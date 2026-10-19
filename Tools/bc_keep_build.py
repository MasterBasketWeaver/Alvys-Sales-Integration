"""Keeps every build uploaded as a PTE.

BC takes a PTE app id + version only once per tenant, so installing that version again anywhere in
the tenant needs the identical file. Uploads therefore go from a kept, read-only copy in the
project's output/ (or releases/), never from a scratch or temp folder, and a kept build is never
replaced. bc_build.py refuses to compile over one.
"""
import io
import os
import re
import stat
import sys
import zipfile

KEEP_DIRS = ("output", "releases")


def kept_name(data):
    # A .app is a 40-byte header followed by a zip whose NavxManifest.xml names the app.
    xml = zipfile.ZipFile(io.BytesIO(data[40:])).read("NavxManifest.xml").decode("utf-8-sig")
    app = re.search(r"<App\s[^>]*>", xml).group(0)
    attr = lambda name: re.search(rf'\b{name}="([^"]*)"', app).group(1)
    return f"{attr('Publisher')}_{attr('Name')}_{attr('Version')}.app"


def is_kept(path):
    return os.path.isfile(path) and not os.stat(path).st_mode & stat.S_IWUSR


def keep_build(app_path, keep_dir=None):
    """Return the kept copy of app_path to upload, creating it if needed.

    keep_dir defaults to the .app's own folder when that is inside an output/ or releases/ folder;
    otherwise it must be given (the project's output/).
    """
    app_path = os.path.abspath(app_path)
    with open(app_path, "rb") as f:
        data = f.read()
    if keep_dir is None:
        keep_dir = os.path.dirname(app_path)
        if not set(KEEP_DIRS) & set(keep_dir.split(os.sep)):
            sys.exit(f"[FAIL] {app_path} is not in a project's output/ or releases/ folder. Pass "
                     "--keep-dir <project>/output so the uploaded build is kept.")
    kept = os.path.join(os.path.abspath(keep_dir), kept_name(data))
    if os.path.exists(kept) and kept != app_path:
        with open(kept, "rb") as f:
            if f.read() != data:
                sys.exit(f"[FAIL] {kept} is a different build of the same version. Upload that file "
                         "instead, or raise the version (ask first). If the kept build was never "
                         "accepted by BC, delete it and retry.")
    elif kept != app_path:
        os.makedirs(os.path.dirname(kept), exist_ok=True)
        with open(kept, "wb") as f:
            f.write(data)
    os.chmod(kept, 0o444)
    print(f"kept build: {kept}", flush=True)
    return kept
