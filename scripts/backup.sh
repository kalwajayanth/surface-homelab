#!/bin/bash
# Monthly encrypted backup of everything that exists ONLY on this server
# (the scripts themselves live in git), emailed to ALERT_EMAIL so a copy
# survives the SSD dying.
#
#   - bundles configs, firewall/CrowdSec state, SSH keys, package lists
#     and Uptime Kuma's data
#   - encrypts with gpg (AES-256) using the passphrase in
#     /etc/homelab/backup.pass -- keep that passphrase in a password
#     manager too, or the backups cannot be opened after a disk failure
#   - decrypts the result once to prove it opens before sending it
#   - keeps the newest BACKUP_KEEP copies in /var/backups/homelab
#
# Restore anywhere with gpg (Linux, macOS, or Git Bash on Windows):
#   gpg -d homelab-HOST-DATE.tar.gz.gpg | tar -xzf -

set -uo pipefail

CONFIG="/etc/homelab/homelab.env"
[ -r "$CONFIG" ] && . "$CONFIG"

ALERT_EMAIL="${ALERT_EMAIL:-root}"
PASSFILE="${BACKUP_PASSPHRASE_FILE:-/etc/homelab/backup.pass}"
DEST="${BACKUP_DIR:-/var/backups/homelab}"
KEEP="${BACKUP_KEEP:-3}"
MAX_MAIL_MB="${BACKUP_MAX_MAIL_MB:-20}"     # Gmail rejects mail over 25 MB
KUMA_CONTAINER="${KUMA_CONTAINER:-uptime-kuma}"
HOST=$(hostname)
STAMP=$(date +%Y-%m-%d)
NAME="homelab-${HOST}-${STAMP}.tar.gz.gpg"

fail() {
    {
    echo "The monthly backup of $HOST failed: $1"
    echo
    echo "Run it by hand to see the details:"
    echo "  sudo /opt/homelab/scripts/backup.sh"
    } | mail -s "[BACKUP FAILED] $HOST" "$ALERT_EMAIL"
    exit 1
}

[ -s "$PASSFILE" ] || fail "no passphrase file at $PASSFILE"

WORK=$(mktemp -d)
KUMA_STOPPED=no
cleanup() {
    [ "$KUMA_STOPPED" = yes ] && docker start "$KUMA_CONTAINER" > /dev/null 2>&1
    rm -rf "$WORK"
}
trap cleanup EXIT

mkdir -p "$WORK/extra" "$DEST"
chmod 700 "$DEST"

# --- state that lives in commands rather than files -----------------------
apt-mark showmanual   > "$WORK/extra/packages-manual.txt"  2>/dev/null || true
dpkg --get-selections > "$WORK/extra/dpkg-selections.txt"  2>/dev/null || true
uname -a              > "$WORK/extra/uname.txt"            2>/dev/null || true
if command -v cscli > /dev/null; then
    # Allowlists live in CrowdSec's database, not in /etc/crowdsec.
    cscli allowlists list -o json > "$WORK/extra/crowdsec-allowlists.json" 2>/dev/null || true
    for n in $(grep -o '"name": *"[^"]*"' "$WORK/extra/crowdsec-allowlists.json" 2>/dev/null \
               | cut -d'"' -f4 | sort -u); do
        cscli allowlists inspect "$n" -o json \
          > "$WORK/extra/crowdsec-allowlist-$n.json" 2>/dev/null || true
    done
fi

# --- files that exist only on this machine ---------------------------------
PATHS=(
    /etc/homelab
    /etc/msmtprc
    /etc/netplan
    /etc/ssh/sshd_config.d
    /etc/systemd/logind.conf
    /etc/default/grub
    /etc/systemd/system
    /etc/ufw
    /etc/crowdsec
    /etc/apt/sources.list.d
    /etc/apt/keyrings
    /opt/uptime-kuma
)
for k in /root/.ssh/authorized_keys /home/*/.ssh/authorized_keys; do
    [ -f "$k" ] && PATHS+=("$k")
done
REL=()
for p in "${PATHS[@]}"; do
    [ -e "$p" ] && REL+=("${p#/}")
done

# Uptime Kuma writes to SQLite constantly; copying it mid-write can give a
# corrupt copy. Pause the container for the few seconds tar needs.
if command -v docker > /dev/null \
   && [ "$(docker inspect -f '{{.State.Running}}' "$KUMA_CONTAINER" 2>/dev/null)" = "true" ]; then
    docker stop -t 30 "$KUMA_CONTAINER" > /dev/null 2>&1 && KUMA_STOPPED=yes
fi

tar -czf "$WORK/backup.tar.gz" \
    --exclude="${PASSFILE#/}" \
    -C / "${REL[@]}" \
    -C "$WORK" extra
TAR_RC=$?

if [ "$KUMA_STOPPED" = yes ]; then
    docker start "$KUMA_CONTAINER" > /dev/null 2>&1 && KUMA_STOPPED=no
fi

# tar exit 1 = "a file changed while being read", which is fine here.
[ "$TAR_RC" -le 1 ] || fail "tar exited with code $TAR_RC"

# --- encrypt, then prove it decrypts --------------------------------------
export GNUPGHOME="$WORK/gnupg"
mkdir -m 700 "$GNUPGHOME"
GPG=(gpg --batch --yes --quiet --pinentry-mode loopback --passphrase-file "$PASSFILE")

"${GPG[@]}" --symmetric --cipher-algo AES256 \
    -o "$WORK/$NAME" "$WORK/backup.tar.gz" || fail "encryption failed"

FILES=$("${GPG[@]}" -d "$WORK/$NAME" 2>/dev/null | tar -tzf - 2>/dev/null | wc -l)
[ "${FILES:-0}" -gt 0 ] || fail "the encrypted archive did not decrypt cleanly"

install -m 600 "$WORK/$NAME" "$DEST/$NAME"

# Keep only the newest $KEEP archives.
ls -1t "$DEST"/homelab-*.tar.gz.gpg 2>/dev/null | tail -n +$((KEEP + 1)) | xargs -r rm -f

SIZE_BYTES=$(stat -c %s "$DEST/$NAME")
SIZE_H=$(du -h "$DEST/$NAME" | cut -f1)

body() {
    echo "Encrypted backup of $HOST, $STAMP."
    echo "Size $SIZE_H, $FILES entries -- decrypted once on the server to check it opens."
    echo
    echo "Keep this email. To restore, save the attachment and run"
    echo "(Linux, macOS, or Git Bash on Windows):"
    echo
    echo "    gpg -d $NAME | tar -xzf -"
    echo
    echo "It asks for the backup passphrase from your password manager."
    echo "(It is also in /etc/homelab/backup.pass on the server, which is no"
    echo "help if the server is the thing that died.)"
    echo
    echo "Contains: /etc/homelab, msmtprc, netplan, SSH hardening and"
    echo "authorized_keys, logind and GRUB settings, systemd units, UFW rules,"
    echo "CrowdSec config and allowlists, apt sources, package lists, and"
    echo "Uptime Kuma's data. The scripts themselves are in the git repo."
    echo
    echo "The newest $KEEP copies are also kept on the server in $DEST."
}

# --- mail it ----------------------------------------------------------------
if [ "$SIZE_BYTES" -gt $((MAX_MAIL_MB * 1024 * 1024)) ]; then
    {
    body
    echo
    echo "NOT ATTACHED: at $SIZE_H it is over the ${MAX_MAIL_MB} MB mail limit."
    echo "Copy it off the server by hand. It is root-only, so on the server:"
    echo "    sudo install -m 600 -o \"\$USER\" $DEST/$NAME ~/"
    echo "then from another machine:  scp SERVER:~/$NAME ."
    } | mail -s "[backup] $HOST $STAMP (too large to attach)" "$ALERT_EMAIL"
    exit 0
fi

BOUNDARY="homelab-backup-$(date +%s)-$$"
{
echo "To: $ALERT_EMAIL"
echo "Subject: [backup] $HOST $STAMP"
echo "MIME-Version: 1.0"
echo "Content-Type: multipart/mixed; boundary=\"$BOUNDARY\""
echo
echo "--$BOUNDARY"
echo "Content-Type: text/plain; charset=utf-8"
echo
body
echo
echo "--$BOUNDARY"
echo "Content-Type: application/octet-stream; name=\"$NAME\""
echo "Content-Transfer-Encoding: base64"
echo "Content-Disposition: attachment; filename=\"$NAME\""
echo
base64 -w 76 "$DEST/$NAME"
echo
echo "--$BOUNDARY--"
} | /usr/sbin/sendmail -t || fail "sending the mail failed (see /var/log/msmtp.log)"
