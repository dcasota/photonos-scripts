#!/usr/bin/env python3
"""
Formatting Plugin for Photon OS Documentation Lecturer

Handles backtick spacing issues and other formatting fixes.
Fixes missing spaces around inline code backticks.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, PatternBasedPlugin

__version__ = "1.0.0"


class FormattingPlugin(PatternBasedPlugin):
    """Plugin for detecting and fixing formatting issues.
    
    Handles backtick spacing and related formatting problems.
    """
    
    PLUGIN_NAME = "formatting"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix missing spaces around backticks"
    REQUIRES_LLM = False
    FIX_ID = 4
    
    # Pattern for missing space before backticks
    MISSING_SPACE_BEFORE = re.compile(r'([a-zA-Z])(`[^\s`][^`\n]*?`)')
    
    # Pattern for missing space after backticks
    MISSING_SPACE_AFTER = re.compile(r'(`[^\s`][^`\n]*?`)([a-zA-Z])')
    
    # Pattern for stray backtick typo (e.g., Clone`the -> Clone the)
    STRAY_BACKTICK = re.compile(r'(?:^|(?<=\s))([a-zA-Z]+)`([a-zA-Z])(?![^`\n]*`)')
    
    # Pattern for URLs wrapped in backticks (should be removed)
    URL_IN_BACKTICKS = re.compile(r'`(https?://[^`\s]+)`')
    
    # Pattern for standalone URL with trailing backtick (opening removed by LLM)
    URL_TRAILING_BACKTICK = re.compile(r'(https?://[^\s`]+)`(\s|$)')
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect formatting issues.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of formatting issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Check for missing space before backticks
        for match in self.MISSING_SPACE_BEFORE.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: {match.group(0)[:30]}",
                description="Missing space before backtick",
                suggestion=f"Add space: {match.group(1)} {match.group(2)}",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for missing space after backticks
        for match in self.MISSING_SPACE_AFTER.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: {match.group(0)[:30]}",
                description="Missing space after backtick",
                suggestion=f"Add space: {match.group(1)} {match.group(2)}",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for URLs in backticks
        for match in self.URL_IN_BACKTICKS.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"URL: {match.group(1)[:40]}",
                description="URL should not be in backticks",
                suggestion=f"Remove backticks: {match.group(1)}",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for stray backtick typos
        for match in self.STRAY_BACKTICK.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: {match.group(0)[:30]}",
                description="Stray backtick (likely typo for space)",
                suggestion=f"Replace with: {match.group(1)} {match.group(2)}",
                context=match.group(0)
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply formatting fixes.
        
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
        
        # Fix missing space before backticks
        def add_space_before(match):
            return f"{match.group(1)} {match.group(2)}"
        
        new_result, count = self.MISSING_SPACE_BEFORE.subn(add_space_before, result)
        if count > 0:
            changes.append(f"Added {count} spaces before backticks")
            result = new_result
            self.increment_fixed(count)
        
        # Fix missing space after backticks
        def add_space_after(match):
            return f"{match.group(1)} {match.group(2)}"
        
        new_result, count = self.MISSING_SPACE_AFTER.subn(add_space_after, result)
        if count > 0:
            changes.append(f"Added {count} spaces after backticks")
            result = new_result
            self.increment_fixed(count)
        
        # Fix URLs in backticks (remove backticks)
        def remove_url_backticks(match):
            return match.group(1)
        
        new_result, count = self.URL_IN_BACKTICKS.subn(remove_url_backticks, result)
        if count > 0:
            changes.append(f"Removed backticks from {count} URLs")
            result = new_result
            self.increment_fixed(count)
        
        # Fix stray backtick typos
        def fix_stray_backtick(match):
            return f"{match.group(1)} {match.group(2)}"
        
        new_result, count = self.STRAY_BACKTICK.subn(fix_stray_backtick, result)
        if count > 0:
            changes.append(f"Fixed {count} stray backtick typos")
            result = new_result
            self.increment_fixed(count)
        
        # Fix trailing backtick on URLs (from LLM corruption)
        def fix_url_trailing(match):
            url = match.group(1)
            trailing = match.group(2)
            # Check if there's no opening backtick before URL
            url_pos = result.find(url)
            if url_pos > 0 and result[url_pos - 1] == '`':
                # Has opening backtick - keep as is
                return match.group(0)
            return url + trailing
        
        new_result, count = self.URL_TRAILING_BACKTICK.subn(fix_url_trailing, result)
        if count > 0:
            changes.append(f"Fixed {count} URLs with trailing backticks")
            result = new_result
            self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
