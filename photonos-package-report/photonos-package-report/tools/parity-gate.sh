#!/bin/sh
# parity-gate.sh — apply the 30/60/90-day strictness ladder to the
# parity journal and emit a verdict for the gate workflow.
#
# Phase 8 task 082. ADR-0009.
#
# Window matrix (days since the FIRST journal row, i.e. clock-start):
#
#    0-30  : soft       — informational; pass regardless of latest verdict
#   30-60  : warning    — pass with warning if latest is not green
#   60-90  : strict     — fail PR if latest is strict-diff
#   90+    : cutover    — pass (Phase 9 retirement trigger)
#
# Usage:
#   parity-gate.sh <journal.tsv>
#
# Output (one TSV line on stdout, machine-readable):
#   <state>\t<days_elapsed>\t<window>\t<latest_verdict>\t<journal_rows>
#
# state ∈ {pass, warn, fail, no-data}
# window ∈ {0-30, 30-60, 60-90, 90+, no-data}
#
# Detailed message goes to stderr.
#
# Exit:
#   0 — pass (state=pass or warn)
#   1 — fail (state=fail)
#   2 — no journal data / bad arguments
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 <journal.tsv>" >&2
    exit 2
fi

J="$1"

if [ ! -f "$J" ]; then
    printf 'no-data\t0\tno-data\tnone\t0\n'
    echo "::warning::parity-gate: journal file does not exist yet — clock not started" >&2
    exit 2
fi

# Skip header, count data rows.
rows=$(awk 'NR > 1' "$J" | wc -l)
if [ "$rows" -eq 0 ]; then
    printf 'no-data\t0\tno-data\tnone\t0\n'
    echo "::warning::parity-gate: journal is empty (header only) — clock not started" >&2
    exit 2
fi

# First data row's ts → clock start. Latest data row's verdict → current state.
first_ts=$(awk 'NR == 2 { print $1; exit }' "$J")
latest_verdict=$(awk 'END { print $NF }' "$J")

# Days elapsed (integer division, second-precision input).
now_epoch=$(date -u +%s)
first_epoch=$(date -u -d "$first_ts" +%s 2>/dev/null || echo "$now_epoch")
days=$(( (now_epoch - first_epoch) / 86400 ))

# Window classification.
if   [ "$days" -lt 30 ];  then window="0-30"
elif [ "$days" -lt 60 ];  then window="30-60"
elif [ "$days" -lt 90 ];  then window="60-90"
else                            window="90+"
fi

# State per ADR-0009 ladder.
state="pass"
case "$window" in
    "0-30")
        # Soft window: pass regardless. Surface the verdict for visibility.
        state="pass"
        ;;
    "30-60")
        # Strict-warning: pass with warning if not green.
        if [ "$latest_verdict" = "green" ]; then
            state="pass"
        else
            state="warn"
        fi
        ;;
    "60-90")
        # Strict-failure: fail on strict; warn on soft; pass on green.
        case "$latest_verdict" in
            green) state="pass" ;;
            soft)  state="warn" ;;
            strict) state="fail" ;;
            *)      state="warn" ;;
        esac
        ;;
    "90+")
        # Cutover-ready: pass. Retirement (Phase 9 task 090) is a
        # separate action triggered by sustained green in this window.
        state="pass"
        ;;
esac

printf '%s\t%d\t%s\t%s\t%d\n' "$state" "$days" "$window" "$latest_verdict" "$rows"

case "$state" in
    pass) exit 0 ;;
    warn) exit 0 ;;
    fail) exit 1 ;;
    *)    exit 2 ;;
esac
