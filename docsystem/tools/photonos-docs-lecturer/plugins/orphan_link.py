#!/usr/bin/env python3
"""
Orphan Link Plugin for Photon OS Documentation Lecturer

Detects broken hyperlinks that return 404 or connection errors.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional
from urllib.parse import urljoin, urlparse

from .base import BasePlugin, Issue, FixResult

__version__ = "2.0.0"


class OrphanLinkPlugin(BasePlugin):
    """Plugin for detecting broken hyperlinks.
    
    Detection only - manual fixes required.
    """
    
    PLUGIN_NAME = "orphan_link"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect broken hyperlinks"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix
    
    # Link pattern in markdown
    LINK_PATTERN = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize with optional requests session."""
        super().__init__(config)
        self._session = None
        self._checked_urls = {}  # Cache results
    
    def _get_session(self):
        """Get or create requests session."""
        if self._session is None:
            try:
                import requests
                self._session = requests.Session()
                self._session.headers['User-Agent'] = 'PhotonOS-Docs-Lecturer/2.0'
            except ImportError:
                pass
        return self._session
    
    def _check_url(self, url: str, base_url: str) -> Optional[str]:
        """Check if URL is accessible.
        
        Returns error message if broken, None if OK.
        """
        # Skip anchors and mailto
        if url.startswith('#') or url.startswith('mailto:'):
            return None
        
        # Resolve relative URLs
        full_url = urljoin(base_url, url)
        
        # Check cache
        if full_url in self._checked_urls:
            return self._checked_urls[full_url]
        
        session = self._get_session()
        if not session:
            return None
        
        try:
            response = session.head(full_url, timeout=10, allow_redirects=True)
            if response.status_code >= 400:
                error = f"HTTP {response.status_code}"
            else:
                error = None
        except Exception as e:
            error = str(e)[:50]
        
        self._checked_urls[full_url] = error
        return error
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect broken links.
        
        Args:
            content: Markdown content
            url: URL of the page (for resolving relative links)
            **kwargs: Additional context
            
        Returns:
            List of broken link issues
        """
        issues = []
        
        if not content:
            return issues
        
        for match in self.LINK_PATTERN.finditer(content):
            link_text = match.group(1)
            link_url = match.group(2)
            
            error = self._check_url(link_url, url)
            if error:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Link: {link_text[:30]}",
                    description=f"Broken link: {error}",
                    suggestion=f"Fix or remove link to: {link_url[:50]}",
                    context=match.group(0)[:100],
                    severity="high"
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for broken links.
        
        Returns content unchanged - manual review required.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Broken links require manual review"]
        )
