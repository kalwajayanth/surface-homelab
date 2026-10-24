# Design notes

Why things are the way they are.

---

## The constraint

No usable screen. Every decision follows from that: nothing may require
console interaction, boot must never block waiting for something, and the
machine must report its own state because nobody is watching it.

---

## Why a dead-man's switch

Every other check runs on the server. If the server dies, they die with it,
and silence is indistinguishable from "everything is fine."

An external service expecting a regular ping inverts that: the alert comes
from somewhere that is still alive. It is outbound-only, so it works behind
a firewall and a mesh VPN with nothing exposed.

This is the one alert that cannot be replaced by something running locally.

---

## Why the daily report always sends

A report that only arrives when something is wrong trains you to ignore the
absence of mail. You cannot tell "nothing wrong" from "cron broke three weeks
ago."

A daily `[ok]` is a heartbeat you read. Urgency goes in the subject line
(`[3 security]`, `[REBOOT]`, `[HOT 78C]`) so it is triageable from a phone
notification without opening anything.

The temperature watcher is the opposite on purpose: silent unless something
is wrong, because it runs every 15 minutes. Mixing the two patterns in one
channel would make both useless.

---

## Why config lives outside the repo

`/etc/homelab/homelab.env`, mode 600, never committed. The repo holds only
examples. This is what makes it publishable without a credential audit every
time, and it means a `git pull` never clobbers local settings.

---

## Why systemd timers instead of cron

`Persistent=true` catches up a missed run after downtime, which matters on a
machine that is not always on. Failures land in the journal next to the
service. `systemctl list-timers` shows exactly when each next fires. And the
unit files version-control cleanly, which crontabs do not.

---

## Why no port forwarding

A forwarded port is scanned within hours — not targeted, just swept. The
server would then be defended by its own configuration alone, and anything
it exposes becomes a route onto the home network where the phones and
laptops live.

A mesh VPN gives the same reachability with nothing listening publicly.
The cost is installing a client on each device, which is not a real cost.

If something genuinely must be public, it belongs on a VPS or behind a
tunnel, not on the home connection.

---

## Known weaknesses

**Everything is on one machine.** Monitoring, services and the thing being
monitored share a host and a power supply. The heartbeat partly covers this;
nothing else does.

**The battery is a decade old and the charge limit is unavailable** without
UEFI access. Mitigated by habit, not by design.

**One Wi-Fi link, no wired fallback.** If the chip's driver regresses in a
kernel update the machine disappears, and recovery means attaching a display.

**Published Docker ports bypass UFW.** Docker writes its iptables rules ahead
of UFW's, so `-p 8080:80` is reachable LAN-wide regardless of firewall rules.
Bind to `127.0.0.1` unless LAN access is actually wanted. This surprises
people regularly and is worth stating twice.
