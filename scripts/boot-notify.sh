#!/bin/bash
# Run once per boot by boot-notify.service. Emails that the server is back,
# how long it was down, and whether the previous shutdown was clean.
#
# Clean vs unclean comes from the marker shutdown-notify.sh leaves on the
# way down. No marker means the last boot ended without a clean shutdown:
# power loss, a crash, the power button held down, or a thermal cut-out.
#
# The network may not be up yet at boot (and after a power cut the router
# may still be starting), so it keeps trying to send for up to 30 minutes.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

ALERT_EMAIL="${ALERT_EMAIL:-root}"
HOST=$(hostname)
MARKER="/var/lib/homelab/clean-shutdown"

BOOT_EPOCH=$(date -d "$(uptime -s)" +%s)

CLEAN=no
SD_EPOCH=""
SD_KIND=""
if [ -f "$MARKER" ]; then
    read -r SD_EPOCH SD_KIND < "$MARKER" || true
    # Only trust a marker written before this boot started.
    if [ -n "$SD_EPOCH" ] && [ "$SD_EPOCH" -le "$BOOT_EPOCH" ] 2>/dev/null; then
        CLEAN=yes
    fi
    rm -f "$MARKER"
fi
if [ "$CLEAN" = no ]; then
    # Last thing the previous boot managed to log -- roughly when it died.
    SD_EPOCH=$(journalctl -b -1 -n 1 -q -o short-unix --no-pager 2>/dev/null \
      | awk 'NR==1 && $1 ~ /^[0-9]/ {print int($1)}')
fi

human() {   # seconds -> "3 h 05 min" / "26 min" / "40 s"
    local s=$1
    if   [ "$s" -ge 3600 ]; then printf '%d h %02d min' $((s / 3600)) $((s % 3600 / 60))
    elif [ "$s" -ge 60 ];   then printf '%d min' $((s / 60))
    else                         printf '%d s' "$s"
    fi
}

DOWN=""
if [ -n "$SD_EPOCH" ] && [ "$SD_EPOCH" -le "$BOOT_EPOCH" ] 2>/dev/null; then
    DOWN=$(human $((BOOT_EPOCH - SD_EPOCH)))
fi

if [ "$CLEAN" = yes ]; then
    SUBJECT="[back up] $HOST${DOWN:+ after $DOWN} (clean $SD_KIND)"
else
    SUBJECT="[BACK UP] $HOST after an UNCLEAN shutdown${DOWN:+, down ~$DOWN}"
fi

body() {
    echo "$HOST is back up."
    echo
    echo "Up since : $(date -d "@$BOOT_EPOCH" '+%d %B %Y, %H:%M:%S %Z')"
    if [ "$CLEAN" = yes ]; then
        echo "Previous : clean $SD_KIND at $(date -d "@$SD_EPOCH" '+%H:%M:%S on %d %b')"
    else
        echo "Previous : NOT a clean shutdown -- power loss, crash, power button"
        echo "           held down, or a thermal cut-out."
        [ -n "$SD_EPOCH" ] && echo "           Last log entry: $(date -d "@$SD_EPOCH" '+%H:%M:%S on %d %b')"
    fi
    [ -n "$DOWN" ] && echo "Down for : $DOWN"
    echo "Kernel   : $(uname -r)"
    for a in /sys/class/power_supply/A*/online; do
        [ -r "$a" ] && { [ "$(cat "$a")" = 1 ] && echo "Power    : mains" || echo "Power    : ON BATTERY"; break; }
    done
    for b in /sys/class/power_supply/BAT*; do
        [ -r "$b/capacity" ] && { echo "Battery  : $(cat "$b/capacity")%"; break; }
    done
    echo "Addresses: $(ip -4 -brief addr show scope global 2>/dev/null \
      | awk '$1 !~ /^(docker|br-|veth)/ {print $1" "$3}' | paste -sd ',' | sed 's/,/, /g')"
    FAILED=$(systemctl list-units --state=failed --no-legend --no-pager 2>/dev/null | awk '{print $1}' | paste -sd ' ')
    echo "Failed   : ${FAILED:-none}"
    if [ "$CLEAN" = no ]; then
        echo
        echo "Worth a look:  journalctl -b -1 -e --no-pager"
    fi
    echo
    echo "${SSH_HINT:-}"
}

for attempt in $(seq 1 60); do
    if { echo "To: $ALERT_EMAIL"
         echo "Subject: $SUBJECT"
         echo
         body
       } | /usr/sbin/sendmail -t 2>/dev/null; then
        exit 0
    fi
    sleep 30
done
echo "boot-notify: could not send mail after 30 minutes" >&2
exit 1
