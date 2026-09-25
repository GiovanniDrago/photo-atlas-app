# Run the app

The API must be reachable first (see photo-atlas-api docs): `http://localhost:8787` by default.
Change it in **Settings → API server** when needed.

## First start

Login is mandatory. On the development database use **demo / demo**, or create a new account
(open registration, username and password only). Folders, media and the kDrive connection are tied
to the signed-in user. The server address can be set before login under **Server settings** on the
login screen (with a **Detect** button), and later in Settings.

## Gallery, details and export

- The gallery merges the **indexed items** (kDrive and scanned local folders) with the **files on
  this device** (the whole Android media library, or the local folders configured on desktop): the
  same photo appears once, with a badge telling its state — `cloud_done` uploaded, `cloud_queue`
  not uploaded, `cloud_off` failed, plus "On device" for files that are not indexed yet. Items are
  ordered by capture date, newest first; items without a date (no EXIF and no file date) go last
- The device library is read with an explicit date order in a single query (the platform default
  order is arbitrary and makes paged reads repeat or skip items) and matched to the indexed rows by
  asset id, falling back to name + size so a rebuilt media library (new asset ids) does not show
  the same photo twice. A small line under the filters shows how many items come from the device
  and from the cloud
- Filters: All / Photos / Videos / Not uploaded / Uploaded / No metadata. Pull down to refresh
- In the **timeline** (opened from the Collections card) long-press an item to select it like in
  the gallery: the bottom bar offers **Share**, **Download original** and **Delete** on the
  selection
- **Tap** an item to open the full screen viewer: the photo fills the screen, **swipe left/right**
  moves to the previous/next item and **scrolling vertically** reveals the details (all metadata
  fields, **Download original** for cloud items and a small map preview when the position is known;
  tap the map to open it in the maps app). The viewer menu has **Share**, **Upload** (when the
  file is not on kDrive yet), **Download original**, **Delete**, **Select** (goes back to the grid
  with the item selected) and **Open in Maps**. The **Path** row of a device file is tappable: it
  opens the system Files app on that folder. Swiping past the last photo of a day (or month)
  continues with the first one of the next period, and backwards. kDrive items are previewed at 1600 px on
  the fly (`/api/media/:id/thumbnail?w=1600`), device files are read locally
- **Long-press** to start the selection and **drag over the grid** to select (or deselect, when the
  long-pressed item was already selected) the items you pass; the grid scrolls automatically near
  the edges. In selection mode a tap toggles a single item; **Select all** selects the loaded ones,
  then
  - **Upload**: indexes the device files that are missing from the server (attaching them to the
    album/folder source) and uploads them to kDrive
  - **Share**: opens the system share sheet; cloud-only items are downloaded to a temporary file
    first
  - **Delete**: asks every time with two checkboxes — *From the cloud* (moves the kDrive copies to
    the trash, recoverable) and *From the device* (the Android system trash on Android 11+,
    recoverable, with the system confirmation prompt; on older versions the delete is permanent).
    Index rows left without any copy are dropped; when a copy survives the row is kept and its
    state updated
  - **Export metadata**: JSON file with all fields of the selected items
- Thumbnails are served through signed URLs and cached: the server stores kDrive previews and
  phone-uploaded previews on disk and the app/browser keeps its own cache; device files are read
  locally, without a round trip

## Collections (folders and timeline)

- The **Collections** tab is the entry point for browsing:
  - the big card on top previews the newest photos (device + cloud) and opens the **timeline**
    (day/week/month buckets with horizontal previews)
  - the **Folders** section lists every device folder (MediaStore bucket) that directly contains
    photos or videos: subfolders are folders of their own, and a folder with only subfolders never
    appears. Each card shows the folder path (to tell same-named folders apart), the item count, a
    thumbnail and the **Automatic upload** switch
- While the app is open the enabled folders are checked on open, on returning to the app and
  every 15 minutes: folders with pending files (or without a recent run) are scanned and uploaded
  right away one at a time; the periodic schedule only matters when the app is closed. Tap the
  progress bar to see the job state, the technical log, the files waiting for upload and to press
  **Backup now**, **Retry in background** or **Cancel**
- Turning the switch on indexes the folder (scan + database census, **without subfolders**) and
  uploads everything it contains. The run happens in a foreground service: it continues while you
  change screen, put the app in the background or close it, and a thin progress bar above every
  screen shows the phase, the counters, the queued folders and a **stop** button. Turning the
  switch off keeps the indexed items. If the background backup is off, the app asks whether to
  enable it
- The background job checks exactly the folders enabled here: on every run it scans each one and
  uploads what is missing (`docs/BACKUP.md`)
- Tapping a folder card opens the same gallery UI restricted to that folder: type filters are
  hidden, the header keeps the switch and the upload state, and selection actions (upload, share,
  delete) work as in the Gallery. Pulling down refreshes the media list **and** the uploaded
  counters; turning the switch off only stops future runs, the files already uploaded stay on
  kDrive. Device folders are only available in the Android app

## Albums

- The **Albums** tab lists every album with cover, name, item count and a **Manual** / **Smart**
  badge. Smart albums are resolved live from rules; manual membership is a database relation, so
  files are never moved or duplicated (`docs/ALBUMS.md`)
- **Create**: *+ → Manual album* (name only, then add items) or *+ → Smart album* (name + rules
  with a live matching-items preview). You can also create an album from a selection in the
  Gallery, Timeline or viewer with *Add to album → New album*
- **Smart rules**: capture date range, upload date range, location (center picked on the map) plus
  radius and media type; rules are combined with AND. New matching media appear automatically
- **Detail**: tap a card to open the album as a cloud-only gallery. Selection actions are share,
  download original, remove from album (manual) and use as cover; the card menu renames, edits the
  rules or deletes the album (relations only: photos, kDrive copies and device files stay)
- Device-only items are indexed (metadata + thumbnail) when you add them to an album; they are not
  uploaded to kDrive by that action

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

- Settings → About shows the installed version (`v0.8.0 (800)`) and a **Check for updates** button
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
