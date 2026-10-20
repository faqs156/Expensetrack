#!/usr/bin/env bash
# Regenerates web/sqlite3.wasm and web/sqflite_sw.js for sqflite_common_ffi_web.
# Official path (preferred when Xcode / native-assets hooks work):
#   dart run sqflite_common_ffi_web:setup --force
#
# Fallback used when `dart run` fails on native-asset hooks (e.g. Xcode license):
#   1) dart compile js of the package shared-worker entrypoint
#   2) curl the wasm release pinned in sqflite_common_ffi_web 1.2.0
#      (lib/src/setup/sqlite3_wasm_version.dart → sqlite3-3.6.0/sqlite3.wasm)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if command -v flutter >/dev/null 2>&1; then
  DART="$(dirname "$(dirname "$(command -v flutter)")")/bin/cache/dart-sdk/bin/dart"
  if [[ ! -x "$DART" ]]; then
    DART="dart"
  fi
else
  DART="dart"
fi

echo "Trying official setup…"
if "$DART" run sqflite_common_ffi_web:setup --force; then
  echo "Official setup completed."
  ls -lh web/sqlite3.wasm web/sqflite_sw.js
  exit 0
fi

echo "Official setup failed; using documented fallback…"
PKG_CONFIG=".dart_tool/package_config.json"
PKG_URI="$(python3 - <<'PY'
import json
from pathlib import Path
cfg = json.loads(Path(".dart_tool/package_config.json").read_text())
for p in cfg["packages"]:
    if p["name"] == "sqflite_common_ffi_web":
        print(p["rootUri"].replace("file://", ""))
        break
PY
)"
SW_DART="${PKG_URI}/web/sqflite_sw.dart"
"$DART" compile js --packages="$PKG_CONFIG" "$SW_DART" -O2 -o web/sqflite_sw.js
curl -L --fail --retry 3 \
  -o web/sqlite3.wasm \
  "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.6.0/sqlite3.wasm"
ls -lh web/sqlite3.wasm web/sqflite_sw.js
echo "Fallback assets written to web/"
