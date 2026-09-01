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

PERM="" MODE=auto TIMEOUT="" NOWAIT=0
while [ $# -gt 0 ]; do
    case "$1" in
        --id) PERM="$2"; shift 2 ;;
        --mode) MODE="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        --no-wait) NOWAIT=1; shift ;;
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

# vmrun exits 0 even when the VM does not actually come up - a stale modal in
# the Workstation UI silently swallows the power-on request. Trusting the exit
# code once cost a full 40-minute timeout waiting on a VM that never existed.
# Confirm the VM is really in the inventory before going any further.
start_vm_verified() {
    # vmrun's exit code is not evidence in EITHER direction. It exits 0 when a
    # stale modal has silently swallowed the power-on, and it exits non-zero
    # when the VM is merely slow to start - attaching a 3.9G full ISO trips its
    # internal timeout while VMware carries on powering the VM up regardless.
    # Both were observed here. So issue the start, ignore what it claims, and
    # believe only the inventory.
    "$VMRUN" -T ws start "$(mc_win_path "$VMX")" gui >/dev/null 2>&1
    _rc=$?
    _w=0
    while [ "$_w" -lt "${MC_START_TIMEOUT:-240}" ]; do
        vm_is_up && { mc_log "$VM confirmed running after ${_w}s (vmrun rc=$_rc)"; return 0; }
        sleep 5; _w=$((_w+5))
    done
    mc_die "$VM never appeared in the inventory after ${_w}s (vmrun rc=$_rc) - check for a modal dialog in the VMware Workstation UI" 5
}

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
    start_vm_verified
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
    root password   : $MC_GUEST_PASSWORD
    hostname        : mc-$PERM

  Mission control is watching $SER and will continue on its own
  once the guest reboots off disk. Press Ctrl-C here to abandon.
  ============================================================

TXT
else
    # gui, not nogui. On this host "vmrun -T ws start <vmx> nogui" fails with
    # "Error: Unknown error" and does not even create a vmware.log, while the
    # identical VMX starts fine with "gui". Headless start needs VMware
    # Workstation Server / shared-VM support, which is not enabled here.
    start_vm_verified
    mc_log "$VM started headless; kickstart supplied via guestinfo"
fi

# With --no-wait the VM is left running for a human to drive; the caller
# decides when to verify. Used for the UI rows, where blocking here would hide
# the operator instructions behind a poll loop.
if [ "$NOWAIT" -eq 1 ]; then
    mc_log "$VM is up and waiting for the operator"
    exit 0
fi

# --- completion detection -------------------------------------------------
# root=/dev/ram0 is the installer live environment; root=PARTUUID= is the
# installed system. The transition is the only unambiguous "the install
# finished and the machine came back on its own" signal.
mc_log "waiting up to ${TIMEOUT}s for the guest to boot off disk"
deadline=$(( $(date +%s) + TIMEOUT ))
last_size=0 stalled=0 result=timeout GUEST_IP=""
while [ "$(date +%s)" -lt "$deadline" ]; do
    sleep 15
    [ -f "$SER" ] || continue
    size=$(stat -c%s "$SER" 2>/dev/null || echo 0)
    if [ "$size" -eq "$last_size" ]; then stalled=$((stalled+1)); else stalled=0; fi
    last_size=$size
    # Two independent completion signals, because either alone is fragile:
    #  (a) the boot source moves from the installer live env to the disk. Only
    #      visible if the INSTALLED system also has a serial console, which the
    #      kickstart arranges - a stock target is silent here.
    #  (b) the guest answers as a booted machine. open-vm-tools is in the
    #      minimal package set, so a reachable IP means the install finished
    #      and the target came up on its own.
    if [ "$(mc_grep_count 'root=PARTUUID=' "$SER")" -gt 0 ]; then result=installed; break; fi
    gip=$("$VMRUN" -T ws getGuestIPAddress "$(mc_win_path "$VMX")" 2>/dev/null | tr -d '\r' | tail -1)
    case "$gip" in
        [0-9]*.[0-9]*.[0-9]*.[0-9]*) mc_log "guest reachable at $gip"; GUEST_IP="$gip"; result=installed; break ;;
    esac
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

# Record what this phase PROVED. mc-verify used to re-derive both facts from
# scratch and got them wrong: the installed system is serial-silent unless the
# kickstart grub edit takes, so "root=PARTUUID=" never appears, and re-querying
# the guest IP races against first boot. Evidence observed here is authoritative;
# a later phase must not overturn it by failing to reproduce it.
cat > "$DIR/mc-facts.env" <<EOF
MC_INSTALL_RESULT=$result
MC_GUEST_IP=$GUEST_IP
EOF

# Detach the CDROM so a later boot cannot re-enter the installer.
sed -i 's|^sata0:1.startConnected = "TRUE"|sata0:1.startConnected = "FALSE"|' "$VMX" 2>/dev/null || true

printf '%s\n' "$result"
[ "$result" = installed ] || exit 7
