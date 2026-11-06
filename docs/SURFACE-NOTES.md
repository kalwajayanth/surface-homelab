# Surface-specific problems

Everything here cost real time. Written down so the next person does not
repeat it.

---

## Firmware screens do not appear on an external display

On a Surface, the UEFI menu, the GRUB menu, boot errors and BitLocker
recovery prompts render **only on the built-in panel** while it is connected.
The Surface firmware's basic graphics driver lights up the internal display
and does not drive the external port. Output to Mini DisplayPort begins only
once Windows or Linux loads a real graphics driver. (Many other laptops behave
the same way, but not all — desktops and some laptops do show their firmware
on an external screen. This note is about the Surface.)

So with a broken screen you cannot see the UEFI, and no cable, adapter,
screen-mirroring app or remote-desktop tool changes that. They are all
Windows programs; none of them are running yet.

**What actually works:**

1. **A flashlight at an angle on the cracked panel.** If only the backlight
   is dead the image may still be faintly readable.
2. **Detaching the panel.** With no internal display detected, the firmware
   falls back to the external port and the UEFI appears. This is what
   finally worked. It is glued in, so it is a careful job.
3. **Avoiding the UEFI entirely** — see the Hyper-V note at the bottom.

---

## Secure Boot blocks Linux installers

Ubuntu's bootloader is signed with Microsoft's third-party key, so in
principle it can boot with Secure Boot on. In practice Surface firmware may
not trust that key — newer Surfaces have a "Microsoft only" vs "Microsoft and
3rd party CA" choice, and the Pro 3 offers only Enable / Disable. On this
machine, turning Secure Boot **off** is what finally let the installer boot,
and it is the reliable route. The setting lives in the UEFI, which is the
screen you cannot see. Nothing done from another machine can change it:
network boot hits the same check, and moving the SSD elsewhere does not
help because the check happens at boot on the Surface.

With the panel detached and the UEFI visible, set Secure Boot to
**Disabled**.

**Do not touch "Delete all secure boot keys."** Deleting the keys does not
stop Windows booting — with no keys the firmware drops into "setup mode",
which checks nothing, so everything boots. The cost is that Secure Boot is
then silently off, and it cannot be turned back on until the factory keys
are restored, which needs an option your firmware may not have. BitLocker
will also ask for its recovery key again. Disabling is a clean, reversible
switch; deleting is not.

---

## Changing Secure Boot triggers BitLocker

BitLocker's key is sealed by the TPM against measured boot state, and
whether Secure Boot is on or off is one of the measured values (PCR 7).
Change it and the TPM refuses to release the key, so Windows demands the
48-digit recovery key at startup. The red screen before it is just the
firmware warning that Secure Boot is now off — harmless.

Entering the key boots Windows normally and re-seals against the new state,
so it asks once, not every time.

**Decrypt before installing Linux:**

```powershell
manage-bde -off C:
manage-bde -status     # wait for "Fully Decrypted"
```

Otherwise any future firmware change starts the cycle again, and a partly
encrypted disk is messier for the installer.

The recovery key is usually at **account.microsoft.com/devices/recoverykey**
if the device was signed into a Microsoft account. Match the Key ID shown
on screen.

---

## Thermals will shut the machine down

The Pro 3 (i5 and i7 models) cools with a small fan that blows out through
vents around the edge of the case, and the magnesium shell spreads the rest
of the heat. Wrapped in bubble wrap to protect the exposed internals, this
machine had both blocked: it idled at **79°C** and cut power repeatedly,
mid-install more than once. Unwrapped on a hard surface it idles at
**32–38°C**.

A sudden power-off with no warning is almost always thermal or power, not
software. If it happens during long CPU work like disk decryption or an OS
install, suspect cooling first.

Protect the internals with a tray *underneath*, never a wrap *around*.

---

## Installer problems on old hardware

Several failures looked like separate bugs but traced back to two causes.

**SquashFS I/O errors** — `failed to read block ... -5` means the installer
cannot read the USB stick. Bad write, failing stick, or a flaky hub. Reflash,
try another stick, and plug it directly into the machine rather than a hub.
This also explains installers that restart back to the language screen:
subiquity crashes on the unreadable section and relaunches, silently skipping
the Profile step so **no user account is created**. The install "completes"
and leaves a login prompt nothing can get past.

Check for this from a live USB before reinstalling. Find the internal disk
first: when you boot from a USB stick, the stick can take the name `sda` and
push the SSD to `sdb`.

```bash
lsblk               # the SSD is the ~119G disk; partition 1 is the 1G EFI, partition 2 is root
sudo mount /dev/sdX2 /mnt    # X from lsblk -- usually sda2
ls /mnt/home        # empty means no user account
```

**Console flickering between screens** — the installer, a login prompt and
kernel log messages competing for the same console. Quieten the kernel:

```bash
sudo dmesg -n 1
```

Or boot with `nomodeset console=tty1 loglevel=3` added to the GRUB kernel
line.

**Boot hanging with no login prompt** — `systemd-networkd-wait-online` with
no network to wait for (up to about two minutes). Looks like a dead machine.
Mask it — and spell the name exactly, because `systemctl mask` accepts any
name without complaint. I masked two misspelled names and the real service
stayed on. See SETUP Phase 2 for the exact commands and how to verify.

---

## Autoinstall, if the interactive installer will not cooperate

A `user-data` file answers every question, so there is nothing to see or
click. `install/` contains an example. It did not work for me — the installer
ignored it — but I now know why, and the fix is below.

The installer does **not** search an `autoinstall/` folder on the stick by
itself. You have to point it there on the GRUB kernel line, and escape the
semicolon, because GRUB treats a bare `;` as the end of the command:

```
autoinstall ds=nocloud\;s=/cdrom/autoinstall/
```

On 24.04 and later it is simpler: name the file `autoinstall.yaml` and put it
at the root of the stick (still add `autoinstall` to the kernel line, or it
waits at an invisible confirmation prompt). Also check Windows has not
appended `.txt` — turn on **View → File name extensions**. Step by step in
[install/README.md](../install/README.md).

---

## If the UEFI is genuinely unreachable

Keep Windows and run Linux as a Hyper-V VM inside it. Windows boots and
displays fine, and Hyper-V lets you pick the Secure Boot template the
firmware will not. An external virtual switch gives the VM its own address
on the network, so from elsewhere it behaves like a separate machine.

Worth knowing before committing: Windows 10 Pro or better is required,
4 GB RAM is very tight, and **turn off BitLocker first** — a recovery
prompt appears before the display driver loads, so on a screenless machine
it looks identical to a dead box.
