#!/bin/bash
# 30-install-from-iso — unattended install onto the lab VM.
#
# Usage:
#   ./30-install-from-iso.sh --iso /home/dcaso/work/iso-out-<sha>/<name>.iso
#   ./30-install-from-iso.sh --iso <path> --orchestrator <path-to-binary>
#
# WHAT THIS WRAPS
#   spagat-vm-orchestrator install-from-iso — the tested path. It edits the
#   existing VMX in place: attaches the ISO on sata0:1, flips bios.bootOrder
#   to cdrom-first for the install window, powers on, waits for install
#   completion, then restores hdd-first, detaches the CDROM and moves NVRAM
#   aside. It NEVER touches scsi0:1, so the operator medium survives verbatim.
#
# DELIBERATE OMISSIONS
#   --force           auto-stops a running instance. Other VMs on this host
#                     may be live CI runners; this script refuses instead.
#   --efuse-vmdk      attaches an install-time marker on sata0:0 that finalize
#                     then DETACHES. The operator medium is a PERSISTENT
#                     boot-time disk on scsi0:1 — passing this flag for it is
#                     wrong.
#   --root-password-file / --operator-medium-dir
#                     all-or-nothing (BUG-N91). Omitted here, so root installs
#                     LOCKED. `BUG-N91: no --root-password-file supplied` in
#                     the log is EXPECTED, not a fault.
#
# PATH FORM: pass the LINUX path. vmx-info parses /mnt/c/... and fails on
# C:\... with "VMX I/O: No such file or directory"; the orchestrator does the
# Windows translation itself (BUG-N9 / #617).
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

ISO=""
ORCH=""
INSTALL_WINDOW=1200
BOOT_WINDOW=600
while [ $# -gt 0 ]; do
    case "$1" in
        --iso) ISO="$2"; shift 2 ;;
        --orchestrator) ORCH="$2"; shift 2 ;;
        --install-window-sec) INSTALL_WINDOW="$2"; shift 2 ;;
        --boot-window-sec) BOOT_WINDOW="$2"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 64 ;;
    esac
done
[ -n "$ISO" ] || { echo "usage: $0 --iso <path> [--orchestrator <path>]"; exit 64; }

VMX="$VM_DIR_WSL/$VM_NAME.vmx"
STAMP="$(basename "$ISO" .iso)"
SERIAL="$VM_DIR_WSL/${SERIAL_LOG_PREFIX}-${STAMP}.log"
LOG="$ISO_OUT_ROOT/install-${STAMP}.log"
OFFSET_FILE="$ISO_OUT_ROOT/serial-offset-${STAMP}"

# Locate the orchestrator: prefer an explicit path, else the newest build.
if [ -z "$ORCH" ]; then
    ORCH=$(ls -1t "$ISO_OUT_ROOT"/iso-build-*/tools/spagat-rust/target/x86_64-unknown-linux-musl/release/spagat-vm-orchestrator 2>/dev/null | head -n 1)
fi

echo "===== pre-flight ====="
echo "  orchestrator : ${ORCH:-<none found>}"
[ -n "$ORCH" ] && [ -x "$ORCH" ] || { echo "  *** orchestrator not found or not executable ***"; exit 2; }
echo "  vmx          : $VMX"
echo "  iso          : $ISO"
[ -f "$VMX" ] || { echo "  *** VMX missing — run 10-create-vm.ps1 first ***"; exit 3; }
[ -f "$ISO" ] || { echo "  *** ISO missing ***"; exit 3; }

echo -n "  $VM_NAME running? : "
if "$ORCH" list 2>/dev/null | grep -q "$VM_NAME"; then
    echo "YES — stop it first. NOT passing --force (other VMs here may be live CI runners)."
    exit 4
fi
echo "no"
echo "  other VMs (left alone):"
"$ORCH" list 2>/dev/null | sed 's/^/    /'

# Integrity: the ISO must match its own sidecar. 9p -> NTFS is where a short
# write hides, and a truncated ISO installs a subtly broken appliance.
echo -n "  iso sha256   : "
actual=$(sha256sum "$ISO" | cut -d' ' -f1); echo "$actual"
if [ -f "$ISO.sha256" ]; then
    expect=$(grep -oE '[0-9a-f]{64}' "$ISO.sha256" | head -n1)
    echo "  sidecar      : $expect"
    [ "$actual" = "$expect" ] || { echo "  *** HASH MISMATCH — refusing to install ***"; exit 5; }
    echo "  hash OK"
else
    echo "  (no .sha256 sidecar next to the ISO — cannot cross-check)"
fi

echo "  operator medium at scsi0:1:"
grep -E 'scsi0:1' "$VMX" | sed 's/^/    /'
if [ -f "$VM_DIR_WSL/${OPERATOR_MEDIUM_BASENAME}-flat.vmdk" ]; then
    echo "    flat bytes: $(stat -c%s "$VM_DIR_WSL/${OPERATOR_MEDIUM_BASENAME}-flat.vmdk")"
else
    echo "    *** ABSENT — this install will boot KEYLESS ***"
fi

# Point the serial log at this build so RCA logs never interleave, and record
# where the existing log ends: only bytes past that offset belong to this run.
if ! grep -q "${SERIAL_LOG_PREFIX}-${STAMP}.log" "$VMX"; then
    cp "$VMX" "$VMX.pre-${STAMP}-$(date -u +%Y%m%dT%H%M%SZ)"
    win_serial="${VM_DIR_WIN}\\${SERIAL_LOG_PREFIX}-${STAMP}.log"
    esc=$(printf '%s' "$win_serial" | sed 's/\\/\\\\/g')
    sed -i "s|^serial0.fileName = .*|serial0.fileName = \"$esc\"|" "$VMX"
fi
grep -E '^serial0.fileName' "$VMX" | sed 's/^/  /'

OFF=$(stat -c%s "$SERIAL" 2>/dev/null || echo 0)
echo "$OFF" > "$OFFSET_FILE"
echo "  serial offset: $OFF  (read ONLY past this — previous boots stay as evidence)"

echo
echo "===== launching install-from-iso ====="
: > "$LOG"
nohup "$ORCH" install-from-iso \
    --vmx "$VMX" \
    --iso "$ISO" \
    --install-window-sec "$INSTALL_WINDOW" \
    --boot-window-sec "$BOOT_WINDOW" \
    >> "$LOG" 2>&1 &
PID=$!
echo "  pid $PID at $(date -u +%H:%M:%SZ)"
echo "  log     $LOG"
echo "  serial  $SERIAL"
echo "  offset  $OFFSET_FILE"

sleep 90
echo
echo "===== first 25 log lines ====="
sed -E 's/\x1b\[[0-9;]*m//g' "$LOG" | head -n 25 | cut -c1-190
echo
kill -0 "$PID" 2>/dev/null && echo "  RUNNING" || echo "  EXITED — read $LOG"
echo -n "  serial bytes: "; stat -c%s "$SERIAL" 2>/dev/null || echo "not created yet"
echo
echo "NEXT: scripts/50-verify-boot.sh --stamp $STAMP"
