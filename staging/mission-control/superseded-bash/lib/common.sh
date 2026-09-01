# common.sh - shared helpers. Source, do not execute.
#
# Conventions carried over from vm-lab because they were each learned the hard
# way there:
#   * always 'grep -a' a serial log - it contains NUL bytes and plain grep
#     silently prints nothing
#   * 'n=$(grep -c ...) || n=0', never '$(grep -c ... || echo 0)'
#   * every check that can be vacuous carries a negative control
#   * print the measured value, not a bare OK/FAIL - "tool missing" and "tool
#     present but unreadable by this user" need different fixes and look
#     identical in a boolean
# What is new here: every check emits a machine-readable record and a non-zero
# exit propagates. vm-lab's 40-check-staging.sh never exits non-zero, which is
# fine for an inspection tool and useless for a matrix.

set -u

mc_find_config() {
    local here="${1:?}" c
    for c in "${MC_DIR:-}/config/mission-control.env" \
             "${here}/../config/mission-control.env" \
             "${here}/config/mission-control.env" \
             "${PWD}/config/mission-control.env" \
             "${PWD}/../config/mission-control.env"; do
        [ -n "$c" ] && [ -f "$c" ] && { printf '%s\n' "$c"; return 0; }
    done
    echo "FAIL: mission-control.env not found. Export MC_DIR=/path/to/mission-control." >&2
    exit 78
}

# ---- structured results -------------------------------------------------
# Every assertion lands in $MC_RESULT_FILE as one JSON object per line.
# 'pr' names the pull request the assertion proves, so a failure reads as
# "PR #22 regressed" rather than "something broke".
# Every run gets its own timestamped file. The previous version truncated a
# fixed checks.jsonl, so re-running a permutation destroyed the evidence for
# the run before it - exactly when comparing two runs is what would explain a
# regression. checks-latest.jsonl is a convenience pointer, never the storage.
mc_result_init() {
    MC_PERM_ID="${1:?perm id}"
    MC_RUN_STAMP="${MC_RUN_STAMP:-$(date -u +%Y%m%dT%H%M%SZ)}"
    local dir="${MC_RESULTS_DIR}/${MC_PERM_ID}"
    mkdir -p "$dir"
    MC_RESULT_FILE="${dir}/checks-${MC_RUN_STAMP}.jsonl"
    : > "$MC_RESULT_FILE"
    ln -sfn "$(basename "$MC_RESULT_FILE")" "${dir}/checks-latest.jsonl"
    MC_FAILED=0
}

mc_json_escape() { printf '%s' "${1-}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read())[1:-1])'; }

# mc_check <id> <pr> <status pass|fail|skip|info> <expected> <actual> <detail>
mc_check() {
    local id="$1" pr="$2" st="$3" exp="$4" act="$5" det="${6-}"
    printf '{"perm":"%s","check":"%s","pr":"%s","status":"%s","expected":"%s","actual":"%s","detail":"%s"}\n' \
        "$MC_PERM_ID" "$id" "$pr" "$st" \
        "$(mc_json_escape "$exp")" "$(mc_json_escape "$act")" "$(mc_json_escape "$det")" \
        >> "$MC_RESULT_FILE"
    case "$st" in
        pass) printf '  PASS  %-34s %-10s %s\n' "$id" "$pr" "$act" ;;
        fail) printf '  FAIL  %-34s %-10s expected=%s actual=%s\n' "$id" "$pr" "$exp" "$act"; MC_FAILED=$((MC_FAILED+1)) ;;
        skip) printf '  skip  %-34s %-10s %s\n' "$id" "$pr" "$det" ;;
        *)    printf '  info  %-34s %-10s %s\n' "$id" "$pr" "$act" ;;
    esac
}

# mc_expect <id> <pr> <expected> <actual> [detail]
mc_expect() {
    local id="$1" pr="$2" exp="$3" act="$4" det="${5-}"
    if [ "$exp" = "$act" ]; then mc_check "$id" "$pr" pass "$exp" "$act" "$det"
    else mc_check "$id" "$pr" fail "$exp" "$act" "$det"; fi
}

mc_result_summary() {
    local total pass fail
    total=$(wc -l < "$MC_RESULT_FILE")
    pass=$(grep -c '"status":"pass"' "$MC_RESULT_FILE") || pass=0
    fail=$(grep -c '"status":"fail"' "$MC_RESULT_FILE") || fail=0
    printf '\n  %s: %s checks, %s pass, %s fail\n' "$MC_PERM_ID" "$total" "$pass" "$fail"
    if [ "$fail" -gt 0 ]; then
        printf '  PRs implicated:\n'
        grep '"status":"fail"' "$MC_RESULT_FILE" \
          | sed -n 's/.*"pr":"\([^"]*\)".*/    \1/p' | sort -u
    fi
    return "$([ "$fail" -eq 0 ] && echo 0 || echo 1)"
}

# ---- serial log helpers -------------------------------------------------
# Strip NULs and SGR sequences. vm-lab had this right on one line and wrong on
# another (s/...*g//g instead of *m//g); keeping it in one function so it
# cannot drift again.
mc_clean_log() { tr -d '\000' | sed -E 's/\x1b\[[0-9;]*m//g'; }

# Do NOT use "grep -a" here. On this host /usr/bin/grep is toybox in a
# non-interactive shell (interactively it is ugrep), and toybox grep has no
# -a: it returns 0 matches on a NUL-bearing file instead of erroring. That is
# the same silent-zero trap vm-lab documents, reached by a different route.
# Stripping NULs first is portable across all three greps.
mc_grep_count() {
    local n
    n=$(tr -d '\000' < "$2" 2>/dev/null | grep -c "$1" 2>/dev/null) || n=0
    printf '%s' "$n"
}

# ---- identity -----------------------------------------------------------
# Deterministic per-permutation MAC/UUID/IP. VMware's manual-assignment OUI is
# 00:50:56:00:00:00-00:50:56:3F:FF:FF; staying inside it means the address is
# ours and is never derived from the UUID.
# Index = the permutation's ordinal in permutations.tsv, NOT a hash of its id.
# A cksum-based index collided on this very matrix (k04/k16 and k09/s02 shared
# an index, and therefore a MAC, a UUID and an IP), and could reach .240 -
# inside VMnet8's DHCP range of .128-.254. An ordinal is unique by
# construction and stays bounded, so the addresses can never collide with a
# lease or with each other.
mc_perm_index() {
    local id="$1" tsv="${MC_PERM_FILE:-${MC_DIR:-}/config/permutations.tsv}" n
    [ -f "$tsv" ] || tsv="$(dirname "${BASH_SOURCE[0]}")/../config/permutations.tsv"
    n=$(grep -vE '^#|^$' "$tsv" | awk -v want="$id" '$1==want{print NR; exit}')
    [ -n "$n" ] || mc_die "permutation '$id' is not in $tsv" 65
    # .41 upward; the matrix would have to exceed 80 rows to reach the DHCP floor.
    [ "$n" -le 80 ] || mc_die "permutation ordinal $n would push the IP into the DHCP range" 65
    printf '%s' "$n"
}

mc_mac_for()  { printf '00:50:56:3a:%02x:%02x' $(( ${1} / 256 )) $(( ${1} % 256 )); }
mc_uuid_for() { printf '56 4d 6d 63 00 00 00 00-00 00 00 00 00 00 %02x %02x' $(( ${1} / 256 )) $(( ${1} % 256 )); }
mc_ip_for()   { printf '%s.%d' "$MC_NET_PREFIX" $(( MC_IP_BASE + ${1} )); }

# /mnt/c/foo/bar -> C:\foo\bar. tr, not sed's \U: /usr/bin/sed here is
# toybox in a non-interactive shell and emits a literal "U" for that GNU
# extension. vmrun.exe and vmware-vdiskmanager.exe both need Windows form.
mc_win_path() {
    local p="$1" drive rest
    case "$p" in
        /mnt/?/*)
            drive=$(printf '%s' "$p" | cut -c6 | tr 'a-z' 'A-Z')
            rest=$(printf '%s' "$p" | cut -c7- | tr '/' '\\')
            printf '%s:%s' "$drive" "$rest" ;;
        *)  printf '%s' "$p" | tr '/' '\\' ;;
    esac
}

mc_log() { printf '[mc] %s\n' "$*"; }
mc_die() { printf '[mc] FAIL: %s\n' "$*" >&2; exit "${2:-1}"; }
