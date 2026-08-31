#!/bin/bash
# mc-install.sh - run one install, autonomously or with an operator.
#
# This is the part vm-lab delegates to spagat-vm-orchestrator, which is a
# cargo artifact of a repo we do not have. Everything it did is reachable with
# vmrun plus VMX edits; the only genuinely non-trivial piece is deciding when
# an install has finished, which is done here by watching the boot source
# change in the serial log.
#
# usage: mc-install.sh --id <perm> --mode auto|interactive [--timeout <sec>]
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

PERM="" MODE=auto TIMEOUT=""
while [ $# -gt 0 ]; do
    case "$1" in
        --id) PERM="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) mc_die "unknown arg: $1" 64 ;;
    esac
done
[ -n "$PERM" ] || mc_die "--id is required" 64
TIMEOUT="${TIMEOUT:-$MC_INSTALL_TIMEOUT_SEC}"

VM="mc-$PERM"
DIR="$MC_VM_ROOT_WSL/$VM"
VMX="$DIR/$VM.vmx"
SER="$DIR/${SERIAL_LOG_PREFIX}-${VM}.log"
[ -f "$VMX" ] || mc_die "no VMX at $VMX - run mc-create-vm.sh first" 3

vm_is_up() { "$VMRUN" -T ws list 2>/dev/null | tr -d '\r' | grep -qi "$VM\.vmx"; }

# UEFI ignores bios.bootOrder, so the only way to stop the firmware booting the
# PREVIOUS image out of the old ESP is to remove the NVRAM. vm-lab learned this
# the hard way; deleting the disk alone does not help because UEFI re-detects.
if [ -f "$DIR/$VM.nvram" ]; then
    mv "$DIR/$VM.nvram" "$DIR/$VM.nvram.stashed-$(date -u +%Y%m%dT%H%M%SZ)"
    mc_log "stashed NVRAM so UEFI cannot fall back to a previous image"
fi

: > "$SER" 2>/dev/null || true
START_SIZE=$(stat -c%s "$SER" 2>/dev/null || echo 0)

if [ "$MODE" = interactive ]; then
    "$VMRUN" -T ws start "$(mc_win_path "$VMX")" gui >/dev/null 2>&1 \
        || mc_die "could not start $VM" 5
    cat <<TXT

  ============================================================
  INTERACTIVE PERMUTATION $PERM
  ============================================================
  The VM is up with its console visible. This path exists because
  the STIG menu is reachable ONLY from the curses configurator -
  a kickstart cannot answer it - so it has to be driven by hand.

  In the installer, choose:
    filesystem      : $(awk -v p="$PERM" '$1==p{print $5}' "$_here/../config/permutations.tsv")
    STIG hardening  : $(awk -v p="$PERM" '$1==p{print $4}' "$_here/../config/permutations.tsv")
    root password   : MissionControl123!
    hostname        : mc-$PERM

  Mission control is watching $SER and will continue on its own
  once the guest reboots off disk. Press Ctrl-C here to abandon.
  ============================================================

TXT
else
    "$VMRUN" -T ws start "$(mc_win_path "$VMX")" nogui >/dev/null 2>&1 || mc_die "could not start $VM" 5
    mc_log "$VM started headless; kickstart supplied via guestinfo"
fi

# --- completion detection -------------------------------------------------
# root=/dev/ram0 is the installer live environment; root=PARTUUID= is the
# installed system. The transition is the only unambiguous "the install
# finished and the machine came back on its own" signal.
mc_log "waiting up to ${TIMEOUT}s for the guest to boot off disk"
deadline=$(( $(date +%s) + TIMEOUT ))
last_size=0 stalled=0 result=timeout
while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 15
    [ -f "$SER" ] || continue
    size=$(stat -c%s "$SER" 2>/dev/null || echo 0)
    if [ "$size" -eq "$last_size" ]; then stalled=$((stalled+1)); else stalled=0; fi
    last_size=$size
    if [ "$(mc_grep_count 'root=PARTUUID=' "$SER")" -gt 0 ]; then result=installed; break; fi
    if [ "$(mc_grep_count 'Error(1011)' "$SER")" -gt 0 ]; then result=error1011; break; fi
    # A long quiet stretch is not proof of a stall - vm-lab is explicit that
    # no growth is not by itself a hang - so this only reports, never aborts.
    [ $((stalled % 20)) -eq 19 ] && mc_log "serial log quiet for ~5min (size=${size}); still waiting"
done

case "$result" in
    installed) mc_log "install completed: guest is booting from disk" ;;
    error1011) mc_log "install FAILED with Error(1011) - a package the installer requested is not on the media" ;;
    timeout)   mc_log "timed out after ${TIMEOUT}s with no boot-from-disk transition" ;;
esac

# Detach the CDROM so a later boot cannot re-enter the installer.
sed -i 's|^sata0:1.startConnected = "TRUE"|sata0:1.startConnected = "FALSE"|' "$VMX" 2>/dev/null || true

printf '%s\n' "$result"
[ "$result" = installed ] || exit 7
