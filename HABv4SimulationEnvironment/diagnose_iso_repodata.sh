#!/bin/bash
set -e

ISO_PATH="/root/5.0/stage/photon-5.0-d8ac7093c.x86_64-secureboot.iso"
MOUNT_POINT="/mnt/iso_diagnosis"

# Check if ISO exists
if [ ! -f "$ISO_PATH" ]; then
    echo "ISO not found at $ISO_PATH"
    exit 1
fi

echo "Diagnosing ISO: $ISO_PATH"

# Create mount point
mkdir -p "$MOUNT_POINT"

# Mount ISO
echo "Mounting ISO..."
mount -o loop,ro "$ISO_PATH" "$MOUNT_POINT"

# Check RPMS structure
echo "Checking RPMS structure..."
find "$MOUNT_POINT/RPMS" -maxdepth 2 -name "grub2-efi-image-mok*.rpm"
find "$MOUNT_POINT/RPMS" -maxdepth 2 -name "shim-signed-mok*.rpm"
find "$MOUNT_POINT/RPMS" -maxdepth 2 -name "linux-mok*.rpm"

# Check repodata
echo "Checking repodata..."
if [ -d "$MOUNT_POINT/RPMS/repodata" ]; then
    echo "Repodata found at $MOUNT_POINT/RPMS/repodata"
    
    # Check if primary.xml.gz contains grub2-efi-image-mok
    echo "Checking for grub2-efi-image-mok in repodata..."
    zgrep "grub2-efi-image-mok" "$MOUNT_POINT/RPMS/repodata/"*-primary.xml.gz | head -1
else
    echo "ERROR: Repodata not found at $MOUNT_POINT/RPMS/repodata"
fi

# Cleanup
echo "Unmounting..."
umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"

echo "Diagnosis complete."
