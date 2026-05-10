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

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-5.0}"
OUTPUT_DIR="${4:-/mnt/c/Users/dcaso/Downloads/Ph-Builds}"

sleep 3
if ping -c 4 www.google.ch > /dev/null 2>&1; then
  if [ ! -d "$BASE_DIR/$COMMON_BRANCH" ]; then
    git clone https://github.com/dcasota/photonos-scripts.git -b "$COMMON_BRANCH" "$BASE_DIR/$COMMON_BRANCH"
  fi
  cd "$BASE_DIR/$COMMON_BRANCH"
  git fetch 2>/dev/null || true
  git merge 2>/dev/null || true
  cd "$BASE_DIR"
  if [ ! -d "$BASE_DIR/$RELEASE_BRANCH" ]; then
    git clone https://github.com/dcasota/photonos-scripts.git -b "$RELEASE_BRANCH" "$BASE_DIR/$RELEASE_BRANCH"
  fi
  cd "$BASE_DIR/$RELEASE_BRANCH"
  git fetch
  git merge --autostash

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

  # ── Fix POI image: use local photon/installer if remote is unavailable ─
  # The hardcoded Broadcom POI image (projects.packages.broadcom.com/…) may
  # not be accessible. If a local photon/installer image exists, configure
  # the build to use it instead.
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

  # ── Fix Python 3 PGO test flake in WSL2 ────────────────────────────
  # Python's --enable-optimizations runs test_generators for PGO profiling.
  # test_generators.SignalAndYieldFromTest is flaky under WSL2 (signal
  # delivery timing differs from native Linux), causing the entire build
  # to fail. Override PROFILE_TASK to exclude it. Only applied in WSL2.
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    PY3_SPEC="SPECS/python3/python3.spec"
    if [ -f "$PY3_SPEC" ] && ! grep -q 'PROFILE_TASK' "$PY3_SPEC"; then
      sed -i 's|^%make_build$|PROFILE_TASK="-m test --pgo -x test_generators" %make_build|' "$PY3_SPEC"
      echo "[runPh5_normal] Fixed python3 spec: excluded test_generators from PGO"
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
    [ -z "$url" ] && return 1
    echo "[runPh5_normal] Fetching source: $archive"
    wget -q "$url" -O "$target" 2>/dev/null && return 0
    echo "[runPh5_normal] WARNING: Failed to fetch $archive from $url"
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
      echo "[runPh5_normal] Cleaned stale build sandboxes"
    fi
  }

  # ── Initial cleanup before build loop ──────────────────────────
  clean_stale_sandboxes
  if [ -d "$COMMON_STAGE/SRPMS" ]; then
    rm -rf "$COMMON_STAGE/SRPMS"/*
    echo "[runPh5_normal] Cleaned stale SRPMs"
  fi
  if [ -d "$COMMON_STAGE/LOGS" ]; then
    rm -rf "$COMMON_STAGE/LOGS"/*
    echo "[runPh5_normal] Cleaned stale build logs"
  fi
  tdnf clean all 2>/dev/null
  echo "[runPh5_normal] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

  # ── Remove corrupted RPMs that would block dependency installs ────
  # A prior build may have produced RPMs with bad checksums (e.g. due
  # to I/O errors or OOM kills during compression). Detect and remove
  # them so they get rebuilt cleanly.
  if [ -d "$COMMON_STAGE/RPMS/x86_64" ]; then
    bad_rpms=0
    for rpmfile in "$COMMON_STAGE"/RPMS/x86_64/*.rpm; do
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
  for i in $(seq 1 10); do
    # Clean stale mounts/sandboxes before each retry so failures from
    # the previous iteration don't block sandbox creation.
    if [ "$i" -gt 1 ]; then
      echo "[runPh5_normal] Retry $i: cleaning stale sandboxes from previous attempt"
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
