#!/bin/bash
# mc-make-variant-patches.sh - build one patch per installer variant, from the
# PR branches, WITHOUT merging any of them.
#
# The whole point of the harness is to test PRs before they land, so a variant
# that required a merge first would be untestable by definition. Each variant
# is assembled by cherry-picking the PR branches onto a pristine 5.0 in a
# throwaway clone and diffing the result.
#
#   poi-2.8.patch     5.0 + #9 #19 #21 #22 #23 #24   (installer stays 2.8)
#   poi-latest.patch  5.0 + #9 #21 #22 #23 #24 #26   (#26 bumps it to v2.9)
#
# #19 and #26 are alternatives - #19 adds patches to 2.8, #26 moves to 2.9
# where three of them are already upstream - so exactly one appears in each.
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"

: "${MC_PHOTON_REMOTE:=https://github.com/dcasota/photon.git}"
CLONE="$MC_WORK/photon-variants"
mkdir -p "$MC_WORK" "$MC_VARIANT_PATCH_DIR"

if [ ! -d "$CLONE/.git" ]; then
    mc_log "cloning $MC_PHOTON_REMOTE (blobless) -> $CLONE"
    git clone --quiet --filter=blob:none --no-checkout "$MC_PHOTON_REMOTE" "$CLONE" || mc_die "clone failed" 5
fi
cd "$CLONE" || mc_die "cannot enter $CLONE" 5
git fetch -q origin 5.0 fix-selinux-relabel fix/photon-os-installer-2.8-5-interactive-osrelease \
    fix/aide-libgcrypt-versioned-requires fix/systemd-groups-and-stig-variant \
    fix/stig-harden-reachable fix/kernel-shared-canister-config fix/poi-2.9-bump || mc_die "fetch failed" 5

build_variant() {
    local name="$1"; shift
    git checkout -q -B "variant-$name" origin/5.0 || return 1
    local br
    for br in "$@"; do
        # The RANGE, not the tip. A PR branch grows commits over time (PR#9
        # gained the selinux-relabel ordering fix on top of its original
        # commit); cherry-picking only the tip applies a change without the
        # commit it builds on, which conflicts or silently produces a partial
        # variant patch.
        git cherry-pick -x "origin/5.0..origin/$br" >/dev/null 2>&1 || {
            mc_log "  CONFLICT applying $br to variant $name"
            git cherry-pick --abort 2>/dev/null; return 1
        }
    done
    local out="$MC_VARIANT_PATCH_DIR/poi-${name}.patch"
    git diff origin/5.0 "variant-$name" -- SPECS/ > "$out"
    mc_log "  poi-$name: $(grep -c '^+++ ' "$out") files, $(wc -l < "$out") lines"

    # Prove it applies to a pristine tree before anything relies on it.
    local t; t=$(mktemp -d)
    git archive origin/5.0 | tar x -C "$t"
    if ( cd "$t" && patch -p1 --dry-run --forward < "$out" >/dev/null 2>&1 ); then
        mc_log "  poi-$name: applies to pristine 5.0"
    else
        mc_log "  poi-$name: DOES NOT APPLY to pristine 5.0"; rm -rf "$t"; return 1
    fi
    rm -rf "$t"
}

rc=0
mc_log "variant poi-2.8 (installer stays at 2.8, #19)"
build_variant 2.8 fix/photon-os-installer-2.8-5-interactive-osrelease \
    fix/aide-libgcrypt-versioned-requires fix-selinux-relabel \
    fix/systemd-groups-and-stig-variant fix/stig-harden-reachable \
    fix/kernel-shared-canister-config || rc=1

mc_log "variant poi-latest (installer v2.9 via #26, instead of #19)"
build_variant latest fix/poi-2.9-bump \
    fix/aide-libgcrypt-versioned-requires fix-selinux-relabel \
    fix/systemd-groups-and-stig-variant fix/stig-harden-reachable \
    fix/kernel-shared-canister-config || rc=1

exit $rc
