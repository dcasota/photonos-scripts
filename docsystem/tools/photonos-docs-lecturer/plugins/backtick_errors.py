#!/usr/bin/env python3
"""
Backtick Errors Plugin for Photon OS Documentation Lecturer

Detects and fixes spaces inside inline code backticks.
Handles unclosed inline code patterns.

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


class BacktickErrorsPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing backtick errors.
    
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "backtick_errors"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Fix backtick errors (spaces inside backticks)"
    REQUIRES_LLM = False
    FIX_ID = 5
    
    # Space after opening backtick: ` code`
    SPACE_AFTER_OPEN = re.compile(r'(?<![`\w])`[ \t]+(\S[^`\n]*?)`(?![`\w])')
    
    # Space before closing backtick: `code `
    SPACE_BEFORE_CLOSE = re.compile(r'(?<![`\w])`([^`\n]*?\S)[ \t]+`(?![`\w])')
    
    # Spaces on both sides: ` code `
    SPACES_BOTH = re.compile(r'(?<![`\w])`[ \t]+([^`\n]+?)[ \t]+`(?![`\w])')
    
    # Unclosed inline backtick at end of sentence
    UNCLOSED_INLINE = re.compile(r'`([^`\n]+)([.!?])(\s|$)')
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect backtick errors, excluding code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of backtick error issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        # Check for space after opening backtick
        for match in self.SPACE_AFTER_OPEN.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: `{' ' + match.group(1)[:20]}...",
                description="Space after opening backtick",
                suggestion=f"Remove space: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for space before closing backtick
        for match in self.SPACE_BEFORE_CLOSE.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: `{match.group(1)[:20]}...",
                description="Space before closing backtick",
                suggestion=f"Remove space: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for spaces on both sides
        for match in self.SPACES_BOTH.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: ` {match.group(1)[:20]}...",
                description="Spaces inside backticks on both sides",
                suggestion=f"Remove spaces: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply backtick error fixes, protecting code blocks.
        
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
        
        # Fix spaces on both sides (most specific pattern first)
        def fix_both_spaces(match):
            return f'`{match.group(1)}`'
        
        new_result, count = self.SPACES_BOTH.subn(fix_both_spaces, result)
        if count > 0:
            changes.append(f"Removed spaces from both sides in {count} instances")
            result = new_result
            self.increment_fixed(count)
        
        # Fix space after opening backtick
        def fix_space_after_open(match):
            return f'`{match.group(1)}`'
        
        new_result, count = self.SPACE_AFTER_OPEN.subn(fix_space_after_open, result)
        if count > 0:
            changes.append(f"Removed {count} spaces after opening backticks")
            result = new_result
            self.increment_fixed(count)
        
        # Fix space before closing backtick
        def fix_space_before_close(match):
            return f'`{match.group(1)}`'
        
        new_result, count = self.SPACE_BEFORE_CLOSE.subn(fix_space_before_close, result)
        if count > 0:
            changes.append(f"Removed {count} spaces before closing backticks")
            result = new_result
            self.increment_fixed(count)
        
        # Restore code blocks UNCHANGED
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
