#!/bin/sh
# parity-journal-append.sh — append one row to tools/parity-journal.tsv.
#
# Phase 8 task 082. ADR-0009 (30/60/90-day ladder).
#
# The journal is committed alongside each C-side workflow run so the
# 90-day clock survives runner restarts. One row per (PS run, C run,
# branch) triple. tools/parity-gate.sh (task 083) reads this file.
#
# Schema (TSV with header):
#   ts             ISO 8601 UTC, second precision
#   ps_run_id      GitHub run id of the PS workflow that produced the snapshot
#   c_run_id       GitHub run id of this C workflow run
#   branch         Photon branch the .prn pair came from (3.0, 5.0, common, ...)
#   strict_rows    count of rows differing in non-volatile columns
#   soft_rows      count of rows differing only in cols 4 and/or 7
#   volatile_only  "true" if soft_rows > 0 and strict_rows == 0
#   verdict        green | soft | strict
#
# Usage:
#   parity-journal-append.sh <journal.tsv> <ps_run_id> <c_run_id> <branch> \
#                            <strict_rows> <soft_rows> <verdict>
set -eu

if [ "$#" -ne 7 ]; then
    echo "usage: $0 <journal.tsv> <ps_run_id> <c_run_id> <branch> <strict> <soft> <verdict>" >&2
    exit 2
fi

J="$1"
PS_RID="$2"
C_RID="$3"
BR="$4"
STRICT="$5"
SOFT="$6"
V="$7"

case "$V" in
    green|soft|strict) ;;
    *)
        echo "::error::parity-journal-append: invalid verdict '$V' (want green|soft|strict)" >&2
        exit 2
        ;;
esac

# Initialise the file with a header row if absent. The header lets
# downstream consumers ignore field-order changes safely.
if [ ! -f "$J" ]; then
    printf 'ts\tps_run_id\tc_run_id\tbranch\tstrict_rows\tsoft_rows\tvolatile_only\tverdict\n' > "$J"
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
volatile_only="false"
if [ "$V" = "soft" ]; then
    volatile_only="true"
fi

printf '%s\t%s\t%s\t%s\t%d\t%d\t%s\t%s\n' \
    "$ts" "$PS_RID" "$C_RID" "$BR" "$STRICT" "$SOFT" "$volatile_only" "$V" >> "$J"
