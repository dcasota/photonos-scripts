#!/usr/bin/env python3
"""
Deprecated URL Plugin for Photon OS Documentation Lecturer

Detects and replaces deprecated URLs with their current equivalents.
Handles VMware, VDDK, OVFTOOL, AWS, bosh-stemcell, and Bintray URLs.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class DeprecatedUrlPlugin(BasePlugin):
    """Plugin for detecting and fixing deprecated URLs.
    
    Replaces outdated URLs with their current versions.
    """
    
    PLUGIN_NAME = "deprecated_url"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix deprecated URLs"
    REQUIRES_LLM = False
    FIX_ID = 3
    
    # URL replacements: (pattern, replacement, description)
    URL_REPLACEMENTS: List[Tuple[re.Pattern, str, str]] = [
        # VMware packages URL
        (
            re.compile(r'https?://packages\.vmware\.com/[^\s"\'<>]*'),
            'https://packages.broadcom.com/',
            'VMware packages URL deprecated'
        ),
        # VDDK URLs
        (
            re.compile(r'https?://my\.vmware\.com/web/vmware/downloads/details\?downloadGroup=VDDK670[^\s"\'<>]*'),
            'https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7',
            'VDDK download URL deprecated'
        ),
        (
            re.compile(r'https?://developercenter\.vmware\.com/web/sdk/60/vddk'),
            'https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7',
            'VDDK SDK URL deprecated'
        ),
        # OVFTOOL URL
        (
            re.compile(r'https?://my\.vmware\.com/group/vmware/details\?downloadGroup=OVFTOOL410[^\s"\'<>]*'),
            'https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest',
            'OVFTOOL URL deprecated'
        ),
        # AWS EC2 CLI URLs
        (
            re.compile(r'https?://docs\.aws\.amazon\.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux\.html'),
            'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html',
            'AWS EC2 CLI URL deprecated'
        ),
        # CloudFoundry bosh-stemcell URL
        (
            re.compile(r'https?://github\.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README\.md'),
            'https://github.com/cloudfoundry/bosh/blob/main/README.md',
            'Bosh-stemcell URL deprecated (branch changed)'
        ),
        # Bintray URLs (service discontinued)
        (
            re.compile(r'https?://(?:dl\.)?bintray\.com/[^\s"\'<>\)]*'),
            'https://github.com/vmware/photon/wiki/downloading-photon-os',
            'Bintray discontinued (2021)'
        ),
    ]
    
    # Full markdown link replacement for VDDK 6.0 -> 6.7
    VDDK_LINK_PATTERN = re.compile(r'\[VDDK 6\.0\]\(https://developercenter\.vmware\.com/web/sdk/60/vddk\)')
    VDDK_LINK_REPLACEMENT = '[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)'
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect deprecated URLs in content.
        
        Args:
            content: Markdown or HTML content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of deprecated URL issues
        """
        issues = []
        
        if not content:
            return issues
        
        for pattern, replacement, description in self.URL_REPLACEMENTS:
            for match in pattern.finditer(content):
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"URL: {match.group(0)[:50]}...",
                    description=description,
                    suggestion=f"Replace with: {replacement}",
                    context=match.group(0),
                    metadata={
                        'old_url': match.group(0),
                        'new_url': replacement
                    }
                )
                issues.append(issue)
        
        # Check for VDDK markdown link
        if self.VDDK_LINK_PATTERN.search(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location="VDDK 6.0 link",
                description="VDDK 6.0 link should be updated to 6.7",
                suggestion=f"Replace with: {self.VDDK_LINK_REPLACEMENT}",
                metadata={'type': 'vddk_link'}
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Replace deprecated URLs with current ones.
        
        Args:
            content: Content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with updated content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        result = content
        changes = []
        
        # Apply all URL replacements
        for pattern, replacement, description in self.URL_REPLACEMENTS:
            new_result, count = pattern.subn(replacement, result)
            if count > 0:
                changes.append(f"Replaced {count} {description}")
                result = new_result
                self.increment_fixed(count)
        
        # Fix VDDK markdown link
        new_result, count = self.VDDK_LINK_PATTERN.subn(self.VDDK_LINK_REPLACEMENT, result)
        if count > 0:
            changes.append(f"Updated {count} VDDK 6.0 links to 6.7")
            result = new_result
            self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
