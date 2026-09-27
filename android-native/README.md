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
| **M1** | Server discovery/bootstrap, Supabase auth (login, signup, MFA TOTP, recovery codes), secure token storage, REST client | next |
| **M2** | Gallery: MediaStore + cloud merge, badges, filters, selection actions, full screen viewer | |
| **M3** | Collections, timeline, albums (manual + smart rules with map radius, upload retries, covers) | |
| **M4** | Curated 3D globe (custom Canvas renderer) + detailed map (osmdroid) + clusters | |
| **M5** | Backup: manual uploads, per-folder backup, verification, WorkManager job + foreground service, kDrive | |
| **M6** | Polish, it/en localization, tests, docs, parity checklist with the Flutter app | |

## Layout

```
android-native/
  app/src/main/java/dev/giovannidrago/photoatlas/studio/
    MainActivity.kt, StudioApplication.kt
    ui/            shell, screens, Material 3 theme
  app/src/main/res/  strings (en/it), themes, adaptive launcher icon
  gradle/            version catalog and wrapper
```
