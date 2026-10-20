# ExpenseTrack

Offline-first personal expense tracker (Flutter + SQLite).  
Android app + installable **Progressive Web App** (Safari Add to Home Screen / Chrome install).

**Local SQLite always.** Optional **Google Sign-In → private Google Drive app-data file** so the same Google account shares one vault across phones and browsers.

## Features

- Home dashboard, transactions, insights, budgets, categories  
- Light / dark / system themes, INR default  
- CSV import/export and JSON backup/restore  
- Optional Google Drive sync (last-write-wins)  
- Web PWA with offline app-shell caching after first visit  

## Run (local)

```bash
flutter pub get
flutter run                 # Android / device
flutter run -d chrome --web-hostname localhost --web-port 7357 \
  --dart-define=GOOGLE_CLIENT_ID=YOUR_ID.apps.googleusercontent.com
```

## Google Drive sync (one-time Google Cloud setup)

1. [Google Cloud Console](https://console.cloud.google.com/) → create/select a project  
2. **APIs & Services → Library** → enable **Google Drive API**  
3. **OAuth consent screen** → External (or Internal) → add scopes:
   - `.../auth/drive.appdata`
   - `email`, `openid`  
   Add yourself as a **Test user** while the app is in Testing  
4. **Credentials → Create credentials → OAuth client ID → Web application**  
   - Authorized JavaScript origins:
     - `http://localhost:7357`
     - `https://faqs156.github.io`  
   - Authorized redirect URIs (if asked): `https://faqs156.github.io/Expensetrack/`  
5. Copy the client ID (`….apps.googleusercontent.com`)

### Wire the client ID into the app

1. Put it in `web/index.html` meta `google-signin-client_id`  
2. Pass the same value at build time:

```bash
export GOOGLE_CLIENT_ID='xxxx.apps.googleusercontent.com'
# also patches web/index.html meta for local deploy script
./tool/deploy_web.sh
```

### GitHub Actions secrets (Repository secrets)

| Secret | Example | Purpose |
|--------|---------|---------|
| `GOOGLE_CLIENT_ID` | `xxxx.apps.googleusercontent.com` | OAuth web client |
| `GOOGLE_ALLOWED_EMAILS` | `you@gmail.com;partner@gmail.com` | Only these accounts can **open the app** |

Use `;` between emails (recommended). Commas work if the secret has no broken quoting.  
Case-insensitive. Without both secrets, the deploy **fails** and the app stays locked.

After sign-in, ExpenseTrack stores `expense_track_sync.json` in Drive **appDataFolder** (hidden from My Drive). Same account on another device pulls that file.

## Web SQLite assets

```bash
./tool/setup_web_sqlite.sh
# or: dart run sqflite_common_ffi_web:setup --force
```

## GitHub Pages (production PWA)

Live URL: **https://faqs156.github.io/Expensetrack/**

1. Repo **Settings → Pages** → Source: **GitHub Actions**  
2. Add secret `GOOGLE_CLIENT_ID` (optional but required for Drive sync)  
3. Push to `main`

### Install on iPhone (Safari)

1. Open the live URL in **Safari**  
2. Share → **Add to Home Screen**  
3. Sign in with Google (prompt or Settings) to sync across devices  

## Test / analyze

If `flutter test` fails on `objective_c` / `xcrun`, prepend this repo’s shim:

```bash
export PATH="$PWD/tool/bin:$PATH"
flutter analyze
flutter test
```

## Privacy

- No advertising or analytics SDKs  
- Default: data only in local SQLite / IndexedDB  
- Optional: sync file in your Google Drive app data (your account; we don’t run a server)  
- JSON Backup/Restore still available as a manual escape hatch  
