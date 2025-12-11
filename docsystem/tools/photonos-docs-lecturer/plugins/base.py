#!/usr/bin/env python3
"""
Base Plugin Module for Photon OS Documentation Lecturer

Provides the abstract base class and common functionality for all plugins.
Each plugin inherits from BasePlugin and implements detect() and fix() methods.

Version: 1.0.0
"""

from __future__ import annotations

import logging
import os
import re
import threading
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

__version__ = "1.0.0"


@dataclass
class Issue:
    """Represents a detected documentation issue."""
    category: str
    location: str
    description: str
    suggestion: str
    line_number: Optional[int] = None
    context: Optional[str] = None
    severity: str = "medium"  # low, medium, high, critical
    fixable: bool = True
    requires_llm: bool = False
    metadata: Dict[str, Any] = field(default_factory=dict)


@dataclass 
class FixResult:
    """Result of applying a fix."""
    success: bool
    modified_content: Optional[str] = None
    changes_made: List[str] = field(default_factory=list)
    error: Optional[str] = None


class PluginLogger:
    """Thread-safe logger for plugins with dedicated log file."""
    
    _loggers: Dict[str, logging.Logger] = {}
    _lock = threading.Lock()
    
    @classmethod
    def get_logger(cls, plugin_name: str, log_dir: str = "/var/log") -> logging.Logger:
        """Get or create a logger for a plugin.
        
        Args:
            plugin_name: Name of the plugin (e.g., 'grammar', 'markdown')
            log_dir: Directory for log files
            
        Returns:
            Configured logger instance
        """
        with cls._lock:
            logger_key = f"photonos-docs-lecturer-{plugin_name}"
            
            if logger_key in cls._loggers:
                return cls._loggers[logger_key]
            
            logger = logging.getLogger(logger_key)
            logger.setLevel(logging.INFO)
            
            # Prevent duplicate handlers
            if not logger.handlers:
                # File handler
                log_file = os.path.join(log_dir, f"photonos-docs-lecturer-{plugin_name}.log")
                try:
                    os.makedirs(log_dir, exist_ok=True)
                    file_handler = logging.FileHandler(log_file, mode='a', encoding='utf-8')
                    file_handler.setFormatter(logging.Formatter(
                        '%(asctime)s - %(levelname)s - [%(name)s] %(message)s'
                    ))
                    logger.addHandler(file_handler)
                except PermissionError:
                    # Fall back to current directory if /var/log not writable
                    pass
                
                # Stream handler for errors only
                stream_handler = logging.StreamHandler()
                stream_handler.setLevel(logging.WARNING)
                stream_handler.setFormatter(logging.Formatter(
                    '%(levelname)s - [%(name)s] %(message)s'
                ))
                logger.addHandler(stream_handler)
            
            cls._loggers[logger_key] = logger
            return logger


class BasePlugin(ABC):
    """Abstract base class for all documentation plugins.
    
    Each plugin must implement:
    - detect(): Find issues in content
    - fix(): Apply fixes to content
    
    Plugins are thread-safe and maintain their own state.
    """
    
    # Plugin metadata - override in subclasses
    PLUGIN_NAME: str = "base"
    PLUGIN_VERSION: str = "1.0.0"
    PLUGIN_DESCRIPTION: str = "Base plugin"
    REQUIRES_LLM: bool = False
    FIX_ID: Optional[int] = None  # ID for --fix parameter
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the plugin.
        
        Args:
            llm_client: Optional LLM client for AI-assisted fixes
            config: Optional configuration dictionary
        """
        self.llm_client = llm_client
        self.config = config or {}
        self.logger = PluginLogger.get_logger(self.PLUGIN_NAME)
        self._lock = threading.Lock()
        
        # Statistics
        self._issues_detected = 0
        self._fixes_applied = 0
        self._stats_lock = threading.Lock()
    
    @abstractmethod
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect issues in content.
        
        Args:
            content: The content to analyze (HTML or markdown)
            url: URL of the page being analyzed
            **kwargs: Additional context (e.g., soup object, local_path)
            
        Returns:
            List of detected issues
        """
        pass
    
    @abstractmethod
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply fixes to content.
        
        Args:
            content: The markdown content to fix
            issues: List of issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with modified content and changes made
        """
        pass
    
    def can_fix(self, issue: Issue) -> bool:
        """Check if this plugin can fix the given issue.
        
        Args:
            issue: The issue to check
            
        Returns:
            True if plugin can fix this issue
        """
        return issue.category == self.PLUGIN_NAME and issue.fixable
    
    def increment_detected(self, count: int = 1):
        """Thread-safe increment of detected issues count."""
        with self._stats_lock:
            self._issues_detected += count
    
    def increment_fixed(self, count: int = 1):
        """Thread-safe increment of fixes applied count."""
        with self._stats_lock:
            self._fixes_applied += count
    
    def get_stats(self) -> Dict[str, int]:
        """Get plugin statistics.
        
        Returns:
            Dictionary with detection and fix counts
        """
        with self._stats_lock:
            return {
                "issues_detected": self._issues_detected,
                "fixes_applied": self._fixes_applied
            }
    
    def reset_stats(self):
        """Reset statistics counters."""
        with self._stats_lock:
            self._issues_detected = 0
            self._fixes_applied = 0
    
    def validate_content(self, content: str) -> bool:
        """Validate that content is suitable for processing.
        
        Args:
            content: Content to validate
            
        Returns:
            True if content is valid
        """
        if not content or not isinstance(content, str):
            return False
        if len(content.strip()) < 10:
            return False
        return True
    
    def log_issue(self, issue: Issue):
        """Log a detected issue."""
        self.logger.info(f"Detected: {issue.category} - {issue.description[:100]}")
    
    def log_fix(self, description: str):
        """Log an applied fix."""
        self.logger.info(f"Fixed: {description[:100]}")
    
    def log_error(self, error: str):
        """Log an error."""
        self.logger.error(error)


class PatternBasedPlugin(BasePlugin):
    """Base class for plugins that use regex patterns for detection.
    
    Provides common functionality for pattern-based issue detection
    and fixing, which is the most common plugin type.
    """
    
    # Override in subclasses: list of (pattern, description, suggestion) tuples
    DETECTION_PATTERNS: List[Tuple[re.Pattern, str, str]] = []
    
    # Override in subclasses: list of (pattern, replacement) tuples for fixing
    FIX_PATTERNS: List[Tuple[re.Pattern, str]] = []
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect issues using configured patterns.
        
        Args:
            content: Content to analyze
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of detected issues
        """
        issues = []
        
        if not self.validate_content(content):
            return issues
        
        for pattern, description, suggestion in self.DETECTION_PATTERNS:
            for match in pattern.finditer(content):
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Match: {match.group(0)[:50]}...",
                    description=description,
                    suggestion=suggestion,
                    context=match.group(0)[:100],
                    metadata={"match": match.group(0), "start": match.start(), "end": match.end()}
                )
                issues.append(issue)
                self.log_issue(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply pattern-based fixes.
        
        Args:
            content: Content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with modified content
        """
        if not self.validate_content(content):
            return FixResult(success=False, error="Invalid content")
        
        result = content
        changes = []
        
        for pattern, replacement in self.FIX_PATTERNS:
            new_result, count = pattern.subn(replacement, result)
            if count > 0:
                changes.append(f"Applied {pattern.pattern[:30]}... ({count} replacements)")
                result = new_result
                self.increment_fixed(count)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )


class LLMAssistedPlugin(BasePlugin):
    """Base class for plugins that require LLM assistance for fixing.
    
    Provides common functionality for LLM-based issue detection
    and fixing. Includes prompt templates and response handling.
    """
    
    REQUIRES_LLM = True
    
    # Override in subclasses: prompt template for the LLM
    LLM_PROMPT_TEMPLATE: str = ""
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply LLM-assisted fixes.
        
        Args:
            content: Content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with modified content
        """
        if not self.llm_client:
            return FixResult(
                success=False,
                error="LLM client required but not provided"
            )
        
        if not self.validate_content(content):
            return FixResult(success=False, error="Invalid content")
        
        try:
            # Build prompt from template
            prompt = self._build_prompt(content, issues)
            
            # Call LLM
            response = self._call_llm(prompt, content)
            
            if response:
                self.increment_fixed(len(issues))
                return FixResult(
                    success=True,
                    modified_content=response,
                    changes_made=[f"Applied LLM fixes for {len(issues)} issues"]
                )
            else:
                return FixResult(
                    success=False,
                    error="LLM returned empty response"
                )
        except Exception as e:
            self.log_error(f"LLM fix failed: {e}")
            return FixResult(success=False, error=str(e))
    
    def _build_prompt(self, content: str, issues: List[Issue]) -> str:
        """Build LLM prompt from template and issues.
        
        Override in subclasses for custom prompt building.
        """
        issue_desc = "\n".join([f"- {i.description}" for i in issues[:10]])
        return self.LLM_PROMPT_TEMPLATE.format(
            issues=issue_desc,
            text=content
        )
    
    def _call_llm(self, prompt: str, original_text: str) -> Optional[str]:
        """Call the LLM with the prompt.
        
        Override in subclasses for custom LLM interaction.
        """
        if hasattr(self.llm_client, '_generate_with_url_protection'):
            return self.llm_client._generate_with_url_protection(prompt, original_text)
        elif hasattr(self.llm_client, '_generate'):
            return self.llm_client._generate(prompt)
        return None


def strip_code_blocks(text: str) -> str:
    """Remove code blocks from text for analysis.
    
    Strips:
    - Fenced code blocks (```...```)
    - Inline code (`...`)
    - Indented code blocks (4+ spaces or tab at start)
    
    Args:
        text: Text containing code blocks
        
    Returns:
        Text with code blocks removed
    """
    if not text:
        return ""
    
    # Remove fenced code blocks
    result = re.sub(r'```[\s\S]*?```', '', text)
    
    # Remove inline code
    result = re.sub(r'`[^`]+`', '', result)
    
    # Remove indented code blocks (4+ spaces or tab at line start)
    result = re.sub(r'^(?:    |\t).*$', '', result, flags=re.MULTILINE)
    
    return result


def extract_urls(text: str) -> List[str]:
    """Extract all URLs from text.
    
    Args:
        text: Text containing URLs
        
    Returns:
        List of extracted URLs
    """
    url_pattern = re.compile(r'https?://[^\s<>"\')\]]+')
    return url_pattern.findall(text)


def extract_markdown_links(text: str) -> List[Tuple[str, str]]:
    """Extract markdown links from text.
    
    Args:
        text: Text containing markdown links
        
    Returns:
        List of (link_text, url) tuples
    """
    link_pattern = re.compile(r'\[([^\]]+)\]\(([^)]+)\)')
    return link_pattern.findall(text)
