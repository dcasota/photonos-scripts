#!/usr/bin/env python3
"""
Orphan Image Plugin for Photon OS Documentation Lecturer

Detects broken/missing images in documentation pages.
Validates image sources by checking their HTTP status.

Version: 1.0.0
"""

from __future__ import annotations

import re
import urllib.parse
from typing import Any, Dict, List, Optional, Set

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class OrphanImagePlugin(BasePlugin):
    """Plugin for detecting broken/orphan images.
    
    Validates image sources in documentation pages and reports missing ones.
    """
    
    PLUGIN_NAME = "orphan_image"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Detect broken/missing images"
    REQUIRES_LLM = False
    FIX_ID = None  # No auto-fix available
    
    # Pattern for markdown images
    MARKDOWN_IMAGE_PATTERN = re.compile(r'!\[([^\]]*)\]\(([^)]+)\)')
    
    # Pattern for HTML images
    HTML_IMAGE_PATTERN = re.compile(r'<img[^>]+src=["\']([^"\']+)["\']', re.IGNORECASE)
    
    # Common image extensions
    IMAGE_EXTENSIONS = {'.png', '.jpg', '.jpeg', '.gif', '.svg', '.webp', '.ico', '.bmp'}
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the orphan image plugin.
        
        Args:
            llm_client: Not used for this plugin
            config: Configuration with 'session' and 'base_url' keys
        """
        super().__init__(llm_client, config)
        self.session = config.get('session') if config else None
        self.base_url = config.get('base_url', '') if config else ''
        self.timeout = config.get('timeout', 10) if config else 10
        self._checked_images: Set[str] = set()
        self._broken_images: Dict[str, int] = {}  # url -> status_code
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect broken images in content.
        
        Args:
            content: HTML or markdown content
            url: URL of the page containing images
            **kwargs: May include 'soup' for BeautifulSoup object
            
        Returns:
            List of broken image issues
        """
        issues = []
        soup = kwargs.get('soup')
        
        # Extract images from HTML
        images = []
        if soup:
            for img_tag in soup.find_all('img', src=True):
                src = img_tag.get('src', '')
                alt = img_tag.get('alt', '')
                if src:
                    images.append((alt, src))
        else:
            # Extract from markdown
            for match in self.MARKDOWN_IMAGE_PATTERN.finditer(content):
                alt = match.group(1)
                src = match.group(2)
                if src:
                    images.append((alt, src))
        
        # Also extract from HTML in markdown content
        for match in self.HTML_IMAGE_PATTERN.finditer(content):
            src = match.group(1)
            if src:
                images.append(('', src))
        
        # Check each image
        for alt, src in images:
            # Skip data URIs
            if src.startswith('data:'):
                continue
            
            # Resolve relative URLs
            full_url = self._resolve_url(src, url)
            
            # Check if already known to be broken
            if full_url in self._broken_images:
                status = self._broken_images[full_url]
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Image: {alt[:30] if alt else src[:30]}",
                    description=f"Broken image (HTTP {status}): {src[:50]}",
                    suggestion="Fix image path or remove reference",
                    fixable=False,
                    metadata={'url': full_url, 'alt': alt, 'src': src, 'status_code': status}
                )
                issues.append(issue)
                continue
            
            # Skip if already checked and valid
            if full_url in self._checked_images:
                continue
            
            # Check image
            status = self._check_image(full_url)
            if status and status >= 400:
                self._broken_images[full_url] = status
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Image: {alt[:30] if alt else src[:30]}",
                    description=f"Broken image (HTTP {status}): {src[:50]}",
                    suggestion="Fix image path or remove reference",
                    fixable=False,
                    metadata={'url': full_url, 'alt': alt, 'src': src, 'status_code': status}
                )
                issues.append(issue)
            else:
                self._checked_images.add(full_url)
        
        self.increment_detected(len(issues))
        return issues
    
    def _resolve_url(self, src: str, page_url: str) -> str:
        """Resolve a potentially relative image URL.
        
        Args:
            src: The src value (may be relative)
            page_url: The URL of the page containing the image
            
        Returns:
            Absolute URL
        """
        if src.startswith(('http://', 'https://')):
            return src
        
        return urllib.parse.urljoin(page_url, src)
    
    def _check_image(self, url: str) -> Optional[int]:
        """Check if an image is accessible.
        
        Args:
            url: URL to check
            
        Returns:
            HTTP status code or None if check failed
        """
        if not self.session:
            return None
        
        try:
            response = self.session.head(url, timeout=self.timeout, allow_redirects=True)
            return response.status_code
        except Exception as e:
            self.logger.debug(f"Image check failed for {url}: {e}")
            return 599  # Use 599 for connection errors
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Broken images cannot be auto-fixed.
        
        Returns:
            FixResult indicating manual intervention required
        """
        return FixResult(
            success=False,
            error="Broken images require manual intervention to fix paths or remove references"
        )
