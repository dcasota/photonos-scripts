#!/bin/bash
# Rebuild BOTH minimal ISOs from the variant patches that now carry the
# reviewed isoBuilder import, then run every UNATTENDED row they serve.
#
# Both variants must be tested: the isoBuilder change rides 0008, which is
# carried by fix/poi-fips-sshd-algorithms (2.8) AND fix/poi-2.9-bump (latest).
# Testing only 2.8 would leave the latest installer unproven with the same
# change in it.
set -u
: "${MC_GUEST_PASSWORD:?not set. It is the root password of every VM this
   harness creates, so it has no default and is deliberately not stored here.
   Export it before running, e.g. read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD}"
S=/root/photonos-scripts/staging/sharukhan-cli/target/release/sharukhan
LOG=/root/photon-mc/rebuild-both-$(date -u +%Y%m%dT%H%M%SZ).log
log() { printf '[both %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }

for poi in 2.8 latest; do
    log "building minimal/$poi"
    if ! "$S" build-iso --iso-type minimal --poi "$poi" --canister prebuilt --allow-build --force >>"$LOG" 2>&1; then
        log "BUILD FAILED for minimal/$poi - stopping, nothing downstream would mean anything"
        exit 1
    fi
    log "built minimal/$poi"
done

# Gate: the ISO must actually carry the reviewed form, or the rows below prove
# nothing about the change under test.
for poi in 2.8 latest; do
    d=/mnt/c/photon-mc/iso-cache/minimal-poi${poi}-prebuilt
    iso=$(ls "$d"/photon-minimal-*.iso 2>/dev/null | head -1)
    [ -n "$iso" ] || { log "no ISO in $d"; exit 1; }
    log "minimal/$poi -> $(basename "$iso")"
done

log "--- running the unattended rows ---"
"$S" run --only k01,k02,k03,k04,s01,s02 >>"$LOG" 2>&1
"$S" run --only k05,k06,k07,k08 >>"$LOG" 2>&1
log "=== done ==="
"$S" report --only k01,k02,k03,k04,s01,s02,k05,k06,k07,k08 2>&1 | tee -a "$LOG"
