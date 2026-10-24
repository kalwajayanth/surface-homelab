# Surface-specific problems

Everything here cost real time. Written down so the next person does not
repeat it.

---

## Firmware screens do not appear on an external display

On a Surface, the UEFI menu, the GRUB menu, boot errors and BitLocker
recovery prompts render **only on the built-in panel**. The firmware's
basic graphics driver lights up the internal display and never initialises
the external port. Full output to HDMI or DisplayPort begins only once
Windows or Linux loads a real graphics driver.

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

Surfaces ship with Secure Boot trusting Microsoft's key only, so every
Linux installer is refused. The setting lives in the UEFI, which is the
screen you cannot see. Nothing done from another machine can change it:
network boot hits the same check, and moving the SSD elsewhere does not
help because the refusal happens at boot on the Surface.

With the panel detached and the UEFI visible, set Secure Boot to
**Disabled**.

**Do not touch "Delete all secure boot keys."** That erases the trust
database. Restoring it needs a "restore factory keys" option that may not
exist on your firmware, and without it Windows may refuse to boot.
Disabling is reversible; deleting may not be.

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

The chassis is the heat sink. Wrapped in bubble wrap to protect the exposed
internals, this machine idled at **79°C** and cut power repeatedly, mid-install
more than once. Unwrapped on a hard surface it idles at **32–38°C**.

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

Check for this from a live USB before reinstalling:

```bash
sudo mount /dev/sda2 /mnt
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
no network to wait for. Looks like a dead machine. Mask it.

---

## Autoinstall, if the interactive installer will not cooperate

A `user-data` file in an `autoinstall/` folder at the root of the USB stick
answers every question, so there is nothing to see or click. `install/`
contains an example.

The usual reason it is ignored: Windows silently appends `.txt`. Turn on
**View → File name extensions** and check. Forcing it explicitly also works
— add this to the GRUB kernel line:

```
autoinstall ds=nocloud;s=/cdrom/autoinstall/
```

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
