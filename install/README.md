# Install helpers

## install.sh / enable-timers.sh / uninstall.sh

See [../docs/SETUP.md](../docs/SETUP.md).

## Autoinstall

`autoinstall-user-data.example` and `autoinstall-meta-data.example` drive a
fully unattended Ubuntu Server install. Useful when the interactive installer
misbehaves — nothing to see, nothing to click, so a flickering console or a
skipped Profile screen cannot derail it.

1. Flash the ISO with Rufus (GPT, UEFI target, persistence 0)
2. Create a folder `autoinstall` at the **root** of the stick
3. Copy both files in, renamed to **`user-data`** and **`meta-data`**,
   with **no extension**
4. Edit `user-data`: username, password hash, hostname, timezone

**If the installer ignores them**, it is almost always because Windows
appended `.txt`. Turn on **View → File name extensions** in Explorer and
check. To force it regardless, add this to the GRUB kernel line:

```
autoinstall ds=nocloud;s=/cdrom/autoinstall/
```

The example also masks `systemd-networkd-wait-online` during install, so a
boot with no network still reaches a login prompt rather than hanging.
