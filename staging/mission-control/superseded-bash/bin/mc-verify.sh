#!/bin/bash
# mc-verify.sh - run the oracle against one installed permutation and harvest logs.
# usage: mc-verify.sh --id <perm> [--ip <addr>]
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$_here/../lib/oracle.sh"
. "$(mc_find_config "$_here")"

PERM="" IP=""
while [ $# -gt 0 ]; do
    case "$1" in
        --id) PERM="$2"; shift 2 ;;
        --ip) IP="$2"; shift 2 ;;
        *) mc_die "unknown arg: $1" 64 ;;
    esac
done
[ -n "$PERM" ] || mc_die "--id is required" 64

TSV="$_here/../config/permutations.tsv"
read -r _ ISO_TYPE POI STIG FS MODE VARIANT DOC EXPECT CANISTER <<EOF
$(grep -vE '^#|^$' "$TSV" | awk -v p="$PERM" '$1==p')
EOF
[ -n "${ISO_TYPE:-}" ] || mc_die "permutation $PERM not found in $TSV" 65

VM="mc-$PERM"; DIR="$MC_VM_ROOT_WSL/$VM"
SER="$DIR/${SERIAL_LOG_PREFIX}-${VM}.log"
mc_result_init "$PERM"
MC_RUN_STAMP="${MC_RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"; export MC_RUN_STAMP
HARVEST="$MC_RESULTS_DIR/$PERM/logs-$MC_RUN_STAMP"; mkdir -p "$HARVEST"
ln -sfn "$(basename "$HARVEST")" "$MC_RESULTS_DIR/$PERM/logs-latest"

echo "== $PERM  iso=$ISO_TYPE poi=$POI stig=$STIG fs=$FS mode=$MODE =="
mc_check meta.doc_verdict "-" info "" "$DOC" "what ISO-PERMUTATION-MATRIX.md records"
mc_check meta.expected    "-" info "" "$EXPECT" "expected with all PRs applied"

# --- media ---------------------------------------------------------------
# Do not hardcode the canister mode: an ISO built with --canister build|acvp|kat
# lives under a different cache key, and silently reading the prebuilt one
# would verify an artefact the permutation never used.
# The row names its own canister; MC_CANISTER is only the fallback for rows
# written before the column existed.
: "${MC_CANISTER:=prebuilt}"
ISO_LINK="$MC_ISO_CACHE/${ISO_TYPE}-poi${POI}-${CANISTER:-$MC_CANISTER}/photon.iso"
if [ -f "$ISO_LINK" ]; then
    [ "$ISO_TYPE" = minimal ] && mc_oracle_media "$ISO_LINK" "$ISO_TYPE"
else
    mc_check media.iso "-" skip "" "" "no cached ISO at $ISO_LINK"
fi

# --- what the install phase established ----------------------------------
# mc-install observed the guest answer as a booted machine. Prefer that over
# re-deriving it here, where first boot may still be in progress.
MC_INSTALL_RESULT=""
[ -f "$DIR/mc-facts.env" ] && . "$DIR/mc-facts.env"
export MC_INSTALL_RESULT
[ -z "$IP" ] && [ -n "${MC_GUEST_IP:-}" ] && IP="$MC_GUEST_IP"

# --- install phase -------------------------------------------------------
cp -f "$SER" "$HARVEST/serial.log" 2>/dev/null || true
mc_oracle_install "$SER"

# --- guest ---------------------------------------------------------------
# Discover the address rather than assuming it: an interactive install may
# have taken a DHCP lease the kickstart never pinned.
if [ -z "$IP" ]; then
    IP=$("$VMRUN" -T ws getGuestIPAddress "$DIR/$VM.vmx" -wait 2>/dev/null | tr -d '\r' | tail -1)
    case "$IP" in *.*.*.*) ;; *) IP="" ;; esac
fi

if [ -n "$IP" ]; then
    mc_check guest.ip "-" info "" "$IP" ""
    export SSHPASS="$MC_GUEST_PASSWORD"
    guest_run() {
        sshpass -e ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
            -o ConnectTimeout=10 -o BatchMode=no -o LogLevel=ERROR \
            "${SSH_USER}@${IP}" "$@" 2>/dev/null
    }
    if guest_run true; then
        mc_oracle_guest guest_run "$STIG" "$FS"
        mc_oracle_harvest guest_run "$HARVEST"
    else
        mc_check guest.ssh "-" fail "reachable" "unreachable" "no ssh to $IP"
    fi
else
    mc_check guest.ip "-" fail "discovered" "none" "vmrun getGuestIPAddress returned nothing"
fi

mc_result_summary
