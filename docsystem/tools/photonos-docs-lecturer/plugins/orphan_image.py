#!/usr/bin/env python3
"""
Orphan Image Plugin for Photon OS Documentation Lecturer

Detects missing or broken images.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional
from urllib.parse import urljoin

from .base import BasePlugin, Issue, FixResult

__version__ = "2.0.0"


class OrphanImagePlugin(BasePlugin):
    """Plugin for detecting broken images.
    
    Detection only - manual fixes required.
    """
    
    PLUGIN_NAME = "orphan_image"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect missing or broken images"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix
    
    # Image pattern in markdown
    IMAGE_PATTERN = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')
    
    # HTML img pattern
    HTML_IMG_PATTERN = re.compile(r'<img[^>]+src=["\']([^"\']+)["\']')
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize with optional requests session."""
        super().__init__(config)
        self._session = None
        self._checked_urls = {}
    
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
    
    def _check_image(self, url: str, base_url: str) -> Optional[str]:
        """Check if image URL is accessible.
        
        Returns error message if broken, None if OK.
        """
        # Skip data URLs
        if url.startswith('data:'):
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
        """Detect broken images.
        
        Args:
            content: Markdown content
            url: URL of the page (for resolving relative images)
            **kwargs: Additional context (soup for HTML parsing)
            
        Returns:
            List of broken image issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Check markdown images
        for match in self.IMAGE_PATTERN.finditer(content):
            alt_text = match.group(1)
            img_url = match.group(2)
            
            error = self._check_image(img_url, url)
            if error:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Image: {alt_text[:30] or img_url[:30]}",
                    description=f"Broken image: {error}",
                    suggestion=f"Fix or remove image: {img_url[:50]}",
                    context=match.group(0)[:100],
                    severity="high"
                )
                issues.append(issue)
        
        # Check HTML images
        for match in self.HTML_IMG_PATTERN.finditer(content):
            img_url = match.group(1)
            
            error = self._check_image(img_url, url)
            if error:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Image: {img_url[:30]}",
                    description=f"Broken image: {error}",
                    suggestion=f"Fix or remove image: {img_url[:50]}",
                    context=match.group(0)[:100],
                    severity="high"
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for broken images.
        
        Returns content unchanged - manual review required.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Broken images require manual review"]
        )
