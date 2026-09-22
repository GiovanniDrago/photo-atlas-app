#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
UNIT_FILE="$UNIT_DIR/photo-atlas-web.service"
SERVICE_NAME="photo-atlas-web.service"

mkdir -p "$UNIT_DIR"
cat > "$UNIT_FILE" <<EOF
[Unit]
Description=Photo Atlas web preview (CI build served locally)
After=network-online.target

[Service]
WorkingDirectory=$ROOT_DIR
ExecStart=/usr/bin/env bash $ROOT_DIR/scripts/serve-web.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
EOF
chmod 600 "$UNIT_FILE"

systemctl --user daemon-reload
systemctl --user enable --now "$SERVICE_NAME"
systemctl --user status "$SERVICE_NAME" --no-pager | head -12

echo
echo "[install-web-service] unit:   $UNIT_FILE"
echo "[install-web-service] logs:   journalctl --user -u $SERVICE_NAME -f"
echo "[install-web-service] stop:   systemctl --user stop $SERVICE_NAME"
echo "[install-web-service] note:   starts with the ${USER:-user} session; for boot start run:"
echo "                              sudo loginctl enable-linger ${USER:-user}"
