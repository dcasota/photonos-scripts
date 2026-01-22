#!/bin/bash
#
# HABv4 Secure Boot Installer
#
# Complete installer for HABv4 Secure Boot simulation environment.
# Wraps C-based tools (HAB PreLoader, ISO builder) with full workflow support.
#
# Usage:
#   ./HABv4-installer.sh [OPTIONS]
#
# Options:
#   --release=VERSION        Photon OS release: 4.0, 5.0, 6.0 (default: 5.0)
#   --build-iso              Build/fix Photon OS ISO for Secure Boot
#   --full-kernel-build      Build kernel from source (takes hours)
#   --efuse-usb              Enable eFuse USB dongle verification
#   --create-efuse-usb=DEV   Create eFuse USB dongle on device (e.g., /dev/sdb)
#   --mok-days=DAYS          MOK certificate validity days (default: 3650, max: 3650)
#   --skip-build             Skip building HAB PreLoader (use existing)
#   --use-ventoy-preloader   Use Ventoy's PreLoader instead of HAB PreLoader
#   clean                    Clean up all build artifacts
#   --help, -h               Show this help message
#
# Examples:
#   ./HABv4-installer.sh                           # Setup keys and components
#   ./HABv4-installer.sh --build-iso               # Build Secure Boot ISO
#   ./HABv4-installer.sh --release=4.0 --build-iso # Build for Photon 4.0
#   ./HABv4-installer.sh --create-efuse-usb=/dev/sdb  # Create eFuse USB
#   ./HABv4-installer.sh clean                     # Cleanup everything
#

set -e

# ============================================================================
# Configuration
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src/hab"

# Default values
PHOTON_RELEASE="5.0"
BUILD_ISO=0
FULL_KERNEL_BUILD=0
EFUSE_USB_MODE=0
EFUSE_USB_DEVICE=""
MOK_VALIDITY_DAYS=3650
SKIP_BUILD=0
USE_VENTOY_PRELOADER=0

# Directories
PHOTON_DIR="$HOME/$PHOTON_RELEASE"
BUILD_DIR="$HOME/hab_build"
KEYS_DIR="$HOME/hab_keys"
EFUSE_DIR="$HOME/efuse_sim"
EFITOOLS_DIR="${EFITOOLS_DIR:-/root/src/kernel.org/efitools}"

# External sources
VENTOY_VERSION="1.1.10"
VENTOY_URL="https://github.com/ventoy/Ventoy/releases/download/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz"
EFITOOLS_REPO="git://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# Utility Functions
# ============================================================================

log_info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step()  { echo -e "${BLUE}[STEP]${NC} $1"; }

show_help() {
    head -32 "$0" | tail -30 | sed 's/^# //' | sed 's/^#//'
    exit 0
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_args() {
    for arg in "$@"; do
        case $arg in
            --release=*)
                PHOTON_RELEASE="${arg#*=}"
                PHOTON_DIR="$HOME/$PHOTON_RELEASE"
                ;;
            --build-iso)
                BUILD_ISO=1
                ;;
            --full-kernel-build)
                FULL_KERNEL_BUILD=1
                ;;
            --efuse-usb)
                EFUSE_USB_MODE=1
                ;;
            --create-efuse-usb=*)
                EFUSE_USB_DEVICE="${arg#*=}"
                ;;
            --mok-days=*)
                MOK_VALIDITY_DAYS="${arg#*=}"
                if ! [[ "$MOK_VALIDITY_DAYS" =~ ^[0-9]+$ ]] || \
                   [[ "$MOK_VALIDITY_DAYS" -lt 1 ]] || \
                   [[ "$MOK_VALIDITY_DAYS" -gt 3650 ]]; then
                    log_error "--mok-days must be between 1 and 3650"
                    exit 1
                fi
                ;;
            --skip-build)
                SKIP_BUILD=1
                ;;
            --use-ventoy-preloader)
                USE_VENTOY_PRELOADER=1
                ;;
            clean)
                do_cleanup
                exit 0
                ;;
            --help|-h)
                show_help
                ;;
            *)
                log_error "Unknown option: $arg"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Dependency Management
# ============================================================================

install_dependencies() {
    log_step "Installing dependencies..."
    
    tdnf install -y \
        git make gcc binutils \
        openssl-devel \
        gnu-efi-devel \
        sbsigntools \
        xorriso \
        syslinux \
        dosfstools \
        wget curl tar \
        rpm cpio \
        2>/dev/null || true
    
    log_info "Dependencies installed"
}

check_dependencies() {
    log_step "Checking dependencies..."
    
    local missing=()
    for cmd in gcc make git wget xorriso sbsign objcopy; do
        command -v $cmd &>/dev/null || missing+=("$cmd")
    done
    
    if [[ ! -f /usr/include/efi/efi.h ]]; then
        missing+=("gnu-efi-devel")
    fi
    
    if [[ ${#missing[@]} -ne 0 ]]; then
        log_warn "Missing: ${missing[*]}"
        install_dependencies
    else
        log_info "All dependencies satisfied"
    fi
}

# ============================================================================
# Source Code Management
# ============================================================================

setup_efitools() {
    log_step "Setting up efitools source..."
    
    if [[ -d "$EFITOOLS_DIR" ]]; then
        log_info "efitools already exists at $EFITOOLS_DIR"
        return 0
    fi
    
    log_info "Cloning efitools from kernel.org..."
    mkdir -p "$(dirname "$EFITOOLS_DIR")"
    git clone "$EFITOOLS_REPO" "$EFITOOLS_DIR" || {
        log_error "Failed to clone efitools"
        return 1
    }
    
    log_info "efitools cloned to $EFITOOLS_DIR"
}

# ============================================================================
# Key Management
# ============================================================================

generate_keys() {
    log_step "Generating cryptographic keys..."
    
    mkdir -p "$KEYS_DIR"
    cd "$KEYS_DIR"
    
    # Platform Key (PK)
    if [[ ! -f "PK.key" ]]; then
        openssl req -new -x509 -newkey rsa:2048 -nodes \
            -keyout PK.key -out PK.crt -days 3650 \
            -subj "/CN=HABv4 Platform Key/O=HABv4/C=US" 2>/dev/null
        openssl x509 -in PK.crt -outform DER -out PK.der
        log_info "Generated Platform Key (PK)"
    fi
    
    # Key Exchange Key (KEK)
    if [[ ! -f "KEK.key" ]]; then
        openssl req -new -x509 -newkey rsa:2048 -nodes \
            -keyout KEK.key -out KEK.crt -days 3650 \
            -subj "/CN=HABv4 Key Exchange Key/O=HABv4/C=US" 2>/dev/null
        openssl x509 -in KEK.crt -outform DER -out KEK.der
        log_info "Generated Key Exchange Key (KEK)"
    fi
    
    # Database Key (DB)
    if [[ ! -f "DB.key" ]]; then
        openssl req -new -x509 -newkey rsa:2048 -nodes \
            -keyout DB.key -out DB.crt -days 3650 \
            -subj "/CN=HABv4 Signature Database Key/O=HABv4/C=US" 2>/dev/null
        openssl x509 -in DB.crt -outform DER -out DB.der
        log_info "Generated Database Key (DB)"
    fi
    
    # Machine Owner Key (MOK) - with Code Signing extensions
    if [[ ! -f "MOK.key" ]]; then
        cat > /tmp/mok.cnf << 'EOCONFIG'
[ req ]
default_bits = 2048
distinguished_name = req_dn
prompt = no
x509_extensions = v3_ext

[ req_dn ]
CN = HABv4 Secure Boot MOK
O = HABv4
C = US

[ v3_ext ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
EOCONFIG
        openssl req -new -x509 -newkey rsa:2048 -nodes \
            -keyout MOK.key -out MOK.crt \
            -days "$MOK_VALIDITY_DAYS" -config /tmp/mok.cnf 2>/dev/null
        rm -f /tmp/mok.cnf
        openssl x509 -in MOK.crt -outform DER -out MOK.der
        log_info "Generated MOK (validity: $MOK_VALIDITY_DAYS days)"
    fi
    
    # Super Root Key (SRK) - for HAB simulation
    if [[ ! -f "srk.pem" ]]; then
        openssl genrsa -out srk.pem 4096 2>/dev/null
        openssl rsa -in srk.pem -pubout -out srk_pub.pem 2>/dev/null
        openssl dgst -sha256 -binary srk_pub.pem > srk_hash.bin
        log_info "Generated Super Root Key (SRK)"
    fi
    
    # CSF Key (Command Sequence File)
    if [[ ! -f "csf.pem" ]]; then
        openssl genrsa -out csf.pem 2048 2>/dev/null
        openssl rsa -in csf.pem -pubout -out csf_pub.pem 2>/dev/null
        log_info "Generated CSF Key"
    fi
    
    # IMG Key (Image Signing)
    if [[ ! -f "img.pem" ]]; then
        openssl genrsa -out img.pem 2048 2>/dev/null
        openssl rsa -in img.pem -pubout -out img_pub.pem 2>/dev/null
        log_info "Generated IMG Key"
    fi
    
    # Kernel Module Signing Key
    if [[ ! -f "kernel_module_signing.pem" ]]; then
        openssl req -new -x509 -newkey rsa:4096 -nodes \
            -keyout kernel_module_signing.pem -out kernel_module_signing.pem \
            -days 3650 -subj "/CN=HABv4 Kernel Module Signing/O=HABv4/C=US" 2>/dev/null
        log_info "Generated Kernel Module Signing Key"
    fi
    
    log_info "All keys generated in $KEYS_DIR"
}

# ============================================================================
# eFuse Simulation
# ============================================================================

setup_efuse_simulation() {
    log_step "Setting up eFuse simulation..."
    
    mkdir -p "$EFUSE_DIR"
    
    # Copy SRK hash as fused value
    if [[ -f "$KEYS_DIR/srk_hash.bin" ]]; then
        cp "$KEYS_DIR/srk_hash.bin" "$EFUSE_DIR/srk_fuse.bin"
    fi
    
    # Security configuration (closed mode)
    printf '\x02' > "$EFUSE_DIR/sec_config.bin"
    echo "Closed" > "$EFUSE_DIR/sec_config.txt"
    
    # Create eFuse map
    cat > "$EFUSE_DIR/efuse_map.txt" << 'EOF'
# HABv4 eFuse Simulation Map
# ==========================
# OCOTP_CFG5 (0x460): Security Configuration
#   Bit 1: SEC_CONFIG (0=Open, 1=Closed)
#   Bit 0: SJC_DISABLE
# OCOTP_SRK0-7 (0x580-0x5FC): SRK Hash (256 bits)

SEC_CONFIG=Closed
SJC_DISABLE=0
SRK_LOCK=1
SRK_REVOKE=0x00
EOF
    
    log_info "eFuse simulation created in $EFUSE_DIR"
}

create_efuse_usb() {
    local device="$1"
    
    if [[ -z "$device" ]]; then
        log_error "No device specified for eFuse USB"
        return 1
    fi
    
    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi
    
    log_step "Creating eFuse USB dongle on $device..."
    log_warn "This will ERASE all data on $device!"
    echo -n "Continue? [y/N] "
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && return 1
    
    # Create partition table
    parted -s "$device" mklabel gpt
    parted -s "$device" mkpart primary fat32 1MiB 100%
    
    # Format
    local partition="${device}1"
    [[ "$device" == *nvme* ]] && partition="${device}p1"
    mkfs.vfat -F 32 -n "HABEFUSE" "$partition"
    
    # Mount and copy
    local mount_point=$(mktemp -d)
    mount "$partition" "$mount_point"
    
    mkdir -p "$mount_point/efuse"
    cp "$EFUSE_DIR"/* "$mount_point/efuse/" 2>/dev/null || true
    cp "$KEYS_DIR/srk_hash.bin" "$mount_point/efuse/" 2>/dev/null || true
    
    # Create verification script
    cat > "$mount_point/efuse/verify.sh" << 'EOF'
#!/bin/bash
# eFuse USB Dongle Verification
echo "HABv4 eFuse USB Dongle"
echo "======================"
if [[ -f "srk_fuse.bin" ]]; then
    echo "SRK Hash: $(xxd -p srk_fuse.bin | tr -d '\n')"
fi
if [[ -f "sec_config.txt" ]]; then
    echo "Security Config: $(cat sec_config.txt)"
fi
EOF
    chmod +x "$mount_point/efuse/verify.sh"
    
    sync
    umount "$mount_point"
    rmdir "$mount_point"
    
    log_info "eFuse USB dongle created on $device"
}

# ============================================================================
# Ventoy Components
# ============================================================================

download_ventoy_components() {
    log_step "Downloading Ventoy components..."
    
    if [[ -f "$KEYS_DIR/shim-suse.efi" ]] && [[ -f "$KEYS_DIR/MokManager-suse.efi" ]]; then
        log_info "Ventoy components already exist"
        return 0
    fi
    
    local work_dir=$(mktemp -d)
    cd "$work_dir"
    
    log_info "Downloading Ventoy $VENTOY_VERSION..."
    wget -q --show-progress -O ventoy.tar.gz "$VENTOY_URL" || {
        log_error "Failed to download Ventoy"
        rm -rf "$work_dir"
        return 1
    }
    
    tar -xzf ventoy.tar.gz
    
    local ventoy_dir="ventoy-${VENTOY_VERSION}"
    
    # Extract from disk image
    local disk_img="$ventoy_dir/ventoy/ventoy.disk.img"
    [[ -f "${disk_img}.xz" ]] && xz -dk "${disk_img}.xz"
    
    if [[ -f "$disk_img" ]]; then
        local mount_point="$work_dir/mnt"
        mkdir -p "$mount_point"
        mount -o loop,ro "$disk_img" "$mount_point"
        
        cp "$mount_point/EFI/BOOT/BOOTX64.EFI" "$KEYS_DIR/shim-suse.efi"
        cp "$mount_point/EFI/BOOT/MokManager.efi" "$KEYS_DIR/MokManager-suse.efi"
        cp "$mount_point/EFI/BOOT/grub.efi" "$KEYS_DIR/ventoy-preloader.efi"
        cp "$mount_point/EFI/BOOT/grubx64_real.efi" "$KEYS_DIR/ventoy-grub-real.efi" 2>/dev/null || true
        [[ -f "$mount_point/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" ]] && \
            cp "$mount_point/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" "$KEYS_DIR/ventoy-mok.cer"
        
        umount "$mount_point"
    else
        # Fallback: extract from tool directory
        cp "$ventoy_dir/tool/x86_64/BOOTX64.EFI" "$KEYS_DIR/shim-suse.efi" 2>/dev/null || true
        cp "$ventoy_dir/tool/x86_64/MokManager.efi" "$KEYS_DIR/MokManager-suse.efi" 2>/dev/null || true
    fi
    
    rm -rf "$work_dir"
    
    # Verify
    if [[ -f "$KEYS_DIR/shim-suse.efi" ]]; then
        local sbat
        sbat=$(objcopy -O binary --only-section=.sbat "$KEYS_DIR/shim-suse.efi" /dev/stdout 2>/dev/null | grep '^shim,' | head -1)
        log_info "SUSE shim downloaded (SBAT: $sbat)"
    else
        log_error "Failed to extract SUSE shim"
        return 1
    fi
    
    log_info "Ventoy components downloaded to $KEYS_DIR"
}

# ============================================================================
# HAB PreLoader Build
# ============================================================================

build_hab_preloader() {
    log_step "Building HAB PreLoader..."
    
    if [[ "$SKIP_BUILD" -eq 1 ]] && [[ -f "$KEYS_DIR/hab-preloader-signed.efi" ]]; then
        log_info "Using existing HAB PreLoader (--skip-build)"
        return 0
    fi
    
    # Ensure efitools exists
    setup_efitools
    
    # Check for build script
    if [[ ! -f "$SRC_DIR/build.sh" ]]; then
        log_error "Build script not found: $SRC_DIR/build.sh"
        log_info "Using Ventoy PreLoader as fallback"
        USE_VENTOY_PRELOADER=1
        return 0
    fi
    
    # Build
    cd "$SRC_DIR"
    export EFITOOLS_DIR
    export HAB_KEYS="$KEYS_DIR"
    
    ./build.sh all || {
        log_warn "HAB PreLoader build failed, using Ventoy PreLoader"
        USE_VENTOY_PRELOADER=1
        return 0
    }
    
    ./build.sh sign || {
        log_warn "HAB PreLoader signing failed"
        USE_VENTOY_PRELOADER=1
        return 0
    }
    
    if [[ -f "$KEYS_DIR/hab-preloader-signed.efi" ]]; then
        log_info "HAB PreLoader built and signed"
        log_info "Size: $(stat -c%s "$KEYS_DIR/hab-preloader-signed.efi") bytes"
    else
        log_warn "HAB PreLoader not found, using Ventoy PreLoader"
        USE_VENTOY_PRELOADER=1
    fi
}

# ============================================================================
# ISO Building
# ============================================================================

find_base_iso() {
    local iso_dir="$PHOTON_DIR/stage"
    mkdir -p "$iso_dir"
    
    # Look for existing ISO
    local base_iso
    base_iso=$(find "$iso_dir" -maxdepth 1 -name "photon-*.iso" ! -name "*-secureboot.iso" 2>/dev/null | head -1)
    
    if [[ -n "$base_iso" ]]; then
        echo "$base_iso"
        return 0
    fi
    
    # Try to download
    log_info "No base ISO found, attempting download..."
    local iso_name
    case "$PHOTON_RELEASE" in
        5.0) iso_name="photon-5.0-dde71ec57.x86_64.iso" ;;
        4.0) iso_name="photon-4.0-ca7c9e933.iso" ;;
        6.0) iso_name="photon-6.0-minimal.iso" ;;
        *) iso_name="photon-minimal-${PHOTON_RELEASE}.iso" ;;
    esac
    
    local iso_url="https://packages.vmware.com/photon/${PHOTON_RELEASE}/GA/iso/$iso_name"
    local iso_path="$iso_dir/$iso_name"
    
    wget -q --show-progress -O "$iso_path" "$iso_url" 2>/dev/null || {
        log_error "Failed to download ISO"
        log_info "Please place a Photon OS ISO in $iso_dir/"
        return 1
    }
    
    echo "$iso_path"
}

build_secure_boot_iso() {
    log_step "Building Secure Boot ISO..."
    
    # Find base ISO
    local base_iso
    base_iso=$(find_base_iso) || return 1
    log_info "Base ISO: $base_iso"
    
    # Determine which PreLoader to use
    local preloader_efi
    local mok_cert
    
    if [[ "$USE_VENTOY_PRELOADER" -eq 1 ]] || [[ ! -f "$KEYS_DIR/hab-preloader-signed.efi" ]]; then
        preloader_efi="$KEYS_DIR/ventoy-preloader.efi"
        mok_cert="$KEYS_DIR/ventoy-mok.cer"
        log_info "Using Ventoy PreLoader"
    else
        preloader_efi="$KEYS_DIR/hab-preloader-signed.efi"
        mok_cert="$KEYS_DIR/MOK.der"
        log_info "Using HAB PreLoader"
    fi
    
    # Check C-based ISO builder
    local iso_builder="$SRC_DIR/iso/hab_iso"
    if [[ -x "$iso_builder" ]]; then
        log_info "Using C-based ISO builder"
        local output_iso="${base_iso%.iso}-secureboot.iso"
        "$iso_builder" -v "$base_iso" "$output_iso" || {
            log_error "ISO builder failed"
            return 1
        }
    else
        # Fallback to bash-based ISO building
        log_info "Using bash-based ISO building"
        build_iso_bash "$base_iso" "$preloader_efi" "$mok_cert"
    fi
}

build_iso_bash() {
    local base_iso="$1"
    local preloader_efi="$2"
    local mok_cert="$3"
    
    local work_dir=$(mktemp -d)
    local iso_extract="$work_dir/iso"
    local output_iso="${base_iso%.iso}-secureboot.iso"
    
    # Extract ISO
    log_info "Extracting ISO..."
    mkdir -p "$iso_extract"
    local iso_mount="$work_dir/mnt"
    mkdir -p "$iso_mount"
    mount -o loop,ro "$base_iso" "$iso_mount"
    cp -a "$iso_mount"/* "$iso_extract/"
    umount "$iso_mount"
    
    # Find GRUB
    local grub_real=""
    for loc in "$iso_extract/EFI/BOOT/grubx64.efi" \
               "$iso_extract/EFI/BOOT/grubx64_real.efi" \
               "$KEYS_DIR/ventoy-grub-real.efi"; do
        if [[ -f "$loc" ]]; then
            grub_real="$loc"
            break
        fi
    done
    
    if [[ -z "$grub_real" ]]; then
        log_error "GRUB not found"
        rm -rf "$work_dir"
        return 1
    fi
    
    # Update efiboot.img
    log_info "Updating efiboot.img..."
    local efiboot="$iso_extract/boot/grub2/efiboot.img"
    local new_efiboot="$work_dir/efiboot.img"
    
    dd if=/dev/zero of="$new_efiboot" bs=1M count=16 status=none
    mkfs.vfat -F 12 -n EFIBOOT "$new_efiboot" >/dev/null 2>&1
    
    local efi_mount="$work_dir/efi"
    mkdir -p "$efi_mount"
    mount -o loop "$new_efiboot" "$efi_mount"
    mkdir -p "$efi_mount/EFI/BOOT"
    
    cp "$KEYS_DIR/shim-suse.efi" "$efi_mount/EFI/BOOT/BOOTX64.EFI"
    cp "$preloader_efi" "$efi_mount/EFI/BOOT/grub.efi"
    cp "$grub_real" "$efi_mount/EFI/BOOT/grubx64_real.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$efi_mount/EFI/BOOT/MokManager.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$efi_mount/mmx64.efi"
    cp "$mok_cert" "$efi_mount/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    
    cat > "$efi_mount/EFI/BOOT/grub.cfg" << 'EOF'
search --no-floppy --file --set=root /isolinux/isolinux.cfg
set prefix=($root)/boot/grub2
configfile $prefix/grub.cfg
EOF
    
    sync
    umount "$efi_mount"
    cp "$new_efiboot" "$efiboot"
    
    # Update ISO EFI directory
    log_info "Updating ISO EFI directory..."
    mkdir -p "$iso_extract/EFI/BOOT"
    cp "$KEYS_DIR/shim-suse.efi" "$iso_extract/EFI/BOOT/BOOTX64.EFI"
    cp "$preloader_efi" "$iso_extract/EFI/BOOT/grub.efi"
    cp "$grub_real" "$iso_extract/EFI/BOOT/grubx64_real.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$iso_extract/EFI/BOOT/MokManager.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$iso_extract/mmx64.efi"
    cp "$mok_cert" "$iso_extract/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    
    # Build ISO
    log_info "Building ISO..."
    cd "$iso_extract"
    xorriso -as mkisofs \
        -o "$output_iso" \
        -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub2/efiboot.img \
        -no-emul-boot -isohybrid-gpt-basdat \
        -V "PHOTON_SB_${PHOTON_RELEASE}" \
        . 2>&1 | tail -5
    
    rm -rf "$work_dir"
    
    if [[ -f "$output_iso" ]]; then
        echo ""
        log_info "========================================="
        log_info "Secure Boot ISO Created!"
        log_info "========================================="
        log_info "ISO: $output_iso"
        log_info "Size: $(du -h "$output_iso" | cut -f1)"
        echo ""
        echo "Boot Chain:"
        echo "  UEFI -> BOOTX64.EFI (SUSE shim)"
        echo "       -> grub.efi (PreLoader)"
        echo "       -> grubx64_real.efi (GRUB)"
        echo "       -> Linux kernel"
        echo ""
        echo "First Boot:"
        echo "  1. Security Violation -> MokManager"
        echo "  2. Enroll ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
        echo "  3. Reboot"
        log_info "========================================="
    else
        log_error "Failed to create ISO"
        return 1
    fi
}

# ============================================================================
# Kernel Build (Optional)
# ============================================================================

build_kernel() {
    if [[ "$FULL_KERNEL_BUILD" -ne 1 ]]; then
        log_info "Skipping kernel build (use --full-kernel-build)"
        return 0
    fi
    
    log_step "Building Linux kernel..."
    log_warn "This will take several hours!"
    
    mkdir -p "$BUILD_DIR/kernel"
    cd "$BUILD_DIR/kernel"
    
    # Clone kernel source
    if [[ ! -d "linux" ]]; then
        git clone --depth 1 https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
    fi
    
    cd linux
    make defconfig
    
    # Enable Secure Boot options
    ./scripts/config --enable CONFIG_MODULE_SIG
    ./scripts/config --enable CONFIG_MODULE_SIG_ALL
    ./scripts/config --set-str CONFIG_MODULE_SIG_KEY "$KEYS_DIR/kernel_module_signing.pem"
    ./scripts/config --enable CONFIG_EFI_STUB
    ./scripts/config --enable CONFIG_LOCK_DOWN_KERNEL_FORCE_INTEGRITY
    
    make -j$(nproc) || {
        log_error "Kernel build failed"
        return 1
    }
    
    log_info "Kernel built successfully"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    log_step "Verifying installation..."
    
    local errors=0
    
    # Check keys
    for key in MOK.key MOK.crt MOK.der srk.pem; do
        if [[ -f "$KEYS_DIR/$key" ]]; then
            echo -e "  ${GREEN}[OK]${NC} $key"
        else
            echo -e "  ${RED}[--]${NC} $key missing"
            ((errors++))
        fi
    done
    
    # Check Ventoy components
    for comp in shim-suse.efi MokManager-suse.efi; do
        if [[ -f "$KEYS_DIR/$comp" ]]; then
            echo -e "  ${GREEN}[OK]${NC} $comp"
        else
            echo -e "  ${RED}[--]${NC} $comp missing"
            ((errors++))
        fi
    done
    
    # Check PreLoader
    if [[ -f "$KEYS_DIR/hab-preloader-signed.efi" ]]; then
        echo -e "  ${GREEN}[OK]${NC} HAB PreLoader (signed)"
    elif [[ -f "$KEYS_DIR/ventoy-preloader.efi" ]]; then
        echo -e "  ${YELLOW}[OK]${NC} Ventoy PreLoader (fallback)"
    else
        echo -e "  ${RED}[--]${NC} No PreLoader found"
        ((errors++))
    fi
    
    # Check eFuse simulation
    if [[ -f "$EFUSE_DIR/srk_fuse.bin" ]]; then
        echo -e "  ${GREEN}[OK]${NC} eFuse simulation"
    else
        echo -e "  ${YELLOW}[--]${NC} eFuse simulation missing"
    fi
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        log_info "All verifications passed"
    else
        log_warn "$errors verification(s) failed"
    fi
    
    return $errors
}

# ============================================================================
# Cleanup
# ============================================================================

do_cleanup() {
    log_step "Cleaning up..."
    
    rm -rf "$BUILD_DIR"
    rm -rf "$KEYS_DIR"
    rm -rf "$EFUSE_DIR"
    rm -rf "$PHOTON_DIR/stage"/*-secureboot.iso
    
    # Clean build artifacts in src
    if [[ -f "$SRC_DIR/build.sh" ]]; then
        cd "$SRC_DIR"
        ./build.sh clean 2>/dev/null || true
    fi
    
    log_info "Cleanup complete"
}

# ============================================================================
# Main
# ============================================================================

main() {
    check_root
    parse_args "$@"
    
    echo ""
    echo "========================================="
    echo "HABv4 Secure Boot Installer"
    echo "========================================="
    echo "Photon OS Release: $PHOTON_RELEASE"
    echo "Build Directory:   $PHOTON_DIR"
    echo "Keys Directory:    $KEYS_DIR"
    echo "eFuse Directory:   $EFUSE_DIR"
    [[ "$BUILD_ISO" -eq 1 ]] && echo "Build ISO:         YES"
    [[ "$EFUSE_USB_MODE" -eq 1 ]] && echo "eFuse USB Mode:    ENABLED"
    [[ "$FULL_KERNEL_BUILD" -eq 1 ]] && echo "Kernel Build:      ENABLED"
    echo "========================================="
    echo ""
    
    # Handle eFuse USB creation separately
    if [[ -n "$EFUSE_USB_DEVICE" ]]; then
        generate_keys
        setup_efuse_simulation
        create_efuse_usb "$EFUSE_USB_DEVICE"
        exit $?
    fi
    
    # Main workflow
    check_dependencies
    generate_keys
    setup_efuse_simulation
    download_ventoy_components
    
    if [[ "$USE_VENTOY_PRELOADER" -ne 1 ]]; then
        build_hab_preloader
    fi
    
    if [[ "$FULL_KERNEL_BUILD" -eq 1 ]]; then
        build_kernel
    fi
    
    verify_installation
    
    if [[ "$BUILD_ISO" -eq 1 ]]; then
        build_secure_boot_iso
    fi
    
    echo ""
    log_info "========================================="
    log_info "Installation Complete!"
    log_info "========================================="
    echo "Keys:     $KEYS_DIR"
    echo "eFuse:    $EFUSE_DIR"
    echo ""
    echo "Next steps:"
    echo "  - Build ISO:      $0 --build-iso"
    echo "  - Create USB:     $0 --create-efuse-usb=/dev/sdX"
    echo "  - Cleanup:        $0 clean"
    log_info "========================================="
}

main "$@"
