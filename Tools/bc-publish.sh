#!/usr/bin/env bash
# Compile the Alvys AL project with alc and publish it to the BC sandbox dev endpoint.
# Auth comes from bc_auth.py (persistent device-code token, one-time 2FA).
set -euo pipefail

# BASE is Tools/ (where bc_auth.py sits); ROOT is the repo that holds the AL projects.
BASE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$BASE")"
TENANT="0b8281e8-7af6-4870-bd74-03d5eed3e4a0"
ENV="MCSandbox_061226"
REPO="${1:-$ROOT/App}"
# synchronize keeps existing data; forcesync allows destructive schema changes (dropped fields).
SCHEMA_MODE="${SCHEMA_MODE:-synchronize}"
# Default recompiles dependent extensions against the new symbols, which fails when this publish
# changes a signature the installed dependent still calls. DEP_OPTION=Ignore skips that: publish
# the app here, then publish the dependent with its matching source. Chicken-and-egg only, so
# always follow an Ignore with the dependent's own publish.
DEP_OPTION="${DEP_OPTION:-Default}"
ALC="/home/bryan/.vscode/extensions/ms-dynamics-smb.al-17.0.2273547/bin/linux/alc"
OUTPUT_DIR="$REPO/output"

chmod +x "$ALC" 2>/dev/null || true

# --- Token (silent from cache; prompts device-code + 2FA only on first run) ---
echo "[1/3] Acquiring BC access token..."
ACCESS_TOKEN=$(cd "$BASE" && python3 -c "from bc_auth import get_access_token; print(get_access_token())")

# --- Compile ---
echo "[2/3] Compiling AL project..."
mkdir -p "$OUTPUT_DIR"

APP_META=$(python3 -c "
import json
with open('$REPO/app.json') as f:
    d = json.load(f)
print(f\"{d['publisher']}_{d['name']}_{d['version']}.app\")
")
APP_FILE="$OUTPUT_DIR/$APP_META"

"$ALC" /project:"$REPO" /packagecachepath:"$REPO/.alpackages" /out:"$APP_FILE" 2>&1

if [[ ! -f "$APP_FILE" ]]; then
  echo "ERROR: Compilation failed — .app file not produced."
  exit 1
fi
echo "  Built: $APP_FILE ($(du -h "$APP_FILE" | cut -f1))"

# --- Publish ---
echo "[3/3] Publishing to BC ($ENV, SchemaUpdateMode=$SCHEMA_MODE, DependencyPublishingOption=$DEP_OPTION)..."
RESPONSE=$(curl -s -w "\n%{http_code}" \
  -X POST \
  "https://api.businesscentral.dynamics.com/v2.0/$TENANT/$ENV/dev/apps?SchemaUpdateMode=$SCHEMA_MODE&DependencyPublishingOption=$DEP_OPTION" \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -F "file=@$APP_FILE;type=application/octet-stream")

HTTP_STATUS=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -n -1)

if [[ "$HTTP_STATUS" == "200" || "$HTTP_STATUS" == "204" ]]; then
  echo "  Published successfully (HTTP $HTTP_STATUS)."
else
  echo "  ERROR: Publish failed (HTTP $HTTP_STATUS)."
  echo "  Response: $BODY"
  exit 1
fi
