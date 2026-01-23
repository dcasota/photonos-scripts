#!/usr/bin/env python3
"""
MOK Secure Boot Package Substitution Patch for Photon OS Installer

This module patches the Photon OS installer to detect the photon.secureboot=mok
kernel parameter and substitute standard boot packages with MOK-signed variants.

The patch modifies the installer.py configure() method to:
1. Detect photon.secureboot=mok from /proc/cmdline
2. Replace 'linux' with 'linux-mok'
3. Replace 'grub2-efi-image' with 'grub2-efi-image-mok'
4. Add 'shim-signed-mok' (which includes MokManager)

Usage:
    This file should be placed in the initrd at:
    /usr/lib/python3.11/site-packages/photon_installer/mok_patch.py
    
    And installer.py should import and call apply_mok_substitution() after
    the configure() method builds the package list.

Copyright 2024 HABv4 Project
SPDX-License-Identifier: GPL-3.0+
"""

import os
import shlex

# MOK package substitutions
# Key: original package, Value: MOK replacement
MOK_PACKAGE_SUBSTITUTIONS = {
    'linux': 'linux-mok',
    'linux-esx': 'linux-mok',  # ESX flavor -> MOK kernel
    'linux-aws': 'linux-mok',  # AWS flavor -> MOK kernel
    'linux-secure': 'linux-mok',  # Secure flavor -> MOK kernel
    'linux-rt': 'linux-mok',  # RT flavor -> MOK kernel
    'grub2-efi-image': 'grub2-efi-image-mok',
    'shim-signed': 'shim-signed-mok',
}

# Additional packages to add when MOK mode is active
MOK_ADDITIONAL_PACKAGES = [
    'shim-signed-mok',  # Ensure MokManager is installed
]


def is_mok_secureboot_mode():
    """
    Check if photon.secureboot=mok is present in kernel command line.
    
    Returns:
        bool: True if MOK secure boot mode is requested
    """
    try:
        with open('/proc/cmdline', 'r') as f:
            cmdline = f.read().strip()
        
        # Parse kernel parameters
        params = shlex.split(cmdline)
        for param in params:
            if param == 'photon.secureboot=mok':
                return True
            if param.startswith('photon.secureboot=') and param.split('=')[1] == 'mok':
                return True
    except Exception as e:
        print(f"[MOK-PATCH] Warning: Could not read /proc/cmdline: {e}")
    
    return False


def get_mok_package_name(original_package):
    """
    Get the MOK variant package name for a given package.
    
    Args:
        original_package: Original package name (may include version)
    
    Returns:
        str: MOK variant package name, or original if no substitution needed
    """
    # Handle versioned packages (e.g., linux=6.1.159-10.ph5)
    if '=' in original_package:
        name, version = original_package.split('=', 1)
        if name in MOK_PACKAGE_SUBSTITUTIONS:
            # Note: MOK packages have their own versioning, don't preserve version
            return MOK_PACKAGE_SUBSTITUTIONS[name]
        return original_package
    
    # Handle non-versioned packages
    if original_package in MOK_PACKAGE_SUBSTITUTIONS:
        return MOK_PACKAGE_SUBSTITUTIONS[original_package]
    
    return original_package


def apply_mok_substitution(packages, logger=None):
    """
    Apply MOK package substitutions to the package list.
    
    This function should be called after the installer builds the initial
    package list and before packages are installed.
    
    Args:
        packages: List of package names to install
        logger: Optional logger instance
    
    Returns:
        list: Modified package list with MOK substitutions applied
    """
    if not is_mok_secureboot_mode():
        if logger:
            logger.info("[MOK-PATCH] Standard secure boot mode (no MOK substitution)")
        return packages
    
    if logger:
        logger.info("[MOK-PATCH] MOK secure boot mode detected - applying package substitutions")
    else:
        print("[MOK-PATCH] MOK secure boot mode detected - applying package substitutions")
    
    # Create a new list with substitutions
    new_packages = []
    substituted = set()
    
    for pkg in packages:
        new_pkg = get_mok_package_name(pkg)
        if new_pkg != pkg:
            if logger:
                logger.info(f"[MOK-PATCH] Substituting: {pkg} -> {new_pkg}")
            else:
                print(f"[MOK-PATCH] Substituting: {pkg} -> {new_pkg}")
            substituted.add(pkg)
        new_packages.append(new_pkg)
    
    # Add any additional MOK packages that weren't already substituted
    for pkg in MOK_ADDITIONAL_PACKAGES:
        # Check if the original package was in the list
        original = None
        for orig, mok in MOK_PACKAGE_SUBSTITUTIONS.items():
            if mok == pkg:
                original = orig
                break
        
        # Only add if the original wasn't in the list and MOK package isn't already there
        if original not in substituted and pkg not in new_packages:
            if logger:
                logger.info(f"[MOK-PATCH] Adding additional MOK package: {pkg}")
            else:
                print(f"[MOK-PATCH] Adding additional MOK package: {pkg}")
            new_packages.append(pkg)
    
    # Remove duplicates while preserving order
    seen = set()
    result = []
    for pkg in new_packages:
        if pkg not in seen:
            seen.add(pkg)
            result.append(pkg)
    
    return result


def patch_installer_configure(original_configure):
    """
    Decorator to patch the Installer.configure() method.
    
    This wraps the original configure method to apply MOK substitutions
    after the package list is built.
    
    Args:
        original_configure: The original configure method
    
    Returns:
        function: Wrapped configure method
    """
    def patched_configure(self, install_config, ui_config=None):
        # Call original configure
        original_configure(self, install_config, ui_config)
        
        # Apply MOK substitutions if in MOK mode
        if is_mok_secureboot_mode():
            self.install_config['packages'] = apply_mok_substitution(
                self.install_config['packages'],
                logger=getattr(self, 'logger', None)
            )
    
    return patched_configure


# For testing
if __name__ == '__main__':
    print("Testing MOK Secure Boot Patch")
    print(f"MOK mode active: {is_mok_secureboot_mode()}")
    
    test_packages = [
        'linux',
        'grub2-efi-image',
        'bash',
        'systemd',
        'shim-signed',
    ]
    
    print(f"\nOriginal packages: {test_packages}")
    result = apply_mok_substitution(test_packages)
    print(f"After substitution: {result}")
