#!/usr/bin/env python3
"""
Integration Module for Photon OS Documentation Lecturer Plugins

Provides utilities for integrating plugins with the main script.

Version: 2.0.0
"""

from __future__ import annotations

from typing import Any, Dict, List, Optional, Type

from .base import BasePlugin, Issue, FixResult
from .manager import PluginManager
from .deprecated_url import DeprecatedUrlPlugin
from .spelling import SpellingPlugin
from .grammar import GrammarPlugin
from .markdown import MarkdownPlugin
from .indentation import IndentationPlugin
from .heading_hierarchy import HeadingHierarchyPlugin
from .orphan_link import OrphanLinkPlugin
from .orphan_image import OrphanImagePlugin
from .orphan_page import OrphanPagePlugin
from .image_alignment import ImageAlignmentPlugin
from .shell_prompt import ShellPromptPlugin
from .mixed_command_output import MixedCommandOutputPlugin

__version__ = "2.0.0"


# All available plugins
ALL_PLUGINS: List[Type[BasePlugin]] = [
    DeprecatedUrlPlugin,
    SpellingPlugin,
    GrammarPlugin,
    MarkdownPlugin,
    IndentationPlugin,
    HeadingHierarchyPlugin,
    OrphanLinkPlugin,
    OrphanImagePlugin,
    OrphanPagePlugin,
    ImageAlignmentPlugin,
    ShellPromptPlugin,
    MixedCommandOutputPlugin,
]

# Plugins with automatic fixes (FIX_ID > 0)
FIX_PLUGINS: List[Type[BasePlugin]] = [
    p for p in ALL_PLUGINS if p.FIX_ID > 0
]

# Plugin name to class mapping
PLUGIN_MAP: Dict[str, Type[BasePlugin]] = {
    p.PLUGIN_NAME: p for p in ALL_PLUGINS
}

# Fix ID to plugin mapping
FIX_ID_MAP: Dict[int, Type[BasePlugin]] = {
    p.FIX_ID: p for p in ALL_PLUGINS if p.FIX_ID > 0
}


def create_plugin_manager(
    config: Optional[Dict[str, Any]] = None,
    llm_client: Any = None,
    enabled_plugins: Optional[List[str]] = None
) -> PluginManager:
    """Create and configure a plugin manager.
    
    Args:
        config: Optional configuration dict
        llm_client: Optional LLM client for LLM-assisted plugins
        enabled_plugins: List of plugin names to enable (None = all)
        
    Returns:
        Configured PluginManager
    """
    manager = PluginManager(config)
    
    if llm_client:
        manager.set_llm_client(llm_client)
    
    for plugin_class in ALL_PLUGINS:
        if enabled_plugins is None or plugin_class.PLUGIN_NAME in enabled_plugins:
            manager.register(plugin_class)
    
    return manager


def get_fix_descriptions() -> Dict[int, str]:
    """Get descriptions for all fix types.
    
    Returns:
        Dict mapping fix ID to description
    """
    descriptions = {}
    for plugin in ALL_PLUGINS:
        if plugin.FIX_ID > 0:
            descriptions[plugin.FIX_ID] = plugin.PLUGIN_DESCRIPTION
    return descriptions


def parse_fix_range(fix_spec: str) -> List[int]:
    """Parse a fix specification like '1-5' or '1,3,5' into a list of IDs.
    
    Args:
        fix_spec: Fix specification string
        
    Returns:
        List of fix IDs
    """
    fix_ids = []
    
    for part in fix_spec.split(','):
        part = part.strip()
        if '-' in part:
            start, end = part.split('-', 1)
            try:
                fix_ids.extend(range(int(start), int(end) + 1))
            except ValueError:
                pass
        else:
            try:
                fix_ids.append(int(part))
            except ValueError:
                pass
    
    # Filter to valid fix IDs
    valid_ids = set(FIX_ID_MAP.keys())
    return [i for i in fix_ids if i in valid_ids]


def get_plugins_for_fixes(fix_ids: List[int]) -> List[str]:
    """Get plugin names for the given fix IDs.
    
    Args:
        fix_ids: List of fix IDs
        
    Returns:
        List of plugin names
    """
    plugin_names = []
    for fix_id in fix_ids:
        if fix_id in FIX_ID_MAP:
            plugin_names.append(FIX_ID_MAP[fix_id].PLUGIN_NAME)
    return plugin_names
