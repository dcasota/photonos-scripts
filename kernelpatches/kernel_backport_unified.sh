#!/bin/bash

# =============================================================================
# Unified Kernel Backport Script for Photon OS
# =============================================================================
# Combines: script1.sh, script2.sh, backport_loop.sh, run_full_backport.sh
#
# Features:
#   - Clone Photon OS repository for kernel versions 5.10, 6.1, 6.12
#   - Find eligible kernel patches from upstream (fixes/CVEs)
#   - Review patches using CVE review assistance tools
#   - Auto-integrate patches into linux.spec, linux-esx.spec, linux-rt.spec
#   - Skills-based patch routing (all, base, esx, rt, none)
#   - Commit, push, and create PRs
#
# Usage:
#   ./kernel_backport_unified.sh [OPTIONS]
#
# Options:
#   --kernel VERSION     Kernel version to backport (5.10, 6.1, 6.12) - REQUIRED
#   --month YYYY-MM      Month to scan (default: 2025-07)
#   --repo-url URL       Photon repo URL (default: https://github.com/dcasota/photon.git)
#   --branch NAME        Branch to use (default: auto-detected based on kernel)
#   --skip-clone         Skip cloning if repo already exists
#   --skip-review        Skip CVE review step
#   --skip-push          Skip git push and PR creation
#   --enable-build       Enable RPM build (slow, disabled by default)
#   --limit N            Limit to first N patches (0 = no limit)
#   --dry-run            Show what would be done without making changes
#   --help               Show this help message
#
# Supported Kernels:
#   5.10 - Linux 5.10 LTS (Photon OS 4.0)
#   6.1  - Linux 6.1 LTS (Photon OS 5.0)
#   6.12 - Linux 6.12 (Photon OS development)
# =============================================================================

set -e

# -----------------------------------------------------------------------------
# Configuration Defaults
# -----------------------------------------------------------------------------
SUPPORTED_KERNELS=("5.10" "6.1" "6.12")
KERNEL_VERSION=""
SCAN_MONTH="2025-07"
REPO_URL="https://github.com/dcasota/photon.git"
BRANCH=""
REPO_DIR=""
UPSTREAM_REPO="torvalds/linux"
KEYWORDS="fix|CVE|Fixes:"
CVE_PATCH_MIN=100
CVE_PATCH_MAX=249

SKIP_CLONE=false
SKIP_REVIEW=false
SKIP_PUSH=false
ENABLE_BUILD=false
PATCH_LIMIT=0
DRY_RUN=false

# Kernel version to branch/directory mapping
get_branch_for_kernel() {
  local kver="$1"
  case "$kver" in
    5.10) echo "4.0" ;;
    6.1)  echo "5.0" ;;
    6.12) echo "common" ;;
    *)    echo "" ;;
  esac
}

get_spec_dir_for_kernel() {
  local kver="$1"
  case "$kver" in
    5.10) echo "SPECS/linux" ;;
    6.1)  echo "SPECS/linux/v6.1" ;;
    6.12) echo "SPECS/linux/v6.12" ;;
    *)    echo "" ;;
  esac
}

# Get available spec files for a kernel version
get_spec_files_for_kernel() {
  local kver="$1"
  case "$kver" in
    5.10) echo "linux.spec linux-esx.spec linux-rt.spec" ;;
    6.1)  echo "linux.spec linux-esx.spec linux-rt.spec" ;;
    6.12) echo "linux.spec linux-esx.spec" ;;
    *)    echo "" ;;
  esac
}

# Skills file for patch routing
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_FILE="${SCRIPT_DIR}/patch_routing.skills"

# Get patch routing from skills file or auto-detect
get_patch_targets() {
  local SHA=$1
  local PATCH_FILE=$2
  local SHORT_SHA="${SHA:0:12}"
  
  # Check skills file first
  if [ -f "$SKILLS_FILE" ]; then
    local ROUTING=$(grep -E "^${SHORT_SHA}" "$SKILLS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
    if [ -n "$ROUTING" ]; then
      echo "$ROUTING"
      return
    fi
  fi
  
  # Auto-detect based on patch content
  if [ -f "$PATCH_FILE" ]; then
    local HAS_GPU=$(grep -E '^\+\+\+.*drivers/gpu/' "$PATCH_FILE" 2>/dev/null)
    local HAS_KVM=$(grep -E '^\+\+\+.*arch/x86/kvm/' "$PATCH_FILE" 2>/dev/null)
    local HAS_RT=$(grep -E '^\+\+\+.*kernel/sched/.*rt' "$PATCH_FILE" 2>/dev/null)
    local HAS_VIRT=$(grep -E '^\+\+\+.*(hyperv|vmw|xen)/' "$PATCH_FILE" 2>/dev/null)
    
    # GPU patches: base only (not ESX)
    if [ -n "$HAS_GPU" ]; then
      echo "base"
      return
    fi
    
    # KVM/Virtualization patches: esx primarily
    if [ -n "$HAS_KVM" ] || [ -n "$HAS_VIRT" ]; then
      echo "base,esx"
      return
    fi
    
    # RT scheduler patches: rt only
    if [ -n "$HAS_RT" ]; then
      echo "base,rt"
      return
    fi
  fi
  
  # Default: apply to all
  echo "all"
}

# Expand target names to spec file names
expand_targets_to_specs() {
  local TARGETS=$1
  local AVAILABLE_SPECS=$2
  local RESULT=""
  
  case "$TARGETS" in
    all)
      echo "$AVAILABLE_SPECS"
      return ;;
    none)
      echo ""
      return ;;
  esac
  
  # Parse comma-separated targets
  IFS=',' read -ra TARGET_ARRAY <<< "$TARGETS"
  for target in "${TARGET_ARRAY[@]}"; do
    case "$target" in
      base)
        if echo "$AVAILABLE_SPECS" | grep -q "linux.spec"; then
          RESULT="$RESULT linux.spec"
        fi ;;
      esx)
        if echo "$AVAILABLE_SPECS" | grep -q "linux-esx.spec"; then
          RESULT="$RESULT linux-esx.spec"
        fi ;;
      rt)
        if echo "$AVAILABLE_SPECS" | grep -q "linux-rt.spec"; then
          RESULT="$RESULT linux-rt.spec"
        fi ;;
    esac
  done
  
  echo "$RESULT" | xargs
}

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case $1 in
    --kernel) KERNEL_VERSION="$2"; shift 2 ;;
    --month) SCAN_MONTH="$2"; shift 2 ;;
    --repo-url) REPO_URL="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --skip-clone) SKIP_CLONE=true; shift ;;
    --skip-review) SKIP_REVIEW=true; shift ;;
    --skip-push) SKIP_PUSH=true; shift ;;
    --enable-build) ENABLE_BUILD=true; shift ;;
    --limit) PATCH_LIMIT="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help)
      head -42 "$0" | tail -36
      exit 0
      ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

# Validate kernel version
if [ -z "$KERNEL_VERSION" ]; then
  echo "ERROR: --kernel VERSION is required"
  echo "Supported versions: ${SUPPORTED_KERNELS[*]}"
  echo "Usage: $0 --kernel <5.10|6.1|6.12> [OPTIONS]"
  exit 1
fi

VALID_KERNEL=false
for v in "${SUPPORTED_KERNELS[@]}"; do
  if [ "$v" = "$KERNEL_VERSION" ]; then
    VALID_KERNEL=true
    break
  fi
done

if [ "$VALID_KERNEL" = false ]; then
  echo "ERROR: Unsupported kernel version '$KERNEL_VERSION'"
  echo "Supported versions: ${SUPPORTED_KERNELS[*]}"
  exit 1
fi

# Set branch and repo directory based on kernel version if not specified
if [ -z "$BRANCH" ]; then
  BRANCH=$(get_branch_for_kernel "$KERNEL_VERSION")
fi
REPO_DIR="./${BRANCH}"
SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
AVAILABLE_SPECS=$(get_spec_files_for_kernel "$KERNEL_VERSION")

# Determine kernel.org base URL for upstream
KERNEL_MAJOR="${KERNEL_VERSION%%.*}"
KERNEL_ORG_URL="https://cdn.kernel.org/pub/linux/kernel/v${KERNEL_MAJOR}.x/"

# -----------------------------------------------------------------------------
# Setup
# -----------------------------------------------------------------------------
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_BASE="/tmp/backport_${TIMESTAMP}"
mkdir -p "$OUTPUT_BASE"
SKILL_LOG="$OUTPUT_BASE/execution.log"
PATCH_LIST="$OUTPUT_BASE/eligible_patches.txt"

# Network configuration
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-30}"
NETWORK_RETRIES="${NETWORK_RETRIES:-3}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$SKILL_LOG"
}

log_error() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" | tee -a "$SKILL_LOG" >&2
}

# -----------------------------------------------------------------------------
# Network Connectivity Check
# -----------------------------------------------------------------------------
check_network() {
  local hosts=("github.com" "api.github.com" "cdn.kernel.org")
  local attempt=1
  
  log "Checking network connectivity..."
  
  while [ $attempt -le $NETWORK_RETRIES ]; do
    for host in "${hosts[@]}"; do
      # Try ping first
      if timeout "$NETWORK_TIMEOUT" ping -c 1 "$host" >/dev/null 2>&1; then
        log "Network OK: $host reachable (ping)"
        return 0
      fi
      
      # Try curl as fallback (some systems block ICMP)
      if timeout "$NETWORK_TIMEOUT" curl -s --head --max-time "$NETWORK_TIMEOUT" "https://$host" >/dev/null 2>&1; then
        log "Network OK: $host reachable (curl)"
        return 0
      fi
    done
    
    log "Network check attempt $attempt/$NETWORK_RETRIES failed"
    attempt=$((attempt + 1))
    [ $attempt -le $NETWORK_RETRIES ] && sleep 5
  done
  
  log_error "Network is not available after $NETWORK_RETRIES attempts"
  return 1
}

log "=== Unified Kernel Backport Script ==="
log "Kernel version: $KERNEL_VERSION"
log "Output directory: $OUTPUT_BASE"
log "Scan month: $SCAN_MONTH"
log "Target branch: $BRANCH"
log "Spec directory: $SPEC_SUBDIR"
log "Available specs: $AVAILABLE_SPECS"
log "Skills file: $SKILLS_FILE"
log "Kernel.org URL: $KERNEL_ORG_URL"
log "Dry run: $DRY_RUN"

# -----------------------------------------------------------------------------
# Step 1: Clone Photon Repository
# -----------------------------------------------------------------------------
clone_repo() {
  log ""
  log "=== Step 1: Clone Photon Repository ==="
  
  if [ "$SKIP_CLONE" = true ] && [ -d "$REPO_DIR" ]; then
    log "Skipping clone (--skip-clone), using existing $REPO_DIR"
    return 0
  fi
  
  if [ -d "$REPO_DIR" ]; then
    log "Removing existing $REPO_DIR"
    [ "$DRY_RUN" = false ] && rm -rf "$REPO_DIR"
  fi
  
  log "Cloning $REPO_URL branch $BRANCH..."
  if [ "$DRY_RUN" = false ]; then
    git clone "$REPO_URL" "$REPO_DIR" --branch "$BRANCH"
    if [ $? -ne 0 ]; then
      log "ERROR: Failed to clone repository"
      exit 1
    fi
  fi
  log "Clone complete: $REPO_DIR"
}

# -----------------------------------------------------------------------------
# Step 2: Find Eligible Patches (formerly script1.sh)
# -----------------------------------------------------------------------------
find_eligible_patches() {
  log ""
  log "=== Step 2: Find Eligible Patches ==="
  log "Scanning upstream $UPSTREAM_REPO for month $SCAN_MONTH"
  log "Keywords: $KEYWORDS"
  
  # Extract year and month
  YEAR=$(echo "$SCAN_MONTH" | cut -d'-' -f1)
  MONTH=$(echo "$SCAN_MONTH" | cut -d'-' -f2)
  
  # Determine days in month
  case $MONTH in
    01|03|05|07|08|10|12) DAYS=31 ;;
    04|06|09|11) DAYS=30 ;;
    02) 
      if [ $((YEAR % 4)) -eq 0 ] && { [ $((YEAR % 100)) -ne 0 ] || [ $((YEAR % 400)) -eq 0 ]; }; then
        DAYS=29
      else
        DAYS=28
      fi
      ;;
  esac
  
  > "$PATCH_LIST"
  
  for day in $(seq 1 $DAYS); do
    padded_day=$(printf "%02d" $day)
    since="${SCAN_MONTH}-${padded_day}T00:00:00Z"
    until="${SCAN_MONTH}-${padded_day}T23:59:59Z"
    
    log "  Scanning day: ${SCAN_MONTH}-${padded_day}"
    
    if [ "$DRY_RUN" = false ]; then
      api_url="https://api.github.com/repos/${UPSTREAM_REPO}/commits?since=${since}&until=${until}&per_page=100"
      response=$(curl -s -H "Accept: application/vnd.github+json" "$api_url")
      
      # Extract eligible commits
      eligible=$(echo "$response" | jq -r --arg keywords "$KEYWORDS" \
        '.[] | select(.commit.message | test($keywords; "i")) | .sha' 2>/dev/null)
      
      if [ -n "$eligible" ]; then
        echo "$eligible" >> "$PATCH_LIST"
      fi
    fi
  done
  
  if [ "$DRY_RUN" = false ]; then
    TOTAL_PATCHES=$(wc -l < "$PATCH_LIST" | tr -d ' ')
    log "Found $TOTAL_PATCHES eligible patches"
  else
    log "Dry run - skipping actual API calls"
    TOTAL_PATCHES=0
  fi
}

# -----------------------------------------------------------------------------
# Step 3: Review Patches (formerly script2.sh)
# -----------------------------------------------------------------------------
review_patch() {
  local SHA=$1
  local REVIEW_DIR="$OUTPUT_BASE/reviews"
  mkdir -p "$REVIEW_DIR"
  
  log "  Reviewing patch $SHA..."
  
  # Setup review tools
  TOOL_DIR="$REPO_DIR/tools/scripts/photon-cve-review-assistance"
  if [ ! -f "photon_cve_review.py" ] && [ -d "$TOOL_DIR" ]; then
    cp "$TOOL_DIR/photon-cve-review.py" . 2>/dev/null || true
    cp "$TOOL_DIR/patch_comparison.py" . 2>/dev/null || true
  fi
  
  # Download upstream patch
  PATCH_URL="https://github.com/torvalds/linux/commit/${SHA}.patch"
  curl -s -o "$OUTPUT_BASE/upstream_${SHA:0:12}.patch" "$PATCH_URL"
  
  if [ ! -s "$OUTPUT_BASE/upstream_${SHA:0:12}.patch" ]; then
    log "    WARN: Could not download patch for review"
    return 1
  fi
  
  # Create simulated backport with upstream marker
  sed '/^Subject:/a [ Upstream commit '"$SHA"' ]' \
    "$OUTPUT_BASE/upstream_${SHA:0:12}.patch" > "$OUTPUT_BASE/backport_${SHA:0:12}.patch"
  
  # Create temp repo for review
  TEMP_REPO="$OUTPUT_BASE/temp_repo_$$"
  mkdir -p "$TEMP_REPO"
  (
    cd "$TEMP_REPO"
    git init -q
    touch dummy_file
    git add dummy_file
    git commit -q -m "Initial commit"
    cp "$OUTPUT_BASE/backport_${SHA:0:12}.patch" cve_backport.patch
    git add cve_backport.patch
    git commit -q -m "Add backport patch for commit $SHA"
  )
  
  # Run review tool if available
  if [ -f "photon_cve_review.py" ]; then
    python3 photon_cve_review.py "$TEMP_REPO" HEAD \
      --output-dir "$REVIEW_DIR/${SHA:0:12}" --cleanup 2>/dev/null || true
  fi
  
  # Cleanup
  rm -rf "$TEMP_REPO"
  rm -f "$OUTPUT_BASE/upstream_${SHA:0:12}.patch"
  
  return 0
}

# -----------------------------------------------------------------------------
# Step 4: Integrate Patches into Spec Files
# -----------------------------------------------------------------------------
# Helper: Add patch entry to a single spec file
add_patch_to_spec() {
  local SPEC_FILE=$1
  local PATCH_NAME=$2
  local PATCH_NUM=$3
  
  # Find last CVE patch in this spec
  local LAST_CVE=$(grep -oP 'Patch\K(1[0-9]{2}|2[0-4][0-9])(?=:)' "$SPEC_FILE" 2>/dev/null | sort -n | tail -1)
  
  if [ -n "$LAST_CVE" ]; then
    sed -i "/^Patch${LAST_CVE}:/a Patch${PATCH_NUM}: ${PATCH_NAME}" "$SPEC_FILE"
  else
    local LAST_PRE=$(grep -oP 'Patch\K[0-9]+(?=:)' "$SPEC_FILE" 2>/dev/null | \
      awk -v min=$CVE_PATCH_MIN '$1 < min' | sort -n | tail -1)
    if [ -n "$LAST_PRE" ]; then
      sed -i "/^Patch${LAST_PRE}:/a Patch${PATCH_NUM}: ${PATCH_NAME}" "$SPEC_FILE"
    else
      sed -i "/^Source0:/a Patch${PATCH_NUM}: ${PATCH_NAME}" "$SPEC_FILE"
    fi
  fi
}

integrate_patch() {
  local SHA=$1
  local PATCH_NAME="${SHA:0:12}-backport.patch"
  local PATCH_FILE="$REPO_DIR/$SPEC_SUBDIR/$PATCH_NAME"
  
  # Download patch from upstream first (needed for routing detection)
  curl -s -o "$PATCH_FILE" "https://github.com/torvalds/linux/commit/${SHA}.patch"
  
  if [ ! -s "$PATCH_FILE" ]; then
    log "  FAIL: Could not download patch"
    return 3
  fi
  
  # Determine which spec files should receive this patch
  local TARGETS=$(get_patch_targets "$SHA" "$PATCH_FILE")
  local TARGET_SPECS=$(expand_targets_to_specs "$TARGETS" "$AVAILABLE_SPECS")
  
  if [ -z "$TARGET_SPECS" ]; then
    log "  SKIP: Patch routing is 'none' - not applicable"
    rm -f "$PATCH_FILE"
    return 4
  fi
  
  log "  Routing: $TARGETS -> $TARGET_SPECS"
  
  # Check if already integrated in any target spec
  local ALREADY_INTEGRATED=""
  for spec in $TARGET_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    if [ -f "$SPEC_PATH" ] && grep -q "${SHA:0:12}" "$SPEC_PATH" 2>/dev/null; then
      ALREADY_INTEGRATED="$ALREADY_INTEGRATED $spec"
    fi
  done
  
  if [ -n "$ALREADY_INTEGRATED" ]; then
    log "  SKIP: Already integrated in:$ALREADY_INTEGRATED"
    rm -f "$PATCH_FILE"
    return 1
  fi
  
  # Find next available Patch number across all target specs
  local MAX_PATCH=$CVE_PATCH_MIN
  for spec in $TARGET_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    if [ -f "$SPEC_PATH" ]; then
      local LAST=$(grep -oP 'Patch\K(1[0-9]{2}|2[0-4][0-9])(?=:)' "$SPEC_PATH" 2>/dev/null | sort -n | tail -1)
      if [ -n "$LAST" ] && [ "$LAST" -ge "$MAX_PATCH" ]; then
        MAX_PATCH=$((LAST + 1))
      fi
    fi
  done
  NEXT_PATCH=$MAX_PATCH
  
  if [ "$NEXT_PATCH" -gt "$CVE_PATCH_MAX" ]; then
    log "  ERROR: CVE patch range ($CVE_PATCH_MIN-$CVE_PATCH_MAX) is full"
    rm -f "$PATCH_FILE"
    return 2
  fi
  
  # Add patch entry to each target spec file
  local MODIFIED_SPECS=""
  for spec in $TARGET_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    if [ -f "$SPEC_PATH" ]; then
      add_patch_to_spec "$SPEC_PATH" "$PATCH_NAME" "$NEXT_PATCH"
      MODIFIED_SPECS="$MODIFIED_SPECS $spec"
      log "    Added Patch${NEXT_PATCH} to $spec"
    else
      log "    WARN: $spec not found, skipping"
    fi
  done
  
  # Store modified specs list for commit
  LAST_MODIFIED_SPECS="$MODIFIED_SPECS"
  
  log "  Added Patch${NEXT_PATCH}: ${PATCH_NAME} to${MODIFIED_SPECS}"
  echo "$NEXT_PATCH"
  return 0
}

# Global to track modified specs for commit
LAST_MODIFIED_SPECS=""

# -----------------------------------------------------------------------------
# Step 5: Commit Changes
# -----------------------------------------------------------------------------
commit_changes() {
  local SHA=$1
  local PATCH_NUM=$2
  local PATCH_NAME="${SHA:0:12}-backport.patch"
  local BRANCH_NAME="backport/${SHA:0:12}"
  
  git -C "$REPO_DIR" checkout -b "$BRANCH_NAME" 2>/dev/null || \
    git -C "$REPO_DIR" checkout "$BRANCH_NAME" 2>/dev/null || true
  
  # Add patch file
  git -C "$REPO_DIR" add "$SPEC_SUBDIR/$PATCH_NAME" 2>/dev/null
  
  # Add all modified spec files
  for spec in $LAST_MODIFIED_SPECS; do
    git -C "$REPO_DIR" add "$SPEC_SUBDIR/$spec" 2>/dev/null
  done
  
  # Build commit message with list of modified specs
  local SPECS_LIST=$(echo "$LAST_MODIFIED_SPECS" | xargs | tr ' ' ', ')
  
  git -C "$REPO_DIR" commit -m "Backport kernel patch ${SHA:0:12}

Backported from upstream commit: $SHA
Patch number: Patch${PATCH_NUM}
Modified specs: ${SPECS_LIST}
Kernel version: ${KERNEL_VERSION}
Auto-generated by kernel-backport-processor skill" 2>/dev/null
  
  if [ $? -eq 0 ]; then
    log "  Committed to branch: $BRANCH_NAME"
    return 0
  else
    log "  WARN: Commit may have failed"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Step 6: Build RPM (Optional)
# -----------------------------------------------------------------------------
build_rpm() {
  local SHA=$1
  local BUILD_LOG="$OUTPUT_BASE/build_${SHA:0:12}.log"
  
  log "  Building kernel RPM..."
  (cd "$REPO_DIR" && rpmbuild -bb SPECS/linux/linux.spec) > "$BUILD_LOG" 2>&1
  
  if [ $? -ne 0 ]; then
    log "  FAIL: Build failed, see $BUILD_LOG"
    return 1
  fi
  
  # Verify RPM created
  RPM_FILE=$(find ~/rpmbuild/RPMS -name "linux-*.rpm" -mmin -5 2>/dev/null | head -1)
  if [ -z "$RPM_FILE" ]; then
    log "  FAIL: No RPM generated"
    return 1
  fi
  
  # Basic integrity check
  rpm -qp --requires "$RPM_FILE" > /dev/null 2>&1
  if [ $? -ne 0 ]; then
    log "  FAIL: RPM integrity check failed"
    return 1
  fi
  
  log "  Build successful: $RPM_FILE"
  return 0
}

# -----------------------------------------------------------------------------
# Step 7: Push and Create PR
# -----------------------------------------------------------------------------
push_and_pr() {
  local SHA=$1
  local PATCH_NUM=$2
  local PATCH_NAME="${SHA:0:12}-backport.patch"
  local BRANCH_NAME="backport/${SHA:0:12}"
  
  log "  Pushing branch $BRANCH_NAME..."
  git -C "$REPO_DIR" push -u origin "$BRANCH_NAME" 2>&1 | tee -a "$SKILL_LOG"
  
  if [ $? -ne 0 ]; then
    log "  WARN: Push failed"
    return 1
  fi
  
  # Create PR
  PR_URL=$(cd "$REPO_DIR" && gh pr create \
    --title "Backport: ${SHA:0:12} kernel patch" \
    --body "## Backport Summary

**Upstream Commit**: https://github.com/torvalds/linux/commit/$SHA
**Target Branch**: $BRANCH

### Changes
- Added patch file: \`$PATCH_NAME\`
- Updated linux.spec with \`Patch${PATCH_NUM}\`

### Notes
- Patch applies to CVE range ($CVE_PATCH_MIN-$CVE_PATCH_MAX) via \`%autopatch\`
- Build and test before merging

---
*Auto-generated by kernel-backport-processor skill*" \
    --base "$BRANCH" \
    --head "$BRANCH_NAME" 2>&1)
  
  if echo "$PR_URL" | grep -q "http"; then
    log "  SUCCESS: PR created at $PR_URL"
    return 0
  else
    log "  WARN: PR creation output: $PR_URL"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main Processing Loop
# -----------------------------------------------------------------------------
process_patches() {
  log ""
  log "=== Step 4-7: Process Patches ==="
  
  local SPEC_FILE="$REPO_DIR/$SPEC_SUBDIR/linux.spec"
  
  # Backup spec
  cp "$SPEC_FILE" "$OUTPUT_BASE/linux.spec.backup"
  log "Backed up spec to $OUTPUT_BASE/linux.spec.backup"
  
  # Get SHAs
  if [ -f "$PATCH_LIST" ] && [ -s "$PATCH_LIST" ]; then
    SHAS=$(cat "$PATCH_LIST")
  elif [ -f "/root/july_patches.txt" ]; then
    log "Using existing /root/july_patches.txt"
    SHAS=$(grep -oE '[0-9a-f]{40}' /root/july_patches.txt)
  else
    log "ERROR: No patch list available"
    exit 1
  fi
  
  TOTAL=$(echo "$SHAS" | wc -l | tr -d ' ')
  
  # Apply limit if set
  if [ "$PATCH_LIMIT" -gt 0 ] && [ "$PATCH_LIMIT" -lt "$TOTAL" ]; then
    SHAS=$(echo "$SHAS" | head -n "$PATCH_LIMIT")
    TOTAL=$PATCH_LIMIT
    log "Limited to first $PATCH_LIMIT patches"
  fi
  
  log "Processing $TOTAL patches..."
  
  local PROCESSED=0 SKIPPED=0 FAILED=0 SUCCESS=0 RANGE_FULL=false
  
  for SHA in $SHAS; do
    PROCESSED=$((PROCESSED + 1))
    log ""
    log "[$PROCESSED/$TOTAL] SHA: ${SHA:0:12}"
    
    if [ "$DRY_RUN" = true ]; then
      log "  DRY RUN: Would process this patch"
      continue
    fi
    
    # Review (optional)
    if [ "$SKIP_REVIEW" = false ]; then
      review_patch "$SHA" || true
    fi
    
    # Integrate
    PATCH_NUM=$(integrate_patch "$SHA")
    RESULT=$?
    
    case $RESULT in
      0) ;;  # Success, continue
      1) SKIPPED=$((SKIPPED + 1)); continue ;;  # Already integrated
      2) RANGE_FULL=true; break ;;  # Range full
      *) FAILED=$((FAILED + 1)); continue ;;  # Other error
    esac
    
    # Commit
    commit_changes "$SHA" "$PATCH_NUM" || true
    
    # Build (optional)
    if [ "$ENABLE_BUILD" = true ]; then
      if ! build_rpm "$SHA"; then
        git -C "$REPO_DIR" checkout "$BRANCH" 2>/dev/null
        FAILED=$((FAILED + 1))
        continue
      fi
    fi
    
    # Push and PR (optional)
    if [ "$SKIP_PUSH" = false ]; then
      push_and_pr "$SHA" "$PATCH_NUM" || true
    fi
    
    # Return to base branch
    git -C "$REPO_DIR" checkout "$BRANCH" 2>/dev/null || true
    
    SUCCESS=$((SUCCESS + 1))
  done
  
  log ""
  log "=== PROCESSING COMPLETE ==="
  log "Total: $TOTAL"
  log "Processed: $PROCESSED"
  log "Success: $SUCCESS"
  log "Skipped: $SKIPPED"
  log "Failed: $FAILED"
  
  if [ "$RANGE_FULL" = true ]; then
    log "NOTE: CVE patch range ($CVE_PATCH_MIN-$CVE_PATCH_MAX) is full"
  fi
  
  # Final stats
  log ""
  log "CVE patches in spec:"
  grep -cE '^Patch(1[0-9]{2}|2[0-4][0-9]):' "$SPEC_FILE" 2>/dev/null || echo "0"
}

# -----------------------------------------------------------------------------
# Main Execution
# -----------------------------------------------------------------------------
main() {
  local EXIT_CODE=0
  
  # Check network connectivity first
  if ! check_network; then
    log_error "Aborting due to network unavailability"
    log "To retry, ensure network connectivity and run again"
    exit 0  # Exit cleanly (not error) so cron doesn't send error emails
  fi
  
  # Run the workflow with error handling
  if ! clone_repo; then
    log_error "Failed to clone repository"
    EXIT_CODE=1
  elif ! find_eligible_patches; then
    log_error "Failed to find eligible patches"
    EXIT_CODE=1
  else
    process_patches || EXIT_CODE=$?
  fi
  
  log ""
  log "=== ALL DONE ==="
  log "Exit code: $EXIT_CODE"
  log "Output directory: $OUTPUT_BASE"
  log "Execution log: $SKILL_LOG"
  [ -f "$OUTPUT_BASE/linux.spec.backup" ] && log "Spec backup: $OUTPUT_BASE/linux.spec.backup"
  
  return $EXIT_CODE
}

# Trap to log unexpected exits
trap 'log_error "Script terminated unexpectedly"; exit 1' ERR

main "$@"
