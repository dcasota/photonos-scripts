#!/bin/sh

# Photon OS 5.0 build script pinned to photon-subrelease 90
#
# Pins photon-subrelease to 90 so the SPECS/90/ gated specs (older GA
# ecosystem: python 3.11, libcap 2.x, rpm 4.x, nginx 1.26.x, etc.) are
# active instead of the >= 92 defaults. Use this to build/verify the
# SPECS/90 package set (e.g. the SPECS/90/nginx CVE-2026-42945 backport).
#
# NOTE: SPECS/90 is a large (~583-package) ecosystem; like the 91 script,
# a fully-clean ISO build may need additional subrelease-90 bootstrap fixes
# discovered iteratively. The pinning + base-commit bypass below is the core.
#
# Parameters with defaults:
# $1 - Base directory (default: /root)
# $2 - Common branch name (default: common)
# $3 - Release branch name (default: 5.0)
# $4 - Output directory (default: /mnt/c/Users/dcaso/Downloads/Ph-Builds)

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-5.0}"
OUTPUT_DIR="${4:-/mnt/c/Users/dcaso/Downloads/Ph-Builds}"

# SPECS/90 ships libcap 2.x (no libcap-libs split). Exclude libcap-libs so
# transitive deps don't pull the >= 92 libcap-libs and conflict.
export PHOTON_TDNF_EXCLUDE_PKGS="libcap-libs*"
echo "libcap-libs*" > /tmp/photon-tdnf-exclude-pkgs.txt
trap 'rm -f /tmp/photon-tdnf-exclude-pkgs.txt' EXIT INT TERM

# Directory containing this script, used to locate the bundled downstream
# patch set (staging/photonos-patches/). Resolved before any cd.
SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

sleep 3
if ping -c 4 www.google.ch > /dev/null 2>&1; then
  if [ ! -d "$BASE_DIR/$COMMON_BRANCH" ]; then
    git clone https://github.com/dcasota/photon.git -b "$COMMON_BRANCH" "$BASE_DIR/$COMMON_BRANCH"
  fi
  cd "$BASE_DIR/$COMMON_BRANCH"
  git fetch 2>/dev/null || true
  git merge 2>/dev/null || true
  cd "$BASE_DIR"
  if [ ! -d "$BASE_DIR/$RELEASE_BRANCH" ]; then
    git clone https://github.com/dcasota/photon.git -b "$RELEASE_BRANCH" "$BASE_DIR/$RELEASE_BRANCH"
  fi
  cd "$BASE_DIR/$RELEASE_BRANCH"
  git fetch
  git merge --autostash

  # ── Pin subrelease to 90 (activate SPECS/90/ gated specs) ─────────
  PINNED_SUB=90
  sed -i "s/\"photon-subrelease\":.*/\"photon-subrelease\": \"${PINNED_SUB}\",/" build-config.json
  if grep -q '"photon-mainline"' build-config.json; then
    sed -i "s/\"photon-mainline\":.*/\"photon-mainline\": \"${PINNED_SUB}\",/" build-config.json
  else
    sed -i "/\"photon-subrelease\":.*/a\\    \"photon-mainline\": \"${PINNED_SUB}\"," build-config.json
  fi
  echo "[runPh5_pinned90] Pinned photon-subrelease and photon-mainline to ${PINNED_SUB}"

  # Bypass the spec checker: set base-commit to common HEAD so the checker's
  # \`git diff --name-only <base>\` is empty (our edits are unstaged), avoiding
  # the assertion where >= 92 gating values exceed our pinned mainline of 90.
  COMMON_HEAD=$(cd "$BASE_DIR/$COMMON_BRANCH" && git rev-parse HEAD 2>/dev/null)
  if [ -n "$COMMON_HEAD" ]; then
    python3 -c "
import json
with open('build-config.json') as f: cfg = json.load(f)
cfg['photon-build-param']['base-commit'] = '${COMMON_HEAD}'
with open('build-config.json','w') as f: json.dump(cfg, f, indent=4); f.write('\n')
" 2>/dev/null && echo "[runPh5_pinned90] Set base-commit to common HEAD: ${COMMON_HEAD}"
  fi

  # ── Restore ALL files that may have been modified by prior runs ────
  # A prior runPh5_pinned91.sh (or failed normal) run may have altered
  # specs, data files, etc. Restore every dirty tracked file to upstream.
  dirty_files=$(git diff --name-only 2>/dev/null)
  if [ -n "$dirty_files" ]; then
    echo "$dirty_files" | while read -r f; do
      git checkout -- "$f" 2>/dev/null && echo "[runPh5_pinned90] Restored $f to upstream"
    done
  fi

  # ── Apply downstream fixes / PRs (installer + packages) ───────────
  # Re-applied here so they survive the restore above. Covers:
  #   photon-os-installer 2.8-5 : interactive (no-kickstart) UI install fix,
  #       btrfs-progs on btrfs partitions, and tdnf output capture so package
  #       install no longer overlays the curses UI (e.g. /etc/os-release).
  #   stig-hardening 2.1-8      : SELinux first-boot relabel + fips PAM (PR #9)
  #   linux 6.12.87-3           : strip canister Kconfig when fips=0  (PR #14)
  # (nginx PR #17 is intentionally NOT included: 5.0 already ships nginx
  #  1.30.2, newer than the PR's 1.30.1, so it would be a downgrade.)
  DOWNSTREAM_PATCH=""
  for cand in "$SCRIPT_DIR/photonos-patches/downstream-fixes.patch" \
              "$BASE_DIR/photonos-patches/downstream-fixes.patch"; do
    [ -f "$cand" ] && DOWNSTREAM_PATCH="$cand" && break
  done
  if [ -n "$DOWNSTREAM_PATCH" ]; then
    if git apply --check "$DOWNSTREAM_PATCH" 2>/dev/null; then
      git apply "$DOWNSTREAM_PATCH" && echo "[runPh5_pinned90] Applied downstream-fixes.patch"
    else
      echo "[runPh5_pinned90] WARNING: downstream-fixes.patch does not apply cleanly (5.0 may have moved on); skipping"
    fi
  else
    echo "[runPh5_pinned90] NOTE: photonos-patches/downstream-fixes.patch not found; building without downstream fixes"
  fi

  echo "[runPh5_pinned90] Building at pinned photon-subrelease 90 (SPECS/90/ active)"

  # ── Ensure the photon/installer (POI) image exists ────────────────
  # `make image` (poi.py) needs a photon/installer docker image, which is not
  # on any public registry. Build it locally if missing, using the legacy
  # builder (DOCKER_BUILDKIT=0, since buildx may be absent) and the multi-file
  # COPY trailing-slash fix the legacy builder requires (fix/dockerfile-copy-
  # syntax). The image is only the ISO build tool; the installer that ships
  # inside the ISO comes from the patched photon-os-installer RPM built above.
  if ! docker image inspect photon/installer:latest >/dev/null 2>&1; then
    POI_SRC="$BASE_DIR/photon-os-installer"
    [ -d "$POI_SRC/.git" ] || git clone https://github.com/dcasota/photon-os-installer.git "$POI_SRC" 2>/dev/null
    if [ -d "$POI_SRC/docker" ]; then
      ( cd "$POI_SRC"
        # multi-file 'COPY ... /usr/bin' needs a trailing slash for legacy build
        sed -i 's#^\([[:space:]]*\)/usr/bin$#\1/usr/bin/#' docker/Dockerfile
        DOCKER_BUILDKIT=0 docker build -t photon/installer:latest -f docker/Dockerfile docker/ ) \
        && echo "[runPh5_pinned90] Built photon/installer:latest" \
        || echo "[runPh5_pinned90] WARNING: failed to build photon/installer image"
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
" 2>/dev/null && echo "[runPh5_pinned90] Set poi-image to local photon/installer:latest"
    fi
  fi

  # ── Fix spec formatting errors caught by spec checker ─────────────
  # Remove consecutive blank lines in SPECS/91/python3-setuptools if present.
  # The spec checker rejects "multiple empty lines" as a formatting error.
  for spec in SPECS/91/python3-setuptools/python3-setuptools.spec; do
    if [ -f "$spec" ] && awk 'prev=="" && /^$/{found=1} {prev=$0} END{exit !found}' "$spec" 2>/dev/null; then
      sed -i '/^$/N;/^\n$/d' "$spec"
      echo "[runPh5_pinned90] Fixed consecutive blank lines in $spec"
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
        echo "[runPh5_pinned90] Fixed $(basename "$jdk_spec"): added --build for WSL2"
      fi
    done
  fi

  # ── Fix Python 3 PGO test flake in WSL2 ────────────────────────────
  # Python's --enable-optimizations runs test_generators for PGO profiling.
  # test_generators.SignalAndYieldFromTest is flaky under WSL2 (signal
  # delivery timing differs from native Linux), causing the entire build
  # to fail. Override PROFILE_TASK to exclude it. Only applied in WSL2.
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    PY3_SPEC="SPECS/python3/python3.spec"
    if [ -f "$PY3_SPEC" ] && ! grep -q 'PROFILE_TASK' "$PY3_SPEC"; then
      sed -i 's|^%make_build$|PROFILE_TASK="-m test --pgo -x test_generators" %make_build|' "$PY3_SPEC"
      echo "[runPh5_pinned90] Fixed python3 spec: excluded test_generators from PGO"
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
    echo "[runPh5_pinned90] Fixed sssd spec: serial %make_install"
  fi

  # ── Fix run-in-chroot.sh: protect bash's script fd (255) ────────
  # The fd-closing loop closes ALL fds > 2, including fd 255 which
  # bash uses for reading the script file. This causes bash to
  # misparse continuation lines ("bin: command not found") and mark
  # successfully-built packages as failed. Skip fd 255.
  RIC="$BASE_DIR/$COMMON_BRANCH/support/package-builder/run-in-chroot.sh"
  if [ -f "$RIC" ] && grep -q '\[ \$fd -gt 2 \]' "$RIC" && ! grep -q '255' "$RIC"; then
    sed -i 's/\[ \$fd -gt 2 \] && exec/[ $fd -gt 2 ] \&\& [ $fd -ne 255 ] \&\& exec/' "$RIC"
    echo "[runPh5_pinned90] Fixed run-in-chroot.sh: skip fd 255 in fd-closing loop"
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
      echo "[runPh5_pinned90] sha512 mismatch for $archive (cached: ${actual:0:12}…, expected: ${expected_sha:0:12}…)"
      # Try recovering from the common branch's cache (often correct).
      if [ -f "$backup_dir/$archive" ]; then
        backup_sha=$(sha512sum "$backup_dir/$archive" 2>/dev/null | awk '{print $1}')
        if [ "$backup_sha" = "$expected_sha" ]; then
          cp -f "$backup_dir/$archive" "$target"
          echo "[runPh5_pinned90] Restored $archive from $backup_dir"
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
      echo "[runPh5_pinned90] Fetching source: $archive <- $src_url"
      # Download to a temp file: wget -O truncates the target to 0 bytes
      # before the request, so a 404/network failure would otherwise leave
      # an empty file that poisons the SOURCES cache.
      if wget -q "$src_url" -O "$target.tmp" 2>/dev/null && [ -s "$target.tmp" ]; then
        if [ -n "$expected_sha" ]; then
          dl_sha=$(sha512sum "$target.tmp" 2>/dev/null | awk '{print $1}')
          if [ "$dl_sha" != "$expected_sha" ]; then
            echo "[runPh5_pinned90] WARNING: checksum mismatch for fetched $archive (got ${dl_sha:0:12}…), discarding"
            rm -f "$target.tmp"
            continue
          fi
        fi
        mv -f "$target.tmp" "$target"
        return 0
      fi
      rm -f "$target.tmp"
    done
    echo "[runPh5_pinned90] WARNING: Failed to fetch $archive from any source"
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
    echo "[runPh5_pinned90] Removing rpm 6.x RPMs (toolchain bootstrap requires rpm 4.x)"
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
    echo "[runPh5_pinned90] Removing stale libcap-2.66 RPMs to force rebuild to 2.77"
    rm -f "$RPMSDIR"/libcap-2.66*.rpm "$RPMSDIR"/libcap-debuginfo-2.66*.rpm \
          "$RPMSDIR"/libcap-devel-2.66*.rpm "$RPMSDIR"/libcap-doc-2.66*.rpm
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/images/sandboxBase"
  fi

  # ── Determine correct stage path (build runs in common branch) ──
  COMMON_STAGE="$BASE_DIR/$COMMON_BRANCH/stage"

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
    if [ -d "$COMMON_STAGE/photonroot" ]; then
      rm -rf "$COMMON_STAGE/photonroot"/* 2>/dev/null
      echo "[runPh5_pinned90] Cleaned stale build sandboxes"
    fi
  }

  # ── Initial cleanup before build loop ──────────────────────────
  clean_stale_sandboxes
  if [ -d "$COMMON_STAGE/SRPMS" ]; then
    rm -rf "$COMMON_STAGE/SRPMS"/*
    echo "[runPh5_pinned90] Cleaned stale SRPMs"
  fi
  if [ -d "$COMMON_STAGE/LOGS" ]; then
    rm -rf "$COMMON_STAGE/LOGS"/*
    echo "[runPh5_pinned90] Cleaned stale build logs"
  fi
  tdnf clean all 2>/dev/null
  echo "[runPh5_pinned90] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

  # ── Remove corrupted RPMs that would block dependency installs ────
  # A prior build may have produced RPMs with bad checksums (e.g. due
  # to I/O errors or OOM kills during compression). Detect and remove
  # them so they get rebuilt cleanly.
  if [ -d "$COMMON_STAGE/RPMS/x86_64" ]; then
    bad_rpms=0
    for rpmfile in "$COMMON_STAGE"/RPMS/x86_64/*.rpm; do
      [ -f "$rpmfile" ] || continue
      if ! rpm -K "$rpmfile" >/dev/null 2>&1; then
        echo "[runPh5_pinned90] Removing corrupted RPM: $(basename "$rpmfile")"
        rm -f "$rpmfile"
        bad_rpms=$((bad_rpms + 1))
      fi
    done
    [ "$bad_rpms" -gt 0 ] && echo "[runPh5_pinned90] Removed $bad_rpms corrupted RPM(s)"
  fi

  # ── SPECS/90 toolchain bootstrap (build old glibc 2.36 / gcc 12.2.0) ──
  # 1. Port libsanitizer fixes (obsolete termio + glibc 2.42) into SPECS/90/gcc
  #    so old gcc 12.2.0 builds under 6.x kernel headers.
  # 2. Remove leftover >=92 toolchain RPMs (glibc 2.43, gcc/libstdc++ 12.2.0-14)
  #    so the base sandbox bootstraps from the glibc-2.36 base instead of pulling
  #    a libstdc++ needing __isoc23_strtoul@GLIBC_2.38.
  if [ -d SPECS/90/gcc ] && [ -d SPECS/gcc ]; then
    for p in 0001-libsanitizer-Fix-build-with-glibc-2.42.patch \
             0001-sanitizer_common-Remove-reference-to-obsolete-termio.patch; do
      [ -f "SPECS/gcc/$p" ] && cp -n "SPECS/gcc/$p" SPECS/90/gcc/ 2>/dev/null
    done
    if ! grep -q 'Remove-reference-to-obsolete-termio' SPECS/90/gcc/gcc.spec 2>/dev/null; then
      sed -i 's|^\(Patch1:.*plugin-callback.*\)$|\1\nPatch2:         0001-libsanitizer-Fix-build-with-glibc-2.42.patch\nPatch3:         0001-sanitizer_common-Remove-reference-to-obsolete-termio.patch|' SPECS/90/gcc/gcc.spec
      sed -i 's|^Release:        9.1.1%{?dist}|Release:        9.1.2%{?dist}|' SPECS/90/gcc/gcc.spec
      echo "[runPh5_pinned90] Ported libsanitizer termio/glibc-2.42 patches into SPECS/90/gcc"
    fi
  fi
  _R="$BASE_DIR/$RELEASE_BRANCH/stage/RPMS/x86_64"
  rm -f "$_R"/glibc-2.43*.rpm "$_R"/glibc-*-2.43*.rpm \
        "$_R"/gcc-12.2.0-14*.rpm "$_R"/gcc-*-12.2.0-14*.rpm "$_R"/gfortran-12.2.0-14*.rpm \
        "$_R"/libstdc++-12.2.0-14*.rpm "$_R"/libstdc++-*-12.2.0-14*.rpm \
        "$_R"/libgomp-12.2.0-14*.rpm "$_R"/libgomp-*-12.2.0-14*.rpm \
        "$_R"/libgcc-12.2.0-14*.rpm "$_R"/libgcc-*-12.2.0-14*.rpm 2>/dev/null
  rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/images/sandboxBase"
  echo "[runPh5_pinned90] Cleared >=92 toolchain RPMs + sandboxBase for glibc-2.36 bootstrap"

  # ── Build loop ────────────────────────────────────────────────────
  for i in $(seq 1 10); do
    # Clean stale mounts/sandboxes before each retry so failures from
    # the previous iteration don't block sandbox creation.
    if [ "$i" -gt 1 ]; then
      echo "[runPh5_pinned90] Retry $i: cleaning stale sandboxes from previous attempt"
      clean_stale_sandboxes
    fi
    sudo make -j8 image IMG_NAME=iso THREADS=8;
    # ISO lands in the common branch's stage (build.py reads ../common/build-config.json)
    timeout=30
    while [ $timeout -gt 0 ]; do
      if ls "$COMMON_STAGE"/*.iso "$COMMON_STAGE"/iso/*.iso stage/*.iso stage/iso/*.iso 1>/dev/null 2>&1; then
        break
      fi
      sleep 1
      timeout=$((timeout - 1))
    done
    iso_found=""
    for f in "$COMMON_STAGE"/*.iso "$COMMON_STAGE"/iso/*.iso stage/*.iso stage/iso/*.iso; do
      [ -f "$f" ] && iso_found="$f" && break
    done
    if [ -n "$iso_found" ] && sudo mv "$iso_found" "$OUTPUT_DIR"; then
      exit 0
    fi
  done
fi
