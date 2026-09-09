#!/bin/bash
# 00-preflight — prove the host can do the job BEFORE anything is created.
#
# Every check prints what it measured, not just OK/FAIL, because "the tool is
# missing" and "the tool is there but unreadable by this user" need different
# fixes and look identical in a boolean.
#
# Exit 0 = safe to proceed. Non-zero = stop and read the output.
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

fail=0
ok()   { printf '  OK    %s\n' "$1"; }
bad()  { printf '  FAIL  %s\n' "$1"; fail=1; }
note() { printf '        %s\n' "$1"; }

echo "=== identity ==="
note "user: $(id -un) (uid $(id -u))"
if [ "$(id -un)" = "spagat-runner" ]; then
    bad "running as spagat-runner — vmrun.exe is mode 744 owned by dcaso; you will get 'vmrun IO: Permission denied'"
else
    ok "not spagat-runner"
fi

echo
echo "=== VMware Workstation tooling ==="
for t in "$VMRUN_WSL" "$VDISKMANAGER_WSL"; do
    if [ -e "$t" ]; then
        if [ -x "$t" ]; then ok "$(basename "$t")"; else bad "$(basename "$t") present but NOT executable by $(id -un)"; fi
    else
        bad "missing: $t"
    fi
done
if [ -x "$VMRUN_WSL" ]; then
    note "vmrun reports: $("$VMRUN_WSL" -T ws list 2>&1 | head -n 1)"
fi

echo
echo "=== VM directory ==="
if [ -d "$VM_DIR_WSL" ]; then
    ok "$VM_DIR_WSL"
    note "contents: $(ls -1 "$VM_DIR_WSL" 2>/dev/null | wc -l) entries"
else
    note "$VM_DIR_WSL does not exist yet — 10-create-vm.ps1 will create it"
fi

echo
echo "=== free space on the VM volume ==="
avail_k=$(df -k "$(dirname "$VM_DIR_WSL")" 2>/dev/null | tail -n 1 | awk '{print $4}')
if [ -n "${avail_k:-}" ]; then
    note "available: $((avail_k/1024/1024)) GB"
    # A 50 GB thin disk starts ~6 MB but the ISO alone is ~5.4 GB, and the
    # installed system grows to ~12 GB. 20 GB is the honest floor.
    if [ "$avail_k" -gt $((20*1024*1024)) ]; then ok "≥20 GB free"; else bad "under 20 GB free — the ISO copy (5.4 GB) plus a grown disk will not fit"; fi
else
    bad "could not measure free space on $(dirname "$VM_DIR_WSL")"
fi

echo
echo "=== operator medium (credential channel) ==="
med="$VM_DIR_WSL/${OPERATOR_MEDIUM_BASENAME}.vmdk"
flat="$VM_DIR_WSL/${OPERATOR_MEDIUM_BASENAME}-flat.vmdk"
if [ -f "$med" ] && [ -f "$flat" ]; then
    sz=$(stat -c%s "$flat")
    ok "descriptor + flat present"
    note "flat bytes: $sz (expected $OPERATOR_MEDIUM_FLAT_BYTES)"
    if [ "$sz" = "$OPERATOR_MEDIUM_FLAT_BYTES" ]; then ok "flat size matches"; else bad "flat size differs — this is NOT the verified medium"; fi
    grep -E 'createType|ddb.adapterType' "$med" | sed 's/^/        /'
else
    note "absent — the appliance will boot KEYLESS (no credentials)."
    note "This directory never generates it; see README 'The operator medium'."
fi

echo
echo "=== running VMs (these must not be disturbed) ==="
if [ -x "$VMRUN_WSL" ]; then
    "$VMRUN_WSL" -T ws list 2>/dev/null | sed 's/^/        /'
    if "$VMRUN_WSL" -T ws list 2>/dev/null | grep -q "$VM_NAME"; then
        bad "$VM_NAME is RUNNING — stop it before creating or reinstalling"
    else
        ok "$VM_NAME is not running"
    fi
fi

echo
echo "=== ssh keypair ==="
if [ -f "$SSH_KEY_DIR/$SSH_KEY_NAME" ]; then
    ok "private key $SSH_KEY_DIR/$SSH_KEY_NAME"
    note "pub: $(cut -d' ' -f1,3 "$SSH_KEY_DIR/$SSH_KEY_NAME.pub" 2>/dev/null)"
else
    note "no keypair yet — 20-make-ssh-key.sh creates one."
    note "🚨 The pubkey must be baked at ISO BUILD time; it cannot be added later."
fi

echo
if [ "$fail" -eq 0 ]; then echo "PREFLIGHT: PASS"; else echo "PREFLIGHT: FAIL — fix the above before continuing"; fi
exit $fail
