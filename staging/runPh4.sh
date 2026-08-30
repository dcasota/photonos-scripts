#! /bin/sh

# Parameters with defaults:
# $1 - Base directory (default: /root)
# $2 - Common branch name (default: common)
# $3 - Release branch name (default: 4.0)
# $4 - Output directory (default: /mnt/c/Users/dcaso/Downloads/Ph-Builds)
# $5 - Image type (default: minimal-iso; pass "iso" for the full ISO)

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-4.0}"
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
    echo "[runPh4] ERROR: unsupported image type '$IMG_TYPE'" 1>&2
    echo "[runPh4]        valid: iso (full), minimal-iso (default), basic-iso, rt-iso" 1>&2
    exit 1
    ;;
esac
echo "[runPh4] Image type: $IMG_TYPE"

sleep 3
if ping -c 4 www.google.ch > /dev/null 2>&1; then
  if [ ! -d "$BASE_DIR/$COMMON_BRANCH" ]; then
    git clone https://github.com/dcasota/photon.git -b "$COMMON_BRANCH" "$BASE_DIR/$COMMON_BRANCH"
  fi
  cd "$BASE_DIR/$COMMON_BRANCH"
  git fetch
  git merge
  cd "$BASE_DIR"
  if [ ! -d "$BASE_DIR/$RELEASE_BRANCH" ]; then
    git clone https://github.com/dcasota/photon.git -b "$RELEASE_BRANCH" "$BASE_DIR/$RELEASE_BRANCH"
  fi
  cd "$BASE_DIR/$RELEASE_BRANCH"
  git fetch
  git merge --autostash
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
      echo "[runPh4] sha512 mismatch for $archive (cached: ${actual:0:12}…, expected: ${expected_sha:0:12}…)"
      # Try recovering from the common branch's cache (often correct).
      if [ -f "$backup_dir/$archive" ]; then
        backup_sha=$(sha512sum "$backup_dir/$archive" 2>/dev/null | awk '{print $1}')
        if [ "$backup_sha" = "$expected_sha" ]; then
          cp -f "$backup_dir/$archive" "$target"
          echo "[runPh4] Restored $archive from $backup_dir"
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
      echo "[runPh4] Fetching source: $archive <- $src_url"
      # Download to a temp file: wget -O truncates the target to 0 bytes
      # before the request, so a 404/network failure would otherwise leave
      # an empty file that poisons the SOURCES cache.
      if wget -q "$src_url" -O "$target.tmp" 2>/dev/null && [ -s "$target.tmp" ]; then
        if [ -n "$expected_sha" ]; then
          dl_sha=$(sha512sum "$target.tmp" 2>/dev/null | awk '{print $1}')
          if [ "$dl_sha" != "$expected_sha" ]; then
            echo "[runPh4] WARNING: checksum mismatch for fetched $archive (got ${dl_sha:0:12}…), discarding"
            rm -f "$target.tmp"
            continue
          fi
        fi
        mv -f "$target.tmp" "$target"
        return 0
      fi
      rm -f "$target.tmp"
    done
    echo "[runPh4] WARNING: Failed to fetch $archive from any source"
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

  # ── Ensure the photon/installer (POI) image exists ────────────────
  # `make image` (poi.py) needs a photon/installer docker image, which is not
  # on any public registry. Build it locally if missing, using the legacy
  # builder (DOCKER_BUILDKIT=0, since buildx may be absent) and the multi-file
  # COPY trailing-slash fix the legacy builder requires (merged upstream as
  # PR #38; the sed below is kept for older checkouts that predate it). The
  # image is only the ISO build tool; the installer that ships inside the
  # ISO comes from the patched photon-os-installer RPM built above.
  # The image must also contain `file`. photon_installer/generate_initrd.py's
  # strip_if_needed() runs subprocess.check_output(["file", path]) on every
  # file it puts in the initrd, but the upstream Dockerfile never installs it,
  # so ISO assembly dies with
  #   FileNotFoundError: [Errno 2] No such file or directory: 'file'
  # in generateInitrd() -- *after* all packages have been built, and the
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
        && echo "[runPh4] Built photon/installer:latest" \
        || echo "[runPh4] WARNING: failed to build photon/installer image"
    fi
    if ! poi_image_ok; then
      echo "[runPh4] ERROR: photon/installer:latest is missing or has no 'file'" 1>&2
      echo "[runPh4]        binary. ISO assembly would fail in generateInitrd()" 1>&2
      echo "[runPh4]        after every package has been rebuilt -- aborting now." 1>&2
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
" 2>/dev/null && echo "[runPh4] Set poi-image to local photon/installer:latest"
    fi
  fi

  # ── Fix OpenJDK WSL2 detection in chroot ───────────────────────────
  # OpenJDK's configure detects "x86_64-pc-wsl" inside WSL2 chroots and
  # fails with "Incorrect wsl1 installation". Adding --build= overrides
  # the auto-detected triplet. Only applied if the flag is missing.
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    for jdk_spec in SPECS/openjdk/openjdk*.spec "$BASE_DIR/$COMMON_BRANCH"/SPECS/openjdk/openjdk*.spec; do
      [ -f "$jdk_spec" ] || continue
      if grep -q 'sh ./configure' "$jdk_spec" && ! grep -q 'build=x86_64-unknown-linux-gnu' "$jdk_spec"; then
        sed -i 's|--disable-warnings-as-errors$|--disable-warnings-as-errors \\\n    --build=x86_64-unknown-linux-gnu|' "$jdk_spec"
        echo "[runPh4] Fixed $(basename "$jdk_spec"): added --build for WSL2"
      fi
    done
  fi

  # ── Fix Python 3 PGO test flake in WSL2 ────────────────────────────
  # Python's --enable-optimizations runs test_generators for PGO profiling.
  # test_generators.SignalAndYieldFromTest is flaky under WSL2 (signal
  # delivery timing differs from native Linux), causing the entire build
  # to fail. Override PROFILE_TASK to exclude it. Only applied in WSL2.
  #
  # IMPORTANT: PROFILE_TASK must be passed as a make *command-line* variable,
  # not as an environment variable. CPython's Makefile.pre.in contains a
  # plain "PROFILE_TASK= @PROFILE_TASK@" assignment, and a Makefile
  # assignment always beats the environment (only "make VAR=..." or
  # "make -e" overrides it). A "PROFILE_TASK=... %make_build" prefix (i.e.
  # PROFILE_TASK set before the command, as a shell/environment variable)
  # is therefore silently ignored -- the build then trains on the stock
  # 43-test PGO set and fails again with
  #   make: *** [Makefile:1012: profile-run-stamp] Error 2
  # regrtest handles "--pgo -x test_generators" correctly when passed on
  # the make command line: find_tests() moves cmdline args into the
  # exclude set *before* setup_pgo_tests() fills in the default list, so
  # the run becomes PGO_TESTS minus test_generators (42 of 43).
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    PY3_SPEC="SPECS/python3/python3.spec"
    if [ -f "$PY3_SPEC" ] && ! grep -q 'PROFILE_TASK' "$PY3_SPEC"; then
      sed -i 's|^%make_build$|%make_build PROFILE_TASK="-m test --pgo -x test_generators"|' "$PY3_SPEC"
      echo "[runPh4] Fixed python3 spec: excluded test_generators from PGO"
    fi
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
    echo "[runPh4] Fixed sssd spec: serial %make_install"
  fi


  # ── Determine the real stage path ───────────────────────────────
  # `make` runs in the release worktree ($BASE_DIR/$RELEASE_BRANCH, which is
  # also the current directory here) and resolves "stage-path" from that
  # worktree's own build-config.json (normally "./stage"), so RPMS, SRPMS,
  # LOGS and the ISO output all land under $RELEASE_BRANCH/stage -- even
  # though build.py itself lives in $COMMON_BRANCH. Deriving BUILD_STAGE
  # explicitly (rather than assuming the literal "stage" glob used below is
  # always correct) keeps ISO detection right even if stage-path is ever
  # customized, and gives the ISO search a real directory to look in instead
  # of a bare relative glob.
  BUILD_STAGE=$(cd "$BASE_DIR/$RELEASE_BRANCH" 2>/dev/null && \
    realpath "$(jq -r '.["stage-path"] // "./stage"' build-config.json 2>/dev/null)" 2>/dev/null)
  [ -d "$BUILD_STAGE" ] || BUILD_STAGE="$BASE_DIR/$RELEASE_BRANCH/stage"
  COMMON_STAGE="$BASE_DIR/$COMMON_BRANCH/stage"
  echo "[runPh4] Build stage: $BUILD_STAGE"

  # ── Build loop ────────────────────────────────────────────────────
  # poi.py writes the ISO to $BUILD_STAGE/<IMG_NAME>/, NOT to stage/ or
  # stage/iso/ directly. Globbing only stage/*.iso can miss the real output
  # location and burn every retry rebuilding an ISO that had already been
  # produced. An iso_marker file dropped before each `make`, plus a
  # "-newer" search, ensures a stale ISO from an older run is never
  # mistaken for this run's output. A sha256 duplicate check against
  # $OUTPUT_DIR avoids clobbering (or needlessly re-delivering) an ISO
  # that's already there; a timestamp-qualified name is used if the
  # destination filename exists with different content; and two
  # consecutive attempts that fail identically stop the loop early instead
  # of burning all 10 retries reproducing the same deterministic error.
  prev_make_rc=""
  prev_progress=""
  for i in $(seq 1 10); do
    # Drop a marker first: an ISO left in the stage by an older run must not
    # be mistaken for this run's output, which would exit 0 and hand back
    # the wrong image. Only ISOs newer than the marker count.
    iso_marker="$BUILD_STAGE/.runph4-iso-marker"
    : > "$iso_marker"
    # sudo make -j$(( $(nproc) - 1 )) image IMG_NAME=iso THREADS=$(( $(nproc) - 1 ));
    sudo make -j2 image IMG_NAME="$IMG_TYPE" THREADS=2;
    make_rc=$?
    # ── Locate the finished ISO ───────────────────────────────────
    # Search one level deep in both stages, and take the newest match so a
    # stale ISO from an older run is never mistaken for this run's output.
    iso_globs() {
      find "$BUILD_STAGE" "$COMMON_STAGE" -maxdepth 2 -name '*.iso' \
           -newer "$iso_marker" -print 2>/dev/null | xargs -r ls -t 2>/dev/null
    }
    # Wait up to 30 seconds for ISO to appear
    timeout=30
    while [ $timeout -gt 0 ]; do
      [ -n "$(iso_globs | head -1)" ] && break
      sleep 1
      timeout=$((timeout - 1))
    done
    iso_found=$(iso_globs | head -1)
    if [ -n "$iso_found" ]; then
      echo "[runPh4] Built ISO: $iso_found ($(du -h "$iso_found" | cut -f1))"
      # ── Guard: don't move/overwrite if an identical ISO is already
      # delivered. Compare by content (sha256), not by filename, so a
      # rebuild that reproduces a previously-delivered image is recognized
      # as "already done" instead of burning a retry or clobbering the
      # destination.
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
        echo "[runPh4] Identical ISO already present at $dup_found (sha256 $iso_sha) -- not moving/overwriting; nothing left to do."
        exit 0
      fi
      dest="$OUTPUT_DIR/$(basename "$iso_found")"
      if [ -e "$dest" ]; then
        # Same filename but different content (checked above): never
        # silently destroy the existing file, deliver under a distinct
        # name instead.
        dest="$OUTPUT_DIR/$(date +%Y%m%d-%H%M%S)-$(basename "$iso_found")"
        echo "[runPh4] $OUTPUT_DIR/$(basename "$iso_found") already exists with different content; delivering new ISO as $(basename "$dest") instead"
      fi
      if sudo mv "$iso_found" "$dest"; then
        echo "[runPh4] Moved ISO to $dest"
        exit 0
      fi
      echo "[runPh4] ERROR: could not move ISO to $dest" 1>&2
      echo "[runPh4]        It is still at: $iso_found" 1>&2
      exit 1
    fi
    # ── No ISO this attempt: decide whether another retry can help ────
    # "progress" = number of files touched anywhere in the stages since the
    # marker was dropped. If two consecutive attempts both fail with the
    # same make exit code and both touch nothing, the build is stuck in the
    # same deterministic way -- retrying it won't change the outcome, it
    # will just burn the remaining budget re-running for hours to
    # reproduce the same error.
    progress=$(find "$BUILD_STAGE" "$COMMON_STAGE" -newer "$iso_marker" 2>/dev/null | wc -l)
    echo "[runPh4] Attempt $i: no ISO produced (make exit=$make_rc, $progress file(s) touched since marker)"
    if [ "$i" -gt 1 ] && [ "$make_rc" = "$prev_make_rc" ] && [ "$progress" = "0" ] && [ "$prev_progress" = "0" ]; then
      echo "[runPh4] ERROR: attempt $i failed identically to attempt $((i - 1)) (same make exit code, zero new output both times)." 1>&2
      echo "[runPh4]        This looks like a deterministic failure, not a flaky one -- further retries would just reproduce it." 1>&2
      echo "[runPh4]        Stopping after $i/10 attempts. Fix the underlying build error, then re-run." 1>&2
      exit 1
    fi
    prev_make_rc=$make_rc
    prev_progress=$progress
  done
  echo "[runPh4] ERROR: exhausted all 10 attempts without producing an ISO" 1>&2
  exit 1
else
  # The entire build is gated on this reachability check. Without an
  # else branch the script fell off the end of the "if" and exited 0
  # having built nothing -- indistinguishable from a successful
  # delivery to any caller that checks $?. Never exit 0 without an ISO.
  echo "[runPh4] ERROR: no network (ping www.google.ch failed); the build" 1>&2
  echo "[runPh4]        needs to fetch sources and was not started." 1>&2
  exit 1
fi
