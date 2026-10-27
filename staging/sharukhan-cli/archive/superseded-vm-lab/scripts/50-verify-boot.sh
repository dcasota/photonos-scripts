#!/bin/bash
# 50-verify-boot — is the guest alive, and did THIS boot do anything?
#
# The only unambiguous instrument while root is locked is whether the serial
# log GROWS. Everything else is inference:
#
#   * `vmrun list` omits GUI-started VMs entirely — absence is not "off".
#   * A CPU reading of 0.05 usually means the counter has not moved yet, not
#     that the guest is idle. Measure a DELTA over ~25 s.
#   * A black screen at t≈130 s is normal; the TUI starts at t≈133 s.
#   * Elapsed time is not evidence of a stall. Read the step, not the clock.
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

STAMP=""
SAMPLE=25
while [ $# -gt 0 ]; do
    case "$1" in
        --stamp) STAMP="$2"; shift 2 ;;
        --sample-sec) SAMPLE="$2"; shift 2 ;;
        *) echo "unknown arg: $1"; exit 64 ;;
    esac
done

if [ -n "$STAMP" ]; then
    SER="$VM_DIR_WSL/${SERIAL_LOG_PREFIX}-${STAMP}.log"
else
    SER=$(ls -1t "$VM_DIR_WSL"/${SERIAL_LOG_PREFIX}-*.log 2>/dev/null | head -n 1)
fi
[ -n "$SER" ] && [ -f "$SER" ] || { echo "no serial log found (looked in $VM_DIR_WSL)"; exit 2; }

echo "=== serial log ==="
echo "  $SER"
echo "  bytes: $(stat -c%s "$SER")   mtime: $(stat -c%y "$SER" | cut -c1-19)"

echo
echo "=== THE instrument: does it grow over ${SAMPLE}s? ==="
a=$(stat -c%s "$SER"); sleep "$SAMPLE"; b=$(stat -c%s "$SER")
echo "  $a -> $b   delta=$((b-a))"
if [ "$b" -gt "$a" ]; then
    echo "  GROWING — the guest is doing work"
else
    echo "  no growth in this sample."
    echo "  That is NOT by itself a stall: a single long unit (a release build,"
    echo "  a big cargo install) can be quiet for minutes. Check the process"
    echo "  and the last log line before concluding anything."
fi

echo
echo "=== is VMware running it? (note: GUI-started VMs are invisible here) ==="
if [ -x "$VMRUN_WSL" ]; then
    "$VMRUN_WSL" -T ws list 2>/dev/null | sed 's/^/  /'
    "$VMRUN_WSL" -T ws list 2>/dev/null | grep -q "$VM_NAME" \
        && echo "  $VM_NAME: listed as running" \
        || echo "  $VM_NAME: NOT listed — may still be running if started from the GUI"
fi

echo
echo "=== last readable serial lines (NULs stripped, ANSI removed) ==="
tail -c 6000 "$SER" | tr -d '\000' | sed -E 's/\x1b\[[0-9;]*m//g' | tail -n 15 | cut -c1-170 | sed 's/^/  /'

echo
echo "=== failed units this boot ==="
tail -c 400000 "$SER" | tr -d '\000' | sed -E 's/\x1b\[[0-9;]*m//g' \
  | grep -aE 'SPAGAT-DIAG: failed unit|Failed to start' | tail -n 12 | cut -c1-170 | sed 's/^/  /'
echo "  (blank = none seen in the tail)"

echo
echo "=== console/TUI markers ==="
# -a on every grep: NUL bytes otherwise make grep print nothing at all.
for p in 'Started Spagat-Librarian Kanban TUI on tty1' 'spagat-console.service' 'Reached target'; do
    _n=$(grep -ac "$p" "$SER") || _n=0
    printf '  %-46s %s\n' "$p" "$_n"
done
_c=$(grep -ac 'zzz-not-a-real-marker' "$SER") || _c=0
echo "  control (must be 0): $_c"
