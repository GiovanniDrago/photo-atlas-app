#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="GiovanniDrago/photo-atlas-app"
DEST="$ROOT_DIR/build/web-serve"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

run_id="$(gh run list --repo "$REPO" --workflow web-build.yml --status success --limit 1 --json databaseId --jq '.[0].databaseId')"
if [ -z "$run_id" ]; then
  echo "[fetch-web-build] no successful web-build run found" >&2
  exit 1
fi

echo "[fetch-web-build] downloading web-build artifact from run $run_id"
gh run download "$run_id" --repo "$REPO" --name web-build --dir "$TMP"

target="$DEST/photo-atlas-app"
rm -rf "$target"
mkdir -p "$target"

archive="$(find "$TMP" -name 'artifact.tar' -type f -print -quit)"
if [ -n "$archive" ]; then
  tar -xf "$archive" -C "$target"
elif [ -f "$TMP/build/web/index.html" ]; then
  cp -a "$TMP/build/web/." "$target/"
elif [ -f "$TMP/index.html" ]; then
  cp -a "$TMP/." "$target/"
else
  echo "[fetch-web-build] unexpected artifact layout:" >&2
  find "$TMP" -maxdepth 3 >&2
  exit 1
fi

if [ ! -f "$target/index.html" ]; then
  echo "[fetch-web-build] index.html not found after extraction" >&2
  exit 1
fi

echo "[fetch-web-build] ready: $target"
echo "[fetch-web-build] serve it with: scripts/serve-web.sh"
