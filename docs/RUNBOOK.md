# Runbook

---

## Routine

| When | Task |
|---|---|
| Every 2 weeks | **Check the battery for swelling.** Check the temperature trend in the daily reports. |
| Weekly | Skim the daily report for failed units, disk growth, CrowdSec activity |
| Monthly | `sudo apt update && sudo apt full-upgrade -y`, reboot if flagged |
| Monthly | Read the Lynis mail |
| Monthly | Check the `[backup]` mail arrived (1st of the month) |
| Twice a year | Test-restore a backup (below) — an untested backup is a guess |

---

## Commands

```bash
# State
df -h                 # disk
free -h               # memory
uptime -p             # how long up
systemctl --failed    # anything broken

# Temperature
for z in /sys/class/thermal/thermal_zone*/temp; do
  awk '{print $1/1000"C"}' "$z"
done

# Network
ip -brief a
iw dev wlp1s0 get power_save      # expect: off

# Security
sudo cscli decisions list
sudo cscli alerts list
sudo ufw status

# Timers
systemctl list-timers --all | grep -E 'homelab|powerMonitor'
sudo journalctl -u homelab-report.service -n 30 --no-pager

# Mail
sudo tail -30 /var/log/msmtp.log

# Manual runs
sudo /opt/homelab/scripts/health-report.sh
sudo /opt/homelab/scripts/temp-watch.sh     # silent unless hot
```

---

## When something is wrong

### No daily report arrived

Mail, timer, or the whole box. Check the heartbeat service first — if that
also stopped, the machine is down and the problem is physical.

```bash
systemctl list-timers --all | grep -E 'homelab|powerMonitor'
sudo journalctl -u homelab-report.service -n 30 --no-pager
sudo tail -30 /var/log/msmtp.log
echo test | sudo msmtp you@example.com
```

A Gmail app password stops working if 2-Step Verification is turned off or
the password is revoked.

### Temperature alert

Physical, not software. Check it is on a hard surface, back exposed, nothing
wrapped around it, nothing on top. Look at what is burning CPU:

```bash
htop
```

If it idles hot with nothing running, airflow is blocked or the thermal paste
has aged out.

### Unreachable over SSH

1. Is it powered and is the charger LED lit?
2. Try the mesh VPN address — if that works, local networking is the problem
3. Check your router's device list for its current IP
4. If the IP changed, the DHCP reservation was lost
5. Still nothing: connect a display and keyboard

Common causes, in order: Wi-Fi power saving re-enabled, IP reservation lost,
an unexpected reboot leaving a service down.

### Locked out of SSH

Work out which kind of lockout it is:

- **Your IP was banned** (CrowdSec, below): connect over the mesh VPN
  address instead — it comes from a different IP.
- **Key login fails** (lost or changed key): the VPN does not help, since SSH
  still wants the key. Cockpit's terminal accepts your account password. It
  only listens on the mesh VPN, so use the Tailscale address:
  `https://TAILSCALE_IP:9090`.

Failing both, a display and keyboard, then:

```bash
sudo rm /etc/ssh/sshd_config.d/01-hardening.conf
sudo systemctl restart ssh
```

### CrowdSec banned you

```bash
sudo cscli decisions delete --ip YOUR_IP
sudo cscli allowlists list        # is your range actually in there?
sudo cscli allowlists add homelab 192.168.0.0/24
```

An allowlist stops new bans; it does not lift a ban that already exists,
which is why the `delete` comes first. A `--type bypass` decision does
nothing here — the bouncer ignores every type except `ban`.

### Power cut

You should get a `[POWER LOST]` mail within two minutes, with the battery
percentage and a rough runtime estimate. The machine then:

- warns once at the low threshold (default 20%)
- emails and shuts down cleanly at the critical threshold (default 10%)

**It will not come back on its own.** Someone has to press the power button
when mains returns.

If the outage looks like it will run long, shut it down early rather than
draining a decade-old battery:

```bash
sudo poweroff
```

Check the state by hand:

```bash
cat /sys/class/power_supply/BAT*/capacity    # percentage
cat /sys/class/power_supply/BAT*/status      # Charging / Discharging
cat /sys/class/power_supply/A*/online        # 1 = mains, 0 = battery
```

If the external check went down without a `[POWER LOST]` mail arriving first,
the machine lost power instantly rather than switching to battery -- which
points at the battery itself rather than the mains supply.

### Did not come back after a reboot

The mails tell you first: a `[shutdown] … (reboot)` with no `[back up]`
following within a few minutes means the restart did not complete.

Then find out whether it is actually off: `tailscale status` on another
device, or the healthchecks.io dashboard. With no screen, a running machine
looks exactly like a dead one.

- **A short press of the power button shuts a running machine down
  cleanly** (Ubuntu's default). Pressing it to "wake" a box that is already
  on turns it off. On 2026-11-06 this happened three times in a row.
- **Hold the button 10+ seconds** to force it off if it is stuck, then press
  once to start it.

Once it is back, read what happened with exact times rather than guessing:

```bash
journalctl --list-boots | tail -5
journalctl --since -1h | grep -E 'COMMAND=.*(reboot|poweroff)|Power key|Reached target (reboot|poweroff)'
```

A gap with **no boot logged at all** after a clean `Reached target reboot`
means the firmware stalled on the warm restart, before any kernel loaded. It
happened once here (26 minutes, until the power button was used) and the next
reboot worked normally. If it starts recurring, add `reboot=pci` to
`GRUB_CMDLINE_LINUX_DEFAULT` in `/etc/default/grub` (next to `consoleblank=60`),
run `sudo update-grub`, and test with a reboot while you can reach the button.

### Unexpected reboot

```bash
last reboot | head
journalctl --list-boots
journalctl -b -1 -e --no-pager    # end of the previous boot
```

A clean shutdown leaves a trail. An abrupt cut leaves nothing, which itself
points at power or thermal.

### Disk filling up

```bash
sudo du -sh /var/* | sort -h | tail
sudo journalctl --vacuum-time=14d
sudo docker system prune -a      # careful: deletes STOPPED containers and every unused image
```

---

## Recovery

**Forgotten password or username:** boot and tap **Esc** as soon as the
firmware logo goes (the Surface boots UEFI; holding Shift only works on
old BIOS machines). In GRUB: Advanced options, a recovery-mode entry, drop
to a root shell.

```bash
mount -o remount,rw /
ls /home          # usernames
passwd USERNAME
```

**Totally unbootable:** boot the installer USB, press Ctrl+Alt+F2 for a
shell, then mount and inspect:

```bash
lsblk                        # find the internal SSD: the 119.2G disk
sudo mount /dev/sda2 /mnt    # its partition 2 is root (sda1 is the 1G EFI)
ls /mnt/home
sudo chroot /mnt systemctl is-enabled ssh
```

On this machine the SSD is normally `sda` (`sda1` 1G EFI, `sda2` 118.2G
root). Booted from a USB stick, the stick can take `sda` instead, so go by
the size in `lsblk`, not the name.

Useful for resetting a password, re-enabling SSH, or checking whether the
install ever completed, without reinstalling.

**Restoring from a backup:** download the `.tar.gz.gpg` attachment from the
newest `[backup]` mail. On any machine with gpg (Linux, macOS, Git Bash on
Windows), using the passphrase from your password manager:

```bash
mkdir restore && cd restore
gpg -d homelab-HOST-DATE.tar.gz.gpg | tar -xzf -
ls          # etc/  opt/  home/  root/  extra/
```

Nothing is restored automatically; copy back what you need. On a fresh
install, after cloning the repo and running `install.sh`:

```bash
sudo cp -a etc/homelab/. /etc/homelab/
sudo cp etc/msmtprc /etc/msmtprc && sudo chmod 600 /etc/msmtprc
sudo cp etc/netplan/*.yaml /etc/netplan/ && sudo netplan apply
sudo cp etc/ssh/sshd_config.d/*.conf /etc/ssh/sshd_config.d/
sudo cp -a etc/ufw/. /etc/ufw/ && sudo ufw reload
# Uptime Kuma: stop the container, copy opt/uptime-kuma back, start it
```

`extra/` holds the package list (`packages-manual.txt`) and the CrowdSec
allowlists as JSON, to re-create by hand. `backup.pass` is deliberately not
inside the archive — put it back from your password manager.

**Test a restore** (twice a year) by decrypting the latest mail on your
laptop and listing it: `gpg -d FILE | tar -tzf - | head`.
