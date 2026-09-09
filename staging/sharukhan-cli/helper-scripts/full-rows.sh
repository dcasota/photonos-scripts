#!/bin/bash
# The full-ISO half of the matrix, plus the canister row, on the CURRENT
# variant patch.
#
# Why now: the variant patch changed under all of them. It went from linux
# Release 12 to 13 and gained the two rebased canister patch files
# (1004/1010), because a canister=build row was applying 1004 against a
# 6.12.103 that no longer wraps !digest_size in WARN_ON() and %prep died at
# --fuzz=0. Every cached ISO predates that, so k09-k16 have never run against
# what is now under test and c01 has never produced a verdict at all.
#
# Same discipline as pass 2: a refusal is fatal, the expected installer NEVR
# is read out of the variant patch and checked against the produced media, the
# settle window is waited out rather than weakened, and every row must leave
# evidence newer than this script's start or the run fails instead of
# reporting.
set -u
: "${MC_GUEST_PASSWORD:?not set. It is the root password of every VM this
   harness creates, so it has no default and is deliberately not stored here.
   Export it before running, e.g. read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD}"
S=/root/photonos-scripts/staging/sharukhan-cli/target/release/sharukhan
LOG=/root/photon-mc/full-rows-$(date -u +%Y%m%dT%H%M%SZ).log
EPOCH=$(date +%s)
log() { printf '[full %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
die() { log "FAILED: $*"; exit 1; }

log "start (epoch $EPOCH); evidence older than this instant will not be accepted"

cd /root/5.0 || die "no photon tree"
git switch -q 5.0 || die "cannot switch to 5.0"
[ "$(git branch --show-current)" = "5.0" ] || die "switch to 5.0 did not land"
git fetch -q origin 5.0
git reset -q --hard origin/5.0
git clean -fdq SPECS
log "local tree reset to origin/5.0 ($(git rev-parse --short HEAD))"

"$S" mirrors 2>&1 | tee -a "$LOG" | grep -q 'every spec copy matches' \
    || die "a spec copy is behind the fork"
log "gate passed: every spec copy matches its published branch"

"$S" variant-patches >>"$LOG" 2>&1 || die "variant-patches"
for v in 2.8 latest; do
    git apply --check "/root/photon-mc/variant-patches/poi-$v.patch" \
        || die "poi-$v does not apply to pristine 5.0"
done
log "both variant patches apply to pristine 5.0"

# The canister fix must actually be in the patch we are about to build with.
# It is the reason this run exists; building without it would repeat c01.
for v in 2.8 latest; do
    grep -q '1004-Move-__bug_table-section-to-fips_canister_wrapper.patch' \
        "/root/photon-mc/variant-patches/poi-$v.patch" \
        || die "poi-$v does not carry the rebased canister patches - c01 would fail again"
done
log "both variant patches carry the rebased canister series"

# Photon's SpecParser._isDefinition() matches only a line that STARTS with
# %define or %global, so "%{!?name: %global name value}" is invisible to it and
# the macro never reaches self.defs. rpm expands it fine, so the spec looks
# correct to rpmspec and to %prep - the damage shows up only where build.py
# itself substitutes, and then it asks tdnf for a package literally called
# "linux-fips-canister-%{fips_canister_version}". That cost a 2h20m build on
# 2026-09-02.
#
# The guard form is NOT fatal by itself: STIG_HARDEN has used it across every
# green build here, because rpm is the only thing that reads it. It is fatal
# only when the guarded macro is referenced from a line build.py parses. So
# flag that pairing, not the form.
for v in 2.8 latest; do
    P="/root/photon-mc/variant-patches/poi-$v.patch"
    for m in $(grep -hoE '%\{!\?[A-Za-z_][A-Za-z0-9_]*: *%(define|global) [A-Za-z_][A-Za-z0-9_]*' "$P" \
               | awk '{print $NF}' | sort -u); do
        if grep -qE "^\+.*(ExtraBuildRequires[A-Za-z]*|BuildRequires:|^\+Requires:|Version:|Release:).*%\{$m\}" "$P"; then
            die "poi-$v guards %$m with %{!?...}, but build.py substitutes it in a dependency line - it will stay literal"
        fi
    done
done
log "no parser-invisible macro guards in either variant patch"

want() {
    awk '/^\+\+\+ .*photon-os-installer\/photon-os-installer\.spec/,/^diff /' \
        "/root/photon-mc/variant-patches/poi-$1.patch" \
    | awk '/^[+ ]Version:/{v=$NF} /^[+ ]Release:/{r=$NF} END{sub(/%.*/,"",r); print v"-"r}'
}

build() { # <poi> <canister> <label>
    local poi=$1 can=$2 w
    w=$(want "$poi")
    log "building full/$poi canister=$can (media must carry photon-os-installer-$w)"
    "$S" build-iso --iso-type full --poi "$poi" --canister "$can" --allow-build --force >>"$LOG" 2>&1 \
        || die "build full/$poi/$can - rows behind it would prove nothing"
    local got
    got=$(grep -a 'installer on the produced media' "$LOG" | tail -1 | sed 's/.*media: //')
    case "$got" in
        photon-os-installer-$w.*) log "media check ok: $got" ;;
        *) die "full/$poi/$can media carries '$got' but the patch says $w" ;;
    esac
    log "waiting out the 300s ISO settle window"
    sleep 320
}

rows() { # <selection> <description>
    log "running rows: $2"
    "$S" run --only "$1" >>"$LOG" 2>&1 || die "the rows $1 did not run"
}

# ---- full / 2.8 -----------------------------------------------------------
build 2.8 prebuilt
rows k09,k10,k11,k12 "full/2.8 (k09-k12)"

# ---- full / latest --------------------------------------------------------
build latest prebuilt
rows k13,k14,k15,k16 "full/latest (k13-k16)"

# ---- the canister row -----------------------------------------------------
# Its own ISO: canister is a build axis, so c01 must not reuse the prebuilt
# image. This is the long one - the full ISO is ~700 packages and the canister
# is built from source.
build 2.8 build
rows c01 "canister (c01)"

# ---- every verdict must come from THIS run --------------------------------
stale=""
for r in k09 k10 k11 k12 k13 k14 k15 k16 c01; do
    f=/root/photon-mc/results/$r/checks-latest.jsonl
    [ -e "$f" ] || { stale="$stale $r(missing)"; continue; }
    m=$(stat -Lc %Y "$f")
    [ "$m" -gt "$EPOCH" ] || stale="$stale $r($(date -u -d @"$m" +%H:%M:%SZ))"
done
[ -z "$stale" ] || die "these rows carry evidence from BEFORE this run started:$stale"
log "all 9 rows produced fresh evidence"

log "=== verdicts ==="
"$S" report --only k09,k10,k11,k12,k13,k14,k15,k16,c01 2>&1 | tee -a "$LOG"
"$S" ingest 2>&1 | tee -a "$LOG"
log "=== full-ISO + canister run complete ==="
