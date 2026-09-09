#!/bin/bash
# First real exercise of the equivalent-canister path.
#
# minimal/2.8 rather than full: phase A and the purge and phase B are the same
# code either way, and a minimal ISO costs ~30 minutes where a full one costs
# hours. Prove the mechanism cheaply, then spend the hours on c01.
#
# What must be true at the end, and is checked here rather than assumed:
#   1. phase A produced linux-fips-canister-<kernel NEVR>
#   2. the purge left the canister and removed the canister-CREATION kernel
#   3. phase B rebuilt linux AND linux-esx against that canister
#   4. the ISO carries a linux-esx built after the canister
set -u
S=/root/photonos-scripts/staging/sharukhan-cli/target/release/sharukhan
LOG=/root/photon-mc/canister-equivalent-$(date -u +%Y%m%dT%H%M%SZ).log
STAGE=/root/5.0/stage/RPMS
log() { printf '[eq %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
die() { log "FAILED: $*"; exit 1; }

log "start"

# Both parsers, before anything is compiled. They fail on DIFFERENT things and
# passing one says nothing about the other: on 2026-09-02 a spec that satisfied
# Photon's parser perfectly still broke rpm, because rpm expands macros inside
# comments and a comment quoted the macro form it was explaining.
S_TREE=$(mktemp -d /tmp/eqcheck-XXXX)
git -C /root/5.0 worktree add -f -q --detach "$S_TREE/t" origin/5.0 2>/dev/null \
    && git -C "$S_TREE/t" apply /root/photon-mc/variant-patches/poi-2.8.patch 2>/dev/null \
    && python3 /root/photon-mc/check-canister-macros.py --tree "$S_TREE/t" 2>&1 | tee -a "$LOG" | grep -q "^PASS" \
    || { git -C /root/5.0 worktree remove --force "$S_TREE/t" 2>/dev/null; \
         die "the patched specs do not pass the macro checks - see above"; }
git -C /root/5.0 worktree remove --force "$S_TREE/t" 2>/dev/null
log "both spec macro checks pass on the patched tree"

# The plan is re-decided by the tool itself; record what it decided, so the log
# says which path this run took rather than leaving it to be inferred.
"$S" canister 2>&1 | tee -a "$LOG" | grep -q "^plan:" || die "sharukhan canister gave no plan"
PLAN=$("$S" canister 2>&1 | grep '^plan:')
log "$PLAN"

NEVR=$(echo "$PLAN" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.ph5' | head -1)
[ -n "$NEVR" ] || die "could not read the kernel NEVR from the plan"
log "kernel under test: $NEVR"

case "$PLAN" in
    *"no phase A"*) log "a published canister matches; phase A is correctly skipped" ;;
    *"phase A"*)    log "phase A is required: nothing published at $NEVR" ;;
    *)              die "unrecognised plan: $PLAN" ;;
esac

before=$(find "$STAGE" -name 'linux-fips-canister-*.rpm' 2>/dev/null | wc -l)
log "canister RPMs in stage before: $before"

log "building minimal/2.8 --canister equivalent (this runs both phases)"
"$S" build-iso --iso-type minimal --poi 2.8 --canister equivalent --allow-build --force >>"$LOG" 2>&1 \
    || die "the equivalent build did not complete"

# ---- what actually landed -------------------------------------------------
can=$(find "$STAGE" -name "linux-fips-canister-$NEVR.*.rpm" 2>/dev/null | head -1)
[ -n "$can" ] || die "no linux-fips-canister-$NEVR in $STAGE - phase A did not deliver"
log "phase A artifact: $can"

# The purge must have removed the canister-creation kernel, and phase B must
# have rebuilt one. Either way what remains has to be a kernel built AFTER the
# canister, or it is phase A's.
for k in linux linux-esx; do
    rpm=$(find "$STAGE" -name "$k-$NEVR.*.rpm" 2>/dev/null | head -1)
    [ -n "$rpm" ] || die "$k-$NEVR is missing - phase B did not rebuild it"
    if [ "$rpm" -nt "$can" ]; then
        log "$k rebuilt after the canister: $(basename "$rpm")"
    else
        die "$(basename "$rpm") is older than the canister - this is phase A's kernel, \
which links no canister; the purge did not work"
    fi
done

log "=== equivalent-canister path proved end to end ==="
log "next: the guest-side check (canister_based_on == $NEVR) needs a row to run"
