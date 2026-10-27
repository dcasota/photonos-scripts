#!/bin/bash
# check-drift - the kickstart copy in this directory must stay identical to
# the canonical template the ISO build actually consumes.
#
# WHY THIS EXISTS: a convenience copy that can silently diverge from the real
# thing is worse than no copy at all - you would read this directory, reason
# about a kickstart the build never uses, and be confidently wrong.
#
# TWO MODES, because this directory ships in two places:
#
#   1. Next to the SPAGAT repo -> diff against the LIVE canonical file:
#        src/tools/iso-build/iso-phase6-kickstart-template.cfg
#      This is the strong check: it detects drift in EITHER direction.
#
#   2. Standalone (e.g. inside photonos-scripts/staging) -> the canonical
#      file is not reachable, so fall back to the recorded snapshot hash in
#      EXPECTED-SHA256. Weaker - it cannot see upstream moving - but it still
#      catches an edited local copy, and it says plainly which mode it ran in
#      rather than quietly proving less than you think.
#
# Point it at a SPAGAT checkout to force mode 1:
#     SPAGAT_REPO=/path/to/SpagatLibrarian-Appliance ./check-drift.sh
set -u
# ${BASH_SOURCE[0]} may point at a COPY in /tmp (the CRLF-stripping workflow),
# so locate the kickstart directory rather than assuming it is alongside.
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
HERE=""
for _d in "${VM_LAB_DIR:-}/kickstart" "$_here" "$PWD/kickstart" "$PWD"; do
    if [ -n "$_d" ] && [ -f "$_d/photon-appliance.ks.template.json" ]; then HERE="$_d"; break; fi
done
if [ -z "$HERE" ]; then
    echo "FATAL: cannot locate photon-appliance.ks.template.json" >&2
    echo "  Run from the vm-lab/kickstart directory, or export VM_LAB_DIR=/path/to/vm-lab" >&2
    exit 2
fi
COPY="$HERE/photon-appliance.ks.template.json"
HASHFILE="$HERE/EXPECTED-SHA256"
REL="src/tools/iso-build/iso-phase6-kickstart-template.cfg"

echo "=== local copy ==="
echo "  $COPY"
actual=$(sha256sum "$COPY" | cut -d' ' -f1)
echo "  sha256: $actual"
echo "  bytes : $(stat -c%s "$COPY")"

# Find a canonical file if one is reachable.
CANON=""
for c in "${SPAGAT_REPO:-}/$REL" \
         "$HERE/../../../$REL" \
         "$HERE/../../../../SpagatLibrarian-Appliance/$REL"; do
    if [ -n "$c" ] && [ -f "$c" ]; then CANON="$c"; break; fi
done

rc=0
echo
if [ -n "$CANON" ]; then
    echo "=== MODE 1: diffing against the live canonical file ==="
    echo "  $CANON"
    echo "  sha256: $(sha256sum "$CANON" | cut -d' ' -f1)"
    echo
    if cmp -s "$CANON" "$COPY"; then
        echo "IN SYNC - byte-identical to what the build consumes."
    else
        echo "*** DRIFT - the copy no longer matches the canonical template ***"
        echo
        diff -u "$CANON" "$COPY" | head -n 60
        echo
        echo "The canonical file is the source of truth. Refresh with:"
        echo "  cp '$CANON' '$COPY'"
        echo "  sha256sum '$COPY' | cut -d' ' -f1 > '$HASHFILE'"
        rc=1
    fi

    echo
    echo "=== control: the comparison can actually fail ==="
    tmp=$(mktemp); cp "$CANON" "$tmp"; printf '\n#drift-canary\n' >> "$tmp"
    if cmp -s "$CANON" "$tmp"; then
        echo "  *** a modified file compared EQUAL - this check proves nothing ***"; rc=1
    else
        echo "  a modified copy is correctly detected as different"
    fi
    rm -f "$tmp"
else
    echo "=== MODE 2: canonical file not reachable - hash fallback ==="
    echo "  (looked for $REL under \$SPAGAT_REPO and two relative guesses)"
    if [ ! -f "$HASHFILE" ]; then
        echo "  *** no EXPECTED-SHA256 either - drift CANNOT be checked. ***"
        echo "  This is the one outcome that must not be read as 'fine'."
        exit 3
    fi
    expected=$(grep -oE '[0-9a-f]{64}' "$HASHFILE" | head -n1)
    echo "  expected (recorded at snapshot time): $expected"
    echo "  actual                              : $actual"
    if [ "$actual" = "$expected" ]; then
        echo
        echo "UNCHANGED since the snapshot."
        echo "NOTE: this proves the LOCAL copy was not edited. It canNOT tell"
        echo "you whether the upstream template has moved on - for that, run"
        echo "with SPAGAT_REPO pointing at a SpagatLibrarian-Appliance checkout."
    else
        echo
        echo "*** the local copy has been EDITED since the snapshot ***"
        rc=1
    fi

    echo
    echo "=== control: the hash comparison can actually fail ==="
    if [ "$expected" = "0000000000000000000000000000000000000000000000000000000000000000" ]; then
        echo "  *** placeholder hash - meaningless ***"; rc=1
    elif [ "$actual" = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" ]; then
        echo "  *** impossible actual hash ***"; rc=1
    else
        echo "  a wrong hash would not match -> the comparison discriminates"
    fi
fi

exit $rc
