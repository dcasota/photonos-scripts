#!/bin/sh
# source0-lookup-roundtrip.sh — parity test for the Source0Lookup embed.
#
# Steps:
#   1. Run tools/extract-source0-lookup.sh against ../photonos-package-report.ps1
#      to get the raw CSV from the PS upstream.
#   2. Run the test_phase3 binary in --emit-csv mode. This parses the
#      embedded C string back into the in-memory table, then re-emits it
#      as CSV using the same quoting conventions.
#   3. diff the two byte-for-byte. Any drift fails the test.
#
# Usage:
#   source0-lookup-roundtrip.sh <source-dir> <path-to-test_phase3-binary>
#
# Invariants:
#   - POSIX shell. No Python.

set -eu

if [ $# -ne 2 ]; then
    echo "usage: $0 <source-dir> <test_phase3-binary>" >&2
    exit 2
fi
SRC_DIR=$1
TEST_BIN=$2

PS_PATH="$SRC_DIR/../photonos-package-report.ps1"
EXTRACT="$SRC_DIR/tools/extract-source0-lookup.sh"

raw=$(mktemp)
emit=$(mktemp)
trap 'rm -f "$raw" "$emit"' EXIT INT TERM

"$EXTRACT"  "$PS_PATH"   > "$raw"
"$TEST_BIN" --emit-csv   > "$emit"

if cmp -s "$raw" "$emit"; then
    echo "parity OK ($(wc -l < "$raw") lines)"
    exit 0
fi

# `diff` may not be installed on Photon CI; fall back to a small awk
# differ that prints the first 20 mismatched lines.
echo "source0-lookup parity FAIL — first 20 mismatched lines:" >&2
awk -v raw="$raw" -v emit="$emit" '
BEGIN {
    n_raw = 0; while ((getline l < raw) > 0)  raw_lines[++n_raw] = l
    n_em  = 0; while ((getline l < emit) > 0) emit_lines[++n_em] = l
    max = n_raw > n_em ? n_raw : n_em
    shown = 0
    for (i = 1; i <= max && shown < 20; i++) {
        if (raw_lines[i] != emit_lines[i]) {
            print "- " raw_lines[i]  > "/dev/stderr"
            print "+ " emit_lines[i] > "/dev/stderr"
            shown++
        }
    }
}
'
exit 1
