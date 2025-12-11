#!/usr/bin/env python3
"""
Indentation Plugin for Photon OS Documentation Lecturer

Detects and fixes indentation issues in markdown lists and code blocks.
Requires LLM for intelligent indentation adjustments.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, LLMAssistedPlugin

__version__ = "1.0.0"


class IndentationPlugin(LLMAssistedPlugin):
    """Plugin for detecting and fixing indentation issues.
    
    Handles list indentation and nested content alignment.
    """
    
    PLUGIN_NAME = "indentation"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix indentation issues in lists and code blocks"
    REQUIRES_LLM = True
    FIX_ID = 11
    
    # Pattern for numbered lists
    NUMBERED_LIST = re.compile(r'^(\s*)(\d+)([.)])(\s+)(.*)$', re.MULTILINE)
    
    # LLM prompt template
    LLM_PROMPT_TEMPLATE = """You are a documentation indentation reviewer. Fix ONLY indentation/alignment issues.

Issues detected:
{issues}

CRITICAL RULES - VIOLATING ANY WILL CORRUPT THE DOCUMENTATION:

=== NEVER MODIFY CONTENT ===
- Product names: "Photon OS", "VMware vSphere", "VMware Workstation", "VMware Fusion"
- Paths: /etc/yum.repos.d/, ../../images/fs-version.png
- URLs and placeholders (__URL_PLACEHOLDER_N__)
- Content inside backticks
- Domain names (keep lowercase: github.com)
- ALL text and words - do NOT delete or change ANY text

=== CODE BLOCKS (STRICT SEPARATION) ===
- Content inside triple backticks (```...```) - DO NOT modify
- Lines starting with TAB or 4+ spaces are CODE - DO NOT modify text
- NEVER add backticks to content

=== PRESERVE EXACTLY ===
- YAML front matter (--- ... ---) at file start
- All parenthetical notes like "(NOTE: DO NOT use https://)"

=== ONLY ADJUST ===
- Leading whitespace (spaces/tabs at start of lines)
- Alignment of list items and nested content

=== INDENTATION FIXES ALLOWED ===
- Align list items properly
- Indent code blocks inside lists (4 spaces)
- Fix inconsistent indentation

Text to fix:
{{text}}

Return ONLY the corrected markdown. Do NOT add any preamble or explanation."""
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect indentation issues.
        
        Args:
            content: HTML or markdown content
            url: URL of the page
            **kwargs: May include 'soup' for BeautifulSoup object
            
        Returns:
            List of indentation issues
        """
        issues = []
        soup = kwargs.get('soup')
        
        if soup:
            # Check HTML list structure for improper nesting
            issues.extend(self._detect_list_nesting_issues(soup, url))
        
        # Check markdown content directly
        if kwargs.get('markdown_content'):
            md_content = kwargs['markdown_content']
            issues.extend(self._detect_markdown_indentation(md_content))
        
        self.increment_detected(len(issues))
        return issues
    
    def _detect_list_nesting_issues(self, soup, url: str) -> List[Issue]:
        """Detect improper list nesting in HTML.
        
        Args:
            soup: BeautifulSoup object
            url: Page URL
            
        Returns:
            List of nesting issues
        """
        issues = []
        
        # Check for nested lists with improper structure
        for list_tag in soup.find_all(['ul', 'ol']):
            nested_lists = list_tag.find_all(['ul', 'ol'], recursive=False)
            
            for nested in nested_lists:
                # Check if nested list is directly inside list (not in li)
                if nested.parent == list_tag:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"List in {url}",
                        description="Nested list not properly inside list item",
                        suggestion="Ensure nested lists are inside <li> elements",
                        metadata={'type': 'list_nesting'}
                    )
                    issues.append(issue)
        
        return issues
    
    def _detect_markdown_indentation(self, content: str) -> List[Issue]:
        """Detect indentation issues in markdown.
        
        Args:
            content: Markdown content
            
        Returns:
            List of indentation issues
        """
        issues = []
        lines = content.split('\n')
        
        in_list = False
        expected_indent = 0
        
        for i, line in enumerate(lines):
            if not line.strip():
                continue
            
            # Check for list items
            list_match = re.match(r'^(\s*)([*-]|\d+[.)])\s', line)
            if list_match:
                indent = len(list_match.group(1))
                
                if in_list and indent > 0 and indent % 2 != 0 and indent % 4 != 0:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Line {i+1}",
                        description=f"Inconsistent list indentation ({indent} spaces)",
                        suggestion="Use 2 or 4 space indentation consistently",
                        context=line[:50],
                        metadata={'line_number': i+1, 'type': 'list_indent'}
                    )
                    issues.append(issue)
                
                in_list = True
                expected_indent = indent + 2
            
            # Check for code blocks inside lists
            elif in_list and line.startswith(' ') or line.startswith('\t'):
                actual_indent = len(line) - len(line.lstrip())
                # Code inside lists should be indented 4+ spaces
                if 0 < actual_indent < 4 and '```' not in line:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Line {i+1}",
                        description=f"Content inside list has insufficient indentation ({actual_indent} spaces)",
                        suggestion="Indent to at least 4 spaces",
                        context=line[:50],
                        metadata={'line_number': i+1, 'type': 'list_content_indent'}
                    )
                    issues.append(issue)
        
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply indentation fixes using LLM.
        
        Args:
            content: Markdown content to fix
            issues: Indentation issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not issues:
            return FixResult(success=True, modified_content=content, changes_made=[])
        
        if not self.llm_client:
            return FixResult(
                success=False,
                error="LLM client required for indentation fixes"
            )
        
        try:
            issue_desc = "\n".join([
                f"- {i.metadata.get('type', 'unknown')}: {i.description}"
                for i in issues[:10]
            ])
            
            # Use LLM client's fix_indentation method if available
            if hasattr(self.llm_client, 'fix_indentation'):
                issue_dicts = [
                    {'context': i.context, 'type': i.metadata.get('type', 'unknown')}
                    for i in issues
                ]
                result = self.llm_client.fix_indentation(content, issue_dicts)
            else:
                prompt = self.LLM_PROMPT_TEMPLATE.format(issues=issue_desc)
                result = self._call_llm(prompt, content)
            
            if result and result != content:
                self.increment_fixed(len(issues))
                return FixResult(
                    success=True,
                    modified_content=result,
                    changes_made=[f"Applied indentation fixes for {len(issues)} issues"]
                )
            else:
                return FixResult(
                    success=True,
                    modified_content=content,
                    changes_made=[]
                )
        except Exception as e:
            self.logger.error(f"Indentation fix failed: {e}")
            return FixResult(success=False, error=str(e))
