#!/bin/sh

# Photon OS build script (uses common branch build system)
#
# Architecture: The 6.0/Makefile pushes to ../common and uses
# common/build-config.json. SPECS, stage, and build output all
# live under /root/common/. The 6.0 branch provides only the
# Makefile and branch-specific config overrides.
#
# Parameters with defaults:
# $1 - Base directory (default: /root)
# $2 - Common branch name (default: common)
# $3 - Release branch name (default: 6.0)
# $4 - Output directory (default: /mnt/c/Users/dcaso/Downloads/Ph-Builds)

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-6.0}"
OUTPUT_DIR="${4:-/mnt/c/Users/dcaso/Downloads/Ph-Builds}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Signal handling: tear down full build tree on kill ─────────────
# Without a trap, killing runPh6.sh leaves orphaned rpmbuild/gcc/java
# subtrees alive — sudo+make breaks normal SIGINT propagation under
# WSL2 once child PIDs reparent. Kill descendants explicitly, twice
# (TERM then KILL), and unmount any sandbox mounts left behind.
SCRIPT_PID=$$
BUILD_PID=
_cleanup() {
  trap '' INT TERM HUP EXIT
  sig=${1:-EXIT}
  echo "[runPh6] Signal $sig received — terminating build tree"
  # Descendant walk: collect all transitive children of our PID.
  pids=$(ps -e -o pid=,ppid= 2>/dev/null | awk -v root="$SCRIPT_PID" '
    { ch[$2]=ch[$2] " " $1 }
    END {
      n=split(root, q, " ")
      for (i=1; i<=n; i++) out[q[i]]=1
      head=1
      while (head<=n) {
        for (k in ch) if (k==q[head]) {
          m=split(ch[k], kids, " ")
          for (j=1; j<=m; j++) if (kids[j]!="" && !(kids[j] in out)) {
            out[kids[j]]=1; n++; q[n]=kids[j]
          }
        }
        head++
      }
      for (p in out) if (p!=root) print p
    }')
  if [ -n "$pids" ]; then
    kill -TERM $pids 2>/dev/null
    sleep 5
    kill -KILL $pids 2>/dev/null
  fi
  # Belt-and-suspenders: catch any second-level orphans.
  pkill -KILL -P "$SCRIPT_PID" 2>/dev/null
  # Unmount sandbox mounts the build may have left behind, deepest first.
  mount 2>/dev/null | awk '/stage\/photonroot/ {print $3}' | sort -r | \
    while read -r mp; do
      umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
    done
  [ "$sig" = "EXIT" ] || exit 130
}
trap '_cleanup INT' INT
trap '_cleanup TERM' TERM
trap '_cleanup HUP' HUP

# Clear any tdnf exclude file leaked from a prior pinned91 run. TDNFSandbox.py
# reads /tmp/photon-tdnf-exclude-pkgs.txt unconditionally; runPh5_pinned91
# writes "libcap-libs*" there, which is wrong for runPh6 (we use the
# photon_release URL where libcap-libs doesn't even exist) and breaks every
# toolchain install with rc 21 / "package libcap-libs-2.77 is disabled".
rm -f /tmp/photon-tdnf-exclude-pkgs.txt
unset PHOTON_TDNF_EXCLUDE_PKGS

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

  # ── Configure common build-config.json for FIPS ──────────────────
  # build.py reads the COMMON branch's build-config.json (Makefile pushes
  # into ../common before invoking build.py), so photon-subrelease must be
  # propagated from the release branch's config into the common one —
  # otherwise build.py aborts with "ERROR: photon-subrelease is empty".
  COMMON_CFG="$BASE_DIR/$COMMON_BRANCH/build-config.json"
  RELEASE_CFG="$BASE_DIR/$RELEASE_BRANCH/build-config.json"

  python3 -c "
import json
release_bp = json.load(open('$RELEASE_CFG')).get('photon-build-param', {})
subrelease = str(release_bp.get('photon-subrelease', '100'))

cfg = json.load(open('$COMMON_CFG'))
bp = cfg['photon-build-param']
bp['ossl-fips-in-make-check'] = True
bp['poi-image'] = 'photon/installer:latest'
bp['photon-subrelease'] = subrelease
if 'photon-mainline' not in bp:
    bp['photon-mainline'] = subrelease
# Pin to the GA-frozen mirror. The default photon_5.0_x86_64 carries every
# version published since GA — depsolve picks newest of each, dragging in
# glibc-2.43 / libxcrypt-4.5.2 / gcc-12.2.0-12 / rpm-6.0.1+libcap-libs split.
# All of those are incompatible with our local glibc-2.38 / pre-split libcap.
# photon_release_5.0_x86_64 is the GA snapshot only (glibc-2.36-4, libxcrypt
# 4.4.36-3, gcc-12.2.0-1, rpm-4.18.0, libcap-2.66 monolithic) — every package
# requires GLIBC ≤ 2.36, compatible with 2.38-2 by forward-compat. Neither
# tdnf --exclude=NAME (filters by name only, not version) nor repo
# excludepkgs= work for version-specific exclusion (verified).
bp['package-repo-url'] = 'https://packages.broadcom.com/photon/\$releasever/photon_release_\$releasever_\$basearch'
json.dump(cfg, open('$COMMON_CFG', 'w'), indent=4)
print('[runPh6] FIPS: ossl-fips-in-make-check=true, subrelease=' + bp['photon-subrelease'] + ', mainline=' + bp['photon-mainline'])
print('[runPh6] package-repo-url pinned to photon_release (GA-frozen) for ABI-stable toolchain')
"

  echo "[runPh6] FIPS kernel: CONFIG_CRYPTO_FIPS=y (built-in)"
  echo "[runPh6] FIPS userspace: openssl-fips-provider (fips.so)"

  # ── Invalidate stale sandboxBase if package-repo-url changed ──────
  # PackageManager._createBuildImage caches stage/images/sandboxBase across
  # runs (shouldOverwrite() only re-builds it when a stage marker mismatches).
  # If the package-repo-url switched repos (e.g. photon_5.0 → photon_release),
  # the cached sandboxBase still has packages from the OLD repo (libcap-libs
  # 2.77 split, glibc-2.43, etc.) — those leak into every per-build sandbox
  # and cause "package X conflicts with Y" failures during toolchain install.
  # Detect mismatch via a marker file we write next to sandboxBase.
  STAGE_DIR="$BASE_DIR/$RELEASE_BRANCH/stage"
  CURRENT_URL=$(python3 -c "import json; print(json.load(open('$COMMON_CFG'))['photon-build-param']['package-repo-url'])" 2>/dev/null)
  URL_MARKER="$STAGE_DIR/images/sandboxBase.repo-url"
  if [ -d "$STAGE_DIR/images/sandboxBase" ] && [ -n "$CURRENT_URL" ]; then
    PREV_URL=$(cat "$URL_MARKER" 2>/dev/null)
    if [ "$PREV_URL" != "$CURRENT_URL" ]; then
      echo "[runPh6] package-repo-url changed (old: ${PREV_URL:-none}, new: $CURRENT_URL); wiping sandboxBase"
      rm -rf "$STAGE_DIR/images/sandboxBase"
    fi
  fi
  # (Re)record the URL after possible regen — written even when sandboxBase
  # doesn't exist yet, so the next run's compare uses the correct baseline.
  mkdir -p "$STAGE_DIR/images"
  echo "$CURRENT_URL" > "$URL_MARKER"

  # ── Validate / repair source archives in stage/SOURCES ─────────
  # PullSources falls back to the configured pull-sources URL when a
  # cached archive's sha512 does not match config.yaml. If the URL is
  # unreachable, the build aborts with "Missing source: <archive>".
  # Detect mismatches up-front and try to recover from the common
  # branch's cache (which is usually the canonical good copy).
  validate_or_recover_source() {
    archive="$1"; expected_sha="$2"
    target="$BASE_DIR/$RELEASE_BRANCH/stage/SOURCES/$archive"
    backup="$BASE_DIR/$COMMON_BRANCH/stage/SOURCES/$archive"
    [ -f "$target" ] || return 0
    [ -z "$expected_sha" ] && return 0
    actual=$(sha512sum "$target" 2>/dev/null | awk '{print $1}')
    [ "$actual" = "$expected_sha" ] && return 0
    echo "[runPh6] sha512 mismatch for $archive (cached: ${actual:0:12}…, expected: ${expected_sha:0:12}…)"
    if [ -f "$backup" ]; then
      backup_sha=$(sha512sum "$backup" 2>/dev/null | awk '{print $1}')
      if [ "$backup_sha" = "$expected_sha" ]; then
        cp -f "$backup" "$target"
        echo "[runPh6] Restored $archive from $backup"
        return 0
      fi
    fi
    rm -f "$target"  # force redownload via PullSources URL
    echo "[runPh6] Removed bad $archive; PullSources will redownload"
  }
  find "$BASE_DIR/$RELEASE_BRANCH/SPECS" -name config.yaml -print0 2>/dev/null | while IFS= read -r -d '' cfg; do
    python3 -c "
import yaml
with open('$cfg') as f:
    data = yaml.safe_load(f) or {}
for s in data.get('sources', []) or []:
    a = s.get('archive', '') or ''
    h = s.get('archive_sha512sum', '') or ''
    if a and h:
        print(a + '|' + h)
" 2>/dev/null | while IFS='|' read -r archive sha; do
      validate_or_recover_source "$archive" "$sha"
    done
  done

  # ── Fix OpenJDK WSL2 detection in chroot ───────────────────────────
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    for jdk_spec in "$BASE_DIR/$COMMON_BRANCH"/SPECS/openjdk/openjdk*.spec; do
      [ -f "$jdk_spec" ] || continue
      if grep -q 'sh ./configure' "$jdk_spec" && ! grep -q 'build=x86_64-unknown-linux-gnu' "$jdk_spec"; then
        sed -i 's|--disable-warnings-as-errors$|--disable-warnings-as-errors \\\n    --build=x86_64-unknown-linux-gnu|' "$jdk_spec"
        echo "[runPh6] Fixed $(basename "$jdk_spec"): added --build for WSL2"
      fi
    done
  fi

  # ── Free disk space and clean stale build artifacts ─────────────
  COMMON_STAGE="$BASE_DIR/$COMMON_BRANCH/stage"

  for mp in $(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r); do
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
  done
  if [ -d "$COMMON_STAGE/photonroot" ]; then
    rm -rf "$COMMON_STAGE/photonroot"/*
    echo "[runPh6] Cleaned stale build sandboxes"
  fi
  if [ -d "$COMMON_STAGE/SRPMS" ]; then
    rm -rf "$COMMON_STAGE/SRPMS"/*
    echo "[runPh6] Cleaned stale SRPMs"
  fi
  if [ -d "$COMMON_STAGE/LOGS" ]; then
    rm -rf "$COMMON_STAGE/LOGS"/*
    echo "[runPh6] Cleaned stale build logs"
  fi
  # Remove stale ISOs so img_present() doesn't short-circuit
  rm -f "$COMMON_STAGE"/*.iso 2>/dev/null
  # Clean stale ISO staging directories
  if [ -d "$COMMON_STAGE/iso" ]; then
    find "$COMMON_STAGE/iso" -maxdepth 1 -name 'photon-*' -type d -exec rm -rf {} +
    rm -f "$COMMON_STAGE/iso/iso.yaml"
    rm -f "$COMMON_STAGE/iso"/*.rpm-list
    echo "[runPh6] Cleaned stale ISO staging directories"
  fi
  tdnf clean all 2>/dev/null
  echo "[runPh6] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

  # ── Bootstrap seed: libxcrypt-4.4.36-4.1 in stage/RPMS ────────────
  # libxcrypt's own toolchain RPM bootstrap pulls 'libxcrypt' + 'libxcrypt-devel'
  # via listToolChainRPMsToInstall. On a clean tree there's no local libxcrypt,
  # so tdnf falls back to upstream's libxcrypt-4.5.2-1 — which Requires GLIBC_2.43,
  # unsatisfiable against our local glibc-2.38-2 → rc 21 "Solv general runtime error".
  # Seed the older 4.4.36-4.1 (Requires only GLIBC_2.36; compatible with 2.38) into
  # stage/RPMS at priority=10. Our local libxcrypt build then produces 4.4.36-5,
  # which beats the seed on NEVR after the build completes.
  STAGE_RPMS="$BASE_DIR/$RELEASE_BRANCH/stage/RPMS"
  STAGE_X86="$STAGE_RPMS/x86_64"
  mkdir -p "$STAGE_X86"
  if ! ls "$STAGE_X86"/libxcrypt-4.4.36-*.ph5.x86_64.rpm 1>/dev/null 2>&1; then
    echo "[runPh6] Seeding libxcrypt-4.4.36-4.1 from upstream Photon 5.0"
    SEED_REPO="$(mktemp -d -t libxseed-XXXX)"
    cat > "$SEED_REPO/packages.repo" <<EOF
[packages]
name=packages
enabled=1
gpgcheck=0
priority=100
baseurl=https://packages.broadcom.com/photon/\$releasever/photon_\$releasever_\$basearch
EOF
    SEED_DL="$(mktemp -d -t libxdl-XXXX)"
    if tdnf --setopt=reposdir="$SEED_REPO" --releasever=5.0 --disablerepo=* --enablerepo=packages \
            install -y --downloadonly --downloaddir="$SEED_DL" \
            libxcrypt-4.4.36-4.1.ph5 libxcrypt-devel-4.4.36-4.1.ph5 >/dev/null 2>&1; then
      cp "$SEED_DL"/libxcrypt-4.4.36-4.1.ph5.x86_64.rpm \
         "$SEED_DL"/libxcrypt-devel-4.4.36-4.1.ph5.x86_64.rpm "$STAGE_X86"/ 2>/dev/null
      createrepo_c --update "$STAGE_RPMS" >/dev/null 2>&1
      echo "[runPh6] Seeded libxcrypt-4.4.36-4.1 RPMs into local repo"
    else
      echo "[runPh6] WARNING: Failed to seed libxcrypt; libxcrypt build will fail"
    fi
    rm -rf "$SEED_REPO" "$SEED_DL"
  fi

  # ── Ensure GNU wget (build.py uses `wget -P`, toybox wget rejects -P) ──
  # The toybox package on Photon ships a /usr/bin/wget symlink that can
  # overwrite the GNU wget binary when toybox is (re)installed. build.py's
  # create_ph_builder_img() then aborts with "wget: Unknown option 'P'".
  if ! wget --help 2>&1 | grep -q 'GNU Wget'; then
    echo "[runPh6] /usr/bin/wget is not GNU wget — reinstalling to restore it"
    tdnf reinstall -y wget >/dev/null 2>&1 || tdnf install -y wget >/dev/null 2>&1
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
      echo "[runPh6] sha512 mismatch for $archive (cached: ${actual:0:12}…, expected: ${expected_sha:0:12}…)"
      # Try recovering from the common branch's cache (often correct).
      if [ -f "$backup_dir/$archive" ]; then
        backup_sha=$(sha512sum "$backup_dir/$archive" 2>/dev/null | awk '{print $1}')
        if [ "$backup_sha" = "$expected_sha" ]; then
          cp -f "$backup_dir/$archive" "$target"
          echo "[runPh6] Restored $archive from $backup_dir"
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
      echo "[runPh6] Fetching source: $archive <- $src_url"
      # Download to a temp file: wget -O truncates the target to 0 bytes
      # before the request, so a 404/network failure would otherwise leave
      # an empty file that poisons the SOURCES cache.
      if wget -q "$src_url" -O "$target.tmp" 2>/dev/null && [ -s "$target.tmp" ]; then
        if [ -n "$expected_sha" ]; then
          dl_sha=$(sha512sum "$target.tmp" 2>/dev/null | awk '{print $1}')
          if [ "$dl_sha" != "$expected_sha" ]; then
            echo "[runPh6] WARNING: checksum mismatch for fetched $archive (got ${dl_sha:0:12}…), discarding"
            rm -f "$target.tmp"
            continue
          fi
        fi
        mv -f "$target.tmp" "$target"
        return 0
      fi
      rm -f "$target.tmp"
    done
    echo "[runPh6] WARNING: Failed to fetch $archive from any source"
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
        && echo "[runPh6] Built photon/installer:latest" \
        || echo "[runPh6] WARNING: failed to build photon/installer image"
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
" 2>/dev/null && echo "[runPh6] Set poi-image to local photon/installer:latest"
    fi
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
      echo "[runPh6] Fixed python3 spec: excluded test_generators from PGO"
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
    echo "[runPh6] Fixed sssd spec: serial %make_install"
  fi


  # --- Fix gcc 12.2.0 libsanitizer build under 6.x kernel headers ---
  # 6.0 builds gcc 12.2.0-9 against linux-api-headers 6.1.x where struct termio
  # was removed; old libsanitizer still references it (and breaks on glibc
  # >=2.42). Port the same two patches 5.0's gcc already carries.
  if [ -d SPECS/gcc ] && ! grep -q 'Remove-reference-to-obsolete-termio' SPECS/gcc/gcc.spec 2>/dev/null; then
    for p in 0001-libsanitizer-Fix-build-with-glibc-2.42.patch \
             0001-sanitizer_common-Remove-reference-to-obsolete-termio.patch; do
      [ -f "$SCRIPT_DIR/photonos-patches/gcc/$p" ] && cp "$SCRIPT_DIR/photonos-patches/gcc/$p" SPECS/gcc/ 2>/dev/null
    done
    sed -i 's|^\(Patch1:.*plugin-callback.*\)$|\1\nPatch2:         0001-libsanitizer-Fix-build-with-glibc-2.42.patch\nPatch3:         0001-sanitizer_common-Remove-reference-to-obsolete-termio.patch|' SPECS/gcc/gcc.spec
    sed -i 's|^Release:        9%{?dist}|Release:        9.1%{?dist}|' SPECS/gcc/gcc.spec
    echo "[runPh6] Ported libsanitizer termio/glibc-2.42 patches into SPECS/gcc"
  fi
  # ── Build loop ────────────────────────────────────────────────────
  # build.py's scheduler (PackageManager._buildPackages) already keeps
  # going across per-package failures: a failed rpmbuild only marks
  # that package broken; independent packages continue to build to
  # completion on the remaining worker threads. Each loop iteration
  # below is therefore mostly cheap on retry — only the still-failing
  # specs are rebuilt; the rest are reused from stage/RPMS.
  for i in $(seq 1 10); do
    echo "[runPh6] Build attempt $i/10 starting at $(date)"
    # Run in background so the cleanup trap fires when Ctrl-C reaches
    # us during `wait` — synchronous foreground execution would let
    # SIGINT terminate make + sudo while leaving rpmbuild/gcc orphans
    # under WSL2's signal-forwarding behaviour.
    # 4h timeout to allow long builds (kernel, rust) to complete.
    timeout 14400 sudo make -j$(( $(nproc) - 1 )) image \
      IMG_NAME=iso THREADS=$(( $(nproc) - 1 )) &
    BUILD_PID=$!
    wait "$BUILD_PID"
    rc=$?
    BUILD_PID=
    if [ $rc -eq 124 ]; then
      echo "[runPh6] WARNING: Build timed out after 4 hours on attempt $i"
      find "$COMMON_STAGE/iso" -maxdepth 1 -name 'photon-*' -type d -exec rm -rf {} + 2>/dev/null
      continue
    fi
    # ISO lands in common/stage/ (build.py's stagePath = common/stage)
    timeout_wait=30
    while [ $timeout_wait -gt 0 ]; do
      if ls "$COMMON_STAGE"/*.iso "$COMMON_STAGE"/iso/*.iso 1>/dev/null 2>&1; then
        break
      fi
      sleep 1
      timeout_wait=$((timeout_wait - 1))
    done
    if sudo mv "$COMMON_STAGE"/*.iso "$OUTPUT_DIR" 2>/dev/null || sudo mv "$COMMON_STAGE"/iso/*.iso "$OUTPUT_DIR" 2>/dev/null; then
      echo "[runPh6] ISO successfully moved to $OUTPUT_DIR"
      exit 0
    fi
    echo "[runPh6] No ISO produced on attempt $i (make exit code: $rc)"
  done
  echo "[runPh6] All 10 build attempts exhausted without producing an ISO"
fi
