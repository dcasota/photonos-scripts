#!/usr/bin/env python3
"""
Deprecated URL Plugin for Photon OS Documentation Lecturer

Detects and fixes deprecated URLs (VMware, VDDK, OVFTOOL, AWS, Bintray, etc.).

CRITICAL: All operations protect fenced code blocks from modification.

Version: 2.2.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from .base import (
    PatternBasedPlugin,
    Issue,
    FixResult,
    strip_code_blocks,
    protect_code_blocks,
    restore_code_blocks,
)

__version__ = "2.2.0"


class DeprecatedUrlPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing deprecated URLs.
    
    Handles: VMware packages, VDDK, OVFTOOL, AWS EC2 CLI, bosh-stemcell, Bintray.
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "deprecated_url"
    PLUGIN_VERSION = "2.2.0"
    PLUGIN_DESCRIPTION = "Fix deprecated URLs (VMware, VDDK, AWS, Bintray)"
    REQUIRES_LLM = False
    FIX_ID = 2
    
    # Simple URL replacements: (old_url, new_url, description)
    URL_REPLACEMENTS: List[Tuple[str, str, str]] = [
        # VDDK URLs
        ('https://my.vmware.com/web/vmware/downloads/details?downloadGroup=VDDK670&productId=742',
         'https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7',
         'Deprecated VDDK URL'),
        ('https://developercenter.vmware.com/web/sdk/60/vddk',
         'https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7',
         'Deprecated VDDK URL'),
        # VDDK markdown link
        ('[VDDK 6.0](https://developercenter.vmware.com/web/sdk/60/vddk)',
         '[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)',
         'Deprecated VDDK 6.0 link'),
        # OVFTOOL URL
        ('https://my.vmware.com/group/vmware/details?downloadGroup=OVFTOOL410&productId=491',
         'https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest',
         'Deprecated OVFTOOL URL'),
        # CloudFoundry bosh-stemcell URL
        ('https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md',
         'https://github.com/cloudfoundry/bosh-linux-stemcell-builder',
         'Deprecated bosh-stemcell URL'),
        # Malformed URLs (typos with ./ in path)
        ('https://cloud.google.com/compute./tutorials/building-images',
         'https://cloud.google.com/compute/docs/tutorials/building-images',
         'Malformed URL (typo in path)'),
        ('https://github.com/vmware/photon-os-installer/blob/master./ks_config.md',
         'https://github.com/vmware/photon-os-installer/blob/master/docs/ks_config.md',
         'Malformed URL (typo in path)'),
    ]
    
    # Regex-based URL patterns: (pattern, replacement_or_none, description)
    # If replacement is a string, use subn directly
    # If replacement is None, use custom logic in fix() method
    REGEX_REPLACEMENTS: List[Tuple[re.Pattern, Optional[str], str]] = [
        # VMware packages URL pattern - replacement preserves path (handled specially in fix())
        # Pattern excludes ] and ) to properly handle markdown links like [url](url)
        # Each URL in the markdown link is matched separately
        # NOTE: hardcoded_replaces runs FIRST and handles specific full-string replacements
        (re.compile(r'https?://packages\.vmware\.com(/[^\s"\'<>\]\)]*)?'),
         None,  # Special handling to preserve path
         'Deprecated VMware packages URL'),
        # AWS EC2 CLI URL pattern
        (re.compile(r'https?://docs\.aws\.amazon\.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux\.html'),
         'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html',
         'Deprecated AWS EC2 CLI URL'),
        # Bintray URLs (service discontinued in 2021)
        (re.compile(r'https?://(?:dl\.)?bintray\.com/[^\s\)\"\']*', re.IGNORECASE),
         'https://github.com/vmware/photon/wiki/downloading-photon-os',
         'Deprecated Bintray URL'),
    ]
    
    # Pattern for VMware packages URL with path capture
    # Pattern excludes ] and ) to properly handle markdown links like [url](url)
    # Each URL in the markdown link is matched separately
    VMWARE_PACKAGES_PATTERN = re.compile(r'https?://packages\.vmware\.com(/[^\s"\'<>\]\)]*)?')
    
    def _replace_url(self, content: str, old_url: str, new_url: str) -> Tuple[str, bool]:
        """Replace a single URL in content. Returns (modified_content, was_changed)."""
        if old_url in content:
            return content.replace(old_url, new_url), True
        return content, False
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect deprecated URLs, excluding code blocks."""
        issues = []
        
        if not content:
            return issues
        
        safe_content = strip_code_blocks(content)
        
        # Check simple URL replacements
        for old_url, new_url, description in self.URL_REPLACEMENTS:
            if old_url in safe_content:
                issues.append(Issue(
                    category=self.PLUGIN_NAME,
                    location=f"URL: {old_url[:50]}",
                    description=description,
                    suggestion=f"Replace with: {new_url}",
                    context=old_url
                ))
        
        # Check regex-based URL patterns
        for pattern, replacement, description in self.REGEX_REPLACEMENTS:
            for match in pattern.finditer(safe_content):
                issues.append(Issue(
                    category=self.PLUGIN_NAME,
                    location=f"URL: {match.group(0)[:50]}",
                    description=description,
                    suggestion=f"Replace with: {replacement}",
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
        
        # Apply simple URL replacements
        for old_url, new_url, description in self.URL_REPLACEMENTS:
            result, changed = self._replace_url(result, old_url, new_url)
            if changed:
                changes.append(f"Fixed: {description}")
        
        # Apply regex-based replacements
        for pattern, replacement, description in self.REGEX_REPLACEMENTS:
            if replacement is None:
                # Special handling for VMware packages URL - preserve path
                if 'VMware packages' in description:
                    def replace_vmware_url(match):
                        path = match.group(1) if match.group(1) else ''
                        # Handle trailing ) that might be markdown link delimiter
                        # If path ends with ) and there's a matching ( earlier, it's part of URL
                        # Otherwise, it's likely a markdown link closer
                        if path.endswith(')'):
                            # Count parentheses to determine if ) is balanced
                            open_count = path.count('(')
                            close_count = path.count(')')
                            if close_count > open_count:
                                # Extra ) is likely markdown delimiter, don't include it
                                path = path[:-1]
                        return f'https://packages.broadcom.com{path}'
                    new_result, count = pattern.subn(replace_vmware_url, result)
                    if count > 0:
                        changes.append(f"Fixed {count} {description}(s)")
                        result = new_result
            else:
                new_result, count = pattern.subn(replacement, result)
                if count > 0:
                    changes.append(f"Fixed {count} {description}(s)")
                    result = new_result

        self.increment_fixed(len(changes))
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
