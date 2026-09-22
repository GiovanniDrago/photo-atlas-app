# Run the app

The API must be reachable first (see photo-atlas-api docs): `http://localhost:8787` by default.
Change it in **Settings → API server** when needed.

## First start

Login is mandatory. On the development database use **demo / demo**, or create a new account
(open registration, username and password only). Folders, media and the kDrive connection are tied
to the signed-in user. The server address can be set before login under **Server settings** on the
login screen (with a **Detect** button), and later in Settings.

## Gallery, details and export

- Tap any thumbnail (gallery, timeline, map list) to open the media detail: big preview, every
  metadata field and **Download original** (full quality, straight from kDrive when available; the
  button is hidden for local items whose file is already on this device)
- In the gallery, long-press to enter selection mode: tap to add/remove items, use **Select all**,
  then **Export metadata** to download a JSON file with all fields of the selected items
- Thumbnails are served through signed URLs and cached: the server stores kDrive previews and
  phone-uploaded previews on disk and the app/browser keeps its own cache

## Account and security

- The app signs in through **Supabase Auth**; the API only verifies the access token. The Supabase
  URL and publishable key come from `GET /api/config` on the configured server, so nothing is baked
  into the build
- Sign up with **email + password**: Supabase sends a confirmation email (link handled by the
  Netlify page configured in the Supabase dashboard); until it is confirmed the app shows "check
  your email". After the first sign-in the app shows the one-time **recovery codes**
- **Settings → Security**:
  - *Two-factor authentication*: enable with any TOTP app (QR code), disable from the same screen
  - *Regenerate recovery codes*: new password-reset codes (and MFA codes when 2FA is on)
  - *Sign out everywhere*: revokes the session on every device
- **Forgot password**: sign-in screen → *Reset a forgotten password* → email + one recovery code +
  new password. Break-glass on the server: `npm run reset-password -- <email>` (API repo)
- **Lost the 2FA device**: on the MFA screen → *Lost your device?* → email + one MFA recovery code
  removes the authenticator; an admin can also delete the factor from the Supabase dashboard
- The Supabase session (access + refresh token) is stored in the platform secure storage
  (Android Keystore; web falls back to browser storage when WebCrypto is unavailable)

## Backup to kDrive

- Central **+** button in the bottom bar → Backup screen: *Upload files* opens a multi-select
  picker (all device photos/videos) and uploads the originals to `Media/PhotoAtlas/Manual`
- *Back up all* / per-folder *Back up now* upload the indexed originals of a scanned folder to
  `Media/PhotoAtlas/<folder>`; *Verify backup* checks on kDrive that every file still exists
- Gallery, timeline and detail show a cloud badge (uploaded / pending / failed); details in
  [BACKUP.md](BACKUP.md)
- On Android the Backup screen has an **Automatic backup** switch (off by default): a periodic
  WorkManager job scans the selected folders and uploads new photos in the background, with a
  notification while it runs. Frequency, *Only on Wi-Fi* and *Only while charging* are configurable
- kDrive must be connected in Settings → kDrive; uploads need the API to be reachable

## Updates

- Settings → About shows the installed version (`v0.7.0 (700)`) and a **Check for updates** button
- The app also checks silently once a day at startup; when a newer GitHub release exists it offers
  to download it (Android: the arm64 APK; Linux: the bundle) and opens the browser
- "Later" silences that version for the silent check; the manual check always reports the result

## Local folders

- Settings → **Local folders** lists every added folder with its indexed count, last scan and a
  menu (**Scan again**, **Delete** — index only, files are never touched)
- **Android**: *Add folder* opens the system media **album picker** (Camera, Download, app albums…).
  Albums are read through the MediaStore API, so capture date, GPS, dimensions and duration come
  from the system library; grant the media permission and the photo **location** permission when
  asked (without the location grant Android hides EXIF GPS). Preview thumbnails are generated on
  the phone and uploaded to the API, so the app, web and map show the same pictures. This is the only
  reliable way to scan media under Android's scoped storage (a plain folder path returned by a file
  picker cannot be read)
- **Linux desktop**: *Add folder* uses the system folder dialog and reads EXIF (date, GPS) from the
  image files
- **Web**: local scanning is not available (explained in the UI); use kDrive or the Android/Linux app

## Android

```bash
flutter devices
flutter run -d <device-id>
```

- Emulator: use `http://10.0.2.2:8787` as the API URL.
- Physical device: use the computer LAN address, for example `http://192.168.1.20:8787`, and keep
  both on the same network.

Release build (needs signing files, see [FDROID.md](FDROID.md)):

```bash
flutter build apk --release --split-per-abi
flutter build appbundle --release
```

## Linux desktop

```bash
flutter run -d linux
flutter build linux --release
```

## Web

```bash
flutter run -d chrome
```

Serve on the local network so a phone browser can open it:

```bash
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8080
```

Then open `http://<computer-ip>:8080`.

On this machine the Flutter tool cannot run; use the CI-built preview instead:

```bash
scripts/fetch-web-build.sh   # downloads the latest GitHub Pages artifact
scripts/serve-web.sh         # prints http://<vm-ip>:8080/photo-atlas-app/
```

The web build defaults its API to `http://<same host>:8787`, so opening the printed URL is enough;
**Settings → Detect** finds a reachable server if a different one is stored.

The production web build deployed by CI uses:

```bash
flutter build web --release --base-href "/photo-atlas-app/"
```

You can point the web build at an API at compile time:

```bash
flutter build web --release --dart-define=API_BASE_URL=http://192.168.1.20:8787
```

## Server address

- The app ships with `http://10.234.121.225:8787` as the default API address (Android/Linux); the
  web build uses the host that serves the page
- When the API does not answer, the app tries the known addresses and then shows **Server settings**
  (also reachable from the loading screen after a few seconds) with *Test connection*, *Detect*
  (known addresses plus a scan of the local `/24` on port 8787) and a manual field
- The address is stored per installation, so it survives app restarts

## Checks

```bash
flutter analyze
flutter gen-l10n
```

## Troubleshooting

| Symptom | Fix |
|---|---|
| `This application is not configured to build on the web` | Run the scaffold workflow or `flutter create --platforms=web .` |
| Images do not load in the gallery | The API is unreachable: check the health chip in Settings |
| The app stays on the loading screen at startup | The API address changed (the VM hotspot hands out a new subnet). The app detects it automatically after a few seconds; if not, tap **Server settings** on the loading screen, then **Detect** (it also scans the local network) or type the new address |
| Map tiles are blank | Network blocked: CARTO tiles require internet access |
| Local scan button disabled | The web build cannot read local folders: use Android/Linux or kDrive |
| Android build fails on signing | Create `android/key.properties` from `android/key.properties_sample` or use debug signing |
