#!/usr/bin/env python3
"""
Orphan Page Plugin for Photon OS Documentation Lecturer

Detects pages that are not linked from anywhere (orphaned).

Version: 2.0.0
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Set

from .base import BasePlugin, Issue, FixResult

__version__ = "2.0.0"


class OrphanPagePlugin(BasePlugin):
    """Plugin for detecting orphan pages.
    
    Requires full site context to identify unreferenced pages.
    Detection only - manual fixes required.
    """
    
    PLUGIN_NAME = "orphan_page"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect pages not linked from anywhere"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize orphan page detector."""
        super().__init__(config)
        self._all_pages: Set[str] = set()
        self._linked_pages: Set[str] = set()
    
    def register_page(self, url: str):
        """Register a discovered page."""
        self._all_pages.add(url)
    
    def register_link(self, from_url: str, to_url: str):
        """Register a link from one page to another."""
        self._linked_pages.add(to_url)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect if this page is orphaned.
        
        Note: Full detection requires all pages to be registered first.
        
        Args:
            content: Markdown content (not used)
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of orphan page issues
        """
        issues = []
        
        # Skip if not enough context
        if not self._all_pages:
            return issues
        
        # Check if this page is linked from anywhere
        if url in self._all_pages and url not in self._linked_pages:
            # Check if it's the index/home page
            if not url.endswith('/') and not url.endswith('index'):
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=url,
                    description="Page is not linked from any other page",
                    suggestion="Add a link to this page from relevant locations",
                    severity="medium"
                )
                issues.append(issue)
                self.increment_detected(1)
        
        return issues
    
    def get_all_orphans(self) -> List[str]:
        """Get all orphan pages after full site scan."""
        orphans = []
        for page in self._all_pages:
            if page not in self._linked_pages:
                if not page.endswith('/') and not page.endswith('index'):
                    orphans.append(page)
        return orphans
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for orphan pages.
        
        Returns content unchanged - manual linking required.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Orphan pages require manual linking"]
        )
