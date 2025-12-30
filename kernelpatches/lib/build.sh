#!/bin/bash
# =============================================================================
# Build Library Functions for Kernel Backport Solution
# =============================================================================
# Functions for building kernel RPMs after patch integration
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/lib/build.sh"
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_BUILD_SH_LOADED:-}" ]] && return 0
_BUILD_SH_LOADED=1

# -----------------------------------------------------------------------------
# Build Configuration
# -----------------------------------------------------------------------------
BUILD_TIMEOUT="${BUILD_TIMEOUT:-3600}"  # 1 hour default timeout for kernel builds

# -----------------------------------------------------------------------------
# Dependency Verification
# -----------------------------------------------------------------------------

# Verify build dependencies are available
verify_build_deps() {
  local missing=()
  
  # Check for rpmbuild
  if ! command -v rpmbuild >/dev/null 2>&1; then
    missing+=("rpmbuild (rpm-build package)")
  fi
  
  # Check for rpm
  if ! command -v rpm >/dev/null 2>&1; then
    missing+=("rpm")
  fi
  
  # Check for make
  if ! command -v make >/dev/null 2>&1; then
    missing+=("make")
  fi
  
  # Check for gcc
  if ! command -v gcc >/dev/null 2>&1; then
    missing+=("gcc")
  fi
  
  if [ ${#missing[@]} -gt 0 ]; then
    log_error "Missing build dependencies: ${missing[*]}"
    return 1
  fi
  
  log "Build dependencies verified"
  return 0
}

# -----------------------------------------------------------------------------
# RPM Build Functions
# -----------------------------------------------------------------------------

# Build kernel RPM from spec file
# Arguments:
#   $1 - SPEC_PATH: Full path to spec file
#   $2 - BUILD_LOG: Path to build log file
#   $3 - CANISTER: canister_build value (0 or 1, default: 0)
#   $4 - ACVP: acvp_build value (0 or 1, default: 0)
#   $5 - TOPDIR: RPM build top directory (optional)
# Returns: 0 on success, 1 on failure
build_kernel_rpm() {
  local SPEC_PATH="$1"
  local BUILD_LOG="$2"
  local CANISTER="${3:-0}"
  local ACVP="${4:-0}"
  local TOPDIR="${5:-}"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  local SPEC_NAME=$(basename "$SPEC_PATH")
  local SPEC_DIR=$(dirname "$SPEC_PATH")
  
  log "Building $SPEC_NAME (canister=$CANISTER, acvp=$ACVP)..."
  log "  Spec: $SPEC_PATH"
  log "  Log: $BUILD_LOG"
  
  # Build rpmbuild command
  local RPMBUILD_CMD="rpmbuild -bb"
  
  # Add defines
  RPMBUILD_CMD="$RPMBUILD_CMD --define 'canister_build $CANISTER'"
  RPMBUILD_CMD="$RPMBUILD_CMD --define 'acvp_build $ACVP'"
  
  # Add topdir if specified
  if [ -n "$TOPDIR" ]; then
    RPMBUILD_CMD="$RPMBUILD_CMD --define '_topdir $TOPDIR'"
  fi
  
  # Add spec file
  RPMBUILD_CMD="$RPMBUILD_CMD $SPEC_PATH"
  
  # Run build with timeout
  log "  Running: $RPMBUILD_CMD"
  
  local START_TIME=$(date +%s)
  
  if timeout "$BUILD_TIMEOUT" bash -c "$RPMBUILD_CMD" > "$BUILD_LOG" 2>&1; then
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    log "  Build successful in ${DURATION}s"
    return 0
  else
    local EXIT_CODE=$?
    local END_TIME=$(date +%s)
    local DURATION=$((END_TIME - START_TIME))
    
    if [ $EXIT_CODE -eq 124 ]; then
      log_error "  Build timed out after ${BUILD_TIMEOUT}s"
    else
      log_error "  Build failed (exit code: $EXIT_CODE) after ${DURATION}s"
    fi
    
    # Show last 20 lines of build log
    if [ -f "$BUILD_LOG" ]; then
      log_error "  Last 20 lines of build log:"
      tail -20 "$BUILD_LOG" | while read line; do
        log_error "    $line"
      done
    fi
    
    return 1
  fi
}

# Build all kernel specs for a given kernel version
# Arguments:
#   $1 - KERNEL_VERSION: Kernel version (e.g., "6.1")
#   $2 - REPO_DIR: Path to Photon repository
#   $3 - OUTPUT_DIR: Directory for build logs
#   $4 - CANISTER: canister_build value (0 or 1, default: 0)
#   $5 - ACVP: acvp_build value (0 or 1, default: 0)
# Returns: 0 if all builds succeed, 1 if any fail
build_all_kernel_specs() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local OUTPUT_DIR="$3"
  local CANISTER="${4:-0}"
  local ACVP="${5:-0}"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local AVAILABLE_SPECS=$(get_spec_files_for_kernel "$KERNEL_VERSION")
  
  if [ -z "$SPEC_SUBDIR" ] || [ -z "$AVAILABLE_SPECS" ]; then
    log_error "Invalid kernel version: $KERNEL_VERSION"
    return 1
  fi
  
  local BUILD_SUCCESS=0
  local BUILD_FAILED=0
  local BUILD_LOGS=()
  
  log "Building kernel specs for $KERNEL_VERSION..."
  log "  Specs: $AVAILABLE_SPECS"
  log "  Spec directory: $REPO_DIR/$SPEC_SUBDIR"
  
  for spec in $AVAILABLE_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    local BUILD_LOG="$OUTPUT_DIR/build_${spec%.spec}.log"
    
    if [ ! -f "$SPEC_PATH" ]; then
      log_warn "Spec file not found, skipping: $SPEC_PATH"
      continue
    fi
    
    if build_kernel_rpm "$SPEC_PATH" "$BUILD_LOG" "$CANISTER" "$ACVP"; then
      BUILD_SUCCESS=$((BUILD_SUCCESS + 1))
    else
      BUILD_FAILED=$((BUILD_FAILED + 1))
      BUILD_LOGS+=("$BUILD_LOG")
    fi
  done
  
  log ""
  log "Build Summary: Success=$BUILD_SUCCESS, Failed=$BUILD_FAILED"
  
  if [ $BUILD_FAILED -gt 0 ]; then
    log_error "Failed build logs:"
    for log_file in "${BUILD_LOGS[@]}"; do
      log_error "  $log_file"
    done
    return 1
  fi
  
  return 0
}

# Build with all permutations of canister_build and acvp_build
# Arguments:
#   $1 - KERNEL_VERSION: Kernel version
#   $2 - REPO_DIR: Path to Photon repository
#   $3 - OUTPUT_DIR: Directory for build logs
# Returns: 0 if all permutations succeed, 1 if any fail
build_all_permutations() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local OUTPUT_DIR="$3"
  
  local PERMUTATIONS=(
    "0 0"  # canister=0, acvp=0 (standard build)
    "1 0"  # canister=1, acvp=0 (canister build)
    "0 1"  # canister=0, acvp=1 (acvp build)
    "1 1"  # canister=1, acvp=1 (canister+acvp build)
  )
  
  local TOTAL_SUCCESS=0
  local TOTAL_FAILED=0
  
  log "Building all permutations for kernel $KERNEL_VERSION..."
  
  for perm in "${PERMUTATIONS[@]}"; do
    read -r canister acvp <<< "$perm"
    log ""
    log "=== Permutation: canister_build=$canister, acvp_build=$acvp ==="
    
    local PERM_OUTPUT="$OUTPUT_DIR/perm_c${canister}_a${acvp}"
    mkdir -p "$PERM_OUTPUT"
    
    if build_all_kernel_specs "$KERNEL_VERSION" "$REPO_DIR" "$PERM_OUTPUT" "$canister" "$acvp"; then
      TOTAL_SUCCESS=$((TOTAL_SUCCESS + 1))
    else
      TOTAL_FAILED=$((TOTAL_FAILED + 1))
    fi
  done
  
  log ""
  log "Permutation Summary: Success=$TOTAL_SUCCESS/4, Failed=$TOTAL_FAILED/4"
  
  if [ $TOTAL_FAILED -gt 0 ]; then
    return 1
  fi
  
  return 0
}

# -----------------------------------------------------------------------------
# Build Step for kernel_backport.sh
# -----------------------------------------------------------------------------

# Run the build step after patch integration
# Arguments:
#   $1 - KERNEL_VERSION: Kernel version
#   $2 - REPO_DIR: Path to Photon repository
#   $3 - OUTPUT_DIR: Directory for build logs
#   $4 - PATCH_COUNT: Number of patches integrated (for changelog)
#   $5 - AVAILABLE_SPECS: Space-separated list of spec files to build
#   $6 - DRY_RUN: "true" to skip actual build
# Returns: 0 on success, 1 on failure
run_build_step() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  local OUTPUT_DIR="$3"
  local PATCH_COUNT="$4"
  local AVAILABLE_SPECS="$5"
  local DRY_RUN="${6:-false}"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  
  if [ -z "$SPEC_SUBDIR" ]; then
    log_error "Invalid kernel version: $KERNEL_VERSION"
    return 1
  fi
  
  log ""
  log "=== Build Step: Update Spec and Build RPMs ==="
  
  # Verify build dependencies
  if [ "$DRY_RUN" != "true" ]; then
    if ! verify_build_deps; then
      log_error "Build dependencies not met"
      return 1
    fi
  fi
  
  local BUILD_FAILED=false
  local CHANGELOG_MSG="Backported $PATCH_COUNT CVE patch(es)"
  
  for spec in $AVAILABLE_SPECS; do
    local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/$spec"
    
    if [ ! -f "$SPEC_PATH" ]; then
      log_warn "Spec file not found, skipping: $SPEC_PATH"
      continue
    fi
    
    log ""
    log "Processing $spec..."
    
    # Get current version
    local VERSION=$(get_spec_version "$SPEC_PATH")
    if [ -z "$VERSION" ]; then
      log_error "Could not get version from $SPEC_PATH"
      BUILD_FAILED=true
      continue
    fi
    
    if [ "$DRY_RUN" = "true" ]; then
      local CURRENT_RELEASE=$(get_spec_release "$SPEC_PATH")
      log "  DRY RUN: Would increment Release $CURRENT_RELEASE -> $((CURRENT_RELEASE + 1))"
      log "  DRY RUN: Would add changelog entry for $VERSION-$((CURRENT_RELEASE + 1))"
      log "  DRY RUN: Would build $spec"
      continue
    fi
    
    # Increment release number
    local NEW_RELEASE=$(increment_spec_release "$SPEC_PATH")
    if [ -z "$NEW_RELEASE" ]; then
      log_error "Failed to increment release for $spec"
      BUILD_FAILED=true
      continue
    fi
    
    # Add changelog entry
    if ! add_changelog_entry "$SPEC_PATH" "$VERSION" "$NEW_RELEASE" "$CHANGELOG_MSG"; then
      log_error "Failed to add changelog entry for $spec"
      BUILD_FAILED=true
      continue
    fi
    
    # Build RPM
    local BUILD_LOG="$OUTPUT_DIR/build_${spec%.spec}.log"
    if ! build_kernel_rpm "$SPEC_PATH" "$BUILD_LOG"; then
      log_error "Build failed for $spec"
      BUILD_FAILED=true
      continue
    fi
    
    log "  Successfully built $spec (Release: $NEW_RELEASE)"
  done
  
  if [ "$BUILD_FAILED" = true ]; then
    log_error "One or more builds failed"
    return 1
  fi
  
  log ""
  log "Build step completed successfully"
  return 0
}
