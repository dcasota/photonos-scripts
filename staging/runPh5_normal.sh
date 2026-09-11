#!/bin/sh

# Photon OS 5.0 build script using upstream defaults (non-SPECS/91)
#
# Unlike runPh5.sh which pins photon-subrelease to 91 (activating
# SPECS/91/ gated specs), this script uses the upstream subrelease
# so that the standard SPECS/ directory specs are active.
#
# Parameters with defaults:
# $1 - Base directory (default: /root)
# $2 - Common branch name (default: common)
# $3 - Release branch name (default: 5.0)
# $4 - Output directory (default: /mnt/c/Users/dcaso/Downloads/Ph-Builds)
# $5 - Image type (default: minimal-iso; pass "iso" for the full ISO)
# $6 - FIPS canister mode (default: prebuilt; build|acvp|kat)

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-5.0}"
OUTPUT_DIR="${4:-/mnt/c/Users/dcaso/Downloads/Ph-Builds}"

# ── Image type: minimal ISO by default ────────────────────────────────
# $5 selects what `make image` builds. The two main types differ in far
# more than size, and the difference has bitten us:
#   iso          poi.py create_full_iso() passes --rpms-list-file, so
#                isoBuilder takes the copyPkgs() path and copies EVERY
#                built RPM onto the ISO (~4.6 GB). Anything the installer
#                may ask for later -- notably the STIG hardening package
#                set -- is therefore present.
#   minimal-iso  poi.py create_custom_iso() omits --rpms-list-file, so
#                isoBuilder falls through to downloadPkgs() and ships only
#                the dependency closure of common/data/packages_minimal.json
#                (~507 MB). Selecting "Apply STIG hardening" in the
#                installer then fails with Error(1011) -- the ISO carries no
#                selinux-policy, libselinux-utils, rsyslog, aide or
#                openssl-fips-provider.
# Note also that build.py relocates only the FULL iso from stage/iso/ to
# stage/; a minimal ISO stays in stage/minimal-iso/ (the ISO search below
# handles both).
IMG_TYPE="${5:-minimal-iso}"
case "$IMG_TYPE" in
  iso|minimal-iso|basic-iso|rt-iso) ;;
  *)
    echo "[runPh5_normal] ERROR: unsupported image type '$IMG_TYPE'" 1>&2
    echo "[runPh5_normal]        valid: iso (full), minimal-iso (default), basic-iso, rt-iso" 1>&2
    exit 1
    ;;
esac
echo "[runPh5_normal] Image type: $IMG_TYPE"

# ── FIPS canister mode ────────────────────────────────────────────────
# $6 selects how the FIPS crypto canister is handled by SPECS/linux.
# On x86_64 linux.spec sets "%global fips 1" unguarded, so FIPS itself
# cannot be turned off from outside; canister_usage is derived
# (canister_usage = !canister_build when fips=1) and per linux.spec:40
# cannot be set directly. The externally settable macros are therefore
# canister_build, acvp_build and kat_build:
#   prebuilt  (default) link the prebuilt canister object -> canister_usage=1
#   build     canister_build=1, build the canister from source
#   acvp      acvp_build=1, FIPS-certification build (forces fips=1)
#   kat       kat_build=1, non-production KAT build (forces acvp+canister_build)
#
# Two further modes implement the equivalent-canister workflow. They are two
# INVOCATIONS of this script, not one, because the produce and consume paths
# are mutually exclusive inside a single build: canister_build=1 forces
# canister_usage=0, so the build that creates a canister links none.
#
#   equivalent-a  canister_build=1 on linux only, target "linux" rather than an
#                 image. Produces linux-fips-canister-$MC_CANISTER_NEVR.rpm.
#   equivalent-b  canister_equivalent=1 + fips_canister_override on BOTH
#                 flavours, target image. linux-esx is the kernel the ISO
#                 boots and it never builds a canister - it only links one - so
#                 leaving it out would ship a kernel still bound to the
#                 published pin.
#
# Both need MC_CANISTER_NEVR (e.g. 6.12.103-14.ph5).
CANISTER_MODE="${6:-prebuilt}"
case "$CANISTER_MODE" in
  prebuilt|build|acvp|kat) ;;
  equivalent-a|equivalent-b)
    if [ -z "${MC_CANISTER_NEVR:-}" ]; then
      echo "[runPh5_normal] ERROR: $CANISTER_MODE needs MC_CANISTER_NEVR" 1>&2
      echo "[runPh5_normal]        (the NEVR the locally built canister carries)" 1>&2
      exit 1
    fi
    ;;
  *)
    echo "[runPh5_normal] ERROR: unsupported canister mode '$CANISTER_MODE'" 1>&2
    echo "[runPh5_normal]        valid: prebuilt (default), build, acvp, kat," 1>&2
    echo "[runPh5_normal]               equivalent-a, equivalent-b" 1>&2
    exit 1
    ;;
esac
echo "[runPh5_normal] Canister mode: $CANISTER_MODE"

# Phase A builds one package, not an image; everything downstream that hunts
# for an ISO is skipped for it.
if [ "$CANISTER_MODE" = "equivalent-a" ]; then
  MC_MAKE_TARGET="linux"
else
  MC_MAKE_TARGET="image"
fi

# Directory containing this script, used to locate the bundled downstream
# patch set (staging/photonos-patches/). Resolved before any cd.
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

sleep 3
if ping -c 4 www.google.ch > /dev/null 2>&1; then
  # ── Keep both worktrees in lockstep with origin ───────────────────
  # The common and release branches are two halves of one build tree:
  # common/ holds the build tooling (spec generator, kernel-deps.json),
  # $RELEASE_BRANCH/ holds the SPECS it drives. If one advances and the
  # other does not, the build fails in confusing ways -- e.g. common's
  # kernel-deps.json listing sysdig/falco/kernels-drivers-intel while the
  # release tree still has no matching *.spec.in templates, which makes
  # create-kernel-deps-specs-from-template.py die with
  # "TypeError: expected str, bytes or os.PathLike object, not NoneType".
  #
  # A shallow fetch (e.g. a prior "git fetch --depth=1") grafts the remote
  # history and makes "git merge" abort with "refusing to merge unrelated
  # histories" -- silently, when the exit code is thrown away. Unshallow
  # first, then merge, and make any failure loud.
  sync_repo() {
    repo_dir="$1"; branch="$2"
    cd "$repo_dir" || return 1
    if [ "$(git rev-parse --is-shallow-repository 2>/dev/null)" = "true" ]; then
      echo "[runPh5_normal] $branch: repository is shallow, unshallowing ..."
      git fetch --unshallow origin || echo "[runPh5_normal] WARNING: $branch: --unshallow failed"
    fi
    if ! git fetch origin; then
      echo "[runPh5_normal] WARNING: $branch: git fetch failed (building against local state)"
      return 0
    fi
    behind=$(git rev-list --count "HEAD..origin/$branch" 2>/dev/null)
    [ -n "$behind" ] && [ "$behind" != "0" ] && \
      echo "[runPh5_normal] $branch: $behind commit(s) behind origin/$branch, merging ..."
    if ! git merge --autostash "origin/$branch"; then
      git merge --abort 2>/dev/null
      echo "[runPh5_normal] ERROR: $branch: cannot merge origin/$branch." 1>&2
      echo "[runPh5_normal]        Resolve this first -- a $COMMON_BRANCH/$RELEASE_BRANCH" 1>&2
      echo "[runPh5_normal]        version skew breaks the spec generator." 1>&2
      return 1
    fi
    return 0
  }

  if [ ! -d "$BASE_DIR/$COMMON_BRANCH" ]; then
    git clone https://github.com/dcasota/photon.git -b "$COMMON_BRANCH" "$BASE_DIR/$COMMON_BRANCH"
  fi
  sync_repo "$BASE_DIR/$COMMON_BRANCH" "$COMMON_BRANCH" || exit 1
  cd "$BASE_DIR"
  if [ ! -d "$BASE_DIR/$RELEASE_BRANCH" ]; then
    git clone https://github.com/dcasota/photon.git -b "$RELEASE_BRANCH" "$BASE_DIR/$RELEASE_BRANCH"
  fi
  sync_repo "$BASE_DIR/$RELEASE_BRANCH" "$RELEASE_BRANCH" || exit 1

  # ── Use upstream subrelease (non-SPECS/91) ────────────────────────
  # Do NOT pin subrelease to 91. Restore upstream values so the build
  # system uses standard SPECS/ instead of SPECS/91/ gated specs.
  git checkout -- build-config.json 2>/dev/null

  # ── Restore ALL files that may have been modified by prior runs ────
  # A prior runPh5_pinned91.sh (or failed normal) run may have altered
  # specs, data files, etc. Restore every dirty tracked file to upstream.
  dirty_files=$(git diff --name-only 2>/dev/null)
  if [ -n "$dirty_files" ]; then
    echo "$dirty_files" | while read -r f; do
      git checkout -- "$f" 2>/dev/null && echo "[runPh5_normal] Restored $f to upstream"
    done
  fi

  # ── Apply downstream fixes / PRs (installer + packages) ───────────
  # Re-applied here so they survive the restore above. Covers:
  #   photon-os-installer 2.8-5 : interactive (no-kickstart) UI install fix,
  #       btrfs-progs on btrfs partitions, tdnf output capture so package
  #       install no longer overlays the curses UI, KS_STIG_PACKAGES reduced to
  #       the five that are actually needed, and /etc/locale.conf seeded before
  #       package install so dracut stops reporting "i18n_vars not set".
  #   aide 0.19-3               : versioned Requires: libgcrypt >= 1.10.4 (91+)
  #   stig-hardening 2.1-9      : SELinux first-boot relabel + fips PAM (PR #9)
  #   linux 6.12.103-11 /
  #   linux-esx 6.12.103-10     : canister/.config handling moved into the
  #       shared canister_config.inc, fixing the fips=0 (aarch64) path (PR #24,
  #       supersedes the standalone PR #14)
  #   systemd 257.13-7          : drop the dangling accel/render udev rule,
  #       restore the systemd-journal sysusers entry the initrd needs, pin
  #       -Dsystemd-journal-gid=23, ship harden-tmpfs-mount-options.patch and
  #       auto-number the patch list (PR #22)
  #   8 STIG_HARDEN specs       : define-if-unset so the flag is settable (PR #23)
  # (nginx PR #17 is intentionally NOT included: 5.0 already ships nginx
  #  1.30.4, newer than the PR's 1.30.1, so it would be a downgrade.)
  DOWNSTREAM_PATCH=""
  for cand in "$SCRIPT_DIR/photonos-patches/downstream-fixes.patch" \
              "$BASE_DIR/photonos-patches/downstream-fixes.patch"; do
    [ -f "$cand" ] && DOWNSTREAM_PATCH="$cand" && break
  done
  if [ -n "$DOWNSTREAM_PATCH" ]; then
    # Files the patch *creates* survive the "git checkout --" restore above
    # (they are untracked), and "git apply" then refuses the whole patch with
    # "already exists in working directory" -- which used to be swallowed as a
    # warning, so the build silently shipped without any downstream fix.
    # Drop those leftovers first; the patch recreates them verbatim.
    git apply --summary "$DOWNSTREAM_PATCH" 2>/dev/null |
      sed -n 's/^ *create mode [0-9]* //p' | while read -r nf; do
        [ -f "$nf" ] || continue
        git ls-files --error-unmatch "$nf" >/dev/null 2>&1 && continue
        rm -f "$nf"
      done
    if git apply "$DOWNSTREAM_PATCH"; then
      echo "[runPh5_normal] Applied downstream-fixes.patch"
    else
      echo "[runPh5_normal] ERROR: downstream-fixes.patch does not apply to the" 1>&2
      echo "[runPh5_normal]        current $RELEASE_BRANCH tree. Rebase it (the specs it" 1>&2
      echo "[runPh5_normal]        touches moved on upstream) -- building without it" 1>&2
      echo "[runPh5_normal]        would drop the POI, stig-hardening and linux fixes." 1>&2
      exit 1
    fi
  else
    echo "[runPh5_normal] NOTE: photonos-patches/downstream-fixes.patch not found; building without downstream fixes"
  fi

  # ---- the COMMON tree ------------------------------------------------------
  # The release tree and the common tree are different branch lines of the same
  # repository: common has no SPECS/, the release branches have no
  # support/package-builder/. downstream-fixes.patch therefore CANNOT carry a
  # change to the build tooling, and until common-fixes.patch existed such a
  # change reached a build only by being present in whatever this checkout
  # happened to be sitting on. That is how --canister equivalent came to depend
  # on an operator's working tree: a fresh clone (-b common, above) does not
  # contain the sans-snapshot fix, and the build dies two hours in with
  #     linux-fips-canister-<nevr> package not found or not installed
  # for an RPM that is present and indexed.
  COMMON_PATCH=""
  for cand in "$SCRIPT_DIR/photonos-patches/common-fixes.patch" \
              "$BASE_DIR/photonos-patches/common-fixes.patch"; do
    [ -f "$cand" ] && COMMON_PATCH="$cand" && break
  done
  if [ -n "$COMMON_PATCH" ]; then
    (
      cd "$BASE_DIR/$COMMON_BRANCH" || exit 1
      # Reset ONLY the files this patch touches. A blanket "git checkout -- ."
      # here would destroy build-config.json and run-in-chroot.sh, which are
      # ambient host configuration rather than build artifacts -- unlike SPECS/,
      # where everything is reproduced by the patch.
      git apply --numstat "$COMMON_PATCH" 2>/dev/null | awk '{print $3}' | while read -r f; do
        [ -n "$f" ] || continue
        git ls-files --error-unmatch "$f" >/dev/null 2>&1 && git checkout -- "$f" 2>/dev/null
      done
      if git apply --check "$COMMON_PATCH" 2>/dev/null; then
        git apply "$COMMON_PATCH" && \
          echo "[runPh5_normal] Applied common-fixes.patch to $COMMON_BRANCH"
      elif git apply --reverse --check "$COMMON_PATCH" 2>/dev/null; then
        # Already applied - the merge in sync_repo may have brought it in.
        echo "[runPh5_normal] common-fixes.patch already present in $COMMON_BRANCH"
      else
        echo "[runPh5_normal] ERROR: common-fixes.patch does not apply to the" 1>&2
        echo "[runPh5_normal]        current $COMMON_BRANCH tree, and is not already" 1>&2
        echo "[runPh5_normal]        applied. Regenerate it (sharukhan variant-patches)." 1>&2
        exit 1
      fi
    ) || exit 1
  else
    echo "[runPh5_normal] NOTE: no common-fixes.patch; $COMMON_BRANCH used as checked out"
  fi

  UPSTREAM_SUB=$(python3 -c "
import json
cfg = json.load(open('build-config.json'))
print(cfg['photon-build-param']['photon-subrelease'])
" 2>/dev/null)
  UPSTREAM_MAIN=$(python3 -c "
import json
cfg = json.load(open('build-config.json'))
print(cfg['photon-build-param'].get('photon-mainline', cfg['photon-build-param']['photon-subrelease']))
" 2>/dev/null)
  echo "[runPh5_normal] Using upstream photon-subrelease: ${UPSTREAM_SUB} (mainline: ${UPSTREAM_MAIN})"

  # ── Ensure the photon/installer (POI) image exists ────────────────
  # `make image` (poi.py) needs a photon/installer docker image, which is not
  # on any public registry. Build it locally if missing, using the legacy
  # builder (DOCKER_BUILDKIT=0, since buildx may be absent) and the multi-file
  # COPY trailing-slash fix the legacy builder requires (merged upstream as
  # PR #38; the sed below is kept for older checkouts that predate it). The image is only the ISO build tool; the installer that ships
  # inside the ISO comes from the patched photon-os-installer RPM built above.
  # The image must also contain `file`. photon_installer/generate_initrd.py's
  # strip_if_needed() runs subprocess.check_output(["file", path]) on every
  # file it puts in the initrd, but the upstream Dockerfile never installs it,
  # so ISO assembly dies with
  #   FileNotFoundError: [Errno 2] No such file or directory: 'file'
  # in generateInitrd() -- *after* all 250 packages have been built, and the
  # retry loop below then burns all 10 attempts on it. Check the image for
  # `file` up front, add it to the Dockerfile package list, and rebuild any
  # older image that predates the fix.
  poi_image_ok() {
    docker image inspect photon/installer:latest >/dev/null 2>&1 || return 1
    docker run --rm --entrypoint /bin/sh photon/installer:latest \
      -c 'command -v file >/dev/null' >/dev/null 2>&1
  }
  if ! poi_image_ok; then
    POI_SRC="$BASE_DIR/photon-os-installer"
    [ -d "$POI_SRC/.git" ] || git clone https://github.com/dcasota/photon-os-installer.git "$POI_SRC" 2>/dev/null
    if [ -d "$POI_SRC/docker" ]; then
      ( cd "$POI_SRC"
        # multi-file 'COPY ... /usr/bin' needs a trailing slash for legacy build
        sed -i 's#^\([[:space:]]*\)/usr/bin$#\1/usr/bin/#' docker/Dockerfile
        # initrd generation shells out to `file`. Upstream added it to the
        # package list (on the 'binutils file xorriso' line) after v2.9, so
        # match a standalone 'file' token in ANY position rather than one
        # exact line -- checking only for our own edit shape would add a
        # duplicate on a fresh clone of master. '(^|space)file(space|eol)'
        # deliberately does not match 'Dockerfile' or 'multi-file'.
        grep -qE '(^|[[:space:]])file([[:space:]]|$)' docker/Dockerfile || \
          sed -i 's|^    zlib tar \\$|    file zlib tar \\|' docker/Dockerfile
        DOCKER_BUILDKIT=0 docker build -t photon/installer:latest -f docker/Dockerfile docker/ ) \
        && echo "[runPh5_normal] Built photon/installer:latest" \
        || echo "[runPh5_normal] WARNING: failed to build photon/installer image"
    fi
    if ! poi_image_ok; then
      echo "[runPh5_normal] ERROR: photon/installer:latest is missing or has no 'file'" 1>&2
      echo "[runPh5_normal]        binary. ISO assembly would fail in generateInitrd()" 1>&2
      echo "[runPh5_normal]        after every package has been rebuilt -- aborting now." 1>&2
      exit 1
    fi
  fi

  # ── Point the build at the local POI image ────────────────────────

  # ── Per-package build options: FIPS canister macros ───────────────
  # build.py loads this via Builder.get_packages_with_build_options(), which is
  # guarded by os.path.exists() -- a path that does not resolve is SILENTLY
  # ignored, and the build then links the prebuilt canister while reporting
  # success. That is exactly how the first c01 attempt burned 3.5h.
  #
  # The value in build-config.json must be a BARE FILENAME, because
  # set_default_value_of_config() (build.py:1720) rewrites it unconditionally:
  #
  #     ret = f"{curDir}/common/data/" + configdict[key]["pkg-build-options"]
  #
  # so an absolute path becomes /root/common/common/data//root/<file> and never
  # exists. Write the generated file into $COMMON_BRANCH/common/data/ under a
  # name of our own, so the tracked pkg_build_options.json is left alone. The
  # name deliberately does not match the packages_*.json glob build.py uses at
  # line 296. Cleaned up by the trap below.
  PKG_BUILD_OPTIONS_NAME="mc_pkg_build_options.json"
  PKG_BUILD_OPTIONS_DIR="$BASE_DIR/$COMMON_BRANCH/common/data"
  PKG_BUILD_OPTIONS="$PKG_BUILD_OPTIONS_DIR/$PKG_BUILD_OPTIONS_NAME"
  if [ ! -d "$PKG_BUILD_OPTIONS_DIR" ]; then
    echo "[runPh5_normal] ERROR: $PKG_BUILD_OPTIONS_DIR does not exist;" 1>&2
    echo "[runPh5_normal]        build.py resolves pkg-build-options there." 1>&2
    exit 1
  fi
  python3 -c "
import json, sys
mode, out, nevr = sys.argv[1], sys.argv[2], sys.argv[3]
both = ('linux', 'linux-esx')
if mode == 'equivalent-a':
    # Only linux can create a canister; linux-esx hardcodes canister_build 0.
    # Giving linux-esx these macros would be a lie about what it does.
    # canister_stamp_real makes the new canister record the kernel it was
    # really built from rather than inherit 6.12.60's certification.
    opts = {'linux': {'pullsources': [], 'macros': [
        'canister_build 1', 'canister_stamp_real 1',
        f'fips_certified_override {nevr}']}}
elif mode == 'equivalent-b':
    m = ['canister_equivalent 1', f'fips_canister_override {nevr}']
    opts = {p: {'pullsources': [], 'macros': list(m)} for p in both}
else:
    macros = {'prebuilt': [], 'build': ['canister_build 1'],
              'acvp': ['acvp_build 1'], 'kat': ['kat_build 1']}[mode]
    opts = {p: {'pullsources': [], 'macros': list(macros)} for p in both}
with open(out, 'w') as f:
    json.dump(opts, f, indent=4)
print('  ' + json.dumps(opts))
" "$CANISTER_MODE" "$PKG_BUILD_OPTIONS" "${MC_CANISTER_NEVR:-}" && \
    echo "[runPh5_normal] Canister macros ($CANISTER_MODE) -> $PKG_BUILD_OPTIONS"

  COMMON_CFG="$BASE_DIR/$COMMON_BRANCH/build-config.json"
  # Point build.py at the generated options file, by bare name (see above).
  if [ -f "$COMMON_CFG" ]; then
    python3 -c "
import json
with open('$COMMON_CFG') as f:
    cfg = json.load(f)
cfg.setdefault('photon-build-param', {})['pkg-build-options'] = '$PKG_BUILD_OPTIONS_NAME'
with open('$COMMON_CFG', 'w') as f:
    json.dump(cfg, f, indent=4)
" 2>/dev/null && echo "[runPh5_normal] pkg-build-options -> $PKG_BUILD_OPTIONS_NAME (resolved under common/data/)"
    # Prove the path build.py will actually open, rather than trusting it.
    python3 -c "
import json, os, sys
cfg = json.load(open('$COMMON_CFG'))
name = cfg['photon-build-param']['pkg-build-options']
resolved = os.path.join('$BASE_DIR/$COMMON_BRANCH', 'common', 'data', name)
if not os.path.exists(resolved):
    sys.exit('[runPh5_normal] ERROR: build.py would open %s, which does not exist' % resolved)
opts = json.load(open(resolved))
mode, nevr = '$CANISTER_MODE', '${MC_CANISTER_NEVR:-}'
if mode == 'equivalent-a':
    want = ['canister_build 1', 'canister_stamp_real 1',
            'fips_certified_override ' + nevr]
elif mode == 'equivalent-b':
    want = ['canister_equivalent 1', 'fips_canister_override ' + nevr]
else:
    want = {'prebuilt': [], 'build': ['canister_build 1'],
            'acvp': ['acvp_build 1'], 'kat': ['kat_build 1']}[mode]
if opts.get('linux', {}).get('macros') != want:
    sys.exit('[runPh5_normal] ERROR: %s carries %r, expected %r'
             % (resolved, opts.get('linux', {}).get('macros'), want))
# Phase B must reach linux-esx too: it is the kernel the ISO boots, and it
# links the canister rather than building one. A phase B that overrode only
# linux would ship a kernel still bound to the published pin while reporting
# success - the exact shape of failure this whole mode exists to avoid.
if mode == 'equivalent-b' and opts.get('linux-esx', {}).get('macros') != want:
    sys.exit('[runPh5_normal] ERROR: %s does not override linux-esx: %r'
             % (resolved, opts.get('linux-esx', {}).get('macros')))
print('[runPh5_normal] verified: build.py will apply %r to linux' % (want,))
" || exit 1
  fi
  if [ -f "$COMMON_CFG" ]; then
    POI_SET=$(python3 -c "
import json
cfg = json.load(open('$COMMON_CFG'))
print(cfg.get('photon-build-param',{}).get('poi-image',''))
" 2>/dev/null)
    if [ -z "$POI_SET" ] && docker image inspect photon/installer:latest >/dev/null 2>&1; then
      python3 -c "
import json
with open('$COMMON_CFG') as f:
    cfg = json.load(f)
cfg['photon-build-param']['poi-image'] = 'photon/installer:latest'
with open('$COMMON_CFG', 'w') as f:
    json.dump(cfg, f, indent=4)
" 2>/dev/null && echo "[runPh5_normal] Set poi-image to local photon/installer:latest"
    fi
  fi

  # ── Fix spec formatting errors caught by spec checker ─────────────
  # Remove consecutive blank lines in SPECS/91/python3-setuptools if present.
  # The spec checker rejects "multiple empty lines" as a formatting error.
  for spec in SPECS/91/python3-setuptools/python3-setuptools.spec; do
    if [ -f "$spec" ] && awk 'prev=="" && /^$/{found=1} {prev=$0} END{exit !found}' "$spec" 2>/dev/null; then
      sed -i '/^$/N;/^\n$/d' "$spec"
      echo "[runPh5_normal] Fixed consecutive blank lines in $spec"
    fi
  done

  # ── Fix OpenJDK WSL2 detection in chroot ───────────────────────────
  # OpenJDK's configure detects "x86_64-pc-wsl" inside WSL2 chroots and
  # fails with "Incorrect wsl1 installation". Adding --build= overrides
  # the auto-detected triplet. Only applied if the flag is missing.
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    for jdk_spec in SPECS/openjdk/openjdk*.spec "$BASE_DIR/$COMMON_BRANCH"/SPECS/openjdk/openjdk*.spec; do
      [ -f "$jdk_spec" ] || continue
      if grep -q 'sh ./configure' "$jdk_spec" && ! grep -q 'build=x86_64-unknown-linux-gnu' "$jdk_spec"; then
        sed -i 's|--disable-warnings-as-errors$|--disable-warnings-as-errors \\\n    --build=x86_64-unknown-linux-gnu|' "$jdk_spec"
        echo "[runPh5_normal] Fixed $(basename "$jdk_spec"): added --build for WSL2"
      fi
    done
  fi

  # ── Fix Python 3 PGO training failure ──────────────────────────────
  # python3 is built with --enable-optimizations, so make runs the PGO
  # training task (PROFILE_TASK). CPython 3.14 dropped the trailing
  # "|| true" from Makefile.pre.in's run_profile_task, so one failing test
  # now aborts %build outright:
  #   FAIL: test_generators.SignalAndYieldFromTest.test_raise_and_yield_from
  #   AssertionError: 'FAILED' != 'PASSED'
  #   make: *** [Makefile:1012: profile-run-stamp] Error 2
  # That test asserts a SIGINT arriving as a "yield from" chain is entered
  # raises KeyboardInterrupt in the innermost generator. It fails
  # reproducibly here and the root cause is NOT established -- the same C
  # mechanism (_testcapi.raise_SIGINT_then_send_None) passes 300/300 on this
  # kernel with the host python3.11, so the "WSL2 signal timing" explanation
  # does not hold. Excluding it is therefore a workaround, but a cheap one:
  # PROFILE_TASK only decides which tests generate *profile data*, so this
  # costs one test's worth of PGO training, not shipped correctness (%check
  # is separate and gated off by with_check).
  #
  # The exclusion is applied unconditionally rather than gated on WSL2,
  # since the cause is not known to be WSL-specific.
  #
  # IMPORTANT: PROFILE_TASK must be passed as a make *command-line* variable,
  # not as an environment variable. Makefile.pre.in contains a plain
  # "PROFILE_TASK= @PROFILE_TASK@" assignment, and a Makefile assignment always
  # beats the environment (only "make VAR=..." or "make -e" overrides it).
  # A "PROFILE_TASK=... %make_build" prefix is silently ignored -- the build
  # then trains on the stock 43-test PGO set and fails again.
  #
  # regrtest handles "--pgo -x test_generators" correctly: find_tests() moves
  # cmdline args into the exclude set *before* setup_pgo_tests() fills in the
  # default list, so the run is PGO_TESTS minus test_generators (42 of 43).
  PY3_SPEC="SPECS/python3/python3.spec"
  if [ -f "$PY3_SPEC" ] && ! grep -q 'PROFILE_TASK' "$PY3_SPEC"; then
    sed -i 's|^%make_build$|%make_build PROFILE_TASK="-m test --pgo -x test_generators"|' "$PY3_SPEC"
    echo "[runPh5_normal] Fixed python3 spec: excluded test_generators from PGO training"
  fi

  # ── Fix sssd %make_install parallel libtool race ───────────────
  # sssd 2.8.2 uses %make_install %{?_smp_mflags} which runs `make
  # install -jN`. With high j-count, libtool's relink phase races with
  # the install phase: it tries to relink _py3hbac.la / libsss_*.la
  # against libsss_child.la before libsss_child.la has been installed,
  # producing `file format not recognized` and `ld returned 1`.
  # Switch to serial install. Only patches if not already serialized.
  SSSD_SPEC="SPECS/sssd/sssd.spec"
  if [ -f "$SSSD_SPEC" ] && grep -q "%make_install %{?_smp_mflags}" "$SSSD_SPEC"; then
    sed -i 's|%make_install %{?_smp_mflags}|%make_install|' "$SSSD_SPEC"
    echo "[runPh5_normal] Fixed sssd spec: serial %make_install"
  fi

  # ── Fix run-in-chroot.sh: protect bash's script fd (255) ────────
  # The fd-closing loop closes ALL fds > 2, including fd 255 which
  # bash uses for reading the script file. This causes bash to
  # misparse continuation lines ("bin: command not found") and mark
  # successfully-built packages as failed. Skip fd 255.
  RIC="$BASE_DIR/$COMMON_BRANCH/support/package-builder/run-in-chroot.sh"
  if [ -f "$RIC" ] && grep -q '\[ \$fd -gt 2 \]' "$RIC" && ! grep -q '255' "$RIC"; then
    sed -i 's/\[ \$fd -gt 2 \] && exec/[ $fd -gt 2 ] \&\& [ $fd -ne 255 ] \&\& exec/' "$RIC"
    echo "[runPh5_normal] Fixed run-in-chroot.sh: skip fd 255 in fd-closing loop"
  fi

  # ── Pre-fetch / validate source archives ───────────────────────
  # New packages added to upstream may not yet be on the Broadcom
  # photon_sources mirror. Download directly from upstream if missing.
  # Also validate sha512 of cached archives: a corrupt cached file
  # (mismatched checksum) blocks the build with "Missing source"
  # because PullSources falls back to URL fetch which often fails.
  fetch_or_validate_source() {
    archive="$1"; url="$2"; expected_sha="$3"
    destdir="$BASE_DIR/$RELEASE_BRANCH/stage/SOURCES"
    backup_dir="$BASE_DIR/$COMMON_BRANCH/stage/SOURCES"
    target="$destdir/$archive"
    mkdir -p "$destdir"
    # If cached and checksum matches, nothing to do.
    if [ -f "$target" ] && [ -n "$expected_sha" ]; then
      actual=$(sha512sum "$target" 2>/dev/null | awk '{print $1}')
      if [ "$actual" = "$expected_sha" ]; then
        return 0
      fi
      echo "[runPh5_normal] sha512 mismatch for $archive (cached: ${actual:0:12}…, expected: ${expected_sha:0:12}…)"
      # Try recovering from the common branch's cache (often correct).
      if [ -f "$backup_dir/$archive" ]; then
        backup_sha=$(sha512sum "$backup_dir/$archive" 2>/dev/null | awk '{print $1}')
        if [ "$backup_sha" = "$expected_sha" ]; then
          cp -f "$backup_dir/$archive" "$target"
          echo "[runPh5_normal] Restored $archive from $backup_dir"
          return 0
        fi
      fi
      # Otherwise drop the bad copy so we redownload below.
      rm -f "$target"
    elif [ -f "$target" ]; then
      return 0  # cached, no checksum to validate against
    fi
    # Build the list of candidate URLs. The spec's url often points at
    # invisible-island.net/.../current/, which 404s once a dated snapshot
    # is superseded (e.g. ncurses-6.5-20250816.tgz). The Broadcom
    # photon_sources mirror keeps every historical archive, so try it too.
    BCOM_MIRROR="https://packages.broadcom.com/photon/photon_sources/1.0/$archive"
    for src_url in "$url" "$BCOM_MIRROR"; do
      [ -z "$src_url" ] && continue
      echo "[runPh5_normal] Fetching source: $archive <- $src_url"
      # Download to a temp file: wget -O truncates the target to 0 bytes
      # before the request, so a 404/network failure would otherwise leave
      # an empty file that poisons the SOURCES cache.
      if wget -q "$src_url" -O "$target.tmp" 2>/dev/null && [ -s "$target.tmp" ]; then
        if [ -n "$expected_sha" ]; then
          dl_sha=$(sha512sum "$target.tmp" 2>/dev/null | awk '{print $1}')
          if [ "$dl_sha" != "$expected_sha" ]; then
            echo "[runPh5_normal] WARNING: checksum mismatch for fetched $archive (got ${dl_sha:0:12}…), discarding"
            rm -f "$target.tmp"
            continue
          fi
        fi
        mv -f "$target.tmp" "$target"
        return 0
      fi
      rm -f "$target.tmp"
    done
    echo "[runPh5_normal] WARNING: Failed to fetch $archive from any source"
    return 1
  }

  # Parse config.yaml files and fetch/validate every declared source.
  find "$BASE_DIR/$RELEASE_BRANCH/SPECS" -name config.yaml -print0 2>/dev/null | while IFS= read -r -d '' cfg; do
    python3 -c "
import yaml
with open('$cfg') as f:
    data = yaml.safe_load(f) or {}
for s in data.get('sources', []) or []:
    a = s.get('archive', '') or ''
    u = s.get('url', '') or ''
    h = s.get('archive_sha512sum', '') or ''
    if a:
        print(a + '|' + u + '|' + h)
" 2>/dev/null | while IFS='|' read -r archive url sha; do
      fetch_or_validate_source "$archive" "$url" "$sha"
    done
  done

  # ── Fix sandbox bootstrap: remove rpm 6.x and stale libcap RPMs ──
  # rpm-libs 6.0.1 requires libcap-libs (split from libcap >= 2.77). If
  # the local repo holds libcap 2.66 (from a prior pinned91 run) the
  # libcap-libs requirement can't be satisfied and the toolchain install
  # fails. Remove rpm 6.x and stale libcap-2.66 RPMs to let tdnf bootstrap
  # with rpm 4.x; libcap 2.77 (with libcap-libs split) and rpm 6.x will
  # then be built as regular packages in the right order.
  RPMSDIR="$BASE_DIR/$RELEASE_BRANCH/stage/RPMS/x86_64"
  if ls "$RPMSDIR"/rpm-build-6.*.rpm >/dev/null 2>&1 || \
     ls "$RPMSDIR"/rpm-libs-6.*.rpm >/dev/null 2>&1; then
    echo "[runPh5_normal] Removing rpm 6.x RPMs (toolchain bootstrap requires rpm 4.x)"
    rm -f "$RPMSDIR"/rpm-6.*.rpm "$RPMSDIR"/rpm-build-6.*.rpm \
          "$RPMSDIR"/rpm-build-libs-6.*.rpm "$RPMSDIR"/rpm-libs-6.*.rpm \
          "$RPMSDIR"/rpm-devel-6.*.rpm "$RPMSDIR"/rpm-lang-6.*.rpm \
          "$RPMSDIR"/rpm-sign-libs-6.*.rpm "$RPMSDIR"/rpm-debuginfo-6.*.rpm \
          "$RPMSDIR"/rpm-plugin-systemd-inhibit-6.*.rpm \
          "$RPMSDIR"/rpm-sequoia-*.rpm
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/images/sandboxBase"
  fi
  # Remove stale libcap-2.66 (from pinned91 builds) so libcap 2.77 with
  # the libcap-libs split rebuilds cleanly. Don't touch libcap-ng (separate
  # package).
  if ls "$RPMSDIR"/libcap-2.66*.rpm >/dev/null 2>&1; then
    echo "[runPh5_normal] Removing stale libcap-2.66 RPMs to force rebuild to 2.77"
    rm -f "$RPMSDIR"/libcap-2.66*.rpm "$RPMSDIR"/libcap-debuginfo-2.66*.rpm \
          "$RPMSDIR"/libcap-devel-2.66*.rpm "$RPMSDIR"/libcap-doc-2.66*.rpm
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/images/sandboxBase"
  fi

  # ── Determine the real stage path ───────────────────────────────
  # `make` runs in the release worktree and resolves "stage-path" from that
  # worktree's own build-config.json ("./stage"), so RPMS, SRPMS, LOGS and the
  # chroot sandboxes all land in $RELEASE_BRANCH/stage -- even though build.py
  # itself lives in $COMMON_BRANCH. This used to be hardcoded to
  # $COMMON_BRANCH/stage, which is an empty directory, so every cleanup helper
  # below silently did nothing: stale sandboxes were never unmounted or
  # removed (a failed run's photonroot/<pkg> survived the "Retry N: cleaning
  # stale sandboxes" message) and corrupted RPMs were never detected.
  BUILD_STAGE=$(cd "$BASE_DIR/$RELEASE_BRANCH" 2>/dev/null && \
    realpath "$(jq -r '.["stage-path"] // "./stage"' build-config.json 2>/dev/null)" 2>/dev/null)
  [ -d "$BUILD_STAGE" ] || BUILD_STAGE="$BASE_DIR/$RELEASE_BRANCH/stage"
  COMMON_STAGE="$BASE_DIR/$COMMON_BRANCH/stage"
  echo "[runPh5_normal] Build stage: $BUILD_STAGE"

  # ── Drop stale RPMs that would shadow a freshly patched build ─────
  # tdnf resolves by highest VERSION-RELEASE, not by build time. The
  # downstream patch currently produces photon-os-installer 2.8-3, but an
  # older revision of that same patch once produced 2.8-4 and 2.8-5 (built
  # 2026-06-04). Those stale RPMs sat in the stage repo and silently won:
  # the ISO shipped the June installer, not the freshly patched one. The
  # payloads happened to match that time, so nothing broke -- but any future
  # change to the patch set would have been invisible on the media.
  # For each spec the downstream patch touches, drop RPMs with the same
  # NAME-VERSION but a HIGHER release than the spec now declares.
  for _pkg in photon-os-installer stig-hardening linux; do
    _spec="SPECS/$_pkg/$_pkg.spec"
    [ -f "$_spec" ] || continue
    _ver=$(awk '/^Version:/{print $2; exit}' "$_spec")
    _rel=$(awk '/^Release:/{print $2; exit}' "$_spec" | sed 's/%.*//')
    # skip if either still contains an unexpanded rpm macro
    case "$_ver$_rel" in *%*|"") continue ;; esac
    case "$_rel" in *[!0-9]*) continue ;; esac
    for _r in "$BUILD_STAGE"/RPMS/*/"$_pkg"-"$_ver"-*.rpm; do
      [ -f "$_r" ] || continue
      _rrel=$(rpm -qp --qf '%{RELEASE}' "$_r" 2>/dev/null | sed 's/\.ph[0-9]*$//')
      case "$_rrel" in ''|*[!0-9]*) continue ;; esac
      if [ "$_rrel" -gt "$_rel" ]; then
        echo "[runPh5_normal] Removing stale $(basename "$_r") -- release $_rrel shadows patched $_rel"
        rm -f "$_r"
      fi
    done
  done

  # ── Helper: clean stale chroot mounts and sandbox directories ───
  # The build creates bind mounts inside chroot sandboxes. If a build
  # fails, those mounts may persist and block subsequent sandbox
  # creation (rm -rf fails on mounted directories). This helper kills
  # processes rooted inside the stage, unmounts everything, waits for
  # lazy unmounts to complete, then removes stale chroot dirs.
  # Kill only what actually lives INSIDE the stage, matched by the process's
  # own root, never by mount point.
  #
  # This used to start with `fuser -km <mountpoint>` over every
  # stage/photonroot mount. Those are overlay and bind mounts whose backing
  # filesystem is the ROOT filesystem, and `fuser -m` reports every process
  # using that filesystem - i.e. every process on the box. On 2026-09-11 the
  # kernel BuildRequires failure sent this function down the retry path twice,
  # and each time the sweep SIGKILLed PID 1 along with everything else: the
  # WSL2 instance went down mid-build and came back looking like a
  # spontaneous reboot, with the build log ending at "cleaning stale
  # sandboxes" and a bare list of PIDs - 1 and 2 among them - as the only
  # trace. Never signal by mount point, and never signal PID 1.
  #
  # Gradle daemons are the reason any of this exists: kafka builds with
  # gradle, and a daemon left over from a failed attempt keeps holding
  #   <sandbox>/root/.gradle/caches/*/zinc-*/zinc-*.lock
  # so the next attempt dies with "Timeout waiting to lock zinc-... It is
  # currently in use by another process" - which is how kafka broke the
  # canister ISO on 2026-09-01 while nothing was wrong with kafka. Those
  # daemons run inside the sandbox, so a root-based match reaches them.
  kill_stage_processes() {
    local p pid root
    for p in /proc/[0-9]*; do
      pid=${p#/proc/}
      # PID 1 is init. Killing it ends the instance, not a sandbox.
      [ "$pid" = "1" ] && continue
      [ "$pid" = "$$" ] && continue
      [ -r "$p/root" ] || continue
      root=$(readlink "$p/root" 2>/dev/null)
      case "$root" in
        "$BUILD_STAGE"/*) kill -9 "$pid" 2>/dev/null || true ;;
      esac
    done
  }

  clean_stale_sandboxes() {
    local mounts
    mounts=$(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r)
    if [ -n "$mounts" ]; then
      kill_stage_processes
      sleep 1
      mounts=$(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r)
      echo "$mounts" | while read -r mp; do
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
      done
      sync
      sleep 2
    fi
    kill_stage_processes
    find "$BUILD_STAGE" -name '*.lock' -path '*/.gradle/*' -delete 2>/dev/null

    if [ -d "$BUILD_STAGE/photonroot" ]; then
      rm -rf "$BUILD_STAGE/photonroot"/* 2>/dev/null
      echo "[runPh5_normal] Cleaned stale build sandboxes"
    fi
  }

  # ── Initial cleanup before build loop ──────────────────────────
  clean_stale_sandboxes
  if [ -d "$BUILD_STAGE/SRPMS" ]; then
    rm -rf "$BUILD_STAGE/SRPMS"/*
    echo "[runPh5_normal] Cleaned stale SRPMs"
  fi
  if [ -d "$BUILD_STAGE/LOGS" ]; then
    rm -rf "$BUILD_STAGE/LOGS"/*
    echo "[runPh5_normal] Cleaned stale build logs"
  fi
  tdnf clean all 2>/dev/null
  echo "[runPh5_normal] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

  # ── Host tooling preflight ────────────────────────────────────────
  # build.py runs createrepo_c on the *host* (not in a chroot). A partial
  # host upgrade breaks it hours into a run: photon-updates ships a
  # createrepo_c built against a newer glib, and if the host still has the
  # old one the call dies with
  #   createrepo_c: symbol lookup error: /usr/lib/libcreaterepo_c.so.1:
  #   undefined symbol: g_free_sized
  # (g_free_sized landed in glib 2.76). Detect it up front and pull the
  # matching glib rather than failing at the first create_repo().
  if ! createrepo_c --version >/dev/null 2>&1; then
    echo "[runPh5_normal] createrepo_c is broken on the host, updating glib ..."
    tdnf update -y glib >/dev/null 2>&1
    if createrepo_c --version >/dev/null 2>&1; then
      echo "[runPh5_normal] createrepo_c repaired (glib $(rpm -q --qf '%{VERSION}-%{RELEASE}' glib))"
    else
      echo "[runPh5_normal] ERROR: createrepo_c still broken:" 1>&2
      createrepo_c --version 1>&2
      echo "[runPh5_normal]        The build cannot create the local repo; fix the host first." 1>&2
      exit 1
    fi
  fi

  # ── Remove corrupted RPMs that would block dependency installs ────
  # A prior build may have produced RPMs with bad checksums (e.g. due
  # to I/O errors or OOM kills during compression). Detect and remove
  # them so they get rebuilt cleanly.
  if [ -d "$BUILD_STAGE/RPMS/x86_64" ]; then
    bad_rpms=0
    for rpmfile in "$BUILD_STAGE"/RPMS/x86_64/*.rpm; do
      [ -f "$rpmfile" ] || continue
      if ! rpm -K "$rpmfile" >/dev/null 2>&1; then
        echo "[runPh5_normal] Removing corrupted RPM: $(basename "$rpmfile")"
        rm -f "$rpmfile"
        bad_rpms=$((bad_rpms + 1))
      fi
    done
    [ "$bad_rpms" -gt 0 ] && echo "[runPh5_normal] Removed $bad_rpms corrupted RPM(s)"
  fi

  # ── Build loop ────────────────────────────────────────────────────
  # Incident note: a previous run burned ALL 10 retries rebuilding an ISO
  # that had already been built successfully, because the ISO-detection
  # globs missed the real output location (they checked stage/ and
  # stage/iso/, but poi.py actually writes to stage/<IMG_NAME>/). That is
  # fixed above via iso_marker + iso_globs (maxdepth 2, -newer marker).
  # The guards below exist so that even with correct detection, retries
  # still can't be wasted on work that is already done or that can never
  # succeed:
  #   1. success moves the ISO and exits immediately -- it can never fall
  #      through into another retry (see the exit 0 / exit 1 below, both
  #      of which are unconditional once an ISO is found).
  #   2. if an ISO with identical *content* (sha256, not just filename)
  #      already sits in $OUTPUT_DIR, there is nothing left to deliver --
  #      report it and exit 0 instead of moving/overwriting anything.
  #   3. a different file already at the destination filename is never
  #      silently clobbered; the new ISO is delivered under a
  #      timestamp-qualified name instead.
  #   4. two attempts in a row that both fail with the same make exit
  #      code AND produce zero new output are almost certainly the same
  #      deterministic failure (bad spec, missing dep, ...), not a flaky
  #      one -- stop early with a clear error rather than silently
  #      reproducing the same failure 10 times.
  prev_make_rc=""
  prev_progress=""
  for i in $(seq 1 10); do
    # Clean stale mounts/sandboxes before each retry so failures from
    # the previous iteration don't block sandbox creation.
    if [ "$i" -gt 1 ]; then
      echo "[runPh5_normal] Retry $i: cleaning stale sandboxes from previous attempt"
      clean_stale_sandboxes
    fi
    # Drop a marker first: an ISO left in the stage by an older run must not
    # be mistaken for this run's output, which would exit 0 and hand back the
    # wrong image. Only ISOs newer than the marker count.
    iso_marker="$BUILD_STAGE/.runph5-iso-marker"
    : > "$iso_marker"
    if [ "$MC_MAKE_TARGET" = "linux" ]; then
      # Phase A: one package, no image. build.py treats an unrecognised target
      # as a package name and falls through to RpmBuildTarget().package().
      sudo make -j8 linux THREADS=8;
      make_rc=$?
      # Success here is the canister RPM existing at the NEVR we asked for -
      # not make's exit code, and not the linux RPM, which phase A also
      # produces but which is a canister-CREATION kernel (canister_usage=0)
      # that must never reach an image.
      can=$(find "$BUILD_STAGE/RPMS" -name "linux-fips-canister-$MC_CANISTER_NEVR.*.rpm" 2>/dev/null | head -1)
      if [ -n "$can" ]; then
        echo "[runPh5_normal] phase A produced: $can"
        exit 0
      fi
      echo "[runPh5_normal] phase A did NOT produce linux-fips-canister-$MC_CANISTER_NEVR (make rc=$make_rc)" 1>&2
      found=$(find "$BUILD_STAGE/RPMS" -name "linux-fips-canister-*.rpm" 2>/dev/null | head -3)
      [ -n "$found" ] && echo "[runPh5_normal] found instead: $found" 1>&2
      continue
    fi
    sudo make -j8 image IMG_NAME="$IMG_TYPE" THREADS=8;
    make_rc=$?
    # ── Locate the finished ISO ───────────────────────────────────
    # poi.py writes the image into $BUILD_STAGE/<IMG_NAME>/, i.e.
    # stage/minimal-iso/photon-minimal-<ver>-<sha>.x86_64.iso -- NOT into
    # stage/ or stage/iso/. Globbing only those two made the loop miss a
    # perfectly good, fully written ISO and burn every remaining retry
    # rebuilding it. Search one level deep in both stages, and take the
    # newest match so a stale ISO from an older run is never mistaken for
    # this run's output.
    iso_globs() {
      find "$BUILD_STAGE" "$COMMON_STAGE" -maxdepth 2 -name '*.iso' \
           -newer "$iso_marker" -print 2>/dev/null | xargs -r ls -t 2>/dev/null
    }
    timeout=30
    while [ $timeout -gt 0 ]; do
      [ -n "$(iso_globs | head -1)" ] && break
      sleep 1
      timeout=$((timeout - 1))
    done
    iso_found=$(iso_globs | head -1)
    if [ -n "$iso_found" ]; then
      echo "[runPh5_normal] Built ISO: $iso_found ($(du -h "$iso_found" | cut -f1))"
      # ── Guard: don't move/overwrite if an identical ISO is already
      # delivered. Compare by content (sha256), not by filename, so a
      # rebuild that reproduces a previously-delivered image is
      # recognized as "already done" instead of burning a retry or
      # clobbering the destination.
      iso_sha=$(sha256sum "$iso_found" | cut -d' ' -f1)
      dup_found=""
      for existing in "$OUTPUT_DIR"/*.iso; do
        [ -f "$existing" ] || continue
        if [ "$(sha256sum "$existing" | cut -d' ' -f1)" = "$iso_sha" ]; then
          dup_found="$existing"
          break
        fi
      done
      if [ -n "$dup_found" ]; then
        echo "[runPh5_normal] Identical ISO already present at $dup_found (sha256 $iso_sha) -- not moving/overwriting; nothing left to do."
        exit 0
      fi
      dest="$OUTPUT_DIR/$(basename "$iso_found")"
      if [ -e "$dest" ]; then
        # Same filename but different content (checked above): never
        # silently destroy the existing file, deliver under a distinct
        # name instead.
        dest="$OUTPUT_DIR/$(date +%Y%m%d-%H%M%S)-$(basename "$iso_found")"
        echo "[runPh5_normal] $OUTPUT_DIR/$(basename "$iso_found") already exists with different content; delivering new ISO as $(basename "$dest") instead"
      fi
      if sudo mv "$iso_found" "$dest"; then
        echo "[runPh5_normal] Moved ISO to $dest"
        exit 0
      fi
      echo "[runPh5_normal] ERROR: could not move ISO to $dest" 1>&2
      echo "[runPh5_normal]        It is still at: $iso_found" 1>&2
      exit 1
    fi
    # ── No ISO this attempt: decide whether another retry can help ────
    # "progress" = number of files touched anywhere in the stages since
    # the marker was dropped. If two consecutive attempts both fail with
    # the same make exit code and both touch nothing, the build is stuck
    # in the same deterministic way -- retrying it won't change the
    # outcome, it will just burn the remaining budget re-running for
    # hours to reproduce the same error.
    progress=$(find "$BUILD_STAGE" "$COMMON_STAGE" -newer "$iso_marker" 2>/dev/null | wc -l)
    echo "[runPh5_normal] Attempt $i: no ISO produced (make exit=$make_rc, $progress file(s) touched since marker)"
    if [ "$i" -gt 1 ] && [ "$make_rc" = "$prev_make_rc" ] && [ "$progress" = "0" ] && [ "$prev_progress" = "0" ]; then
      echo "[runPh5_normal] ERROR: attempt $i failed identically to attempt $((i - 1)) (same make exit code, zero new output both times)." 1>&2
      echo "[runPh5_normal]        This looks like a deterministic failure, not a flaky one -- further retries would just reproduce it." 1>&2
      echo "[runPh5_normal]        Stopping after $i/10 attempts. Fix the underlying build error, then re-run." 1>&2
      exit 1
    fi
    prev_make_rc=$make_rc
    prev_progress=$progress
  done
  echo "[runPh5_normal] ERROR: exhausted all 10 attempts without producing an ISO" 1>&2
  exit 1
else
  # The entire build is gated on this reachability check. Without an
  # else branch the script fell off the end of the "if" and exited 0
  # having built nothing -- indistinguishable from a successful
  # delivery to any caller that checks $?. Never exit 0 without an ISO.
  echo "[runPh5_normal] ERROR: no network (ping www.google.ch failed); the build" 1>&2
  echo "[runPh5_normal]        needs to fetch sources and was not started." 1>&2
  exit 1
fi
