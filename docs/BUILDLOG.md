# Build log: turning a screenless Surface Pro 3 into a server

My chronological account of this build, including everything that failed. The
failures took most of the time and taught most of the lessons, so I have
written them up in as much detail as the things that worked.

**Where I started:** a Surface Pro 3 with a smashed display, a USB hub with a
mouse and keyboard, and a TV connected over Mini DisplayPort. Windows 10 Pro
22H2, 4 GB RAM, 128 GB SSD. No prior Linux server experience.

**Where I ended up:** headless Ubuntu Server 24.04, reachable over Wi-Fi and a
mesh VPN, hardened, monitored, and reporting its own health to my inbox.

**Elapsed:** several days, most of it spent on three problems that had nothing
to do with Linux.

---

## Stage 0 — The plan, and the assumption that cost me days

My plan was simple: install Ubuntu Server, manage it over SSH, never look at
the screen again. I chose Ubuntu Server LTS over Debian, CasaOS, Proxmox and
TrueNAS, mostly because Proxmox and TrueNAS have no usable Wi-Fi support and
this machine had no wired option.

**The assumption I carried in:** that the broken screen was a cosmetic problem.

It seemed reasonable, because it is true *after* the OS is installed — servers
are headless anyway. But getting to that point meant passing through the UEFI,
the boot menu and the installer, all of which need a working display. The thing
I had dismissed as irrelevant turned out to be the obstacle that cost me the
most time.

---

## Stage 1 — No Ethernet

My USB hub turned out to have no Ethernet port. That left a USB Ethernet
adapter, a USB Wi-Fi dongle, or the built-in Marvell AVASTAR chip.

I decided to use the built-in Wi-Fi, accept that it is flaky on Linux, and
disable power saving once the system was up. The Marvell chip's habit of
dropping its connection when idle is well documented, and on a headless box
that looks exactly like a dead server.

This turned out fine. The chip worked perfectly on a real system — all the
Wi-Fi trouble came later, and from a different cause entirely.

---

## Stage 2 — The UEFI will not appear on the TV

This is where the real work started.

**Attempt 1 — Windows Advanced startup → Use a device → USB.** The USB stick
was either not detected or not offered, and I never reached the installer.

**Attempt 2 — hold Volume Down, press Power.** The screen stayed black. After
three minutes I could not tell whether the machine was running or off.

**Attempt 3 — edit GRUB on the stick.** I added `video=eDP-1:d` to the kernel
line to tell Linux to ignore the internal panel entirely, and also tried
`nomodeset console=tty1 loglevel=3`. No change, because the problem was
happening earlier than Linux.

**Attempt 4 — blind navigation.** I asked for a sequence of arrow keys and
Enters to change the UEFI setting without seeing it. I was talked out of it, and
on reflection that was right: the Security page has a UEFI password field
directly above the Secure Boot setting. A sequence off by one keypress sets a
password I would not know and could not see, permanently locking the firmware.
Nearby options can also disable the USB port, killing my only keyboard, or the
Wi-Fi, killing my only network.

**The diagnosis, which I confirmed myself.** I connected an ordinary laptop to
the same TV over HDMI and entered its BIOS. Same behaviour — nothing on the TV.

So it is not a Surface fault, not a cable fault, and not an adapter fault. The
firmware's basic graphics driver initialises the **internal panel only**.
External outputs start working the moment Windows or Linux loads a real
graphics driver, and not one instant before. Firmware screens, the GRUB menu,
early boot errors and BitLocker prompts are all on the wrong side of that line.

**This is the single most useful thing I learned in the whole project**, and it
is poorly documented anywhere.

---

## Stage 3 — Secure Boot, suspected

My working theory at this point: Surfaces ship with Secure Boot trusting
Microsoft's key only, which refuses every Linux bootloader. The setting lives in
the UEFI — the screen I could not see.

I checked whether anything could change it from outside:

- **Network boot (PXE)** — hits the same check, and needs UEFI settings anyway
- **Remove the SSD, install Linux elsewhere, put it back** — the SSD sits behind
  the glued-on screen, and the refusal happens at boot on the Surface regardless
- **Recovery-mode Command Prompt** — Windows tools cannot change firmware
  settings. Also dangerous to use blind, since `diskpart` can wipe the disk in
  two keystrokes.
- **Four solutions from an old forum thread** (external monitor, serial console,
  goodbye-windows.com, Wubi) — all written for 2010-era netbooks. There is no
  serial port on a Surface; goodbye-windows.com has been dead for a decade; Wubi
  was discontinued in 2013 and its surviving fork needs the firmware to accept a
  Linux bootloader, which is the exact thing in question.

Every route assumed the firmware would boot something other than Windows. That
was the unknown, and nothing on the Windows side could resolve it.

---

## Stage 4 — Fallback plan: Hyper-V

With the UEFI apparently unreachable, my fallback was to keep Windows as the
host and run Ubuntu as a Hyper-V virtual machine inside it. Windows boots and
displays fine, and **Hyper-V lets you choose the Secure Boot template that the
physical firmware will not**. An external virtual switch gives the VM its own
address on the LAN, so from anywhere else it behaves like a separate machine.

I had a full guide written for this route, tuned for 4 GB: a 1.5 GB VM with
dynamic memory, a 60 GB virtual disk, and a Windows slimming pass (startup apps,
background apps, search indexing, visual effects) to leave room.

**I never needed it.** I am documenting it anyway, because it is a reasonable
answer for anyone whose panel cannot be detached.

---

## Stage 5 — A factory reset

A factory reset was triggered. The screen stayed black for over thirty minutes.

The reset progress screen also runs before the full graphics driver loads, so it
was invisible — another instance of the same root cause as Stage 2. I left it
alone and let it run. The reset completed on its own and the device came back up
into a fresh Windows.

Silver lining: a clean Windows was a better starting point than a decade of
accumulated software.

---

## Stage 6 — The breakthrough: detach the panel

I physically detached the broken display panel.

With no internal panel detected, the firmware fell back to the external port.
**The UEFI appeared on my monitor.** Days of workarounds became unnecessary in
one step.

The UEFI showed: TPM, Secure Boot Control, Configure Alternate System Boot
Order, Advanced Device Security, Kiosk Mode, Device Information, Administrator
Password, Exit Setup.

**Secure Boot Control offered only Enable and Disable**, plus a separate
"Delete all secure boot keys" option — not the three-way Microsoft-only /
Microsoft-and-3rd-party / None choice found on newer Surfaces.

I set it to **Disabled**.

**I deliberately did not touch "Delete all secure boot keys."** That erases the
firmware's trust database. Restoring it requires a "restore factory keys" option
that may not exist on this firmware, and without it Windows may refuse to boot
at all. Disabling is reversible; deleting may not be.

I also left the Administrator Password field alone, for the same reason that
made blind navigation too risky.

---

## Stage 7 — BitLocker demands a recovery key

On the next boot: a red screen, then a BitLocker recovery prompt.

**Why this happened.** BitLocker's key is held by the TPM and sealed against
*measured boot state*. During startup each stage hashes the next and reports the
hash to the TPM, which accumulates them into registers called PCRs. The key is
released only if today's values match the ones recorded when the key was sealed.

**Whether Secure Boot is on or off is one of those measured values (PCR 7).**
Disabling it changed the measurement, the TPM refused to release the key, and
BitLocker fell back to its other unlock method — the 48-digit recovery key.

This is the system working as designed. If an attacker disabled Secure Boot to
insert a malicious bootloader, this is precisely the alarm you would want.

The red screen was separate and harmless: the firmware noting that Secure Boot
is off and it will now run unsigned code.

**How I resolved it.** I entered the recovery key. Windows booted normally and
re-sealed the key against the new configuration, so it asked once rather than
every time. Then I ran `manage-bde -off C:` to decrypt the drive entirely —
because re-sealing is tied to the current state, so any *future* firmware change
would start the cycle again, and a partly encrypted disk is messier for an
installer to handle.

Decryption began. It reached 15.1%.

---

## Stage 8 — The machine starts shutting itself off

Mid-decryption, the Surface powered off with no warning. Then again. Pressing
Power produced a red flash and another shutdown.

I considered: a loose connector disturbed during the panel removal, a
ten-year-old battery collapsing under load, an underpowered charger, a swollen
cell pressing on the board, thermal cutoff.

I inspected the battery visually. **No bulge**, which ruled out the most
dangerous possibility.

Then the actual cause emerged. With the panel removed, I had been protecting the
exposed internals by **wrapping the device in bubble wrap**.

**The Surface Pro 3 cools itself through its magnesium chassis.** The body *is*
the heat sink; the small fan is secondary. Bubble wrap is an insulator wrapped
directly around the cooling surface. Under sustained load — and BitLocker
decryption hammers the CPU and SSD for an hour — the CPU hit its thermal limit
and the firmware cut power to protect the hardware.

It is also plastic held against a hot metal surface next to an aged lithium
battery, which is a fire risk rather than merely a performance one.

**The fix:** remove the wrap, stand the device on its kickstand on a hard
surface with the back fully exposed. Protect the internals with a tray
*underneath*, never a wrap *around*.

**What I measured later:** 79°C idle wrapped, **32–38°C idle unwrapped.**

The shutdowns stopped completely. In hindsight, every unexplained failure during
long CPU work traced back to this.

---

## Stage 9 — Ubuntu 26.04 fights back

With Secure Boot off and the UEFI visible, the installer finally booted. Then
three separate problems appeared, which looked unrelated but were not.

**Problem 1 — the console flickers between three things.** The installer, a
`login:` prompt, and a stream of kernel log messages all competing for the same
console, repainting over each other several times a second. Unreadable.

Partial mitigations I tried: `Ctrl+Alt+F2` then `Ctrl+Alt+F1` to force a
repaint; `sudo dmesg -n 1` to silence kernel output; booting with
`nomodeset console=tty1 loglevel=3`.

**Problem 2 — the installer restarts back to the language screen.** Subiquity
crashes and relaunches from the beginning rather than dying visibly.

**Problem 3 — SquashFS I/O errors.** `failed to read block 0x40d96d5: -5`. The
installer could not read parts of the USB stick.

**These were one problem, not three.** The unreadable media caused the crashes,
and the crash-restart loop silently skipped the **Profile** screen — the one
that creates the user account.

**The consequence is nasty and silent.** The install "completes", reboots, and
presents a login prompt that no username or password can pass, because no
account exists. There is no error message anywhere. It looks exactly like a
forgotten password.

**How I confirmed it.** I booted the installer USB, pressed `Ctrl+Alt+F2` for a
live shell, and mounted the installed system:

```bash
sudo mount /dev/sda2 /mnt
ls /mnt/home        # empty — no user account
```

An empty `/home` is the definitive test. Worth knowing before reinstalling
blind, because the symptom points somewhere else entirely.

**I also realised here** that the ISO I was using was Ubuntu **26.04**, released
only months earlier. Two reasons that was the wrong choice on this hardware: a
brand new LTS has the least-tested installer, and a much newer kernel is often
*worse* on 2014 hardware, since support for older Intel graphics and the Marvell
Wi-Fi chip gets rewritten or dropped.

---

## Stage 10 — Autoinstall, as an alternative

With the interactive installer unreliable, I tried an unattended install: a
`user-data` file in an `autoinstall/` folder at the root of the USB stick,
answering every question including user creation and enabling SSH. Nothing to
see, nothing to click, so a flickering console cannot derail it.

**The installer ignored it and went interactive anyway.**

The most likely cause, which I never fully confirmed: Windows silently appends
`.txt` to files saved from Notepad unless the filename is wrapped in quotes, and
**View → File name extensions** is off by default so it is invisible.

There is an override I did not end up needing, which forces the datasource on
the GRUB kernel line:

```
autoinstall ds=nocloud;s=/cdrom/autoinstall/
```

I am keeping the autoinstall files in this repo as an alternative route, in case
the interactive installer proves unusable on someone else's hardware.

---

## Stage 11 — Ubuntu 24.04.5 LTS, which works

I downloaded **Ubuntu Server 24.04.5 LTS, Intel/AMD (amd64)**, and wrote it to a
**different USB stick**.

Two years of installer fixes and a kernel better matched to the hardware. The
install went through cleanly, with the Profile and SSH screens appearing where
they should.

My installer choices:
- Full **Ubuntu Server**, not minimized
- Entire disk, **LVM unticked** — one small disk gains nothing from LVM, and a
  plain partition can be mounted from any live USB with a single command, which
  matters a great deal on a machine being recovered blind
- **OpenSSH server ticked**
- No snaps
- **Network skipped**, because Wi-Fi would not associate in the installer

---

## Stage 12 — Getting a network, the hard way

**Phone USB tethering.** The interface appeared as `usb0`, then
`enx12cfaf5275ee`, in state DOWN.

**`dhclient` does not exist on Ubuntu 24.04.** It was removed in favour of
netplan and `systemd-networkd`. Every older tutorial that reaches for `dhclient`
is now wrong.

I configured it via netplan instead:

```yaml
network:
  version: 2
  ethernets:
    enx12cfaf5275ee:
      dhcp4: true
      optional: true
```

Address obtained: `10.30.57.69`.

**SSH would not connect — timeout, not refusal.** Two separate causes, which I
found in sequence:

1. **The SSH service was `inactive`.** Installed but never started. Fixed with
   `systemctl enable --now ssh`.
2. **My laptop and the server were on different networks.** The laptop sat on
   `10.140.96.117` via the phone's *Wi-Fi hotspot*; the server on `10.30.57.69`
   via *USB tethering*. Android places hotspot clients and USB-tethered devices
   on separate subnets with no routing between them. Both were online. Neither
   could see the other.

A timeout means no path; a refusal means a path with nothing listening. That
distinction saved me a lot of guessing.

**My solution: Tailscale.** Installed on the server, which obtained
`100.124.178.42`. Tailscale connects devices regardless of the network each is
on, needs no inbound ports, and gives each device a permanent address. It
sidestepped the subnet problem entirely and became my permanent remote-access
method.

---

## Stage 13 — Wi-Fi, which was never actually broken

On a full system, the driver told a completely different story from the
installer:

```
mwifiex_pcie: info: FW download over, size 723540 bytes
mwifiex_pcie: WLAN FW is active
mwifiex_pcie wlp1s0: renamed from mlan0
```

Firmware loaded, chip active, interface present, no errors. **The hardware was
fine all along** — the installer environment had been the problem.

**`nmcli` does not exist on Ubuntu Server.** NetworkManager is not installed;
netplan is the interface. Another case where common tutorials do not apply.

I configured `/etc/netplan/50-wifi.yaml` with `wifis:`, `dhcp4: true`,
`optional: true` and the access point credentials, locked it to mode 600, and
applied it. The interface came up on **`192.168.0.6`**.

### Reserving the address on the router

A DHCP lease is temporary. If the router hands out a different address after a
reboot or a lease expiry, a headless server effectively disappears — I would
have to scan the network or attach a display just to find it again.

So I pinned it. On the TP-Link router:

**Advanced → Network → DHCP Server → Address Reservation → Add**

I bound the server's Wi-Fi MAC (`c0:33:5e:1c:a2:89`, shown as `link/ether` in
`ip -brief link`) to `192.168.0.6`, enabled the entry and saved. TP-Link's
interface wants the MAC with hyphens rather than colons. On older TP-Link
firmware the same setting lives under **DHCP → Address Reservation**.

After a reboot the server requested its address and got the same one back.

**Why this matters beyond convenience:** every later piece of the setup assumes
a fixed address — the SSH config shortcut, the firewall rules, the reports that
print a reconnection hint, and the web dashboards below. One drifting IP breaks
all of them at once.

### Reaching the web interfaces over that IP

With a stable address, browser-based management became possible from my laptop:

- **Cockpit** on `https://192.168.0.6:9090` — CPU, memory, disk, logs, services,
  updates and a browser terminal. It serves a self-signed certificate, so the
  browser warning is expected rather than a problem. Port 9090 is allowed
  through UFW.
- **Uptime Kuma** on port 3001 — but I deliberately bound this one to
  `127.0.0.1` instead of the LAN, and reach it through an SSH tunnel:

  ```bash
  ssh -L 3001:localhost:3001 user@192.168.0.6
  ```

  Then `http://localhost:3001` in the browser, for as long as that session is
  open.

The split is intentional. Cockpit authenticates against system accounts and is
useful from any device in the house, so LAN exposure is a fair trade. Uptime
Kuma has its own login and no reason to be reachable by every device on the
network, so it stays on loopback.

Both also work from outside the house over Tailscale, using `100.124.178.42` in
place of the LAN address, with no router changes and nothing exposed to the
internet.

---

## Stage 14 — Hardening

**SSH keys.** I generated an ed25519 pair on my laptop and appended the public
key to `~/.ssh/authorized_keys` on the server.

A subtlety worth naming: after copying the key, the prompt changed from
`user@host's password:` to `Enter passphrase for key`. **These look similar and
mean opposite things.** The first is the server asking; the second is my local
key unlocking. Confusing them leads to disabling passwords while key auth is not
actually working.

**Disabling passwords — and the file that silently overrode it.** I created
`/etc/ssh/sshd_config.d/99-hardening.conf` with `PasswordAuthentication no`.
Verification showed the setting had **not** taken effect:

```bash
sudo sshd -T | grep -i passwordauthentication   # still "yes"
```

**The cause.** sshd takes the **first** occurrence of a setting, not the last.
Ubuntu ships `50-cloud-init.conf` containing `PasswordAuthentication yes`, which
sorts *before* `99-`. My hardening file was being read too late to matter.

**The fix:** rename it to `01-hardening.conf` so it sorts first.

**I verified it properly**, by forcing password-only authentication from a
second terminal while the first stayed open:

```bash
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password user@host
# Permission denied (publickey)  ← correct
```

Checking the file is not the same as checking the running configuration.
`sshd -T` is the only honest test.

**I also applied:**
- UFW, allowing OpenSSH **before** enabling it, plus 9090 for Cockpit
- `unattended-upgrades` for automatic security patching
- Timezone set to `Asia/Kolkata`, so log timestamps stopped being misleading
- **Changed my Wi-Fi password on the router** — it had been written in plain
  text into a config file during setup

---

## Stage 15 — Headless reliability

A set of changes whose entire purpose is that the machine comes back on its own,
with nobody watching.

**Wi-Fi power saving off.** The Marvell chip drops its connection when idle with
power saving enabled. On a headless box that is indistinguishable from a dead
server. A small systemd oneshot service runs at boot:

```bash
iw dev wlp1s0 set power_save off
iw dev wlp1s0 get power_save   # Power save: off
```

**Lid switch ignored.** `HandleLidSwitch=ignore` and related settings in
`/etc/systemd/logind.conf` — the Type Cover registers as a lid, and a stray
close would suspend the server.

**Console blanking** via `consoleblank=60` in GRUB.

**Tailscale confirmed enabled at boot**, so remote access survives a restart.

**Then a deliberate reboot with nothing attached**, followed by SSH from my
laptop. That last step is the real test. Everything up to then had been applied
to a running system; the reboot proved it survives a restart unattended.

---

## Stage 16 — CrowdSec

I installed it natively rather than in Docker, since it needs to read host logs.

**Detection and enforcement are separate components.** The agent decides; a
*bouncer* acts. Without a bouncer, CrowdSec watches and logs but never blocks —
which looks like it is working.

The documented `crowdsec-firewall-bouncer-iptables` service was not found.
Ubuntu 24.04 uses nftables by default, so
`crowdsec-firewall-bouncer-nftables` is the correct package.

I verified with `cscli bouncers list` — an empty result means nothing is
enforcing.

**I whitelisted myself before anything else**, so a mistyped login cannot cause
a lockout:

```bash
sudo cscli decisions add --range 192.168.0.0/24 --type bypass --duration 8760h
sudo cscli decisions add --range 100.64.0.0/10 --type bypass --duration 8760h
```

The second covers the entire Tailscale range. Tailscale addresses look unrelated
(`100.103.x`, `100.112.x`, `100.91.x`) but all fall inside `100.64.0.0/10`, so
one entry replaces per-device entries and covers future devices automatically.

Note the one-year expiry on both.

---

## Stage 17 — Uptime Kuma, and two Docker lessons

Deployed in Docker, bound to `127.0.0.1:3001` and reached through an SSH tunnel
as described in Stage 13.

**Lesson 1 — pinned tags go end-of-life.** I pinned `:1`; the running
application told me that v1 was no longer maintained. I moved to `:2`. Data
lives in a host volume, so the database migrated automatically. Pinning a major
version is correct, but major versions do expire.

**Lesson 2 — published Docker ports bypass UFW.** Docker writes its own iptables
rules *ahead* of UFW's. A container started with `-p 8080:80` is reachable from
every device on the LAN no matter what UFW says. Binding to `127.0.0.1`
explicitly is the fix. This surprises people constantly and is worth repeating.

A related decision: **I deliberately skipped `usermod -aG docker`.** Membership
of the `docker` group is effectively root, since a container can mount the host
filesystem. Keeping Docker behind `sudo` is the safer posture.

---

## Stage 18 — Email alerting

A server nobody can see has to report on itself.

**Mail transport:** `msmtp` relaying to Gmail, which requires an **app
password**, which requires 2-Step Verification, on a **personal** account.
Workspace accounts generally block SMTP, and server scripts should not hold a
work credential. The password sits in `/etc/msmtprc`, mode 600 — a live
credential on disk, revocable from Google's account page.

**Four checks, two deliberately different patterns:**

| Check | Schedule | Behaviour |
|---|---|---|
| Health digest | 08:00 daily | **Always** sends |
| Temperature | every 15 min | **Silent** unless over 75°C, 3-hour cooldown |
| Lynis audit | 1st monthly | Hardening index and findings |
| Shutdown notice | on shutdown | Immediate, so a deliberate reboot is obvious |

**Why the digest always sends.** A report that only arrives when something is
wrong trains you to ignore its absence — and silence then cannot distinguish
"all fine" from "the job broke three weeks ago". Urgency goes in the subject
line (`[3 security]`, `[REBOOT]`, `[HOT 78C]`, `[ok]`), so I can triage from a
phone notification without opening anything.

**Why the temperature watcher is the opposite.** It runs every 15 minutes.
Mailing every run would destroy the signal in both channels. Silence is the
normal state, so any mail from it means something — with a cooldown so one hot
afternoon does not produce twelve messages.

**Systemd timers rather than cron**, for `Persistent=true` (catches up missed
runs after downtime), journal integration, and `systemctl list-timers` showing
exactly when each next fires.

---

## Stage 19 — The dead man's switch

Every check above runs **on** the server. If the server dies, they die with it,
and no alert is sent. Silence means nothing.

**Healthchecks.io**, free tier: the server pings an external URL every 5
minutes; if pings stop for longer than the grace period, that service sends the
alert. Outbound-only, so it works behind the firewall and Tailscale with nothing
exposed.

This is the only alert that survives its own host, and it is the most important
one in the whole setup.

I paired it with a **clean-shutdown notice**, so a deliberate reboot produces an
immediate "this was intentional" mail rather than fifteen minutes of worry.

---

## What I would tell someone starting this

**The problems that cost me the most time, in order:**

1. Firmware output going only to the internal panel — days, resolved by
   physically detaching the panel
2. Bubble wrap causing thermal shutdowns — hours of apparently random failures
3. A bad USB stick causing installer crashes that silently skipped user creation
4. Secure Boot blocking Linux, unreachable until the panel came off
5. BitLocker triggered by the Secure Boot change

**Things that were never actually broken:**

- The Marvell Wi-Fi chip — fine on a real system, only unusable in the installer
- The Surface's hardware generally — nothing failed. Everything was
  configuration, firmware behaviour, bad media, or cooling.

**Commands and facts I will carry forward:**

- `sshd -T` shows the *running* config; reading the file is not verification
- sshd takes the **first** occurrence of a setting, so filename ordering decides
  which file wins
- `dhclient` and `nmcli` are both absent on Ubuntu Server 24.04 — netplan is the
  interface
- `ls /home` on a mounted install tells you instantly whether setup ever
  completed
- A **timeout** means no network path; a **refusal** means a path with nothing
  listening
- CrowdSec without a bouncer detects but never blocks
- Docker's published ports bypass UFW entirely
- A reserved DHCP address is not optional on a headless box — everything
  downstream assumes it
- Thermal shutdowns look exactly like random hardware failure

---

## Final state

| | |
|---|---|
| **Hardware** | Surface Pro 3, screen detached, 4 GB RAM, 128 GB SSD |
| **OS** | Ubuntu Server 24.04.5 LTS |
| **Network** | Wi-Fi on a reserved address, plus a mesh VPN for remote access |
| **Access** | SSH keys only, passwords disabled, verified with `sshd -T` |
| **Firewall** | UFW, plus CrowdSec with an nftables bouncer |
| **Updates** | Unattended security upgrades, reboot flagged in the daily report |
| **Monitoring** | Daily digest, temperature watch, monthly audit, external heartbeat, shutdown notice |
| **Services** | Cockpit on the LAN, Uptime Kuma on loopback |
| **Thermals** | 32–38°C idle, down from 79°C |
