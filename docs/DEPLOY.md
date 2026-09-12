# Deployment

All builds run on GitHub Actions, which is also the only way to produce binaries while developing
from the aarch64 device.

## Workflows

| Workflow | Trigger | Result |
|---|---|---|
| `ci.yml` | push / PR to `main` | `flutter pub get`, `gen-l10n`, `analyze` |
| `scaffold-platforms.yml` | manual | runs `flutter create` and commits `android/`, `linux/`, `web/` |
| `web-deploy.yml` | push to `main`, manual | builds the web app and deploys to GitHub Pages |
| `android-release-build.yml` | tag `v*`, manual | 3 ABI APKs + AAB; publishes a GitHub release on tags |
| `linux-build.yml` | tag `v*`, manual | Linux bundle for x86_64 |

Run the scaffold workflow once after the first push, before any other build.

## First-time setup

```bash
gh workflow run scaffold-platforms.yml --repo GiovanniDrago/photo-atlas-app
gh run watch --repo GiovanniDrago/photo-atlas-app
```

Enable Pages: **Settings → Pages → Source: GitHub Actions** (or run `web-deploy` after enabling).

## Release

```bash
./scripts/tag-release.sh v0.1.0
```

The script:

1. Computes the build number (`major*10000 + minor*100 + patch`), updates `pubspec.yaml`.
2. Commits the bump and pushes it.
3. Creates the annotated tag and pushes it.

GitHub Actions then builds and publishes:

- `app-armeabi-v7a-release.apk`
- `app-arm64-v8a-release.apk`
- `app-x86_64-release.apk`
- `app-release.aab`
- `photoatlas-linux-x86_64.tar.gz`

Linux arm64 bundles are not built because Flutter ships an x86_64-only Linux SDK; building them
requires a community arm64 Flutter SDK on an arm64 machine.

## Android signing secrets

Set these repository secrets before tagging (Settings → Secrets and variables → Actions):

| Secret | Content |
|---|---|
| `KEYSTORE_BASE64` | `base64 -w0 release.keystore` |
| `KEYSTORE_PASSWORD` | keystore password |
| `KEY_PASSWORD` | key password |
| `KEY_ALIAS` | key alias (`upload`) |

Create the keystore on a machine with a JDK:

```bash
keytool -genkey -v -keystore release.keystore -alias upload \
  -keyalg RSA -keysize 2048 -validity 10000
base64 -w0 release.keystore
```

If the secrets are missing the build continues with debug signing and prints a warning; installable
for testing, not for store or F-Droid distribution.

## Web

The deployed URL is `https://giovannidrago.github.io/photo-atlas-app/`. The API base URL can be set
in Settings at runtime, or baked in with a `--dart-define` in the workflow.

## Manual runs

Every build workflow accepts `workflow_dispatch`, so you can produce APKs, AAB and Linux bundles
without tagging:

```bash
gh workflow run android-release-build.yml --repo GiovanniDrago/photo-atlas-app
gh workflow run linux-build.yml --repo GiovanniDrago/photo-atlas-app
```
