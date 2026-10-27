#!/bin/bash
# Pass 2, second attempt.
#
# The first attempt (coverage-plan-20260901T195253Z.log) reported "pass 2
# complete" having run zero rows. Three things were wrong, and they compounded:
#
#   1. build-iso's stale-installer purge read stage/RPMS flat, but rpmbuild
#      files under stage/RPMS/x86_64/. The purge matched nothing, so the 2.8
#      build inherited the 2.9-3 installer from the preceding latest build and
#      put it on the media. Fixed in build.rs (find_files_rec) + a test.
#   2. `run` was invoked without `|| die`. Both groups were REFUSED - 2.8 on the
#      wrong installer, latest on the 300s settle guard - and the script carried
#      on regardless.
#   3. `report` then printed pass-1 evidence under a "pass 2 complete" banner.
#      A report that cannot tell you WHICH run it is describing is not evidence.
#
# So this run refuses to draw a conclusion it has not earned: every row must
# produce evidence newer than the moment pass 2 started, or the whole thing
# fails loudly.
set -u
: "${MC_GUEST_PASSWORD:?not set. It is the root password of every VM this
   harness creates, so it has no default and is deliberately not stored here.
   Export it before running, e.g. read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD}"
S=/root/photonos-scripts/staging/sharukhan-cli/target/release/sharukhan
LOG=/root/photon-mc/pass2-$(date -u +%Y%m%dT%H%M%SZ).log
EPOCH=$(date +%s)
log() { printf '[pass2 %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
die() { log "FAILED: $*"; exit 1; }

log "start (epoch $EPOCH); evidence older than this instant will not be accepted"

# ---- the gate, re-checked -------------------------------------------------
# The branches were pushed and verified by the first attempt; re-check rather
# than assume, since that attempt is the reason we are here.
cd /root/5.0 || die "no photon tree"
git switch -q 5.0 || die "cannot switch to 5.0"
[ "$(git branch --show-current)" = "5.0" ] || die "switch to 5.0 did not land"
git fetch -q origin 5.0
git reset -q --hard origin/5.0
git clean -fdq SPECS
log "local tree reset to origin/5.0 ($(git rev-parse --short HEAD))"

"$S" mirrors 2>&1 | tee -a "$LOG" | grep -q 'every spec copy matches' \
    || die "a spec copy is behind the fork; a row built now would prove the old change"
log "gate passed: every spec copy matches its published branch"

"$S" variant-patches >>"$LOG" 2>&1 || die "variant-patches"
for v in 2.8 latest; do
    git apply --check "/root/photon-mc/variant-patches/poi-$v.patch" \
        || die "poi-$v does not apply to pristine 5.0"
done
log "both variant patches apply to pristine 5.0"

# What each variant MUST end up with on the media. Read from the patch rather
# than hardcoded, so a release bump cannot silently desynchronise this check
# from the thing it is checking.
want() {
    awk '/^\+\+\+ .*photon-os-installer\/photon-os-installer\.spec/,/^diff /' \
        "/root/photon-mc/variant-patches/poi-$1.patch" \
    | awk '/^[+ ]Version:/{v=$NF} /^[+ ]Release:/{r=$NF} END{sub(/%.*/,"",r); print v"-"r}'
}

for poi in 2.8 latest; do
    w=$(want "$poi")
    log "rebuilding minimal/$poi from published refs (media must carry photon-os-installer-$w)"
    "$S" build-iso --iso-type minimal --poi "$poi" --canister prebuilt --allow-build --force >>"$LOG" 2>&1 \
        || die "build minimal/$poi - rows behind it would prove nothing"
    got=$(grep -a 'installer on the produced media' "$LOG" | tail -1 | sed 's/.*media: //')
    case "$got" in
        photon-os-installer-$w.*) log "media check ok: $got" ;;
        *) die "minimal/$poi media carries '$got' but the patch says $w - this is defect 1 again" ;;
    esac
done

# ---- settle ---------------------------------------------------------------
# VMware cannot reliably open an ISO that is still being flushed (finding #29);
# the guard wants 300s and the first attempt gave it 243. Wait it out here
# rather than weakening the guard - the guard was right.
log "waiting out the 300s ISO settle window before touching VMware"
sleep 320

# ---- rows -----------------------------------------------------------------
log "running unattended rows, 2.8"
"$S" run --only k01,k02,k03,k04,s01,s02 >>"$LOG" 2>&1 || die "the 2.8 rows did not run"
log "running unattended rows, latest"
"$S" run --only k05,k06,k07,k08 >>"$LOG" 2>&1 || die "the latest rows did not run"

# ---- every verdict must come from THIS pass -------------------------------
stale=""
for r in k01 k02 k03 k04 s01 s02 k05 k06 k07 k08; do
    f=/root/photon-mc/results/$r/checks-latest.jsonl
    [ -e "$f" ] || { stale="$stale $r(missing)"; continue; }
    m=$(stat -Lc %Y "$f")
    [ "$m" -gt "$EPOCH" ] || stale="$stale $r($(date -u -d @"$m" +%H:%M:%SZ))"
done
[ -z "$stale" ] || die "these rows carry evidence from BEFORE pass 2 started:$stale"
log "all 10 rows produced fresh evidence"

log "=== verdicts ==="
"$S" report --only k01,k02,k03,k04,s01,s02,k05,k06,k07,k08 2>&1 | tee -a "$LOG"
"$S" ingest 2>&1 | tee -a "$LOG"
log "=== pass 2 complete. Replicating to vmware is NOT automatic. ==="
