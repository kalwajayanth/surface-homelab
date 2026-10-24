#!/bin/bash
# Removes the timers, units and scripts. Leaves /etc/homelab/homelab.env
# in place so you do not lose your settings.

set -uo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

for t in homelab-report homelab-temp homelab-lynis homelab-heartbeat; do
    systemctl disable --now "$t.timer" 2>/dev/null || true
    rm -f "/etc/systemd/system/$t.timer" "/etc/systemd/system/$t.service"
done
systemctl disable shutdown-notify.service 2>/dev/null || true
rm -f /etc/systemd/system/shutdown-notify.service
systemctl daemon-reload
rm -rf /opt/homelab/scripts

echo "Removed. /etc/homelab/homelab.env was left in place."
