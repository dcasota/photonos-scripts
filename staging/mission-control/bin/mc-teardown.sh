#!/bin/bash
# mc-teardown.sh - return one permutation's VM to a fresh-disk state.
#
# Nothing is deleted; files are renamed .stashed-<ts>. Recovery is a rename
# back. The whole chain goes, not just the disk: if any piece survives, UEFI's
# removable-media fallback finds the old ESP and boots the PREVIOUS image -
# and bios.bootOrder is ignored on EFI VMs, so that is the only control.
#
# The serial log and the results directory are always preserved: they are the
# evidence the run produced.
#
# usage: mc-teardown.sh --id <perm> [--purge]   (--purge deletes old stashes)
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

PERM="" PURGE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --id) PERM="$2"; shift 2 ;;
        --purge) PURGE=1; shift ;;
        *) mc_die "unknown arg: $1" 64 ;;
    esac
done
[ -n "$PERM" ] || mc_die "--id is required" 64

VM="mc-$PERM"; DIR="$MC_VM_ROOT_WSL/$VM"
[ -d "$DIR" ] || { mc_log "$DIR does not exist, nothing to tear down"; exit 0; }

# Only ever stop our own VM. Other VMs on this host may be live CI runners.
if "$VMRUN" -T ws list 2>/dev/null | tr -d '\r' | grep -qi "$VM\.vmx"; then
    mc_log "stopping $VM"
    "$VMRUN" -T ws stop "$(mc_win_path "$DIR/$VM.vmx")" hard >/dev/null 2>&1 || true
    sleep 3
fi

TS=$(date -u +%Y%m%dT%H%M%SZ)
n=0
# Globbed, not enumerated: a fixed list of two snapshot deltas silently leaves
# an orphan on a VM that reached -000003.vmdk.
for f in "$DIR"/*.vmdk "$DIR"/*.vmsn "$DIR"/*.vmsd "$DIR"/*.nvram "$DIR"/*.vmss; do
    [ -e "$f" ] || continue
    case "$f" in *.stashed-*) continue ;; esac
    mv "$f" "${f}.stashed-$TS" && n=$((n+1))
done
rm -rf "$DIR"/*.lck 2>/dev/null || true
mc_log "stashed $n file(s) with suffix .stashed-$TS"

kept=$(ls "$DIR"/${SERIAL_LOG_PREFIX}-*.log 2>/dev/null | wc -l)
mc_log "preserved $kept serial log(s) - they are this run's evidence"

if [ "$PURGE" -eq 1 ]; then
    old=$(find "$DIR" -name '*.stashed-*' 2>/dev/null | wc -l)
    find "$DIR" -name '*.stashed-*' -delete 2>/dev/null || true
    mc_log "purged $old stashed file(s) to reclaim space"
fi
