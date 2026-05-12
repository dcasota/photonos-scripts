#!/bin/sh
# parity-snapshot.sh — capture parity inputs for the C-side replay workflow.
#
# Phase 8 task 080. Runs at the tail of the PS-side package-report.yml
# workflow, immediately after .prn files are collected to staging. Captures
# the *state* the PS run saw (branch clone SHAs, upstream clone SHAs,
# tarball sha256s) and the .prn outputs PS produced — not the bytes of
# the working tree itself. The C-side workflow (package-report-C.yml)
# uses the manifests to reconstruct an equivalent working tree by
# re-cloning at the recorded SHAs, then diffs its .prn against the
# snapshot's prn-snapshot/.
#
# Usage:
#   parity-snapshot.sh <working-dir> <upstreams-dir> <prn-staging-dir> <out-tar>
#
# Arguments:
#   working-dir       — root containing per-branch Photon clones (<wd>/3.0, <wd>/4.0, ...)
#   upstreams-dir     — root containing per-branch upstream state
#                       (<ud>/<branch>/{clones,SOURCES_NEW,SPECS_NEW})
#   prn-staging-dir   — directory holding .prn files produced by this run
#                       (e.g. /tmp/new-reports as written by the workflow's
#                       Collect-new-reports step)
#   out-tar           — output path for the tar.gz snapshot artifact
#
# Output: writes <out-tar>. Echoes one final line with counts:
#   branch-clones=N  upstream-clones=N  tarballs=N  prn-files=N
#
# Exit codes:
#   0 success
#   1 missing required argument
#   2 working-dir or upstreams-dir not a directory
set -eu

if [ "$#" -ne 4 ]; then
    echo "usage: $0 <working-dir> <upstreams-dir> <prn-staging-dir> <out-tar>" >&2
    exit 1
fi

WORKING_DIR="$1"
UPSTREAMS_DIR="$2"
PRN_STAGING="$3"
OUT_TAR="$4"

if [ ! -d "$WORKING_DIR" ]; then
    echo "::error::parity-snapshot: working-dir not a directory: $WORKING_DIR" >&2
    exit 2
fi
if [ ! -d "$UPSTREAMS_DIR" ]; then
    echo "::warning::parity-snapshot: upstreams-dir not a directory: $UPSTREAMS_DIR (empty manifests)" >&2
fi

stage="$(mktemp -d -t parity-snap.XXXXXX)"
trap 'rm -rf "$stage"' EXIT

mkdir -p "$stage/prn-snapshot"

# ---- 1. Branch-clones manifest -----------------------------------------
# Each <working-dir>/<branch> is a Photon repo clone (the SPECS tree the
# PS script + C binary read from). One row per branch.
{
    for branch_dir in "$WORKING_DIR"/*; do
        [ -d "$branch_dir/.git" ] || continue
        branch="$(basename "$branch_dir")"
        sha="$(git -C "$branch_dir" rev-parse HEAD 2>/dev/null || echo unknown)"
        url="$(git -C "$branch_dir" remote get-url origin 2>/dev/null || echo unknown)"
        printf '%s\t%s\t%s\n' "$branch" "$url" "$sha"
    done
} > "$stage/branch-clones-manifest.tsv"

# ---- 2. Upstream-clones manifest ---------------------------------------
# Per-branch upstream repository clones (used for git-tag detection in
# phase 6c, local fetch in 6d). One row per clone.
{
    for branch_dir in "$UPSTREAMS_DIR"/*; do
        [ -d "$branch_dir/clones" ] || continue
        branch="$(basename "$branch_dir")"
        for clone in "$branch_dir/clones"/*; do
            # A clone may be a bare repo (HEAD file) or a working tree (.git dir).
            if [ -d "$clone/.git" ] || [ -f "$clone/HEAD" ]; then
                sha="$(git -C "$clone" rev-parse HEAD 2>/dev/null || echo unknown)"
                url="$(git -C "$clone" remote get-url origin 2>/dev/null || echo unknown)"
                printf '%s\t%s\t%s\t%s\n' "$branch" "$(basename "$clone")" "$url" "$sha"
            fi
        done
    done
} > "$stage/upstream-clones-manifest.tsv"

# ---- 3. Tarball manifest -----------------------------------------------
# Per-branch downloaded source tarballs in SOURCES_NEW. Records size + sha256
# so the C run can validate it sees byte-identical tarballs when it fetches
# them (Phase 6f col-9 SHA assembly).
{
    for branch_dir in "$UPSTREAMS_DIR"/*; do
        src_new="$branch_dir/SOURCES_NEW"
        [ -d "$src_new" ] || continue
        branch="$(basename "$branch_dir")"
        find "$src_new" -maxdepth 1 -type f -print | while read -r f; do
            size="$(stat -c %s "$f" 2>/dev/null || echo 0)"
            sha="$(sha256sum "$f" 2>/dev/null | awk '{print $1}')"
            printf '%s\t%s\t%s\t%s\n' "$branch" "$(basename "$f")" "$size" "$sha"
        done
    done
} > "$stage/tarball-manifest.tsv"

# ---- 4. PRN snapshot ---------------------------------------------------
# Copy in the .prn files PS produced this run — these are the diff
# target the C run will compare against. Optional .md issue summaries
# are excluded; only .prn matters for parity.
if [ -d "$PRN_STAGING" ]; then
    for f in "$PRN_STAGING"/*.prn; do
        [ -f "$f" ] || continue
        cp "$f" "$stage/prn-snapshot/"
    done
fi

# ---- 5. Run info -------------------------------------------------------
# Captured so the C-side journal row can reference the PS run by id.
cat > "$stage/ps-run-info.json" <<EOF
{
  "run_id":      "${GITHUB_RUN_ID:-local}",
  "run_attempt": "${GITHUB_RUN_ATTEMPT:-1}",
  "github_sha":  "${GITHUB_SHA:-unknown}",
  "github_ref":  "${GITHUB_REF:-unknown}",
  "captured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

# ---- 6. Tar ------------------------------------------------------------
# gzip rather than zstd for portability; manifests + .prn are highly
# compressible text. Expected size << 100 MB.
tar -C "$stage" -czf "$OUT_TAR" .

# ---- 7. Summary line for the workflow log ------------------------------
n_branch=$(wc -l < "$stage/branch-clones-manifest.tsv")
n_upstream=$(wc -l < "$stage/upstream-clones-manifest.tsv")
n_tarball=$(wc -l < "$stage/tarball-manifest.tsv")
n_prn=$(find "$stage/prn-snapshot" -maxdepth 1 -name '*.prn' -type f | wc -l)
size=$(stat -c %s "$OUT_TAR" 2>/dev/null || echo 0)

printf 'parity-snapshot: branch-clones=%d  upstream-clones=%d  tarballs=%d  prn-files=%d  archive-bytes=%d\n' \
    "$n_branch" "$n_upstream" "$n_tarball" "$n_prn" "$size"
