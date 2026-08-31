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

# Directory containing this script, used to locate the bundled downstream
# patch set (staging/photonos-patches/). Resolved before any cd.
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)
SCRIPT_TAG=$(basename "$0" .sh)

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
  #   photon-os-installer 2.8-3 : interactive (no-kickstart) UI install fix,
  #       btrfs-progs on btrfs partitions, and tdnf output capture so package
  #       install no longer overlays the curses UI (e.g. /etc/os-release).
  #   stig-hardening 2.1-9      : SELinux first-boot relabel + fips PAM (PR #9)
  #   linux 6.12.96-10          : strip canister Kconfig when fips=0  (PR #14)
  # (nginx PR #17 is intentionally NOT included: 5.0 already ships nginx
  #  1.30.2, newer than the PR's 1.30.1, so it would be a downgrade.)
  # -- Resolve the downstream patch --------------------------------------
  # Precedence: an explicit DOWNSTREAM_PATCH from the caller, else the
  # historical search. With the variable unset this behaves exactly as before,
  # so the standalone "just run it" path is unchanged.
  #
  # Why explicit-first: this script resolves the patch RELATIVE TO ITSELF, so
  # two checkouts of it see two different patches. When those diverge, the
  # build silently uses whichever copy sits beside the script that was
  # invoked, and the failure surfaces as "patch does not apply" against a spec
  # -- which reads like a rebase problem rather than a path problem. An
  # automated driver previously had no way to say which patch it meant.
  if [ -n "${DOWNSTREAM_PATCH:-}" ]; then
    [ -f "$DOWNSTREAM_PATCH" ] || {
      echo "[$SCRIPT_TAG] ERROR: DOWNSTREAM_PATCH=$DOWNSTREAM_PATCH does not exist" 1>&2
      exit 1
    }
    echo "[$SCRIPT_TAG] downstream patch: $DOWNSTREAM_PATCH (caller-specified)"
  else
    DOWNSTREAM_PATCH=""
    _cands=""
    for cand in "$SCRIPT_DIR/photonos-patches/downstream-fixes.patch" \
                "$BASE_DIR/photonos-patches/downstream-fixes.patch"; do
      [ -f "$cand" ] || continue
      _cands="$_cands $cand"
      [ -n "$DOWNSTREAM_PATCH" ] || DOWNSTREAM_PATCH="$cand"
    done
    # Ambiguity is refused, not silently resolved. Identical copies are fine;
    # copies that differ mean the build would otherwise be a coin toss.
    if [ "$(echo $_cands | wc -w)" -gt 1 ]; then
      if [ "$(for c in $_cands; do sha256sum "$c" | cut -c1-16; done | sort -u | wc -l)" -gt 1 ]; then
        echo "[$SCRIPT_TAG] ERROR: several downstream-fixes.patch copies exist and they DIFFER:" 1>&2
        for c in $_cands; do
          echo "[$SCRIPT_TAG]   $c ($(grep -c '^+++ ' "$c") files, sha $(sha256sum "$c" | cut -c1-16))" 1>&2
        done
        echo "[$SCRIPT_TAG]        Set DOWNSTREAM_PATCH=<path> to choose deliberately." 1>&2
        exit 1
      fi
    fi
  fi
  if [ -n "$DOWNSTREAM_PATCH" ]; then
    echo "[$SCRIPT_TAG] downstream patch: $DOWNSTREAM_PATCH ($(grep -c '^+++ ' "$DOWNSTREAM_PATCH") files, sha $(sha256sum "$DOWNSTREAM_PATCH" | cut -c1-16))"
  fi
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
  COMMON_CFG="$BASE_DIR/$COMMON_BRANCH/build-config.json"
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
  # processes holding mount points, unmounts everything, waits for
  # lazy unmounts to complete, then removes stale chroot dirs.
  clean_stale_sandboxes() {
    local mounts
    mounts=$(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r)
    if [ -n "$mounts" ]; then
      echo "$mounts" | while read -r mp; do
        fuser -km "$mp" 2>/dev/null || true
      done
      sleep 1
      mounts=$(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r)
      echo "$mounts" | while read -r mp; do
        umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
      done
      sync
      sleep 2
    fi
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
        # -- Provenance sidecar ------------------------------------------
        # An ISO with no record of what produced it cannot be attributed:
        # you cannot tell later which patch set, which tree, or which
        # installer it actually contains. A driver also should not have to
        # scrape "Moved ISO to" out of a log to find the artefact.
        {
          printf '{\n'
          printf '  "iso": "%s",\n' "$dest"
          printf '  "iso_sha256": "%s",\n' "$(sha256sum "$dest" | cut -d" " -f1)"
          printf '  "img_type": "%s",\n' "$IMG_TYPE"
          printf '  "canister_mode": "%s",\n' "$CANISTER_MODE"
          printf '  "release_branch": "%s",\n' "$RELEASE_BRANCH"
          printf '  "tree_head": "%s",\n' "$(git -C "$BASE_DIR/$RELEASE_BRANCH" rev-parse HEAD 2>/dev/null)"
          printf '  "downstream_patch": "%s",\n' "${DOWNSTREAM_PATCH:-}"
          printf '  "downstream_patch_sha256": "%s",\n' "$([ -n "${DOWNSTREAM_PATCH:-}" ] && sha256sum "$DOWNSTREAM_PATCH" | cut -d" " -f1)"
          printf '  "built_at": "%s"\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
          printf '}\n'
        } > "${dest%.iso}.build-manifest.json"
        echo "[runPh5_normal] Manifest: ${dest%.iso}.build-manifest.json"
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
