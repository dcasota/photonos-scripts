#!/bin/sh

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

  # ── Pin subrelease ────────────────────────────────────────────────
  # Ensure photon-subrelease is 91 so the 6.1.x kernel specs are active.
  sed -i 's/"photon-subrelease":.*/"photon-subrelease": "91",/' build-config.json
  # Set photon-mainline=91 to skip snapshot (avoids stale snapshot conflicts).
  if grep -q '"photon-mainline"' build-config.json; then
    sed -i 's/"photon-mainline":.*/"photon-mainline": "91",/' build-config.json
  else
    sed -i '/"photon-subrelease":.*/a\    "photon-mainline": "91",' build-config.json
  fi

  # ── Read effective subrelease and upstream mainline ────────────────
  PINNED_SUB=$(python3 -c "
import json
cfg = json.load(open('build-config.json'))
print(cfg['photon-build-param']['photon-subrelease'])
" 2>/dev/null)
  UPSTREAM_MAIN=$(cd "$BASE_DIR/$RELEASE_BRANCH" && git show HEAD:build-config.json 2>/dev/null | python3 -c "
import json, sys
cfg = json.load(sys.stdin)
print(cfg['photon-build-param'].get('photon-mainline', cfg['photon-build-param']['photon-subrelease']))
" 2>/dev/null || echo "$PINNED_SUB")
  echo "[runPh5] Effective photon-subrelease: ${PINNED_SUB} (upstream mainline: ${UPSTREAM_MAIN})"

  # ── Fix libcap gating conflict (package split) ────────────────────
  # The libcap 2.77 spec splits the package into subpackages
  # (libcap-libs, libcap-minimal, etc.). The remote packages repo ships
  # v2.77 with "Conflicts: libcap < 2.77-1", which makes it impossible
  # for the build sandbox to install the old monolithic v2.66 alongside
  # any dependency that transitively pulls libcap-libs from the remote
  # repo. This ONLY needs fixing when pinned below the upstream mainline.
  #
  # We selectively flip the libcap build_if guards so v2.77 (split)
  # is active at the pinned subrelease. This is safe because libcap
  # v2.77 has no dependency on the python3.14/subrelease-92 ecosystem.
  fix_libcap_gating() {
    pin="$1"
    threshold=$((pin - 1))
    specroot="$BASE_DIR/$RELEASE_BRANCH/SPECS"

    for pkg in libcap; do
      old_spec="${specroot}/91/${pkg}/${pkg}.spec"
      new_spec="${specroot}/${pkg}/${pkg}.spec"
      [ -f "$old_spec" ] && [ -f "$new_spec" ] || continue

      old_val=$(head -5 "$old_spec" | sed -n 's/^%[gd].*build_if[[:space:]]\+\(.*\)/\1/p' | grep -oP '<=\s*\K[0-9]+')
      new_val=$(head -5 "$new_spec" | sed -n 's/^%[gd].*build_if[[:space:]]\+\(.*\)/\1/p' | grep -oP '>=\s*\K[0-9]+')
      [ -n "$old_val" ] && [ -n "$new_val" ] || continue

      need_fix=false
      [ "$old_val" -ge "$pin" ] 2>/dev/null && need_fix=true
      [ "$new_val" -gt "$pin" ] 2>/dev/null && need_fix=true

      if [ "$need_fix" = "true" ]; then
        echo "[runPh5] Fixing libcap gating: old <= $old_val -> <= $threshold, new >= $new_val -> >= $pin"
        sed -i "1,5 s|%{photon_subrelease}[[:space:]]*<=[[:space:]]*${old_val}|%{photon_subrelease} <= ${threshold}|" "$old_spec"
        sed -i "1,5 s|%{photon_subrelease}[[:space:]]*>=[[:space:]]*${new_val}|%{photon_subrelease} >= ${pin}|" "$new_spec"
      fi
    done
  }

  if [ "$PINNED_SUB" != "$UPSTREAM_MAIN" ]; then
    fix_libcap_gating "$PINNED_SUB"
  fi

  # ── Ensure builder-pkg-preq.json has libcap-libs ──────────────────
  # The libcap 2.77 split produces libcap-libs as a separate subpackage
  # needed by the toolchain. Add it if not already present.
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
print('[runPh5] Added libcap-libs to builder-pkg-preq.json')
" 2>/dev/null
  fi

  # ── Fix python3-setuptools circular wheel dependency ──────────────
  # Upstream commit a3ced8c introduced a bdist_wheel build in the
  # SPECS/91/ setuptools spec, creating a circular dependency
  # (setuptools <-> wheel). If the fix (commit 9457922a2) has not yet
  # been merged, apply it here. Only touch SPECS/91/ (the pinned spec);
  # the SPECS/ main spec (v80.9.0) is for the >= 92 ecosystem.
  SETUPTOOLS_SPEC="SPECS/91/python3-setuptools/python3-setuptools.spec"
  if [ -f "$SETUPTOOLS_SPEC" ] && grep -q "bdist_wheel" "$SETUPTOOLS_SPEC"; then
    echo "[runPh5] Fixing python3-setuptools: removing bdist_wheel circular dependency"
    sed -i 's|%{python3} setup.py bdist_wheel|%py3_build|' "$SETUPTOOLS_SPEC"
    sed -i '/^%define ExtraBuildRequires.*python3-wheel/d' "$SETUPTOOLS_SPEC"
    sed -i '/^%define python_wheel_dir/d' "$SETUPTOOLS_SPEC"
    sed -i '/^%define python_wheel_name/d' "$SETUPTOOLS_SPEC"
    sed -i '/^%package wheel/,/^%description wheel/{/^%description wheel/!d}' "$SETUPTOOLS_SPEC"
    sed -i '/^%description wheel/,/^$/d' "$SETUPTOOLS_SPEC"
    sed -i '/^%files wheel/,/^$/d' "$SETUPTOOLS_SPEC"
    sed -i '/install.*python_wheel_dir/d' "$SETUPTOOLS_SPEC"
    sed -i '/install.*python_wheel_name/d' "$SETUPTOOLS_SPEC"
    sed -i '/mkdir.*python_wheel_dir/d' "$SETUPTOOLS_SPEC"
  fi

  # ── Free disk space and clean stale build artifacts ─────────────
  # Unmount stale build sandbox overlays from previous failed runs
  for mp in $(mount 2>/dev/null | grep "stage/photonroot" | awk '{print $3}' | sort -r); do
    umount "$mp" 2>/dev/null || umount -l "$mp" 2>/dev/null
  done
  # Remove leftover sandbox directories after unmounting
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/photonroot" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/photonroot"/*
    echo "[runPh5] Cleaned stale build sandboxes"
  fi
  # Remove SRPMs from previous builds (rebuilt each run, ~7-8 GB)
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/SRPMS" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/SRPMS"/*
    echo "[runPh5] Cleaned stale SRPMs"
  fi
  # Clean build logs from previous runs
  if [ -d "$BASE_DIR/$RELEASE_BRANCH/stage/LOGS" ]; then
    rm -rf "$BASE_DIR/$RELEASE_BRANCH/stage/LOGS"/*
    echo "[runPh5] Cleaned stale build logs"
  fi
  # Clean host tdnf cache
  tdnf clean all 2>/dev/null
  echo "[runPh5] Disk space available: $(df -h / | awk 'NR==2{print $4}')"

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
