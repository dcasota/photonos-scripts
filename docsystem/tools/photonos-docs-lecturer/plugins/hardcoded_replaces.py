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
         "    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    ```\n\n      If you encounter"),
        # Multiline: malformed inline code for export commands in build-cloud-images.md
        ("       `export LC_ALL=\"en_US.UTF-8\"`\n   ` export LC_CTYPE=\"en_US.UTF-8\"`",
         "      ```\n      export LC_ALL=\"en_US.UTF-8\"\n      export LC_CTYPE=\"en_US.UTF-8\"\n      ```"),
        # Multiline: fix numbering and code blocks for clone/make steps in build-cloud-images.md
        ("3.  Clone`the Photon project:\n   \n    `git clone https://github.com/vmware/photon.git`\n    `cd $HOME/workspaces/photon`\n\n4. Make the cloud image for AMI. \n\n    \n    `sudo make image IMG_NAME=ami`\n\n4. Make the cloud image for Azure. \n  \n   \n    `sudo make image IMG_NAME=azure`\n\n4. Make the cloud image for GCE. \n    \n   \n    `sudo make image IMG_NAME=gce`",
         "4.  Clone the Photon project:\n\n    ```\n    git clone https://github.com/vmware/photon.git\n    cd $HOME/workspaces/photon\n    ```\n\n5. Make the cloud image for AMI. \n\n    `sudo make image IMG_NAME=ami`\n\n6. Make the cloud image for Azure. \n\n    `sudo make image IMG_NAME=azure`\n\n7. Make the cloud image for GCE. \n\n    `sudo make image IMG_NAME=gce`"),
        # Multiline: remove code block wrapper around URL link
        ("    ```\n    [https://github.com/vmware/photon/blob/dev/photon-build-config.txt](https://github.com/vmware/photon/blob/dev/photon-build-config.txt)",
         "    [https://github.com/vmware/photon/blob/dev/photon-build-config.txt](https://github.com/vmware/photon/blob/dev/photon-build-config.txt)"),
        # Multiline: fix clone/make steps with proper code block and numbering (full pattern)
        ("5. Clone the Photon project:\n   \n    `git clone https://github.com/vmware/photon.git`\n     `cd $HOME/workspaces/photon`\n    \n\n6. Make ISO as follows:\n    \n   ` sudo make iso`\n\n\n5. Make Minimal ISO as follows:\n    \n    \n    `sudo make minimal-iso`\n    \n\n6. Make Real-Time ISO as follows:\n\n    `sudo make rt-iso `",
         "5. Clone the Photon project:\n\n    ```\n    git clone https://github.com/vmware/photon.git\n    cd $HOME/workspaces/photon\n    ```\n\n6. Make ISO as follows:\n    \n   `sudo make iso`\n\n\n7. Make Minimal ISO as follows:\n    \n    \n    `sudo make minimal-iso`\n    \n\n8. Make Real-Time ISO as follows:\n\n    `sudo make rt-iso`"),
        # Multiline: focused clone section only - converts inline code to fenced block
        ("5. Clone the Photon project:\n   \n    `git clone https://github.com/vmware/photon.git`\n     `cd $HOME/workspaces/photon`",
         "5. Clone the Photon project:\n\n    ```\n    git clone https://github.com/vmware/photon.git\n    cd $HOME/workspaces/photon\n    ```"),
        # Multiline: focused install pip + clone section (steps 3-4) - fixes unclosed code block and inline code
        ("3.  Install pip \n   \n    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    \n    \n    \n    If you encounter an error for LOCALE when you run these commands, then export the following variables in the terminal:\n    \n    \n        export LC_ALL=\"en_US.UTF-8\"\n    `export LC_CTYPE=\"en_US.UTF-8\"`\n\n\n4.  Clone the Photon project:\n  \n        git clone https://github.com/vmware/photon.git\n    `cd $HOME/workspaces/photon`",
         "3.  Install pip \n   \n    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    ```    \n    \n    \n    If you encounter an error for LOCALE when you run these commands, then export the following variables in the terminal:\n    \n    ```    \n    export LC_ALL=\"en_US.UTF-8\"\n    export LC_CTYPE=\"en_US.UTF-8\"\n    ```\n\n\n4.  Clone the Photon project:\n\n    ```  \n    git clone https://github.com/vmware/photon.git\n    cd $HOME/workspaces/photon\n    ```"),
        # Multiline: focused OVA build steps 6-11 - fixes inline code, numbering, and code blocks
        ("6. Search for `VMware-ovftool` in the same site and install it.\n\n   For example:\n\n   ovftool downloaded file:\n\n    `VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle`\n\n   Add exec permission and run it as sudo:\n\n    `  $ chmod +x VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle && sudo ./VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle --eulas-agreed --required`\n\n6. For VDDK, if the downloaded file is `VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz`, untar the downloaded tarball:\n\n    `$ tar xf VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz`\n\n7. Navigate to extracted directory.  \n\n- Move the header files to /usr/include\n\n    $ `sudo mv include/*.h /usr/include`\n\n\n- Move the shared libs to /usr/lib/vmware\n    `$ sudo mkdir -p /usr/lib/vmware && sudo mv lib64/* /usr/lib/vmware && sudo rm /usr/lib/vmware/libstdc++.so*`\n\n8.  Export /usr/lib/vmware library path(only for current session). Do this step every time you try to build an ova image.\n\n      `$ export LD_LIBRARY_PATH=/usr/lib/vmware`\n\n7. Navigate to your intended Photon source repository and run the following command. \n    ```\n    \n    `sudo make image IMG_NAME=ova`\n\n1. Make the image for OVA UEFI\n\n `sudo make image IMG_NAME=ova_uefi`",
         "6. Search for `VMware-ovftool` in the same site and install it.\n\n   For example:\n\n   ovftool downloaded file:\n\n    `VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle`\n\n   Add exec permission and run it as sudo:\n\n    ```\n    chmod +x VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle && sudo ./VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle --eulas-agreed --required\n    ```\n\n7. For VDDK, if the downloaded file is `VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz`, untar the downloaded tarball:\n\n    ```\n    tar xf VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz\n    ```\n\n8. Navigate to extracted directory.  \n\n   - Move the header files to /usr/include\n\n    ```\n    sudo mv include/*.h /usr/include\n    ```\n\n   - Move the shared libs to /usr/lib/vmware\n\n    ```\n    sudo mkdir -p /usr/lib/vmware && sudo mv lib64/* /usr/lib/vmware && sudo rm /usr/lib/vmware/libstdc++.so*\n    ```\n\n9.  Export /usr/lib/vmware library path(only for current session). Do this step every time you try to build an ova image.\n\n    ```\n    export LD_LIBRARY_PATH=/usr/lib/vmware\n    ```\n\n10. Navigate to your intended Photon source repository and run the following command.\n\n    ```\n    sudo make image IMG_NAME=ova\n    ```\n\n11. Make the image for OVA UEFI\n\n    ```\n    sudo make image IMG_NAME=ova_uefi\n    ```"),
        # Multiline: fix build-cloud-images OVA section with proper code blocks and numbering
        ("3.  Install pip \n   \n    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    \n    \n    \n    If you encounter an error for LOCALE when you run these commands, then export the following variables in the terminal:\n    \n    \n        export LC_ALL=\"en_US.UTF-8\"\n    `export LC_CTYPE=\"en_US.UTF-8\"`\n\n\n4.  Clone the Photon project:\n  \n        git clone https://github.com/vmware/photon.git\n    `cd $HOME/workspaces/photon`\n\n5. Download latest VDDK from below link:\n\n   [https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7 \"Link to VMware ovftool site\")\n\n6. Search for `VMware-ovftool` in the same site and install it.\n\n   For example:\n\n   ovftool downloaded file:\n\n    `VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle`\n\n   Add exec permission and run it as sudo:\n\n    `  $ chmod +x VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle && sudo ./VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle --eulas-agreed --required`\n\n6. For VDDK, if the downloaded file is `VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz`, untar the downloaded tarball:\n\n    `$ tar xf VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz`\n\n7. Navigate to extracted directory.  \n\n- Move the header files to /usr/include\n\n    $ `sudo mv include/*.h /usr/include`\n\n\n- Move the shared libs to /usr/lib/vmware\n    `$ sudo mkdir -p /usr/lib/vmware && sudo mv lib64/* /usr/lib/vmware && sudo rm /usr/lib/vmware/libstdc++.so*`\n\n8.  Export /usr/lib/vmware library path(only for current session). Do this step every time you try to build an ova image.\n\n      `$ export LD_LIBRARY_PATH=/usr/lib/vmware`\n\n7. Navigate to your intended Photon source repository and run the following command. \n    ```\n    \n    `sudo make image IMG_NAME=ova`\n\n1. Make the image for OVA UEFI\n\n `sudo make image IMG_NAME=ova_uefi`",
         "3.  Install pip \n   \n    ```\n    sudo apt install python3-pip\n    pip3 install git+https://github.com/vmware/photon-os-installer.git\n    git clone https://github.com/vmware/photon.git\n    ```    \n    \n    \n    If you encounter an error for LOCALE when you run these commands, then export the following variables in the terminal:\n    \n    ```    \n    export LC_ALL=\"en_US.UTF-8\"\n    export LC_CTYPE=\"en_US.UTF-8\"`\n    ```\n\n4.  Clone the Photon project:\n\n    ```  \n    git clone https://github.com/vmware/photon.git\n    cd $HOME/workspaces/photon\n    ```\n\n5.  Download latest VDDK from below link:\n\n    [https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)\n\n6.  Search for `VMware-ovftool` and install it.\n\n    [https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest](https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest)\n\n    For example:\n\n    ovftool downloaded file:\n\n    `VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle`\n\n    Add exec permission and run it as sudo:\n    ```\n    chmod +x VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle\n    sudo ./VMware-ovftool-4.3.0-13981069-lin.x86_64.bundle --eulas-agreed --required\n    ```\n\n6. For VDDK, if the downloaded file is `VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz`, untar the downloaded tarball:\n\n    ```\n    tar xf VMware-vix-disklib-6.7.0-8173251.x86_64.tar.gz\n    ```\n\n7. Navigate to extracted directory.  \n\n   - Move the header files to /usr/include\n\n    ```\n    sudo mv include/*.h /usr/include\n    ```\n\n\n   - Move the shared libs to /usr/lib/VMware\n\n    ```\n    sudo mkdir -p /usr/lib/vmware && sudo mv lib64/* /usr/lib/vmware && sudo rm /usr/lib/vmware/libstdc++.so*\n    ```\n\n8.  Export /usr/lib/vmware library path(only for current session). Do this step every time you try to build an ova image.\n\n    ```\n    export LD_LIBRARY_PATH=/usr/lib/VMware\n    ```\n\n9. Navigate to your intended Photon source repository and run the following command.\n\n    ```\n    sudo make image IMG_NAME=ova\n    ```\n\n10. Make the image for OVA UEFI\n\n    ```\n    sudo make image IMG_NAME=ova_uefi\n    ```"),
        # Multiline: Replace VMware packages download text with Broadcom download link
        # Converts two-line format (text + bare link) to single line with inline link
        ("You can obtain the Photon OS ISO for free from VMware at the following URL: \n\n[https://packages.vmware.com/photon](https://packages.vmware.com/photon)",
         "You can obtain the Photon OS ISO for free from the [Broadcom Photon OS download webpage](https://github.com/vmware/photon/wiki/Downloading-Photon-OS)."),
        # Multiline: Replace deprecated Bintray download with GitHub wiki link
        # Converts indented link format to inline link with proper text
        # Pattern matches the full "1. Download Photon OS. Go to the following..." format
        ("1. Download Photon OS. Go to the following Bintray URL and download the latest release of Photon OS:\n\n    [https://bintray.com/vmware/photon/](https://bintray.com/vmware/photon/)",
         "1. Download Photon OS. Go to the [Photon OS download URL](https://github.com/vmware/photon/wiki/downloading-photon-os) and download the latest release of Photon OS."),
        # Fix broken local .md link to use proper Hugo relative path
        ("For instructions, see [Downloading Photon OS](Downloading-Photon-OS.md).",
         "For instructions, see [Downloading Photon OS](../../downloading-photon/)."),
        ("For instructions, see [Downloading Photon OS](downloading-photon-os).",                                                                                                                                         "For instructions, see [Downloading Photon OS](../../downloading-photon/)."),
        # Fix HTML table cell with deprecated Bintray download link
        ('<td>Photon OS ISO or OVA file downloaded from bintray (<a href="https://bintray.com/vmware/photon/">https://bintray.com/vmware/photon/</a>).</td>',
         '<td>Photon OS ISO or OVA file downloaded from <a href="https://github.com/vmware/photon/wiki/Downloading-Photon-OS/">Broadcom Photon OS download webpage</a>.</td>'),
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
        ("for free from Bintray at the following URL", "for free at the following URL"),
        ("for free from VMware at the following URL", "for free at the following URL"),
        # Full markdown link replacements for VMware/Broadcom packages (must come before partial replacements)
        ("[VMware Photon Packages](https://packages.vmware.com/photon)", "[Broadcom Photon OS packages](https://packages.broadcom.com/photon)"),
        ("[Vmware Photon Packages website](https://packages.vmware.com/photon/)", "[Broadcom Photon OS download webpage](https://github.com/vmware/photon/wiki/Downloading-Photon-OS)"),
        ("[VMware Packages](https://packages.vmware.com/photon)", "[Broadcom Photon OS packages](https://packages.broadcom.com/photon)"),
        ("[https://packages.vmware.com/photon](https://packages.vmware.com/photon)", "[Broadcom packages repository](https://packages.broadcom.com/photon)"),
        # Handle full string with VMWare (capital W) - original incorrect spelling
        ("VMWare Packages repository: [packages.vmware.com/photon](https://packages.vmware.com/photon)", "[Broadcom Photon OS packages repository](https://packages.broadcom.com/photon)."),
        # Handle full string with VMware (correct spelling) - after spelling fix has run
        ("VMware Packages repository: [packages.vmware.com/photon](https://packages.vmware.com/photon)", "[Broadcom Photon OS packages repository](https://packages.broadcom.com/photon)"),
        # Handle original link where both link text and URL are still vmware.com
        ("[packages.vmware.com/photon](https://packages.vmware.com/photon)", "[packages.broadcom.com/photon](https://packages.broadcom.com/photon)"),
        # Handle partially updated links where URL was changed but link text wasn't
        ("[packages.vmware.com/photon](https://packages.broadcom.com/photon)", "[packages.broadcom.com/photon](https://packages.broadcom.com/photon)"),
        # Handle case where spelling was fixed AND URL was partially updated (href changed, text not)
        # Partial link text replacements (only if full link replacement didn't match)
        ("[VMware Photon Packages]", "[Broadcom Photon OS packages]"),
        ("[VMware Packages]", "[Broadcom Photon OS packages]"),
        ("VMWare Packages repository", "Broadcom packages repository"),
        ("VMware Packages repository", "Broadcom packages repository"),
        ("uses from the  Packages location", "uses from the packages location"),
        # AWS EC2 CLI URL replacement - FULL markdown link replacement
        # This replaces the entire markdown link including link text to update both URL and description
        # The old EC2 CLI documentation is deprecated, replaced by general AWS CLI install guide
        ("[Setting Up the Amazon EC2 Command Line Interface Tools on Linux](http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html)",
         "[Installing the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"),
        ("[Setting Up the Amazon EC2 Command Line Interface Tools on Linux](https://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html)",
         "[Installing the AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)"),
        # AWS EC2 CLI URL replacement (bare URLs, both http and https variants)
        # Fallback for cases where only the URL appears without markdown link syntax
        ("http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html", "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"),
        ("https://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html", "https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"),
        # CloudFoundry bosh-stemcell URL replacement (both with and without .md extension)
        # The .md-less variant handles cases where installer-weblinkfixes.sh stripped the extension
        # Also handles URLs inside HTML comments which BeautifulSoup doesn't detect
        ("https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md", "https://github.com/cloudfoundry/bosh-linux-stemcell-builder"),
        ("https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README", "https://github.com/cloudfoundry/bosh-linux-stemcell-builder"),
        # Fix duplicate 16GB recommendation text
        ("16GB is recommended; 16GB recommended.", "16GB is recommended."),
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
