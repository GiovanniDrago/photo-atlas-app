# Photo Atlas Studio (native Android)

Kotlin + Jetpack Compose rewrite of the Photo Atlas Flutter app, **Android only**.
It talks to the same API (`photo-atlas-api`) and keeps the same feature set, with a
curated Material 3 interface and a custom 3D globe renderer.

The app is intentionally a **separate install** from the Flutter build:

| | Flutter app | Native app |
|---|---|---|
| Label | Photo Atlas | Photo Atlas Studio |
| Application id | `dev.giovannidrago.photoatlas` | `dev.giovannidrago.photoatlas.studio` |

This folder is a standalone Gradle project; the Flutter project and the native one do not
affect each other.

## Build

Requires JDK 17+ and the Android SDK (compileSdk 37). In CI everything is set up by
`.github/workflows/native-android-build.yml`, which runs `./gradlew test assembleDebug
assembleRelease`, signs the release APK with the repository keystore secrets and (on
`native-v*` tags) publishes it on GitHub releases.

The APK that goes to the phone is copied to `/mnt/shared/debian/photo-atlas-studio/` (the
phone storage shared with Debian) together with its SHA-256 and a `LEGGIMI.txt`.

## Milestones

| | Content | Status |
|---|---|---|
| **M0** | Gradle project, Material 3 theme, shell with the 5 tabs + center action, CI workflow | done |
| **M1** | Server discovery/bootstrap, Supabase auth (login, signup, MFA TOTP, recovery codes), secure token storage, REST client, full Settings screen | done |
| **M2a** | Gallery: MediaStore + cloud merge, badges, filters, drag selection, full screen viewer (tag `native-v0.3.0`) | done |
| **M2b** | Gallery actions: upload/index, share, delete (cloud/device), export metadata (tag `native-v0.4.0`) | done |
| **M3** | Collections (folders + auto backup switch), timeline (day/week/month + continuous viewer) and albums (manual + smart rules with preview, upload retries, covers) — tag `native-v0.5.0` | done |
| **M4** | Curated 3D globe (custom Canvas renderer) + detailed map (osmdroid) + clusters + smart-album location rule | |
| **M5** | Backup: manual uploads, per-folder backup, verification, WorkManager job + foreground service, kDrive | |
| **M6** | Polish, it/en localization, tests, docs, parity checklist with the Flutter app | |

## Fixes

- **0.5.1** — a blank server address can no longer be stored (it poisoned every request and made
  the app report "unreachable" forever). Detection now also verifies `/api/config` before adopting
  an address, the LAN scan waits longer per host and the error screen shows the reason for every
  tried address (`timeout`, `connection refused`, `HTTP 500`, `not the Photo Atlas API`).

- **0.2.1** — the bootstrap now runs at startup (it only ran when the server address was saved from
  the settings dialog, so a fresh install stayed on the splash). The error screen also gained
  **Retry**, **Test connection**, the list of tried addresses and the detected candidates.

## Verified in M1

- Unit tests: server candidates/subnets, session mapping, auth flows against a MockWebServer
  (sign-in, wrong password, MFA challenge, refresh after 401, signup without session, recovery
  code generation, password reset, logout).
- End-to-end on the phone (login, MFA, recovery codes) is done by the user with a real account.

## Layout

```
android-native/
  app/src/main/java/dev/giovannidrago/photoatlas/studio/
    MainActivity.kt, StudioApplication.kt
    ui/            shell, screens, Material 3 theme
  app/src/main/res/  strings (en/it), themes, adaptive launcher icon
  gradle/            version catalog and wrapper
```
