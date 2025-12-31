#!/bin/bash
# =============================================================================
# Common Library Functions for Kernel Backport Solution
# =============================================================================
# Shared functions for logging, network checks, patch routing, and utilities
# Source this file: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"
# =============================================================================

# Prevent multiple sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# -----------------------------------------------------------------------------
# Configuration Defaults
# -----------------------------------------------------------------------------
SUPPORTED_KERNELS=("5.10" "6.1" "6.12")
NETWORK_TIMEOUT="${NETWORK_TIMEOUT:-30}"
NETWORK_RETRIES="${NETWORK_RETRIES:-3}"
LOG_DIR="${LOG_DIR:-/var/log/kernel-backport}"

# kernel.org CNA sourceIdentifier UUID for NVD filtering
KERNEL_ORG_CNA="416baaa9-dc9f-4396-8d5f-8c081fb06d67"

# CVE patch range in spec files
CVE_PATCH_MIN=100
CVE_PATCH_MAX=499

# -----------------------------------------------------------------------------
# Kernel Version Mappings
# -----------------------------------------------------------------------------
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
    6.1)  echo "SPECS/linux" ;;
    6.12) echo "SPECS/linux/v6.12" ;;
    *)    echo "" ;;
  esac
}

get_spec_files_for_kernel() {
  local kver="$1"
  case "$kver" in
    5.10) echo "linux.spec linux-esx.spec linux-rt.spec" ;;
    6.1)  echo "linux.spec linux-esx.spec linux-rt.spec" ;;
    6.12) echo "linux.spec linux-esx.spec" ;;
    *)    echo "" ;;
  esac
}

get_kernel_org_url() {
  local kver="$1"
  local major="${kver%%.*}"
  echo "https://cdn.kernel.org/pub/linux/kernel/v${major}.x/"
}

get_kernel_stable_pattern() {
  local kver="$1"
  echo "${kver}."
}

# -----------------------------------------------------------------------------
# Logging Functions
# -----------------------------------------------------------------------------
setup_logging() {
  local prefix="${1:-backport}"
  local kernel_ver="${2:-}"
  
  mkdir -p "$LOG_DIR" 2>/dev/null || LOG_DIR="/tmp"
  
  if [ -n "$kernel_ver" ]; then
    LOG_FILE="$LOG_DIR/${prefix}_${kernel_ver}_$(date +%Y%m%d_%H%M%S).log"
  else
    LOG_FILE="$LOG_DIR/${prefix}_$(date +%Y%m%d_%H%M%S).log"
  fi
  
  export LOG_FILE
}

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $*"
  echo "$msg"
  [ -n "${LOG_FILE:-}" ] && echo "$msg" >> "$LOG_FILE"
}

log_error() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*"
  echo "$msg" >&2
  [ -n "${LOG_FILE:-}" ] && echo "$msg" >> "$LOG_FILE"
}

log_warn() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*"
  echo "$msg" >&2
  [ -n "${LOG_FILE:-}" ] && echo "$msg" >> "$LOG_FILE"
}

log_debug() {
  if [ "${DEBUG:-false}" = "true" ]; then
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [DEBUG] $*"
    echo "$msg"
    [ -n "${LOG_FILE:-}" ] && echo "$msg" >> "$LOG_FILE"
  fi
}

# -----------------------------------------------------------------------------
# Network Functions
# -----------------------------------------------------------------------------
check_network() {
  local hosts=("github.com" "cdn.kernel.org" "nvd.nist.gov")
  local attempt=1
  
  log "Checking network connectivity..."
  
  while [ $attempt -le $NETWORK_RETRIES ]; do
    for host in "${hosts[@]}"; do
      if timeout "$NETWORK_TIMEOUT" ping -c 1 "$host" >/dev/null 2>&1; then
        log "Network OK: $host reachable (ping)"
        return 0
      fi
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

# -----------------------------------------------------------------------------
# Patch Routing Functions
# -----------------------------------------------------------------------------
get_patch_targets() {
  local SHA="$1"
  local PATCH_FILE="$2"
  local SKILLS_FILE="${3:-}"
  
  # Check skills file first
  if [ -n "$SKILLS_FILE" ] && [ -f "$SKILLS_FILE" ]; then
    local ROUTING=$(grep -E "^${SHA:0:12}" "$SKILLS_FILE" 2>/dev/null | head -1 | cut -d'|' -f2)
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
    
    if [ -n "$HAS_GPU" ]; then
      echo "base"
      return
    fi
    if [ -n "$HAS_KVM" ] || [ -n "$HAS_VIRT" ]; then
      echo "base,esx"
      return
    fi
    if [ -n "$HAS_RT" ]; then
      echo "base,rt"
      return
    fi
  fi
  
  echo "all"
}

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
# Spec File Functions
# -----------------------------------------------------------------------------
add_patch_to_spec() {
  local SPEC_PATH=$1
  local PATCH_NAME=$2
  local PATCH_NUM=$3
  
  # Find the last Patch line and add after it
  local LAST_PATCH=$(grep -n '^Patch[0-9]*:' "$SPEC_PATH" | tail -1 | cut -d: -f1)
  
  if [ -n "$LAST_PATCH" ]; then
    sed -i "${LAST_PATCH}a Patch${PATCH_NUM}: ${PATCH_NAME}" "$SPEC_PATH"
  else
    log_warn "No existing Patch lines found in $SPEC_PATH"
    return 1
  fi
  
  # Find %patch section and add application
  local LAST_APPLY=$(grep -n '^%patch[0-9]* -p1' "$SPEC_PATH" | tail -1 | cut -d: -f1)
  if [ -n "$LAST_APPLY" ]; then
    sed -i "${LAST_APPLY}a %patch${PATCH_NUM} -p1" "$SPEC_PATH"
  fi
  
  return 0
}

get_next_patch_number() {
  local SPEC_PATH=$1
  local MIN=${2:-$CVE_PATCH_MIN}
  local MAX=${3:-$CVE_PATCH_MAX}
  
  local LAST=$(grep -oP "Patch\K([0-9]+)(?=:)" "$SPEC_PATH" 2>/dev/null | \
               awk -v min="$MIN" -v max="$MAX" '$1 >= min && $1 <= max' | \
               sort -n | tail -1)
  
  if [ -z "$LAST" ]; then
    echo "$MIN"
  elif [ "$LAST" -ge "$MAX" ]; then
    echo "-1"  # Range full
  else
    echo $((LAST + 1))
  fi
}

# -----------------------------------------------------------------------------
# Spec Release and Changelog Functions
# -----------------------------------------------------------------------------

# Get current release number from spec file
get_spec_release() {
  local SPEC_PATH="$1"
  
  if [ ! -f "$SPEC_PATH" ]; then
    echo ""
    return 1
  fi
  
  # Extract release number from "Release: N%{...}" pattern
  grep -E '^Release:' "$SPEC_PATH" | head -1 | \
    sed -E 's/^Release:\s*([0-9]+).*/\1/'
}

# Increment release number in spec file
# Returns the new release number
increment_spec_release() {
  local SPEC_PATH="$1"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  local CURRENT=$(get_spec_release "$SPEC_PATH")
  if [ -z "$CURRENT" ]; then
    log_error "Could not extract Release number from $SPEC_PATH"
    return 1
  fi
  
  local NEW=$((CURRENT + 1))
  
  # Replace the release number, preserving the rest of the line
  sed -i -E "s/^(Release:\s*)${CURRENT}(%.*)/\1${NEW}\2/" "$SPEC_PATH"
  
  if [ $? -eq 0 ]; then
    log "Incremented Release: $CURRENT -> $NEW in $(basename "$SPEC_PATH")"
    echo "$NEW"
    return 0
  else
    log_error "Failed to increment Release in $SPEC_PATH"
    return 1
  fi
}

# Add changelog entry to spec file
# Format: * <Day> <Mon> <DD> <YYYY> <Author> <Version>-<Release>
#         - <Message>
add_changelog_entry() {
  local SPEC_PATH="$1"
  local VERSION="$2"
  local RELEASE="$3"
  local MESSAGE="$4"
  local AUTHOR="${5:-Kernel Backport Script <kernel-backport@photon.local>}"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  # Format date as: Day Mon DD YYYY (e.g., "Mon Dec 30 2024")
  local DATE_STR=$(date '+%a %b %d %Y')
  
  # Find %changelog line number
  local CHANGELOG_LINE=$(grep -n '^%changelog' "$SPEC_PATH" | head -1 | cut -d: -f1)
  
  if [ -z "$CHANGELOG_LINE" ]; then
    log_error "No %changelog section found in $SPEC_PATH"
    return 1
  fi
  
  # Create temporary file with changelog entry inserted
  local TMP_FILE=$(mktemp)
  
  # Copy lines up to and including %changelog, then insert entry, then rest of file
  head -n "$CHANGELOG_LINE" "$SPEC_PATH" > "$TMP_FILE"
  echo "* ${DATE_STR} ${AUTHOR} ${VERSION}-${RELEASE}" >> "$TMP_FILE"
  echo "- ${MESSAGE}" >> "$TMP_FILE"
  tail -n +$((CHANGELOG_LINE + 1)) "$SPEC_PATH" >> "$TMP_FILE"
  
  # Replace original file
  mv "$TMP_FILE" "$SPEC_PATH"
  
  if [ $? -eq 0 ]; then
    log "Added changelog entry to $(basename "$SPEC_PATH")"
    return 0
  else
    log_error "Failed to add changelog entry to $SPEC_PATH"
    return 1
  fi
}

# Get version from spec file
get_spec_version() {
  local SPEC_PATH="$1"
  
  if [ ! -f "$SPEC_PATH" ]; then
    echo ""
    return 1
  fi
  
  grep -E '^Version:' "$SPEC_PATH" | head -1 | \
    sed -E 's/^Version:\s*([0-9.]+).*/\1/'
}

# Update version in spec file
update_spec_version() {
  local SPEC_PATH="$1"
  local NEW_VERSION="$2"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  local OLD_VERSION=$(get_spec_version "$SPEC_PATH")
  if [ -z "$OLD_VERSION" ]; then
    log_error "Could not extract current version from $SPEC_PATH"
    return 1
  fi
  
  # Replace version line
  sed -i -E "s/^(Version:\s*)${OLD_VERSION}/\1${NEW_VERSION}/" "$SPEC_PATH"
  
  if [ $? -eq 0 ]; then
    log "Updated Version: $OLD_VERSION -> $NEW_VERSION in $(basename "$SPEC_PATH")"
    return 0
  else
    log_error "Failed to update version in $SPEC_PATH"
    return 1
  fi
}

# Reset release number to 1 (for new kernel version)
reset_spec_release() {
  local SPEC_PATH="$1"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  local CURRENT=$(get_spec_release "$SPEC_PATH")
  if [ -z "$CURRENT" ]; then
    log_error "Could not extract Release number from $SPEC_PATH"
    return 1
  fi
  
  # Replace the release number with 1, preserving the rest of the line
  sed -i -E "s/^(Release:\s*)${CURRENT}(%.*)/\11\2/" "$SPEC_PATH"
  
  if [ $? -eq 0 ]; then
    log "Reset Release: $CURRENT -> 1 in $(basename "$SPEC_PATH")"
    echo "1"
    return 0
  else
    log_error "Failed to reset Release in $SPEC_PATH"
    return 1
  fi
}

# -----------------------------------------------------------------------------
# Validation Functions
# -----------------------------------------------------------------------------
validate_kernel_version() {
  local kver="$1"
  
  for v in "${SUPPORTED_KERNELS[@]}"; do
    if [ "$v" = "$kver" ]; then
      return 0
    fi
  done
  
  return 1
}

# -----------------------------------------------------------------------------
# Version Comparison Functions
# -----------------------------------------------------------------------------

# Compare two kernel versions (e.g., 6.12.60 vs 6.12.63)
# Returns: 0 if v1 < v2, 1 if v1 >= v2
version_less_than() {
  local v1="$1"
  local v2="$2"
  
  # Split versions into components
  local v1_major=$(echo "$v1" | cut -d. -f1)
  local v1_minor=$(echo "$v1" | cut -d. -f2)
  local v1_patch=$(echo "$v1" | cut -d. -f3)
  
  local v2_major=$(echo "$v2" | cut -d. -f1)
  local v2_minor=$(echo "$v2" | cut -d. -f2)
  local v2_patch=$(echo "$v2" | cut -d. -f3)
  
  # Default patch to 0 if not present
  v1_patch=${v1_patch:-0}
  v2_patch=${v2_patch:-0}
  
  # Compare major
  if [ "$v1_major" -lt "$v2_major" ]; then
    return 0
  elif [ "$v1_major" -gt "$v2_major" ]; then
    return 1
  fi
  
  # Compare minor
  if [ "$v1_minor" -lt "$v2_minor" ]; then
    return 0
  elif [ "$v1_minor" -gt "$v2_minor" ]; then
    return 1
  fi
  
  # Compare patch
  if [ "$v1_patch" -lt "$v2_patch" ]; then
    return 0
  else
    return 1
  fi
}

# Get current Photon kernel version from spec file
get_photon_kernel_version() {
  local KERNEL_VERSION="$1"
  local REPO_DIR="$2"
  
  local SPEC_SUBDIR=$(get_spec_dir_for_kernel "$KERNEL_VERSION")
  local SPEC_PATH="$REPO_DIR/$SPEC_SUBDIR/linux.spec"
  
  if [ -f "$SPEC_PATH" ]; then
    get_spec_version "$SPEC_PATH"
  else
    echo ""
  fi
}

# -----------------------------------------------------------------------------
# SHA512 Hash Functions
# -----------------------------------------------------------------------------

# Calculate SHA512 hash of a file
calculate_file_sha512() {
  local FILE_PATH="$1"
  
  if [ ! -f "$FILE_PATH" ]; then
    log_error "File not found: $FILE_PATH"
    return 1
  fi
  
  sha512sum "$FILE_PATH" | awk '{print $1}'
}

# Get current SHA512 hash for a source from spec file
# Arguments:
#   $1 - SPEC_PATH: Path to spec file
#   $2 - SOURCE_NAME: Name identifier in sha512 define (e.g., "linux", "ena_linux")
# Returns: The SHA512 hash string or empty if not found
get_spec_sha512() {
  local SPEC_PATH="$1"
  local SOURCE_NAME="${2:-linux}"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  # Match pattern: %define sha512 <name>=<hash>
  grep -E "^%define sha512\s+${SOURCE_NAME}=" "$SPEC_PATH" | head -1 | \
    sed -E "s/^%define sha512\s+${SOURCE_NAME}=([0-9a-f]+).*/\1/"
}

# Update SHA512 hash for a source in spec file
# Arguments:
#   $1 - SPEC_PATH: Path to spec file
#   $2 - SOURCE_NAME: Name identifier in sha512 define (e.g., "linux", "ena_linux")
#   $3 - NEW_SHA512: The new SHA512 hash value
# Returns: 0 on success, 1 on failure
update_spec_sha512() {
  local SPEC_PATH="$1"
  local SOURCE_NAME="${2:-linux}"
  local NEW_SHA512="$3"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  if [ -z "$NEW_SHA512" ]; then
    log_error "No SHA512 hash provided"
    return 1
  fi
  
  # Validate SHA512 format (128 hex characters)
  if ! echo "$NEW_SHA512" | grep -qE '^[0-9a-f]{128}$'; then
    log_error "Invalid SHA512 hash format: $NEW_SHA512"
    return 1
  fi
  
  local OLD_SHA512=$(get_spec_sha512 "$SPEC_PATH" "$SOURCE_NAME")
  
  if [ -z "$OLD_SHA512" ]; then
    log_error "No existing SHA512 definition found for '$SOURCE_NAME' in $SPEC_PATH"
    return 1
  fi
  
  if [ "$OLD_SHA512" = "$NEW_SHA512" ]; then
    log "SHA512 hash unchanged for $SOURCE_NAME in $(basename "$SPEC_PATH")"
    return 0
  fi
  
  # Update the SHA512 hash
  sed -i -E "s/^(%define sha512\s+${SOURCE_NAME}=)[0-9a-f]+/\1${NEW_SHA512}/" "$SPEC_PATH"
  
  if [ $? -eq 0 ]; then
    log "Updated SHA512 for $SOURCE_NAME in $(basename "$SPEC_PATH")"
    log "  Old: ${OLD_SHA512:0:16}...${OLD_SHA512: -16}"
    log "  New: ${NEW_SHA512:0:16}...${NEW_SHA512: -16}"
    return 0
  else
    log_error "Failed to update SHA512 in $SPEC_PATH"
    return 1
  fi
}

# Update SHA512 hash for kernel tarball after downloading new version
# Arguments:
#   $1 - SPEC_PATH: Path to spec file
#   $2 - TARBALL_PATH: Path to the kernel tarball file
#   $3 - SOURCE_NAME: Name identifier (default: "linux")
# Returns: 0 on success, 1 on failure
update_kernel_tarball_sha512() {
  local SPEC_PATH="$1"
  local TARBALL_PATH="$2"
  local SOURCE_NAME="${3:-linux}"
  
  if [ ! -f "$SPEC_PATH" ]; then
    log_error "Spec file not found: $SPEC_PATH"
    return 1
  fi
  
  if [ ! -f "$TARBALL_PATH" ]; then
    log_error "Tarball not found: $TARBALL_PATH"
    return 1
  fi
  
  log "Calculating SHA512 for $(basename "$TARBALL_PATH")..."
  local NEW_SHA512=$(calculate_file_sha512 "$TARBALL_PATH")
  
  if [ -z "$NEW_SHA512" ]; then
    log_error "Failed to calculate SHA512 for $TARBALL_PATH"
    return 1
  fi
  
  update_spec_sha512 "$SPEC_PATH" "$SOURCE_NAME" "$NEW_SHA512"
}

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------
safe_remove_dir() {
  local dir=$1
  if [ -d "$dir" ]; then
    find "$dir" -name '*.lock' -delete 2>/dev/null
    rm -rf "$dir"
    sleep 1
  fi
}

create_output_dir() {
  local prefix="${1:-backport}"
  local dir="/tmp/${prefix}_$(date +%Y%m%d_%H%M%S)"
  mkdir -p "$dir"
  echo "$dir"
}
