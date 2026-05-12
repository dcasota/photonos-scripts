#!/bin/sh
# spec-hooks-drift-check.sh — compare PS-side hooks vs C-side hooks.
#
# Reads:
#   - tools/extract-spec-hooks.sh output (PS-side blocks)
#   - the SPEC: annotations in src/hooks/*.c (C-side ports)
#
# Reports two classes of drift:
#   1. WARNING (PS-only): hook block exists in PS but no C port yet.
#      During Phase 3b-6 this is expected (96 specs await porting).
#      Phase 7+ flips this to an error.
#   2. ERROR (C-only): hook .c file exists with no PS counterpart.
#      Indicates the upstream removed the override or the C author
#      invented one. Always a hard error — fix the C side.
#
# Exit code:
#   0 = no drift, or only PS-only warnings within the configured budget
#   1 = C-only orphans found
#   2 = bad arguments
#
# The Phase-7 flip is controlled by the env var
#   PR_HOOKS_PS_ONLY_FATAL=1
# Set it from CMakeLists when the project reaches Phase 7.
#
# Usage:
#   spec-hooks-drift-check.sh <source-dir>
#     where <source-dir> contains tools/, src/hooks/ and ../photonos-package-report.ps1

set -eu

# Force C locale globally so the sort orderings used by `sort` and `comm`
# agree byte-for-byte regardless of the maintainer's $LANG.
LC_ALL=C
export LC_ALL

if [ $# -ne 1 ]; then
    echo "usage: $0 <source-dir>" >&2
    exit 2
fi
SRC=$1
PS_PATH="$SRC/../photonos-package-report.ps1"
HOOKS_DIR="$SRC/src/hooks"
EXTRACT="$SRC/tools/extract-spec-hooks.sh"

if [ ! -r "$PS_PATH" ]; then
    echo "$0: cannot read $PS_PATH" >&2
    exit 2
fi

ps_specs=$(mktemp)
c_specs=$(mktemp)
trap 'rm -f "$ps_specs" "$c_specs"' EXIT INT TERM

# PS side: unique spec basenames from extractor.
"$EXTRACT" "$PS_PATH" | awk -F '\t' '{ print $1 }' | LC_ALL=C sort -u > "$ps_specs"

# C side: SPEC: annotations from each hook file.
for f in "$HOOKS_DIR"/*.c; do
    [ -e "$f" ] || continue
    awk '
        /SPEC:[ \t]*[^* ]+\.spec/ {
            if (match($0, /SPEC:[ \t]*[^* ]+\.spec/)) {
                tok = substr($0, RSTART + 5, RLENGTH - 5)
                sub(/^[ \t]+/, "", tok)
                print tok
                exit
            }
        }
    ' "$f"
done | LC_ALL=C sort -u > "$c_specs"

# Diff via comm: -23 = lines only in $1, -13 = lines only in $2
ps_only=$(comm -23 "$ps_specs" "$c_specs")
c_only=$(comm -13  "$ps_specs" "$c_specs")

n_ps_only=0
n_c_only=0
[ -n "$ps_only" ] && n_ps_only=$(printf '%s\n' "$ps_only" | wc -l)
[ -n "$c_only"  ] && n_c_only=$(printf '%s\n' "$c_only"  | wc -l)
n_ps_total=$(wc -l < "$ps_specs")
n_c_total=$(wc -l < "$c_specs")

echo "spec-hooks-drift: PS=$n_ps_total  C=$n_c_total  PS-only=$n_ps_only  C-only=$n_c_only"

if [ "$n_c_only" -gt 0 ]; then
    echo "ERROR: C-only hook files with no PS counterpart:" >&2
    printf '%s\n' "$c_only" | sed 's/^/  /' >&2
    exit 1
fi

if [ "$n_ps_only" -gt 0 ]; then
    echo "WARNING: $n_ps_only PS hooks awaiting C port:" >&2
    printf '%s\n' "$ps_only" | head -20 | sed 's/^/  /' >&2
    if [ "$n_ps_only" -gt 20 ]; then
        echo "  ... and $(($n_ps_only - 20)) more" >&2
    fi
    if [ "${PR_HOOKS_PS_ONLY_FATAL:-0}" = "1" ]; then
        echo "ERROR: PR_HOOKS_PS_ONLY_FATAL=1 — unported hooks are fatal in this phase." >&2
        exit 1
    fi
fi

exit 0
