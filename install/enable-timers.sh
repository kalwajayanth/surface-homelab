#!/bin/bash
# Enables the timers. Run only after install.sh and a successful mail test.

set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

systemctl daemon-reload
systemctl enable --now homelab-report.timer
systemctl enable --now homelab-temp.timer
systemctl enable --now homelab-lynis.timer

if grep -q '^HEARTBEAT_URL="https' /etc/homelab/homelab.env 2>/dev/null; then
    systemctl enable --now homelab-heartbeat.timer
    systemctl start homelab-heartbeat.service
    echo "Heartbeat enabled."
else
    echo "HEARTBEAT_URL not set -- skipping the heartbeat timer."
fi

echo
systemctl list-timers --all | grep -E 'homelab|NEXT' || true
