#!/bin/bash
# mc-run.sh - mission control. Drive permutations end to end.
#
# usage:
#   mc-run.sh --plan                     show what would run, build nothing
#   mc-run.sh --only p01,p04 [--keep]    run named permutations
#   mc-run.sh --all                      run every permutation in the matrix
#   mc-run.sh --report                   re-print the summary from stored results
#
# Runs are SEQUENTIAL by design: every ISO build shares $PHOTON_TREE/stage, and
# C: does not have room for many installed VMs at once.
set -u
_here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$_here/../lib/common.sh"
. "$(mc_find_config "$_here")"
TSV="$_here/../config/permutations.tsv"

ONLY="" ALL=0 PLAN=0 REPORT=0 KEEP=0
while [ $# -gt 0 ]; do
    case "$1" in
        --only) ONLY="$2"; shift 2 ;;
        --all) ALL=1; shift ;;
        --plan) PLAN=1; shift ;;
        --report) REPORT=1; shift ;;
        --keep) KEEP=1; shift ;;
        *) mc_die "unknown arg: $1" 64 ;;
    esac
done

rows() { grep -vE '^#|^$' "$TSV"; }

select_rows() {
    if [ -n "$ONLY" ]; then
        # printf '%s' emits no trailing newline, so `read` silently drops the
        # LAST id: --only k01,k03 ran only k01. Newline-terminate the list.
        printf '%s\n' "$ONLY" | tr ',' '\n' | while read -r id; do
            [ -n "$id" ] && rows | awk -v p="$id" '$1==p'
        done
    elif [ "$ALL" -eq 1 ]; then rows
    fi
}

# ---- report --------------------------------------------------------------
mc_report() {
    printf '\n%-6s %-8s %-7s %-5s %-6s %-5s %-9s %-9s %s\n' \
        ID ISO POI STIG FS MODE DOC RESULT "PRs implicated"
    printf '%s\n' "--------------------------------------------------------------------------------"
    local id f pass fail verdict prs
    rows | while read -r id iso poi stig fs mode variant doc expect canister; do
        f="$MC_RESULTS_DIR/$id/checks.jsonl"
        if [ ! -f "$f" ]; then verdict="-"; prs=""
        else
            fail=$(grep -c '"status":"fail"' "$f") || fail=0
            if [ "$fail" -eq 0 ]; then verdict="PASS"; prs=""
            else
                verdict="FAIL($fail)"
                prs=$(grep '"status":"fail"' "$f" | sed -n 's/.*"pr":"\([^"]*\)".*/\1/p' \
                      | grep -v '^-$' | sort -u | tr '\n' ' ')
            fi
        fi
        printf '%-6s %-8s %-7s %-5s %-6s %-5s %-9s %-9s %s\n' \
            "$id" "$iso" "$poi" "$stig" "$fs" "$mode" "$doc" "$verdict" "$prs"
    done
    echo
    echo "DOC is what ISO-PERMUTATION-MATRIX.md recorded before the PRs."
    echo "A row whose RESULT reproduces DOC's 'fails' is a PR regression;"
    echo "the PRs column names which PR the failing assertions belong to."
}

# Reports are versioned too: a report that overwrites its predecessor cannot
# be diffed against it, which is the main thing anyone wants from two runs.
mc_report_to_file() {
    local stamp="${MC_RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
    local dir="$MC_RESULTS_DIR/reports"; mkdir -p "$dir"
    local out="$dir/report-${stamp}.txt"
    mc_report | tee "$out"
    ln -sfn "$(basename "$out")" "$dir/report-latest.txt"
    printf '\n[mc] report written: %s\n' "$out"
}

[ "$REPORT" -eq 1 ] && { mc_report_to_file; exit 0; }

MC_RUN_STAMP="${MC_RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"; export MC_RUN_STAMP
SEL=$(select_rows)
[ -n "$SEL" ] || mc_die "nothing selected - pass --only <ids>, --all, or --plan" 64

if [ "$PLAN" -eq 1 ]; then
    echo "ISOs required (build-time axes only):"
    printf '%s\n' "$SEL" | awk '{print "  "$2"/"$3}' | sort -u
    echo
    echo "Permutations:"
    printf '%s\n' "$SEL" | while read -r id iso poi stig fs mode variant doc expect canister; do
        printf '  %-5s %-8s poi=%-7s stig=%-4s fs=%-6s mode=%-5s variant=%-9s doc=%s\n' \
            "$id" "$iso" "$poi" "$stig" "$fs" "$mode" "$variant" "$doc"
    done
    exit 0
fi

[ -f "$SSH_KEY_DIR/$SSH_KEY_NAME" ] || {
    mkdir -p "$SSH_KEY_DIR"; chmod 700 "$SSH_KEY_DIR"
    ssh-keygen -t ed25519 -N '' -C "photon-mc@$(hostname)" -f "$SSH_KEY_DIR/$SSH_KEY_NAME" >/dev/null \
        || mc_die "ssh-keygen failed" 5
    mc_log "created lab keypair $SSH_KEY_DIR/$SSH_KEY_NAME"
}

# The counters must not live in a subshell. Piping into `while read` forks,
# so every increment is discarded and the final tally is always zero - which
# is exactly what the previous version reported. A here-string keeps the loop
# in this shell.
total=0 failed=0
while read -r id iso poi stig fs mode variant doc expect canister; do
    [ -n "${id:-}" ] || continue
    total=$((total+1))
    echo
    echo "################ $id ################"

    # The canister is a BUILD-time axis like iso_type and poi, so it belongs in
    # the ISO key. Rows that need a locally built canister must not silently
    # reuse the prebuilt ISO - that is how an axis ends up never exercised.
    ISO_PATH=$("$_here/mc-build-iso.sh" --iso-type "$iso" --poi "$poi" \
               --canister "${canister:-prebuilt}" 2>&1 | tail -1)
    if [ ! -f "$ISO_PATH" ]; then
        mc_log "$id: no ISO for $iso/$poi - $ISO_PATH"
        mc_result_init "$id"
        mc_check iso.available "-" fail "built" "missing" "$ISO_PATH"
        continue
    fi

    KS=""
    if [ "$mode" = ks ]; then
        KS="$MC_RESULTS_DIR/$id/kickstart.json"
        mkdir -p "$(dirname "$KS")"
        "$_here/mc-gen-kickstart.sh" --fs "$fs" --stig "$stig" --variant "$variant" \
            --id "$id" --pubkey "$SSH_KEY_DIR/$SSH_KEY_NAME.pub" > "$KS"
    fi

    "$_here/mc-create-vm.sh" --id "$id" --iso "$ISO_PATH" ${KS:+--kickstart "$KS"} --recreate >/dev/null \
        || { mc_log "$id: VM creation failed"; continue; }

    if [ "$mode" = ks ]; then
        "$_here/mc-install.sh" --id "$id" --mode auto || true
    else
        "$_here/mc-install.sh" --id "$id" --mode interactive || true
    fi

    "$_here/mc-verify.sh" --id "$id" || failed=$((failed+1))

    [ "$KEEP" -eq 1 ] || "$_here/mc-teardown.sh" --id "$id" --purge >/dev/null
done <<EOF
$SEL
EOF

printf '\n[mc] %s permutation(s) attempted, %s with failing checks\n' "$total" "$failed"
mc_report_to_file
