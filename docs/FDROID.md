# F-Droid

The repository contains everything F-Droid needs except the submission itself (no fork of
`fdroiddata` is created at this stage).

## Files

| File | Purpose |
|---|---|
| `fastlane/metadata/android/en-US/title.txt` | app name |
| `fastlane/metadata/android/en-US/short_description.txt` | < 80 characters |
| `fastlane/metadata/android/en-US/full_description.txt` | store description |
| `fastlane/metadata/android/en-US/changelogs/100.txt` | changelog for version code 100 |
| `fastlane/metadata/android/en-US/images/icon.png` | 512x512 icon |
| `fastlane/metadata/android/en-US/images/phoneScreenshots/` | add 1080x1920 screenshots before submitting |
| `fdroid/metadata/dev.giovannidrago.photoatlas.yml` | draft metadata for `fdroiddata` |

The Android package id is `dev.giovannidrago.photoatlas`.

## Before submitting

The draft still contains `TODO` values:

1. **commit**: push the release tag and use the full commit hash of that tag.
2. **AllowedAPKSigningKeys**: SHA-256 of the release certificate:

   ```bash
   keytool -printcert -jarfile app-arm64-v8a-release.apk
   ```

   Copy the SHA256 fingerprint into `AllowedAPKSigningKeys`.

3. **Screenshots**: at least one phone screenshot per locale in the fastlane folder.

## Prepare the upstream repository

The Android release workflow already implements the F-Droid requirements:

- ABI split with `--split-per-abi` and version codes `base*10 + 1/2/3`.
- `dependenciesInfo { includeInApk = false; includeInBundle = false }`.
- Reproducible build workspace and `SOURCE_DATE_EPOCH`.
- Flutter version pinned in `.github/workflows/android-release-build.yml` (read by the F-Droid
  prebuild step).

## Submission (when you decide to publish)

1. Fork <https://gitlab.com/fdroid/fdroiddata> and clone it.
2. Copy `fdroid/metadata/dev.giovannidrago.photoatlas.yml` to `metadata/` in the fork, completing the
   TODOs.
3. Validate locally:

   ```bash
   python3 -m venv ~/.local/venvs/fdroidserver
   source ~/.local/venvs/fdroidserver/bin/activate
   pip install fdroidserver
   fdroid rewritemeta dev.giovannidrago.photoatlas
   fdroid lint dev.giovannidrago.photoatlas
   git diff --stat
   ```

   If `rewritemeta` changes line wrapping, accept those exact changes: wrapping depends on character
   counts and must match.

4. Commit, push the branch and open a merge request on GitLab.

## Notes

- The `binary:` values point at the GitHub release APKs; F-Droid verifies they match a source build.
- `CurrentVersionCode` must always be the highest ABI code (`base*10 + 3`).
- Keep the signing keystore safe: losing it means changing `AllowedAPKSigningKeys` for future
  versions.
