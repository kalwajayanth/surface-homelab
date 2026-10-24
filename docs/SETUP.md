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
```

Without this, a boot with no network sits at a blank screen for minutes
with no login prompt. On a machine you cannot see, that is indistinguishable
from a failed boot.

**Disable Wi-Fi power saving:**

```bash
sudo apt install -y iw
sudo cp systemd/wifi-powersave-off.service /etc/systemd/system/
# edit the interface name and check `which iw` for the path
sudo systemctl enable --now wifi-powersave-off.service
iw dev wlp1s0 get power_save   # expect: off
```

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

**Then harden.** Install `config/99-hardening.conf` as
`/etc/ssh/sshd_config.d/01-hardening.conf` — the `01` prefix matters.
sshd takes the *first* occurrence of a setting, and Ubuntu ships
`50-cloud-init.conf` with `PasswordAuthentication yes`.

```bash
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
sudo ufw allow 9090/tcp         # dashboard, if you use one
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
sudo apt install -y crowdsec-firewall-bouncer-nftables
```

nftables rather than iptables on Ubuntu 24.04. Detection and enforcement are
separate: without a bouncer, CrowdSec watches but never blocks.

```bash
sudo cscli bouncers list     # must not be empty
sudo cscli metrics           # check it is reading /var/log/auth.log
```

Whitelist yourself so a fat-fingered login cannot lock you out:

```bash
sudo cscli decisions add --range 192.168.0.0/24 --type bypass --duration 8760h
sudo cscli decisions add --range 100.64.0.0/10 --type bypass --duration 8760h
```

The second is the mesh VPN range. Note the one-year expiry.

---

## Phase 6 — Mail

```bash
sudo apt install -y msmtp msmtp-mta bsd-mailx
sudo cp config/msmtprc.example /etc/msmtprc
sudo nano /etc/msmtprc
sudo chmod 600 /etc/msmtprc
echo "test" | sudo msmtp you@example.com
```

Needs a Gmail **app password**, which needs 2-Step Verification, on a
**personal** account. Workspace accounts usually block SMTP, and server
scripts should not hold a work credential.

If nothing arrives: `sudo tail -20 /var/log/msmtp.log`.

---

## Phase 7 — Monitoring

```bash
sudo ./install/install.sh
sudo nano /etc/homelab/homelab.env
sudo apt install -y lynis
sudo /opt/homelab/scripts/health-report.sh    # test before scheduling
sudo ./install/enable-timers.sh
```

**Heartbeat.** Create a check at healthchecks.io with a 5-minute period and
10-minute grace, then put the ping URL in `homelab.env` and re-run
`enable-timers.sh`.

**Shutdown notice** (optional, needs mail working):

```bash
sudo cp systemd/shutdown-notify.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable shutdown-notify.service
```

---

## Phase 8 — Verify

```bash
sudo reboot
```

Wait two minutes, then SSH in from your laptop with **nothing plugged into
the server**. That is the real test. If it comes back by itself, you are done.

```bash
systemctl list-timers --all | grep homelab
```
