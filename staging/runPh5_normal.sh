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
  git fetch
  git merge
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
  if grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
    for jdk_spec in SPECS/openjdk/openjdk*.spec; do
      [ -f "$jdk_spec" ] || continue
      if grep -q 'sh ./configure' "$jdk_spec" && ! grep -q 'build=x86_64-unknown-linux-gnu' "$jdk_spec"; then
        sed -i 's|--disable-warnings-as-errors$|--disable-warnings-as-errors \\\n    --build=x86_64-unknown-linux-gnu|' "$jdk_spec"
        echo "[runPh5_normal] Fixed $(basename "$jdk_spec"): added --build for WSL2"
      fi
    done
  fi

  # ── Fix perl-rpm-packaging missing debug_package disable ──────────
  # Pure-Perl noarch package has no debug symbols; rpm build fails with
  # "Empty %files file debugfiles.list" without this macro.
  PRP_SPEC="SPECS/perl-rpm-packaging/perl-rpm-packaging.spec"
  if [ -f "$PRP_SPEC" ] && ! grep -q 'debug_package' "$PRP_SPEC"; then
    sed -i '/%global build_if/a %define debug_package %{nil}' "$PRP_SPEC"
    echo "[runPh5_normal] Fixed perl-rpm-packaging: added debug_package disable"
  fi

  # ── Ensure builder-pkg-preq.json has libcap-libs ──────────────────
  if [ -f data/builder-pkg-preq.json ]; then
    python3 -c "
import json, sys
with open('data/builder-pkg-preq.json', 'r') as f:
    data = json.load(f)
rpms = data.get('listToolChainRPMsToInstall', [])
if 'libcap-libs' in rpms:
    sys.exit(0)
try:
    idx = rpms.index('libcap')
    rpms.insert(idx + 1, 'libcap-libs')
except ValueError:
    rpms.append('libcap-libs')
data['listToolChainRPMsToInstall'] = rpms
with open('data/builder-pkg-preq.json', 'w') as f:
    json.dump(data, f, indent=4)
    f.write('\n')
print('[runPh5_normal] Added libcap-libs to builder-pkg-preq.json')
" 2>/dev/null
  fi

  # ── Pre-fetch sources missing from Broadcom mirror ─────────────
  # New packages added to upstream may not yet be on the Broadcom
  # photon_sources mirror. Download directly from upstream if missing.
  fetch_missing_source() {
    archive="$1"; url="$2"; destdir="$BASE_DIR/$RELEASE_BRANCH/stage/SOURCES"
    [ -f "$destdir/$archive" ] && return 0
    echo "[runPh5_normal] Fetching missing source: $archive"
    mkdir -p "$destdir"
    wget -q "$url" -O "$destdir/$archive" 2>/dev/null && return 0
    echo "[runPh5_normal] WARNING: Failed to fetch $archive from $url"
    return 1
  }

  # Parse config.yaml files and fetch any source archives not yet cached.
  # Only runs for archives that are truly missing; no-ops once cached.
  find "$BASE_DIR/$RELEASE_BRANCH/SPECS" -name config.yaml -print0 2>/dev/null | while IFS= read -r -d '' cfg; do
    python3 -c "
import yaml, sys
with open('$cfg') as f:
    data = yaml.safe_load(f)
for s in data.get('sources', []):
    a = s.get('archive', '')
    u = s.get('url', '')
    if a and u:
        print(a + '|' + u)
" 2>/dev/null | while IFS='|' read -r archive url; do
      fetch_missing_source "$archive" "$url"
    done
  done

  # ── Fix sandbox bootstrap: remove rpm 6.x RPMs if deps missing ──
  # rpm-build 6.x requires perl-rpm-packaging. If that RPM hasn't been
  # built yet, tdnf can't install rpm-build into the sandbox. Remove
  # rpm 6.x RPMs to let tdnf fall back to rpm 4.x for bootstrapping;
  # rpm 6.x will then be built as a regular package in the right order.
  RPMSDIR="$BASE_DIR/$RELEASE_BRANCH/stage/RPMS/x86_64"
  if ls "$RPMSDIR"/rpm-build-6.*.rpm >/dev/null 2>&1 && \
     ! ls "$RPMSDIR"/perl-rpm-packaging-*.rpm >/dev/null 2>&1; then
    echo "[runPh5_normal] Removing rpm 6.x RPMs (perl-rpm-packaging not yet built)"
    rm -f "$RPMSDIR"/rpm-6.*.rpm "$RPMSDIR"/rpm-build-6.*.rpm \
          "$RPMSDIR"/rpm-build-libs-6.*.rpm "$RPMSDIR"/rpm-libs-6.*.rpm \
          "$RPMSDIR"/rpm-devel-6.*.rpm "$RPMSDIR"/rpm-lang-6.*.rpm \
          "$RPMSDIR"/rpm-sign-libs-6.*.rpm "$RPMSDIR"/rpm-debuginfo-6.*.rpm \
          "$RPMSDIR"/rpm-plugin-systemd-inhibit-6.*.rpm \
          "$RPMSDIR"/rpm-sequoia-*.rpm
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/images/sandboxBase"
  fi

  # ── Free disk space and clean stale build artifacts ─────────────
  for mp in $(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r); do
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
  done
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/photonroot" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/photonroot"/*
    echo "[runPh5_normal] Cleaned stale build sandboxes"
  fi
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/SRPMS" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/SRPMS"/*
    echo "[runPh5_normal] Cleaned stale SRPMs"
  fi
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/LOGS" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/LOGS"/*
    echo "[runPh5_normal] Cleaned stale build logs"
  fi
  tdnf clean all 2>/dev/null
  echo "[runPh5_normal] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

  # ── Build loop ────────────────────────────────────────────────────
  for i in $(seq 1 10); do
    sudo make -j2 image IMG_NAME=iso THREADS=2;
    timeout=30
    while [ $timeout -gt 0 ]; do
      if ls stage/*.iso 1>/dev/null 2>&1; then
        break
      fi
      sleep 1
      timeout=$((timeout - 1))
    done
    if sudo mv stage/*.iso "$OUTPUT_DIR"; then
      exit 0
    fi
  done
fi
