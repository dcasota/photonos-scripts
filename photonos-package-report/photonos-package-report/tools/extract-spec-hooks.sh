#!/bin/sh
# extract-spec-hooks.sh — list every per-spec override block in the
# upstream PowerShell script.
#
# Each PS block looks like one of:
#
#   if ($currentTask.spec -ilike 'foo.spec') { ... single-line body ... }
#
#   if ($currentTask.spec -ilike 'bar.spec') {
#       ... multi-line body ...
#   }
#
#   The body may contain nested braces (string interpolation, sub-scriptblocks);
#   we balance them with a depth counter.
#
# Invariants (ADR-0005, ADR-0008):
#   - POSIX shell + awk only. No Python, no Perl, no pwsh.
#   - PS source is read-only.
#
# Output (TSV, one row per block):
#   <spec-basename>\t<start-line>\t<end-line>
#
# Multiple rows may share a spec-basename: PS scatters several blocks
# across the script (Source0 substitution, UpdateDownloadName rewrite,
# version normalisation). The downstream consumer (drift check / hook
# generator) deduplicates as needed.
#
# Usage:
#   extract-spec-hooks.sh <path-to-photonos-package-report.ps1>

set -eu

if [ $# -ne 1 ]; then
    echo "usage: $0 <photonos-package-report.ps1>" >&2
    exit 2
fi
ps_path=$1
if [ ! -r "$ps_path" ]; then
    echo "$0: cannot read $ps_path" >&2
    exit 2
fi

awk_prog=$(mktemp)
trap 'rm -f "$awk_prog"' EXIT INT TERM

cat > "$awk_prog" <<'AWKEOF'
# Match every line that opens a hook block. The pattern is anchored on
# the literal substring `currentTask.spec -ilike` followed by a quoted
# spec basename. Apostrophe = \47 to avoid the shell-quoting trap.
#
# State machine:
#   depth == 0  : looking for an opener
#   depth >  0  : counting braces inside the active block

BEGIN { depth = 0; spec = ""; start = 0 }

{
    line = $0
    if (depth == 0) {
        # Look for the opener pattern on this line.
        if (match(line, /currentTask\.spec[ \t]+-ilike[ \t]+\47[^\47]+\.spec\47/)) {
            tok = substr(line, RSTART, RLENGTH)
            # Extract the spec basename out of \47SPEC\47.
            if (match(tok, /\47[^\47]+\.spec\47/)) {
                spec = substr(tok, RSTART + 1, RLENGTH - 2)
            } else {
                spec = ""
            }
            start = NR
            # Now count braces on the remainder of the line.
            tail = substr(line, RSTART + RLENGTH)
            depth = 0
            for (i = 1; i <= length(tail); i++) {
                c = substr(tail, i, 1)
                if (c == "{") depth++
                else if (c == "}") depth--
            }
            if (depth == 0 && index(tail, "{") > 0) {
                # Single-line block opened and closed on the same line.
                print spec "\t" start "\t" NR
                spec = ""; start = 0
            }
            # If no `{` was seen yet, the opening brace is on a later line.
            if (depth == 0 && index(tail, "{") == 0) {
                # treat as still searching for `{`
                # (rare; PS authors put `{` on same line as `if`)
                spec = ""
                start = 0
            }
        }
        next
    }
    # depth > 0 — inside an active block. Count braces on this entire line.
    for (i = 1; i <= length(line); i++) {
        c = substr(line, i, 1)
        if (c == "{") depth++
        else if (c == "}") {
            depth--
            if (depth == 0) {
                print spec "\t" start "\t" NR
                spec = ""; start = 0
                break
            }
        }
    }
}

END {
    if (depth != 0) {
        printf("extract-spec-hooks: unbalanced braces (depth=%d) starting at L%d (spec=%s)\n",
               depth, start, spec) > "/dev/stderr"
        exit 5
    }
}
AWKEOF

awk -f "$awk_prog" "$ps_path"
