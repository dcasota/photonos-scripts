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
