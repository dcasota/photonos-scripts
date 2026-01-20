#!/bin/bash
# HAB Library - Common functions and utilities
# Source this file from other HAB scripts

# Prevent multiple inclusion
[[ -n "$HAB_LIB_LOADED" ]] && return 0
HAB_LIB_LOADED=1

# ============================================================================
# Configuration
# ============================================================================

# Default directories
export HAB_BUILD_DIR="${HAB_BUILD_DIR:-$HOME/hab_build}"
export HAB_KEYS_DIR="${HAB_KEYS_DIR:-$HOME/hab_keys}"
export HAB_EFUSE_DIR="${HAB_EFUSE_DIR:-$HOME/efuse_sim}"

# Shim configuration - SUSE shim from Ventoy (SBAT=shim,4 compliant)
export SHIM_VENDOR="suse"
export SHIM_SBAT_VERSION="shim,4"
export VENTOY_VERSION="1.1.10"
export VENTOY_URL="https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"

# MokManager paths - SUSE shim looks for \MokManager.efi at ROOT
export MOKMANAGER_ROOT_PATH="MokManager.efi"
export MOKMANAGER_FALLBACK_PATH="EFI/BOOT/MokManager.efi"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ============================================================================
# Logging Functions
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $*"
}

log_ok() {
    echo -e "${GREEN}[OK]${NC} $*"
}

# ============================================================================
# Utility Functions
# ============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

check_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        return 1
    fi
    return 0
}

check_file() {
    local file="$1"
    local desc="${2:-file}"
    if [[ ! -f "$file" ]]; then
        log_error "$desc not found: $file"
        return 1
    fi
    return 0
}

ensure_dir() {
    local dir="$1"
    if [[ ! -d "$dir" ]]; then
        mkdir -p "$dir"
        log_info "Created directory: $dir"
    fi
}

# Download file with progress
download_file() {
    local url="$1"
    local dest="$2"
    local desc="${3:-file}"
    
    log_info "Downloading $desc..."
    if wget -q --show-progress -O "$dest" "$url"; then
        log_ok "Downloaded $desc"
        return 0
    else
        log_error "Failed to download $desc from $url"
        return 1
    fi
}

# Get file hash
get_sha256() {
    local file="$1"
    sha256sum "$file" | awk '{print $1}'
}

# Verify file signature with sbverify
verify_signature() {
    local file="$1"
    local signer="${2:-}"
    
    if ! check_command sbverify; then
        log_warn "sbverify not available, skipping signature check"
        return 0
    fi
    
    local sig_info
    sig_info=$(sbverify --list "$file" 2>&1)
    
    if [[ -n "$signer" ]]; then
        if echo "$sig_info" | grep -qi "$signer"; then
            log_ok "Verified $signer signature on $(basename "$file")"
            return 0
        else
            log_error "Expected $signer signature not found on $(basename "$file")"
            return 1
        fi
    else
        if echo "$sig_info" | grep -q "signature"; then
            log_ok "Signature found on $(basename "$file")"
            return 0
        else
            log_warn "No signature found on $(basename "$file")"
            return 1
        fi
    fi
}

# Get SBAT version from EFI binary
get_sbat_version() {
    local file="$1"
    
    if ! check_command objcopy; then
        log_warn "objcopy not available"
        return 1
    fi
    
    local sbat
    sbat=$(objcopy -O binary --only-section=.sbat "$file" /dev/stdout 2>/dev/null | grep "^shim," | head -1)
    echo "$sbat"
}

# Mount ISO or image file
mount_image() {
    local image="$1"
    local mount_point="$2"
    local options="${3:-ro}"
    
    ensure_dir "$mount_point"
    
    if mount -o "loop,$options" "$image" "$mount_point" 2>/dev/null; then
        return 0
    else
        log_error "Failed to mount $image"
        return 1
    fi
}

# Unmount safely
unmount_image() {
    local mount_point="$1"
    
    if mountpoint -q "$mount_point" 2>/dev/null; then
        umount "$mount_point" 2>/dev/null || umount -l "$mount_point" 2>/dev/null
    fi
}

# Create temporary directory
make_temp_dir() {
    local prefix="${1:-hab}"
    mktemp -d "/tmp/${prefix}.XXXXXX"
}

# Cleanup function for traps
cleanup_temp() {
    local dir="$1"
    if [[ -d "$dir" && "$dir" == /tmp/* ]]; then
        rm -rf "$dir"
    fi
}

# ============================================================================
# EFI/ISO Utility Functions
# ============================================================================

# Create FAT32 image
create_fat_image() {
    local image="$1"
    local size_mb="${2:-16}"
    local label="${3:-EFIBOOT}"
    
    dd if=/dev/zero of="$image" bs=1M count="$size_mb" status=none
    mkfs.vfat -F 32 -n "$label" "$image" >/dev/null 2>&1
    log_ok "Created ${size_mb}MB FAT32 image: $(basename "$image")"
}

# Copy file to FAT image using mtools or mount
copy_to_fat() {
    local image="$1"
    local src="$2"
    local dest="$3"  # Destination path inside image
    
    local mount_point
    mount_point=$(make_temp_dir "fat_mount")
    
    if mount -o loop "$image" "$mount_point"; then
        local dest_dir
        dest_dir=$(dirname "$mount_point/$dest")
        mkdir -p "$dest_dir"
        cp "$src" "$mount_point/$dest"
        sync
        umount "$mount_point"
        rmdir "$mount_point"
        return 0
    else
        rmdir "$mount_point" 2>/dev/null
        log_error "Failed to mount FAT image"
        return 1
    fi
}

# ============================================================================
# Package Management
# ============================================================================

install_packages() {
    local packages=("$@")
    
    if command -v tdnf &>/dev/null; then
        tdnf install -y "${packages[@]}" 2>/dev/null || true
    elif command -v dnf &>/dev/null; then
        dnf install -y "${packages[@]}" 2>/dev/null || true
    elif command -v apt-get &>/dev/null; then
        apt-get update -qq
        apt-get install -y "${packages[@]}" 2>/dev/null || true
    elif command -v yum &>/dev/null; then
        yum install -y "${packages[@]}" 2>/dev/null || true
    else
        log_warn "No supported package manager found"
        return 1
    fi
}

# ============================================================================
# Export functions for use by other scripts
# ============================================================================

export -f log_info log_warn log_error log_step log_ok
export -f check_root check_command check_file ensure_dir
export -f download_file get_sha256 verify_signature get_sbat_version
export -f mount_image unmount_image make_temp_dir cleanup_temp
export -f create_fat_image copy_to_fat install_packages
