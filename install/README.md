# Install helpers

## install.sh / enable-timers.sh / uninstall.sh

See [../docs/SETUP.md](../docs/SETUP.md).

## Autoinstall

`autoinstall-user-data.example` and `autoinstall-meta-data.example` drive a
fully unattended Ubuntu Server install. Useful when the interactive installer
misbehaves — nothing to see, nothing to click, so a flickering console or a
skipped Profile screen cannot derail it.

> **Honest status:** this did not work for me — the installer ignored the
> files and went interactive. The steps below fix the two things I now know
> I got wrong, so it should work, but it is untested on this machine.

1. Flash the ISO with Rufus (GPT, UEFI target, ISO mode, persistence 0) so the
   stick stays writable
2. Create a folder `autoinstall` at the **root** of the stick
3. Copy both files in, renamed to **`user-data`** and **`meta-data`**,
   with **no extension** (`meta-data` stays empty, but it must exist)
4. Edit `user-data`: username, password hash, hostname, timezone
5. **Tell the installer where to look.** It does *not* search an
   `autoinstall/` folder on its own. At the GRUB menu press `e` and add this to
   the end of the `linux` line, before any `---`:

   ```
   autoinstall ds=nocloud\;s=/cdrom/autoinstall/
   ```

   The backslash matters. GRUB treats a bare `;` as the end of a command and
   silently drops everything after it, so `ds=nocloud;s=...` without the
   backslash never reaches the kernel. Putting the whole value in quotes
   (`"ds=nocloud;s=/cdrom/autoinstall/"`) also works. Press **Ctrl+X** to boot.

**Simpler on 24.04 and later:** skip steps 2 and 3 and instead save the same
file as **`autoinstall.yaml`** at the root of the stick. The installer finds it
without the `ds=` part. Still add the word `autoinstall` to the `linux` line in
step 5, though: without it the installer stops at a "Continue with
autoinstall?" confirmation before wiping the disk, which on a screenless
machine looks exactly like a hang.

**If it is still ignored**, check that Windows has not added `.txt` to the
file names. Turn on **View → File name extensions** in Explorer.

The example also masks `systemd-networkd-wait-online` during install, so a
boot with no network still reaches a login prompt rather than hanging.
