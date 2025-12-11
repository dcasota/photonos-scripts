#!/usr/bin/env python3
"""
Spelling Plugin for Photon OS Documentation Lecturer

Detects and fixes incorrect VMware/Photon spelling variants.

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


class SpellingPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing spelling issues.
    
    Focuses on VMware/Photon-specific terms.
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "spelling"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Fix incorrect VMware/Photon spelling"
    REQUIRES_LLM = False
    FIX_ID = 14
    
    # VMware spelling variants (incorrect -> correct)
    VMWARE_PATTERNS = [
        (re.compile(r'\bVmware\b'), 'VMware'),
        (re.compile(r'\bvmware\b(?!\.com)'), 'VMware'),
        (re.compile(r'\bVMWare\b'), 'VMware'),
        (re.compile(r'\bVMWARE\b'), 'VMware'),
    ]
    
    # Photon OS spelling
    PHOTON_PATTERNS = [
        (re.compile(r'\bphoton os\b', re.IGNORECASE), 'Photon OS'),
        (re.compile(r'\bPhoton os\b'), 'Photon OS'),
        (re.compile(r'\bphoton OS\b'), 'Photon OS'),
    ]
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect spelling issues, excluding code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of spelling issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        # Check VMware patterns
        for pattern, correct in self.VMWARE_PATTERNS:
            for match in pattern.finditer(safe_content):
                if match.group(0) != correct:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Position {match.start()}",
                        description=f"Incorrect spelling: {match.group(0)}",
                        suggestion=f"Replace with: {correct}",
                        context=match.group(0)
                    )
                    issues.append(issue)
        
        # Check Photon patterns
        for pattern, correct in self.PHOTON_PATTERNS:
            for match in pattern.finditer(safe_content):
                if match.group(0) != correct:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Position {match.start()}",
                        description=f"Incorrect spelling: {match.group(0)}",
                        suggestion=f"Replace with: {correct}",
                        context=match.group(0)
                    )
                    issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply spelling fixes, protecting code blocks.
        
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
        total_fixes = 0
        
        # Fix VMware patterns
        for pattern, correct in self.VMWARE_PATTERNS:
            new_result, count = pattern.subn(correct, result)
            if count > 0:
                total_fixes += count
                result = new_result
        
        # Fix Photon patterns
        for pattern, correct in self.PHOTON_PATTERNS:
            new_result, count = pattern.subn(correct, result)
            if count > 0:
                total_fixes += count
                result = new_result
        
        if total_fixes > 0:
            changes.append(f"Fixed {total_fixes} spelling issues")
            self.increment_fixed(total_fixes)
        
        # Restore code blocks UNCHANGED
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
