#!/bin/bash
# Dead-man's switch. Pings an external service on a schedule; if the
# pings stop, that service alerts you. This is the ONLY alert that
# survives the server dying, because every other check runs on the
# server itself.
#
# Outbound only, so it works behind a firewall or mesh VPN with
# nothing exposed.
#
# The ping is a POST carrying a short diagnostic line. Healthchecks
# stores the request body against each ping, so when a DOWN alert
# arrives you can open the check's event log and read the state at the
# moment of the last successful ping -- including battery percentage,
# which is what you want to know during a power cut.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

[ -z "${HEARTBEAT_URL:-}" ] && exit 0

# --- battery and mains, if present ---
PCT="n/a"; BAT_STATUS=""; AC_TEXT=""
for b in /sys/class/power_supply/BAT*; do
    [ -r "$b/capacity" ] || continue
    PCT="$(cat "$b/capacity")%"
    [ -r "$b/status" ] && BAT_STATUS=" ($(cat "$b/status"))"
    break
done
for a in /sys/class/power_supply/A*/online /sys/class/power_supply/ADP*/online; do
    if [ -r "$a" ]; then
        [ "$(cat "$a")" = "1" ] && AC_TEXT="mains" || AC_TEXT="ON BATTERY"
        break
    fi
done

# --- temperature: highest zone ---
TEMP=0
for z in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$z" ] || continue
    t=$(( $(cat "$z") / 1000 ))
    [ "$t" -gt "$TEMP" ] && TEMP=$t
done

DISK=$(df / | awk 'NR==2 {print $5}')
LOAD=$(cut -d' ' -f1-3 /proc/loadavg)

BODY="$(hostname) ok | battery ${PCT}${BAT_STATUS}${AC_TEXT:+ | power ${AC_TEXT}} | temp ${TEMP}C | disk ${DISK} | load ${LOAD} | up $(uptime -p)"

curl -fsS -m 10 --retry 3 --data-raw "$BODY" "$HEARTBEAT_URL" > /dev/null
