# ExpenseTrack

Offline-first personal expense tracker (Flutter + SQLite).  
Android app + installable **Progressive Web App** (Safari Add to Home Screen / Chrome install).

**No backend, no login, no cloud sync.** Data stays in on-device SQLite (native) or browser IndexedDB (web/PWA).

## Features

- Home dashboard, transactions, insights, budgets, categories  
- Light / dark / system themes, INR default  
- CSV import/export and JSON backup/restore (creates a real downloadable file)  
- Web PWA with offline app-shell caching after first visit  

## Run (local)

```bash
flutter pub get
flutter run                 # Android / device
flutter run -d chrome       # Web (keep a stable port — IndexedDB is per port)
```

## Web SQLite assets

Requires `web/sqlite3.wasm` and `web/sqflite_sw.js` ([sqflite_common_ffi_web](https://pub.dev/packages/sqflite_common_ffi_web)):

```bash
./tool/setup_web_sqlite.sh
# or: dart run sqflite_common_ffi_web:setup --force
```

## GitHub Pages (production PWA)

Repo: `https://github.com/faqs156/Expensetrack`  
Live URL (after Pages is enabled): **https://faqs156.github.io/Expensetrack/**

### One-time GitHub setup

1. Repo **Settings → Pages**  
2. Source: **GitHub Actions**  
3. Push to `main` (workflow `.github/workflows/deploy-github-pages.yml` builds with `--base-href /Expensetrack/`)

### Local release build

```bash
./tool/deploy_web.sh
# artifact in build/web
```

### Install on iPhone (Safari)

1. Open **https://faqs156.github.io/Expensetrack/** in **Safari** (HTTPS).  
2. Wait for the first load (caches the app shell + WASM).  
3. Share → **Add to Home Screen**.  
4. Open from the Home Screen icon (standalone).  
5. Add a transaction, force-quit, reopen — data should persist.  

**Backup tip:** Settings → Backup data downloads a JSON file. Browser storage can be cleared by Safari; backups are not automatic.

## Test / analyze

If `flutter test` fails on `objective_c` / `xcrun` (“Bad state: No element”), Xcode’s license is blocking the real `xcrun`. Prefer accepting the license (`sudo xcodebuild -license`), or prepend this repo’s shim (also used by `./tool/deploy_web.sh`):

```bash
export PATH="$PWD/tool/bin:$PATH"
flutter analyze
flutter test
flutter build web --release --base-href /Expensetrack/
```

Offline caching uses the custom service worker `web/offline_sw.js` (Flutter’s built-in SW is deprecated and only cleans up old workers).

## Privacy

- No accounts, analytics, or advertising SDKs in this version.  
- Web data: SQLite via WASM persisted in **IndexedDB** for that site origin.  
- Clearing site data / “Clear History and Website Data” deletes finances unless you restored from a JSON backup you saved earlier.  
