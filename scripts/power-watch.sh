#!/bin/bash
# Power transition watcher.
#
# When mains power is cut the machine keeps running on battery for a
# while. That window is the only chance to send a detailed alert from
# the server itself -- the external heartbeat only notices silence
# later, after the grace period, and by then the machine is gone.
#
# This script:
#   - emails immediately when AC is lost or restored
#   - emails and shuts down cleanly when the battery gets low,
#     so the filesystem is not left mid-write
#   - signals the external check on AC loss, so the dashboard shows
#     the outage without waiting for the grace period to expire
#
# It only emails on a CHANGE of state, so it is silent in normal use.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

ALERT_EMAIL="${ALERT_EMAIL:-root}"
LOW_PCT="${BATTERY_LOW_PCT:-20}"
CRITICAL_PCT="${BATTERY_CRITICAL_PCT:-10}"
STATE="/var/lib/homelab/power-state"
HOST=$(hostname)

mkdir -p "$(dirname "$STATE")"

# --- read AC adapter state -------------------------------------------
# 1 = on mains, 0 = on battery. Absent on desktops, in which case
# there is nothing to watch.
AC=""
for a in /sys/class/power_supply/A*/online /sys/class/power_supply/ADP*/online; do
    [ -r "$a" ] && { AC=$(cat "$a"); break; }
done
[ -z "$AC" ] && exit 0

# --- read battery -----------------------------------------------------
PCT=""
BAT_STATUS=""
for b in /sys/class/power_supply/BAT*; do
    [ -r "$b/capacity" ] || continue
    PCT=$(cat "$b/capacity")
    [ -r "$b/status" ] && BAT_STATUS=$(cat "$b/status")
    break
done
PCT="${PCT:-unknown}"
BAT_STATUS="${BAT_STATUS:-unknown}"

# --- rough runtime estimate, if the kernel exposes the counters -------
RUNTIME="unknown"
for b in /sys/class/power_supply/BAT*; do
    if [ -r "$b/power_now" ] && [ -r "$b/energy_now" ]; then
        pw=$(cat "$b/power_now"); en=$(cat "$b/energy_now")
        [ "$pw" -gt 0 ] 2>/dev/null && RUNTIME="about $(( en * 60 / pw )) minutes"
    elif [ -r "$b/current_now" ] && [ -r "$b/charge_now" ]; then
        cu=$(cat "$b/current_now"); ch=$(cat "$b/charge_now")
        [ "$cu" -gt 0 ] 2>/dev/null && RUNTIME="about $(( ch * 60 / cu )) minutes"
    fi
    break
done

PREV=""
[ -f "$STATE" ] && PREV=$(cat "$STATE")
echo "$AC" > "$STATE"

common_block() {
    echo "Time       : $(date '+%d %B %Y, %H:%M:%S %Z')"
    echo "Battery    : ${PCT}%"
    echo "Status     : $BAT_STATUS"
    [ "$AC" = "0" ] && echo "Est. left  : $RUNTIME"
    echo "Uptime     : $(uptime -p)"
    echo
    echo "Reconnect  : ${SSH_HINT:-see your notes}"
}

# --- AC lost ----------------------------------------------------------
if [ "$AC" = "0" ] && [ "$PREV" != "0" ]; then
    {
    echo "$HOST has lost mains power and is now running on battery."
    echo
    common_block
    echo
    echo "It will shut down cleanly on its own at ${CRITICAL_PCT}% battery."
    echo "If the outage looks long, shut it down now rather than letting"
    echo "the battery run flat:   sudo poweroff"
    } | mail -s "[POWER LOST] $HOST on battery, ${PCT}%" "$ALERT_EMAIL"

    # Tell the external check straight away rather than waiting for
    # the grace period to expire.
    if [ -n "${HEARTBEAT_URL:-}" ]; then
        curl -fsS -m 10 --data-raw \
          "AC LOST at $(date '+%H:%M %Z') -- battery ${PCT}%, $BAT_STATUS" \
          "${HEARTBEAT_URL%/}/fail" > /dev/null 2>&1 || true
    fi
fi

# --- AC restored ------------------------------------------------------
if [ "$AC" = "1" ] && [ "$PREV" = "0" ]; then
    {
    echo "$HOST is back on mains power."
    echo
    common_block
    } | mail -s "[POWER BACK] $HOST on mains, ${PCT}%" "$ALERT_EMAIL"
fi

# --- running on battery: warn once, then shut down --------------------
if [ "$AC" = "0" ] && [ "$PCT" != "unknown" ]; then

    if [ "$PCT" -le "$CRITICAL_PCT" ]; then
        {
        echo "$HOST battery is at ${PCT}%, at or below the critical"
        echo "threshold of ${CRITICAL_PCT}%. Shutting down cleanly now to"
        echo "avoid an abrupt power loss mid-write."
        echo
        common_block
        echo
        echo "It will NOT come back on its own when power returns --"
        echo "someone has to press the power button."
        } | mail -s "[SHUTTING DOWN] $HOST battery ${PCT}%" "$ALERT_EMAIL"

        sleep 20            # give the mail time to leave
        /sbin/shutdown -h now "Battery critical (${PCT}%)"
        exit 0
    fi

    if [ "$PCT" -le "$LOW_PCT" ] && [ ! -f "${STATE}.lowsent" ]; then
        {
        echo "$HOST battery is at ${PCT}%, below the warning threshold"
        echo "of ${LOW_PCT}%. Still running on battery."
        echo
        common_block
        echo
        echo "Automatic clean shutdown will happen at ${CRITICAL_PCT}%."
        } | mail -s "[BATTERY LOW] $HOST at ${PCT}%" "$ALERT_EMAIL"
        touch "${STATE}.lowsent"
    fi
else
    rm -f "${STATE}.lowsent"
fi
