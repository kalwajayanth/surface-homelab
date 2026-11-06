# Setup

Order matters. Each phase assumes the previous one worked.

---

## Phase 1 — Base install

Ubuntu Server LTS, not the newest release. On hardware this old, a newer
kernel is often worse, and a fresh LTS installer carries bugs that the
point releases have fixed.

At the installer:

- **Type of install:** full, not minimized
- **Storage:** entire disk, **untick LVM**. One small disk gains nothing
  from LVM, and plain partitions are far easier to recover from a live USB.
- **Profile:** write down the username and password. Without a user account
  the install completes and leaves you at a login prompt you cannot pass.
- **SSH:** tick **Install OpenSSH server**. This is the step that makes the
  machine reachable at all.
- **Snaps:** none

If the network step fails, install without one and configure it afterwards.
Phone USB tethering works as a stopgap.

---

## Phase 2 — Network

Find the interface name. Note the lowercase L in `wlp1s0`; it is not a one,
and that typo produces a confusing systemd error about a service that does
not exist.

```bash
ip -brief link
```

Copy `config/50-wifi.yaml.example` to `/etc/netplan/50-wifi.yaml`, fill in
the SSID and password, then:

```bash
sudo chmod 600 /etc/netplan/50-wifi.yaml
sudo netplan apply
ip -brief a
```

Then reserve the address in your router by MAC, or it will change and you
will spend an evening hunting for it.

**Stop the boot hanging when the network is not ready:**

```bash
sudo systemctl mask systemd-networkd-wait-online.service
# If you install Cockpit later it brings NetworkManager, which adds a second one:
sudo systemctl mask NetworkManager-wait-online.service

systemctl is-enabled systemd-networkd-wait-online.service   # expect: masked
```

Without this, a boot with no network sits at a blank screen for up to two
minutes with no login prompt. On a machine you cannot see, that is
indistinguishable from a failed boot. Masking only removes that pause — the
Wi-Fi still connects in the background as soon as a network is available.

**Copy the unit names exactly and run the check.** `systemctl mask` accepts
any name, real or not, without an error. On my server two misspelled
attempts (`systemd-network-wait-online`, `...wait-online.services`) "worked"
and the real service stayed on.

**Disable Wi-Fi power saving:**

```bash
sudo apt install -y iw
sudo cp systemd/wifi-powersave-off.service /etc/systemd/system/
sudo systemctl enable --now wifi-powersave-off.service
iw dev wlp1s0 get power_save   # expect: off
```

The unit uses `wlp1s0` unless `WIFI_IFACE` is set in
`/etc/homelab/homelab.env` (created in Phase 7). If your interface has a
different name, set it there rather than editing the unit — `install.sh`
re-copies the unit and would overwrite your edit.

---

## Phase 3 — Remote access

**SSH keys**, from your laptop:

```powershell
ssh-keygen -t ed25519
type $env:USERPROFILE\.ssh\id_ed25519.pub | ssh user@SERVER_IP "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Confirm key login works **before** disabling passwords. A passphrase prompt
is your key unlocking; a password prompt is the server. They look similar
and mean opposite things.

**Then harden.** Install `config/01-hardening.conf` into
`/etc/ssh/sshd_config.d/`, keeping the name — the `01` prefix matters.
sshd takes the *first* occurrence of a setting, and Ubuntu ships
`50-cloud-init.conf` with `PasswordAuthentication yes`, so a file named
`99-…` would be ignored.

```bash
sudo cp config/01-hardening.conf /etc/ssh/sshd_config.d/
sudo sshd -t
sudo systemctl restart ssh
sudo sshd -T | grep -iE 'passwordauthentication|permitrootlogin'
```

Verify from a **new** terminal while the old one stays open:

```powershell
ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password user@SERVER_IP
```

`Permission denied (publickey)` is the correct answer.

**Mesh VPN.** Install Tailscale or similar for access from outside. It dials
outward, so nothing is exposed and no router changes are needed. Addresses
are stable per device.

---

## Phase 4 — Firewall and updates

```bash
sudo ufw allow OpenSSH          # BEFORE enabling, or you lock yourself out
# dashboard (Cockpit), if you use one -- only over the mesh VPN, not the LAN
sudo ufw allow in on tailscale0 to any port 9090 proto tcp comment 'Cockpit via Tailscale only'
sudo ufw enable

sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades
```

Unattended upgrades install patches but do not reboot for kernel updates.
That is what the reboot flag in the daily report is for.

---

## Phase 5 — CrowdSec

```bash
curl -s https://install.crowdsec.net | sudo sh
sudo apt install -y crowdsec
sudo apt install -y crowdsec-firewall-bouncer-iptables
```

Detection and enforcement are separate: without a bouncer, CrowdSec watches
but never blocks. Either bouncer package works on Ubuntu 24.04 — its
`iptables` command already writes nftables rules underneath
(`iptables --version` shows `nf_tables`). Whichever you pick, the service is
called **`crowdsec-firewall-bouncer`**; there is no unit named after the
package.

```bash
sudo systemctl status crowdsec-firewall-bouncer --no-pager
sudo cscli bouncers list     # must not be empty
sudo cscli metrics           # check it is reading /var/log/auth.log
```

Allowlist yourself so a fat-fingered login cannot lock you out:

```bash
sudo cscli allowlists create homelab -d "LAN and tailnet"
sudo cscli allowlists add homelab 192.168.0.0/24 100.64.0.0/10
sudo cscli allowlists list
```

The second range covers every mesh VPN (Tailscale) address. Allowlists need
CrowdSec 1.6.8 or later.

**Do not use `cscli decisions add --type bypass` for this.** CrowdSec accepts
any word as a decision type, but the firewall bouncer only acts on `ban`. A
"bypass" decision is stored and shown in `cscli decisions list`, yet it
protects nothing — a ban for the same address is still enforced.

---

## Phase 6 — Mail

```bash
echo "msmtp msmtp/apparmor boolean false" | sudo debconf-set-selections
sudo apt install -y msmtp msmtp-mta bsd-mailx
sudo cp config/msmtprc.example /etc/msmtprc
sudo chmod 600 /etc/msmtprc
sudo nano /etc/msmtprc
echo "test" | sudo msmtp you@example.com      # your real address, not this placeholder
```

Needs a Gmail **app password**, which needs 2-Step Verification, on a
**personal** account. Workspace accounts usually block SMTP, and server
scripts should not hold a work credential.

The first line pre-answers the install's "Enable AppArmor support?" question
with No (the default). If you answered Yes, turn it back off with
`sudo dpkg-reconfigure msmtp`, or purge and reinstall after the first line,
then unload the profile that is still in memory:
`sudo apparmor_parser -R /etc/apparmor.d/usr.bin.msmtp`. Check with
`sudo aa-status | grep msmtp`, which should print nothing.

If nothing arrives: `sudo tail -20 /var/log/msmtp.log`.

---

## Phase 7 — Monitoring

```bash
sudo ./install/install.sh
sudo nano /etc/homelab/homelab.env
sudo apt install -y lynis
sudo systemctl disable --now lynis.timer      # the package's own daily scan; homelab-lynis runs monthly and mails
sudo /opt/homelab/scripts/health-report.sh    # test before scheduling
sudo ./install/enable-timers.sh
```

**Heartbeat.** Create a check at healthchecks.io with a 5-minute period and
10-minute grace, then put the ping URL in `homelab.env` (keep the quotes) and
re-run `enable-timers.sh`. It runs as `powerMonitor.timer`. If you already had
a hand-made unit with that name, `install.sh` replaces it, so copy the ping
URL out of it first (`systemctl cat powerMonitor.service`).

**Monthly backup** (needs mail working). Everything that exists only on this
server — configs, firewall and CrowdSec state, SSH keys, package lists,
Uptime Kuma's data — is encrypted and emailed to you on the 1st of each
month. Create the passphrase, then **save it in your password manager**:

```bash
sudo sh -c 'umask 077; openssl rand -base64 32 > /etc/homelab/backup.pass'
sudo cat /etc/homelab/backup.pass      # copy this into your password manager
sudo /opt/homelab/scripts/backup.sh    # test: a "[backup]" mail with an attachment
sudo ./install/enable-timers.sh        # picks up the backup timer
```

Without the saved passphrase the backups are useless after a disk failure —
the only other copy is on the disk that failed. Restore steps are in the
RUNBOOK.

**Shutdown notice** (optional, needs mail working). `install.sh` has already
copied the unit; it just needs enabling. `--now` matters: the mail is sent
when the unit is *stopped*, so it has to be running first.

```bash
sudo systemctl enable --now shutdown-notify.service
```

---

## Phase 8 — Verify

```bash
sudo reboot
```

Wait two minutes, then SSH in from your laptop with **nothing plugged into
the server**. That is the real test. If it comes back by itself, you are done.

```bash
systemctl list-timers --all | grep -E 'homelab|powerMonitor'
```
