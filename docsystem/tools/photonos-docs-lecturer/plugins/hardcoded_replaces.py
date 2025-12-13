#!/usr/bin/env python3
"""
Hardcoded Replaces Plugin for Photon OS Documentation Lecturer

Detects and fixes known typos and errors in documentation using a static list
of hardcoded replacements.

Two types of replacements:
1. STRUCTURAL_REPLACEMENTS - Applied BEFORE code block protection (modify code block structure)
2. REPLACEMENTS - Applied AFTER code block protection (regular text fixes)

Version: 1.1.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import (
    PatternBasedPlugin,
    Issue,
    FixResult,
    strip_code_blocks,
    protect_code_blocks,
    restore_code_blocks,
)

__version__ = "1.1.0"


class HardcodedReplacesPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing known typos and errors.
    
    Uses a static list of hardcoded original -> fixed replacements.
    Structural replacements (modifying code blocks) are applied first,
    then regular replacements are applied with code block protection.
    """
    
    PLUGIN_NAME = "hardcoded_replaces"
    PLUGIN_VERSION = "1.1.0"
    PLUGIN_DESCRIPTION = "Fix known typos and errors (hardcoded replacements)"
    REQUIRES_LLM = False
    FIX_ID = 3
    
    # Structural replacements that intentionally modify code block structure
    # These are applied BEFORE protect_code_blocks() since they need to fix
    # malformed code blocks, unclosed blocks, or convert inline code to blocks
    # Patterns must match EXACT byte-for-byte content including whitespace
    STRUCTURAL_REPLACEMENTS = [
        # Multiline: unclosed code block in build-cloud-images.md
        # Note: Uses "    \n" (4 spaces + newline) not empty newlines
        ("    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    \n    \n    \n   If you encounter",
         "    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    ```\n\n   If you encounter"),
        # Multiline: malformed inline code for export commands in build-cloud-images.md
        ("       `export LC_ALL=\"en_US.UTF-8\"`\n   ` export LC_CTYPE=\"en_US.UTF-8\"`",
         "   ```\n   export LC_ALL=\"en_US.UTF-8\"\n   export LC_CTYPE=\"en_US.UTF-8\"\n   ```"),
        # Multiline: fix numbering and code blocks for clone/make steps in build-cloud-images.md
        ("3.  Clone the Photon project:\n   \n    `git clone https://github.com/vmware/photon.git`\n    `cd $HOME/workspaces/photon`\n\n4. Make the cloud image for AMI. \n\n    \n    `sudo make image IMG_NAME=ami`\n\n4. Make the cloud image for Azure. \n  \n   \n    `sudo make image IMG_NAME=azure`\n\n4. Make the cloud image for GCE. \n    \n   \n    `sudo make image IMG_NAME=gce`",
         "4.  Clone the Photon project:\n\n    ```\n    git clone https://github.com/vmware/photon.git\n    cd $HOME/workspaces/photon\n    ```\n\n5. Make the cloud image for AMI. \n\n    `sudo make image IMG_NAME=ami`\n\n6. Make the cloud image for Azure. \n\n    `sudo make image IMG_NAME=azure`\n\n7. Make the cloud image for GCE. \n\n    `sudo make image IMG_NAME=gce`"),
    ]
    
    # Regular replacements: list of (original, fixed) tuples
    # These are applied AFTER protect_code_blocks() to preserve code block content
    REPLACEMENTS = [
        ("setttings", "settings"),
        ("the the", "the"),
        ("type 'quit´", "type ´quit´"),
        ("on a init.d-based Linux system", "on an init.d-based Linux system"),
        ("Clone`the Photon project", "Clone the Photon project"),
        ("followng", "following"),
        ("Photon OS, is an open-source minimalist Linux operating system", "Photon OS is an open-source minimalist Linux operating system"),
        ("`https://github.com/vmware/photon/tree/master/SPECS`", "https://github.com/vmware/photon/tree/master/SPECS"),
        ("during replication or deployment- power loss", "during replication or deployment power loss"),
        ("one can remote connect via ssh", "one can remotely connect via ssh"),
        ("run into the chicken and egg problem", "run into the chicken-and-egg problem"),
        ("presented in great detail that may be seem hard", "presented in great detail that may seem hard"),
        ("command to troubleshooting kernel errors", "command to troubleshoot kernel errors"),
        ("from external interfaces and  applications", "from external interfaces and applications"),
        ("Verify that that you have", "Verify that you have"),
        ("Shut down the Photon VM and copy its disk to THE", "Shut down the Photon VM and copy its disk to the"),
        ("Alternatively The `tdnf updateinfo info` command displays all", "Alternatively the `tdnf updateinfo info` command displays all"),
        ("Check if there are security updates for libssh2. note this is relative", "Check if there are security updates for libssh2. Note this is relative"),
        ("`ssh test_user@localhost`", "ssh test_user@localhost"),
        ("dockerd-rootless-setuptool.sh --help`", "dockerd-rootless-setuptool.sh --help"),
        ("dockerd-rootless-setuptool.sh`", "dockerd-rootless-setuptool.sh"),
        ("tdnf update ---sec-severity <level>", "tdnf update --sec-severity <level>"),
        ("The minimal version of Photon OS is lightweight container", "The minimal version of Photon OS is a lightweight container"),
        ("devloper", "developer"),
        ("contains information about the types of data sources and", "contain information about the types of data sources and"),
        ("VMWare", "VMware"),
        ("longer used if they were was installed by tdnf", "longer used if they were installed by tdnf"),
        ("verify that you have the performed the following tasks", "verify that you have performed the following tasks"),
        ("The following screen shot is an example", "The following screenshot is an example"),
        ("instance is to be deployed and, before clicking `Create,` check the", "instance is to be deployed, and before clicking `Create`, check the"),
        ("When you power on Raspberry Pi , it boots with Photon OS.", "When you power on Raspberry Pi, it boots with Photon OS."),
        ("the following command from  the kube-master", "the following command from the kube-master"),
        ("Bintray download page", "Download web page"),
        ("[Bintray]", "[Download web page]"),
    ]
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect hardcoded typos and errors.
        
        Detects both structural issues (in raw content) and regular text
        issues (excluding code blocks).
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of detected issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Check structural replacements on raw content (these target code block structure)
        for original, fixed in self.STRUCTURAL_REPLACEMENTS:
            if original in content:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Structural: {original[:50]}...",
                    description=f"Code block structure issue",
                    suggestion=f"Fix code block formatting",
                    context=original[:100]
                )
                issues.append(issue)
        
        # Check regular replacements on content with code blocks stripped
        safe_content = strip_code_blocks(content)
        
        for original, fixed in self.REPLACEMENTS:
            if original in safe_content:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Text: {original[:50]}",
                    description=f"Known typo/error: '{original}'",
                    suggestion=f"Replace with: '{fixed}'",
                    context=original
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply hardcoded replacements.
        
        Two-phase replacement:
        1. STRUCTURAL_REPLACEMENTS applied FIRST on raw content (fix code block structure)
        2. REPLACEMENTS applied on protected content (preserve code blocks)
        
        Args:
            content: Markdown content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        result = content
        changes = []
        total_fixes = 0
        
        # Phase 1: Apply structural replacements BEFORE protecting code blocks
        # These replacements intentionally modify code block structure
        for original, fixed in self.STRUCTURAL_REPLACEMENTS:
            if original in result:
                count = result.count(original)
                result = result.replace(original, fixed)
                total_fixes += count
                changes.append(f"Fixed code block structure ({count}x)")
        
        # Phase 2: Protect code blocks, then apply regular replacements
        protected_content, code_blocks = protect_code_blocks(result)
        
        for original, fixed in self.REPLACEMENTS:
            if original in protected_content:
                count = protected_content.count(original)
                protected_content = protected_content.replace(original, fixed)
                total_fixes += count
                changes.append(f"Replaced '{original[:30]}...' ({count}x)")
        
        if total_fixes > 0:
            self.increment_fixed(total_fixes)
        
        # Restore code blocks
        final_content = restore_code_blocks(protected_content, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
