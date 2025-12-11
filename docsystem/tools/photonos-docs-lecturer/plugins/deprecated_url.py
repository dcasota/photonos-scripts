#!/usr/bin/env python3
"""
Deprecated URL Plugin for Photon OS Documentation Lecturer

Detects and fixes deprecated URLs (e.g., Bintray URLs).

CRITICAL: All operations protect fenced code blocks from modification.

Version: 2.0.0
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

__version__ = "2.0.0"


class DeprecatedUrlPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing deprecated URLs.
    
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "deprecated_url"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Fix deprecated URLs (Bintray, etc.)"
    REQUIRES_LLM = False
    FIX_ID = 13
    
    # Bintray URLs (service discontinued in 2021)
    BINTRAY_PATTERN = re.compile(
        r'https?://(?:dl\.)?bintray\.com/vmware/photon[^\s\)\"\']*',
        re.IGNORECASE
    )
    BINTRAY_REPLACEMENT = "https://github.com/vmware/photon/wiki/downloading-photon-os"
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect deprecated URLs, excluding code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of deprecated URL issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        # Check for Bintray URLs
        for match in self.BINTRAY_PATTERN.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"URL: {match.group(0)[:50]}",
                description="Deprecated Bintray URL (service discontinued 2021)",
                suggestion=f"Replace with: {self.BINTRAY_REPLACEMENT}",
                context=match.group(0)
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply deprecated URL fixes, protecting code blocks.
        
        CRITICAL: Code blocks are protected and restored unchanged.
        
        Args:
            content: Markdown content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        # Protect code blocks FIRST
        protected_content, code_blocks = protect_code_blocks(content)
        
        result = protected_content
        changes = []
        
        # Fix Bintray URLs
        new_result, count = self.BINTRAY_PATTERN.subn(self.BINTRAY_REPLACEMENT, result)
        if count > 0:
            changes.append(f"Replaced {count} deprecated Bintray URLs")
            result = new_result
            self.increment_fixed(count)
        
        # Restore code blocks UNCHANGED
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
