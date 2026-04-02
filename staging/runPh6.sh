#!/bin/sh

# Photon OS 6.0 build script with FIPS enabled
#
# FIPS support in Photon 6.0:
#   - Kernel: CONFIG_CRYPTO_FIPS=y in all kernel configs (x86_64, esx, rt)
#   - Userspace: openssl-fips-provider builds fips.so from SPECS/openssl/
#   - Build: ossl-fips-in-make-check enables FIPS validation in make checks
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

  # ── Use upstream subrelease ───────────────────────────────────────
  # Restore upstream build-config.json first, then apply FIPS settings.
  git checkout -- build-config.json 2>/dev/null

  UPSTREAM_SUB=$(python3 -c "
import json
cfg = json.load(open('build-config.json'))
print(cfg['photon-build-param']['photon-subrelease'])
" 2>/dev/null)
  echo "[runPh6] Using upstream photon-subrelease: ${UPSTREAM_SUB}"

  # Ensure photon-mainline matches subrelease to skip snapshot
  if grep -q '"photon-mainline"' build-config.json; then
    sed -i "s/\"photon-mainline\":.*/\"photon-mainline\": \"${UPSTREAM_SUB}\",/" build-config.json
  else
    sed -i "/\"photon-subrelease\"/a\\    \"photon-mainline\": \"${UPSTREAM_SUB}\"," build-config.json
  fi

  # ── Enable FIPS in build ──────────────────────────────────────────
  # Add ossl-fips-in-make-check to trigger FIPS validation during
  # make check phases (openssl, kernel crypto self-tests).
  if ! grep -q '"ossl-fips-in-make-check"' build-config.json; then
    sed -i '/"photon-mainline"/a\    "ossl-fips-in-make-check": true,' build-config.json
  fi

  echo "[runPh6] FIPS enabled: ossl-fips-in-make-check=true"
  echo "[runPh6] FIPS kernel: CONFIG_CRYPTO_FIPS=y (built-in)"
  echo "[runPh6] FIPS userspace: openssl-fips-provider (fips.so)"

  # ── Fix OpenJDK WSL2 detection in chroot ───────────────────────────
  if grep -qi 'microsoft\|wsl' /proc/version 2>/dev/null; then
    for jdk_spec in SPECS/openjdk/openjdk*.spec; do
      [ -f "$jdk_spec" ] || continue
      if grep -q 'sh ./configure' "$jdk_spec" && ! grep -q 'build=x86_64-unknown-linux-gnu' "$jdk_spec"; then
        sed -i 's|--disable-warnings-as-errors$|--disable-warnings-as-errors \\\n    --build=x86_64-unknown-linux-gnu|' "$jdk_spec"
        echo "[runPh6] Fixed $(basename "$jdk_spec"): added --build for WSL2"
      fi
    done
  fi

  # ── Pre-fetch sources missing from Broadcom mirror ─────────────
  fetch_missing_source() {
    archive="$1"; url="$2"; destdir="$BASE_DIR/$RELEASE_BRANCH/stage/SOURCES"
    [ -f "$destdir/$archive" ] && return 0
    echo "[runPh6] Fetching missing source: $archive"
    mkdir -p "$destdir"
    wget -q "$url" -O "$destdir/$archive" 2>/dev/null && return 0
    echo "[runPh6] WARNING: Failed to fetch $archive from $url"
    return 1
  }

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

  # ── Free disk space and clean stale build artifacts ─────────────
  for mp in $(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r); do
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
  done
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/photonroot" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/photonroot"/*
    echo "[runPh6] Cleaned stale build sandboxes"
  fi
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/SRPMS" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/SRPMS"/*
    echo "[runPh6] Cleaned stale SRPMs"
  fi
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/LOGS" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/LOGS"/*
    echo "[runPh6] Cleaned stale build logs"
  fi
  tdnf clean all 2>/dev/null
  echo "[runPh6] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

  # ── Build loop ────────────────────────────────────────────────────
  for i in $(seq 1 10); do
    sudo make -j$(( $(nproc) - 1 )) image IMG_NAME=iso THREADS=$(( $(nproc) - 1 ));
    # 6.0 uses docker-based ISO assembly; output lands in stage/iso/ not stage/
    timeout=30
    while [ $timeout -gt 0 ]; do
      if ls stage/*.iso stage/iso/*.iso 1>/dev/null 2>&1; then
        break
      fi
      sleep 1
      timeout=$((timeout - 1))
    done
    if sudo mv stage/*.iso "$OUTPUT_DIR" 2>/dev/null || sudo mv stage/iso/*.iso "$OUTPUT_DIR" 2>/dev/null; then
      exit 0
    fi
  done
fi
