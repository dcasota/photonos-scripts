#!/bin/bash
# HAB ISO Management - Create and fix Secure Boot compatible ISOs
# Uses SUSE shim (SBAT=shim,4) from Ventoy for maximum compatibility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hab_lib.sh"
source "$SCRIPT_DIR/hab_shim.sh"

# ============================================================================
# ISO Configuration
# ============================================================================

# EFI boot image size (MB)
EFIBOOT_SIZE_MB=16

# Files that must be present in Secure Boot ISO
REQUIRED_EFI_FILES=(
    "EFI/BOOT/BOOTX64.EFI"
    "EFI/BOOT/grub.efi"
    "EFI/BOOT/grubx64.efi"
    "EFI/BOOT/MokManager.efi"
)

# MokManager locations for maximum compatibility
# SUSE shim looks for \MokManager.efi at ROOT
MOKMANAGER_LOCATIONS=(
    "MokManager.efi"           # ROOT - SUSE shim primary path
    "EFI/BOOT/MokManager.efi"  # Standard fallback
)

# ============================================================================
# GRUB Stub Building
# ============================================================================

build_grub_stub() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    local output_file="${2:-$keys_dir/grub-photon-stub.efi}"
    local efuse_usb_mode="${3:-0}"
    
    log_step "Building Photon OS GRUB stub..."
    
    # Check for grub-mkimage
    if ! check_command grub2-mkimage && ! check_command grub-mkimage; then
        log_error "grub-mkimage/grub2-mkimage not found"
        return 1
    fi
    
    local grub_mkimage="grub2-mkimage"
    check_command grub2-mkimage || grub_mkimage="grub-mkimage"
    
    # Required modules
    local modules="
        normal search search_fs_file search_fs_uuid search_label
        configfile echo test fat part_gpt part_msdos
        chain linux boot all_video gfxterm font
        efi_gop efi_uga
        loadenv ls cat help true regexp
    "
    
    # Add USB search module for eFuse mode
    if [[ "$efuse_usb_mode" -eq 1 ]]; then
        modules="$modules usb usbms"
    fi
    
    # Create embedded grub.cfg
    local temp_dir
    temp_dir=$(make_temp_dir "grub_stub")
    trap "cleanup_temp '$temp_dir'" RETURN
    
    local grub_cfg="$temp_dir/grub.cfg"
    
    if [[ "$efuse_usb_mode" -eq 1 ]]; then
        create_efuse_grub_cfg "$grub_cfg"
    else
        create_standard_grub_cfg "$grub_cfg"
    fi
    
    # Find GRUB modules directory
    local grub_modules_dir=""
    for dir in /usr/lib/grub/x86_64-efi /usr/lib64/grub/x86_64-efi /usr/share/grub2/x86_64-efi; do
        if [[ -d "$dir" ]]; then
            grub_modules_dir="$dir"
            break
        fi
    done
    
    if [[ -z "$grub_modules_dir" ]]; then
        log_error "GRUB x86_64-efi modules not found"
        return 1
    fi
    
    # Build GRUB image
    local unsigned_stub="$temp_dir/grub-unsigned.efi"
    $grub_mkimage \
        -O x86_64-efi \
        -o "$unsigned_stub" \
        -c "$grub_cfg" \
        -p /EFI/BOOT \
        -d "$grub_modules_dir" \
        $modules
    
    log_ok "Built unsigned GRUB stub"
    
    # Sign with MOK
    if [[ -f "$keys_dir/MOK.key" && -f "$keys_dir/MOK.crt" ]]; then
        if check_command sbsign; then
            sbsign --key "$keys_dir/MOK.key" --cert "$keys_dir/MOK.crt" \
                --output "$output_file" "$unsigned_stub"
            log_ok "Signed GRUB stub with MOK"
        else
            cp "$unsigned_stub" "$output_file"
            log_warn "sbsign not available, stub is unsigned"
        fi
    else
        cp "$unsigned_stub" "$output_file"
        log_warn "MOK keys not found, stub is unsigned"
    fi
    
    return 0
}

create_standard_grub_cfg() {
    local output="$1"
    
    cat > "$output" << 'GRUBCFG'
# Photon OS Secure Boot - GRUB Stub Menu
set default=0
set timeout=5
set color_normal=white/black
set color_highlight=black/white

# Search for ISO filesystem
search --no-floppy --file --set=isoroot /isolinux/vmlinuz

menuentry "Continue to Photon OS Installer" {
    if [ -n "$isoroot" ]; then
        set root=$isoroot
        configfile ($isoroot)/boot/grub2/grub.cfg
    else
        chainloader /EFI/BOOT/grubx64_real.efi
    fi
}

menuentry "MokManager - Enroll/Delete MOK Keys" {
    chainloader /MokManager.efi
}

menuentry "Reboot" {
    echo "Rebooting..."
    reboot
}

menuentry "Shutdown" {
    echo "Shutting down..."
    halt
}
GRUBCFG
}

create_efuse_grub_cfg() {
    local output="$1"
    
    cat > "$output" << 'GRUBCFG'
# Photon OS Secure Boot - GRUB Stub Menu (eFuse USB Mode)
set default=0
set timeout=5
set color_normal=white/black
set color_highlight=black/white

# Search for eFuse USB dongle
search --no-floppy --label EFUSE_SIM --set=efuse_usb

# Search for ISO filesystem
search --no-floppy --file --set=isoroot /isolinux/vmlinuz

if [ -n "$efuse_usb" ]; then
    if [ -f ($efuse_usb)/efuse_sim/srk_fuse.bin ]; then
        echo "eFuse USB detected - Security Mode: CLOSED"
        set efuse_valid=1
    else
        echo "eFuse USB found but srk_fuse.bin missing"
        set efuse_valid=0
    fi
else
    echo "WARNING: eFuse USB not detected"
    set efuse_valid=0
fi

if [ "$efuse_valid" = "1" ]; then
    menuentry "Continue to Photon OS Installer" {
        if [ -n "$isoroot" ]; then
            set root=$isoroot
            configfile ($isoroot)/boot/grub2/grub.cfg
        else
            chainloader /EFI/BOOT/grubx64_real.efi
        fi
    }
fi

menuentry "MokManager - Enroll/Delete MOK Keys" {
    chainloader /MokManager.efi
}

if [ "$efuse_valid" != "1" ]; then
    menuentry "Retry - Search for eFuse USB" {
        configfile $prefix/grub.cfg
    }
fi

menuentry "Reboot" {
    echo "Rebooting..."
    reboot
}

menuentry "Shutdown" {
    echo "Shutting down..."
    halt
}
GRUBCFG
}

# ============================================================================
# ISO Building Functions
# ============================================================================

fix_iso_secureboot() {
    local input_iso="$1"
    local output_iso="${2:-}"
    local keys_dir="${3:-$HAB_KEYS_DIR}"
    local efuse_usb_mode="${4:-0}"
    
    if [[ -z "$input_iso" ]]; then
        log_error "Usage: fix_iso_secureboot <input.iso> [output.iso] [keys_dir] [efuse_mode]"
        return 1
    fi
    
    if [[ ! -f "$input_iso" ]]; then
        log_error "Input ISO not found: $input_iso"
        return 1
    fi
    
    # Generate output filename if not specified
    if [[ -z "$output_iso" ]]; then
        output_iso="${input_iso%.iso}-secureboot.iso"
    fi
    
    log_step "Fixing ISO for Secure Boot: $(basename "$input_iso")"
    
    # Ensure we have SUSE shim
    if ! download_ventoy_shim "$keys_dir"; then
        log_error "Failed to download SUSE shim"
        return 1
    fi
    
    local shim_path="$keys_dir/shim-suse.efi"
    local mok_path="$keys_dir/MokManager-suse.efi"
    
    # Build GRUB stub if needed
    local grub_stub="$keys_dir/grub-photon-stub.efi"
    if [[ ! -f "$grub_stub" ]] || [[ "$efuse_usb_mode" -eq 1 ]]; then
        build_grub_stub "$keys_dir" "$grub_stub" "$efuse_usb_mode"
    fi
    
    # Create temp directory
    local temp_dir
    temp_dir=$(make_temp_dir "iso_fix")
    trap "cleanup_temp '$temp_dir'; unmount_image '$temp_dir/iso_mount'; unmount_image '$temp_dir/efi_mount'" RETURN
    
    local iso_extract="$temp_dir/iso_extract"
    local iso_mount="$temp_dir/iso_mount"
    local efi_mount="$temp_dir/efi_mount"
    
    mkdir -p "$iso_extract" "$iso_mount" "$efi_mount"
    
    # Mount and extract ISO
    log_info "Extracting ISO..."
    if ! mount -o loop,ro "$input_iso" "$iso_mount"; then
        log_error "Failed to mount ISO"
        return 1
    fi
    
    cp -a "$iso_mount"/* "$iso_extract/"
    umount "$iso_mount"
    
    # Get VMware-signed GRUB from original ISO or package
    local grub_real="$iso_extract/EFI/BOOT/grubx64.efi"
    if [[ ! -f "$grub_real" ]]; then
        log_warn "Original GRUB not found in ISO, downloading from package..."
        download_vmware_grub "$keys_dir"
        grub_real="$keys_dir/grubx64-vmware.efi"
    fi
    
    # === Update efiboot.img ===
    log_step "Updating efiboot.img..."
    
    local efiboot_img="$iso_extract/boot/grub2/efiboot.img"
    
    # Create new larger efiboot.img
    local new_efiboot="$temp_dir/efiboot_new.img"
    create_fat_image "$new_efiboot" "$EFIBOOT_SIZE_MB" "EFIBOOT"
    
    if ! mount -o loop "$new_efiboot" "$efi_mount"; then
        log_error "Failed to mount new efiboot.img"
        return 1
    fi
    
    mkdir -p "$efi_mount/EFI/BOOT" "$efi_mount/grub"
    
    # Install SUSE shim as BOOTX64.EFI
    cp "$shim_path" "$efi_mount/EFI/BOOT/BOOTX64.EFI"
    log_ok "Installed SUSE shim as BOOTX64.EFI (SBAT=shim,4)"
    
    # Install GRUB stub
    cp "$grub_stub" "$efi_mount/EFI/BOOT/grub.efi"
    cp "$grub_stub" "$efi_mount/EFI/BOOT/grubx64.efi"
    log_ok "Installed Photon OS GRUB stub as grub.efi/grubx64.efi"
    
    # Install VMware GRUB as grubx64_real.efi
    if [[ -f "$grub_real" ]]; then
        cp "$grub_real" "$efi_mount/EFI/BOOT/grubx64_real.efi"
        log_ok "Installed VMware GRUB as grubx64_real.efi"
    fi
    
    # Install MokManager at ALL known locations for maximum compatibility
    # SUSE shim looks for \MokManager.efi at ROOT
    cp "$mok_path" "$efi_mount/MokManager.efi"              # ROOT - SUSE shim primary
    cp "$mok_path" "$efi_mount/EFI/BOOT/MokManager.efi"     # Fallback in EFI/BOOT
    log_ok "Installed SUSE MokManager (ROOT + EFI/BOOT)"
    
    # Install MOK certificate for enrollment at ROOT
    if [[ -f "$keys_dir/MOK.der" ]]; then
        cp "$keys_dir/MOK.der" "$efi_mount/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
        cp "$keys_dir/MOK.der" "$efi_mount/EFI/BOOT/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
        log_ok "Installed MOK certificate for enrollment"
    fi
    
    # Create bootstrap grub.cfg
    cat > "$efi_mount/EFI/BOOT/grub.cfg" << 'EOFGRUBCFG'
search --no-floppy --file --set=root /isolinux/vmlinuz
if [ -n "$root" ]; then
    set prefix=($root)/boot/grub2
    configfile ($root)/boot/grub2/grub.cfg
fi
EOFGRUBCFG
    
    cat > "$efi_mount/grub/grub.cfg" << 'EOFGRUBCFG'
search --no-floppy --file --set=root /isolinux/vmlinuz
if [ -n "$root" ]; then
    set prefix=($root)/boot/grub2
    configfile ($root)/boot/grub2/grub.cfg
fi
EOFGRUBCFG
    
    sync
    umount "$efi_mount"
    
    # Replace efiboot.img in ISO
    cp "$new_efiboot" "$efiboot_img"
    log_ok "Updated efiboot.img (${EFIBOOT_SIZE_MB}MB)"
    
    # === Update ISO root EFI directory ===
    log_step "Updating ISO EFI directory..."
    
    mkdir -p "$iso_extract/EFI/BOOT"
    
    cp "$shim_path" "$iso_extract/EFI/BOOT/BOOTX64.EFI"
    cp "$grub_stub" "$iso_extract/EFI/BOOT/grub.efi"
    cp "$grub_stub" "$iso_extract/EFI/BOOT/grubx64.efi"
    
    if [[ -f "$grub_real" ]]; then
        cp "$grub_real" "$iso_extract/EFI/BOOT/grubx64_real.efi"
    fi
    
    # MokManager at ALL locations in ISO root
    cp "$mok_path" "$iso_extract/MokManager.efi"            # ROOT - SUSE shim primary
    cp "$mok_path" "$iso_extract/EFI/BOOT/MokManager.efi"   # Fallback
    
    if [[ -f "$keys_dir/MOK.der" ]]; then
        cp "$keys_dir/MOK.der" "$iso_extract/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
        cp "$keys_dir/MOK.der" "$iso_extract/EFI/BOOT/ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    fi
    
    log_ok "Updated ISO EFI directory (MokManager at ROOT + EFI/BOOT)"
    
    # === Create main boot menu ===
    log_step "Creating boot menu..."
    create_main_grub_cfg "$iso_extract/boot/grub2/grub.cfg"
    log_ok "Created boot menu"
    
    # === Build ISO ===
    log_step "Building ISO..."
    
    local isohdpfx="/usr/share/syslinux/isohdpfx.bin"
    if [[ ! -f "$isohdpfx" ]]; then
        isohdpfx="/usr/lib/syslinux/mbr/isohdpfx.bin"
    fi
    
    local volume_id
    volume_id=$(isoinfo -d -i "$input_iso" 2>/dev/null | grep "Volume id:" | cut -d: -f2 | tr -d ' ' | head -c 32)
    [[ -z "$volume_id" ]] && volume_id="PHOTON_SB"
    
    xorriso -as mkisofs \
        -R -l -D \
        -o "$output_iso" \
        -V "$volume_id" \
        -c isolinux/boot.cat \
        -b isolinux/isolinux.bin \
        -no-emul-boot -boot-load-size 4 -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub2/efiboot.img \
        -no-emul-boot \
        -isohybrid-mbr "$isohdpfx" \
        -isohybrid-gpt-basdat \
        "$iso_extract"
    
    log_ok "Created Secure Boot ISO: $output_iso"
    
    # Print summary
    print_iso_summary "$output_iso"
    
    return 0
}

create_main_grub_cfg() {
    local output="$1"
    
    cat > "$output" << 'EOFMENU'
# Photon OS Secure Boot Menu
set default=0
set timeout=10
set color_normal=white/black
set color_highlight=black/white

# Load theme if available
if [ -f ${prefix}/themes/photon/theme.txt ]; then
    loadfont ${prefix}/themes/photon/dejavu_sans_mono_14.pf2
    set gfxmode=auto
    terminal_output gfxterm
    set theme=${prefix}/themes/photon/theme.txt
fi

menuentry "Install Photon OS (Custom)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=cdrom
    initrd /isolinux/initrd.img
}

menuentry "Install Photon OS (VMware original)" {
    linux /isolinux/vmlinuz root=/dev/ram0 loglevel=7 photon.media=cdrom console=ttyS0,115200n8
    initrd /isolinux/initrd.img
}

menuentry "UEFI Firmware Settings" {
    fwsetup
}
EOFMENU
}

download_vmware_grub() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    local grub_file="$keys_dir/grubx64-vmware.efi"
    
    if [[ -f "$grub_file" ]]; then
        log_info "VMware GRUB already present"
        return 0
    fi
    
    log_info "Downloading VMware-signed GRUB from Photon repository..."
    
    local temp_dir
    temp_dir=$(make_temp_dir "vmware_grub")
    trap "cleanup_temp '$temp_dir'" RETURN
    
    # Try to download grub2-efi-image package
    local pkg_url="https://packages.vmware.com/photon/5.0/photon_updates_5.0_x86_64"
    local pkg_file="$temp_dir/grub2-efi-image.rpm"
    
    # Get latest version
    if wget -q -O "$temp_dir/pkglist.html" "$pkg_url/"; then
        local rpm_name
        rpm_name=$(grep -oP 'grub2-efi-image-[0-9][^"<>]+x86_64\.rpm' "$temp_dir/pkglist.html" | sort -V | tail -1)
        
        if [[ -n "$rpm_name" ]]; then
            if wget -q -O "$pkg_file" "$pkg_url/$rpm_name"; then
                rpm2cpio "$pkg_file" | cpio -idm -D "$temp_dir" 2>/dev/null
                
                local grub_src="$temp_dir/boot/efi/EFI/BOOT/grubx64.efi"
                if [[ -f "$grub_src" ]]; then
                    cp "$grub_src" "$grub_file"
                    log_ok "Downloaded VMware-signed GRUB"
                    return 0
                fi
            fi
        fi
    fi
    
    log_warn "Could not download VMware GRUB"
    return 1
}

# ============================================================================
# Verification Functions
# ============================================================================

verify_iso() {
    local iso_file="$1"
    local errors=0
    
    if [[ ! -f "$iso_file" ]]; then
        log_error "ISO file not found: $iso_file"
        return 1
    fi
    
    log_step "Verifying ISO: $(basename "$iso_file")"
    
    local temp_dir
    temp_dir=$(make_temp_dir "verify_iso")
    trap "cleanup_temp '$temp_dir'; unmount_image '$temp_dir/iso'; unmount_image '$temp_dir/efi'" RETURN
    
    local iso_mount="$temp_dir/iso"
    local efi_mount="$temp_dir/efi"
    mkdir -p "$iso_mount" "$efi_mount"
    
    # Mount ISO
    if ! mount -o loop,ro "$iso_file" "$iso_mount"; then
        log_error "Failed to mount ISO"
        return 1
    fi
    
    echo ""
    echo "=== ISO Structure ==="
    
    # Check ROOT level MokManager (critical for SUSE shim)
    if [[ -f "$iso_mount/MokManager.efi" ]]; then
        log_ok "MokManager.efi at ROOT (SUSE shim primary path)"
    else
        log_error "MokManager.efi MISSING at ROOT"
        ((errors++))
    fi
    
    # Check EFI/BOOT files
    for file in "${REQUIRED_EFI_FILES[@]}"; do
        if [[ -f "$iso_mount/$file" ]]; then
            log_ok "$file"
        else
            log_error "$file MISSING"
            ((errors++))
        fi
    done
    
    # Check shim SBAT
    echo ""
    echo "=== Shim Information ==="
    local shim_file="$iso_mount/EFI/BOOT/BOOTX64.EFI"
    if [[ -f "$shim_file" ]]; then
        local sbat
        sbat=$(get_sbat_version "$shim_file")
        if [[ "$sbat" == *"shim,4"* ]]; then
            log_ok "Shim SBAT: $sbat (compliant)"
        else
            log_error "Shim SBAT: $sbat (may be revoked)"
            ((errors++))
        fi
        
        # Check signatures
        if sbverify --list "$shim_file" 2>&1 | grep -q "Microsoft"; then
            log_ok "Shim has Microsoft signature"
        else
            log_error "Shim missing Microsoft signature"
            ((errors++))
        fi
        
        if sbverify --list "$shim_file" 2>&1 | grep -q "SUSE"; then
            log_ok "Shim has SUSE signature"
        fi
    fi
    
    # Check efiboot.img
    echo ""
    echo "=== efiboot.img Contents ==="
    local efiboot="$iso_mount/boot/grub2/efiboot.img"
    if [[ -f "$efiboot" ]]; then
        mount -o loop,ro "$efiboot" "$efi_mount" 2>/dev/null
        
        # Check ROOT level MokManager in efiboot.img
        if [[ -f "$efi_mount/MokManager.efi" ]]; then
            log_ok "MokManager.efi at ROOT in efiboot.img"
        else
            log_error "MokManager.efi MISSING at ROOT in efiboot.img"
            ((errors++))
        fi
        
        # List other files
        for file in BOOTX64.EFI grub.efi grubx64.efi MokManager.efi; do
            if [[ -f "$efi_mount/EFI/BOOT/$file" ]]; then
                log_ok "efiboot: EFI/BOOT/$file"
            fi
        done
        
        if [[ -f "$efi_mount/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" ]]; then
            log_ok "MOK certificate at ROOT in efiboot.img"
        fi
        
        umount "$efi_mount" 2>/dev/null
    else
        log_error "efiboot.img not found"
        ((errors++))
    fi
    
    umount "$iso_mount"
    
    echo ""
    if [[ $errors -eq 0 ]]; then
        log_ok "ISO verification passed"
        return 0
    else
        log_error "ISO verification failed with $errors error(s)"
        return 1
    fi
}

print_iso_summary() {
    local iso_file="$1"
    
    echo ""
    echo "========================================="
    echo "Secure Boot ISO Created Successfully!"
    echo "========================================="
    echo ""
    echo "ISO: $iso_file"
    echo "Size: $(du -h "$iso_file" | cut -f1)"
    echo ""
    echo "SECURE BOOT CHAIN (SUSE Shim):"
    echo "  UEFI Firmware (trusts Microsoft UEFI CA 2011)"
    echo "    -> BOOTX64.EFI (SUSE shim 15.8, SBAT=shim,4)"
    echo "       -> grub.efi (Photon OS stub, MOK-signed)"
    echo "          -> grubx64_real.efi (VMware-signed GRUB)"
    echo "             -> Main boot menu -> kernel"
    echo ""
    echo "MOKMANAGER LOCATIONS:"
    echo "  /MokManager.efi              (ROOT - SUSE shim primary)"
    echo "  /EFI/BOOT/MokManager.efi     (Fallback)"
    echo ""
    echo "FIRST BOOT INSTRUCTIONS:"
    echo "  1. Boot from USB - 'Security Violation' appears (expected)"
    echo "  2. Press any key - MokManager loads automatically"
    echo "  3. Select 'Enroll key from disk'"
    echo "  4. Navigate to /, select ENROLL_THIS_KEY_IN_MOKMANAGER.cer"
    echo "  5. Confirm enrollment -> Reboot"
    echo "  6. After reboot, stub menu appears, then main menu"
    echo "========================================="
}

# ============================================================================
# Main (when run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-help}" in
        fix)
            fix_iso_secureboot "$2" "$3" "${4:-$HAB_KEYS_DIR}" "${5:-0}"
            ;;
        verify)
            verify_iso "$2"
            ;;
        stub)
            build_grub_stub "${2:-$HAB_KEYS_DIR}" "${3:-$HAB_KEYS_DIR/grub-photon-stub.efi}" "${4:-0}"
            ;;
        *)
            echo "Usage: $0 {fix|verify|stub} [args...]"
            echo "  fix <input.iso> [output.iso] [keys_dir] [efuse_mode]"
            echo "  verify <iso_file>"
            echo "  stub [keys_dir] [output_file] [efuse_mode]"
            exit 1
            ;;
    esac
fi
