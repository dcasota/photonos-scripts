#!/usr/bin/env python3
"""
Image Alignment Plugin for Photon OS Documentation Lecturer

Detects improperly aligned or positioned images.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, strip_code_blocks

__version__ = "2.0.0"


class ImageAlignmentPlugin(BasePlugin):
    """Plugin for detecting image alignment issues.
    
    Detection only - manual fixes recommended.
    """
    
    PLUGIN_NAME = "image_alignment"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect image alignment issues"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix
    
    # Image patterns
    MARKDOWN_IMAGE = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')
    HTML_IMAGE = re.compile(r'<img[^>]*>')
    
    # Alignment attributes
    ALIGN_ATTR = re.compile(r'align=["\']?(left|right|center)["\']?', re.IGNORECASE)
    STYLE_FLOAT = re.compile(r'float:\s*(left|right)', re.IGNORECASE)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect image alignment issues.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context (soup for HTML parsing)
            
        Returns:
            List of image alignment issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks
        safe_content = strip_code_blocks(content)
        
        # Check for inline images that might break layout
        for match in self.MARKDOWN_IMAGE.finditer(safe_content):
            img_line = content[max(0, match.start()-50):min(len(content), match.end()+50)]
            
            # Check if image is alone on its line (good) vs inline with text (might be bad)
            lines_before = content[:match.start()].split('\n')
            lines_after = content[match.end():].split('\n')
            
            line_before = lines_before[-1] if lines_before else ''
            line_after = lines_after[0] if lines_after else ''
            
            # If text immediately before/after on same line, might be alignment issue
            if line_before.strip() and not line_before.strip().startswith('|'):
                # Not alone on line, could be intentional inline image
                pass  # Don't flag as issue - inline images are valid
        
        # Check HTML images for deprecated align attribute
        for match in self.HTML_IMAGE.finditer(safe_content):
            img_tag = match.group(0)
            if self.ALIGN_ATTR.search(img_tag):
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Image tag",
                    description="Uses deprecated 'align' attribute",
                    suggestion="Use CSS for image alignment instead",
                    context=img_tag[:100],
                    severity="low"
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for image alignment.
        
        Returns content unchanged - manual review recommended.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Image alignment issues require manual review"]
        )
