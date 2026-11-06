#!/bin/bash
# Run by shutdown-notify.service (ExecStop) as the system goes down cleanly.
#
#   - leaves a marker in /var/lib/homelab so boot-notify.sh can tell, on the
#     next boot, that this shutdown was clean and when it happened
#   - emails immediately, saying whether it is a reboot or a power-off and,
#     where the log shows it, what asked for it

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

ALERT_EMAIL="${ALERT_EMAIL:-root}"
HOST=$(hostname)
MARKER="/var/lib/homelab/clean-shutdown"

# What is the system doing? The queued systemd job says.
KIND=""
JOBS=$(systemctl list-jobs --no-legend --no-pager 2>/dev/null || true)
case "$JOBS" in
    *reboot.target*)   KIND="reboot" ;;
    *kexec.target*)    KIND="reboot" ;;
    *poweroff.target*) KIND="power-off" ;;
    *halt.target*)     KIND="halt" ;;
esac

# Who asked? Look at the last couple of minutes of the log.
REASON=$(journalctl --since "-3 min" -o cat --no-pager 2>/dev/null \
  | grep -E 'Power key pressed|COMMAND=.*(reboot|poweroff|shutdown|halt)|Battery critical' \
  | tail -1 \
  | sed -E 's/.*Power key pressed.*/the power button was pressed/;
            s/^ *([a-z_][a-z0-9_-]*) : .*COMMAND=([^ ]+).*/\1 ran \2/;
            s/.*(Battery critical.*)/\1/')

if [ -z "$KIND" ]; then
    # Not a real shutdown -- someone stopped or restarted this service by
    # hand. Mail so the test is visible, but leave no marker: a stale one
    # would make the next boot report a crash as a clean shutdown.
    echo "shutdown-notify was stopped on $HOST at $(date '+%H:%M:%S %Z'), but the system is NOT going down (service test or restart)." \
      | mail -s "[shutdown test] $HOST" "$ALERT_EMAIL"
    exit 0
fi

mkdir -p "$(dirname "$MARKER")"
echo "$(date +%s) $KIND" > "$MARKER"
sync

{
echo "$HOST is going down cleanly: $KIND."
echo
echo "Time    : $(date '+%d %B %Y, %H:%M:%S %Z')"
[ -n "$REASON" ] && echo "Cause   : $REASON"
echo "Uptime  : $(uptime -p)"
echo
if [ "$KIND" = "reboot" ]; then
    echo "A \"[back up]\" mail should follow within a few minutes. If it does"
    echo "not, the restart may have stalled -- see RUNBOOK: Did not come back."
else
    echo "It will not come back by itself; someone has to press the power button."
fi
} | mail -s "[shutdown] $HOST ($KIND)" "$ALERT_EMAIL"
