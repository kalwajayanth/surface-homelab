#!/bin/bash
# Daily digest: updates, reboot flag, temperature, disk, memory,
# failed units, Docker containers, CrowdSec bans.
# Always sends. Urgency is encoded in the subject line so you can
# triage from the notification without opening it.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

ALERT_EMAIL="${ALERT_EMAIL:-root}"
TEMP_THRESHOLD="${TEMP_THRESHOLD:-75}"
SSH_HINT="${SSH_HINT:-}"
HOST=$(hostname)

# --- updates ---
SEC_UPDATES=$(apt-get -s -o Debug::NoLocking=true upgrade 2>/dev/null \
  | grep -c "^Inst.*securi" || true)
ALL_UPDATES=$(apt-get -s -o Debug::NoLocking=true upgrade 2>/dev/null \
  | grep -c "^Inst" || true)

if [ -f /var/run/reboot-required ]; then
    REBOOT="YES"
    REBOOT_PKGS=$(tr '\n' ' ' < /var/run/reboot-required.pkgs 2>/dev/null || true)
else
    REBOOT="no"
    REBOOT_PKGS=""
fi

# --- temperature: highest of all thermal zones ---
TEMP_MAX=0
for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    t=$(( $(cat "$z") / 1000 ))
    [ "$t" -gt "$TEMP_MAX" ] && TEMP_MAX=$t
done

# --- resources ---
DISK=$(df -h / | awk 'NR==2 {print $3" used of "$2" ("$5")"}')
DISK_PCT=$(df / | awk 'NR==2 {gsub("%","",$5); print $5}')
MEM=$(free -h | awk 'NR==2 {print $3" used of "$2}')
UPTIME=$(uptime -p)
LOAD=$(uptime | sed 's/.*load average: //')

# --- services ---
FAILED=$(systemctl list-units --state=failed --no-legend --no-pager | wc -l)
FAILED_LIST=$(systemctl list-units --state=failed --no-legend --no-pager \
  | awk '{print "    "$1}')

# --- docker (may not be installed) ---
DOCKER_UP=$(docker ps --format "{{.Names}}" 2>/dev/null | tr '\n' ' ' || true)
DOCKER_DOWN=$(docker ps -a --filter "status=exited" --format "{{.Names}}" 2>/dev/null \
  | tr '\n' ' ' || true)

# --- crowdsec (may not be installed) ---
CS_BANS=$(cscli decisions list -o json 2>/dev/null | grep -c '"type": "ban"' || true)
CS_ALERTS=$(cscli alerts list -o json 2>/dev/null | grep -c '"id"' || true)

# --- subject flags ---
FLAGS=""
[ "${SEC_UPDATES:-0}" -gt 0 ] && FLAGS="${FLAGS}[${SEC_UPDATES} security] "
[ "$REBOOT" = "YES" ]         && FLAGS="${FLAGS}[REBOOT] "
[ "$TEMP_MAX" -ge "$TEMP_THRESHOLD" ] && FLAGS="${FLAGS}[HOT ${TEMP_MAX}C] "
[ "${FAILED:-0}" -gt 0 ]      && FLAGS="${FLAGS}[${FAILED} failed] "
[ "${DISK_PCT:-0}" -ge 85 ]   && FLAGS="${FLAGS}[DISK ${DISK_PCT}%] "
[ -z "$FLAGS" ] && FLAGS="[ok] "

{
echo "Daily report for $HOST"
echo "$(date '+%A %d %B %Y, %H:%M %Z')"
echo "==========================================================="
echo
echo "UPDATES"
echo "  Security updates pending : ${SEC_UPDATES:-0}"
echo "  Total updates pending    : ${ALL_UPDATES:-0}"
echo "  Reboot required          : $REBOOT"
[ -n "$REBOOT_PKGS" ] && echo "    because of: $REBOOT_PKGS"
echo
echo "SYSTEM"
echo "  Temperature (max zone)   : ${TEMP_MAX}C"
echo "  Disk                     : $DISK"
echo "  Memory                   : $MEM"
echo "  Uptime                   : $UPTIME"
echo "  Load average             : $LOAD"
echo
echo "SERVICES"
echo "  Failed units             : ${FAILED:-0}"
[ "${FAILED:-0}" -gt 0 ] && echo "$FAILED_LIST"
echo "  Docker running           : ${DOCKER_UP:-none}"
[ -n "$DOCKER_DOWN" ] && echo "  Docker stopped           : $DOCKER_DOWN"
echo
echo "CROWDSEC"
echo "  Active bans              : ${CS_BANS:-0}"
echo "  Alerts recorded          : ${CS_ALERTS:-0}"
echo
if [ "${SEC_UPDATES:-0}" -gt 0 ] || [ "$REBOOT" = "YES" ]; then
echo "SUGGESTED"
[ "${SEC_UPDATES:-0}" -gt 0 ] && echo "  sudo apt update && sudo apt full-upgrade -y"
[ "$REBOOT" = "YES" ]         && echo "  sudo reboot"
echo
fi
echo "---"
[ -n "$SSH_HINT" ] && echo "$SSH_HINT"
} | mail -s "${FLAGS}${HOST} daily report" "$ALERT_EMAIL"
