#!/bin/bash
# Enables the timers. Run only after install.sh and a successful mail test.

set -euo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

systemctl daemon-reload
systemctl enable --now homelab-report.timer
systemctl enable --now homelab-temp.timer
systemctl enable --now homelab-lynis.timer

# Only useful on a machine with a battery.
if compgen -G '/sys/class/power_supply/BAT*' > /dev/null; then
    systemctl enable --now homelab-power.timer
    echo "Power/battery watch enabled."
fi

# Shutdown and back-up-again notices. shutdown-notify must be running so
# that stopping it at shutdown sends the mail; boot-notify only runs at boot
# (starting it now would announce a boot that did not happen).
systemctl enable --now shutdown-notify.service
systemctl enable boot-notify.service
echo "Shutdown and boot notices enabled."

if [ -s /etc/homelab/backup.pass ]; then
    systemctl enable --now homelab-backup.timer
    echo "Monthly encrypted backup enabled."
else
    echo "No /etc/homelab/backup.pass -- skipping the backup timer (see docs/SETUP.md)."
fi

if grep -q '^HEARTBEAT_URL="https' /etc/homelab/homelab.env 2>/dev/null; then
    systemctl enable --now powerMonitor.timer
    systemctl start powerMonitor.service
    echo "Heartbeat enabled."
else
    echo "HEARTBEAT_URL not set -- skipping the heartbeat timer."
fi

echo
systemctl list-timers --all | grep -E 'homelab|powerMonitor|NEXT' || true
