#!/usr/bin/env python3
"""
Grammar Plugin for Photon OS Documentation Lecturer

Detects and fixes grammar and spelling issues using LanguageTool.
Requires LLM for applying fixes intelligently.

Version: 1.0.0
"""

from __future__ import annotations

import re
import threading
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, LLMAssistedPlugin, strip_code_blocks

__version__ = "1.0.0"

# Lazy-loaded language_tool_python
language_tool_python = None


def _load_language_tool():
    """Lazy load language_tool_python module."""
    global language_tool_python
    if language_tool_python is None:
        import language_tool_python as ltp
        language_tool_python = ltp
    return language_tool_python


class GrammarPlugin(LLMAssistedPlugin):
    """Plugin for detecting and fixing grammar/spelling issues.
    
    Uses LanguageTool for detection and LLM for intelligent fixing.
    """
    
    PLUGIN_NAME = "grammar"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Detect and fix grammar and spelling issues"
    REQUIRES_LLM = True
    FIX_ID = 9
    
    # LLM prompt template for grammar fixes
    LLM_PROMPT_TEMPLATE = """You are a documentation grammar reviewer. Fix ONLY the specific grammar issues listed below.

CRITICAL RULES - VIOLATING ANY WILL CORRUPT THE DOCUMENTATION:

=== PRODUCT NAMES (NEVER MODIFY) ===
These product names MUST remain EXACTLY as written - never delete, abbreviate, or modify:
- "Photon OS" - ALWAYS keep both words together, never just "OS" or "Photon"
- "VMware vSphere", "VMware Workstation", "VMware Fusion" - keep complete
- "VMware" - never change spelling or case
- "Docker", "Kubernetes", "GitHub", "Google Compute Engine", "Amazon Elastic Compute"

=== PATHS AND TECHNICAL IDENTIFIERS (NEVER MODIFY) ===
- Relative paths: anything with "/" and file extension (e.g., ../../images/fs-version.png)
- Directory paths: /etc/yum.repos.d/ - dots in directory names like "yum.repos.d" are VALID
- File paths: /var/cache/tdnf, /media/cdrom, /dev/sdc
- Placeholders: __URL_PLACEHOLDER_N__, __PATH_PLACEHOLDER_N__
- Technical identifiers with underscores: vg_name, lv_name, disable_ec2_metadata

=== CODE BLOCKS (STRICT SEPARATION) ===
- Content inside triple backticks (```...```) is a CODE BLOCK - DO NOT modify ANY content inside
- Content inside single backticks (`...`) is INLINE CODE - copy the ENTIRE `...` block EXACTLY
- Example: `*.raw` must stay as `*.raw` - never change to `*.raw,` or `*.raw` and
- Lines starting with TAB or 4+ spaces are CODE OUTPUT - DO NOT modify
- NEVER add backticks inside code blocks
- NEVER add backticks to content that didn't have them before
- NEVER remove the closing backtick from inline code

=== PRESERVE EXACTLY ===
- YAML front matter (--- ... ---) at file start
- All URLs (http://, https://)
- All line breaks and indentation
- Markdown headers (#, ##, ###, etc.)
- List formatting (-, *, 1., 2., etc.)
- All parenthetical notes like "(NOTE: DO NOT use https://)" - NEVER delete these

=== DO NOT ===
- Do NOT delete ANY text
- Do NOT add backticks to words that didn't have them
- Do NOT change product names
- Do NOT modify paths (relative or absolute)
- Do NOT add explanations or commentary
- Do NOT add ending backticks after periods

GRAMMAR ISSUES TO FIX (ONLY fix these, nothing else):
{issues}

Text to fix:
{{text}}

Return ONLY the corrected text. Do NOT add any preamble, explanation, or commentary."""
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the grammar plugin.
        
        Args:
            llm_client: LLM client for applying fixes
            config: Configuration with 'language' key (default: 'en-EN')
        """
        super().__init__(llm_client, config)
        self.language = config.get('language', 'en-EN') if config else 'en-EN'
        self._grammar_tool: Optional[Any] = None
        self._tool_lock = threading.Lock()
        self._tool_port = None
    
    def _get_grammar_tool(self):
        """Get or create the grammar tool instance (thread-safe).
        
        Returns:
            LanguageTool instance or None if initialization fails
        """
        with self._tool_lock:
            if self._grammar_tool is None:
                try:
                    ltp = _load_language_tool()
                    # Use a specific port range to avoid conflicts
                    import random
                    self._tool_port = random.randint(8000, 9000)
                    self.logger.info(f"Initializing grammar checker on port {self._tool_port}")
                    self._grammar_tool = ltp.LanguageTool(self.language)
                    self.logger.info(f"Grammar checker initialized for language: {self.language}")
                except Exception as e:
                    self.logger.error(f"Failed to initialize grammar tool: {e}")
                    return None
            return self._grammar_tool
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect grammar and spelling issues.
        
        Args:
            content: HTML or markdown content
            url: URL of the page
            **kwargs: May include 'text' for pre-extracted plain text
            
        Returns:
            List of grammar issues
        """
        issues = []
        
        # Get plain text, stripping code blocks
        text = kwargs.get('text', content)
        text_for_check = strip_code_blocks(text)
        
        if not text_for_check or len(text_for_check.strip()) < 20:
            return issues
        
        grammar_tool = self._get_grammar_tool()
        if grammar_tool is None:
            return issues
        
        try:
            matches = grammar_tool.check(text_for_check)
            
            for match in matches:
                # Skip certain rule categories
                if self._should_skip_match(match):
                    continue
                
                suggestion = ', '.join(match.replacements[:3]) if match.replacements else "No suggestion"
                
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Context: ...{match.context}...",
                    description=match.message,
                    suggestion=suggestion,
                    line_number=match.offset,
                    context=match.context,
                    metadata={
                        'rule_id': match.rule_id,
                        'replacements': match.replacements[:5] if match.replacements else [],
                        'offset': match.offset,
                        'error_length': match.error_length,
                        'message': match.message
                    }
                )
                issues.append(issue)
        except Exception as e:
            self.logger.error(f"Grammar check failed for {url}: {e}")
        
        self.increment_detected(len(issues))
        return issues
    
    def _should_skip_match(self, match) -> bool:
        """Check if a grammar match should be skipped.
        
        Args:
            match: LanguageTool match object
            
        Returns:
            True if match should be skipped
        """
        # Skip certain rule categories that produce false positives
        skip_rules = {
            'WHITESPACE_RULE',
            'EN_QUOTES',
            'COMMA_PARENTHESIS_WHITESPACE',
            'UNLIKELY_OPENING_PUNCTUATION',
            'UPPERCASE_SENTENCE_START',  # Often wrong for technical docs
        }
        
        if match.rule_id in skip_rules:
            return True
        
        # Skip very short matches (often false positives)
        if match.error_length < 2:
            return True
        
        return False
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply grammar fixes using LLM.
        
        Args:
            content: Markdown content to fix
            issues: Grammar issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not issues:
            return FixResult(success=True, modified_content=content, changes_made=[])
        
        if not self.llm_client:
            return FixResult(
                success=False,
                error="LLM client required for grammar fixes"
            )
        
        try:
            # Build issue description for prompt
            issue_desc = "\n".join([
                f"- {i.metadata.get('message', i.description)}: {i.suggestion}"
                for i in issues[:10]
            ])
            
            # Use LLM client's fix_grammar method if available
            if hasattr(self.llm_client, 'fix_grammar'):
                issue_dicts = [
                    {'message': i.metadata.get('message', i.description), 'suggestion': i.suggestion}
                    for i in issues
                ]
                result = self.llm_client.fix_grammar(content, issue_dicts)
            else:
                # Fall back to generic LLM call
                prompt = self.LLM_PROMPT_TEMPLATE.format(issues=issue_desc)
                result = self._call_llm(prompt, content)
            
            if result and result != content:
                self.increment_fixed(len(issues))
                return FixResult(
                    success=True,
                    modified_content=result,
                    changes_made=[f"Applied grammar fixes for {len(issues)} issues"]
                )
            else:
                return FixResult(
                    success=True,
                    modified_content=content,
                    changes_made=[]
                )
        except Exception as e:
            self.logger.error(f"Grammar fix failed: {e}")
            return FixResult(success=False, error=str(e))
    
    def cleanup(self):
        """Clean up resources."""
        with self._tool_lock:
            if self._grammar_tool is not None:
                try:
                    self._grammar_tool.close()
                except Exception:
                    pass
                self._grammar_tool = None
