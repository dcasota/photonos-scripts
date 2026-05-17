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
#                                                (skipped unless PARITY_PRECLONE_UPSTREAMS=1)
#
# Branch clones are REQUIRED: a failed branch clone aborts.
# Upstream clones are SKIPPED by default — there are typically thousands
# per snapshot and pre-cloning them all serially exceeds practical
# workflow timeouts. The C binary's phase 6d local-clone fetch
# (pr_clone_ensure) re-creates each clone on first use, so correctness
# is preserved.
#
# Opt-in eager pre-cloning for byte-stable SHA-pinned parity:
#   PARITY_PRECLONE_UPSTREAMS=1    enable pre-cloning
#   PARITY_PRECLONE_JOBS=N         parallel workers (default 8, max 32)
#
# Both knobs are best-effort: a failed clone is logged as a warning
# but does not abort. The C binary still re-clones what's missing.
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

# ---- Upstream clones ---------------------------------------------------
# Default: SKIP. The C binary re-clones what it needs on first use, so
# correctness is preserved. Opt in for SHA-pinned byte-stable parity.
UP_MAN="$SNAP/upstream-clones-manifest.tsv"
n_upstream=0
n_upstream_failed=0
n_upstream_total=0
if [ -s "$UP_MAN" ]; then
    n_upstream_total=$(wc -l < "$UP_MAN")
fi

if [ "${PARITY_PRECLONE_UPSTREAMS:-0}" != "1" ]; then
    echo "  upstream-preclone: SKIPPED ($n_upstream_total entries in manifest; C binary will clone on-demand)"
    echo "  (set PARITY_PRECLONE_UPSTREAMS=1 to enable eager SHA-pinned reconstruction)"
else
    JOBS="${PARITY_PRECLONE_JOBS:-8}"
    case "$JOBS" in
        ''|*[!0-9]*) JOBS=8 ;;
        0)           JOBS=1 ;;
    esac
    if [ "$JOBS" -gt 32 ]; then JOBS=32; fi
    echo "  upstream-preclone: ENABLED ($n_upstream_total entries, $JOBS parallel workers)"

    work_dir=$(mktemp -d -t parity-recon.XXXXXX)
    trap 'rm -rf "$work_dir"' EXIT
    log_file="$work_dir/log"
    : > "$log_file"

    # Bounded-concurrency batching: launch up to $JOBS background
    # workers, then `wait` for the whole batch before starting the
    # next. Simpler than a fifo semaphore; tail latency per batch is
    # bounded by the slowest clone in that batch, which is acceptable
    # for snapshot-replay use.
    running=0
    while IFS="$(printf '\t')" read -r branch sub url sha; do
        [ -n "$branch" ] && [ -n "$sub" ] && [ -n "$url" ] || continue
        (
            dest="$UPSTREAMS/$branch/clones/$sub"
            mkdir -p "$(dirname "$dest")"
            if [ ! -d "$dest/.git" ] && [ ! -f "$dest/HEAD" ]; then
                if ! git clone --quiet "$url" "$dest" 2>/dev/null; then
                    echo "FAILED $branch/$sub $url" >> "$log_file"
                    echo "::warning::reconstruct: upstream clone failed for $url" >&2
                    exit 0
                fi
            fi
            git -C "$dest" fetch --quiet origin 2>/dev/null || true
            if [ "${sha:-unknown}" != "unknown" ]; then
                git -C "$dest" -c advice.detachedHead=false checkout --quiet "$sha" 2>/dev/null || true
            fi
            echo "DONE $branch/$sub" >> "$log_file"
        ) &
        running=$((running + 1))
        if [ "$running" -ge "$JOBS" ]; then
            wait
            running=0
        fi
    done < "$UP_MAN"
    wait  # drain the final partial batch

    # awk counters tolerate set -eu without grep-exit-1 noise.
    n_upstream=$(awk '/^DONE /   {c++} END {print c+0}' "$log_file")
    n_upstream_failed=$(awk '/^FAILED / {c++} END {print c+0}' "$log_file")
fi

printf 'parity-reconstruct: branch-clones=%d  upstream-clones=%d  upstream-failed=%d  upstream-total=%d\n' \
    "$n_branch" "$n_upstream" "$n_upstream_failed" "$n_upstream_total"
