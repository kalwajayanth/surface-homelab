# Runbook

---

## Routine

| When | Task |
|---|---|
| Every 2 weeks | **Check the battery for swelling.** Check the temperature trend in the daily reports. |
| Weekly | Skim the daily report for failed units, disk growth, CrowdSec activity |
| Monthly | `sudo apt update && sudo apt full-upgrade -y`, reboot if flagged |
| Monthly | Read the Lynis mail |
| Quarterly | Back up anything that matters |

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
systemctl list-timers --all | grep homelab
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
systemctl list-timers --all | grep homelab
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

The mesh VPN still works if the service is running. Failing that, a display
and keyboard, then:

```bash
sudo rm /etc/ssh/sshd_config.d/01-hardening.conf
sudo systemctl restart ssh
```

### CrowdSec banned you

```bash
sudo cscli decisions delete --ip YOUR_IP
sudo cscli decisions add --range 192.168.0.0/24 --type bypass --duration 8760h
```

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
sudo docker system prune -a      # careful: removes unused images
```

---

## Recovery

**Forgotten password or username:** boot, hold Shift for GRUB, Advanced
options, a recovery-mode entry, drop to a root shell.

```bash
mount -o remount,rw /
ls /home          # usernames
passwd USERNAME
```

**Totally unbootable:** boot the installer USB, press Ctrl+Alt+F2 for a
shell, then mount and inspect:

```bash
sudo mount /dev/sda2 /mnt
ls /mnt/home
sudo chroot /mnt systemctl is-enabled ssh
```

Useful for resetting a password, re-enabling SSH, or checking whether the
install ever completed, without reinstalling.
