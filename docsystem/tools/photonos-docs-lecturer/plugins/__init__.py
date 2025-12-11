#!/usr/bin/env python3
"""
Photon OS Documentation Lecturer - Plugin System

This package provides a modular plugin architecture for detecting and fixing
documentation issues. All plugins MUST use the code block protection utilities
to ensure fenced code blocks (``` ... ```) are NEVER modified.

CRITICAL: Fenced code blocks contain command output, configuration examples,
and code snippets that must remain exactly as written.
"""

from .base import (
    BasePlugin,
    Issue,
    FixResult,
    PatternBasedPlugin,
    LLMAssistedPlugin,
    strip_code_blocks,
    protect_code_blocks,
    restore_code_blocks,
    CODE_BLOCK_PLACEHOLDER,
)

from .manager import PluginManager

__version__ = "2.0.0"
__all__ = [
    "BasePlugin",
    "Issue", 
    "FixResult",
    "PatternBasedPlugin",
    "LLMAssistedPlugin",
    "PluginManager",
    "strip_code_blocks",
    "protect_code_blocks",
    "restore_code_blocks",
    "CODE_BLOCK_PLACEHOLDER",
]
