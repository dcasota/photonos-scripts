#!/bin/sh

# Photon OS build script (uses common branch build system)
#
# Architecture: The 6.0/Makefile pushes to ../common and invokes build.py
# there with common/build-config.json for SPECS and package-build logic.
# The 6.0 branch supplies only the Makefile and branch-specific config
# overrides -- BUT `make image` still runs with the RELEASE worktree
# (6.0/) as its cwd, and build.py resolves "stage-path" (./stage) from
# THAT worktree, not from common/. RPMS, SRPMS, LOGS, chroot sandboxes,
# and the finished ISO therefore land under $RELEASE_BRANCH/stage, while
# $COMMON_BRANCH/stage stays empty. See BUILD_STAGE below -- do not
# revert cleanup/ISO-detection code to point at COMMON_STAGE.
#
# Parameters with defaults:
# $1 - Base directory (default: /root)
# $2 - Common branch name (default: common)
# $3 - Release branch name (default: 6.0)
# $4 - Output directory (default: /mnt/c/Users/dcaso/Downloads/Ph-Builds)
# $5 - Image type (default: minimal-iso; pass "iso" for the full ISO)
# $6 - FIPS canister mode (default: prebuilt; build|acvp|kat)

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-6.0}"
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
    echo "[runPh6] ERROR: unsupported image type '$IMG_TYPE'" 1>&2
    echo "[runPh6]        valid: iso (full), minimal-iso (default), basic-iso, rt-iso" 1>&2
    exit 1
    ;;
esac
echo "[runPh6] Image type: $IMG_TYPE"

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
CANISTER_MODE="${6:-prebuilt}"
case "$CANISTER_MODE" in
  prebuilt|build|acvp|kat) ;;
  *)
    echo "[runPh6] ERROR: unsupported canister mode '$CANISTER_MODE'" 1>&2
    echo "[runPh6]        valid: prebuilt (default), build, acvp, kat" 1>&2
    exit 1
    ;;
esac
echo "[runPh6] Canister mode: $CANISTER_MODE"
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

  # ── Determine the real stage path ───────────────────────────────
  # This script's header comment claims "SPECS, stage, and build output
  # all live under /root/common/" -- i.e. that make/build.py resolve
  # stage-path from the COMMON branch's own build-config.json. That is
  # NOT what happens: `make image` runs in the RELEASE worktree and
  # resolves "stage-path" (./stage) relative to IT, so RPMS, SRPMS, LOGS
  # and the chroot sandboxes all land in $RELEASE_BRANCH/stage.
  # $COMMON_BRANCH/stage stays empty. Using it (as this script previously
  # did throughout) meant sandbox cleanup, SRPMS/LOGS cleanup and stale-ISO
  # removal silently did nothing every run.
  BUILD_STAGE=$(cd "$BASE_DIR/$RELEASE_BRANCH" 2>/dev/null && \
    realpath "$(jq -r '.["stage-path"] // "./stage"' build-config.json 2>/dev/null)" 2>/dev/null)
  [ -d "$BUILD_STAGE" ] || BUILD_STAGE="$BASE_DIR/$RELEASE_BRANCH/stage"
  echo "[runPh6] Build stage: $BUILD_STAGE"

  # ── Free disk space and clean stale build artifacts ─────────────
  # COMMON_STAGE is kept defined (empty though it normally is) so the ISO
  # search below can still check it in case a future build-config.json
  # change routes output there.
  COMMON_STAGE="$BASE_DIR/$COMMON_BRANCH/stage"

  for mp in $(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r); do
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
  done
  if [ -d "$BUILD_STAGE/photonroot" ]; then
    rm -rf "$BUILD_STAGE/photonroot"/*
    echo "[runPh6] Cleaned stale build sandboxes"
  fi
  if [ -d "$BUILD_STAGE/SRPMS" ]; then
    rm -rf "$BUILD_STAGE/SRPMS"/*
    echo "[runPh6] Cleaned stale SRPMs"
  fi
  if [ -d "$BUILD_STAGE/LOGS" ]; then
    rm -rf "$BUILD_STAGE/LOGS"/*
    echo "[runPh6] Cleaned stale build logs"
  fi
  # Remove stale ISOs so img_present() doesn't short-circuit
  rm -f "$BUILD_STAGE"/*.iso 2>/dev/null
  # Clean stale ISO staging directories
  if [ -d "$BUILD_STAGE/iso" ]; then
    find "$BUILD_STAGE/iso" -maxdepth 1 -name 'photon-*' -type d -exec rm -rf {} +
    rm -f "$BUILD_STAGE/iso/iso.yaml"
    rm -f "$BUILD_STAGE/iso"/*.rpm-list
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
  # COPY trailing-slash fix the legacy builder requires (merged upstream as
  # PR #38; the sed below is kept for older checkouts that predate it). The
  # image is only the ISO build tool; the installer that ships inside the
  # ISO comes from the patched photon-os-installer RPM built above.
  # The image must also contain `file`. photon_installer/generate_initrd.py's
  # strip_if_needed() runs subprocess.check_output(["file", path]) on every
  # file it puts in the initrd, but older POI Dockerfiles never install it,
  # so ISO assembly dies with
  #   FileNotFoundError: [Errno 2] No such file or directory: 'file'
  # in generateInitrd() -- *after* every package has been rebuilt, and the
  # retry loop below would then burn attempts on it. Check the image for
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
        && echo "[runPh6] Built photon/installer:latest" \
        || echo "[runPh6] WARNING: failed to build photon/installer image"
    fi
    if ! poi_image_ok; then
      echo "[runPh6] ERROR: photon/installer:latest is missing or has no 'file'" 1>&2
      echo "[runPh6]        binary. ISO assembly would fail in generateInitrd()" 1>&2
      echo "[runPh6]        after every package has been rebuilt -- aborting now." 1>&2
      exit 1
    fi
  fi

  # ── Point the build at the local POI image ────────────────────────

  # ── Per-package build options: FIPS canister macros ───────────────
  # build.py reads the path from build-config.json
  # ["photon-build-param"]["pkg-build-options"] and loads it via
  # Builder.get_packages_with_build_options(), which is guarded by
  # os.path.exists() -- so a path that does not resolve is silently ignored.
  # The shipped value is the bare name "pkg_build_options.json"; build.py runs
  # with cwd=$COMMON_BRANCH (the Makefile pushd), where no such file exists,
  # so the whole mechanism is currently inert. Write an absolute path to a
  # generated file kept OUTSIDE both git trees, so nothing tracked is dirtied.
  PKG_BUILD_OPTIONS="$BASE_DIR/photon-pkg-build-options.json"
  python3 -c "
import json, sys
mode = sys.argv[1]
macros = {'prebuilt': [], 'build': ['canister_build 1'],
          'acvp': ['acvp_build 1'], 'kat': ['kat_build 1']}[mode]
opts = {p: {'pullsources': [], 'macros': list(macros)} for p in ('linux', 'linux-esx')}
with open(sys.argv[2], 'w') as f:
    json.dump(opts, f, indent=4)
" "$CANISTER_MODE" "$PKG_BUILD_OPTIONS" && \
    echo "[runPh6] Canister macros -> $PKG_BUILD_OPTIONS"

  COMMON_CFG="$BASE_DIR/$COMMON_BRANCH/build-config.json"
  # Point build.py at the generated options file. Also repairs the shipped
  # relative path, which never resolves from build.py's cwd.
  if [ -f "$COMMON_CFG" ]; then
    python3 -c "
import json
with open('$COMMON_CFG') as f:
    cfg = json.load(f)
cfg.setdefault('photon-build-param', {})['pkg-build-options'] = '$PKG_BUILD_OPTIONS'
with open('$COMMON_CFG', 'w') as f:
    json.dump(cfg, f, indent=4)
" 2>/dev/null && echo "[runPh6] pkg-build-options -> $PKG_BUILD_OPTIONS"
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
" 2>/dev/null && echo "[runPh6] Set poi-image to local photon/installer:latest"
    fi
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
  # "make -e" overrides it). A "PROFILE_TASK=... %make_build" prefix (a
  # shell env-var prefix) is therefore silently ignored -- the build then
  # trains on the stock 43-test PGO set and dies at
  #   make: *** [Makefile:1012: profile-run-stamp] Error 2
  # Emitting it after %make_build instead makes it a make command-line
  # variable, which does win. Keep ^%make_build$ anchored so this does not
  # also match a "%make_build test" line inside %check.
  if grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    PY3_SPEC="SPECS/python3/python3.spec"
    if [ -f "$PY3_SPEC" ] && ! grep -q 'PROFILE_TASK' "$PY3_SPEC"; then
      sed -i 's|^%make_build$|%make_build PROFILE_TASK="-m test --pgo -x test_generators"|' "$PY3_SPEC"
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
  #
  # ISO detection: poi.py writes the image into $BUILD_STAGE/<IMG_NAME>/
  # (e.g. stage/iso/photon-iso-<ver>-<sha>.x86_64.iso), not necessarily
  # directly into stage/. A stale ISO from an older run must not be
  # mistaken for this run's output (which would exit 0 and hand back the
  # wrong image), so an iso_marker is dropped right before `make` and
  # only ISOs newer than it are considered. The guards below exist so
  # retries are never wasted on work that is already done or that can
  # never succeed:
  #   1. success moves the ISO and exits immediately.
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
  mkdir -p "$BUILD_STAGE" 2>/dev/null
  prev_make_rc=""
  prev_progress=""
  for i in $(seq 1 10); do
    echo "[runPh6] Build attempt $i/10 starting at $(date)"
    # Drop a marker first: an ISO left in the stage by an older run must
    # not be mistaken for this run's output.
    iso_marker="$BUILD_STAGE/.runph6-iso-marker"
    : > "$iso_marker" 2>/dev/null
    # Run in background so the cleanup trap fires when Ctrl-C reaches
    # us during `wait` — synchronous foreground execution would let
    # SIGINT terminate make + sudo while leaving rpmbuild/gcc orphans
    # under WSL2's signal-forwarding behaviour.
    # 4h timeout to allow long builds (kernel, rust) to complete.
    timeout 14400 sudo make -j$(( $(nproc) - 1 )) image \
      IMG_NAME="$IMG_TYPE" THREADS=$(( $(nproc) - 1 )) &
    BUILD_PID=$!
    wait "$BUILD_PID"
    rc=$?
    BUILD_PID=
    if [ $rc -eq 124 ]; then
      echo "[runPh6] WARNING: Build timed out after 4 hours on attempt $i"
    fi

    # ── Locate the finished ISO ───────────────────────────────────
    # Search one level deep under both stages (BUILD_STAGE is the real
    # one; COMMON_STAGE is checked too in case that ever changes), and
    # take the newest match so a stale ISO from an older run is never
    # mistaken for this run's output.
    iso_globs() {
      find "$BUILD_STAGE" "$COMMON_STAGE" -maxdepth 2 -name '*.iso' \
           -newer "$iso_marker" -print 2>/dev/null | xargs -r ls -t 2>/dev/null
    }
    timeout_wait=30
    while [ $timeout_wait -gt 0 ]; do
      [ -n "$(iso_globs | head -1)" ] && break
      sleep 1
      timeout_wait=$((timeout_wait - 1))
    done
    iso_found=$(iso_globs | head -1)
    if [ -n "$iso_found" ]; then
      echo "[runPh6] Built ISO: $iso_found ($(du -h "$iso_found" | cut -f1))"
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
        echo "[runPh6] Identical ISO already present at $dup_found (sha256 $iso_sha) -- not moving/overwriting; nothing left to do."
        exit 0
      fi
      dest="$OUTPUT_DIR/$(basename "$iso_found")"
      if [ -e "$dest" ]; then
        # Same filename but different content (checked above): never
        # silently destroy the existing file, deliver under a distinct
        # name instead.
        dest="$OUTPUT_DIR/$(date +%Y%m%d-%H%M%S)-$(basename "$iso_found")"
        echo "[runPh6] $OUTPUT_DIR/$(basename "$iso_found") already exists with different content; delivering new ISO as $(basename "$dest") instead"
      fi
      if sudo mv "$iso_found" "$dest"; then
        echo "[runPh6] Moved ISO to $dest"
        exit 0
      fi
      echo "[runPh6] ERROR: could not move ISO to $dest" 1>&2
      echo "[runPh6]        It is still at: $iso_found" 1>&2
      exit 1
    fi

    # ── No ISO this attempt: decide whether another retry can help ────
    # "progress" = number of files touched anywhere in the stages since
    # the marker was dropped. If two consecutive attempts both fail with
    # the same make exit code and both touch nothing, the build is stuck
    # in the same deterministic way -- retrying it won't change the
    # outcome, it will just burn the remaining budget re-running for
    # hours to reproduce the same error.
    #
    # This MUST be measured before the stale-ISO-dir cleanup below: that
    # cleanup's "rm -rf" bumps the mtime of $BUILD_STAGE/iso whenever it
    # actually removes something, which made an attempt that produced
    # nothing at all report "1 file(s) touched" and suppressed the
    # deterministic-failure early stop for a whole extra 4-hour attempt.
    progress=$(find "$BUILD_STAGE" "$COMMON_STAGE" -newer "$iso_marker" 2>/dev/null | wc -l)
    # Clean stale ISO staging directories left by an aborted/timed-out
    # attempt so they don't confuse the next iteration's search.
    find "$BUILD_STAGE/iso" -maxdepth 1 -name 'photon-*' -type d -exec rm -rf {} + 2>/dev/null
    echo "[runPh6] Attempt $i: no ISO produced (make exit=$rc, $progress file(s) touched since marker)"
    if [ "$i" -gt 1 ] && [ "$rc" = "$prev_make_rc" ] && [ "$progress" = "0" ] && [ "$prev_progress" = "0" ]; then
      echo "[runPh6] ERROR: attempt $i failed identically to attempt $((i - 1)) (same make exit code, zero new output both times)." 1>&2
      echo "[runPh6]        This looks like a deterministic failure, not a flaky one -- further retries would just reproduce it." 1>&2
      echo "[runPh6]        Stopping after $i/10 attempts. Fix the underlying build error, then re-run." 1>&2
      exit 1
    fi
    prev_make_rc=$rc
    prev_progress=$progress
  done
  echo "[runPh6] ERROR: exhausted all 10 attempts without producing an ISO" 1>&2
  exit 1
else
  # The entire build is gated on this reachability check. Without an
  # else branch the script fell off the end of the "if" and exited 0
  # having built nothing -- indistinguishable from a successful
  # delivery to any caller that checks $?. Never exit 0 without an ISO.
  echo "[runPh6] ERROR: no network (ping www.google.ch failed); the build" 1>&2
  echo "[runPh6]        needs to fetch sources and was not started." 1>&2
  exit 1
fi
