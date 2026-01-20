#!/bin/bash
# HAB eFuse Simulation - Create and manage eFuse simulation files
# Includes USB dongle creation for hardware-like simulation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/hab_lib.sh"

# ============================================================================
# eFuse Configuration
# ============================================================================

# Security modes
SEC_MODE_OPEN=0x00
SEC_MODE_CLOSED=0x02

# eFuse files
EFUSE_SRK_FILE="srk_fuse.bin"
EFUSE_SEC_FILE="sec_config.bin"
EFUSE_CONFIG_FILE="efuse_config.json"
EFUSE_USB_LABEL="EFUSE_SIM"

# ============================================================================
# eFuse Simulation Functions
# ============================================================================

create_efuse_simulation() {
    local efuse_dir="${1:-$HAB_EFUSE_DIR}"
    local keys_dir="${2:-$HAB_KEYS_DIR}"
    
    log_step "Creating eFuse simulation..."
    ensure_dir "$efuse_dir"
    
    # Check for SRK hash
    if [[ ! -f "$keys_dir/srk_hash.bin" ]]; then
        log_error "SRK hash not found. Generate keys first."
        return 1
    fi
    
    # Copy SRK hash as "burned" fuse
    cp "$keys_dir/srk_hash.bin" "$efuse_dir/$EFUSE_SRK_FILE"
    log_ok "Created SRK fuse simulation"
    
    # Create security config (Closed mode by default)
    printf '\x02' > "$efuse_dir/$EFUSE_SEC_FILE"
    echo "Closed" > "$efuse_dir/sec_config.txt"
    log_ok "Set security mode: CLOSED"
    
    # Create JSON config
    local srk_hash
    srk_hash=$(xxd -p "$efuse_dir/$EFUSE_SRK_FILE" | tr -d '\n')
    
    cat > "$efuse_dir/$EFUSE_CONFIG_FILE" << EOF
{
    "efuse_simulation": {
        "version": "1.0",
        "created": "$(date -Iseconds)",
        "security_mode": "closed",
        "srk_hash": "$srk_hash",
        "srk_revocation_mask": "0x0",
        "notes": "This is a simulation. Real eFuses are one-time programmable."
    }
}
EOF
    log_ok "Created eFuse configuration"
    
    # Copy SRK public key for reference
    if [[ -f "$keys_dir/srk_pub.pem" ]]; then
        cp "$keys_dir/srk_pub.pem" "$efuse_dir/"
    fi
    
    log_ok "eFuse simulation created in $efuse_dir"
}

verify_efuse_simulation() {
    local efuse_dir="${1:-$HAB_EFUSE_DIR}"
    local keys_dir="${2:-$HAB_KEYS_DIR}"
    local errors=0
    
    log_step "Verifying eFuse simulation..."
    
    # Check SRK fuse
    if [[ ! -f "$efuse_dir/$EFUSE_SRK_FILE" ]]; then
        log_error "SRK fuse file missing"
        ((errors++))
    elif [[ -f "$keys_dir/srk_hash.bin" ]]; then
        local fuse_hash key_hash
        fuse_hash=$(get_sha256 "$efuse_dir/$EFUSE_SRK_FILE")
        key_hash=$(get_sha256 "$keys_dir/srk_hash.bin")
        if [[ "$fuse_hash" != "$key_hash" ]]; then
            log_warn "SRK fuse doesn't match current key (may be intentional)"
        else
            log_ok "SRK fuse matches key"
        fi
    fi
    
    # Check security config
    if [[ ! -f "$efuse_dir/$EFUSE_SEC_FILE" ]]; then
        log_error "Security config file missing"
        ((errors++))
    else
        local sec_mode
        sec_mode=$(xxd -p "$efuse_dir/$EFUSE_SEC_FILE" | head -c2)
        case "$sec_mode" in
            00) log_info "Security mode: OPEN" ;;
            02) log_ok "Security mode: CLOSED" ;;
            *) log_warn "Security mode: UNKNOWN ($sec_mode)" ;;
        esac
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_ok "eFuse simulation verified"
        return 0
    else
        return 1
    fi
}

# ============================================================================
# USB Dongle Functions
# ============================================================================

create_efuse_usb() {
    local device="$1"
    local keys_dir="${2:-$HAB_KEYS_DIR}"
    
    if [[ -z "$device" ]]; then
        log_error "Usage: create_efuse_usb /dev/sdX [keys_dir]"
        return 1
    fi
    
    # Safety checks
    if [[ ! -b "$device" ]]; then
        log_error "Device not found: $device"
        return 1
    fi
    
    # Check it's not a system disk
    local root_dev
    root_dev=$(findmnt -n -o SOURCE /)
    if [[ "$root_dev" == "$device"* ]]; then
        log_error "Cannot use root filesystem device!"
        return 1
    fi
    
    log_warn "This will ERASE ALL DATA on $device"
    echo -n "Type 'YES' to continue: "
    read -r confirm
    if [[ "$confirm" != "YES" ]]; then
        log_info "Aborted"
        return 1
    fi
    
    log_step "Creating eFuse USB dongle on $device..."
    
    # Unmount any mounted partitions
    umount "${device}"* 2>/dev/null || true
    
    # Create partition table and FAT32 partition
    log_info "Creating partition table..."
    parted -s "$device" mklabel msdos
    parted -s "$device" mkpart primary fat32 1MiB 100%
    
    # Wait for partition to appear
    sleep 2
    partprobe "$device" 2>/dev/null || true
    sleep 1
    
    # Find partition
    local partition
    if [[ -b "${device}1" ]]; then
        partition="${device}1"
    elif [[ -b "${device}p1" ]]; then
        partition="${device}p1"
    else
        log_error "Partition not found after creation"
        return 1
    fi
    
    # Format as FAT32 with label
    log_info "Formatting as FAT32..."
    mkfs.vfat -F 32 -n "$EFUSE_USB_LABEL" "$partition"
    
    # Mount and copy files
    local mount_point
    mount_point=$(make_temp_dir "efuse_usb")
    
    if ! mount "$partition" "$mount_point"; then
        rmdir "$mount_point"
        log_error "Failed to mount partition"
        return 1
    fi
    
    # Create efuse_sim directory
    mkdir -p "$mount_point/efuse_sim"
    
    # Check for SRK hash
    if [[ ! -f "$keys_dir/srk_hash.bin" ]]; then
        umount "$mount_point"
        rmdir "$mount_point"
        log_error "SRK hash not found. Generate keys first."
        return 1
    fi
    
    # Copy eFuse files
    cp "$keys_dir/srk_hash.bin" "$mount_point/efuse_sim/$EFUSE_SRK_FILE"
    printf '\x02' > "$mount_point/efuse_sim/$EFUSE_SEC_FILE"
    
    # Create JSON config
    local srk_hash
    srk_hash=$(xxd -p "$keys_dir/srk_hash.bin" | tr -d '\n')
    
    cat > "$mount_point/efuse_sim/$EFUSE_CONFIG_FILE" << EOF
{
    "efuse_simulation": {
        "version": "1.0",
        "created": "$(date -Iseconds)",
        "security_mode": "closed",
        "srk_hash": "$srk_hash",
        "device": "USB Dongle",
        "label": "$EFUSE_USB_LABEL"
    }
}
EOF
    
    # Copy public key for reference
    if [[ -f "$keys_dir/srk_pub.pem" ]]; then
        cp "$keys_dir/srk_pub.pem" "$mount_point/efuse_sim/"
    fi
    
    sync
    umount "$mount_point"
    rmdir "$mount_point"
    
    log_ok "eFuse USB dongle created on $device"
    echo ""
    echo "USB Dongle Information:"
    echo "  Device: $device"
    echo "  Label: $EFUSE_USB_LABEL"
    echo "  Contents: efuse_sim/srk_fuse.bin, sec_config.bin, efuse_config.json"
    echo ""
    echo "Insert this USB when booting ISO built with --efuse-usb flag"
}

show_efuse_info() {
    local efuse_dir="${1:-$HAB_EFUSE_DIR}"
    
    echo ""
    echo "=== eFuse Simulation Information ==="
    echo "Directory: $efuse_dir"
    echo ""
    
    if [[ ! -d "$efuse_dir" ]]; then
        echo "eFuse directory does not exist"
        return 1
    fi
    
    if [[ -f "$efuse_dir/$EFUSE_SRK_FILE" ]]; then
        echo "SRK Fuse: $(xxd -p "$efuse_dir/$EFUSE_SRK_FILE" | head -c 64)..."
        echo "SRK Size: $(stat -c%s "$efuse_dir/$EFUSE_SRK_FILE") bytes"
    else
        echo "SRK Fuse: NOT SET"
    fi
    
    echo ""
    if [[ -f "$efuse_dir/$EFUSE_SEC_FILE" ]]; then
        local sec_mode
        sec_mode=$(xxd -p "$efuse_dir/$EFUSE_SEC_FILE" | head -c2)
        case "$sec_mode" in
            00) echo "Security Mode: OPEN (0x00)" ;;
            02) echo "Security Mode: CLOSED (0x02)" ;;
            *) echo "Security Mode: UNKNOWN ($sec_mode)" ;;
        esac
    else
        echo "Security Mode: NOT SET"
    fi
    
    echo ""
    if [[ -f "$efuse_dir/$EFUSE_CONFIG_FILE" ]]; then
        echo "Configuration:"
        cat "$efuse_dir/$EFUSE_CONFIG_FILE"
    fi
    
    echo ""
}

# ============================================================================
# Main (when run directly)
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "${1:-create}" in
        create)
            create_efuse_simulation "${2:-$HAB_EFUSE_DIR}" "${3:-$HAB_KEYS_DIR}"
            ;;
        verify)
            verify_efuse_simulation "${2:-$HAB_EFUSE_DIR}" "${3:-$HAB_KEYS_DIR}"
            ;;
        usb)
            create_efuse_usb "$2" "${3:-$HAB_KEYS_DIR}"
            ;;
        info)
            show_efuse_info "${2:-$HAB_EFUSE_DIR}"
            ;;
        *)
            echo "Usage: $0 {create|verify|usb|info} [args...]"
            echo "  create [efuse_dir] [keys_dir]  - Create eFuse simulation"
            echo "  verify [efuse_dir] [keys_dir]  - Verify eFuse simulation"
            echo "  usb /dev/sdX [keys_dir]        - Create eFuse USB dongle"
            echo "  info [efuse_dir]               - Show eFuse information"
            exit 1
            ;;
    esac
fi
