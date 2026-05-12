#!/bin/sh
# parity-diff.sh — diff PS vs C .prn output, classify by column volatility.
#
# Phase 8 task 082. ADR-0006 (bit-identical parity) + ADR-0009 (parity gate)
# + FRD-016 (parity harness).
#
# The .prn is a 12-column CSV produced by both the PS script and the C
# port:
#
#   col 1   Spec
#   col 2   Source0 original
#   col 3   Modified Source0 for url health check
#   col 4   UrlHealth                 — VOLATILE (HTTP status, day-to-day)
#   col 5   UpdateAvailable
#   col 6   UpdateURL
#   col 7   HealthUpdateURL           — VOLATILE (HTTP status)
#   col 8   Name
#   col 9   SHAName
#   col 10  UpdateDownloadName
#   col 11  warning
#   col 12  ArchivationDate
#
# Volatile columns (4 and 7) are soft-diffed; all other columns are
# strict — one byte ≠ → strict-diff verdict. The verdict feeds into the
# 30/60/90-day ladder in tools/parity-gate.sh (task 083).
#
# Usage:
#   parity-diff.sh <ps.prn> <c.prn> [-q]
#
# Output (machine-readable, one TSV line on stdout):
#   <verdict>\t<strict_rows>\t<soft_rows>\t<lines_ps>\t<lines_c>
#
# verdict ∈ {green, soft, strict}
#   green   — byte-identical (or all-volatile + zero-diff after stripping vol cols)
#   soft    — rows differ only in cols 4 and/or 7
#   strict  — at least one row differs in a non-volatile column (or
#             line counts differ)
#
# Per-row detail prints to stderr unless -q is given.
#
# Exit:
#   0 — green or soft
#   1 — strict diff
#   2 — bad arguments / missing files
set -eu

quiet=0
if [ "${3-}" = "-q" ]; then
    quiet=1
fi

if [ "$#" -lt 2 ]; then
    echo "usage: $0 <ps.prn> <c.prn> [-q]" >&2
    exit 2
fi

PS_PRN="$1"
C_PRN="$2"

for f in "$PS_PRN" "$C_PRN"; do
    if [ ! -f "$f" ]; then
        echo "::error::parity-diff: missing file $f" >&2
        exit 2
    fi
done

# Fast path: byte-identical → green.
if cmp -s "$PS_PRN" "$C_PRN"; then
    n=$(wc -l < "$PS_PRN")
    printf 'green\t0\t0\t%d\t%d\n' "$n" "$n"
    exit 0
fi

awk -F',' -v PS="$PS_PRN" -v C="$C_PRN" -v QUIET="$quiet" '
BEGIN {
    ln_ps = 0
    while ((getline line < PS) > 0) ps[++ln_ps] = line
    close(PS)
    ln_c = 0
    while ((getline line < C) > 0) c[++ln_c] = line
    close(C)

    strict = 0
    soft   = 0
    n      = (ln_ps > ln_c) ? ln_ps : ln_c

    for (i = 1; i <= n; i++) {
        ps_line = (i <= ln_ps) ? ps[i] : ""
        c_line  = (i <= ln_c)  ? c[i]  : ""

        if (ps_line == c_line) continue

        if (ps_line == "" || c_line == "") {
            # Row added/removed — always strict (parity contract is
            # that both sides produce the same row set).
            strict++
            if (!QUIET)
                printf("STRICT row %d  line-count-mismatch  PS=<%s>  C=<%s>\n",
                       i, ps_line, c_line) > "/dev/stderr"
            continue
        }

        # Naïve comma split — relies on identical quoting on both
        # sides, which is the parity contract (ADR-0006). PS uses
        # Out-File with the "Sort-Object" OrdinalIgnoreCase path; C
        # uses setlocale(LC_ALL,"C")+strcasecmp. They emit the same
        # column count and the same quote-handling for embedded commas.
        npf = split(ps_line, pf, FS)
        ncf = split(c_line,  cf, FS)

        only_volatile = 1
        diff_cols = ""
        max = (npf > ncf) ? npf : ncf
        for (k = 1; k <= max; k++) {
            pv = (k <= npf) ? pf[k] : ""
            cv = (k <= ncf) ? cf[k] : ""
            if (pv != cv) {
                if (k != 4 && k != 7) only_volatile = 0
                diff_cols = diff_cols " " k
            }
        }

        if (only_volatile) {
            soft++
            if (!QUIET)
                printf("SOFT   row %d  cols[%s]  spec=%s\n",
                       i, diff_cols, pf[1]) > "/dev/stderr"
        } else {
            strict++
            if (!QUIET)
                printf("STRICT row %d  cols[%s]  spec=%s\n",
                       i, diff_cols, pf[1]) > "/dev/stderr"
        }
    }

    if      (strict > 0) verdict = "strict"
    else if (soft   > 0) verdict = "soft"
    else                 verdict = "green"

    printf("%s\t%d\t%d\t%d\t%d\n", verdict, strict, soft, ln_ps, ln_c)
    exit (strict > 0 ? 1 : 0)
}'
