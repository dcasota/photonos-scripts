#! /bin/sh

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
  for i in {1..10}; do
    sudo make -j$(( $(nproc) - 1 )) image IMG_NAME=iso THREADS=$(( $(nproc) - 1 ));
    # Wait up to 30 seconds for ISO to appear
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
