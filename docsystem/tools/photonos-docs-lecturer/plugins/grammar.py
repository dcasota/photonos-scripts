#!/usr/bin/env python3
"""
Grammar Plugin for Photon OS Documentation Lecturer

Detects and fixes grammar issues using LanguageTool and optional LLM assistance.

CRITICAL: All operations protect fenced code blocks from modification.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import (
    LLMAssistedPlugin,
    Issue,
    FixResult,
    strip_code_blocks,
    protect_code_blocks,
    restore_code_blocks,
)

__version__ = "2.0.0"


class GrammarPlugin(LLMAssistedPlugin):
    """Plugin for detecting and fixing grammar issues.
    
    Uses LanguageTool for detection and optional LLM for complex fixes.
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "grammar"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Fix grammar and spelling issues"
    REQUIRES_LLM = True
    FIX_ID = 9
    
    # LLM prompt template for grammar fixes
    PROMPT_TEMPLATE = """You are a technical documentation editor. Fix ONLY the grammar issues listed below.

CRITICAL RULES - VIOLATING ANY WILL CORRUPT THE DOCUMENTATION:
1. Output ONLY the corrected text - no explanations, no preamble
2. Preserve ALL formatting: headings (#), lists (-/*), links, code blocks
3. Do NOT modify content inside code blocks (``` or ~~~)
4. Do NOT modify inline code (`...`)
5. Do NOT add or remove any content
6. Do NOT escape underscores with backslash
7. Lines starting with 4+ spaces or tab are CODE - do NOT modify
8. Preserve YAML front matter (---) exactly as-is
9. Do NOT add ANY commentary like "(wait..." or "(note:..."
10. If unsure about a fix, leave the text unchanged

GRAMMAR ISSUES TO FIX (ONLY fix these, nothing else):
{issues}

Text to fix:
{text}

Return ONLY the corrected text. Do NOT add any preamble, explanation, or commentary."""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None, llm_client: Any = None):
        """Initialize with optional LanguageTool."""
        super().__init__(config, llm_client)
        self._language_tool = None
        self._init_language_tool()
    
    def _init_language_tool(self):
        """Initialize LanguageTool if available."""
        try:
            import language_tool_python
            self._language_tool = language_tool_python.LanguageTool('en-US')
        except ImportError:
            self.log_info("LanguageTool not available - detection disabled")
        except Exception as e:
            self.log_error(f"Failed to initialize LanguageTool: {e}")
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect grammar issues, excluding code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of grammar issues
        """
        issues = []
        
        if not content or not self._language_tool:
            return issues
        
        # Strip code blocks before checking grammar
        safe_content = strip_code_blocks(content)
        
        try:
            matches = self._language_tool.check(safe_content)
            
            for match in matches:
                # Skip certain rule categories
                if match.ruleId in ['WHITESPACE_RULE', 'EN_QUOTES', 
                                    'UPPERCASE_SENTENCE_START', 'COMMA_PARENTHESIS_WHITESPACE',
                                    'POSSESSIVE_APOSTROPHE']:  # False positive for noun adjuncts
                    continue
                
                # For spelling rules, skip hyphenated terms, camelCase, and underscored terms
                if match.ruleId in ['MORFOLOGIK_RULE_EN_US', 'MORFOLOGIK_RULE_EN_GB']:
                    matched_text = safe_content[match.offset:match.offset + match.errorLength]
                    
                    # Skip hyphenated terms (e.g., cloud-init, systemd-networkd)
                    if '-' in matched_text:
                        continue
                    
                    # Skip camelCase or PascalCase (e.g., NetworkManager)
                    if any(c.isupper() for c in matched_text[1:]) and any(c.islower() for c in matched_text):
                        continue
                    
                    # Skip terms with underscores (e.g., cloud_init)
                    if '_' in matched_text:
                        continue
                
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Offset {match.offset}",
                    description=match.message,
                    suggestion=', '.join(match.replacements[:3]) if match.replacements else "",
                    context=match.context,
                    metadata={
                        'rule_id': match.ruleId,
                        'offset': match.offset,
                        'length': match.errorLength
                    }
                )
                issues.append(issue)
        except Exception as e:
            self.log_error(f"Grammar detection failed: {e}")
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply grammar fixes using LLM, protecting code blocks.
        
        CRITICAL: Code blocks are protected and restored unchanged.
        
        Args:
            content: Markdown content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with corrected content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        if not issues:
            return FixResult(success=True, modified_content=content, changes_made=[])
        
        if not self.llm_client:
            return FixResult(success=False, error="LLM client required for grammar fixes")
        
        # Protect code blocks FIRST
        protected_content, code_blocks = protect_code_blocks(content)
        
        # Build issues text for prompt
        issues_text = "\n".join([
            f"- {issue.description}: {issue.context[:50]}"
            for issue in issues[:20]  # Limit to avoid token overflow
        ])
        
        # Build prompt
        prompt = self.PROMPT_TEMPLATE.format(
            issues=issues_text,
            text=protected_content
        )
        
        # Call LLM
        result = self.call_llm(prompt, protected_content)
        
        if not result:
            return FixResult(success=False, error="LLM returned invalid response")
        
        # Restore code blocks in LLM output
        final_content = restore_code_blocks(result, code_blocks)
        
        # Verify code blocks unchanged
        _, new_code_blocks = protect_code_blocks(final_content)
        if len(new_code_blocks) != len(code_blocks):
            self.log_error("Code block count changed - rejecting LLM response")
            return FixResult(success=False, error="LLM modified code block structure")
        
        for i, (orig, new) in enumerate(zip(code_blocks, new_code_blocks)):
            if orig != new:
                self.log_error(f"Code block {i} modified - rejecting")
                return FixResult(success=False, error="LLM modified code block content")
        
        self.increment_fixed(len(issues))
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=[f"Fixed {len(issues)} grammar issues"]
        )
