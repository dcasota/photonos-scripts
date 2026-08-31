#!/bin/bash
# mc-create-vm.sh - VM directory, thin boot disk, and VMX for one permutation.
#
# vm-lab splits this into a .ps1 because vmware-vdiskmanager wants Windows
# paths. That split costs a whole second language with its own CRLF and
# ASCII-only-for-PowerShell-5.1 constraints, and cannot be tested from here.
# The .exe runs fine from WSL, so this stays in bash and converts the two
# paths it needs by hand.
#
# usage: mc-create-vm.sh --id <perm> --iso <path> [--kickstart <file>] [--recreate]
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

PERM="" ISO="" KS="" RECREATE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --id) PERM="$2"; shift 2 ;;
        --iso) ISO="$2"; shift 2 ;;
        --kickstart) KS="$2"; shift 2 ;;
        --recreate) RECREATE=1; shift ;;
        *) mc_die "unknown arg: $1" 64 ;;
    esac
done
[ -n "$PERM" ] || mc_die "--id is required" 64
[ -n "$ISO" ] && [ -f "$ISO" ] || mc_die "--iso must name an existing file" 3

VM="mc-$PERM"
DIR_WSL="$MC_VM_ROOT_WSL/$VM"
DIR_WIN="$(mc_win_path "$DIR_WSL")"
IDX=$(mc_perm_index "$PERM")
MAC=$(mc_mac_for "$IDX")
UUID=$(mc_uuid_for "$IDX")
SERIAL_WSL="$DIR_WSL/${SERIAL_LOG_PREFIX}-${VM}.log"

if [ -d "$DIR_WSL" ] && [ "$RECREATE" -eq 1 ]; then
    mc_log "recreate: stashing $DIR_WSL"
    mv "$DIR_WSL" "${DIR_WSL}.stashed-$(date -u +%Y%m%dT%H%M%SZ)"
fi
mkdir -p "$DIR_WSL"

# --- boot disk ------------------------------------------------------------
# -t 0 is monolithicSparse: one file, thin. A fresh 32 GB disk is a few MB and
# grows only as the guest writes. The hand-made test VM on this host is
# monolithicFlat and commits its full size up front; 34 of those would not fit
# in the free space on C:.
if [ ! -f "$DIR_WSL/$VM.vmdk" ]; then
    "$VDISKMANAGER" -c -s "$BOOT_DISK_SIZE" -a "$BOOT_DISK_ADAPTER" -t "$BOOT_DISK_TYPE" \
        "$DIR_WIN\\$VM.vmdk" >/dev/null 2>&1 || mc_die "vmware-vdiskmanager failed for $VM" 5
    mc_log "created thin disk: $(du -h "$DIR_WSL/$VM.vmdk" 2>/dev/null | cut -f1) of $BOOT_DISK_SIZE"
else
    mc_log "disk already present, keeping it"
fi

# --- kickstart injection --------------------------------------------------
# POI's isoInstaller reads guestinfo.kickstart.data via vmtoolsd, and
# /usr/bin/vmtoolsd is present in the installer initrd. So an autonomous
# permutation needs no ISO remaster and no typing at the boot menu.
# Omitting the line entirely is what selects the interactive path: with no
# kickstart the installer falls through to the curses configurator, which is
# the only place the STIG menu exists.
if [ -n "$KS" ] && [ -f "$KS" ]; then
    GUESTINFO="guestinfo.kickstart.data = \"$(base64 -w0 < "$KS")\""
    mc_log "kickstart injected via guestinfo ($(wc -c < "$KS") bytes)"
else
    GUESTINFO="# no kickstart: interactive install, operator drives the curses configurator"
    mc_log "no kickstart - interactive permutation"
fi

TPL="$_here/../config/photon-matrix.vmx.template"
python3 - "$TPL" "$DIR_WSL/$VM.vmx" "$VM" "$GUEST_VCPUS" "$GUEST_MEM_MB" "$MAC" "$UUID" \
         "$(mc_win_path "$ISO")" "$(mc_win_path "$SERIAL_WSL")" "$GUESTINFO" <<'PY'
import sys
tpl, out, vm, vcpu, mem, mac, uuid, iso, serial, guestinfo = sys.argv[1:11]
s = open(tpl).read()
for k, v in (("VM_NAME", vm), ("GUEST_VCPUS", vcpu), ("GUEST_MEM_MB", mem),
             ("GUEST_MAC", mac), ("UUID_BIOS", uuid), ("ISO_PATH_WIN", iso),
             ("SERIAL_LOG_WIN", serial), ("GUESTINFO_KICKSTART", guestinfo),
             ("NIC_DEV", "vmxnet3"), ("SECUREBOOT", "FALSE")):
    s = s.replace("@@%s@@" % k, v)
import re
left = re.findall(r"@@[A-Z_]+@@", s)
if left:
    sys.exit("FAIL: unsubstituted placeholders survived: %s" % sorted(set(left)))
open(out, "w").write(s)
PY
[ $? -eq 0 ] || mc_die "VMX generation failed" 6

mc_log "vm=$VM ip=$(mc_ip_for "$IDX") mac=$MAC"
mc_log "vmx=$DIR_WSL/$VM.vmx"
printf '%s\n' "$DIR_WSL/$VM.vmx"
