#!/bin/bash
# Installs the scripts and systemd units. Idempotent -- safe to re-run.
#
#   sudo ./install/install.sh
#
# It does NOT install packages or write credentials. See docs/SETUP.md.

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Run with sudo."; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="/opt/homelab"

echo "Installing scripts to $DEST"
mkdir -p "$DEST/scripts"
install -m 755 "$REPO"/scripts/*.sh "$DEST/scripts/"

echo "Installing systemd units"
install -m 644 "$REPO"/systemd/*.service /etc/systemd/system/
install -m 644 "$REPO"/systemd/*.timer   /etc/systemd/system/

mkdir -p /etc/homelab
if [ ! -f /etc/homelab/homelab.env ]; then
    install -m 600 "$REPO/config/homelab.env.example" /etc/homelab/homelab.env
    echo
    echo "  Created /etc/homelab/homelab.env from the example."
    echo "  EDIT IT before enabling the timers."
fi

systemctl daemon-reload

echo
echo "Installed. Now:"
echo "  1. sudo nano /etc/homelab/homelab.env"
echo "  2. Configure /etc/msmtprc (see config/msmtprc.example)"
echo "  3. Test mail:   echo test | sudo msmtp you@example.com"
echo "  4. Test report: sudo /opt/homelab/scripts/health-report.sh"
echo "  5. Enable:      sudo ./install/enable-timers.sh"
