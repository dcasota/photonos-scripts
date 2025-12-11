#!/usr/bin/env python3
"""
Markdown Plugin for Photon OS Documentation Lecturer

Detects and fixes markdown rendering artifacts and formatting issues.
Handles both deterministic fixes and LLM-assisted complex fixes.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, LLMAssistedPlugin

__version__ = "1.0.0"


class MarkdownPlugin(LLMAssistedPlugin):
    """Plugin for detecting and fixing markdown artifacts.
    
    Detects unrendered markdown syntax and fixes rendering issues.
    """
    
    PLUGIN_NAME = "markdown"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Detect and fix markdown rendering artifacts"
    REQUIRES_LLM = True
    FIX_ID = 10
    
    # Patterns to detect unrendered markdown in HTML
    ARTIFACT_PATTERNS = [
        (re.compile(r'(?<!\`)##\s+\w+'), 'Unrendered header'),
        (re.compile(r'\*\s+\w+'), 'Unrendered bullet point'),
        (re.compile(r'\[([^\]]+)\]\(([^\)]+)\)'), 'Unrendered link'),
        (re.compile(r'```[\s\S]*?```'), 'Unrendered code block'),
        (re.compile(r'`[^`]+`'), 'Unrendered inline code'),
        (re.compile(r'\*\*([^\*]+)\*\*'), 'Unrendered bold text'),
        (re.compile(r'(?<![*\w])_([^_]+)_(?![*\w])'), 'Unrendered italic text'),
    ]
    
    # Pattern for headers missing space after #
    HEADER_NO_SPACE_PATTERN = re.compile(r'^(#{2,6})([^\s#].*)$', re.MULTILINE)
    
    # Pattern for unclosed fenced code blocks
    UNCLOSED_FENCE_PATTERN = re.compile(r'^```(\w*)\s*$(?![\s\S]*?^```\s*$)', re.MULTILINE)
    
    # LLM prompt template
    LLM_PROMPT_TEMPLATE = """You are a documentation markdown reviewer. Fix ONLY markdown rendering issues.

Issues detected: {issues}

CRITICAL RULES - VIOLATING ANY WILL CORRUPT THE DOCUMENTATION:

=== PRODUCT NAMES (NEVER MODIFY) ===
These product names MUST remain EXACTLY as written:
- "Photon OS" - ALWAYS keep both words together
- "VMware vSphere", "VMware Workstation", "VMware Fusion"
- "Docker", "Kubernetes", "GitHub"

=== PATHS (NEVER MODIFY) ===
- Relative paths: ../../images/fs-version.png - keep EXACTLY as-is
- Directory paths: /etc/yum.repos.d/ - dots in names like "yum.repos.d" are VALID
- File paths: /var/cache/tdnf, /media/cdrom

=== CODE BLOCKS (STRICT SEPARATION) ===
- Content inside triple backticks (```...```) is a CODE BLOCK - DO NOT modify
- Content inside single backticks (`...`) is INLINE CODE - copy the ENTIRE `...` block EXACTLY
- Example: `*.raw` must stay as `*.raw` - never change to `*.raw,` or `*.raw` and
- Lines starting with TAB or 4+ spaces are CODE OUTPUT - DO NOT modify
- NEVER add backticks inside code blocks
- NEVER add backticks to words that didn't have them
- NEVER remove the closing backtick from inline code

=== PRESERVE EXACTLY ===
- YAML front matter (--- ... ---) at file start
- All URLs and domain names (keep lowercase: github.com not GitHub.com)
- All line breaks and indentation
- All parenthetical notes - NEVER delete text like "(NOTE: ...)"

=== MARKDOWN FIXES ALLOWED ===
- Convert ```term``` to `term` ONLY when used inline within a sentence
- Fix unclosed code blocks (missing closing ```)
- Add space after # in headers: #Title -> # Title

=== DO NOT ===
- Do NOT delete ANY text
- Do NOT add backticks after sentence-ending periods
- Do NOT modify product names
- Do NOT modify paths

Text to fix:
{{text}}

Return ONLY the corrected markdown. Do NOT add any preamble or explanation."""
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the markdown plugin."""
        super().__init__(llm_client, config)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect markdown rendering artifacts.
        
        Args:
            content: HTML content from rendered page
            url: URL of the page
            **kwargs: May include 'soup' for BeautifulSoup object
            
        Returns:
            List of markdown artifact issues
        """
        issues = []
        soup = kwargs.get('soup')
        
        if not soup and not content:
            return issues
        
        # Get text content from HTML
        if soup:
            text = soup.get_text()
        else:
            text = content
        
        # Check for unrendered markdown artifacts
        for pattern, description in self.ARTIFACT_PATTERNS:
            matches = pattern.findall(text)
            if matches:
                for match in matches[:5]:  # Limit to first 5
                    match_text = match if isinstance(match, str) else str(match)
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Found: {match_text[:50]}...",
                        description=description,
                        suggestion="Fix markdown syntax or rendering",
                        context=match_text[:100]
                    )
                    issues.append(issue)
        
        # Check for headers missing space
        if kwargs.get('markdown_content'):
            md_content = kwargs['markdown_content']
            header_issues = self._detect_header_spacing(md_content)
            issues.extend(header_issues)
        
        self.increment_detected(len(issues))
        return issues
    
    def _detect_header_spacing(self, content: str) -> List[Issue]:
        """Detect headers missing space after #.
        
        Args:
            content: Markdown content
            
        Returns:
            List of header spacing issues
        """
        issues = []
        
        for match in self.HEADER_NO_SPACE_PATTERN.finditer(content):
            hashes = match.group(1)
            rest = match.group(2)
            issue = Issue(
                category="header_spacing",
                location=f"Line: {match.group(0)[:50]}",
                description=f"Header missing space after {hashes}",
                suggestion=f"Change to: {hashes} {rest}",
                metadata={'hashes': hashes, 'rest': rest, 'full_match': match.group(0)}
            )
            issues.append(issue)
        
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply markdown fixes.
        
        Applies deterministic fixes first, then LLM fixes for complex issues.
        
        Args:
            content: Markdown content to fix
            issues: Markdown issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        result = content
        changes = []
        
        # Apply deterministic fixes first
        result, det_changes = self._apply_deterministic_fixes(result)
        changes.extend(det_changes)
        
        # Apply LLM fixes for remaining complex issues if available
        remaining_issues = [i for i in issues if i.category == self.PLUGIN_NAME]
        if remaining_issues and self.llm_client:
            try:
                llm_result = super().fix(result, remaining_issues, **kwargs)
                if llm_result.success and llm_result.modified_content:
                    result = llm_result.modified_content
                    changes.extend(llm_result.changes_made)
            except Exception as e:
                self.logger.error(f"LLM markdown fix failed: {e}")
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
    
    def _apply_deterministic_fixes(self, content: str) -> tuple:
        """Apply deterministic markdown fixes.
        
        Args:
            content: Markdown content
            
        Returns:
            Tuple of (fixed_content, list_of_changes)
        """
        result = content
        changes = []
        
        # Fix header spacing
        def fix_header(match):
            return f"{match.group(1)} {match.group(2)}"
        
        new_result, count = self.HEADER_NO_SPACE_PATTERN.subn(fix_header, result)
        if count > 0:
            changes.append(f"Fixed {count} header spacing issues")
            result = new_result
            self.increment_fixed(count)
        
        return result, changes


class MalformedCodeBlockPlugin(BasePlugin):
    """Plugin for detecting and fixing malformed code blocks.
    
    Handles various code block issues without requiring LLM.
    """
    
    PLUGIN_NAME = "malformed_code_block"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Fix malformed code blocks"
    REQUIRES_LLM = False
    FIX_ID = 12
    
    # Pattern: single backtick + content + 3+ backticks
    SINGLE_TRIPLE_PATTERN = re.compile(r'`([^`\n]+)`{3,}')
    
    # Pattern: consecutive inline code that should be fenced
    CONSECUTIVE_INLINE = re.compile(
        r'(?:^|\n)(\s*)`([^`\n]+)`\s*\n\s*`([^`\n]+)`',
        re.MULTILINE
    )
    
    # Pattern: triple backticks used as inline (same line)
    TRIPLE_INLINE = re.compile(r'```([a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+)?)```')
    
    # Pattern: fenced block used for inline code (followed by sentence continuation)
    FENCED_INLINE = re.compile(
        r'```(?:bash|sh|shell|console|text)?\s*\n'
        r'([a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+)?)\s*\n'
        r'```'
        r'(\s*(?:[.,;:!?]|(?:\s+(?:is|are|was|were|has|have|had|can|will|would|should|may|might|must|turned|configuration|data|with)\b)))',
        re.MULTILINE
    )
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect malformed code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of code block issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Check for single-triple pattern
        for match in self.SINGLE_TRIPLE_PATTERN.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: `content```",
                description="Single backtick followed by triple backticks",
                suggestion="Convert to proper fenced code block",
                context=match.group(0)[:50]
            )
            issues.append(issue)
        
        # Check for triple backticks used as inline
        for match in self.TRIPLE_INLINE.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Pattern: ```{match.group(1)}```",
                description="Triple backticks used for inline code",
                suggestion=f"Convert to single backticks: `{match.group(1)}`",
                context=match.group(0)
            )
            issues.append(issue)
        
        # Check for fenced block incorrectly used for inline
        for match in self.FENCED_INLINE.finditer(content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Fenced block followed by: {match.group(2)[:20]}",
                description="Fenced code block used where inline code expected",
                suggestion=f"Convert to inline: `{match.group(1)}`",
                context=match.group(0)[:80]
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Fix malformed code blocks.
        
        Args:
            content: Markdown content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        result = content
        changes = []
        
        # Fix triple backticks used as inline
        def fix_triple_inline(match):
            return f'`{match.group(1)}`'
        
        new_result, count = self.TRIPLE_INLINE.subn(fix_triple_inline, result)
        if count > 0:
            changes.append(f"Converted {count} triple-backtick inline code to single backticks")
            result = new_result
            self.increment_fixed(count)
        
        # Fix fenced blocks used for inline
        def fix_fenced_inline(match):
            return f'`{match.group(1)}`{match.group(2)}'
        
        new_result, count = self.FENCED_INLINE.subn(fix_fenced_inline, result)
        if count > 0:
            changes.append(f"Converted {count} fenced blocks to inline code")
            result = new_result
            self.increment_fixed(count)
        
        # Fix single-triple pattern
        def fix_single_triple(match):
            code = match.group(1)
            return f'```\n{code}\n```'
        
        new_result, count = self.SINGLE_TRIPLE_PATTERN.subn(fix_single_triple, result)
        if count > 0:
            changes.append(f"Fixed {count} malformed code blocks")
            result = new_result
            self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
