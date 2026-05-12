#!/bin/sh
# parity-reconstruct.sh — rebuild a working tree from a parity snapshot's
# manifests, for the C-side replay workflow.
#
# Phase 8 task 081.
#
# Reads:
#   <snapshot>/branch-clones-manifest.tsv     (3-col TSV: branch, url, sha)
#   <snapshot>/upstream-clones-manifest.tsv   (4-col TSV: branch, sub, url, sha)
#
# Restores:
#   <out-working-dir>/<branch>/              — Photon branch clone @ SHA
#   <out-upstreams-dir>/<branch>/clones/<sub>/ — upstream repo clone @ SHA
#
# Upstream clones are best-effort: a failed clone is logged as a warning
# but does not abort the script. The C binary's phase 6d local-clone
# fetch will re-create any missing clone on first use.
#
# Branch clones are required: a failed branch clone aborts.
#
# Usage:
#   parity-reconstruct.sh <snapshot-dir> <out-working-dir> <out-upstreams-dir>
set -eu

if [ "$#" -ne 3 ]; then
    echo "usage: $0 <snapshot-dir> <out-working-dir> <out-upstreams-dir>" >&2
    exit 1
fi

SNAP="$1"
WDIR="$2"
UPSTREAMS="$3"

if [ ! -d "$SNAP" ]; then
    echo "::error::parity-reconstruct: snapshot dir does not exist: $SNAP" >&2
    exit 1
fi

mkdir -p "$WDIR" "$UPSTREAMS"

# ---- Branch clones (required) ------------------------------------------
BRANCH_MAN="$SNAP/branch-clones-manifest.tsv"
n_branch=0
if [ -s "$BRANCH_MAN" ]; then
    while IFS="$(printf '\t')" read -r branch url sha; do
        # Skip empty rows.
        [ -n "$branch" ] && [ -n "$url" ] && [ -n "$sha" ] || continue
        dest="$WDIR/$branch"
        if [ ! -d "$dest/.git" ]; then
            echo "  clone $url -> $dest"
            git clone --quiet "$url" "$dest"
        else
            echo "  fetch $branch (cached)"
            git -C "$dest" fetch --quiet origin || true
        fi
        # Try to check out the recorded SHA. If the SHA isn't reachable
        # (e.g. dangling commit on PS side), fetch it explicitly.
        if ! git -C "$dest" rev-parse --verify --quiet "$sha^{commit}" >/dev/null; then
            git -C "$dest" fetch --quiet origin "$sha" 2>/dev/null || {
                echo "::error::reconstruct: branch $branch SHA $sha not fetchable from $url" >&2
                exit 1
            }
        fi
        git -C "$dest" -c advice.detachedHead=false checkout --quiet "$sha"
        n_branch=$((n_branch + 1))
    done < "$BRANCH_MAN"
else
    echo "::error::reconstruct: branch-clones-manifest is empty — cannot reconstruct" >&2
    exit 1
fi

# ---- Upstream clones (best-effort) -------------------------------------
UP_MAN="$SNAP/upstream-clones-manifest.tsv"
n_upstream=0
n_upstream_failed=0
if [ -s "$UP_MAN" ]; then
    while IFS="$(printf '\t')" read -r branch sub url sha; do
        [ -n "$branch" ] && [ -n "$sub" ] && [ -n "$url" ] || continue
        dest="$UPSTREAMS/$branch/clones/$sub"
        mkdir -p "$(dirname "$dest")"
        if [ ! -d "$dest/.git" ] && [ ! -f "$dest/HEAD" ]; then
            if git clone --quiet "$url" "$dest" 2>/dev/null; then
                :
            else
                echo "::warning::reconstruct: upstream clone failed for $url" >&2
                n_upstream_failed=$((n_upstream_failed + 1))
                continue
            fi
        fi
        # Best-effort fetch + checkout at recorded SHA; tolerate failure.
        git -C "$dest" fetch --quiet origin 2>/dev/null || true
        if [ "$sha" != "unknown" ] && [ -n "$sha" ]; then
            git -C "$dest" -c advice.detachedHead=false checkout --quiet "$sha" 2>/dev/null || true
        fi
        n_upstream=$((n_upstream + 1))
    done < "$UP_MAN"
fi

printf 'parity-reconstruct: branch-clones=%d  upstream-clones=%d  upstream-failed=%d\n' \
    "$n_branch" "$n_upstream" "$n_upstream_failed"
