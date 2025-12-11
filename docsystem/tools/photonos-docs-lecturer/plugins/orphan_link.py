#!/usr/bin/env python3
"""
Orphan Link Plugin for Photon OS Documentation Lecturer

Detects broken hyperlinks within documentation pages.
Validates internal links by checking their HTTP status.

Version: 1.0.0
"""

from __future__ import annotations

import re
import urllib.parse
from typing import Any, Dict, List, Optional, Set

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class OrphanLinkPlugin(BasePlugin):
    """Plugin for detecting broken/orphan links.
    
    Validates hyperlinks in documentation pages and reports broken ones.
    """
    
    PLUGIN_NAME = "orphan_link"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Detect broken hyperlinks"
    REQUIRES_LLM = False
    FIX_ID = None  # No auto-fix available
    
    # Pattern for markdown links
    MARKDOWN_LINK_PATTERN = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
    
    # Pattern for HTML links
    HTML_LINK_PATTERN = re.compile(r'<a[^>]+href=["\']([^"\']+)["\'][^>]*>([^<]*)</a>', re.IGNORECASE)
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the orphan link plugin.
        
        Args:
            llm_client: Not used for this plugin
            config: Configuration with 'session' and 'base_url' keys
        """
        super().__init__(llm_client, config)
        self.session = config.get('session') if config else None
        self.base_url = config.get('base_url', '') if config else ''
        self.timeout = config.get('timeout', 10) if config else 10
        self._checked_urls: Set[str] = set()
        self._broken_urls: Dict[str, int] = {}  # url -> status_code
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect broken links in content.
        
        Args:
            content: HTML or markdown content
            url: URL of the page containing links
            **kwargs: May include 'soup' for BeautifulSoup object
            
        Returns:
            List of broken link issues
        """
        issues = []
        soup = kwargs.get('soup')
        
        # Extract links from HTML
        links = []
        if soup:
            for a_tag in soup.find_all('a', href=True):
                href = a_tag.get('href', '')
                text = a_tag.get_text(strip=True)
                if href and not href.startswith(('#', 'javascript:', 'mailto:')):
                    links.append((text, href))
        else:
            # Extract from markdown
            for match in self.MARKDOWN_LINK_PATTERN.finditer(content):
                text = match.group(1)
                href = match.group(2)
                if href and not href.startswith(('#', 'javascript:', 'mailto:')):
                    links.append((text, href))
        
        # Check each link
        for text, href in links:
            # Resolve relative URLs
            full_url = self._resolve_url(href, url)
            
            # Skip external links unless configured to check them
            if not self._should_check_url(full_url):
                continue
            
            # Check if already known to be broken
            if full_url in self._broken_urls:
                status = self._broken_urls[full_url]
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Link text: '{text[:30]}', URL: {href[:50]}",
                    description=f"Broken link (HTTP {status})",
                    suggestion="Remove or update link",
                    fixable=False,
                    metadata={'url': full_url, 'text': text, 'status_code': status}
                )
                issues.append(issue)
                continue
            
            # Skip if already checked and valid
            if full_url in self._checked_urls:
                continue
            
            # Check link
            status = self._check_link(full_url)
            if status and status >= 400:
                self._broken_urls[full_url] = status
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Link text: '{text[:30]}', URL: {href[:50]}",
                    description=f"Broken link (HTTP {status})",
                    suggestion="Remove or update link",
                    fixable=False,
                    metadata={'url': full_url, 'text': text, 'status_code': status}
                )
                issues.append(issue)
            else:
                self._checked_urls.add(full_url)
        
        self.increment_detected(len(issues))
        return issues
    
    def _resolve_url(self, href: str, page_url: str) -> str:
        """Resolve a potentially relative URL.
        
        Args:
            href: The href value (may be relative)
            page_url: The URL of the page containing the link
            
        Returns:
            Absolute URL
        """
        if href.startswith(('http://', 'https://')):
            return href
        
        return urllib.parse.urljoin(page_url, href)
    
    def _should_check_url(self, url: str) -> bool:
        """Determine if URL should be checked.
        
        Args:
            url: URL to check
            
        Returns:
            True if URL should be validated
        """
        # Only check internal links by default
        if self.base_url:
            parsed_base = urllib.parse.urlparse(self.base_url)
            parsed_url = urllib.parse.urlparse(url)
            return parsed_url.netloc == parsed_base.netloc
        
        return True
    
    def _check_link(self, url: str) -> Optional[int]:
        """Check if a link is accessible.
        
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
            self.logger.debug(f"Link check failed for {url}: {e}")
            return 599  # Use 599 for connection errors
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Broken links cannot be auto-fixed.
        
        Returns:
            FixResult indicating manual intervention required
        """
        return FixResult(
            success=False,
            error="Broken links require manual intervention to update or remove"
        )
