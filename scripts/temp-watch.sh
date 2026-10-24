#!/bin/bash
# Runs every 15 minutes but stays SILENT unless the threshold is crossed,
# so a mail from this script always means something.
# A cooldown prevents one hot afternoon from filling the inbox.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

ALERT_EMAIL="${ALERT_EMAIL:-root}"
THRESHOLD="${TEMP_THRESHOLD:-75}"
COOLDOWN="${TEMP_COOLDOWN:-10800}"
STATE="/run/homelab-temp-alert"

TEMP_MAX=0
for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    t=$(( $(cat "$z") / 1000 ))
    [ "$t" -gt "$TEMP_MAX" ] && TEMP_MAX=$t
done

if [ "$TEMP_MAX" -lt "$THRESHOLD" ]; then
    rm -f "$STATE"
    exit 0
fi

now=$(date +%s)
last=0
[ -f "$STATE" ] && last=$(cat "$STATE")
[ $(( now - last )) -lt "$COOLDOWN" ] && exit 0

{
echo "Temperature on $(hostname) has reached ${TEMP_MAX}C."
echo "Warning threshold is ${THRESHOLD}C."
echo
echo "Time : $(date '+%d %B %Y, %H:%M %Z')"
echo "Load : $(uptime | sed 's/.*load average: //')"
echo
echo "Top processes by CPU:"
ps -eo pcpu,pmem,comm --sort=-pcpu | head -6 | sed 's/^/    /'
echo
echo "Check that it is on a hard surface with the back exposed,"
echo "with nothing wrapped around it and nothing blocking airflow."
echo "If it stays high, point a fan at it."
} | mail -s "[HOT ${TEMP_MAX}C] $(hostname) temperature alert" "$ALERT_EMAIL"

echo "$now" > "$STATE"
