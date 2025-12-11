#!/usr/bin/env python3
"""
Backtick Errors Plugin for Photon OS Documentation Lecturer

Detects and fixes spaces inside inline code backticks.
Handles unclosed inline code and fenced code blocks.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class BacktickErrorsPlugin(BasePlugin):
    """Plugin for detecting and fixing backtick errors.
    
    Handles spaces inside backticks and unclosed code blocks.
    """
    
    PLUGIN_NAME = "backtick_errors"
    PLUGIN_VERSION = "1.0.0"
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
    
    # Valid inline code characters (for checking unclosed detection)
    VALID_INLINE_CHARS = set('abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_]).>')
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect backtick errors.
        
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
        
        # Check for space after opening backtick
        for match in self.SPACE_AFTER_OPEN.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: `{' ' + match.group(1)[:20]}...",
                description="Space after opening backtick",
                suggestion=f"Remove space: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for space before closing backtick
        for match in self.SPACE_BEFORE_CLOSE.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: `{match.group(1)[:20]}...",
                description="Space before closing backtick",
                suggestion=f"Remove space: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for spaces on both sides
        for match in self.SPACES_BOTH.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: ` {match.group(1)[:20]}...",
                description="Spaces inside backticks on both sides",
                suggestion=f"Remove spaces: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for unclosed inline backticks
        for match in self.UNCLOSED_INLINE.finditer(content):
            code_content = match.group(1)
            punct = match.group(2)
            
            # Check if this is actually unclosed (not preceded by valid chars)
            start_pos = match.start()
            if start_pos > 0:
                prev_char = content[start_pos - 1]
                if prev_char in self.VALID_INLINE_CHARS:
                    continue
            
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: `{code_content[:20]}...",
                description=f"Unclosed inline backtick before '{punct}'",
                suggestion=f"Close backtick: `{code_content}`{punct}",
                context=match.group(0),
                metadata={'content': code_content, 'punct': punct}
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply backtick error fixes.
        
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
        
        # Fix unclosed inline backticks
        def fix_unclosed(match):
            code_content = match.group(1)
            punct = match.group(2)
            trailing = match.group(3)
            
            # Check if truly unclosed
            start_pos = match.start()
            if start_pos > 0:
                prev_char = content[start_pos - 1]
                if prev_char in self.VALID_INLINE_CHARS:
                    return match.group(0)
            
            return f'`{code_content}`{punct}{trailing}'
        
        new_result, count = self.UNCLOSED_INLINE.subn(fix_unclosed, result)
        if count > 0:
            changes.append(f"Closed {count} unclosed inline backticks")
            result = new_result
            self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
