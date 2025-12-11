#!/usr/bin/env python3
"""
Heading Hierarchy Plugin for Photon OS Documentation Lecturer

Detects and fixes heading level violations in markdown documents.
Ensures proper heading progression without skipped levels.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class HeadingHierarchyPlugin(BasePlugin):
    """Plugin for detecting and fixing heading hierarchy violations.
    
    Ensures proper heading level progression in markdown documents.
    """
    
    PLUGIN_NAME = "heading_hierarchy"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix heading hierarchy violations (skipped levels)"
    REQUIRES_LLM = False
    FIX_ID = 6
    
    # Pattern to match ATX-style headings (# ## ### etc.)
    HEADING_PATTERN = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the heading hierarchy plugin."""
        super().__init__(llm_client, config)
        self.min_first_level = config.get('min_first_level', 2) if config else 2
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect heading hierarchy violations.
        
        Checks for:
        - Skipped heading levels (e.g., H1 -> H3)
        - Wrong starting level
        
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
        
        # Extract all headings
        headings = []
        for match in self.HEADING_PATTERN.finditer(content):
            level = len(match.group(1))
            text = match.group(2).strip()
            headings.append({
                'level': level,
                'text': text,
                'match': match.group(0),
                'start': match.start(),
                'end': match.end()
            })
        
        if not headings:
            return issues
        
        # Check for hierarchy violations
        prev_level = 0
        for i, heading in enumerate(headings):
            level = heading['level']
            
            # Check for skipped levels (more than 1 level increase)
            if prev_level > 0 and level > prev_level + 1:
                skipped = level - prev_level - 1
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Heading: {heading['text'][:40]}...",
                    description=f"Skipped {skipped} heading level(s): H{prev_level} -> H{level}",
                    suggestion=f"Change from H{level} to H{prev_level + 1}",
                    metadata={
                        'index': i,
                        'current_level': level,
                        'expected_level': prev_level + 1,
                        'text': heading['text']
                    }
                )
                issues.append(issue)
            
            prev_level = level
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Fix heading hierarchy violations.
        
        Adjusts heading levels to ensure proper progression.
        
        Args:
            content: Markdown content to fix
            issues: Heading issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        if not issues:
            return FixResult(success=True, modified_content=content, changes_made=[])
        
        result = content
        changes = []
        
        # Re-extract headings for current state
        headings = list(self.HEADING_PATTERN.finditer(result))
        
        if not headings:
            return FixResult(success=True, modified_content=content, changes_made=[])
        
        # Calculate level adjustments
        adjustments = self._calculate_adjustments(headings)
        
        # Apply fixes in reverse order to preserve positions
        for match, new_level in reversed(adjustments):
            old_hashes = match.group(1)
            text = match.group(2)
            new_hashes = '#' * new_level
            
            if old_hashes != new_hashes:
                old_heading = match.group(0)
                new_heading = f"{new_hashes} {text}"
                result = result[:match.start()] + new_heading + result[match.end():]
                changes.append(f"Changed H{len(old_hashes)} to H{new_level}: {text[:30]}...")
                self.increment_fixed(1)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
    
    def _calculate_adjustments(self, headings: List) -> List[tuple]:
        """Calculate necessary heading level adjustments.
        
        Args:
            headings: List of heading regex matches
            
        Returns:
            List of (match, new_level) tuples
        """
        adjustments = []
        prev_level = 0
        
        for match in headings:
            current_level = len(match.group(1))
            
            if prev_level == 0:
                # First heading - keep as is
                new_level = current_level
            elif current_level > prev_level + 1:
                # Skipped level - adjust down
                new_level = prev_level + 1
            else:
                # Valid level
                new_level = current_level
            
            adjustments.append((match, new_level))
            prev_level = new_level
        
        return adjustments
