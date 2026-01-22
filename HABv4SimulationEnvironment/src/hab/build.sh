#!/bin/bash
#
# HAB Secure Boot Build System
#
# Builds HAB PreLoader using the efitools library.
#
# Prerequisites:
#   - gnu-efi-devel package installed
#   - efitools source cloned to $EFITOOLS_DIR
#   - Ventoy binaries in $HAB_KEYS (shim-suse.efi, MokManager-suse.efi)
#   - MOK key pair in $HAB_KEYS (MOK.key, MOK.crt, MOK.der)
#
# Usage: ./build.sh [target]
#   Targets: all, clean, efitools, preloader, install, sign, info, help
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configurable paths (override with environment variables)
EFITOOLS_DIR="${EFITOOLS_DIR:-/root/src/kernel.org/efitools}"
HAB_KEYS="${HAB_KEYS:-/root/hab_keys}"

HAB_PRELOADER_DIR="$SCRIPT_DIR/preloader"
HAB_ISO_DIR="$SCRIPT_DIR/iso"

# Colors
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
    
    for tool in gcc ld objcopy sbsign; do
        if ! command -v $tool &>/dev/null; then
            missing+=("$tool")
        fi
    done
    
    if [ ! -f /usr/include/efi/efi.h ]; then
        missing+=("gnu-efi-devel")
    fi
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing dependencies: ${missing[*]}"
        echo "Install with: tdnf install gnu-efi-devel sbsigntools gcc make"
        return 1
    fi
    
    log_info "All dependencies satisfied"
}

check_efitools() {
    if [ ! -d "$EFITOOLS_DIR" ]; then
        log_error "efitools not found at $EFITOOLS_DIR"
        echo ""
        echo "Clone efitools with:"
        echo "  mkdir -p $(dirname $EFITOOLS_DIR)"
        echo "  cd $(dirname $EFITOOLS_DIR)"
        echo "  git clone git://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git"
        return 1
    fi
    log_info "efitools found at $EFITOOLS_DIR"
}

build_efitools_lib() {
    log_info "Building efitools library..."
    
    cd "$EFITOOLS_DIR"
    
    # Create empty hashlist.h if xxdi.pl fails
    if [ ! -f hashlist.h ]; then
        echo 'unsigned char _tmp_tmp_hash[] = {};' > hashlist.h
        echo 'unsigned int _tmp_tmp_hash_len = 0;' >> hashlist.h
    fi
    
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
    
    # Update Makefile with correct efitools path
    sed -i "s|^EFITOOLS_DIR.*=.*|EFITOOLS_DIR = $EFITOOLS_DIR|" Makefile
    
    make clean 2>/dev/null || true
    make all
    
    if [ -f HabPreLoader-sbat.efi ]; then
        log_info "HAB PreLoader built: HabPreLoader-sbat.efi ($(stat -c%s HabPreLoader-sbat.efi) bytes)"
    else
        log_error "Failed to build HAB PreLoader"
        return 1
    fi
}

build_iso_tool() {
    log_info "Building ISO tool..."
    
    cd "$HAB_ISO_DIR"
    make clean 2>/dev/null || true
    make
    
    if [ -f hab_iso ]; then
        log_info "ISO tool built: hab_iso"
    else
        log_error "Failed to build ISO tool"
        return 1
    fi
}

install_preloader() {
    log_info "Installing HAB PreLoader to $HAB_KEYS..."
    
    mkdir -p "$HAB_KEYS"
    
    if [ -f "$HAB_PRELOADER_DIR/HabPreLoader-sbat.efi" ]; then
        cp "$HAB_PRELOADER_DIR/HabPreLoader-sbat.efi" "$HAB_KEYS/hab-preloader.efi"
        log_info "Installed: $HAB_KEYS/hab-preloader.efi"
    else
        log_error "HabPreLoader-sbat.efi not found - run build first"
        return 1
    fi
}

sign_preloader() {
    log_info "Signing HAB PreLoader with MOK..."
    
    if [ ! -f "$HAB_KEYS/MOK.key" ] || [ ! -f "$HAB_KEYS/MOK.crt" ]; then
        log_error "MOK key not found at $HAB_KEYS/MOK.key"
        echo ""
        echo "Generate MOK with:"
        echo "  openssl genrsa -out $HAB_KEYS/MOK.key 2048"
        echo "  openssl req -new -x509 -sha256 -key $HAB_KEYS/MOK.key -out $HAB_KEYS/MOK.crt -days 3650 \\"
        echo "      -subj \"/CN=HABv4 Secure Boot MOK/O=Organization/C=US\""
        echo "  openssl x509 -in $HAB_KEYS/MOK.crt -outform DER -out $HAB_KEYS/MOK.der"
        return 1
    fi
    
    if [ ! -f "$HAB_KEYS/hab-preloader.efi" ]; then
        log_error "hab-preloader.efi not found - run install first"
        return 1
    fi
    
    sbsign --key "$HAB_KEYS/MOK.key" \
           --cert "$HAB_KEYS/MOK.crt" \
           --output "$HAB_KEYS/hab-preloader-signed.efi" \
           "$HAB_KEYS/hab-preloader.efi" 2>&1
    
    if [ -f "$HAB_KEYS/hab-preloader-signed.efi" ]; then
        log_info "Signed: $HAB_KEYS/hab-preloader-signed.efi"
        sbverify --list "$HAB_KEYS/hab-preloader-signed.efi" 2>&1 | head -5
    fi
}

clean_all() {
    log_info "Cleaning build artifacts..."
    
    cd "$HAB_PRELOADER_DIR" && make clean 2>/dev/null || true
    cd "$HAB_ISO_DIR" && make clean 2>/dev/null || true
    
    log_info "Clean complete"
}

show_info() {
    echo "HAB Secure Boot Build Configuration"
    echo "===================================="
    echo "Script directory: $SCRIPT_DIR"
    echo "efitools:         $EFITOOLS_DIR"
    echo "HAB keys:         $HAB_KEYS"
    echo "PreLoader dir:    $HAB_PRELOADER_DIR"
    echo "ISO tool dir:     $HAB_ISO_DIR"
    echo ""
    echo "Environment variables:"
    echo "  EFITOOLS_DIR - Path to efitools source"
    echo "  HAB_KEYS     - Path to keys and output binaries"
}

show_help() {
    cat << EOF
HAB Secure Boot Build System

Usage: $0 [target]

Targets:
  all           Build efitools library + HAB PreLoader + ISO tool (default)
  clean         Clean all build artifacts
  deps          Check build dependencies
  efitools      Build efitools library only
  preloader     Build HAB PreLoader only
  isotool       Build ISO tool only
  install       Install PreLoader to \$HAB_KEYS
  sign          Sign PreLoader with MOK
  info          Show build configuration
  help          Show this help

Environment Variables:
  EFITOOLS_DIR  Path to efitools source (default: /root/src/kernel.org/efitools)
  HAB_KEYS      Path to keys directory (default: /root/hab_keys)

Examples:
  $0                        # Build everything
  $0 preloader              # Build HAB PreLoader only
  EFITOOLS_DIR=/opt/efitools $0 all   # Use custom efitools path
EOF
}

# Main
case "${1:-all}" in
    all)
        check_dependencies
        check_efitools
        build_efitools_lib
        build_hab_preloader
        build_iso_tool
        install_preloader
        ;;
    clean)
        clean_all
        ;;
    deps)
        check_dependencies
        ;;
    efitools)
        check_efitools
        build_efitools_lib
        ;;
    preloader)
        check_efitools
        build_hab_preloader
        ;;
    isotool)
        build_iso_tool
        ;;
    install)
        install_preloader
        ;;
    sign)
        sign_preloader
        ;;
    info)
        show_info
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
