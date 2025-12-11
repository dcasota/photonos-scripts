#!/usr/bin/env python3
"""
Heading Hierarchy Plugin for Photon OS Documentation Lecturer

Detects heading level violations (skipped levels, wrong first heading).

CRITICAL: All operations protect fenced code blocks from modification.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import (
    BasePlugin,
    Issue,
    FixResult,
    strip_code_blocks,
)

__version__ = "2.0.0"


class HeadingHierarchyPlugin(BasePlugin):
    """Plugin for detecting heading hierarchy violations.
    
    Detection only - manual fixes recommended for heading structure.
    """
    
    PLUGIN_NAME = "heading_hierarchy"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect heading hierarchy violations"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix
    
    # Heading pattern
    HEADING_PATTERN = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect heading hierarchy issues.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of heading hierarchy issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        headings = []
        for match in self.HEADING_PATTERN.finditer(safe_content):
            level = len(match.group(1))
            text = match.group(2).strip()
            headings.append((level, text, match.start()))
        
        if not headings:
            return issues
        
        # Check first heading
        first_level = headings[0][0]
        if first_level > 2:
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"First heading: {headings[0][1][:30]}",
                description=f"First heading is h{first_level}, should be h1 or h2",
                suggestion="Consider using h1 or h2 for the first heading",
                severity="medium"
            )
            issues.append(issue)
        
        # Check for skipped levels
        prev_level = 0
        for level, text, pos in headings:
            if prev_level > 0 and level > prev_level + 1:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Heading: {text[:30]}",
                    description=f"Skipped heading level: h{prev_level} -> h{level}",
                    suggestion=f"Use h{prev_level + 1} instead of h{level}",
                    severity="medium"
                )
                issues.append(issue)
            prev_level = level
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for heading hierarchy.
        
        Returns content unchanged - manual review recommended.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Heading hierarchy issues require manual review"]
        )
