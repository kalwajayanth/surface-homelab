# Surface Homelab

Turning a Surface Pro 3 with a broken screen into a headless Ubuntu Server,
and the monitoring that tells you when something is wrong with it.

Everything here is driven by one constraint: **you cannot see the machine.**
No screen, no console, no way to read an error. So the setup has to survive
reboots unattended, and the server has to report its own state by email.

---

## What this repo contains

| Path | What it is |
|---|---|
| `scripts/` | Health report, temperature watch, power watch, Lynis audit, heartbeat, backup |
| `systemd/` | Timers and units for all of the above |
| `config/` | Example configs — Wi-Fi, SSH hardening, mail, settings |
| `install/` | Install, enable and uninstall scripts |
| `docs/` | Setup walkthrough, build log, Surface-specific notes, runbook |

## Quick start

```bash
git clone https://github.com/YOURNAME/surface-homelab.git
cd surface-homelab
sudo ./install/install.sh
sudo nano /etc/homelab/homelab.env
# configure /etc/msmtprc, then test mail
sudo /opt/homelab/scripts/health-report.sh
sudo ./install/enable-timers.sh
```

Full walkthrough in [docs/SETUP.md](docs/SETUP.md).

---

## What gets monitored

| Check | Schedule | Behaviour |
|---|---|---|
| Health digest | 08:00 daily | Always sends. Urgency in the subject line. |
| Temperature | every 15 min | Silent unless over threshold, with a cooldown |
| Lynis audit | 1st monthly | Hardening index plus findings |
| Power / battery | every 2 min | Silent on mains. Emails on AC loss or return, warns when low, shuts down cleanly when critical |
| Heartbeat | every 5 min | External service alerts if pings stop. Carries battery state in the ping body |
| Clean shutdown | on shutdown | Immediate mail saying reboot or power-off, and who asked (`sudo reboot`, power button, critical battery) |
| Back up | on every boot | `[back up]` after a clean shutdown, `[BACK UP] … UNCLEAN` otherwise, with how long it was down. Retries for 30 min while the network comes up |
| Backup | 1st monthly, 10:00 | Encrypted archive of the server-only config and Uptime Kuma data, emailed as an attachment. Daily report flags it if over 35 days old |

The heartbeat matters more than it looks. Every other check runs **on** the
server, so if the server dies you get silence, not an alert. A dead-man's
switch is the only thing that survives its own host.
---

## Hardware notes

A tablet from 2014 makes a usable server, with caveats worth knowing
before you start.

**Thermals are the whole game.** A small fan blows out through vents around
the edge, and the magnesium shell spreads the rest of the heat. Wrapped in
bubble wrap, which blocked both, this machine idled at 79°C and shut itself
down repeatedly. Unwrapped on a hard surface it idles at 32–38°C. Nothing
else matters if it keeps cutting out.

**The battery is over a decade old.** Surface UEFI has a **Battery Limit**
setting (under **Kiosk Mode**, on firmware from late 2018 onwards) that caps
charging at 50%. It is enabled on mine. If you cannot reach the UEFI, a
smart plug on a schedule is the fallback. Check for swelling every two
weeks regardless — a swollen cell in an always-plugged-in device is a fire
risk, not an inconvenience.

**Wi-Fi power saving must be disabled.** The Marvell AVASTAR chip drops its
connection when idle. On a headless box that looks exactly like a dead server.

See [docs/SURFACE-NOTES.md](docs/SURFACE-NOTES.md) for the firmware,
Secure Boot and BitLocker problems and how I solved them, and
[docs/BUILDLOG.md](docs/BUILDLOG.md) for the full account of the build
including every dead end.

---

## Security posture

This box is a development machine reachable over LAN and a mesh VPN. It is
not production, and the configuration reflects that.

- SSH keys only, passwords disabled
- UFW allowing only SSH, plus the Cockpit dashboard on the mesh VPN
  interface only — it is not reachable from the rest of the LAN
- CrowdSec reading auth logs, with a firewall bouncer enforcing
- Unattended security upgrades
- **Nothing port-forwarded.** Remote access is the mesh VPN's job.

One sharp edge worth repeating: **published Docker ports bypass UFW.**
`-p 8080:80` is reachable from every device on your network regardless of
what UFW says, because Docker writes its rules first. Bind to `127.0.0.1`
for anything that does not need LAN access.

---

## How it went

The short version: three problems cost me almost all the time, and none of
them were Linux problems.

**Surface firmware only draws on the internal panel.** On the Surface, the
UEFI, the GRUB menu and early boot errors never reach an external display
while the internal panel is connected, because the firmware does not drive
the external port — that only starts once Windows or Linux loads a real
graphics driver. No cable, adapter or screen-mirroring app can change that —
they are all Windows programs that do not exist yet at that point. (My other
laptop behaved the same on the same TV; many laptops do, though not all.)
The fix was physically detaching the broken panel, after which the firmware
fell back to the external port.

**Bubble wrap caused repeated thermal shutdowns.** I had wrapped the device to
protect the exposed internals. That blocked the fan's vents and insulated the
metal shell — both halves of the cooling. 79°C idle wrapped, 32–38°C
unwrapped.

**A bad USB stick silently produced an install with no user account.** SquashFS
read errors crashed the installer, which relaunched from the start and skipped
the account-creation screen. The install "completed", rebooted, and presented a
login prompt that nothing could pass — with no error message anywhere.
`ls /home` on the mounted disk is the quick test (find the right disk with
`lsblk` first).

The full write-up, in order, is in [docs/BUILDLOG.md](docs/BUILDLOG.md).

---

## Licence

MIT. See [LICENSE](LICENSE).
