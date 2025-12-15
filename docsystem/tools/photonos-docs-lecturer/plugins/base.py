#!/usr/bin/env python3
"""
Base Plugin Classes for Photon OS Documentation Lecturer

Provides the foundation for all documentation analysis plugins with
CRITICAL code block protection to ensure fenced code blocks are NEVER modified.

Version: 2.0.0
"""

from __future__ import annotations

import re
import logging
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

__version__ = "2.0.0"

# Placeholder used to protect code blocks during processing
CODE_BLOCK_PLACEHOLDER = "\x00CODEBLOCK_{}_\x00"

# Pattern to match fenced code blocks (``` or ~~~)
FENCED_CODE_BLOCK_PATTERN = re.compile(
    r'(^```[\w]*.*?^```|^~~~[\w]*.*?^~~~)',
    re.MULTILINE | re.DOTALL
)

# Pattern to match indented code blocks (4+ spaces or tab at line start)
# IMPORTANT: This pattern is intentionally restrictive to avoid false positives
# with list continuations. Indented code blocks in markdown must be preceded by
# a blank line. Lines indented within list items are NOT code blocks.
# We use a negative lookbehind to ensure the indented block follows a blank line.
INDENTED_CODE_BLOCK_PATTERN = re.compile(
    r'(?:^|\n\n)'  # Start of text or blank line (paragraph break)
    r'((?:[ ]{4,}|\t)[^\n]+(?:\n(?:[ ]{4,}|\t)[^\n]+)*)',  # Indented lines
    re.MULTILINE
)


@dataclass
class Issue:
    """Represents a detected documentation issue."""
    category: str
    location: str
    description: str
    suggestion: str = ""
    context: str = ""
    severity: str = "medium"
    line_number: int = 0
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass
class FixResult:
    """Result of applying a fix."""
    success: bool
    modified_content: Optional[str] = None
    changes_made: List[str] = field(default_factory=list)
    error: Optional[str] = None


def strip_code_blocks(text: str) -> str:
    """Remove all code blocks from text for analysis.
    
    This function removes:
    - Fenced code blocks (``` ... ``` or ~~~ ... ~~~)
    - Inline code (`...`)
    
    NOTE: Indented code blocks (4+ spaces) are NOT stripped because:
    - They are ambiguous with list continuations and nested content
    - Modern markdown primarily uses fenced code blocks
    - Stripping them causes false positives (e.g., URLs in list items)
    
    Use this before detecting issues to avoid false positives on code content.
    
    Args:
        text: The markdown content
        
    Returns:
        Text with code blocks replaced with spaces
    """
    if not text:
        return text
    
    # Remove fenced code blocks
    result = FENCED_CODE_BLOCK_PATTERN.sub(' ', text)
    
    # Remove inline code
    result = re.sub(r'`[^`\n]+`', ' ', result)
    
    # NOTE: We intentionally do NOT strip indented code blocks here.
    # The INDENTED_CODE_BLOCK_PATTERN is too aggressive and incorrectly
    # matches list continuations (4+ space indented content within lists).
    # Fenced code blocks are the standard for Photon OS documentation.
    
    return result


def protect_code_blocks(text: str) -> Tuple[str, List[str]]:
    """Replace code blocks with placeholders to protect them during fixes.
    
    CRITICAL: This function MUST be called before applying any regex-based
    fixes to ensure code block content is never modified.
    
    NOTE: Only fenced code blocks are protected. Indented code blocks are NOT
    protected because the pattern incorrectly matches list continuations.
    
    Args:
        text: The markdown content
        
    Returns:
        Tuple of (text with placeholders, list of original code blocks)
    """
    if not text:
        return text, []
    
    code_blocks = []
    
    def save_code_block(match):
        idx = len(code_blocks)
        code_blocks.append(match.group(0))
        return CODE_BLOCK_PLACEHOLDER.format(idx)
    
    # Protect fenced code blocks (the standard for Photon OS documentation)
    result = FENCED_CODE_BLOCK_PATTERN.sub(save_code_block, text)
    
    # NOTE: We intentionally do NOT protect indented code blocks here.
    # The INDENTED_CODE_BLOCK_PATTERN is too aggressive and incorrectly
    # matches list continuations (4+ space indented content within lists).
    # This caused URLs in list items to be skipped during fix application.
    
    return result, code_blocks


def restore_code_blocks(text: str, code_blocks: List[str]) -> str:
    """Restore code blocks from placeholders after fixes are applied.
    
    Args:
        text: Text with placeholders
        code_blocks: List of original code block content
        
    Returns:
        Text with code blocks restored
    """
    if not text or not code_blocks:
        return text
    
    result = text
    for idx, block in enumerate(code_blocks):
        placeholder = CODE_BLOCK_PLACEHOLDER.format(idx)
        result = result.replace(placeholder, block)
    
    return result


class BasePlugin(ABC):
    """Abstract base class for all documentation plugins.
    
    All plugins MUST implement detect() and fix() methods.
    All plugins MUST use protect_code_blocks() before applying fixes.
    """
    
    PLUGIN_NAME: str = "base"
    PLUGIN_VERSION: str = "1.0.0"
    PLUGIN_DESCRIPTION: str = "Base plugin"
    REQUIRES_LLM: bool = False
    FIX_ID: int = 0
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize plugin with optional configuration."""
        self.config = config or {}
        self.logger = logging.getLogger(f"plugin.{self.PLUGIN_NAME}")
        self._issues_detected = 0
        self._issues_fixed = 0
    
    @abstractmethod
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect issues in the content.
        
        IMPORTANT: Use strip_code_blocks() on content before pattern matching
        to avoid detecting issues inside code blocks.
        
        Args:
            content: The markdown content to analyze
            url: URL or path of the document
            **kwargs: Additional context (soup, raw_html, etc.)
            
        Returns:
            List of detected issues
        """
        pass
    
    @abstractmethod
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply fixes to the content.
        
        CRITICAL: Use protect_code_blocks() and restore_code_blocks() to
        ensure code blocks are NEVER modified.
        
        Args:
            content: The markdown content to fix
            issues: List of issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with modified content
        """
        pass
    
    def increment_detected(self, count: int = 1):
        """Track number of issues detected."""
        self._issues_detected += count
    
    def increment_fixed(self, count: int = 1):
        """Track number of issues fixed."""
        self._issues_fixed += count
    
    def get_stats(self) -> Dict[str, int]:
        """Get plugin statistics."""
        return {
            "detected": self._issues_detected,
            "fixed": self._issues_fixed
        }
    
    def reset_stats(self):
        """Reset plugin statistics."""
        self._issues_detected = 0
        self._issues_fixed = 0
    
    def log_info(self, message: str):
        """Log info message."""
        self.logger.info(f"[{self.PLUGIN_NAME}] {message}")
    
    def log_error(self, message: str):
        """Log error message."""
        self.logger.error(f"[{self.PLUGIN_NAME}] {message}")
    
    def log_debug(self, message: str):
        """Log debug message."""
        self.logger.debug(f"[{self.PLUGIN_NAME}] {message}")


class PatternBasedPlugin(BasePlugin):
    """Base class for plugins that use regex patterns.
    
    Provides helper methods for safe pattern-based detection and fixing
    that automatically protect code blocks.
    """
    
    def detect_with_pattern(
        self,
        content: str,
        pattern: re.Pattern,
        category: str,
        description: str,
        suggestion_template: str = ""
    ) -> List[Issue]:
        """Detect issues using a regex pattern, excluding code blocks.
        
        Args:
            content: The markdown content
            pattern: Compiled regex pattern
            category: Issue category
            description: Issue description
            suggestion_template: Template for suggestion (use {match} for match text)
            
        Returns:
            List of detected issues
        """
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        issues = []
        for match in pattern.finditer(safe_content):
            suggestion = suggestion_template.format(match=match.group(0)) if suggestion_template else ""
            issue = Issue(
                category=category,
                location=f"Position {match.start()}",
                description=description,
                suggestion=suggestion,
                context=match.group(0)[:100]
            )
            issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix_with_pattern(
        self,
        content: str,
        pattern: re.Pattern,
        replacement: str,
        change_description: str
    ) -> FixResult:
        """Apply a regex-based fix, protecting code blocks.
        
        CRITICAL: This method automatically protects code blocks.
        
        Args:
            content: The markdown content
            pattern: Compiled regex pattern
            replacement: Replacement string (can use backreferences)
            change_description: Description of the change
            
        Returns:
            FixResult with modified content
        """
        if not content:
            return FixResult(success=False, error="No content")
        
        # Protect code blocks
        protected_content, code_blocks = protect_code_blocks(content)
        
        # Apply fix
        new_content, count = pattern.subn(replacement, protected_content)
        
        # Restore code blocks
        result = restore_code_blocks(new_content, code_blocks)
        
        changes = []
        if count > 0:
            changes.append(f"{change_description}: {count} instances")
            self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )


class LLMAssistedPlugin(BasePlugin):
    """Base class for plugins that use LLM assistance.
    
    Provides helper methods for LLM-based detection and fixing
    with proper prompt construction and response validation.
    """
    
    REQUIRES_LLM = True
    
    def __init__(self, config: Optional[Dict[str, Any]] = None, llm_client: Any = None):
        """Initialize with optional LLM client."""
        super().__init__(config)
        self.llm_client = llm_client
    
    def set_llm_client(self, client: Any):
        """Set the LLM client."""
        self.llm_client = client
    
    def call_llm(self, prompt: str, original_text: str) -> Optional[str]:
        """Call LLM with prompt and validate response.
        
        Args:
            prompt: The prompt to send to LLM
            original_text: Original text for validation
            
        Returns:
            LLM response or None if validation fails
        """
        if not self.llm_client:
            self.log_error("No LLM client configured")
            return None
        
        result = None
        if hasattr(self.llm_client, '_generate_with_url_protection'):
            result = self.llm_client._generate_with_url_protection(prompt, original_text)
        elif hasattr(self.llm_client, '_generate'):
            result = self.llm_client._generate(prompt)
        
        if result:
            result = self._validate_llm_response(result, original_text)
        
        return result
    
    def _validate_llm_response(self, response: str, original_text: str) -> Optional[str]:
        """Validate LLM response to prevent content destruction.
        
        Args:
            response: The LLM response
            original_text: The original text
            
        Returns:
            Response if valid, None otherwise
        """
        if not response:
            return None
        
        # Reject responses with template placeholders
        if '{text}' in response or '{{text}}' in response:
            self.log_error("LLM returned template placeholder - rejecting")
            return None
        
        # Check content length (allow 80-130% of original)
        original_len = len(original_text.strip())
        response_len = len(response.strip())
        
        if original_len > 100:
            if response_len < original_len * 0.8:
                self.log_error(f"LLM response too short ({response_len} vs {original_len})")
                return None
            if response_len > original_len * 1.3:
                self.log_error(f"LLM response too long ({response_len} vs {original_len})")
                return None
        
        # Preserve YAML front matter
        if original_text.strip().startswith('---'):
            if not response.strip().startswith('---'):
                self.log_error("LLM removed YAML front matter - rejecting")
                return None
        
        # Reject suspiciously short responses
        if response_len < 50 and original_len > 200:
            self.log_error("LLM response suspiciously short - rejecting")
            return None
        
        return response
    
    def fix_with_llm(
        self,
        content: str,
        prompt_template: str,
        issues_text: str,
        change_description: str
    ) -> FixResult:
        """Apply LLM-based fix, protecting code blocks.
        
        CRITICAL: Code blocks are extracted, LLM processes only non-code content,
        then code blocks are restored exactly as they were.
        
        Args:
            content: The markdown content
            prompt_template: Template with {text} placeholder
            issues_text: Description of issues to fix
            change_description: Description of the change
            
        Returns:
            FixResult with modified content
        """
        if not content:
            return FixResult(success=False, error="No content")
        
        if not self.llm_client:
            return FixResult(success=False, error="No LLM client")
        
        # Protect code blocks
        protected_content, code_blocks = protect_code_blocks(content)
        
        # Build prompt with protected content
        prompt = prompt_template.format(text=protected_content)
        
        # Call LLM
        result = self.call_llm(prompt, protected_content)
        
        if not result:
            return FixResult(success=False, error="LLM returned invalid response")
        
        # Restore code blocks in LLM output
        final_content = restore_code_blocks(result, code_blocks)
        
        # Verify code blocks are unchanged
        _, new_code_blocks = protect_code_blocks(final_content)
        if len(new_code_blocks) != len(code_blocks):
            self.log_error("Code block count changed - rejecting LLM response")
            return FixResult(success=False, error="LLM modified code block structure")
        
        for i, (orig, new) in enumerate(zip(code_blocks, new_code_blocks)):
            if orig != new:
                self.log_error(f"Code block {i} was modified - rejecting")
                return FixResult(success=False, error="LLM modified code block content")
        
        self.increment_fixed(1)
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=[change_description]
        )
