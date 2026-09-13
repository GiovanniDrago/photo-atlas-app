#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEB_ROOT="${WEB_ROOT:-$ROOT_DIR/build/web-serve}"
WEB_PORT="${WEB_PORT:-8080}"
RUN_DIR="$ROOT_DIR/.run"
PID_FILE="$RUN_DIR/web.pid"

ip="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}')"
if [ -z "${ip:-}" ]; then
  ip="$(hostname -I | awk '{print $1}')"
fi
url="http://${ip:-localhost}:${WEB_PORT}/photo-atlas-app/"

stop() {
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE")"
    if kill -0 "$pid" 2>/dev/null; then
      kill "$pid"
      echo "[serve-web] stopped (pid $pid)"
    else
      echo "[serve-web] not running"
    fi
    rm -f "$PID_FILE"
  else
    echo "[serve-web] not running"
  fi
}

if [ ! -f "$WEB_ROOT/photo-atlas-app/index.html" ]; then
  echo "[serve-web] web build not found in $WEB_ROOT/photo-atlas-app" >&2
  echo "[serve-web] run scripts/fetch-web-build.sh first" >&2
  exit 1
fi

case "${1:-}" in
  --stop)
    stop
    ;;
  --background)
    if ss -ltn 2>/dev/null | grep -q ":${WEB_PORT} "; then
      echo "[serve-web] port ${WEB_PORT} already in use"
      exit 0
    fi
    mkdir -p "$RUN_DIR"
    nohup python3 -m http.server "$WEB_PORT" --bind 0.0.0.0 --directory "$WEB_ROOT" > "$RUN_DIR/web.log" 2>&1 &
    echo $! > "$PID_FILE"
    sleep 1
    echo "[serve-web] serving on 0.0.0.0:${WEB_PORT} (log: .run/web.log)"
    echo "[serve-web] open on the phone: ${url}"
    ;;
  *)
    echo "[serve-web] serving on 0.0.0.0:${WEB_PORT} (Ctrl+C to stop)"
    echo "[serve-web] open on the phone: ${url}"
    exec python3 -m http.server "$WEB_PORT" --bind 0.0.0.0 --directory "$WEB_ROOT"
    ;;
esac
