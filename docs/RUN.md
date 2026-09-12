# Run the app

The API must be reachable first (see photo-atlas-api docs): `http://localhost:8787` by default.
Change it in **Settings → API server** when needed.

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

The production web build deployed by CI uses:

```bash
flutter build web --release --base-href "/photo-atlas-app/"
```

You can point the web build at an API at compile time:

```bash
flutter build web --release --dart-define=API_BASE_URL=http://192.168.1.20:8787
```

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
| Map tiles are blank | Network blocked: CARTO tiles require internet access |
| Local scan button disabled | The web build cannot read local folders: use Android/Linux or kDrive |
| Android build fails on signing | Create `android/key.properties` from `android/key.properties_sample` or use debug signing |
