#!/usr/bin/env python3
"""
Shell Prompt Plugin for Photon OS Documentation Lecturer

Detects and removes shell prompts from code blocks.
This is a feature (opt-in) that modifies code block formatting.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional, Tuple

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class ShellPromptPlugin(BasePlugin):
    """Plugin for detecting and removing shell prompts in code blocks.
    
    This is an optional feature that removes shell prompts like:
    $ command, # command, > command, etc.
    """
    
    PLUGIN_NAME = "shell_prompt"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Remove shell prompts in code blocks"
    REQUIRES_LLM = False
    FIX_ID = None  # This is a feature, not a fix
    FEATURE_ID = 1
    
    # Shell prompt patterns to detect and remove
    PROMPT_PATTERNS: List[Tuple[re.Pattern, str]] = [
        (re.compile(r'^(\s*)(\$\s+)(.+)$', re.MULTILINE), '$ prompt'),
        (re.compile(r'^(\s*)(>\s+)(.+)$', re.MULTILINE), '> prompt'),
        (re.compile(r'^(\s*)(%\s+)(.+)$', re.MULTILINE), '% prompt'),
        (re.compile(r'^(\s*)(~\s+)(.+)$', re.MULTILINE), '~ prompt'),
        (re.compile(r'^(\s*)(❯\s*)(.+)$', re.MULTILINE), '❯ prompt'),
        (re.compile(r'^(\s*)(➜\s+)(.+)$', re.MULTILINE), '➜ prompt'),
        (re.compile(r'^(\s*)(root@\S+[#$]\s*)(.+)$', re.MULTILINE), 'root@host# prompt'),
        (re.compile(r'^(\s*)(\w+@\S+[#$%]\s*)(.+)$', re.MULTILINE), 'user@host$ prompt'),
    ]
    
    # Pattern to match fenced code blocks
    FENCED_BLOCK_PATTERN = re.compile(r'```(\w*)\n([\s\S]*?)```')
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect shell prompts in code blocks.
        
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
        for block_match in self.FENCED_BLOCK_PATTERN.finditer(content):
            lang = block_match.group(1)
            block_content = block_match.group(2)
            
            # Check each prompt pattern
            for pattern, desc in self.PROMPT_PATTERNS:
                matches = pattern.findall(block_content)
                if matches:
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location=f"Code block ({lang or 'no lang'})",
                        description=f"Shell prompt detected: {desc}",
                        suggestion="Remove shell prompts for copyable code",
                        context=block_content[:80],
                        metadata={
                            'lang': lang,
                            'prompt_type': desc,
                            'match_count': len(matches)
                        }
                    )
                    issues.append(issue)
                    break  # One issue per block is enough
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Remove shell prompts from code blocks.
        
        Args:
            content: Markdown content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with cleaned content
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        result = content
        changes = []
        total_fixed = 0
        
        def process_block(match):
            nonlocal total_fixed
            lang = match.group(1)
            block_content = match.group(2)
            modified = False
            
            # Apply each prompt pattern
            for pattern, desc in self.PROMPT_PATTERNS:
                def remove_prompt(m):
                    nonlocal modified
                    modified = True
                    indent = m.group(1)
                    command = m.group(3)
                    return f"{indent}{command}"
                
                block_content, count = pattern.subn(remove_prompt, block_content)
                if count > 0:
                    total_fixed += count
            
            # Add 'console' language hint if prompts were removed and no lang specified
            if modified and not lang:
                lang = 'console'
            
            return f"```{lang}\n{block_content}```"
        
        result = self.FENCED_BLOCK_PATTERN.sub(process_block, result)
        
        if total_fixed > 0:
            changes.append(f"Removed {total_fixed} shell prompts from code blocks")
            self.increment_fixed(total_fixed)
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
