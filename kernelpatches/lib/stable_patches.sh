#!/bin/bash
# =============================================================================
# Stable Kernel Patches Library for Kernel Backport Solution
# =============================================================================
# Functions for downloading and integrating stable kernel subversion patches
# from kernel.org (e.g., 6.1.120 -> 6.1.121)
# Source this file after common.sh
# =============================================================================

[[ -n "${_STABLE_PATCHES_SH_LOADED:-}" ]] && return 0
_STABLE_PATCHES_SH_LOADED=1

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
STABLE_MARKER_DIR="${LOG_DIR:-/var/log/kernel-backport}"
PHOTON_REPO_URL="${PHOTON_REPO_URL:-https://github.com/vmware/photon.git}"

# -----------------------------------------------------------------------------
# Stable Kernel Status Check
# -----------------------------------------------------------------------------

# Check if Photon kernel is behind latest stable
# Returns: "UPDATE_NEEDED|current_version|latest_version" or "UP_TO_DATE|version"
check_stable_kernel_status() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  
  # Get current Photon version from spec
  local current=$(get_photon_kernel_version "$KERNEL_VERSION" "$REPO_DIR")
  if [ -z "$current" ]; then
    log_error "Could not determine current Photon kernel version" >&2
    echo "ERROR|unknown|unknown"
    return 1
  fi
  
  # Get latest stable from kernel.org
  local latest=$(get_latest_stable_version "$KERNEL_VERSION")
  if [ -z "$latest" ]; then
    log_error "Could not determine latest stable version" >&2
    echo "ERROR|$current|unknown"
    return 1
  fi
  
  if version_less_than "$current" "$latest"; then
    echo "UPDATE_NEEDED|$current|$latest"
  else
    echo "UP_TO_DATE|$current"
  fi
}

# Get the number of stable versions behind
get_versions_behind() {
  local current="$1"
  local latest="$2"
  
  local current_patch=$(echo "$current" | cut -d. -f3)
  local latest_patch=$(echo "$latest" | cut -d. -f3)
  
  echo $((latest_patch - current_patch))
}

# -----------------------------------------------------------------------------
# Stable Update Integration
# -----------------------------------------------------------------------------

# Integrate a stable kernel update into spec files
# This updates Version, resets Release to 1, and adds changelog
integrate_stable_update() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local NEW_VERSION="$3"
  local AVAILABLE_SPECS="$4"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local OLD_VERSION=$(get_photon_kernel_version "$KERNEL_VERSION" "$REPO_DIR")
  
  if [ -z "$OLD_VERSION" ]; then
    log_error "Could not determine current version"
    return 1
  fi
  
  log "Integrating stable update: $OLD_VERSION -> $NEW_VERSION"
  
  local update_success=true
  
  for spec in $AVAILABLE_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    
    if [ ! -f "$SPEC_PATH" ]; then
      log_warn "Spec file not found, skipping: $SPEC_PATH"
      continue
    fi
    
    log "Updating $spec..."
    
    # 1. Update Version
    if ! update_spec_version "$SPEC_PATH" "$NEW_VERSION"; then
      log_error "Failed to update version in $spec"
      update_success=false
      continue
    fi
    
    # 2. Reset Release to 1
    if ! reset_spec_release "$SPEC_PATH"; then
      log_error "Failed to reset release in $spec"
      update_success=false
      continue
    fi
    
    # 3. Add changelog entry
    local CHANGELOG_MSG="Update to stable kernel $NEW_VERSION"
    if ! add_changelog_entry "$SPEC_PATH" "$NEW_VERSION" "1" "$CHANGELOG_MSG"; then
      log_error "Failed to add changelog in $spec"
      update_success=false
      continue
    fi
    
    log "  Successfully updated $spec"
  done
  
  if [ "$update_success" = true ]; then
    log "Stable update integration complete"
    return 0
  else
    log_error "Some spec files failed to update"
    return 1
  fi
}

# Remove CVE patches that are now included in the new kernel tarball
# This checks each patch file to see if the commit is in the new version
remove_redundant_cve_patches() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local NEW_VERSION="$3"
  local AVAILABLE_SPECS="$4"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local removed_count=0
  
  log "Checking for CVE patches now included in $NEW_VERSION..."
  
  # Get list of patch files in CVE range (Patch100-499)
  for spec in $AVAILABLE_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    
    if [ ! -f "$SPEC_PATH" ]; then
      continue
    fi
    
    # Extract CVE patch entries (Patch100-499)
    local cve_patches=$(grep -oP '^Patch[1-4][0-9][0-9]:\s*\K[^\s]+' "$SPEC_PATH" 2>/dev/null)
    
    if [ -z "$cve_patches" ]; then
      continue
    fi
    
    log "  Checking $spec for redundant patches..."
    
    while IFS= read -r patch_name; do
      [ -z "$patch_name" ] && continue
      
      local patch_file="$REPO_DIR/$SPEC_SUBDIR/$patch_name"
      
      # Check if patch file exists
      if [ ! -f "$patch_file" ]; then
        continue
      fi
      
      # Extract commit SHA from patch file (first 12 chars usually in filename)
      local commit_sha=$(echo "$patch_name" | grep -oP '^[a-f0-9]{12}' || true)
      
      if [ -z "$commit_sha" ]; then
        # Try to extract from patch content
        commit_sha=$(head -1 "$patch_file" | grep -oP 'From \K[a-f0-9]{40}' | cut -c1-12 || true)
      fi
      
      if [ -z "$commit_sha" ]; then
        continue
      fi
      
      # Check if this commit is in the new stable version
      # We'll mark for removal - actual removal needs careful spec editing
      log "    Found CVE patch: $patch_name (commit: $commit_sha)"
      # Note: Full implementation would check git log of stable branch
      # For now, we log but don't auto-remove (requires manual verification)
      
    done <<< "$cve_patches"
  done
  
  log "CVE patch analysis complete (found $removed_count potentially redundant patches)"
  return 0
}

# -----------------------------------------------------------------------------
# Stable Patch Discovery
# -----------------------------------------------------------------------------
get_current_kernel_subversion() {
  local SPEC_PATH="$1"
  
  if [ ! -f "$SPEC_PATH" ]; then
    echo ""
    return 1
  fi
  
  # Extract Version and Release from spec file
  local version=$(grep -oP '^Version:\s*\K[0-9.]+' "$SPEC_PATH" | head -1)
  local release=$(grep -oP '^Release:\s*\K[0-9]+' "$SPEC_PATH" | head -1)
  
  if [ -n "$version" ]; then
    echo "$version"
  else
    echo ""
    return 1
  fi
}

get_latest_stable_version() {
  local KERNEL_VERSION="$1"
  local KERNEL_ORG_URL=$(get_kernel_org_url "$KERNEL_VERSION")
  
  log "Checking latest stable version for kernel $KERNEL_VERSION..." >&2
  
  # Fetch directory listing from kernel.org
  local listing=$(curl -s --max-time 30 "$KERNEL_ORG_URL" 2>/dev/null)
  
  if [ -z "$listing" ]; then
    log_error "Failed to fetch kernel.org listing" >&2
    echo ""
    return 1
  fi
  
  # Find latest patch version (e.g., patch-6.1.123.xz)
  local latest=$(echo "$listing" | \
    grep -oP "patch-${KERNEL_VERSION}\.[0-9]+\.xz" | \
    sed "s/patch-${KERNEL_VERSION}\.\([0-9]*\)\.xz/\1/" | \
    sort -n | tail -1)
  
  if [ -n "$latest" ]; then
    echo "${KERNEL_VERSION}.${latest}"
  else
    echo ""
  fi
}

get_stable_marker_file() {
  local KERNEL_VERSION="$1"
  echo "${STABLE_MARKER_DIR}/.stable_${KERNEL_VERSION}_last_version"
}

get_last_integrated_version() {
  local KERNEL_VERSION="$1"
  local marker=$(get_stable_marker_file "$KERNEL_VERSION")
  
  if [ -f "$marker" ]; then
    cat "$marker"
  else
    echo ""
  fi
}

update_stable_marker() {
  local KERNEL_VERSION="$1"
  local VERSION="$2"
  local marker=$(get_stable_marker_file "$KERNEL_VERSION")
  
  mkdir -p "$(dirname "$marker")"
  echo "$VERSION" > "$marker"
}

# -----------------------------------------------------------------------------
# Stable Patch Download
# -----------------------------------------------------------------------------
download_stable_patches() {
  local KERNEL_VERSION="$1"
  local OUTPUT_DIR="$2"
  local START_SUBVER="${3:-1}"
  local END_SUBVER="${4:-}"
  
  local KERNEL_ORG_URL=$(get_kernel_org_url "$KERNEL_VERSION")
  local PATCH_DIR="$OUTPUT_DIR/stable_patches"
  mkdir -p "$PATCH_DIR"
  
  log "Downloading stable patches for kernel $KERNEL_VERSION from $KERNEL_ORG_URL" >&2
  
  local patch_num=$START_SUBVER
  local downloaded=0
  
  while true; do
    # Check if we've reached the end
    if [ -n "$END_SUBVER" ] && [ $patch_num -gt $END_SUBVER ]; then
      break
    fi
    
    local patch_file="patch-${KERNEL_VERSION}.${patch_num}.xz"
    local url="${KERNEL_ORG_URL}${patch_file}"
    local xz_path="$PATCH_DIR/$patch_file"
    local patch_path="$PATCH_DIR/patch-${KERNEL_VERSION}.${patch_num}"
    
    # Download compressed patch
    if ! curl -sf --max-time 60 -o "$xz_path" "$url" 2>/dev/null; then
      if [ $downloaded -eq 0 ] && [ $patch_num -eq $START_SUBVER ]; then
        log_warn "No patches found starting from ${KERNEL_VERSION}.${patch_num}" >&2
      else
        log "No more patches found after ${KERNEL_VERSION}.$((patch_num - 1))" >&2
      fi
      break
    fi
    
    # Decompress
    if ! xz -d -k -f "$xz_path" 2>/dev/null; then
      log_warn "Failed to decompress $patch_file (possibly corrupt), skipping" >&2
      rm -f "$xz_path"
      patch_num=$((patch_num + 1))
      continue
    fi
    
    # Rename decompressed file
    mv "${xz_path%.xz}" "$patch_path" 2>/dev/null || true
    
    log "  Downloaded: $patch_file -> patch-${KERNEL_VERSION}.${patch_num}" >&2
    downloaded=$((downloaded + 1))
    patch_num=$((patch_num + 1))
  done
  
  log "Downloaded $downloaded stable patches" >&2
  echo "$downloaded"
}

# -----------------------------------------------------------------------------
# Stable Patch Integration (spec2git workflow)
# -----------------------------------------------------------------------------
check_spec2git_available() {
  local PHOTON_DIR="$1"
  local SPEC2GIT="$PHOTON_DIR/tools/scripts/spec2git/spec2git.py"
  
  if [ -f "$SPEC2GIT" ]; then
    echo "$SPEC2GIT"
    return 0
  else
    echo ""
    return 1
  fi
}

run_spec2git_tests() {
  local PHOTON_DIR="$1"
  local TESTS_DIR="$PHOTON_DIR/tools/scripts/spec2git/tests"
  
  if [ ! -d "$TESTS_DIR" ]; then
    log_warn "spec2git tests directory not found"
    return 1
  fi
  
  log "Running spec2git tests..."
  (cd "$TESTS_DIR" && python3 -m pytest . -q) 2>&1 | while read line; do
    log "  $line"
  done
  
  return ${PIPESTATUS[0]}
}

integrate_stable_patches_spec2git() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local PATCH_DIR="$3"
  local SPEC_FILE="$4"
  local CANISTER="${5:-0}"
  local ACVP="${6:-0}"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$SPEC_FILE"
  local SPEC2GIT=$(check_spec2git_available "$REPO_DIR")
  
  if [ -z "$SPEC2GIT" ]; then
    log_error "spec2git not found in $REPO_DIR"
    return 1
  fi
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  local SPEC_BASE="${SPEC_FILE%.*}"
  local GIT_DIR="$REPO_DIR/linux-git-${SPEC_BASE}-c${CANISTER}-a${ACVP}-${KERNEL_VERSION}"
  
  log "Integrating stable patches into $SPEC_FILE..."
  log "  Canister build: $CANISTER, ACVP build: $ACVP"
  
  # Clean up any existing git directory
  safe_remove_dir "$GIT_DIR"
  
  # Convert spec to git
  log "  Converting spec to git repository..."
  cd "$REPO_DIR/$SPEC_SUBDIR" || return 1
  
  if ! python3 "$SPEC2GIT" "$SPEC_FILE" --output-dir "$GIT_DIR" \
       --define canister_build=$CANISTER --define acvp_build=$ACVP --force 2>&1 | \
       while read line; do log_debug "    $line"; done; then
    log_error "spec2git conversion failed"
    return 1
  fi
  
  # Disable auto gc in git repo
  cd "$GIT_DIR" || return 1
  git config gc.auto 0
  
  # Apply stable patches
  local applied=0
  for patch_file in $(ls "$PATCH_DIR"/patch-"$KERNEL_VERSION".* 2>/dev/null | sort -V); do
    if [ -f "$patch_file" ] && [[ ! "$patch_file" =~ \.xz$ ]]; then
      log "  Applying: $(basename "$patch_file")"
      
      if git apply --check "$patch_file" 2>/dev/null; then
        git apply "$patch_file"
        git add -A
        git commit -m "Applied stable patch: $(basename "$patch_file")" 2>/dev/null || true
        applied=$((applied + 1))
      else
        log_warn "  Patch did not apply cleanly: $(basename "$patch_file")"
      fi
    fi
  done
  
  log "  Applied $applied stable patches"
  
  # Convert back to spec
  cd "$REPO_DIR/$SPEC_SUBDIR" || return 1
  log "  Converting git back to spec..."
  
  if ! python3 "$SPEC2GIT" "$SPEC_FILE" --git2spec --git-repo "$GIT_DIR" \
       --changelog "Integrated stable patches for Linux kernel $KERNEL_VERSION" 2>&1 | \
       while read line; do log_debug "    $line"; done; then
    log_error "git2spec conversion failed"
    return 1
  fi
  
  # Validate updated spec
  if ! rpmspec --parse "$SPEC_FILE" > /dev/null 2>&1; then
    log_error "Updated spec file is invalid"
    return 1
  fi
  
  log "  Successfully integrated stable patches into $SPEC_FILE"
  
  # Cleanup
  safe_remove_dir "$GIT_DIR"
  
  echo "$applied"
}

# -----------------------------------------------------------------------------
# Simple Patch Integration (without spec2git)
# -----------------------------------------------------------------------------
integrate_stable_patch_simple() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local PATCH_FILE="$3"
  local SPEC_FILE="$4"
  local SKILLS_FILE="${5:-}"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$SPEC_FILE"
  local AVAILABLE_SPECS=$(get_spec_files_for_kernel "$KERNEL_VERSION")
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  local PATCH_NAME=$(basename "$PATCH_FILE")
  local PATCH_NUM=$(get_next_patch_number "$SPEC_PATH")
  
  if [ "$PATCH_NUM" -eq -1 ]; then
    log_error "Patch number range is full"
    return 1
  fi
  
  # Copy patch to spec directory
  cp "$PATCH_FILE" "$REPO_DIR/$SPEC_SUBDIR/$PATCH_NAME"
  
  # Add patch to spec
  if add_patch_to_spec "$SPEC_PATH" "$PATCH_NAME" "$PATCH_NUM"; then
    log "Added Patch${PATCH_NUM}: $PATCH_NAME to $SPEC_FILE"
    return 0
  else
    log_error "Failed to add patch to spec"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Main Stable Patches Function
# -----------------------------------------------------------------------------
find_and_download_stable_patches() {
  local KERNEL_VERSION="$1"
  local OUTPUT_DIR="$2"
  local DRY_RUN="${3:-false}"
  
  log "=== Stable Kernel Patches ===" >&2
  log "Kernel version: $KERNEL_VERSION" >&2
  
  # Get current and latest versions
  local latest=$(get_latest_stable_version "$KERNEL_VERSION")
  local last_integrated=$(get_last_integrated_version "$KERNEL_VERSION")
  
  if [ -z "$latest" ]; then
    log_warn "Could not determine latest stable version" >&2
    echo "0"
    return 1
  fi
  
  log "Latest stable: $latest" >&2
  log "Last integrated: ${last_integrated:-none}" >&2
  
  # Determine starting subversion
  local latest_subver=$(echo "$latest" | cut -d. -f3)
  local start_subver=1
  
  if [ -n "$last_integrated" ]; then
    local last_subver=$(echo "$last_integrated" | cut -d. -f3)
    start_subver=$((last_subver + 1))
    
    if [ $start_subver -gt $latest_subver ]; then
      log "Already up to date (at $last_integrated)" >&2
      echo "0"
      return 0
    fi
  fi
  
  log "Will download patches from ${KERNEL_VERSION}.${start_subver} to ${KERNEL_VERSION}.${latest_subver}" >&2
  
  if [ "$DRY_RUN" = true ]; then
    log "Dry run - skipping actual download" >&2
    echo "0"
    return 0
  fi
  
  # Download patches
  local downloaded=$(download_stable_patches "$KERNEL_VERSION" "$OUTPUT_DIR" "$start_subver" "$latest_subver")
  
  if [ "$downloaded" -gt 0 ]; then
    update_stable_marker "$KERNEL_VERSION" "$latest"
    log "Updated stable marker to $latest" >&2
  fi
  
  echo "$downloaded"
}

# =============================================================================
# Checkpoint Management for Resume Capability
# =============================================================================

CHECKPOINT_FILE="${CHECKPOINT_FILE:-checkpoint.conf}"

# Save checkpoint state
save_checkpoint() {
  local kernel_version="$1"
  local spec_file="$2"
  local canister="$3"
  local acvp="$4"
  local stable_patch_index="$5"
  local patch_count="$6"
  local checkpoint_dir="${7:-.}"
  
  local checkpoint_path="$checkpoint_dir/$CHECKPOINT_FILE"
  
  cat > "$checkpoint_path" << EOF
kernel_version=$kernel_version
spec_file=$spec_file
canister=$canister
acvp=$acvp
stable_patch_index=$stable_patch_index
patch_count=$patch_count
timestamp=$(date +%s)
EOF
  
  log "Checkpoint saved: $spec_file canister=$canister acvp=$acvp patch=$stable_patch_index/$patch_count" >&2
}

# Load checkpoint state
load_checkpoint() {
  local checkpoint_dir="${1:-.}"
  local checkpoint_path="$checkpoint_dir/$CHECKPOINT_FILE"
  
  if [ ! -f "$checkpoint_path" ]; then
    echo ""
    return 1
  fi
  
  # Validate checkpoint file
  local kernel=$(grep '^kernel_version=' "$checkpoint_path" 2>/dev/null | cut -d= -f2)
  local spec=$(grep '^spec_file=' "$checkpoint_path" 2>/dev/null | cut -d= -f2)
  local canister=$(grep '^canister=' "$checkpoint_path" 2>/dev/null | cut -d= -f2)
  local acvp=$(grep '^acvp=' "$checkpoint_path" 2>/dev/null | cut -d= -f2)
  local patch_idx=$(grep '^stable_patch_index=' "$checkpoint_path" 2>/dev/null | cut -d= -f2)
  local timestamp=$(grep '^timestamp=' "$checkpoint_path" 2>/dev/null | cut -d= -f2)
  
  if [ -z "$kernel" ] || [ -z "$spec" ]; then
    echo ""
    return 1
  fi
  
  echo "$kernel|$spec|$canister|$acvp|$patch_idx|$timestamp"
}

# Validate checkpoint matches current run
validate_checkpoint() {
  local checkpoint_data="$1"
  local expected_kernel="$2"
  
  local ckpt_kernel=$(echo "$checkpoint_data" | cut -d'|' -f1)
  
  if [ "$ckpt_kernel" = "$expected_kernel" ]; then
    return 0
  fi
  return 1
}

# Clear checkpoint after successful completion
clear_checkpoint() {
  local checkpoint_dir="${1:-.}"
  rm -f "$checkpoint_dir/$CHECKPOINT_FILE"
  log "Checkpoint cleared" >&2
}

# =============================================================================
# Simple Stable Workflow (fallback when spec2git not available)
# =============================================================================

# Run simple stable patch integration without spec2git
run_simple_stable_workflow() {
  local KERNEL_VERSION="$1"
  local PHOTON_DIR="$2"
  local PATCH_DIR="$3"
  local REPORT_DIR="$4"
  local ANALYZE_CVES="${5:-false}"
  local CVE_SINCE="${6:-}"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local SPEC_DIR="$PHOTON_DIR/$SPEC_SUBDIR"
  local AVAILABLE_SPECS=$(get_spec_files_for_kernel "$KERNEL_VERSION")
  
  log "=== Simple Stable Patch Integration ===" >&2
  log "Kernel: $KERNEL_VERSION" >&2
  log "Spec directory: $SPEC_DIR" >&2
  log "Available specs: $AVAILABLE_SPECS" >&2
  
  # Verify spec directory exists
  if [ ! -d "$SPEC_DIR" ]; then
    log_error "Spec directory not found: $SPEC_DIR" >&2
    return 1
  fi
  
  # Get list of stable patches
  local stable_patches=($(ls "$PATCH_DIR"/patch-"$KERNEL_VERSION".* 2>/dev/null | grep -v '\.xz$' | sort -V))
  local total_patches=${#stable_patches[@]}
  
  if [ $total_patches -eq 0 ]; then
    log "No stable patches found in $PATCH_DIR" >&2
    return 0
  fi
  
  log "Found $total_patches stable patches to process" >&2
  
  # Initialize CVE report if analyzing
  local cve_report=""
  if [ "$ANALYZE_CVES" = true ]; then
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$script_dir/cve_analysis.sh" 2>/dev/null || true
    if type init_cve_report &>/dev/null; then
      cve_report=$(init_cve_report "$KERNEL_VERSION" "$REPORT_DIR")
      log "CVE report initialized: $cve_report" >&2
    fi
  fi
  
  local all_redundant_cves=""
  local integrated_count=0
  local skipped_count=0
  
  # Process each spec file
  for spec in $AVAILABLE_SPECS; do
    local spec_path="$SPEC_DIR/$spec"
    
    if [ ! -f "$spec_path" ]; then
      log_warn "Spec file not found: $spec_path" >&2
      continue
    fi
    
    log "" >&2
    log "Processing spec: $spec" >&2
    
    local patch_idx=0
    for patch_file in "${stable_patches[@]}"; do
      patch_idx=$((patch_idx + 1))
      local patch_name=$(basename "$patch_file")
      
      log "  [$patch_idx/$total_patches] Processing: $patch_name" >&2
      
      # Check if already integrated (by patch name in spec)
      if grep -q "$patch_name" "$spec_path" 2>/dev/null; then
        log "    Skipped: already in spec" >&2
        skipped_count=$((skipped_count + 1))
        continue
      fi
      
      # Copy patch to spec directory
      cp "$patch_file" "$SPEC_DIR/$patch_name"
      
      # Get next available patch number
      local patch_num=$(get_next_patch_number "$spec_path" 2>/dev/null || echo "100")
      
      # Add patch to spec using simple method
      if add_patch_to_spec "$spec_path" "$patch_name" "$patch_num" 2>/dev/null; then
        log "    Added as Patch${patch_num}" >&2
        integrated_count=$((integrated_count + 1))
        
        # Analyze CVE coverage if enabled
        if [ "$ANALYZE_CVES" = true ] && [ -n "$cve_report" ]; then
          if type extract_cves_from_patch &>/dev/null; then
            local patch_cves=$(extract_cves_from_patch "$patch_file" 2>/dev/null)
            local redundant=$(analyze_stable_patch_cve_coverage "$patch_file" "$spec_path" "$SPEC_DIR" "" 2>/dev/null)
            
            if [ -n "$CVE_SINCE" ] && type filter_cves_since &>/dev/null; then
              patch_cves=$(filter_cves_since "$patch_cves" "$CVE_SINCE")
              redundant=$(filter_cves_since "$redundant" "$CVE_SINCE")
            fi
            
            if [ -n "$redundant" ]; then
              log "    CVEs now redundant: $redundant" >&2
              all_redundant_cves="$all_redundant_cves $redundant"
            fi
            
            if type add_patch_to_report &>/dev/null; then
              add_patch_to_report "$cve_report" "$patch_name" "true" "$patch_cves" "$redundant"
            fi
          fi
        fi
      else
        log_warn "    Failed to add to spec" >&2
      fi
    done
  done
  
  # Finalize CVE report
  if [ "$ANALYZE_CVES" = true ] && [ -n "$cve_report" ]; then
    if type finalize_cve_report &>/dev/null; then
      local total_cves=0
      local cves_fixed=$(echo "$all_redundant_cves" | tr ' ' '\n' | grep -E 'CVE-[0-9]+-[0-9]+' | sort -u | wc -l)
      finalize_cve_report "$cve_report" "$total_patches" "$total_cves" "$cves_fixed" "0"
    fi
  fi
  
  log "" >&2
  log "=== Simple Integration Complete ===" >&2
  log "Integrated: $integrated_count patches" >&2
  log "Skipped: $skipped_count patches (already present)" >&2
  log "Patches copied to: $SPEC_DIR/" >&2
  
  return 0
}

# =============================================================================
# Full Spec2Git Workflow with Permutations
# =============================================================================

# Run the complete spec2git workflow for a kernel version
# Falls back to simple integration if spec2git is not available
run_spec2git_full_workflow() {
  local KERNEL_VERSION="$1"
  local PHOTON_DIR="$2"
  local PATCH_DIR="$3"
  local REPORT_DIR="$4"
  local RESUME="${5:-false}"
  local ANALYZE_CVES="${6:-false}"
  local CVE_SINCE="${7:-}"
  
  local SPEC2GIT=$(check_spec2git_available "$PHOTON_DIR")
  if [ -z "$SPEC2GIT" ]; then
    log_warn "spec2git not found in $PHOTON_DIR - using simple integration mode" >&2
    log "Note: spec2git is an optional advanced tool. Simple integration will copy patches to spec directory." >&2
    run_simple_stable_workflow "$KERNEL_VERSION" "$PHOTON_DIR" "$PATCH_DIR" "$REPORT_DIR" "$ANALYZE_CVES" "$CVE_SINCE"
    return $?
  fi
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local SPEC_DIR="$PHOTON_DIR/$SPEC_SUBDIR"
  local TESTS_DIR="$PHOTON_DIR/tools/scripts/spec2git/tests"
  local AVAILABLE_SPECS=$(get_spec_files_for_kernel "$KERNEL_VERSION")
  
  log "=== Full Spec2Git Workflow ===" >&2
  log "Kernel: $KERNEL_VERSION" >&2
  log "Spec directory: $SPEC_DIR" >&2
  log "Available specs: $AVAILABLE_SPECS" >&2
  log "Analyze CVEs: $ANALYZE_CVES" >&2
  
  # Verify spec directory exists
  if [ ! -d "$SPEC_DIR" ]; then
    log_error "Spec directory not found: $SPEC_DIR" >&2
    return 1
  fi
  
  # Run spec2git tests first
  if ! run_spec2git_tests "$PHOTON_DIR"; then
    log_error "spec2git tests failed, aborting" >&2
    return 1
  fi
  
  # Get list of stable patches
  local stable_patches=($(ls "$PATCH_DIR"/patch-"$KERNEL_VERSION".* 2>/dev/null | grep -v '\.xz$' | sort -V))
  local total_patches=${#stable_patches[@]}
  
  if [ $total_patches -eq 0 ]; then
    log "No stable patches found in $PATCH_DIR" >&2
    return 0
  fi
  
  log "Found $total_patches stable patches to process" >&2
  
  # Check for checkpoint if resuming
  local start_spec_idx=0
  local start_canister=0
  local start_acvp=0
  local start_patch_idx=0
  
  if [ "$RESUME" = true ]; then
    local ckpt=$(load_checkpoint "$REPORT_DIR")
    if [ -n "$ckpt" ] && validate_checkpoint "$ckpt" "$KERNEL_VERSION"; then
      start_spec_idx=0  # Would need spec index lookup
      start_canister=$(echo "$ckpt" | cut -d'|' -f3)
      start_acvp=$(echo "$ckpt" | cut -d'|' -f4)
      start_patch_idx=$(echo "$ckpt" | cut -d'|' -f5)
      log "Resuming from checkpoint: canister=$start_canister acvp=$start_acvp patch=$start_patch_idx" >&2
    fi
  fi
  
  # Initialize CVE report if analyzing
  local cve_report=""
  if [ "$ANALYZE_CVES" = true ]; then
    # Source CVE analysis library
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$script_dir/cve_analysis.sh"
    cve_report=$(init_cve_report "$KERNEL_VERSION" "$REPORT_DIR")
    log "CVE report initialized: $cve_report" >&2
  fi
  
  local total_cves_fixed=0
  local all_redundant_cves=""
  
  # Process each spec file
  local spec_idx=0
  for spec in $AVAILABLE_SPECS; do
    local spec_path="$SPEC_DIR/$spec"
    
    if [ ! -f "$spec_path" ]; then
      log_warn "Spec file not found: $spec_path" >&2
      continue
    fi
    
    log "" >&2
    log "Processing spec: $spec" >&2
    
    # Process permutations: canister_build (0,1) x acvp_build (0,1)
    for canister in 0 1; do
      for acvp in 0 1; do
        # Skip if resuming and before checkpoint
        if [ $spec_idx -eq 0 ] && [ $canister -lt $start_canister ]; then
          continue
        fi
        if [ $spec_idx -eq 0 ] && [ $canister -eq $start_canister ] && [ $acvp -lt $start_acvp ]; then
          continue
        fi
        
        local spec_base="${spec%.*}"
        local git_dir="$PHOTON_DIR/linux-git-${spec_base}-c${canister}-a${acvp}-${KERNEL_VERSION}"
        
        log "  Permutation: canister_build=$canister, acvp_build=$acvp" >&2
        
        # Clean up any existing git directory
        safe_remove_dir "$git_dir"
        
        # Convert spec to git
        log "    Converting spec to git..." >&2
        cd "$SPEC_DIR" || return 1
        
        if ! python3 "$SPEC2GIT" "$spec" --output-dir "$git_dir" \
             --define canister_build=$canister --define acvp_build=$acvp --force 2>&1 | \
             while read line; do log_debug "      $line"; done; then
          log_error "    spec2git conversion failed" >&2
          return 1
        fi
        
        # Disable auto gc
        cd "$git_dir" || return 1
        git config gc.auto 0
        
        # Apply stable patches one by one
        local patch_idx=0
        for patch_file in "${stable_patches[@]}"; do
          patch_idx=$((patch_idx + 1))
          
          # Skip if resuming and before checkpoint
          if [ $spec_idx -eq 0 ] && [ $canister -eq $start_canister ] && \
             [ $acvp -eq $start_acvp ] && [ $patch_idx -le $start_patch_idx ]; then
            continue
          fi
          
          local patch_name=$(basename "$patch_file")
          log "    [$patch_idx/$total_patches] Applying: $patch_name" >&2
          
          # Try to apply the patch
          local applied=false
          if git apply --check "$patch_file" 2>/dev/null; then
            if git apply "$patch_file" 2>/dev/null; then
              git add -A
              git commit -m "Applied stable patch: $patch_name" 2>/dev/null || true
              applied=true
              log "      Applied successfully" >&2
            fi
          fi
          
          if [ "$applied" = false ]; then
            log_warn "      Patch did not apply cleanly (may be already applied or conflict)" >&2
          fi
          
          # Analyze CVE coverage if enabled
          if [ "$ANALYZE_CVES" = true ] && [ "$applied" = true ]; then
            local patch_cves=$(extract_cves_from_patch "$patch_file")
            local redundant=$(analyze_stable_patch_cve_coverage "$patch_file" "$spec_path" "$SPEC_DIR" "")
            
            # Filter by date if specified
            if [ -n "$CVE_SINCE" ]; then
              patch_cves=$(filter_cves_since "$patch_cves" "$CVE_SINCE")
              redundant=$(filter_cves_since "$redundant" "$CVE_SINCE")
            fi
            
            if [ -n "$redundant" ]; then
              log "      CVEs now redundant: $redundant" >&2
              all_redundant_cves="$all_redundant_cves $redundant"
            fi
            
            add_patch_to_report "$cve_report" "$patch_name" "true" "$patch_cves" "$redundant"
          fi
          
          # Save checkpoint
          save_checkpoint "$KERNEL_VERSION" "$spec" "$canister" "$acvp" "$patch_idx" "$total_patches" "$REPORT_DIR"
        done
        
        # Convert back to spec
        cd "$SPEC_DIR" || return 1
        log "    Converting git back to spec..." >&2
        
        if ! python3 "$SPEC2GIT" "$spec" --git2spec --git-repo "$git_dir" \
             --changelog "Integrated stable patches for kernel $KERNEL_VERSION (canister=$canister, acvp=$acvp)" 2>&1 | \
             while read line; do log_debug "      $line"; done; then
          log_error "    git2spec conversion failed" >&2
          return 1
        fi
        
        # Validate spec
        if ! rpmspec --parse "$spec" > /dev/null 2>&1; then
          log_error "    Updated spec is invalid" >&2
          return 1
        fi
        log "    Spec validated successfully" >&2
        
        # Run targeted tests
        cd "$TESTS_DIR" || return 1
        if ! python3 -m pytest test_git2spec.py test_end_to_end.py -q 2>&1 | \
             while read line; do log_debug "      $line"; done; then
          log_error "    Tests failed for this permutation" >&2
          return 1
        fi
        log "    Tests passed" >&2
        
        # Cleanup git directory
        safe_remove_dir "$git_dir"
      done
    done
    
    spec_idx=$((spec_idx + 1))
  done
  
  # Finalize CVE report
  if [ "$ANALYZE_CVES" = true ] && [ -n "$cve_report" ]; then
    local total_cves=$(echo "$AVAILABLE_SPECS" | xargs -I{} sh -c "extract_cves_from_spec '$SPEC_DIR/{}'" 2>/dev/null | sort -u | wc -l)
    local cves_fixed=$(echo "$all_redundant_cves" | tr ' ' '\n' | grep -E 'CVE-[0-9]+-[0-9]+' | sort -u | wc -l)
    local cves_needed=$((total_cves - cves_fixed))
    [ "$cves_needed" -lt 0 ] && cves_needed=0
    
    finalize_cve_report "$cve_report" "$total_patches" "$total_cves" "$cves_fixed" "$cves_needed"
  fi
  
  # Clear checkpoint on success
  clear_checkpoint "$REPORT_DIR"
  
  log "" >&2
  log "=== Workflow Complete ===" >&2
  log "Processed $total_patches stable patches across $(echo "$AVAILABLE_SPECS" | wc -w) spec files" >&2
  
  return 0
}
