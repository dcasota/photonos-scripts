# kernel-iso.sh: the steps

[← sharukhan overview](../../README.md)

**Who this is for:** Readers of `examples/kernel-iso.sh`: each step function and the command line, line by line.

### Step `preflight`

```bash
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
```

Refuses unless: the script runs in the host mount namespace; the sharukhan
binary exists; `sharukhan service status` reports the installed services and
settings unchanged; no sharukhan job runs (a build would compete for the
builder and the disk); and `DISK_MIN_GB` are free under `$MC_WORK`.

### Step `settings`

```bash
settings() {
    say "KERNEL=$KERNEL POI=$POI CANISTER=$CANISTER ISO_TYPE=$ISO_TYPE ROWS=$ROWS"
    say "kernel branch $KBRANCH (local to $MC_GATE_REPO), wrapper $KWRAPPER, rpm $KVERSION-$KRELEASE"
    say "release $MC_RELEASE, work $MC_WORK, build root of this kernel $MC_WORK/kbuild/$KERNEL"
    say "ISO cache $MC_ISO_CACHE/k$KERNEL/$ISO_TYPE-poi$POI-$CANISTER, store ${MC_ISO_STORE:-none}"
    say "results $MC_RESULTS_DIR, run logs $MC_RUN_LOG_DIR, build logs $MC_BUILD_LOG_DIR"
}
```

Prints what the run will use - the variables, the kernel branch and wrapper,
the release, the kernel's build root `$MC_WORK/kbuild/<kernel>`, its ISO cache
directory `$MC_ISO_CACHE/k<kernel>/<type>-poi<variant>-<canister>` and the
store, the results and log directories. Nothing here is typed in; all of it
comes from `sharukhan settings` and `sharukhan wrapper kernel`.

### Step `verify_kernel_release`

```bash
verify_kernel_release() {
    "$SHARUKHAN" wrapper kernel "$KERNEL"          # identity, and what kernel.org lists now
    "$SHARUKHAN" wrapper kernel stable              # the newest stable, to compare with
    # download and verify the signed tarball against the reviewed signers of the profiles
    run "$SHARUKHAN" wrapper verify "$KERNEL" --profiles "$SHARUKHAN_CLI_DIR/profiles/kernel"
}
```

- `wrapper kernel <release>` (online): the identity, and how kernel.org lists
  the release now (mainline, stable, longterm).
- `wrapper kernel stable`: the newest stable release, to see whether a newer
  point release exists.
- `wrapper verify <release>` downloads `linux-<release>.tar.xz` into the kernel
  cache and accepts it only with the `.tar.sign` of a reviewed kernel.org signer
  (`profiles/kernel/kernel-org-signers.json`), printing its sha512 - the value
  every later step compares against. *Example output (2026-10):* `verified
  .../linux-7.3.tar.xz (pgp-signature)`, `sha512 14b99ea7...e590`, `signer
  647F28654894E3BD457199BE38DBBDC86092693E (Greg Kroah-Hartman)`.

### Step `prepare_branch`

```bash
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
```

- `base` is the head of the release branch in the gate repository.
- If the kernel branch exists, it must contain that head (`merge-base
  --is-ancestor`); otherwise the step stops - see "Why a kernel branch".
- If it does not exist, a detached worktree is created on the release head
  under `$MC_WORK/kernel-branch-<kernel>`, and the step stops for the port:
  the new kernel into the tree's kernel directory, its patch sets, its
  `config.yaml` entry (URL, sha512 from `verify_kernel_release`, the version
  quoted so YAML keeps it a string), the FIPS canister series and manifest for
  a FIPS profile; then `git branch <kernel branch>` in the worktree. The proof
  is `write_profile`'s branch check.

### Step `write_profile`

```bash
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
```

- A missing profile is started from `FROM_PROFILE` with `wrapper profile-new`
  (which verifies the source again and lists every text naming a release); the
  step then stops for the review.
- A clone of the gate repository at the kernel branch
  (`$MC_WORK/kernel-repo-<kernel>`, created or fetched): the branch check reads
  `origin/<kernel branch>` of it.
- `wrapper derive --check` compares the derived wrapper with the committed one;
  without one, `derive` writes it (commit it to photonos-scripts).
- `wrapper check` derives every profile and verifies each branch: the kernel
  directory, tarball and sha512, `Version`/`Release`, every patch file and the
  FIPS manifest.

### Step `prove_patches`

```bash
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
```

This step is a person's: before hours of build, the pin script of the derived
wrapper (the heredoc between `EMBEDPIN` markers) is run on a scratch checkout
of the kernel branch in the builder image, and `rpmbuild -bp` replays `%prep`
of the pinned specs with each canister phase's macros. Every patch must apply
at `--fuzz=0`. In the 2026-10 run one hunk of the FIPS canister-creation patch
did not (culprit 5); it was ported by hand on the branch and the replay
repeated. The 2026-10 commands, for reference:

```sh
docker run --rm --network none -v <scratch tree>:<scratch tree> -w <scratch tree> \
  -e CANISTER_MODE=equivalent-a ... sharukhan/photon-builder:<tag> sh -c 'set -eu; . /pins.sh'
rpmbuild -bp --nodeps -D "_sourcedir /src" -D "photon_subrelease 92" -D "dist .ph5" \
  -D "canister_build 1" -D "canister_stamp_real 1" -D "fips_certified_override 7.3.0-1.ph5" linux.spec
```

### Step `variant_patches`

```bash
variant_patches() {
    run "$SHARUKHAN" variant-patches --kernel "$KERNEL"
}
```

Assembles each installer variant's PR branches on the kernel branch and writes
the patches to `$MC_VARIANT_PATCH_DIR/k<kernel>/`. A PR whose range changes
only kernel spec directories is left out and named: under a kernel profile the
profile owns those files. *Example output (2026-10):*
`fix/linux-esx-depmod-ghost: left out - it changes 638 kernel file(s)`, the
tip of the kernel PR stack.

### Step `build_iso`

```bash
build_iso() {
    detach build_iso "$SHARUKHAN" build-iso --kernel "$KERNEL" --iso-type "$ISO_TYPE" \
        --poi "$POI" --canister "$CANISTER" --allow-build
}
```

Runs `sharukhan build-iso --kernel <release> --iso-type <type> --poi
<variant> --canister <mode> --allow-build` detached. The build runs in the
kernel's own root `$MC_WORK/kbuild/<kernel>`: for `equivalent`, phase A builds
the toolchain and `linux` with its canister, phase B relinks both flavours
against it and builds the image. The ISO goes to the store and is linked from
the kernel's ISO cache.

### Step `boot_test`

```bash
boot_test() {
    detach boot_test "$SHARUKHAN" run --kernel "$KERNEL" --only "$ROWS" --allow-build
}
```

`sharukhan run --kernel <release> --only <rows> --allow-build`, detached: each
row is installed into a fresh VM and verified, against the profile's kernel
(`meta.kernel`, `guest.kernel_release`) and, on a STIG row, its canister
(`guest.fips_canister`, `guest.canister_based_on`).

### Step `verify_media`

```bash
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
```

- The ISO is the cache's `photon.iso` link, or `ISO=<file>`; its sha256 must be
  the one the build recorded in `photon.iso.sha256`.
- `poi-nevr.txt` is the installer read off the media when it was built.
- `bsdtar -tf` lists the media; `linux` and `linux-esx` of the profile's
  `Version-Release` must be on it.
- For `equivalent`, the canister package must exist in the kernel's build root:
  it is linked into the kernel, not shipped on the media.

### Step `report`

```bash
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
```

For each row, the newest checks file: how many checks, which failed, and the
kernel and canister checks. *Example output (2026-10):*

```
k13: 44 checks, 0 fail
  meta.kernel = 7.3 (7.3.0-1.ph5)
  guest.kernel_release = 7.3.0-1.ph5-esx
  guest.fips_canister = 0
k15: 46 checks, 0 fail
  meta.kernel = 7.3 (7.3.0-1.ph5)
  guest.kernel_release = 7.3.0-1.ph5-esx
  guest.fips_canister = 1
  guest.canister_based_on = 7.3.0-1.ph5
```

### The command line

```bash
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
```

- Options: `--dry-run`, `--step <name>` (one step), `--from <name>` (from a
  step to the end; `preflight` and `settings` always run), `--list`, `--help`.
- `KERNEL`, `CANISTER`, `ISO_TYPE` and the step names are checked before
  anything runs.
- The settings file is sourced with `set -a` (every assignment exported), then
  `eval "$(sharukhan settings)"` sets every effective value - including
  defaults the file does not repeat.
- `POI` must be a variant `sharukhan variants` knows.
- The kernel's branch, wrapper and RPM version come from `identity`; `ROWS`
  from `derive_rows` when not given.

---

[← sharukhan overview](../../README.md)
