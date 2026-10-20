#!/usr/bin/env bash
# Local release web build for GitHub Pages project site.
# Output: build/web  → publish via Actions or gh-pages branch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_HREF="${BASE_HREF:-/Expensetrack/}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-}"
GOOGLE_ALLOWED_EMAILS="${GOOGLE_ALLOWED_EMAILS:-}"

# Flutter hooks_runner drops DEVELOPER_DIR; put our xcrun shim first on PATH so
# objective_c native-asset builds use Command Line Tools (no Xcode license).
export PATH="$ROOT/tool/bin:$PATH"
echo "==> PATH shim: $ROOT/tool/bin/xcrun"

if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
  echo "==> Injecting GOOGLE_CLIENT_ID into web/index.html"
  # macOS/BSD sed needs -i ''; GNU sed accepts -i.bak then remove.
  sed -i.bak "s/YOUR_GOOGLE_CLIENT_ID\\.apps\\.googleusercontent\\.com/${GOOGLE_CLIENT_ID}/g" \
    "$ROOT/web/index.html"
  rm -f "$ROOT/web/index.html.bak"
else
  echo "==> GOOGLE_CLIENT_ID unset — Drive sync UI will show “not configured”"
fi

if [[ -n "$GOOGLE_ALLOWED_EMAILS" ]]; then
  echo "==> GOOGLE_ALLOWED_EMAILS set (${GOOGLE_ALLOWED_EMAILS//,/; } )"
else
  echo "==> GOOGLE_ALLOWED_EMAILS unset — no Google accounts can sign in"
fi

echo "==> pub get"
flutter pub get

if [ ! -f web/sqlite3.wasm ] || [ ! -f web/sqflite_sw.js ]; then
  echo "==> SQLite web assets missing; running setup"
  ./tool/setup_web_sqlite.sh
fi

echo "==> analyze"
flutter analyze

echo "==> test"
flutter test

echo "==> build web (base-href=$BASE_HREF; offline via web/offline_sw.js)"
DEFINE_ARGS=()
if [[ -n "$GOOGLE_CLIENT_ID" ]]; then
  DEFINE_ARGS+=(--dart-define="GOOGLE_CLIENT_ID=$GOOGLE_CLIENT_ID")
fi
if [[ -n "$GOOGLE_ALLOWED_EMAILS" ]]; then
  DEFINE_ARGS+=(--dart-define="GOOGLE_ALLOWED_EMAILS=$GOOGLE_ALLOWED_EMAILS")
fi
flutter build web --release \
  --base-href "$BASE_HREF" \
  "${DEFINE_ARGS[@]}"

echo ""
echo "Build ready: $ROOT/build/web"
echo "Serve locally with correct base (example):"
echo "  cd build/web && python3 -m http.server 8080"
echo "  open http://localhost:8080/Expensetrack/   # if using a reverse-proxy path"
echo "Or push to main and let GitHub Actions deploy Pages."
