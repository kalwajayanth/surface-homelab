#!/bin/bash
# Dead-man's switch. Pings an external service on a schedule; if the
# pings stop, that service alerts you. This is the ONLY alert that
# survives the server dying, because every other check runs on the
# server itself.
#
# Outbound only, so it works behind a firewall or mesh VPN with
# nothing exposed.

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

[ -z "${HEARTBEAT_URL:-}" ] && exit 0

curl -fsS -m 10 --retry 3 "$HEARTBEAT_URL" > /dev/null
