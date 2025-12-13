#!/usr/bin/env python3
"""
Shell Prompt Plugin for Photon OS Documentation Lecturer

Detects and removes shell prompts ($ # root@) in code blocks for
copy-paste friendliness.

Version: 2.1.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "2.1.0"


class ShellPromptPlugin(BasePlugin):
    """Plugin for detecting and removing shell prompts in code blocks."""
    
    PLUGIN_NAME = "shell_prompt"
    PLUGIN_VERSION = "2.1.0"
    PLUGIN_DESCRIPTION = "Remove shell prompts from code blocks"
    REQUIRES_LLM = False
    FIX_ID = 0  # This is a FEATURE, not a FIX
    
    # Shell prompt patterns for detection
    PROMPTS = [
        re.compile(r'^(\$|#)\s+', re.MULTILINE),  # $ or # at line start
        re.compile(r'^root@\S+[:#]\s*', re.MULTILINE),  # root@host:
        re.compile(r'^\[\S+@\S+\s+\S+\]\$\s*', re.MULTILINE),  # [user@host dir]$
        re.compile(r'^>\s+', re.MULTILINE),  # PowerShell-style >
    ]
    
    # Shell prompt patterns for removal (with capture groups)
    SHELL_PROMPT_PATTERNS = [
        re.compile(r'^(\s*)(\$\s+)(.+)$', re.MULTILINE),      # "$ command"
        re.compile(r'^(\s*)(>\s+)(.+)$', re.MULTILINE),       # "> command"
        re.compile(r'^(\s*)(%\s+)(.+)$', re.MULTILINE),       # "% command"
        re.compile(r'^(\s*)(~\s+)(.+)$', re.MULTILINE),       # "~ command"
        re.compile(r'^(\s*)(❯\s*)(.+)$', re.MULTILINE),       # "❯ command"
        re.compile(r'^(\s*)(➜\s+)(.+)$', re.MULTILINE),       # "➜  command"
        re.compile(r'^(\s*)(root@\S+[#$]\s*)(.+)$', re.MULTILINE),  # "root@host# command"
        re.compile(r'^(\s*)(\w+@\S+[#$%]\s*)(.+)$', re.MULTILINE),  # "user@host$ command"
    ]
    
    # Fenced code block pattern
    FENCED_BLOCK = re.compile(r'```[\w]*\n(.*?)```', re.DOTALL)
    
    # Python indicators for language detection
    PYTHON_INDICATORS = [
        r'^\s*import\s+\w+',
        r'^\s*from\s+\w+\s+import',
        r'^\s*def\s+\w+\s*\(',
        r'^\s*class\s+\w+',
        r'^\s*if\s+.*:$',
        r'^\s*for\s+\w+\s+in\s+',
        r'^\s*while\s+.*:$',
        r'^\s*print\s*\(',
        r'^\s*return\s+',
        r'^\s*#\s*!.*python',
        r'^\s*"""',
        r"^\s*'''",
        r'^\s*@\w+',
    ]
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect shell prompts inside code blocks."""
        issues = []
        
        if not content:
            return issues
        
        for block_match in self.FENCED_BLOCK.finditer(content):
            block_content = block_match.group(1)
            
            for prompt_pattern in self.PROMPTS:
                if prompt_pattern.search(block_content):
                    first_line = block_content.split('\n')[0][:50]
                    
                    issue = Issue(
                        category=self.PLUGIN_NAME,
                        location="Code block",
                        description="Shell prompt found in code block",
                        suggestion="Remove prompts for copy-paste friendliness",
                        context=first_line,
                        severity="low"
                    )
                    issues.append(issue)
                    break
        
        self.increment_detected(len(issues))
        return issues
    
    def _looks_like_python(self, code: str) -> bool:
        """Heuristic to detect if code content looks like Python."""
        for pattern in self.PYTHON_INDICATORS:
            if re.search(pattern, code, re.MULTILINE):
                return True
        return False
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Remove shell prompt prefixes from code blocks.
        
        Also adds language hints to code blocks without them:
        - Adds 'python' if content looks like Python code
        - Adds 'console' otherwise for shell commands
        """
        if not content:
            return FixResult(success=False, error="No content to fix")
        
        changes = []
        
        def fix_code_block(match):
            code_block = match.group(0)
            lines = code_block.split('\n')
            
            if not lines:
                return code_block
            
            opening_line = lines[0]
            has_language = len(opening_line) > 3
            
            fixed_lines = []
            code_content_lines = []
            prompts_removed = 0
            
            for line in lines[1:-1]:
                fixed_line = line
                for pattern in self.SHELL_PROMPT_PATTERNS:
                    prompt_match = pattern.match(line)
                    if prompt_match:
                        leading_ws = prompt_match.group(1)
                        command = prompt_match.group(3)
                        fixed_line = leading_ws + command
                        prompts_removed += 1
                        break
                code_content_lines.append(fixed_line)
            
            if not has_language and code_content_lines:
                code_text = '\n'.join(code_content_lines)
                if self._looks_like_python(code_text):
                    opening_line = '```python'
                else:
                    opening_line = '```console'
            
            fixed_lines.append(opening_line)
            fixed_lines.extend(code_content_lines)
            if lines:
                fixed_lines.append(lines[-1])
            
            if prompts_removed > 0:
                changes.append(f"Removed {prompts_removed} shell prompts")
            
            return '\n'.join(fixed_lines)
        
        result = re.sub(r'```[\w]*\n[\s\S]*?```', fix_code_block, content)
        
        self.increment_fixed(len(changes))
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
