#!/bin/bash

# Enhanced installer script for HABv4-like simulation and Photon OS ISO integration
# Supports both x86_64 and aarch64 hosts.
# Builds HAB components, then integrates into Photon OS ISO build.
# Run as root. Use 'clean' arg for cleanup.
#
# Usage:
#   ./HABv4-installer.sh [OPTIONS]
#
# Options:
#   --release=VERSION        Specify Photon OS release (default: 5.0)
#   --build-iso              Build Photon OS ISO after setup
#   --full-kernel-build      Build kernel from source (takes hours)
#   --efuse-usb              Enable eFuse USB dongle verification in GRUB stub
#   --create-efuse-usb=DEV   Create eFuse USB dongle on device (e.g., /dev/sdb)
#   --help, -h               Show this help message
#   clean                    Clean up all build artifacts

set -e

# ============================================================================
# Script location and module loading
# ============================================================================
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HAB_SCRIPTS_DIR="$SCRIPT_DIR/hab_scripts"

# Source modular scripts if available
if [[ -d "$HAB_SCRIPTS_DIR" ]]; then
    source "$HAB_SCRIPTS_DIR/hab_lib.sh"
    source "$HAB_SCRIPTS_DIR/hab_keys.sh"
    source "$HAB_SCRIPTS_DIR/hab_efuse.sh"
    source "$HAB_SCRIPTS_DIR/hab_shim.sh"
    source "$HAB_SCRIPTS_DIR/hab_iso.sh"
    MODULES_LOADED=1
else
    MODULES_LOADED=0
    echo "Warning: Modular scripts not found in $HAB_SCRIPTS_DIR"
fi

# ============================================================================
# Default values and argument parsing
# ============================================================================
PHOTON_RELEASE="5.0"
BUILD_PHOTON_ISO=0
FULL_KERNEL_BUILD=0
EFUSE_USB_MODE=0
EFUSE_USB_DEVICE=""

for arg in "$@"; do
    case $arg in
        --release=*)
            PHOTON_RELEASE="${arg#*=}"
            ;;
        --build-iso)
            BUILD_PHOTON_ISO=1
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
        clean)
            # Handled at end of script
            ;;
        --help|-h)
            head -20 "$0" | grep -E "^#" | sed 's/^# //' | sed 's/^#//'
            exit 0
            ;;
        *)
            if [[ "$arg" != "clean" ]]; then
                echo "Unknown option: $arg"
                echo "Use --help for usage information."
                exit 1
            fi
            ;;
    esac
done

# ============================================================================
# Global variables
# ============================================================================
HOST_ARCH=$(uname -m)
PHOTON_DIR="$HOME/$PHOTON_RELEASE"

# Validate Photon release
case "$PHOTON_RELEASE" in
    4.0|5.0|6.0) ;;
    *) echo "Warning: Photon OS $PHOTON_RELEASE may not be supported." ;;
esac

# Build directories
BUILD_DIR="$HOME/hab_build"
KEYS_DIR="$HOME/hab_keys"
EFUSE_DIR="$HOME/efuse_sim"

# Export for modules
export HAB_BUILD_DIR="$BUILD_DIR"
export HAB_KEYS_DIR="$KEYS_DIR"
export HAB_EFUSE_DIR="$EFUSE_DIR"

# Toolchain and external URLs
TOOLCHAIN_VERSION="14.3.rel1"
TOOLCHAIN_HOST="$HOST_ARCH"
TOOLCHAIN_URL="https://developer.arm.com/-/media/Files/downloads/gnu/${TOOLCHAIN_VERSION}/binrel/arm-gnu-toolchain-${TOOLCHAIN_VERSION}-${TOOLCHAIN_HOST}-aarch64-none-linux-gnu.tar.xz"
TOOLCHAIN_DIR="$HOME/arm-toolchain"
QEMU_VERSION="10.1.0"
QEMU_URL="https://download.qemu.org/qemu-$QEMU_VERSION.tar.xz"

# Repository URLs
CST_REPO="https://github.com/nxp-qoriq/cst.git"
UBOOT_REPO="https://source.denx.de/u-boot/u-boot.git"
OPTEE_REPO="https://github.com/OP-TEE/optee_os.git"
TFA_REPO="https://github.com/nxp-imx/imx-atf.git"
IMX_MKIMAGE_REPO="https://github.com/nxp-imx/imx-mkimage.git"
LINUX_IMX_REPO="https://github.com/nxp-imx/linux-imx.git"
LINUX_IMX_BRANCH="lf-6.6.y"
LINUX_REPO="https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git"
SGX_SDK_URL="https://download.01.org/intel-sgx/sgx-linux/2.24/sgx_linux_x64_sdk_2.24.100.4.bin"

# ============================================================================
# Root check
# ============================================================================
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

# ============================================================================
# Core Functions (not in modules)
# ============================================================================

check_prerequisites() {
    echo "Checking prerequisites..."
    if [[ "$HOST_ARCH" != "x86_64" && "$HOST_ARCH" != "aarch64" ]]; then
        echo "Error: This script supports x86_64 and aarch64 hosts only."
        exit 1
    fi
    if ! grep -q "Photon" /etc/os-release 2>/dev/null; then
        echo "Warning: This script assumes Photon OS."
    fi
    
    local missing=()
    for cmd in git make gcc wget tar; do
        command -v $cmd &>/dev/null || missing+=($cmd)
    done
    
    if [[ ${#missing[@]} -ne 0 ]]; then
        echo "Missing prerequisites: ${missing[*]}"
    else
        echo "Basic prerequisites satisfied."
    fi
}

install_dependencies() {
    echo "Installing dependencies..."
    tdnf update -y || true
    tdnf install -y git make gcc binutils bc openssl-devel bison flex elfutils-devel \
        ncurses-devel python3-setuptools wget unzip tar gawk build-essential \
        zlib-devel glib-devel pixman-devel device-mapper-devel autoconf automake \
        libtool pkg-config efibootmgr jq curl sbsigntools rpm cpio xorriso \
        grub2 grub2-efi grub2-efi-image shim-signed 2>/dev/null || true
}

install_toolchain() {
    echo "Installing ARM toolchain..."
    if [[ "$HOST_ARCH" == "aarch64" ]]; then
        echo "Native aarch64 host, skipping cross-compiler."
        return
    fi
    
    if [[ -d "$TOOLCHAIN_DIR" ]]; then
        echo "Toolchain already installed."
        return
    fi
    
    mkdir -p "$TOOLCHAIN_DIR"
    cd "$TOOLCHAIN_DIR"
    wget -q --show-progress "$TOOLCHAIN_URL" -O toolchain.tar.xz
    tar -xf toolchain.tar.xz --strip-components=1
    rm toolchain.tar.xz
    echo "Toolchain installed in $TOOLCHAIN_DIR"
}

build_qemu() {
    echo "Setting up QEMU..."
    
    if command -v qemu-system-aarch64 &>/dev/null || command -v qemu-system-x86_64 &>/dev/null; then
        echo "QEMU already available."
        return
    fi
    
    tdnf install -y qemu qemu-system-aarch64 qemu-system-x86_64 2>/dev/null || {
        echo "QEMU package not available, skipping (not required for ISO builds)."
    }
    echo "QEMU setup complete."
}

build_cst() {
    echo "Setting up Code Signing Tool..."
    
    if [[ -f "/opt/cst/linux64/bin/cst" ]]; then
        echo "CST already installed."
        return
    fi
    
    mkdir -p "$BUILD_DIR/cst"
    cd "$BUILD_DIR/cst"
    
    if [[ ! -d "cst" ]]; then
        git clone "$CST_REPO" cst || {
            echo "Creating CST simulator..."
            mkdir -p /opt/cst/linux64/bin /opt/cst/keys
            cat > /usr/local/bin/cst << 'EOF'
#!/bin/bash
echo "CST Simulator - HAB Code Signing"
echo "Input: $1"
echo "Simulating signature..."
if [[ -f "$1" ]]; then
    openssl dgst -sha256 -sign "$HAB_KEYS_DIR/img.pem" -out "${1}.sig" "$1" 2>/dev/null || echo "Signature placeholder"
fi
EOF
            chmod +x /usr/local/bin/cst
        }
    fi
    echo "CST setup complete."
}

# ============================================================================
# Platform-specific build functions (aarch64)
# ============================================================================

build_optee_aarch64() {
    echo "Building OP-TEE for aarch64..."
    
    if [[ "$HOST_ARCH" == "x86_64" ]] && [[ ! -d "$TOOLCHAIN_DIR" ]]; then
        echo "Skipping OP-TEE (no cross-compiler)."
        return
    fi
    
    mkdir -p "$BUILD_DIR/optee"
    cd "$BUILD_DIR/optee"
    
    if [[ ! -d "optee_os" ]]; then
        git clone "$OPTEE_REPO" optee_os
    fi
    
    cd optee_os
    
    if [[ "$HOST_ARCH" == "x86_64" ]]; then
        export CROSS_COMPILE="$TOOLCHAIN_DIR/bin/aarch64-none-linux-gnu-"
    fi
    
    make PLATFORM=imx-mx8mmevk CFG_TEE_CORE_LOG_LEVEL=2 -j$(nproc) || {
        echo "OP-TEE build failed (may need specific platform config)."
    }
}

build_tfa_aarch64() {
    echo "Building Trusted Firmware-A..."
    
    if [[ "$HOST_ARCH" == "x86_64" ]] && [[ ! -d "$TOOLCHAIN_DIR" ]]; then
        echo "Skipping TF-A (no cross-compiler)."
        return
    fi
    
    mkdir -p "$BUILD_DIR/tfa"
    cd "$BUILD_DIR/tfa"
    
    if [[ ! -d "imx-atf" ]]; then
        git clone "$TFA_REPO" imx-atf
    fi
    
    cd imx-atf
    
    if [[ "$HOST_ARCH" == "x86_64" ]]; then
        export CROSS_COMPILE="$TOOLCHAIN_DIR/bin/aarch64-none-linux-gnu-"
    fi
    
    make PLAT=imx8mm bl31 -j$(nproc) || {
        echo "TF-A build failed."
    }
}

enable_tee_x86_64() {
    echo "Checking x86_64 TEE capabilities..."
    
    if [[ "$HOST_ARCH" != "x86_64" ]]; then
        return
    fi
    
    # Check for SGX
    if grep -q sgx /proc/cpuinfo 2>/dev/null; then
        echo "Intel SGX supported."
    else
        echo "Intel SGX not available."
    fi
    
    # Check for SEV
    if [[ -f /sys/module/kvm_amd/parameters/sev ]]; then
        if [[ "$(cat /sys/module/kvm_amd/parameters/sev)" == "Y" ]]; then
            echo "AMD SEV supported."
        fi
    fi
}

build_uboot_aarch64() {
    echo "Building U-Boot for aarch64..."
    
    if [[ "$HOST_ARCH" == "x86_64" ]] && [[ ! -d "$TOOLCHAIN_DIR" ]]; then
        echo "Skipping U-Boot (no cross-compiler)."
        return
    fi
    
    mkdir -p "$BUILD_DIR/uboot"
    cd "$BUILD_DIR/uboot"
    
    if [[ ! -d "u-boot" ]]; then
        git clone "$UBOOT_REPO" u-boot
    fi
    
    cd u-boot
    
    if [[ "$HOST_ARCH" == "x86_64" ]]; then
        export CROSS_COMPILE="$TOOLCHAIN_DIR/bin/aarch64-none-linux-gnu-"
    fi
    
    make imx8mm_evk_defconfig
    make -j$(nproc) || {
        echo "U-Boot build failed."
    }
}

build_grub_x86_64() {
    echo "Setting up GRUB for x86_64..."
    
    if [[ "$HOST_ARCH" != "x86_64" ]]; then
        return
    fi
    
    tdnf install -y grub2 grub2-efi grub2-efi-image 2>/dev/null || true
    
    mkdir -p "$BUILD_DIR/secureboot"
    echo "GRUB setup complete."
}

integrate_tfa_uboot_aarch64() {
    echo "Integrating TF-A with U-Boot..."
    
    if [[ "$HOST_ARCH" == "x86_64" ]]; then
        echo "Skipping ARM integration on x86_64."
        return
    fi
    
    mkdir -p "$BUILD_DIR/integrated"
    # Integration logic for ARM platforms would go here
    echo "Integration complete (placeholder for actual ARM integration)."
}

build_linux_aarch64() {
    echo "Linux aarch64 kernel build..."
    
    if [[ "$FULL_KERNEL_BUILD" -ne 1 ]]; then
        echo "Skipping full kernel build (use --full-kernel-build)."
        return
    fi
    
    # Full kernel build logic here
    echo "Kernel build skipped in this refactored version."
}

build_linux_x86_64() {
    echo "Linux x86_64 kernel build..."
    
    if [[ "$FULL_KERNEL_BUILD" -ne 1 ]]; then
        echo "Skipping full kernel build."
        return
    fi
    
    echo "Kernel build skipped in this refactored version."
}

# ============================================================================
# Cleanup
# ============================================================================

cleanup() {
    echo "Cleaning up build artifacts..."
    rm -rf "$BUILD_DIR"
    rm -rf "$KEYS_DIR"
    rm -rf "$EFUSE_DIR"
    rm -rf "$TOOLCHAIN_DIR"
    rm -rf "$HOME/linux-aarch64" "$HOME/linux-x86_64"
    echo "Cleanup complete."
}

# ============================================================================
# Verification
# ============================================================================

verify_installations() {
    echo ""
    echo "========================================="
    echo "Verifying installations..."
    echo "========================================="
    
    local errors=0
    
    # Check keys
    if [[ -f "$KEYS_DIR/MOK.key" ]]; then
        echo "[OK] MOK key exists"
    else
        echo "[--] MOK key missing"
        ((errors++))
    fi
    
    # Check shim
    if [[ -f "$KEYS_DIR/shim-suse.efi" ]]; then
        local sbat
        sbat=$(objcopy -O binary --only-section=.sbat "$KEYS_DIR/shim-suse.efi" /dev/stdout 2>/dev/null | grep '^shim,' | head -1)
        echo "[OK] SUSE shim exists (SBAT: $sbat)"
    else
        echo "[--] SUSE shim missing"
        ((errors++))
    fi
    
    # Check MokManager
    if [[ -f "$KEYS_DIR/MokManager-suse.efi" ]]; then
        echo "[OK] SUSE MokManager exists"
    else
        echo "[--] SUSE MokManager missing"
        ((errors++))
    fi
    
    # Check eFuse simulation
    if [[ -f "$EFUSE_DIR/srk_fuse.bin" ]]; then
        echo "[OK] eFuse simulation exists"
    else
        echo "[--] eFuse simulation missing"
        ((errors++))
    fi
    
    # Check GRUB stub
    if [[ -f "$KEYS_DIR/grub-photon-stub.efi" ]]; then
        echo "[OK] GRUB stub exists"
    else
        echo "[--] GRUB stub missing (will be built during ISO creation)"
    fi
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        echo "All verifications passed."
    else
        echo "$errors verification(s) failed."
    fi
    
    return $errors
}

# ============================================================================
# Photon OS Integration
# ============================================================================

prepare_photon_env() {
    echo "Preparing Photon OS build environment..."
    
    mkdir -p "$PHOTON_DIR"
    cd "$PHOTON_DIR"
    
    if [[ ! -d "photon" ]]; then
        git clone --depth 1 -b "$PHOTON_RELEASE" https://github.com/vmware/photon.git photon 2>/dev/null || {
            echo "Warning: Could not clone Photon repo"
        }
    fi
    
    mkdir -p stage
    echo "Photon environment ready in $PHOTON_DIR"
}

build_photon_iso() {
    echo ""
    echo "========================================="
    echo "Building Photon OS ISO"
    echo "========================================="
    
    if [[ "$BUILD_PHOTON_ISO" -ne 1 ]]; then
        echo "Skipping ISO build (use --build-iso to enable)."
        return
    fi
    
    cd "$PHOTON_DIR"
    
    # Check for existing ISO
    local existing_iso
    existing_iso=$(find "$PHOTON_DIR/stage" -name "photon-*.iso" ! -name "*-secureboot.iso" 2>/dev/null | head -1)
    
    if [[ -z "$existing_iso" ]]; then
        echo "No base ISO found. Attempting to download..."
        mkdir -p "$PHOTON_DIR/stage"
        
        local iso_name
        case "$PHOTON_RELEASE" in
            5.0) iso_name="photon-5.0-dde71ec57.x86_64.iso" ;;
            4.0) iso_name="photon-4.0-ca7c9e933.iso" ;;
            *) iso_name="photon-minimal-${PHOTON_RELEASE}.iso" ;;
        esac
        
        wget -q --show-progress -O "$PHOTON_DIR/stage/$iso_name" \
            "https://packages.vmware.com/photon/${PHOTON_RELEASE}/GA/iso/$iso_name" 2>/dev/null || {
            echo "Could not download ISO. Please place a Photon ISO in $PHOTON_DIR/stage/"
            return 1
        }
        
        existing_iso="$PHOTON_DIR/stage/$iso_name"
    fi
    
    echo "Using base ISO: $existing_iso"
    
    # Fix ISO for Secure Boot
    fix_iso_secureboot "$existing_iso"
}

# ============================================================================
# Fix ISO for Secure Boot (SUSE shim from Ventoy)
# ============================================================================

fix_iso_secureboot() {
    local iso_path="$1"
    
    echo ""
    echo "========================================="
    echo "Fixing ISO for Secure Boot (Photon OS)"
    echo "========================================="
    echo "Using SUSE shim from Ventoy (SBAT=shim,4) + Photon OS MOK-signed GRUB stub"
    echo ""
    
    if [[ ! -f "$iso_path" ]]; then
        echo "Error: ISO file not found: $iso_path"
        return 1
    fi
    
    # Check required tools
    for cmd in xorriso sbverify openssl grub2-mkstandalone sbsign; do
        if ! command -v $cmd &>/dev/null; then
            echo "Installing $cmd..."
            tdnf install -y $cmd 2>/dev/null || true
        fi
    done
    
    local work_dir=$(mktemp -d)
    local efi_mount="$work_dir/efi_mount"
    local iso_mount="$work_dir/iso_mount"
    local iso_extract="$work_dir/iso_extract"
    
    mkdir -p "$efi_mount" "$iso_mount" "$iso_extract"
    
    # === STEP 1: Get SUSE shim from Ventoy ===
    echo ""
    echo "[Step 1] Getting SUSE shim and MokManager from Ventoy..."
    
    local ventoy_version="1.1.10"
    local ventoy_url="https://github.com/ventoy/Ventoy/releases/download/v${ventoy_version}/ventoy-${ventoy_version}-linux.tar.gz"
    
    if [[ ! -f "$KEYS_DIR/shim-suse.efi" ]] || [[ ! -f "$KEYS_DIR/MokManager-suse.efi" ]]; then
        echo "Downloading SUSE shim from Ventoy ${ventoy_version}..."
        local ventoy_dir="$work_dir/ventoy"
        mkdir -p "$ventoy_dir"
        wget -q --show-progress -O "$ventoy_dir/ventoy.tar.gz" "$ventoy_url" || {
            echo "Error: Failed to download Ventoy"
            rm -rf "$work_dir"
            return 1
        }
        cd "$ventoy_dir"
        tar -xzf ventoy.tar.gz
        
        local disk_img="$ventoy_dir/ventoy-${ventoy_version}/ventoy/ventoy.disk.img"
        [[ -f "${disk_img}.xz" ]] && xz -dk "${disk_img}.xz"
        
        if [[ ! -f "$disk_img" ]]; then
            echo "Error: Ventoy disk image not found"
            rm -rf "$work_dir"
            return 1
        fi
        
        local ventoy_mount="$ventoy_dir/mount"
        mkdir -p "$ventoy_mount"
        mount -o loop,ro "$disk_img" "$ventoy_mount" || {
            echo "Error: Failed to mount Ventoy disk image"
            rm -rf "$work_dir"
            return 1
        }
        
        cp "$ventoy_mount/EFI/BOOT/BOOTX64.EFI" "$KEYS_DIR/shim-suse.efi"
        cp "$ventoy_mount/EFI/BOOT/MokManager.efi" "$KEYS_DIR/MokManager-suse.efi"
        umount "$ventoy_mount"
        
        echo "[OK] SUSE shim and MokManager extracted"
        echo "[OK] SBAT: $(objcopy -O binary --only-section=.sbat "$KEYS_DIR/shim-suse.efi" /dev/stdout 2>/dev/null | grep '^shim,' | head -1)"
    else
        echo "[OK] Using cached SUSE shim from $KEYS_DIR"
    fi
    
    # === Generate MOK if needed ===
    if [[ ! -f "$KEYS_DIR/MOK.key" ]]; then
        echo "Generating Photon OS MOK key pair..."
        openssl req -new -x509 -newkey rsa:2048 \
            -keyout "$KEYS_DIR/MOK.key" -out "$KEYS_DIR/MOK.crt" \
            -nodes -days 3650 -subj "/CN=Photon OS Secure Boot MOK"
        openssl x509 -in "$KEYS_DIR/MOK.crt" -outform DER -out "$KEYS_DIR/MOK.der"
        chmod 400 "$KEYS_DIR/MOK.key"
        echo "[OK] Generated MOK key pair"
    fi
    
    # === Build GRUB stub ===
    local grub_stub_signed
    [[ "$EFUSE_USB_MODE" -eq 1 ]] && grub_stub_signed="$KEYS_DIR/grub-photon-stub-efuse.efi" || grub_stub_signed="$KEYS_DIR/grub-photon-stub.efi"
    
    if [[ ! -f "$grub_stub_signed" ]]; then
        echo "Building Photon OS GRUB stub..."
        local stub_cfg="$work_dir/stub_grub.cfg"
        local grub_stub_unsigned="$work_dir/grub_stub_unsigned.efi"
        
        if [[ "$EFUSE_USB_MODE" -eq 1 ]]; then
            cat > "$stub_cfg" << 'EOFCFG'
set timeout=5
set default=0
search --no-floppy --file --set=efipart /EFI/BOOT/grubx64_real.efi
search --no-floppy --fs-label EFUSE_SIM --set=efuse_usb
set efuse_verified=0
if [ -n "$efuse_usb" ]; then
    if [ -f ($efuse_usb)/efuse_sim/srk_fuse.bin ]; then
        set efuse_verified=1
    fi
fi
if [ "$efuse_verified" = "1" ]; then
    menuentry "Continue to Photon OS Installer" {
        chainloader /EFI/BOOT/grubx64_real.efi
    }
fi
menuentry "MokManager - Enroll/Delete MOK Keys" {
    chainloader /MokManager.efi
}
if [ "$efuse_verified" != "1" ]; then
    menuentry ">> Retry - Search for eFuse USB <<" {
        configfile $prefix/grub.cfg
    }
fi
menuentry "Reboot" { reboot }
menuentry "Shutdown" { halt }
EOFCFG
        else
            cat > "$stub_cfg" << 'EOFCFG'
set timeout=5
set default=0
search --no-floppy --file --set=efipart /EFI/BOOT/grubx64_real.efi
menuentry "Continue to Photon OS Installer" {
    if [ -n "$efipart" ]; then
        chainloader ($efipart)/EFI/BOOT/grubx64_real.efi
    else
        chainloader /EFI/BOOT/grubx64_real.efi
    fi
}
menuentry "MokManager - Enroll/Delete MOK Keys" {
    chainloader /MokManager.efi
}
menuentry "Reboot" { reboot }
menuentry "Shutdown" { halt }
EOFCFG
        fi
        
        grub2-mkstandalone --format=x86_64-efi --output="$grub_stub_unsigned" \
            --modules="chain fat part_gpt part_msdos normal boot configfile echo reboot halt search search_fs_file search_fs_uuid search_label test true" \
            "boot/grub/grub.cfg=$stub_cfg" || {
            echo "Error: Failed to build GRUB stub"
            rm -rf "$work_dir"
            return 1
        }
        
        sbsign --key "$KEYS_DIR/MOK.key" --cert "$KEYS_DIR/MOK.crt" \
            --output "$grub_stub_signed" "$grub_stub_unsigned" || {
            echo "Error: Failed to sign GRUB stub"
            rm -rf "$work_dir"
            return 1
        }
        echo "[OK] Built and signed GRUB stub"
    else
        echo "[OK] Using cached GRUB stub"
    fi
    
    # === STEP 2: Extract ISO ===
    echo ""
    echo "[Step 2] Extracting ISO..."
    mount -o loop,ro "$iso_path" "$iso_mount" || {
        echo "Error: Failed to mount ISO"
        rm -rf "$work_dir"
        return 1
    }
    cp -a "$iso_mount"/* "$iso_extract/"
    umount "$iso_mount"
    echo "[OK] ISO extracted"
    
    # === STEP 3: Get VMware GRUB ===
    echo ""
    echo "[Step 3] Getting VMware-signed GRUB..."
    local grub_real="$work_dir/grubx64_real.efi"
    
    tdnf install --downloadonly --alldeps -y grub2-efi-image 2>/dev/null || true
    local grub_rpm=$(find /var/cache/tdnf -name "grub2-efi-image*.rpm" 2>/dev/null | head -1)
    
    if [[ -n "$grub_rpm" ]]; then
        local rpm_extract="$work_dir/rpm_extract"
        mkdir -p "$rpm_extract"
        cd "$rpm_extract"
        rpm2cpio "$grub_rpm" | cpio -idm 2>/dev/null
        [[ -f "$rpm_extract/boot/efi/EFI/BOOT/grubx64.efi" ]] && cp "$rpm_extract/boot/efi/EFI/BOOT/grubx64.efi" "$grub_real"
    fi
    
    [[ ! -f "$grub_real" ]] && [[ -f "/boot/efi/EFI/BOOT/grubx64.efi" ]] && cp "/boot/efi/EFI/BOOT/grubx64.efi" "$grub_real"
    
    if [[ ! -f "$grub_real" ]]; then
        echo "Error: Could not find GRUB"
        rm -rf "$work_dir"
        return 1
    fi
    echo "[OK] Got VMware GRUB"
    
    # === STEP 4: Update efiboot.img ===
    echo ""
    echo "[Step 4] Updating efiboot.img..."
    local efiboot_img="$iso_extract/boot/grub2/efiboot.img"
    local new_efiboot="$work_dir/efiboot_new.img"
    
    dd if=/dev/zero of="$new_efiboot" bs=1M count=16 status=none
    mkfs.vfat -F 12 -n "EFIBOOT" "$new_efiboot" >/dev/null 2>&1
    
    local old_mount="$work_dir/old_efi"
    local new_mount="$work_dir/new_efi"
    mkdir -p "$old_mount" "$new_mount"
    
    mount -o loop "$efiboot_img" "$old_mount"
    mount -o loop "$new_efiboot" "$new_mount"
    
    cp -a "$old_mount"/* "$new_mount"/ 2>/dev/null || true
    mkdir -p "$new_mount/EFI/BOOT" "$new_mount/grub"
    
    # Install boot chain
    cp "$KEYS_DIR/shim-suse.efi" "$new_mount/EFI/BOOT/BOOTX64.EFI"
    cp "$KEYS_DIR/shim-suse.efi" "$new_mount/EFI/BOOT/bootx64.efi"
    cp "$grub_stub_signed" "$new_mount/EFI/BOOT/grub.efi"
    cp "$grub_stub_signed" "$new_mount/EFI/BOOT/grubx64.efi"
    cp "$grub_real" "$new_mount/EFI/BOOT/grubx64_real.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$new_mount/MokManager.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$new_mount/EFI/BOOT/MokManager.efi"
    cp "$KEYS_DIR/MOK.der" "$new_mount/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    
    # Create grub.cfg
    cat > "$new_mount/grub/grub.cfg" << 'EOFCFG'
search --no-floppy --file --set=root /isolinux/vmlinuz
if [ -n "$root" ]; then
    configfile ($root)/boot/grub2/grub.cfg
fi
EOFCFG
    cp "$new_mount/grub/grub.cfg" "$new_mount/EFI/BOOT/grub.cfg"
    
    sync
    umount "$old_mount"
    umount "$new_mount"
    cp "$new_efiboot" "$efiboot_img"
    echo "[OK] Updated efiboot.img (16MB)"
    
    # === STEP 5: Update ISO EFI directory ===
    echo ""
    echo "[Step 5] Updating ISO EFI directory..."
    mkdir -p "$iso_extract/EFI/BOOT"
    
    cp "$KEYS_DIR/shim-suse.efi" "$iso_extract/EFI/BOOT/BOOTX64.EFI"
    cp "$grub_stub_signed" "$iso_extract/EFI/BOOT/grub.efi"
    cp "$grub_stub_signed" "$iso_extract/EFI/BOOT/grubx64.efi"
    cp "$grub_real" "$iso_extract/EFI/BOOT/grubx64_real.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$iso_extract/MokManager.efi"
    cp "$KEYS_DIR/MokManager-suse.efi" "$iso_extract/EFI/BOOT/MokManager.efi"
    cp "$KEYS_DIR/MOK.der" "$iso_extract/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    cp "$KEYS_DIR/MOK.der" "$iso_extract/EFI/BOOT/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    echo "[OK] Updated ISO EFI directory"
    
    # === STEP 6: Create boot menu ===
    echo ""
    echo "[Step 6] Creating boot menu..."
    cat > "$iso_extract/boot/grub2/grub.cfg" << 'EOFMENU'
set default=0
set timeout=10
probe -s photondisk -u ($root)
menuentry "Install Photon OS (Custom)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=UUID=$photondisk
    initrd /isolinux/initrd.img
}
menuentry "Install Photon OS (VMware original)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=7 photon.media=UUID=$photondisk
    initrd /isolinux/initrd.img
}
menuentry "UEFI Firmware Settings" { fwsetup }
EOFMENU
    echo "[OK] Created boot menu"
    
    # === STEP 7: Rebuild ISO ===
    echo ""
    echo "[Step 7] Rebuilding ISO..."
    local new_iso="${iso_path%.iso}-secureboot.iso"
    
    cd "$iso_extract"
    xorriso -as mkisofs -R -l -D -o "$new_iso" \
        -V "PHOTON_$(echo $PHOTON_RELEASE | tr -d '.')_SB" \
        -c isolinux/boot.cat -b isolinux/isolinux.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot -e boot/grub2/efiboot.img -no-emul-boot \
        -isohybrid-mbr /usr/share/syslinux/isohdpfx.bin \
        -isohybrid-gpt-basdat "$iso_extract" 2>&1
    
    cd /
    rm -rf "$work_dir"
    
    if [[ -f "$new_iso" ]]; then
        echo ""
        echo "========================================="
        echo "Secure Boot ISO Created Successfully!"
        echo "========================================="
        echo "ISO: $new_iso"
        echo "Size: $(du -h "$new_iso" | cut -f1)"
        echo ""
        echo "BOOT CHAIN: UEFI -> SUSE shim (SBAT=shim,4) -> GRUB stub -> VMware GRUB"
        echo "MOKMANAGER: /MokManager.efi (ROOT)"
        echo ""
        echo "FIRST BOOT: Security Violation -> MokManager -> Enroll key -> /"
        echo "            -> ENROLL_THIS_KEY_IN_MOKMANAGER.cer -> Reboot"
        echo "========================================="
        return 0
    else
        echo "Error: Failed to create ISO"
        return 1
    fi
}

# ============================================================================
# Wrapper functions that use modules
# ============================================================================

setup_keys() {
    echo ""
    echo "========================================="
    echo "Setting up cryptographic keys"
    echo "========================================="
    
    if [[ "$MODULES_LOADED" -eq 1 ]]; then
        generate_all_keys "$KEYS_DIR"
    else
        # Fallback to basic key generation
        mkdir -p "$KEYS_DIR"
        cd "$KEYS_DIR"
        
        if [[ ! -f "MOK.key" ]]; then
            openssl req -new -x509 -newkey rsa:2048 -nodes \
                -keyout MOK.key -out MOK.crt \
                -days 3650 -subj "/CN=Photon OS Secure Boot MOK" 2>/dev/null
            openssl x509 -in MOK.crt -outform DER -out MOK.der
            echo "[OK] Generated MOK key"
        fi
        
        if [[ ! -f "srk.pem" ]]; then
            openssl genrsa -out srk.pem 4096 2>/dev/null
            openssl rsa -in srk.pem -pubout -out srk_pub.pem 2>/dev/null
            openssl dgst -sha256 -binary srk_pub.pem > srk_hash.bin
            echo "[OK] Generated SRK key"
        fi
    fi
}

setup_efuse() {
    echo ""
    echo "========================================="
    echo "Setting up eFuse simulation"
    echo "========================================="
    
    if [[ "$MODULES_LOADED" -eq 1 ]]; then
        create_efuse_simulation "$EFUSE_DIR" "$KEYS_DIR"
    else
        # Fallback
        mkdir -p "$EFUSE_DIR"
        if [[ -f "$KEYS_DIR/srk_hash.bin" ]]; then
            cp "$KEYS_DIR/srk_hash.bin" "$EFUSE_DIR/srk_fuse.bin"
        fi
        printf '\x02' > "$EFUSE_DIR/sec_config.bin"
        echo "Closed" > "$EFUSE_DIR/sec_config.txt"
        echo "[OK] eFuse simulation created"
    fi
}

setup_shim() {
    echo ""
    echo "========================================="
    echo "Setting up SUSE shim and MokManager"
    echo "========================================="
    
    if [[ "$MODULES_LOADED" -eq 1 ]]; then
        download_ventoy_shim "$KEYS_DIR"
    else
        echo "Error: Modules required for shim setup"
        return 1
    fi
}

# ============================================================================
# Main execution
# ============================================================================

# Handle --create-efuse-usb separately
if [[ -n "$EFUSE_USB_DEVICE" ]]; then
    echo "========================================="
    echo "Creating eFuse USB Dongle"
    echo "========================================="
    
    if [[ "$MODULES_LOADED" -eq 1 ]]; then
        # Ensure keys exist
        [[ -f "$KEYS_DIR/srk_hash.bin" ]] || setup_keys
        create_efuse_usb "$EFUSE_USB_DEVICE" "$KEYS_DIR"
    else
        echo "Error: Modules required for USB creation"
        exit 1
    fi
    exit $?
fi

# Handle clean
if [[ "$1" == "clean" ]]; then
    cleanup
    exit 0
fi

echo "========================================="
echo "HABv4 Installer"
echo "========================================="
echo "Host Architecture: $HOST_ARCH"
echo "Photon OS Release: $PHOTON_RELEASE"
echo "Build Directory:   $PHOTON_DIR"
echo "Modules Loaded:    $MODULES_LOADED"
[[ "$EFUSE_USB_MODE" -eq 1 ]] && echo "eFuse USB Mode:    ENABLED"
echo "========================================="

# Run installation steps
check_prerequisites
install_dependencies
install_toolchain
build_qemu
build_cst

# Key and security setup (uses modules)
setup_keys
setup_efuse
setup_shim

# Platform-specific builds
build_optee_aarch64
build_tfa_aarch64
enable_tee_x86_64
build_uboot_aarch64
build_grub_x86_64
integrate_tfa_uboot_aarch64
build_linux_aarch64
build_linux_x86_64

# Verification
verify_installations

# Photon OS integration
prepare_photon_env
build_photon_iso

echo ""
echo "========================================="
echo "Installation Complete!"
echo "========================================="
echo "HAB components:  $BUILD_DIR"
echo "Keys:            $KEYS_DIR"
echo "eFuse simulation: $EFUSE_DIR"
echo ""
echo "For cleanup: $0 clean"
echo "========================================="
