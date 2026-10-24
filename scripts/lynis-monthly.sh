#!/bin/bash
# Monthly hardening audit. Emails the index plus warnings and the
# first 25 suggestions.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"
ALERT_EMAIL="${ALERT_EMAIL:-root}"

lynis audit system --quiet --no-colors > /tmp/lynis-run.txt 2>&1 || true

INDEX=$(grep -i "hardening index" /tmp/lynis-run.txt | tail -1 || true)
WARNINGS=$(grep "^warning\[\]=" /var/log/lynis-report.dat 2>/dev/null \
  | sed 's/^warning\[\]=/  - /' || true)
SUGGESTIONS=$(grep "^suggestion\[\]=" /var/log/lynis-report.dat 2>/dev/null \
  | sed 's/^suggestion\[\]=/  - /' | head -25 || true)

{
echo "Monthly Lynis audit -- $(hostname) -- $(date '+%d %B %Y')"
echo "==========================================================="
echo
echo "${INDEX:-Hardening index not found in output}"
echo
echo "WARNINGS"
echo "${WARNINGS:-  none}"
echo
echo "SUGGESTIONS (first 25)"
echo "${SUGGESTIONS:-  none}"
echo
echo "---"
echo "Lynis assumes a production, internet-facing server. A box reachable"
echo "only over LAN and a mesh VPN can ignore suggestions about mail"
echo "servers, intrusion detection and partition layout."
echo "Usually worth acting on: kernel sysctl settings, file permissions,"
echo "and unused services still running."
echo
echo "Full report: /var/log/lynis-report.dat"
} | mail -s "Monthly Lynis audit -- $(hostname)" "$ALERT_EMAIL"
