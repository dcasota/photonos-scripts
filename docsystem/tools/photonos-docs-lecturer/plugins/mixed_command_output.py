#!/usr/bin/env python3
"""
Mixed Command Output Plugin for Photon OS Documentation Lecturer

Detects code blocks that mix commands with their output, which can
make copy-paste difficult.

CRITICAL: This plugin only detects issues - it does NOT modify code blocks.

Version: 2.0.0
"""

from __future__ import annotations

import re
from typing import Any, Dict, List, Optional

from .base import BasePlugin, Issue, FixResult

__version__ = "2.0.0"


class MixedCommandOutputPlugin(BasePlugin):
    """Plugin for detecting mixed command/output in code blocks.
    
    Detection only - separation requires human judgment.
    """
    
    PLUGIN_NAME = "mixed_command_output"
    PLUGIN_VERSION = "2.0.0"
    PLUGIN_DESCRIPTION = "Detect commands mixed with output in code blocks"
    REQUIRES_LLM = False
    FIX_ID = 0  # No automatic fix
    
    # Fenced code block pattern
    FENCED_BLOCK = re.compile(r'```([\w]*)\n(.*?)```', re.DOTALL)
    
    # Patterns that suggest command output
    OUTPUT_INDICATORS = [
        re.compile(r'^\s+\S'),  # Indented content (likely output)
        re.compile(r'^(total|drwx|lrwx|-rw)', re.MULTILINE),  # ls output
        re.compile(r'^\d+\.\d+\.\d+'),  # Version numbers as output
        re.compile(r'^[\s]*[A-Z][a-z]+:'),  # Label: value format
    ]
    
    # Patterns that suggest commands
    COMMAND_INDICATORS = [
        re.compile(r'^(sudo|apt|yum|tdnf|dnf|rpm|systemctl|docker|kubectl)\s'),
        re.compile(r'^\$\s+'),
        re.compile(r'^#\s+(?!#)'),  # # but not ## (which is comment)
    ]
    
    def detect(self, content: str, url: str, **kwargs) -> List[Issue]:
        """Detect mixed command/output in code blocks.
        
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
        
        for block_match in self.FENCED_BLOCK.finditer(content):
            lang = block_match.group(1) or ''
            block_content = block_match.group(2)
            
            # Skip if explicitly marked as output
            if lang.lower() in ['output', 'console', 'text', 'log']:
                continue
            
            lines = block_content.strip().split('\n')
            if len(lines) < 2:
                continue
            
            has_commands = False
            has_output = False
            
            for line in lines:
                # Check for command patterns
                for pattern in self.COMMAND_INDICATORS:
                    if pattern.search(line):
                        has_commands = True
                        break
                
                # Check for output patterns
                for pattern in self.OUTPUT_INDICATORS:
                    if pattern.search(line):
                        has_output = True
                        break
            
            if has_commands and has_output:
                first_line = lines[0][:50] if lines else ''
                issue = Issue(
                    category=self.PLUGIN_NAME,
                    location="Code block",
                    description="Code block mixes commands with output",
                    suggestion="Consider separating commands from output into different blocks",
                    context=first_line,
                    severity="low"
                )
                issues.append(issue)
        
        self.increment_detected(len(issues))
        return issues
    
    def fix(self, content: str, issues: List[Issue], **kwargs) -> FixResult:
        """No automatic fix for mixed command/output.
        
        Separating commands from output requires human judgment
        about what is a command vs what is output.
        """
        return FixResult(
            success=True,
            modified_content=content,
            changes_made=["Mixed command/output requires manual separation"]
        )
