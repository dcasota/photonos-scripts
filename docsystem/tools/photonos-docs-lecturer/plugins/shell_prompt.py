#!/usr/bin/env python3
"""
Shell Prompt Plugin for Photon OS Documentation Lecturer

Detects shell prompts ($ # root@) in code blocks that might need removal
for copy-paste friendliness.

CRITICAL: This plugin only detects issues - it does NOT modify code blocks.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "2.0.0"


class ShellPromptPlugin(BasePlugin):
    """Plugin for detecting shell prompts in code blocks.
    
    Detection only - removal is a stylistic choice that should be manual.
    """
    
    PLUGIN_NAME = "shell_prompt"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect shell prompts in code blocks"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix - this is intentional
    
    # Shell prompt patterns
    PROMPTS = [
        re.compile(r'^(\$|#)\s+', re.MULTILINE),  # $ or # at line start
        re.compile(r'^root@\S+[:#]\s*', re.MULTILINE),  # root@host:
        re.compile(r'^\[\S+@\S+\s+\S+\]\$\s*', re.MULTILINE),  # [user@host dir]$
        re.compile(r'^>\s+', re.MULTILINE),  # PowerShell-style >
    ]
    
    # Fenced code block pattern
    FENCED_BLOCK = re.compile(r'```[\w]*\n(.*?)```', re.DOTALL)
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect shell prompts inside code blocks.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of shell prompt issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Find all fenced code blocks
        for block_match in self.FENCED_BLOCK.finditer(content):
            block_content = block_match.group(1)
            
            # Check for shell prompts in this block
            for prompt_pattern in self.PROMPTS:
                if prompt_pattern.search(block_content):
                    # Get first line as preview
                    first_line = block_content.split('\n')[0][:50]
                    
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Code block",
                        description="Shell prompt found in code block",
                        suggestion="Consider removing prompts for copy-paste friendliness",
                        context=first_line,
                        severity="low"
                    )
                    issues.append(issue)
                    break  # Only one issue per block
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for shell prompts.
        
        Shell prompts in code blocks are often intentional to show
        interactive sessions. Removal should be a manual decision.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Shell prompt removal is a stylistic choice - review manually"]
        )
