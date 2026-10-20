#!/usr/bin/env bash
# Local release web build for GitHub Pages project site.
# Output: build/web  → publish via Actions or gh-pages branch.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

BASE_HREF="${BASE_HREF:-/Expensetrack/}"

# Flutter hooks_runner drops DEVELOPER_DIR; put our xcrun shim first on PATH so
# objective_c native-asset builds use Command Line Tools (no Xcode license).
export PATH="$ROOT/tool/bin:$PATH"
echo "==> PATH shim: $ROOT/tool/bin/xcrun"

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
flutter build web --release \
  --base-href "$BASE_HREF"

echo ""
echo "Build ready: $ROOT/build/web"
echo "Serve locally with correct base (example):"
echo "  cd build/web && python3 -m http.server 8080"
echo "  open http://localhost:8080/Expensetrack/   # if using a reverse-proxy path"
echo "Or push to main and let GitHub Actions deploy Pages."
