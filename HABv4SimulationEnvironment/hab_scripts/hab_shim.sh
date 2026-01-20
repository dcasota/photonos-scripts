#!/bin/bash
# HAB Shim Management - Download and setup SUSE shim and MokManager
# Uses Ventoy's SUSE shim which is SBAT=shim,4 compliant

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hab_lib.sh"

# ============================================================================
# SUSE Shim Configuration
# ============================================================================

# SUSE shim (from Ventoy) - SBAT compliant (shim,4)
# - Microsoft-signed for UEFI Secure Boot
# - SUSE-signed for internal trust chain
# - Looks for MokManager at \MokManager.efi (ROOT level)
# - Looks for GRUB at \grub.efi or \EFI\BOOT\grub*.efi

SHIM_FILE="shim-suse.efi"
MOKMANAGER_FILE="MokManager-suse.efi"

# ============================================================================
# Functions
# ============================================================================

download_ventoy_shim() {
    local dest_dir="${1:-$HAB_KEYS_DIR}"
    local temp_dir
    
    ensure_dir "$dest_dir"
    
    # Check if already downloaded
    if [[ -f "$dest_dir/$SHIM_FILE" && -f "$dest_dir/$MOKMANAGER_FILE" ]]; then
        local sbat
        sbat=$(get_sbat_version "$dest_dir/$SHIM_FILE")
        if [[ "$sbat" == *"shim,4"* ]]; then
            log_info "SUSE shim already present (SBAT=$sbat)"
            return 0
        fi
    fi
    
    log_step "Downloading SUSE shim from Ventoy ${VENTOY_VERSION}..."
    
    temp_dir=$(make_temp_dir "ventoy")
    trap "cleanup_temp '$temp_dir'" RETURN
    
    # Download Ventoy
    local ventoy_tar="$temp_dir/ventoy.tar.gz"
    if ! download_file "$VENTOY_URL" "$ventoy_tar" "Ventoy ${VENTOY_VERSION}"; then
        return 1
    fi
    
    # Extract
    tar -xzf "$ventoy_tar" -C "$temp_dir"
    
    # Extract disk image
    local disk_img="$temp_dir/ventoy-${VENTOY_VERSION}/ventoy/ventoy.disk.img"
    if [[ -f "${disk_img}.xz" ]]; then
        xz -dk "${disk_img}.xz"
    fi
    
    if [[ ! -f "$disk_img" ]]; then
        log_error "Ventoy disk image not found"
        return 1
    fi
    
    # Mount and extract EFI files
    local mount_point="$temp_dir/mount"
    ensure_dir "$mount_point"
    
    if ! mount -o loop,ro "$disk_img" "$mount_point"; then
        log_error "Failed to mount Ventoy disk image"
        return 1
    fi
    
    # Copy shim and MokManager
    if [[ -f "$mount_point/EFI/BOOT/BOOTX64.EFI" ]]; then
        cp "$mount_point/EFI/BOOT/BOOTX64.EFI" "$dest_dir/$SHIM_FILE"
        log_ok "Extracted SUSE shim"
    else
        umount "$mount_point"
        log_error "Shim not found in Ventoy image"
        return 1
    fi
    
    if [[ -f "$mount_point/EFI/BOOT/MokManager.efi" ]]; then
        cp "$mount_point/EFI/BOOT/MokManager.efi" "$dest_dir/$MOKMANAGER_FILE"
        log_ok "Extracted SUSE MokManager"
    else
        umount "$mount_point"
        log_error "MokManager not found in Ventoy image"
        return 1
    fi
    
    # Copy enrollment certificate if present
    if [[ -f "$mount_point/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" ]]; then
        cp "$mount_point/ENROLL_THIS_KEY_IN_MOKMANAGER.cer" "$dest_dir/ventoy-mok.cer"
    fi
    
    umount "$mount_point"
    
    # Verify downloaded files
    verify_suse_shim "$dest_dir"
}

verify_suse_shim() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    local shim_path="$keys_dir/$SHIM_FILE"
    local mok_path="$keys_dir/$MOKMANAGER_FILE"
    
    log_step "Verifying SUSE shim..."
    
    # Check shim exists
    if ! check_file "$shim_path" "SUSE shim"; then
        return 1
    fi
    
    # Check MokManager exists
    if ! check_file "$mok_path" "SUSE MokManager"; then
        return 1
    fi
    
    # Verify SBAT version
    local sbat
    sbat=$(get_sbat_version "$shim_path")
    if [[ "$sbat" != *"shim,4"* ]]; then
        log_error "SUSE shim has wrong SBAT version: $sbat (expected shim,4)"
        return 1
    fi
    log_ok "SUSE shim SBAT version: $sbat"
    
    # Verify Microsoft signature
    if ! verify_signature "$shim_path" "Microsoft"; then
        log_error "SUSE shim missing Microsoft signature"
        return 1
    fi
    
    # Verify SUSE signature
    if ! verify_signature "$shim_path" "SUSE"; then
        log_warn "SUSE signature verification inconclusive"
    fi
    
    # Verify MokManager has SUSE signature
    if ! verify_signature "$mok_path" "SUSE"; then
        log_warn "MokManager SUSE signature verification inconclusive"
    fi
    
    # Check what path shim looks for MokManager
    local mok_path_check
    mok_path_check=$(strings -e l "$shim_path" 2>/dev/null | grep -i "MokManager" | head -1)
    if [[ -n "$mok_path_check" ]]; then
        log_info "Shim MokManager path: $mok_path_check"
    fi
    
    log_ok "SUSE shim verification complete"
    return 0
}

get_shim_path() {
    echo "$HAB_KEYS_DIR/$SHIM_FILE"
}

get_mokmanager_path() {
    echo "$HAB_KEYS_DIR/$MOKMANAGER_FILE"
}

# Show shim info
show_shim_info() {
    local keys_dir="${1:-$HAB_KEYS_DIR}"
    local shim_path="$keys_dir/$SHIM_FILE"
    local mok_path="$keys_dir/$MOKMANAGER_FILE"
    
    echo ""
    echo "=== SUSE Shim Information ==="
    echo "Shim file: $shim_path"
    echo "MokManager file: $mok_path"
    echo ""
    
    if [[ -f "$shim_path" ]]; then
        echo "Shim size: $(stat -c%s "$shim_path") bytes"
        echo "Shim SHA256: $(get_sha256 "$shim_path")"
        echo "SBAT: $(get_sbat_version "$shim_path")"
        echo ""
        echo "Shim signatures:"
        sbverify --list "$shim_path" 2>&1 | grep -E "subject:|issuer:" | head -10
    else
        echo "Shim not found"
    fi
    
    echo ""
    if [[ -f "$mok_path" ]]; then
        echo "MokManager size: $(stat -c%s "$mok_path") bytes"
        echo "MokManager SHA256: $(get_sha256 "$mok_path")"
        echo ""
        echo "MokManager signatures:"
        sbverify --list "$mok_path" 2>&1 | grep -E "subject:|issuer:" | head -10
    else
        echo "MokManager not found"
    fi
    
    echo ""
    echo "=== MokManager Search Paths (SUSE shim) ==="
    echo "Primary:   \\MokManager.efi (ROOT level)"
    echo "Fallback:  \\EFI\\BOOT\\MokManager.efi"
    echo ""
}

# ============================================================================
# Main (when run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-download}" in
        download)
            download_ventoy_shim "${2:-$HAB_KEYS_DIR}"
            ;;
        verify)
            verify_suse_shim "${2:-$HAB_KEYS_DIR}"
            ;;
        info)
            show_shim_info "${2:-$HAB_KEYS_DIR}"
            ;;
        *)
            echo "Usage: $0 {download|verify|info} [keys_dir]"
            exit 1
            ;;
    esac
fi
