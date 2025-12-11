#!/usr/bin/env python3
"""
Deprecated URL Plugin for Photon OS Documentation Lecturer

Detects and fixes deprecated URLs (VMware, VDDK, OVFTOOL, AWS, Bintray, etc.).

CRITICAL: All operations protect fenced code blocks from modification.

Version: 2.1.0
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

__version__ = "2.1.0"


class DeprecatedUrlPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing deprecated URLs.
    
    Handles: VMware packages, VDDK, OVFTOOL, AWS EC2 CLI, bosh-stemcell, Bintray.
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "deprecated_url"
    PLUGIN_VERSION = "2.1.0"
    PLUGIN_DESCRIPTION = "Fix deprecated URLs (VMware, VDDK, AWS, Bintray)"
    REQUIRES_LLM = False
    FIX_ID = 13
    
    # Deprecated VMware packages URL pattern
    DEPRECATED_VMWARE_URL = re.compile(r'https?://packages\.vmware\.com/[^\s"\'<>]*')
    VMWARE_URL_REPLACEMENT = 'https://packages.broadcom.com/'
    
    # Deprecated VDDK download URLs
    DEPRECATED_VDDK_URLS = [
        'https://my.vmware.com/web/vmware/downloads/details?downloadGroup=VDDK670&productId=742',
        'https://developercenter.vmware.com/web/sdk/60/vddk'
    ]
    VDDK_URL_REPLACEMENT = 'https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7'
    DEPRECATED_VDDK_60_LINK = '[VDDK 6.0](https://developercenter.vmware.com/web/sdk/60/vddk)'
    VDDK_67_LINK_REPLACEMENT = '[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)'
    
    # Deprecated OVFTOOL URL
    DEPRECATED_OVFTOOL_URL = 'https://my.vmware.com/group/vmware/details?downloadGroup=OVFTOOL410&productId=491'
    OVFTOOL_URL_REPLACEMENT = 'https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest'
    
    # Deprecated AWS EC2 CLI URLs
    DEPRECATED_AWS_EC2_CLI_URLS = [
        'http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html',
        'https://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html'
    ]
    AWS_EC2_CLI_URL_REPLACEMENT = 'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'
    
    # Deprecated CloudFoundry bosh-stemcell URL
    DEPRECATED_BOSH_STEMCELL_URL = 'https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md'
    BOSH_STEMCELL_URL_REPLACEMENT = 'https://github.com/cloudfoundry/bosh/blob/main/README.md'
    
    # Bintray URLs (service discontinued in 2021)
    BINTRAY_PATTERN = re.compile(
        r'https?://(?:dl\.)?bintray\.com/[^\s\)\"\']*',
        re.IGNORECASE
    )
    BINTRAY_REPLACEMENT = "https://github.com/vmware/photon/wiki/downloading-photon-os"
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect deprecated URLs, excluding code blocks."""
        issues = []
        
        if not content:
            return issues
        
        safe_content = strip_code_blocks(content)
        
        # Check VMware packages URLs
        for match in self.DEPRECATED_VMWARE_URL.finditer(safe_content):
            issues.append(Issue(
                category=self.PLUGIN_NAME,
                location=f"URL: {match.group(0)[:50]}",
                description="Deprecated VMware packages URL",
                suggestion=f"Replace with Broadcom URL",
                context=match.group(0)
            ))
        
        # Check VDDK URLs
        for vddk_url in self.DEPRECATED_VDDK_URLS:
            if vddk_url in safe_content:
                issues.append(Issue(
                    category=self.PLUGIN_NAME,
                    location=f"URL: {vddk_url[:50]}",
                    description="Deprecated VDDK URL",
                    suggestion=f"Replace with: {self.VDDK_URL_REPLACEMENT}",
                    context=vddk_url
                ))
        
        # Check OVFTOOL URL
        if self.DEPRECATED_OVFTOOL_URL in safe_content:
            issues.append(Issue(
                category=self.PLUGIN_NAME,
                location="OVFTOOL URL",
                description="Deprecated OVFTOOL URL",
                suggestion=f"Replace with: {self.OVFTOOL_URL_REPLACEMENT}",
                context=self.DEPRECATED_OVFTOOL_URL
            ))
        
        # Check AWS EC2 CLI URLs
        for aws_url in self.DEPRECATED_AWS_EC2_CLI_URLS:
            if aws_url in safe_content:
                issues.append(Issue(
                    category=self.PLUGIN_NAME,
                    location=f"URL: {aws_url[:50]}",
                    description="Deprecated AWS EC2 CLI URL",
                    suggestion=f"Replace with: {self.AWS_EC2_CLI_URL_REPLACEMENT}",
                    context=aws_url
                ))
        
        # Check bosh-stemcell URL
        if self.DEPRECATED_BOSH_STEMCELL_URL in safe_content:
            issues.append(Issue(
                category=self.PLUGIN_NAME,
                location="bosh-stemcell URL",
                description="Deprecated bosh-stemcell URL (develop -> main branch)",
                suggestion=f"Replace with: {self.BOSH_STEMCELL_URL_REPLACEMENT}",
                context=self.DEPRECATED_BOSH_STEMCELL_URL
            ))
        
        # Check Bintray URLs
        for match in self.BINTRAY_PATTERN.finditer(safe_content):
            issues.append(Issue(
                category=self.PLUGIN_NAME,
                location=f"URL: {match.group(0)[:50]}",
                description="Deprecated Bintray URL (service discontinued 2021)",
                suggestion=f"Replace with: {self.BINTRAY_REPLACEMENT}",
                context=match.group(0)
            ))
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply deprecated URL fixes, protecting code blocks."""
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        protected_content, code_blocks = protect_code_blocks(content)
        result = protected_content
        changes = []
        
        # Fix VMware packages URLs
        def replace_vmware_url(match):
            old_url = match.group(0)
            path_match = re.search(r'packages\.vmware\.com(/[^\s"\'<>]*)?', old_url)
            if path_match:
                path = path_match.group(1) or ''
                return f'https://packages.broadcom.com{path}'
            return old_url
        
        new_result = self.DEPRECATED_VMWARE_URL.sub(replace_vmware_url, result)
        if new_result != result:
            changes.append("Replaced VMware packages URLs with Broadcom URLs")
            result = new_result
        
        # Fix VDDK URLs (markdown link first, then plain URLs)
        if self.DEPRECATED_VDDK_60_LINK in result:
            result = result.replace(self.DEPRECATED_VDDK_60_LINK, self.VDDK_67_LINK_REPLACEMENT)
            changes.append("Replaced VDDK 6.0 link with VDDK 6.7")
        
        for vddk_url in self.DEPRECATED_VDDK_URLS:
            if vddk_url in result:
                result = result.replace(vddk_url, self.VDDK_URL_REPLACEMENT)
                changes.append("Replaced deprecated VDDK URL")
        
        # Fix AWS EC2 CLI URLs
        for aws_url in self.DEPRECATED_AWS_EC2_CLI_URLS:
            if aws_url in result:
                result = result.replace(aws_url, self.AWS_EC2_CLI_URL_REPLACEMENT)
                changes.append("Replaced deprecated AWS EC2 CLI URL")
        
        # Fix OVFTOOL URL
        if self.DEPRECATED_OVFTOOL_URL in result:
            result = result.replace(self.DEPRECATED_OVFTOOL_URL, self.OVFTOOL_URL_REPLACEMENT)
            changes.append("Replaced deprecated OVFTOOL URL")
        
        # Fix bosh-stemcell URL
        if self.DEPRECATED_BOSH_STEMCELL_URL in result:
            result = result.replace(self.DEPRECATED_BOSH_STEMCELL_URL, self.BOSH_STEMCELL_URL_REPLACEMENT)
            changes.append("Replaced deprecated bosh-stemcell URL")
        
        # Fix Bintray URLs
        new_result, count = self.BINTRAY_PATTERN.subn(self.BINTRAY_REPLACEMENT, result)
        if count > 0:
            changes.append(f"Replaced {count} deprecated Bintray URLs")
            result = new_result
        
        self.increment_fixed(len(changes))
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
