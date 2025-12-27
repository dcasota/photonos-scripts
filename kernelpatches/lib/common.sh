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
