#!/usr/bin/env python3
"""
Install Tools Module for Photon OS Documentation Lecturer

Provides functionality to install required dependencies (Java, Python packages).

Version: 1.0.0
"""

from __future__ import annotations

import subprocess
import sys
from typing import List, Tuple

__version__ = "1.0.0"

# Tool info (will be set from main module)
TOOL_NAME = "photonos-docs-lecturer.py"
VERSION = "2.4"


def set_tool_info(tool_name: str, version: str):
    """Set tool name and version from main module."""
    global TOOL_NAME, VERSION
    TOOL_NAME = tool_name
    VERSION = version


def check_admin_privileges() -> bool:
    """Check if running with admin/root privileges."""
    import os
    return os.geteuid() == 0


def install_tools() -> int:
    """Install required tools: Java and language-tool-python.
    
    Returns:
        0 on success, 1 on failure
    """
    print(f"{TOOL_NAME} v{VERSION} - Install Tools")
    print()
    
    # Check for admin privileges
    if not check_admin_privileges():
        print("[ERROR] Administrative privileges required to install tools.", file=sys.stderr)
        print("        Please run as root or with sudo:", file=sys.stderr)
        print(f"        sudo python3 {TOOL_NAME} install-tools", file=sys.stderr)
        return 1
    
    print("[INFO] Running with administrative privileges")
    print()
    
    success = True
    
    # Install Java using tdnf (Photon OS package manager)
    # LanguageTool requires Java >= 17
    print("[STEP 1/3] Installing Java >= 17 (required for LanguageTool)...")
    java_ok = False
    java_version = None
    
    # Check if Java is already installed and get version
    try:
        result = subprocess.run(['java', '-version'], capture_output=True, text=True)
        if result.returncode == 0:
            # Java version is typically in stderr, format: 'openjdk version "21.0.x"' or 'java version "17.0.x"'
            version_output = result.stderr or result.stdout
            # Parse version number
            import re
            version_match = re.search(r'version\s+"?(\d+)(?:\.(\d+))?', version_output)
            if version_match:
                major_version = int(version_match.group(1))
                java_version = major_version
                if major_version >= 17:
                    print(f"[OK] Java {major_version} is installed (meets requirement >= 17)")
                    java_ok = True
                else:
                    print(f"[WARN] Java {major_version} is installed but version >= 17 is required")
    except FileNotFoundError:
        print("[INFO] Java is not installed")
    
    if not java_ok:
        print("[INFO] Installing openjdk21 via tdnf...")
        try:
            subprocess.run(['tdnf', 'install', '-y', 'openjdk21'], check=True)
            print("[OK] Java (openjdk21) installed via tdnf")
            java_ok = True
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to install openjdk21 via tdnf: {e}", file=sys.stderr)
            success = False
    
    if not java_ok:
        print("[WARN] Java >= 17 installation failed. LanguageTool requires Java >= 17.", file=sys.stderr)
        success = False
    
    # Step 2: Ensure pip is available
    print()
    print("[STEP 2/3] Ensuring pip is available...")
    pip_available = False
    
    try:
        result = subprocess.run([sys.executable, '-m', 'pip', '--version'], capture_output=True, text=True)
        if result.returncode == 0:
            print("[OK] pip is available")
            pip_available = True
    except Exception:
        pass
    
    if not pip_available:
        print("[INFO] Installing pip...")
        try:
            subprocess.run([sys.executable, '-m', 'ensurepip', '--default-pip'], check=True)
            print("[OK] pip installed")
            pip_available = True
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to install pip: {e}", file=sys.stderr)
            success = False
    
    # Step 3: Install required Python packages
    print()
    print("[STEP 3/3] Installing required Python packages...")
    
    # List of required packages: (pip_name, display_name)
    required_packages: List[Tuple[str, str]] = [
        ('requests', 'requests'),
        ('beautifulsoup4', 'beautifulsoup4 (bs4)'),
        ('lxml', 'lxml'),
        ('language-tool-python', 'language-tool-python'),
        ('Pillow', 'Pillow (PIL)'),
        ('tqdm', 'tqdm'),
        ('google-generativeai', 'google-generativeai (for --llm gemini)'),
    ]
    
    if pip_available:
        for pip_name, display_name in required_packages:
            try:
                # Check if already installed
                result = subprocess.run(
                    [sys.executable, '-m', 'pip', 'show', pip_name],
                    capture_output=True, text=True
                )
                if result.returncode == 0:
                    print(f"[OK] {display_name} is already installed")
                else:
                    # Install package
                    print(f"[INFO] Installing {display_name}...")
                    subprocess.run(
                        [sys.executable, '-m', 'pip', 'install', pip_name],
                        check=True
                    )
                    print(f"[OK] {display_name} installed")
            except subprocess.CalledProcessError as e:
                print(f"[ERROR] Failed to install {display_name}: {e}", file=sys.stderr)
                success = False
    else:
        print("[ERROR] Cannot install Python packages without pip", file=sys.stderr)
        success = False
    
    # Summary
    print()
    if success:
        print("=" * 50)
        print("[OK] All tools installed successfully!")
        print()
        print("You can now use the analyzer:")
        print(f"  python3 {TOOL_NAME} analyze --website https://127.0.0.1/docs-v5")
        print("=" * 50)
        return 0
    else:
        print("=" * 50)
        print("[WARN] Some tools failed to install. Please check errors above.")
        print("=" * 50)
        return 1


if __name__ == "__main__":
    sys.exit(install_tools())
