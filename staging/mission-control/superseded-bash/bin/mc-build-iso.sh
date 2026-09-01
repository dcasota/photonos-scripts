#!/bin/bash
# mc-build-iso.sh - resolve one build-axis tuple to an ISO, building if needed.
#
# The build-time axes are ISO type and installer version, and nothing else.
# Everything the matrix varies at install time (STIG, filesystem, kickstart vs
# UI) is injected per VM, so 34 permutations need only 4 ISOs.
#
# usage: mc-build-iso.sh --iso-type minimal|full --poi 2.8|latest [--canister prebuilt|build|acvp|kat] [--force]
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

ISO_TYPE=minimal POI=2.8 CANISTER=prebuilt FORCE=0
while [ $# -gt 0 ]; do
    case "$1" in
        --iso-type) ISO_TYPE="$2"; shift 2 ;;
        --poi) POI="$2"; shift 2 ;;
        --canister) CANISTER="$2"; shift 2 ;;
        --force) FORCE=1; shift ;;
        *) mc_die "unknown arg: $1" 64 ;;
    esac
done

case "$ISO_TYPE" in minimal) IMG=minimal-iso ;; full) IMG=iso ;; *) mc_die "bad --iso-type" 64 ;; esac
KEY="${ISO_TYPE}-poi${POI}-${CANISTER}"
DEST="$MC_ISO_CACHE/$KEY"
mkdir -p "$DEST" "$MC_BUILD_LOG_DIR"

if [ "$FORCE" -eq 0 ] && [ -f "$DEST/photon.iso" ]; then
    mc_log "cache hit: $KEY -> $DEST/photon.iso"
    printf '%s\n' "$DEST/photon.iso"; exit 0
fi

# --- the stale-RPM landmine ----------------------------------------------
# tdnf picks the highest release it can see, so a months-old
# photon-os-installer left in stage/RPMS silently wins and lands on the ISO.
# A test run that exercises a stale installer is worse than no test run: it
# reports a verdict for code nobody is shipping.
STAGE_RPMS="$PHOTON_TREE/stage/RPMS"
if [ -d "$STAGE_RPMS" ]; then
    n=$(find "$STAGE_RPMS" -name 'photon-os-installer-*.rpm' 2>/dev/null | wc -l)
    if [ "$n" -gt 0 ]; then
        mc_log "purging $n cached photon-os-installer RPM(s) so the build cannot pick a stale one"
        find "$STAGE_RPMS" -name 'photon-os-installer-*.rpm' -delete
    fi
fi

# --- installer version, without merging anything -------------------------
# The point of this harness is to test PRs BEFORE they merge, so requiring a
# merge to reach the poi=latest rows would invert that. Instead each variant
# gets its own patch: poi=2.8 uses the downstream set as-is, poi=latest uses
# the same set with dcasota/photon#26 (installer v2.9) substituted for the
# 2.8-only installer PR. Both are generated from the PR branches and both are
# verified to apply to a pristine 5.0 before use.
#
# runPh5_normal.sh resolves its patch relative to its OWN directory, so the
# variant is selected by staging a script directory rather than by editing the
# build script. SCRIPT_DIR is used for nothing else (runPh5_normal.sh:75,163).
VARIANT_PATCH="$MC_VARIANT_PATCH_DIR/poi-${POI}.patch"
[ -f "$VARIANT_PATCH" ] || mc_die "no variant patch at $VARIANT_PATCH - run mc-make-variant-patches.sh" 3

STAGE_DIR="$MC_WORK/scriptdir/$KEY"
mkdir -p "$STAGE_DIR/photonos-patches"
cp "$PHOTON_SCRIPTS/runPh5_normal.sh" "$STAGE_DIR/runPh5_normal.sh"
cp "$VARIANT_PATCH" "$STAGE_DIR/photonos-patches/downstream-fixes.patch"
mc_log "staged build dir $STAGE_DIR with poi-${POI}.patch ($(grep -c '^+++ ' "$VARIANT_PATCH") files)"

SPEC="$PHOTON_TREE/SPECS/photon-os-installer/photon-os-installer.spec"
have=$(awk '/^Version:/{print $2; exit}' "$SPEC" 2>/dev/null); [ -n "$have" ] || have='?'
mc_log "installer version in the pristine tree: $have (the variant patch sets the one under test)"

# Each variant patch must land on a PRISTINE SPECS tree. runPh5 applies it on
# top of whatever is already there, so one variant's files survive into the
# next: after a poi-2.8 build, 0003/0004/0005 were still on disk while the
# poi-latest spec no longer referenced them, and Photon's own spec check
# failed the build with "List of unused files". Everything removed here is
# reproduced by the variant patch, so the reset is idempotent.
git -C "$PHOTON_TREE" checkout -- SPECS 2>/dev/null || true
git -C "$PHOTON_TREE" clean -fdq SPECS 2>/dev/null || true
mc_log "SPECS reset to pristine 5.0 before applying poi-${POI}.patch"

BUILD_LOG="$MC_BUILD_LOG_DIR/${KEY}-$(date -u +%Y%m%dT%H%M%SZ).log"
mc_log "building $IMG (canister=$CANISTER) -> $BUILD_LOG"
mc_log "this takes hours; the run script polls rather than blocking"

sh "$STAGE_DIR/runPh5_normal.sh" /root common 5.0 "$DEST" "$IMG" "$CANISTER" \
    > "$BUILD_LOG" 2>&1
rc=$?
[ $rc -eq 0 ] || mc_die "build failed (rc=$rc), see $BUILD_LOG" "$rc"

iso=$(find "$DEST" -maxdepth 1 -name '*.iso' -newer "$BUILD_LOG" 2>/dev/null | head -1)
[ -n "$iso" ] || iso=$(find "$DEST" -maxdepth 1 -name '*.iso' | head -1)
[ -n "$iso" ] || mc_die "build reported success but produced no ISO in $DEST" 4
[ "$iso" = "$DEST/photon.iso" ] || ln -sf "$(basename "$iso")" "$DEST/photon.iso"

# --- assert what actually shipped ----------------------------------------
poi_on_media=$(xorriso -osirrox on -indev "$iso" -find /RPMS -name 'photon-os-installer-*.rpm' 2>/dev/null \
               | sed 's|.*/||' | tr -d "'" | head -1)
mc_log "installer on the produced media: ${poi_on_media:-ABSENT}"
printf '%s\n' "$poi_on_media" > "$DEST/poi-nevr.txt"
sha256sum "$iso" | awk '{print $1}' > "$DEST/photon.iso.sha256"
mc_log "cached: $DEST/photon.iso"
printf '%s\n' "$DEST/photon.iso"
