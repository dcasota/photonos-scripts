#!/usr/bin/env python3
"""
Markdown Plugin for Photon OS Documentation Lecturer

Detects and fixes markdown formatting issues like unrendered artifacts,
missing header spacing, and unclosed code blocks.

CRITICAL: All operations protect fenced code blocks from modification.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import (
    LLMAssistedPlugin,
    Issue,
    FixResult,
    strip_code_blocks,
    protect_code_blocks,
    restore_code_blocks,
)

__version__ = "2.0.0"


class MarkdownPlugin(LLMAssistedPlugin):
    """Plugin for detecting and fixing markdown issues.
    
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "markdown"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Fix markdown formatting issues"
    REQUIRES_LLM = True
    FIX_ID = 10
    
    # Missing space after heading hash
    MISSING_HEADING_SPACE = re.compile(r'^(#{1,6})([^\s#])', re.MULTILINE)
    
    # Unrendered bold/italic
    UNRENDERED_BOLD = re.compile(r'\*\*[^*]+\*\*')
    UNRENDERED_ITALIC = re.compile(r'(?<!\*)\*[^*]+\*(?!\*)')
    
    # Broken link patterns
    BROKEN_LINK = re.compile(r'\[([^\]]+)\]\s+\(')  # Space between ] and (
    
    # LLM prompt template
    PROMPT_TEMPLATE = """You are a markdown formatting expert. Fix ONLY the markdown issues listed below.

CRITICAL RULES - VIOLATING ANY WILL CORRUPT THE DOCUMENTATION:
1. Output ONLY the corrected text - no explanations
2. Preserve ALL existing formatting that is correct
3. Do NOT modify fenced code blocks (``` or ~~~) or their content
4. Do NOT modify inline code (`...`)
5. Do NOT add or remove any content
6. Lines starting with 4+ spaces are code - do NOT modify
7. Preserve YAML front matter exactly
8. Do NOT escape underscores

MARKDOWN ISSUES TO FIX:
{issues}

Text to fix:
{text}

Return ONLY the corrected text."""
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect markdown issues, excluding code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of markdown issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        # Check for missing heading space
        for match in self.MISSING_HEADING_SPACE.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Heading: {match.group(0)[:30]}",
                description="Missing space after heading hash",
                suggestion=f"Add space: {match.group(1)} {match.group(2)}",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for broken links (space between ] and ()
        for match in self.BROKEN_LINK.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Link: {match.group(1)[:30]}",
                description="Space between link text and URL",
                suggestion="Remove space between ] and (",
                context=match.group(0)
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply markdown fixes, protecting code blocks.
        
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
        
        # Fix simple issues with regex (no LLM needed)
        
        # Fix missing heading space
        def fix_heading_space(match):
            return f"{match.group(1)} {match.group(2)}"
        
        new_result, count = self.MISSING_HEADING_SPACE.subn(fix_heading_space, result)
        if count > 0:
            changes.append(f"Added space after {count} heading hashes")
            result = new_result
            self.increment_fixed(count)
        
        # Fix broken links
        def fix_broken_link(match):
            return f"[{match.group(1)}]("
        
        new_result, count = self.BROKEN_LINK.subn(fix_broken_link, result)
        if count > 0:
            changes.append(f"Fixed {count} broken links")
            result = new_result
            self.increment_fixed(count)
        
        # Restore code blocks UNCHANGED
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
