#!/usr/bin/env bash
# Copies the APK of a published native release into the phone shared folder,
# ready to install: verifies the CI checksum and refreshes SHA256.txt.
#
# Usage: android-native/scripts/deliver-to-shared.sh <tag>   (example: native-v0.6.0)
#
# Run from inside the repository clone: gh infers the repository from the git
# remote, so no account names are stored here. LEGGIMI.txt is hand-written and
# is not touched: the script prints the file name and SHA-256 to update it.
set -euo pipefail

TAG="${1:-}"
DEST="${DEST:-/mnt/shared/debian/photo-atlas-studio}"

if [[ -z "$TAG" ]]; then
  echo "Usage: $0 <tag> (example: native-v0.6.0)" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Run this script inside the repository clone (gh needs the git remote)" >&2
  exit 1
fi

mkdir -p "$DEST"

gh release download "$TAG" \
  --pattern '*.apk' \
  --pattern '*.sha256' \
  --clobber \
  --dir "$DEST"

APK="$(find "$DEST" -maxdepth 1 -name '*.apk' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f 2-)"
APK_NAME="$(basename "$APK")"

if [[ ! -f "$DEST/${APK_NAME}.sha256" ]]; then
  echo "Missing ${APK_NAME}.sha256 next to the APK" >&2
  exit 1
fi

(cd "$DEST" && sha256sum -c "${APK_NAME}.sha256")
(cd "$DEST" && sha256sum PhotoAtlasStudio-*.apk > SHA256.txt)

CHECKSUM="$(cd "$DEST" && sha256sum "$APK_NAME" | cut -d' ' -f 1)"

echo "Delivered ${APK_NAME} to ${DEST}"
echo "SHA-256: ${CHECKSUM}"
echo "Update LEGGIMI.txt with the version, the file name and this SHA-256."
