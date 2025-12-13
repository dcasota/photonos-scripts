#!/usr/bin/env python3
"""
Indentation Plugin for Photon OS Documentation Lecturer

Detects and fixes list and nested content indentation issues.

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


class IndentationPlugin(LLMAssistedPlugin):
    """Plugin for detecting and fixing indentation issues.
    
    All detection and fixing operations exclude fenced code blocks.
    """
    
    PLUGIN_NAME = "indentation"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Fix list and content indentation"
    REQUIRES_LLM = True
    FIX_ID = 11
    
    # Mixed tabs and spaces
    MIXED_INDENT = re.compile(r'^( +\t|\t+ )', re.MULTILINE)
    
    # Inconsistent list indentation
    LIST_INDENT_PATTERN = re.compile(r'^(\s*)[-*+]\s', re.MULTILINE)
    
    # LLM prompt template
    PROMPT_TEMPLATE = """You are a markdown formatting expert. Fix ONLY the indentation issues listed below.

CRITICAL RULES - VIOLATING ANY WILL CORRUPT THE DOCUMENTATION:
1. Output ONLY the corrected text - no explanations
2. Preserve ALL content exactly - only fix indentation
3. Do NOT modify fenced code blocks (``` or ~~~) or their content
4. Do NOT modify inline code (`...`)
5. Lines with 4+ spaces at start that are NOT lists are intentional code blocks
6. Use consistent 2-space or 4-space indentation for lists
7. Nested list items should be indented relative to parent
8. Preserve YAML front matter exactly
9. Do NOT merge lines or change line breaks

INDENTATION ISSUES TO FIX:
{issues}

Text to fix:
{text}

Return ONLY the corrected text."""
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect indentation issues, excluding code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of indentation issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Strip code blocks before detection
        safe_content = strip_code_blocks(content)
        
        # Check for mixed tabs and spaces
        for match in self.MIXED_INDENT.finditer(safe_content):
            issue = Issue(
                category=self.PLUGIN_NAME,
                location=f"Line with mixed indent",
                description="Mixed tabs and spaces in indentation",
                suggestion="Use consistent spaces for indentation",
                context=match.group(0)[:30]
            )
            issues.append(issue)
        
        # Check for inconsistent list indentation
        indents = set()
        for match in self.LIST_INDENT_PATTERN.finditer(safe_content):
            indent = len(match.group(1))
            if indent > 0:
                indents.add(indent)
        
        # If we have inconsistent indent levels (not multiples of 2 or 4)
        if indents:
            base_indent = min(indents) if indents else 2
            for indent in indents:
                if indent % base_indent != 0 and indent != 0:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location="Document",
                        description=f"Inconsistent list indentation ({indent} spaces)",
                        suggestion=f"Use multiples of {base_indent} for indentation",
                        context=""
                    )
                    issues.append(issue)
                    break
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Apply indentation fixes, protecting code blocks.
        
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
        
        # Protect code blocks FIRST
        protected_content, code_blocks = protect_code_blocks(content)
        
        result = protected_content
        changes = []
        
        # Fix simple issues with regex (no LLM needed)
        
        # Convert tabs to spaces in indentation
        def fix_mixed_indent(match):
            return match.group(0).replace('\t', '    ')
        
        new_result = re.sub(r'^\t+', fix_mixed_indent, result, flags=re.MULTILINE)
        if new_result != result:
            changes.append("Converted tabs to spaces")
            result = new_result
            self.increment_fixed(1)
        
        # Restore code blocks UNCHANGED
        final_content = restore_code_blocks(result, code_blocks)
        
        return FixResult(
            success=True,
            modified_content=final_content,
            changes_made=changes
        )
