#!/bin/bash
# 40-check-staging — answer "did the thing I think is staged actually get
# staged?" at each of the three places staging happens.
#
#   --rootfs <dir>   the BUILT ROOTFS the ISO was made from (iso-rootfs-<sha>)
#   --iso <path>     the finished ISO + its sidecars
#   --guest          the RUNNING guest, via its serial log
#
# Pass any combination. With no flag it checks whatever it can find.
#
# DESIGN RULE: every check prints the measured value, and the ones that can
# be vacuous carry a control. A check that prints nothing is indistinguishable
# from a check that passed — that failure mode is the whole reason this script
# exists.
set -u
# --- locate + load the config, FAIL CLOSED --------------------------------
# ${BASH_SOURCE[0]} may point at a COPY in /tmp: the standard WSL workflow
# here is: tr -d CR < script > /tmp/x.sh ; bash /tmp/x.sh  (strips CRLF),
# which breaks any path computed relative to the script. Try the plausible
# locations and REFUSE to continue if none has the config - a previous
# version merely failed to source it and carried on, printing a healthy
# looking first section before dying on unbound variables further down.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
CFG=""
for _c in "${VM_LAB_DIR:-}/config/vm-lab.env" \
          "$_here/../config/vm-lab.env" \
          "$_here/config/vm-lab.env" \
          "$PWD/config/vm-lab.env" \
          "$PWD/../config/vm-lab.env"; do
    if [ -n "$_c" ] && [ -f "$_c" ]; then CFG="$_c"; break; fi
done
if [ -z "$CFG" ]; then
    echo "FATAL: cannot locate config/vm-lab.env" >&2
    echo "  Run from deploy/vm-lab/, or: export VM_LAB_DIR=/path/to/deploy/vm-lab" >&2
    exit 78
fi
# shellcheck source=../config/vm-lab.env
. "$CFG"
HERE="$_here"

ROOTFS=""; ISO=""; GUEST=0
while [ $# -gt 0 ]; do
    case "$1" in
        --rootfs) ROOTFS="$2"; shift 2 ;;
        --iso) ISO="$2"; shift 2 ;;
        --guest) GUEST=1; shift ;;
        *) echo "unknown arg: $1"; exit 64 ;;
    esac
done
if [ -z "$ROOTFS" ] && [ -z "$ISO" ] && [ "$GUEST" -eq 0 ]; then
    ROOTFS=$(ls -1td "$ISO_OUT_ROOT"/iso-rootfs-* 2>/dev/null | head -n 1)
    ISO=$(ls -1t "$ISO_OUT_ROOT"/iso-out-*/*.iso 2>/dev/null | head -n 1)
    GUEST=1
    echo "(no flags — auto-selected the newest of each)"
fi

# ---------------------------------------------------------------- 1. ROOTFS --
if [ -n "$ROOTFS" ] && [ -d "$ROOTFS" ]; then
echo "=============================================================="
echo "1. BUILT ROOTFS — what the ISO was actually made from"
echo "   $ROOTFS   ($(du -sh "$ROOTFS" 2>/dev/null | cut -f1))"
echo "=============================================================="

echo "-- build identity (the only field that proves WHICH image) --"
grep -E '^build_label|^profile|^built_at' "$ROOTFS/etc/spagat/appliance-info.toml" 2>/dev/null | sed 's/^/   /'

echo "-- staged binaries --"
BD="$ROOTFS/usr/local/bin"
echo "   count: $(ls -1 "$BD" 2>/dev/null | wc -l)"
echo "   control (a name that must NOT exist): $(ls -1 "$BD"/zzz-not-a-real-binary 2>/dev/null | wc -l)  (must be 0)"

echo "-- appliance source staged (BUG-N182: upstream-drift-detector chdirs here) --"
if [ -d "$ROOTFS/opt/spagat/appliance-src" ]; then
    echo "   PRESENT, $(find "$ROOTFS/opt/spagat/appliance-src" -maxdepth 1 | wc -l) top-level entries"
else
    echo "   *** ABSENT — the drift detector will fail 200/CHDIR at first boot ***"
fi

echo "-- SSH: is a key actually baked in? --"
# The kickstart writes authorized_keys at INSTALL time from a template
# placeholder, so the rootfs shows the KICKSTART, not the file.
KS=$(find "$ROOTFS" -name 'kickstart*.cfg' -o -name '*.ks.json' 2>/dev/null | head -n 1)
echo "   kickstart in rootfs: ${KS:-<none — it lives on the ISO, see section 2>}"

echo "-- tmpfiles: the audit tier must stay 0750 --"
grep -hE '^d[[:space:]]+/var/spagat/audit[[:space:]]' "$ROOTFS"/etc/tmpfiles.d/*.conf 2>/dev/null | sed 's/^/   /'
echo "   (widening this is never the right fix for an EACCES)"
echo
fi

# ------------------------------------------------------------------- 2. ISO --
if [ -n "$ISO" ] && [ -f "$ISO" ]; then
echo "=============================================================="
echo "2. ISO + sidecars"
echo "   $ISO"
echo "=============================================================="
echo "   bytes : $(stat -c%s "$ISO")"
echo "   sha256: $(sha256sum "$ISO" | cut -d' ' -f1)"
if [ "$(id -u)" -ne 0 ]; then
    echo "   ⚠ NOT ROOT — the sidecars are 0600 root. Unreadable here reads as"
    echo "     MISMATCH even when the ISO is fine. Re-run as root for section 2."
fi
for x in sha256 manifest.json sig; do
    f="$ISO.$x"
    if [ -r "$f" ]; then echo "   readable: $(basename "$f") ($(stat -c%s "$f") bytes)"
    elif [ -e "$f" ]; then echo "   EXISTS BUT UNREADABLE: $(basename "$f")"
    else echo "   absent: $(basename "$f")"; fi
done

echo "-- the four hashes must agree --"
calc=$(sha256sum "$ISO" | cut -d' ' -f1)
side=$(grep -oE '[0-9a-f]{64}' "$ISO.sha256" 2>/dev/null | head -n1)
man=$(jq -r '.iso_sha256 // empty' "$ISO.manifest.json" 2>/dev/null)
# NOTE: the "passport" the docs mention is emitted as <iso>.sig. There is no
# *passport*.json anywhere; not finding that filename is NOT evidence the
# check does not apply.
pp=$(jq -r '.rpm_sha256 // empty' "$ISO.sig" 2>/dev/null)
printf '   %-22s %s\n' recomputed "$calc"
printf '   %-22s %s\n' .sha256 "${side:-<unreadable>}"
printf '   %-22s %s\n' manifest "${man:-<unreadable>}"
printf '   %-22s %s\n' sig.rpm_sha256 "${pp:-<unreadable>}"
u=$(printf '%s\n%s\n%s\n%s\n' "$calc" "$side" "$man" "$pp" | sort -u | wc -l)
[ "$u" -eq 1 ] && echo "   -> ALL AGREE" || echo "   -> $u DISTINCT VALUES"
u2=$(printf '%s\n%s\n' "$calc" "0000000000000000000000000000000000000000000000000000000000000000" | sort -u | wc -l)
[ "$u2" -eq 2 ] && echo "   control: a wrong hash yields 2 values -> the comparison discriminates" \
                || echo "   *** control did not fail — this comparison proves nothing ***"

echo "-- 🚨 IS AN SSH KEY BAKED INTO THE ISO'S KICKSTART? --"
# This is the check people skip and then spend a day on "the appliance
# refuses my key". Read it out of the ISO itself.
if command -v xorriso >/dev/null 2>&1; then
    tmpks=$(mktemp)
    xorriso -osirrox on -indev "$ISO" -extract /spagat/kickstart.cfg "$tmpks" >/dev/null 2>&1 || true
    if [ -s "$tmpks" ]; then
        n=$(grep -c 'ssh-ed25519\|ssh-rsa' "$tmpks" 2>/dev/null) || n=0
        echo "   ssh public keys in the ISO kickstart: $n"
        if [ "$n" -gt 0 ]; then
            grep -oE '(ssh-ed25519|ssh-rsa) [A-Za-z0-9+/=]{20}' "$tmpks" | sed 's/^/     /'
            echo "   -> SSH WILL WORK for whoever holds the matching private key"
        else
            echo "   -> NO KEY BAKED IN. authorized_keys ships EMPTY."
            echo "      The serial console is your only way in. Re-export"
            echo "      SPAGAT_OPERATOR_AUTHORIZED_KEY and rebuild the ISO."
        fi
        # `n=$(grep -c ...) || n=0`, never `$(grep -c ... || echo 0)`:
        # grep -c PRINTS 0 and EXITS 1 on no match, so the inline form emits
        # the two-line string "0\n0" and every later numeric test on it dies.
        _kc=$(grep -c 'zzz-not-a-real-key' "$tmpks") || _kc=0
        echo "   control (a token that must NOT be there): $_kc  (must be 0)"
        echo "   static IP in the kickstart:"
        grep -oE 'Address=[0-9./]+' "$tmpks" 2>/dev/null | sort -u | sed 's/^/     /'
        echo "   root password: $(grep -oE '"crypted": true, "text": "[^"]{0,3}' "$tmpks" 2>/dev/null | sed 's/.*"text": "//')  ('*' = LOCKED)"
    else
        echo "   could not extract /spagat/kickstart.cfg from the ISO"
    fi
    rm -f "$tmpks" 2>/dev/null || true
else
    echo "   xorriso not available — cannot read the kickstart out of the ISO"
fi
echo
fi

# ----------------------------------------------------------------- 3. GUEST --
if [ "$GUEST" -eq 1 ]; then
echo "=============================================================="
echo "3. GUEST — what the running/installed system actually did"
echo "=============================================================="
SER=$(ls -1t "$VM_DIR_WSL"/${SERIAL_LOG_PREFIX}-*.log 2>/dev/null | head -n 1)
if [ -z "$SER" ]; then echo "   no serial log under $VM_DIR_WSL"; exit 0; fi
echo "   serial: $SER ($(stat -c%s "$SER") bytes)"

# `-a` on EVERY grep: the serial log contains NUL bytes and without it grep
# treats the file as binary and prints NOTHING — which reads exactly like
# "the line is not there".
SLICE=$(mktemp)
STAMP=$(basename "$SER" .log); STAMP=${STAMP#${SERIAL_LOG_PREFIX}-}
OFF=$(cat "$ISO_OUT_ROOT/serial-offset-${STAMP}" 2>/dev/null || echo 0)
tail -c +$((OFF+1)) "$SER" | tr -d '\000' | sed -E 's/\x1b\[[0-9;]*m//g' > "$SLICE"
echo "   reading only past offset $OFF ($(stat -c%s "$SLICE") bytes belong to this run)"

echo "-- which system booted? --"
echo "   kernel boots in this run: $(grep -ac 'Linux version' "$SLICE")"
grep -ao 'root=[^ ]*' "$SLICE" | sort -u | sed 's/^/     /'
echo "     root=/dev/ram0 + isolinux = the INSTALLER live env"
echo "     root=PARTUUID=...         = the INSTALLED system"
grep -ao 'running in system mode' "$SLICE" | head -n 2 | sed 's/^/     /'
echo "     (anything logged BEFORE that line is the initrd's systemd, a"
echo "      different /etc — never compare timestamps across the boundary)"

echo "-- build identity the guest self-reports --"
grep -ao 'spagat-librarian-iter[0-9]*-[a-f0-9]*' "$SLICE" | sort -u | sed 's/^/     /'

echo "-- credential injection (the keystone) --"
for p in 'SPAGAT_OP_DISCOVERY' 'mount=mounted+nonempty' 'PQ verify-key loaded' \
         'bundle PQ signature verified' 'in-process priv-drop succeeded' \
         'audit log handed to the priv-drop target' 'finished providers=' 'AbsentLegacy'; do
    _n=$(grep -ac "$p" "$SLICE") || _n=0
    printf '     %-46s %s\n' "$p" "$_n"
done
echo "   PASS = 'finished providers=N' with N>=1 AND operator_tree != AbsentLegacy"
grep -ao 'finished providers=[0-9]*' "$SLICE" | sort | uniq -c | sed 's/^/     /'
grep -aE 'hab-credentials-injector.*(FATAL|Failed|exited)' "$SLICE" | tail -n 3 | cut -c1-170 | sed 's/^/     /'

echo "-- ssh reachability from here --"
echo "     guest IP (from the kickstart): $GUEST_IP_BARE"
if command -v nc >/dev/null 2>&1; then
    if nc -z -w3 "$GUEST_IP_BARE" 22 2>/dev/null; then echo "     port 22: OPEN"; else echo "     port 22: closed/unreachable"; fi
else
    echo "     (nc not available — skip)"
fi
echo "-- console / TUI --"
_n=$(grep -ac 'Started Spagat-Librarian Kanban TUI on tty1' "$SLICE") || _n=0
printf '     %-46s %s\n' 'Started Spagat-Librarian Kanban TUI on tty1' "$_n"
echo "     ('FAIL spagat-console: container not running' is a RED HERRING —"
echo "      it asserts on a retired container, not the live TUI)"
rm -f "$SLICE"
fi
