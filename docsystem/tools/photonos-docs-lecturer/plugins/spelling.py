#!/usr/bin/env python3
"""
Spelling Plugin for Photon OS Documentation Lecturer

Detects and fixes VMware spelling errors and broken email addresses.
Also handles HTML comments.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, strip_code_blocks

__version__ = "1.0.0"


class SpellingPlugin(BasePlugin):
    """Plugin for detecting and fixing spelling issues.
    
    Handles VMware spelling, broken emails, and HTML comments.
    """
    
    PLUGIN_NAME = "spelling"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix VMware spelling and broken emails"
    REQUIRES_LLM = False
    FIX_ID = 2  # VMware spelling is fix ID 2
    
    # VMware spelling pattern - matches incorrect capitalizations
    VMWARE_PATTERN = re.compile(r'\b((?!VMware)[vV][mM][wW][aA][rR][eE])\b')
    
    # Broken email pattern (domain split with whitespace)
    BROKEN_EMAIL_PATTERN = re.compile(
        r'([\w.+-]+@[\w.-]+\.)'  # Email local part + @ + domain + dot
        r'(\s+)'                  # Whitespace (including newlines)
        r'(\w{2,6})'              # TLD (2-6 chars)
        r'(?=[>\s\)\]"\']|$)',
        re.MULTILINE
    )
    
    # HTML comment pattern
    HTML_COMMENT_PATTERN = re.compile(r'<!--\s*([\s\S]*?)\s*-->', re.MULTILINE)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect spelling issues.
        
        Args:
            content: Content to check (code blocks are stripped)
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of spelling issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks for VMware checking
        text_only = strip_code_blocks(content)
        
        # Check VMware spelling
        for match in self.VMWARE_PATTERN.finditer(text_only):
            # Skip if in URL or path context
            context_start = max(0, match.start() - 20)
            context_end = min(len(text_only), match.end() + 20)
            context = text_only[context_start:context_end]
            
            if self._is_in_url_or_path(match.group(0), context):
                continue
            
            issue = Issue(
                category="vmware_spelling",
                location=f"Found: {match.group(0)}",
                description=f"Incorrect VMware spelling: {match.group(0)}",
                suggestion="Change to: VMware",
                context=context
            )
            issues.append(issue)
        
        # Check broken emails (full content)
        for match in self.BROKEN_EMAIL_PATTERN.finditer(content):
            email_start = match.group(1)
            tld = match.group(3)
            issue = Issue(
                category="broken_email",
                location=f"Email: {email_start}...{tld}",
                description="Broken email address (domain split with whitespace)",
                suggestion=f"Fix to: {email_start}{tld}",
                context=match.group(0)[:50],
                metadata={'start': email_start, 'tld': tld}
            )
            issues.append(issue)
        
        # Check HTML comments (may need manual review)
        for match in self.HTML_COMMENT_PATTERN.finditer(content):
            comment_content = match.group(1).strip()
            if comment_content:
                issue = Issue(
                    category="html_comment",
                    location=f"Comment: {comment_content[:30]}...",
                    description="HTML comment found",
                    suggestion="Consider uncommenting content",
                    context=match.group(0)[:80],
                    metadata={'content': comment_content}
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def _is_in_url_or_path(self, word: str, context: str) -> bool:
        """Check if word appears in URL or path context.
        
        Args:
            word: The word found
            context: Surrounding context
            
        Returns:
            True if word is in URL/path context
        """
        context_lower = context.lower()
        
        # Check for URL patterns
        if any(pattern in context_lower for pattern in ['http://', 'https://', '@', '.com', '.org', '.io']):
            return True
        
        # Check for path patterns
        if '/' in context and word.lower() in context_lower:
            return True
        
        return False
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Fix spelling issues.
        
        Args:
            content: Content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with fixed content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        result = content
        changes = []
        
        # Filter issues by what we should fix
        fix_vmware = kwargs.get('fix_vmware', True)
        fix_emails = kwargs.get('fix_emails', True)
        fix_comments = kwargs.get('fix_comments', True)
        
        # Fix VMware spelling (skip URLs/paths)
        if fix_vmware:
            def fix_vmware_spelling(match):
                # Check context to avoid fixing in URLs
                start = max(0, match.start() - 50)
                end = min(len(result), match.end() + 50)
                context = result[start:end]
                
                if self._is_in_url_or_path(match.group(0), context):
                    return match.group(0)
                return 'VMware'
            
            new_result = self.VMWARE_PATTERN.sub(fix_vmware_spelling, result)
            if new_result != result:
                count = len(result) - len(new_result) + result.count('VMware') - new_result.count('VMware')
                changes.append(f"Fixed VMware spelling")
                result = new_result
                self.increment_fixed(1)
        
        # Fix broken emails
        if fix_emails:
            def fix_email(match):
                return f"{match.group(1)}{match.group(3)}"
            
            new_result, count = self.BROKEN_EMAIL_PATTERN.subn(fix_email, result)
            if count > 0:
                changes.append(f"Fixed {count} broken email addresses")
                result = new_result
                self.increment_fixed(count)
        
        # Fix HTML comments (remove markers, keep content)
        if fix_comments:
            def uncomment(match):
                return match.group(1).strip()
            
            new_result, count = self.HTML_COMMENT_PATTERN.subn(uncomment, result)
            if count > 0:
                changes.append(f"Uncommented {count} HTML comments")
                result = new_result
                self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )


class BrokenEmailPlugin(BasePlugin):
    """Standalone plugin for broken email fixes (FIX_ID 1)."""
    
    PLUGIN_NAME = "broken_email"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix broken email addresses"
    REQUIRES_LLM = False
    FIX_ID = 1
    
    BROKEN_EMAIL_PATTERN = re.compile(
        r'([\w.+-]+@[\w.-]+\.)'
        r'(\s+)'
        r'(\w{2,6})'
        r'(?=[>\s\)\]"\']|$)',
        re.MULTILINE
    )
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect broken emails."""
        issues = []
        if not content:
            return issues
        
        for match in self.BROKEN_EMAIL_PATTERN.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Email: {match.group(1)}...{match.group(3)}",
                description="Broken email address",
                suggestion=f"Fix to: {match.group(1)}{match.group(3)}"
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Fix broken emails."""
        if not content:
            return FixResult(success=False, error="No content")
        
        def fix_email(match):
            return f"{match.group(1)}{match.group(3)}"
        
        result, count = self.BROKEN_EMAIL_PATTERN.subn(fix_email, content)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=[f"Fixed {count} broken emails"] if count > 0 else []
        )


class HtmlCommentPlugin(BasePlugin):
    """Standalone plugin for HTML comment fixes (FIX_ID 8)."""
    
    PLUGIN_NAME = "html_comment"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix HTML comments"
    REQUIRES_LLM = False
    FIX_ID = 8
    
    HTML_COMMENT_PATTERN = re.compile(r'<!--\s*([\s\S]*?)\s*-->', re.MULTILINE)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect HTML comments."""
        issues = []
        if not content:
            return issues
        
        for match in self.HTML_COMMENT_PATTERN.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Comment at position {match.start()}",
                description="HTML comment found",
                suggestion="Consider uncommenting"
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Fix HTML comments by uncommenting."""
        if not content:
            return FixResult(success=False, error="No content")
        
        def uncomment(match):
            return match.group(1).strip()
        
        result, count = self.HTML_COMMENT_PATTERN.subn(uncomment, content)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=[f"Uncommented {count} HTML comments"] if count > 0 else []
        )
