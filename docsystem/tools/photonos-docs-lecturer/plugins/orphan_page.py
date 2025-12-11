#!/usr/bin/env python3
"""
Orphan Page Plugin for Photon OS Documentation Lecturer

Detects pages that return HTTP errors (404, 5xx) or are inaccessible.
These issues require manual intervention to resolve.

Version: 1.0.0
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class OrphanPagePlugin(BasePlugin):
    """Plugin for detecting inaccessible/orphan pages.
    
    Detects pages that return HTTP errors or are unreachable.
    These issues cannot be auto-fixed and require manual review.
    """
    
    PLUGIN_NAME = "orphan_page"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Detect broken/inaccessible pages"
    REQUIRES_LLM = False
    FIX_ID = None  # No auto-fix available
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the orphan page plugin.
        
        Args:
            llm_client: Not used for this plugin
            config: Configuration with 'session' key for requests.Session
        """
        super().__init__(llm_client, config)
        self.session = config.get('session') if config else None
        self.timeout = config.get('timeout', 10) if config else 10
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect if a page is orphan/inaccessible.
        
        Args:
            content: Not used directly (checks URL accessibility)
            url: URL to check
            **kwargs: May include 'status_code' if already fetched
            
        Returns:
            List with single issue if page is orphan, empty otherwise
        """
        issues = []
        
        status_code = kwargs.get('status_code')
        error = kwargs.get('error')
        
        # If status code already provided
        if status_code and status_code >= 400:
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=url,
                description=f"Page returned HTTP {status_code}",
                suggestion="Remove from sitemap or fix the page",
                fixable=False,
                metadata={'status_code': status_code}
            )
            issues.append(issue)
            self.increment_detected(1)
            return issues
        
        # If error message provided
        if error:
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=url,
                description=f"Page error: {error}",
                suggestion="Check server configuration",
                fixable=False,
                metadata={'error': error}
            )
            issues.append(issue)
            self.increment_detected(1)
            return issues
        
        # Check URL if session available
        if self.session and url:
            try:
                response = self.session.head(url, timeout=self.timeout, allow_redirects=True)
                if response.status_code >= 400:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=url,
                        description=f"Page returned HTTP {response.status_code}",
                        suggestion="Remove from sitemap or fix the page",
                        fixable=False,
                        metadata={'status_code': response.status_code}
                    )
                    issues.append(issue)
                    self.increment_detected(1)
            except Exception as e:
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=url,
                    description=f"Failed to access page: {str(e)[:100]}",
                    suggestion="Check server and network connectivity",
                    fixable=False,
                    metadata={'error': str(e)}
                )
                issues.append(issue)
                self.increment_detected(1)
        
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Orphan pages cannot be auto-fixed.
        
        Returns:
            FixResult indicating manual intervention required
        """
        return FixResult(
            success=False,
            error="Orphan pages require manual intervention"
        )
