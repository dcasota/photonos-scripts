#!/bin/bash
#
# HAB Secure Boot Build System
#
# This script builds all HAB components from source:
# - efitools library and PreLoader
# - HAB PreLoader (customized for VMware GRUB)
#
# Usage: ./build.sh [target]
#   Targets: all, clean, preloader, install, sign
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_ROOT="/root/src"
HAB_KEYS="/root/hab_keys"

# Source directories
EFITOOLS_DIR="$SRC_ROOT/kernel.org/efitools"
SHIM_DIR="$SRC_ROOT/rhboot/shim"
VENTOY_DIR="$SRC_ROOT/ventoy/Ventoy-1.1.10"
HAB_PRELOADER_DIR="$SCRIPT_DIR/preloader"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

check_dependencies() {
    log_info "Checking build dependencies..."
    
    local missing=()
    
    # Check for required tools
    for tool in gcc ld objcopy sbsign; do
        if ! command -v $tool &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    # Check for GNU-EFI
    if [ ! -f /usr/include/efi/efi.h ]; then
        missing+=("gnu-efi-devel")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with: dnf install ${missing[*]}"
        return 1
    fi
    
    log_info "All dependencies satisfied"
    return 0
}

check_sources() {
    log_info "Checking source directories..."
    
    if [ ! -d "$EFITOOLS_DIR" ]; then
        log_error "efitools not found at $EFITOOLS_DIR"
        echo "Run: cd $SRC_ROOT/kernel.org && git clone git://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git"
        return 1
    fi
    
    if [ ! -d "$VENTOY_DIR" ]; then
        log_warn "Ventoy source not found at $VENTOY_DIR"
        echo "Download from: https://github.com/ventoy/Ventoy/archive/refs/tags/v1.1.10.tar.gz"
    fi
    
    log_info "Source directories OK"
    return 0
}

build_efitools_lib() {
    log_info "Building efitools library..."
    
    cd "$EFITOOLS_DIR"
    
    # Create empty hashlist.h if xxdi.pl fails
    if [ ! -f hashlist.h ]; then
        echo 'unsigned char _tmp_tmp_hash[] = {};' > hashlist.h
        echo 'unsigned int _tmp_tmp_hash_len = 0;' >> hashlist.h
    fi
    
    # Build the EFI library
    make lib/lib-efi.a ARCH=x86_64 2>&1 | tail -5
    
    if [ -f lib/lib-efi.a ]; then
        log_info "efitools library built: lib/lib-efi.a"
    else
        log_error "Failed to build efitools library"
        return 1
    fi
}

build_hab_preloader() {
    log_info "Building HAB PreLoader..."
    
    cd "$HAB_PRELOADER_DIR"
    
    make clean 2>/dev/null || true
    make all
    
    if [ -f HabPreLoader-sbat.efi ]; then
        log_info "HAB PreLoader built: HabPreLoader-sbat.efi"
        ls -la HabPreLoader-sbat.efi
    else
        log_error "Failed to build HAB PreLoader"
        return 1
    fi
}

install_preloader() {
    log_info "Installing HAB PreLoader..."
    
    mkdir -p "$HAB_KEYS"
    
    cd "$HAB_PRELOADER_DIR"
    
    if [ -f HabPreLoader-sbat.efi ]; then
        cp HabPreLoader-sbat.efi "$HAB_KEYS/hab-preloader.efi"
        log_info "Installed: $HAB_KEYS/hab-preloader.efi"
    else
        log_error "HabPreLoader-sbat.efi not found - run build first"
        return 1
    fi
}

sign_preloader() {
    log_info "Signing HAB PreLoader with MOK..."
    
    if [ ! -f "$HAB_KEYS/MOK.key" ] || [ ! -f "$HAB_KEYS/MOK.crt" ]; then
        log_error "MOK key not found. Generate with HABv4-installer.sh first."
        return 1
    fi
    
    cd "$HAB_PRELOADER_DIR"
    make sign
    
    if [ -f "$HAB_KEYS/hab-preloader-signed.efi" ]; then
        log_info "Signed PreLoader: $HAB_KEYS/hab-preloader-signed.efi"
        sbverify --list "$HAB_KEYS/hab-preloader-signed.efi" 2>&1 | head -5
    fi
}

copy_ventoy_binaries() {
    log_info "Copying Ventoy pre-built binaries..."
    
    if [ ! -d "$VENTOY_DIR" ]; then
        log_warn "Ventoy source not available"
        return 1
    fi
    
    mkdir -p "$HAB_KEYS"
    
    # Copy shim (SUSE signed, SBAT compliant)
    if [ -f "$VENTOY_DIR/INSTALL/EFI/BOOT/BOOTX64.EFI" ]; then
        cp "$VENTOY_DIR/INSTALL/EFI/BOOT/BOOTX64.EFI" "$HAB_KEYS/shim-suse.efi"
        log_info "Copied: shim-suse.efi"
    fi
    
    # Copy MokManager
    if [ -f "$VENTOY_DIR/INSTALL/EFI/BOOT/MokManager.efi" ]; then
        cp "$VENTOY_DIR/INSTALL/EFI/BOOT/MokManager.efi" "$HAB_KEYS/MokManager-suse.efi"
        log_info "Copied: MokManager-suse.efi"
    fi
    
    # Copy Ventoy's grubx64_real.efi (patched GRUB that doesn't need shim_lock)
    if [ -f "$VENTOY_DIR/INSTALL/EFI/BOOT/grubx64_real.efi" ]; then
        cp "$VENTOY_DIR/INSTALL/EFI/BOOT/grubx64_real.efi" "$HAB_KEYS/ventoy-grub-real.efi"
        log_info "Copied: ventoy-grub-real.efi"
    fi
    
    # Copy Ventoy's PreLoader for reference
    if [ -f "$VENTOY_DIR/INSTALL/EFI/BOOT/grub.efi" ]; then
        cp "$VENTOY_DIR/INSTALL/EFI/BOOT/grub.efi" "$HAB_KEYS/ventoy-preloader.efi"
        log_info "Copied: ventoy-preloader.efi"
    fi
}

clean_all() {
    log_info "Cleaning build artifacts..."
    
    cd "$HAB_PRELOADER_DIR" && make clean 2>/dev/null || true
    cd "$EFITOOLS_DIR" && make clean 2>/dev/null || true
    
    log_info "Clean complete"
}

show_help() {
    cat << EOF
HAB Secure Boot Build System

Usage: $0 [target]

Targets:
  all           Build everything (default)
  clean         Clean all build artifacts
  deps          Check build dependencies
  efitools      Build efitools library only
  preloader     Build HAB PreLoader only
  install       Install PreLoader to hab_keys
  sign          Sign PreLoader with MOK
  ventoy        Copy Ventoy pre-built binaries
  help          Show this help

Examples:
  $0              # Build everything
  $0 preloader    # Build HAB PreLoader only
  $0 sign         # Sign with MOK after building

Source Locations:
  efitools: $EFITOOLS_DIR
  Ventoy:   $VENTOY_DIR
  HAB:      $HAB_PRELOADER_DIR

Output:
  $HAB_KEYS/hab-preloader.efi        (unsigned)
  $HAB_KEYS/hab-preloader-signed.efi (signed with MOK)
EOF
}

# Main
case "${1:-all}" in
    all)
        check_dependencies
        check_sources
        build_efitools_lib
        build_hab_preloader
        install_preloader
        ;;
    clean)
        clean_all
        ;;
    deps)
        check_dependencies
        ;;
    efitools)
        build_efitools_lib
        ;;
    preloader)
        build_hab_preloader
        ;;
    install)
        install_preloader
        ;;
    sign)
        sign_preloader
        ;;
    ventoy)
        copy_ventoy_binaries
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        log_error "Unknown target: $1"
        show_help
        exit 1
        ;;
esac
