#!/bin/sh
# extract-source0-lookup.sh — emit the embedded $Source0LookupData CSV from
# the upstream PowerShell script.
#
# Invariants (ADR-0005, ADR-0008):
#   - POSIX shell + awk only. No Python, no Perl, no pwsh.
#   - PS source is read-only; this script never modifies it.
#
# The PS source contains a PowerShell here-string. The opening marker is
# the literal four-character sequence  =@  followed by U+0027 APOSTROPHE
# at end-of-line. The closing marker is U+0027 APOSTROPHE followed by @
# at start-of-line. Between the two we have:
#
#     specfile,Source0Lookup,...      <-- CSV header
#     ...                             <-- data rows
#
# Output: the CSV lines BETWEEN the two markers, in order, one per line,
# preserving the exact byte content (no trim, no quoting changes). Exit
# non-zero if either marker is missing.
#
# Usage:
#   extract-source0-lookup.sh <path-to-photonos-package-report.ps1>
#
# Quoting note: this script contains NO literal apostrophes inside the
# shell heredoc, and the awk program is fed to awk via -f from a temp
# heredoc to avoid the well-known shell-single-quote-awk-apostrophe trap.

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

# Build the awk program in a temporary file. Use \47 (octal for the
# apostrophe character U+0027) so this script body itself never contains
# a stray literal apostrophe.
awk_prog=$(mktemp)
trap 'rm -f "$awk_prog"' EXIT INT TERM

cat > "$awk_prog" <<'AWKEOF'
# State:
#   0 = before opening marker
#   1 = inside here-string (emit)
#   2 = after closing marker
BEGIN { state = 0; saw_open = 0; saw_close = 0 }

# Opening marker. Apostrophe expressed as \47 (octal U+0027) so this
# script body contains no stray literal apostrophes.
state == 0 && $0 ~ "^\\$Source0LookupData=@\47[[:space:]]*$" {
    state = 1
    saw_open = 1
    next
}

# Closing marker: apostrophe followed by @ at start-of-line.
state == 1 && $0 ~ "^\47@[[:space:]]*$" {
    state = 2
    saw_close = 1
    next
}

state == 1 { print }

END {
    if (!saw_open)  { print "extract-source0-lookup: opening marker not found"  > "/dev/stderr"; exit 3 }
    if (!saw_close) { print "extract-source0-lookup: closing marker not found"  > "/dev/stderr"; exit 4 }
}
AWKEOF

awk -f "$awk_prog" "$ps_path"
