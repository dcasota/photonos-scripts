#!/bin/bash
# Pass 2 of the two-pass protocol.
#
#   pass 1  change it locally, test it locally, push it to the dcasota PR
#   pass 2  THROW THE LOCAL STATE AWAY, take everything back from the fork,
#           rebuild, and run every unattended row
#
# Pass 1 proves the change is right. Pass 2 proves the change that is PUBLISHED
# is the one that was proven - which is a different claim, and the one that
# matters when the next step is opening a PR against vmware. A local working
# tree can make a test pass for reasons the fork does not carry.
set -u
: "${MC_GUEST_PASSWORD:?not set. It is the root password of every VM this
   harness creates, so it has no default and is deliberately not stored here.
   Export it before running, e.g. read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD}"
S=/root/photonos-scripts/staging/sharukhan-cli/target/release/sharukhan
LOG=/root/photon-mc/coverage-plan-$(date -u +%Y%m%dT%H%M%SZ).log
log() { printf '[plan %s] %s\n' "$(date -u +%H:%M:%SZ)" "$*" | tee -a "$LOG"; }
die() { log "$*"; exit 1; }

log "waiting for rebuild-both.sh"
while pgrep -f 'bash /root/photon-mc/rebuild-both\.sh' >/dev/null; do sleep 60; done
log "rebuild finished"
grep -q '=== done ===' /root/photon-mc/rebuild-both-*.log 2>/dev/null \
    || die "REFUSING: the rebuild never reached '=== done ==='. Acting on a failed rebuild tests nothing."

# ---- local cleanup: nothing local may leak into pass 2 --------------------
cd /root/5.0 || die "no photon tree"
git switch -q 5.0 || die "cannot switch to 5.0"
git fetch -q origin 5.0
git reset -q --hard origin/5.0
git clean -fdq SPECS
log "local tree discarded and reset to origin/5.0 ($(git rev-parse --short HEAD))"

# ---- mirror every POI PR commit into its spec patch, BOTH variants --------
# Regenerated from the PUBLISHED fork branch, never from a local checkout.
POI=/root/photon-os-installer
git -C "$POI" fetch -q dcasota || die "cannot fetch the fork"
mirror() { # <spec-patch-name> <dcasota-branch>
    git -C "$POI" format-patch --stdout "dcasota/$2~1..dcasota/$2" > /tmp/mirror-raw.patch 2>/dev/null \
        || { log "cannot format-patch dcasota/$2"; return 1; }
    python3 - "$1" <<'PY'
import sys
lines = open("/tmp/mirror-raw.patch").read().split("\n")
lines[0] = "From 0000000000000000000000000000000000000000 Mon Sep 17 00:00:00 2001"
for i, l in enumerate(lines[:6]):
    if l.startswith("Date: "):
        lines[i] = "Date: Mon, 31 Aug 2026 00:00:00 +0000"
s = "\n".join(lines).split("\n-- \n")[0].rstrip("\n") + "\n"
open("/tmp/mirror-final.patch", "w").write(s)
PY
    cp /tmp/mirror-final.patch "SPECS/photon-os-installer/$1"
}
for b in fix/poi-fips-sshd-algorithms fix/poi-2.9-bump; do
    git switch -q "$b" 2>/dev/null || { log "cannot switch to $b"; continue; }
    [ "$(git branch --show-current)" = "$b" ] || { log "REFUSING $b: switch did not land"; continue; }
    git reset -q --hard "origin/$b"
    mirror 0006-stig-drop-redundant-packages.patch                        fix/stig-drop-redundant-packages
    mirror 0007-installer-seed-locale.conf-before-package-install.patch   fix/seed-locale-conf-before-pkg-install
    mirror 0008-isoBuilder-put-installer-requestable-packages-on-media.patch fix/isobuilder-installer-pkgs-on-media
    if git diff --quiet -- SPECS/photon-os-installer; then
        log "$b: spec copies already match the fork"
    else
        git add SPECS/photon-os-installer
        git -c user.name="Daniel Casota" -c user.email="dcasota@gmail.com" commit -q -m \
"photon-os-installer: resync the spec patch copies with the fork

Regenerated 0006, 0007 and 0008 from the published branches on
github.com/dcasota/photon-os-installer, so the copies carried here are the
commits the PRs actually contain. A copy that lags means the matrix proves the
old change while looking exactly like it proved the new one.

Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01JW73JTCUGRcaNTUEQcAMtf"
        git push -q --force-with-lease origin "$b:$b" && log "$b -> $(git rev-parse --short HEAD), pushed"
    fi
done
git switch -q 5.0

# ---- the gate ------------------------------------------------------------
"$S" mirrors 2>&1 | tee -a "$LOG" | grep -q 'every spec copy matches' \
    || die "GATE FAILED: a spec copy is still behind the fork. A row built now proves the old change."
log "gate passed: every spec copy matches its published branch"

# ---- rebuild from published refs, then every unattended row --------------
"$S" variant-patches >>"$LOG" 2>&1 || die "variant-patches failed"
for v in 2.8 latest; do
    git apply --check "/root/photon-mc/variant-patches/poi-$v.patch" || die "poi-$v does not apply to pristine 5.0"
done
log "both variant patches apply to pristine 5.0"
for poi in 2.8 latest; do
    log "rebuilding minimal/$poi from published refs"
    "$S" build-iso --iso-type minimal --poi "$poi" --canister prebuilt --allow-build --force >>"$LOG" 2>&1 \
        || die "build minimal/$poi FAILED - rows behind it would prove nothing"
done
log "running unattended rows, 2.8"
"$S" run --only k01,k02,k03,k04,s01,s02 >>"$LOG" 2>&1
log "running unattended rows, latest"
"$S" run --only k05,k06,k07,k08 >>"$LOG" 2>&1
log "=== verdicts ==="
"$S" report --only k01,k02,k03,k04,s01,s02,k05,k06,k07,k08 2>&1 | tee -a "$LOG"
log "=== pass 2 complete. Replicating to vmware is NOT automatic. ==="
