#!/usr/bin/env python3
"""
Mixed Command Output Plugin for Photon OS Documentation Lecturer

Detects and separates code blocks that mix commands with their output.
Requires LLM for intelligent separation.

Version: 1.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult, LLMAssistedPlugin

__version__ = "1.0.0"


class MixedCommandOutputPlugin(LLMAssistedPlugin):
    """Plugin for detecting and separating mixed command/output blocks.
    
    This is an optional feature that separates code blocks containing
    both commands and their output into two separate blocks.
    """
    
    PLUGIN_NAME = "mixed_command_output"
    PLUGIN_VERSION = "1.0.0"
    PLUGIN_DESCRIPTION = "Separate mixed command/output in code blocks"
    REQUIRES_LLM = True
    FIX_ID = None  # This is a feature, not a fix
    FEATURE_ID = 2
    
    # Pattern to match fenced code blocks
    FENCED_BLOCK_PATTERN = re.compile(r'```(\w*)\n([\s\S]*?)```')
    
    # Patterns that indicate command lines
    COMMAND_INDICATORS = [
        r'^\$\s+',           # $ prompt
        r'^#\s+(?!#)',       # # prompt (but not markdown headers)
        r'^>\s+',            # > prompt
        r'^root@',           # root@host#
        r'^\w+@\w+',         # user@host$
        r'^sudo\s+',         # sudo commands
        r'^tdnf\s+',         # tdnf commands
        r'^yum\s+',          # yum commands
        r'^rpm\s+',          # rpm commands
        r'^git\s+',          # git commands
        r'^cd\s+',           # cd commands
        r'^cat\s+',          # cat commands
        r'^ls\s+',           # ls commands
        r'^systemctl\s+',    # systemctl commands
    ]
    
    # LLM prompt for separation
    LLM_PROMPT_TEMPLATE = """You are a documentation reviewer. Separate the following code block into command and output sections.

The code block contains mixed commands and their output. Separate them into two blocks:
1. A "bash" or "console" block with just the commands
2. A text block with the output

CRITICAL RULES:
- Keep ALL original content
- Do NOT modify any text
- Only add the separation markers
- Commands should be in ```bash or ```console blocks
- Output should be in plain text or ```text blocks

Code block to separate:
{code_block}

Return the separated blocks. No explanations."""
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect code blocks with mixed commands and output.
        
        Args:
            content: Markdown content
            url: URL of the page
            **kwargs: Additional context
            
        Returns:
            List of mixed content issues
        """
        issues = []
        
        if not content:
            return issues
        
        # Find all fenced code blocks
        for block_match in self.FENCED_BLOCK_PATTERN.finditer(content):
            lang = block_match.group(1)
            block_content = block_match.group(2)
            
            if self._is_mixed_block(block_content):
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location=f"Code block ({lang or 'no lang'})",
                    description="Code block contains mixed commands and output",
                    suggestion="Separate into command and output blocks",
                    context=block_content[:100],
                    metadata={
                        'lang': lang,
                        'content': block_content,
                        'start': block_match.start(),
                        'end': block_match.end()
                    }
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def _is_mixed_block(self, block_content: str) -> bool:
        """Check if a code block contains mixed commands and output.
        
        Args:
            block_content: Content of the code block
            
        Returns:
            True if block appears to have mixed content
        """
        lines = block_content.strip().split('\n')
        if len(lines) < 2:
            return False
        
        command_lines = 0
        output_lines = 0
        
        for line in lines:
            line_stripped = line.strip()
            if not line_stripped:
                continue
            
            is_command = False
            for pattern in self.COMMAND_INDICATORS:
                if re.match(pattern, line_stripped):
                    is_command = True
                    break
            
            if is_command:
                command_lines += 1
            else:
                output_lines += 1
        
        # Consider it mixed if there's at least one command and some output
        return command_lines >= 1 and output_lines >= 2
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """Separate mixed command/output blocks using LLM.
        
        Args:
            content: Markdown content to fix
            issues: Issues to fix
            **kwargs: Additional context
            
        Returns:
            FixResult with separated content
        """
        if not issues:
            return FixResult(success=True, modified_content=content, changes_made=[])
        
        if not self.llm_client:
            return FixResult(
                success=False,
                error="LLM client required for mixed command/output separation"
            )
        
        result = content
        changes = []
        
        # Process each mixed block (in reverse to maintain positions)
        for issue in sorted(issues, key=lambda i: i.metadata.get('start', 0), reverse=True):
            block_content = issue.metadata.get('content', '')
            start = issue.metadata.get('start', 0)
            end = issue.metadata.get('end', 0)
            
            if not block_content or start == end:
                continue
            
            try:
                # Ask LLM to separate
                prompt = self.LLM_PROMPT_TEMPLATE.format(code_block=block_content)
                
                if hasattr(self.llm_client, '_generate'):
                    separated = self.llm_client._generate(prompt)
                else:
                    separated = None
                
                if separated and separated != block_content:
                    # Replace the original block
                    original_block = result[start:end]
                    result = result[:start] + separated + result[end:]
                    changes.append(f"Separated command/output block")
                    self.increment_fixed(1)
                    
            except Exception as e:
                self.logger.error(f"Failed to separate block: {e}")
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=changes
        )
