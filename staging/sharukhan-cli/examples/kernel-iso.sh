#!/bin/bash
# kernel-iso.sh - one Photon ISO with another kernel.org kernel, built,
# boot-tested and verified through sharukhan.
#
# The README chapter "Real-world example: a full ISO with kernel 7.3, the
# latest installer and the equivalent canister" explains every function of
# this script line by line. Every value is a variable below or is read from
# sharukhan itself (`sharukhan settings`, `sharukhan wrapper kernel`); the
# script never names a host path, a branch or a row of its own.
#
#   KERNEL=7.3 POI=latest CANISTER=equivalent ISO_TYPE=full examples/kernel-iso.sh
#   examples/kernel-iso.sh --dry-run            print every command, run nothing
#   examples/kernel-iso.sh --step verify_media  run one step
#   examples/kernel-iso.sh --from variant_patches  run from a step to the end
#   examples/kernel-iso.sh --list               the steps, in order
#
# Steps that need a person (porting the kernel's patches to a new release,
# reviewing a new profile) stop with what to do and the command that proves
# it was done; run the script again, or that step with --step, afterwards.
set -euo pipefail

# --- what to build: from the environment, defaults for the documented case ---
KERNEL=${KERNEL:-}                    # kernel.org release: 7.3, 7.3-rc4, 7.2.5 ...
POI=${POI:-latest}                    # installer variant: a [variant <name>] of variants.conf
CANISTER=${CANISTER:-equivalent}      # equivalent (built from this kernel) | prebuilt
ISO_TYPE=${ISO_TYPE:-full}            # full | minimal
ROWS=${ROWS:-}                        # matrix rows to boot-test; empty: derived (see derive_rows)
FROM_PROFILE=${FROM_PROFILE:-}        # write_profile: the profile a new one starts from
DISK_MIN_GB=${DISK_MIN_GB:-40}        # free space a kernel build needs (the 7.3 build used about 30 GB)
WAIT=${WAIT:-1}                       # 1: wait for a detached build or run; 0: return at once
ISO=${ISO:-}                          # verify_media: this file instead of the cache's photon.iso

# --- where sharukhan and its settings are -----------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export SHARUKHAN_CLI_DIR=${SHARUKHAN_CLI_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}
SHARUKHAN=${SHARUKHAN:-$(command -v sharukhan || echo /usr/local/libexec/sharukhan/sharukhan)}
SETTINGS_FILE=${SETTINGS_FILE:-/etc/sharukhan/sharukhan.env}

STEPS=(preflight settings verify_kernel_release prepare_branch write_profile prove_patches
       variant_patches build_iso boot_test verify_media report)

DRY=0
ONLY=""
FROM=""

say() { printf '[kernel-iso] %s\n' "$*"; }
die() { printf '[kernel-iso] REFUSED: %s\n' "$*" >&2; exit 2; }

# A step a person must finish: what to do, and how to prove it was done.
human() {
    local step=$1; shift
    printf '[kernel-iso] STOP at %s - a person must do this:\n' "$step" >&2
    printf '  %s\n' "$@" >&2
    if [ "$DRY" = 1 ]; then
        printf '[kernel-iso] (dry run: a real run stops here)\n' >&2
        return 0
    fi
    printf '[kernel-iso] then: %s --from %s\n' "$0" "$step" >&2
    exit 10
}

# Every command that changes something goes through run(): --dry-run prints it.
run() {
    if [ "$DRY" = 1 ]; then
        printf '+ %s\n' "$*"
    else
        "$@"
    fi
}

# Long work runs detached in its own session with a log, so a closed terminal
# does not end it; the exit status is the log's last line.
detach() {
    local name=$1; shift
    local log="$MC_RUN_LOG_DIR/kernel-iso-$KERNEL-$name-$(date -u +%Y%m%dT%H%M%SZ).log"
    if [ "$DRY" = 1 ]; then
        printf '+ setsid nohup %s > %s 2>&1 &\n' "$*" "$log"
        return 0
    fi
    mkdir -p "$MC_RUN_LOG_DIR"
    setsid nohup bash -c '"$@"; echo "=== exit $? $(date -u +%FT%TZ)"' _ "$@" > "$log" 2>&1 < /dev/null &
    say "$name detached (pid $!), log $log"
    if [ "$WAIT" = 1 ]; then
        until grep -q '^=== exit ' "$log"; do sleep 60; done
        local rc
        rc=$(grep '^=== exit ' "$log" | tail -1 | awk '{print $3}')
        say "$name ended with exit $rc"
        [ "$rc" = 0 ] || die "$name failed, see $log"
    else
        say "not waiting (WAIT=0): follow $log, then continue with --step after $name"
    fi
}

# --- refusal checks ----------------------------------------------------------

in_host_namespace() {
    [ "$(readlink /proc/self/ns/mnt)" = "$(readlink /proc/1/ns/mnt)" ]
}

# Jobs whose row says running and whose process is a live sharukhan.
live_jobs() {
    [ -f "$SHARUKHAN_DB" ] || return 0
    sqlite3 -cmd ".timeout 10000" "$SHARUKHAN_DB" \
        "SELECT id || ' ' || coalesce(pid,0) FROM job WHERE state = 'running'" 2>/dev/null |
    while read -r id pid; do
        [ "$pid" -gt 0 ] && [ -r "/proc/$pid/cmdline" ] &&
            grep -qa 'sharukhan' "/proc/$pid/cmdline" && echo "job $id (pid $pid)"
    done
}

free_gb() { df -BG --output=avail "$1" | tail -1 | tr -dc '0-9'; }

# --- derived values ----------------------------------------------------------

# The kernel's identity as sharukhan derives it: branch, wrapper, rpm version.
# Output lines look like "  branch       experimental/linux-7.3"; the key may hold a space.
identity() {
    "$SHARUKHAN" wrapper kernel "$KERNEL" --offline | sed -n "s/^  $1  *//p" | sed -n 1p
}

# Rows for the boot test: one without and one with STIG, autonomous (kickstart),
# default network, ext4, of the requested ISO type and installer variant.
derive_rows() {
    awk -v t="$ISO_TYPE" -v p="$POI" '
        /^#/ || NF < 10 { next }
        { net = (NF >= 11 ? $11 : "-") }    # an empty net column is the default network
        $2 == t && $3 == p && $6 == "ks" && $5 == "ext4" && net == "-" {
            if ($4 == "no"  && !no)  no = $1
            if ($4 == "yes" && !yes) yes = $1
        }
        END { if (no && yes) print no "," yes; else if (no) print no; else if (yes) print yes }
    ' "$SHARUKHAN_MATRIX"
}

# --- the steps ---------------------------------------------------------------

preflight() {
    in_host_namespace || die "run it in the host mount namespace: nsenter --target 1 --mount -- $0"
    [ -x "$SHARUKHAN" ] || die "no sharukhan at $SHARUKHAN (set SHARUKHAN)"
    "$SHARUKHAN" service status > /dev/null || die "the installed services differ from what 'sharukhan service install' writes ('sharukhan service status')"
    local jobs
    jobs=$(live_jobs)
    [ -z "$jobs" ] || die "a sharukhan job is running: $jobs"
    local free
    free=$(free_gb "$MC_WORK")
    [ "$free" -ge "$DISK_MIN_GB" ] || die "$free GB free under $MC_WORK, $DISK_MIN_GB GB needed (DISK_MIN_GB)"
    say "host namespace, sharukhan $("$SHARUKHAN" service status | grep -c current) current service file(s), no live job, $free GB free"
}

settings() {
    say "KERNEL=$KERNEL POI=$POI CANISTER=$CANISTER ISO_TYPE=$ISO_TYPE ROWS=$ROWS"
    say "kernel branch $KBRANCH (local to $MC_GATE_REPO), wrapper $KWRAPPER, rpm $KVERSION-$KRELEASE"
    say "release $MC_RELEASE, work $MC_WORK, build root of this kernel $MC_WORK/kbuild/$KERNEL"
    say "ISO cache $MC_ISO_CACHE/k$KERNEL/$ISO_TYPE-poi$POI-$CANISTER, store ${MC_ISO_STORE:-none}"
    say "results $MC_RESULTS_DIR, run logs $MC_RUN_LOG_DIR, build logs $MC_BUILD_LOG_DIR"
}

verify_kernel_release() {
    "$SHARUKHAN" wrapper kernel "$KERNEL"          # identity, and what kernel.org lists now
    "$SHARUKHAN" wrapper kernel stable              # the newest stable, to compare with
    # download and verify the signed tarball against the reviewed signers of the profiles
    run "$SHARUKHAN" wrapper verify "$KERNEL" --profiles "$SHARUKHAN_CLI_DIR/profiles/kernel"
}

prepare_branch() {
    local base worktree="$MC_WORK/kernel-branch-$KERNEL"
    base=$(git -C "$MC_GATE_REPO" rev-parse "refs/heads/$MC_RELEASE")
    if git -C "$MC_GATE_REPO" rev-parse -q --verify "refs/heads/$KBRANCH" > /dev/null; then
        # the branch must contain today's release: PR ranges are origin/<branch>..origin/<PR>
        git -C "$MC_GATE_REPO" merge-base --is-ancestor "$base" "refs/heads/$KBRANCH" ||
            human prepare_branch \
                "$KBRANCH does not contain $MC_RELEASE ${base:0:10}: every PR range would carry the difference." \
                "Rebuild it on $MC_RELEASE (see 'prepare_branch' in the README) or rebase its kernel commits onto ${base:0:10}."
        say "$KBRANCH $(git -C "$MC_GATE_REPO" rev-parse --short=10 "refs/heads/$KBRANCH") contains $MC_RELEASE ${base:0:10}"
        return 0
    fi
    run git -C "$MC_GATE_REPO" worktree add --detach "$worktree" "$base"
    human prepare_branch \
        "In $worktree (on $MC_RELEASE ${base:0:10}): put the $KERNEL kernel into the tree's kernel directory," \
        "  the one 'sharukhan wrapper check' names (SPECS/<subrelease>/linux on 5.0): its patch sets," \
        "  config.yaml entry for linux-$KERNEL.tar.xz (sha512 from verify_kernel_release, version quoted)," \
        "  and for a FIPS profile the canister series with its manifest; commit." \
        "git -C $worktree branch $KBRANCH      # local to the gate repository, never pushed" \
        "Proof: write_profile's 'sharukhan wrapper check' passes the branch check."
}

write_profile() {
    local profiles="$SHARUKHAN_CLI_DIR/profiles/kernel" repo="$MC_WORK/kernel-repo-$KERNEL"
    if [ ! -f "$profiles/$KERNEL.json" ]; then
        [ -n "$FROM_PROFILE" ] || die "no profile $profiles/$KERNEL.json: set FROM_PROFILE to the profile it starts from"
        run "$SHARUKHAN" wrapper profile-new --kernel "$KERNEL" --from "$FROM_PROFILE" --profiles "$profiles"
        human write_profile \
            "Review $profiles/$KERNEL.json: every line profile-new listed, the FIPS manifest path," \
            "  installer patches and userland pre-builds; commit it to photonos-scripts."
    fi
    # a clone whose origin is the gate repository: the branch check reads origin/<branch>
    if [ -d "$repo/.git" ]; then
        run git -C "$repo" fetch -q origin "$KBRANCH"
    else
        run git clone -q --no-checkout -b "$KBRANCH" "$MC_GATE_REPO" "$repo"
    fi
    if [ -f "$SHARUKHAN_CLI_DIR/../$KWRAPPER" ]; then
        run "$SHARUKHAN" wrapper derive --profile "$KERNEL" --profiles "$profiles" --repo "$repo" --check
    else
        run "$SHARUKHAN" wrapper derive --profile "$KERNEL" --profiles "$profiles" --repo "$repo"
        say "derived $KWRAPPER: commit it to photonos-scripts"
    fi
    run "$SHARUKHAN" wrapper check --profiles "$profiles" --repo "$repo"
}

prove_patches() {
    human prove_patches \
        "Replay %prep of the pinned kernel specs before hours are spent: run the pin script of $KWRAPPER" \
        "  (its EMBEDPIN heredoc) on a scratch checkout of $KBRANCH in the builder image, then" \
        "  rpmbuild -bp --nodeps -D '_sourcedir <dir>' -D 'photon_subrelease <n>' -D 'dist <tag>' \\" \
        "    -D 'canister_build 1' -D 'canister_stamp_real 1' -D 'fips_certified_override $KVERSION-$KRELEASE<dist>' linux.spec" \
        "  for each flavour (see 'prove_patches' in the README for the exact container command)." \
        "Proof: every patch applies at --fuzz=0 - 0 failed hunks, 0 rejects. A rejected hunk is" \
        "  ported on the branch by hand, committed, and the replay repeated." \
        "Done already? Continue with: $0 --from variant_patches"
}

variant_patches() {
    run "$SHARUKHAN" variant-patches --kernel "$KERNEL"
}

build_iso() {
    detach build_iso "$SHARUKHAN" build-iso --kernel "$KERNEL" --iso-type "$ISO_TYPE" \
        --poi "$POI" --canister "$CANISTER" --allow-build
}

boot_test() {
    detach boot_test "$SHARUKHAN" run --kernel "$KERNEL" --only "$ROWS" --allow-build
}

verify_media() {
    local dir="$MC_ISO_CACHE/k$KERNEL/$ISO_TYPE-poi$POI-$CANISTER" iso want got
    [ -f "$dir/photon.iso.sha256" ] || die "no build recorded in $dir (build_iso first)"
    if [ -n "$ISO" ]; then
        iso=$ISO                                  # e.g. a copy moved or renamed in the store
    else
        [ -e "$dir/photon.iso" ] ||
            die "$dir/photon.iso -> $(readlink -f "$dir/photon.iso"): the file is gone (moved or renamed? set ISO=<file>)"
        iso=$(readlink -f "$dir/photon.iso")
    fi
    [ -f "$iso" ] || die "$iso: no such file"
    want=$(cut -d' ' -f1 "$dir/photon.iso.sha256")
    got=$(sha256sum "$iso" | cut -d' ' -f1)
    [ "$want" = "$got" ] || die "$iso: sha256 $got, the build recorded $want"
    say "ISO $iso, sha256 as recorded"
    say "installer on the media: $(cat "$dir/poi-nevr.txt")"
    local rpms
    rpms=$(bsdtar -tf "$iso" | grep -E '/(linux|linux-esx|linux-fips-canister)-[0-9][^/]*\.rpm$' | sed 's#.*/##' | sort)
    printf '  %s\n' $rpms
    grep -q "^linux-$KVERSION-$KRELEASE\." <<< "$rpms" || die "linux $KVERSION-$KRELEASE is not on the media"
    grep -q "^linux-esx-$KVERSION-$KRELEASE\." <<< "$rpms" || die "linux-esx $KVERSION-$KRELEASE is not on the media"
    say "kernel $KVERSION-$KRELEASE is on the media"
    if [ "$CANISTER" = equivalent ]; then
        # the canister is linked into the kernel, not shipped: its package is in this
        # kernel's build root, from phase A; boot_test's guest.canister_based_on shows it running
        local rpmdir="$MC_WORK/kbuild/$KERNEL/$KBRANCH/stage/RPMS/x86_64" can
        can=$(ls "$rpmdir" 2>/dev/null | grep -E "^linux-fips-canister-$KVERSION-$KRELEASE\." || true)
        [ -n "$can" ] || die "no linux-fips-canister-$KVERSION-$KRELEASE in $rpmdir: phase A did not build the equivalent canister"
        say "equivalent canister built in phase A: $can (not CMVP validated)"
    fi
}

report() {
    local id f
    for id in ${ROWS//,/ }; do
        f=$(ls -t "$MC_RESULTS_DIR/$id"/checks-*.jsonl 2>/dev/null | sed -n 1p)
        [ -n "$f" ] || { say "$id: no results yet"; continue; }
        python3 -I - "$f" <<'PY'
import json, sys
rows = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
fail = [r["check"] for r in rows if r.get("status") == "fail"]
keys = ("meta.kernel", "guest.kernel_release", "guest.fips_canister", "guest.canister_based_on")
seen = {r["check"]: r.get("actual", "") for r in rows if r.get("check") in keys}
print(f"  {sys.argv[1].split('/')[-2]}: {len(rows)} checks, {len(fail)} fail {fail or ''}")
for k in keys:
    if k in seen:
        print(f"    {k} = {seen[k]}")
PY
    done
}

# --- command line ------------------------------------------------------------

while [ $# -gt 0 ]; do
    case $1 in
        --dry-run) DRY=1 ;;
        --step) ONLY=${2:?--step needs a step name}; shift ;;
        --from) FROM=${2:?--from needs a step name}; shift ;;
        --list) printf '%s\n' "${STEPS[@]}"; exit 0 ;;
        -h|--help) sed -n '2,20p' "$0"; exit 0 ;;
        *) die "unknown argument $1 (see --help)" ;;
    esac
    shift
done

[ -n "$KERNEL" ] || die "KERNEL is not set (e.g. KERNEL=7.3)"
case $CANISTER in equivalent|prebuilt) ;; *) die "CANISTER=$CANISTER: equivalent or prebuilt" ;; esac
case $ISO_TYPE in full|minimal) ;; *) die "ISO_TYPE=$ISO_TYPE: full or minimal" ;; esac
for s in "$ONLY" "$FROM"; do
    if [ -n "$s" ] && ! grep -qx -- "$s" <<< "$(printf '%s\n' "${STEPS[@]}")"; then
        die "$s: not a step; one of ${STEPS[*]}"
    fi
done
[ -z "$ONLY" ] || [ -z "$FROM" ] || die "--step and --from exclude each other"

# sharukhan's settings: the file the services use, then every effective value
[ -r "$SETTINGS_FILE" ] || die "$SETTINGS_FILE missing: run 'sharukhan service install' first"
set -a
# shellcheck disable=SC1090
. "$SETTINGS_FILE"
set +a
eval "$("$SHARUKHAN" settings)"

# the installer variant must be one variants.conf defines (captured first: with
# pipefail, grep -q closing the pipe early would fail the producer)
VARIANTS=$("$SHARUKHAN" variants | awk '/^variant /{sub(/:$/, "", $2); print $2}')
grep -qx -- "$POI" <<< "$VARIANTS" ||
    die "POI=$POI: not a variant of $SHARUKHAN_VARIANTS ($(echo $VARIANTS))"

KBRANCH=$(identity branch)
KWRAPPER=$(identity wrapper)
KVERSION=$(identity "rpm Version")
KRELEASE=$(identity "rpm Release" | awk '{print $1}')
[ -n "$KBRANCH" ] && [ -n "$KVERSION" ] && [ -n "$KRELEASE" ] || die "sharukhan could not derive the identity of $KERNEL"
[ -n "$ROWS" ] || ROWS=$(derive_rows)
[ -n "$ROWS" ] || die "no $ISO_TYPE/$POI kickstart row in $SHARUKHAN_MATRIX (set ROWS)"

started=0
for step in "${STEPS[@]}"; do
    if [ -n "$ONLY" ] && [ "$step" != "$ONLY" ]; then
        continue
    fi
    # --from: skip the steps before it; preflight and settings always run
    [ "$step" = "$FROM" ] && started=1
    if [ -n "$FROM" ] && [ "$started" = 0 ] && [ "$step" != preflight ] && [ "$step" != settings ]; then
        continue
    fi
    say "--- $step"
    "$step"
done
