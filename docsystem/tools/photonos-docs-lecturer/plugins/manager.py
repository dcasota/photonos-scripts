#!/usr/bin/env python3
"""
Plugin Manager for Photon OS Documentation Lecturer

Handles plugin discovery, loading, and coordination.
Provides thread-safe access to plugins and manages execution order.

Version: 1.0.0
"""

from __future__ import annotations

import threading
from typing import Any, Dict, List, Optional, Set, Type

from .base import BasePlugin, Issue, FixResult

__version__ = "1.0.0"


class PluginManager:
    """Manages plugin lifecycle and coordination.
    
    Provides:
    - Plugin registration and discovery
    - Thread-safe plugin access
    - Fix ID to plugin mapping
    - Feature ID to plugin mapping
    """
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the plugin manager.
        
        Args:
            llm_client: LLM client for plugins that need it
            config: Global configuration for plugins
        """
        self.llm_client = llm_client
        self.config = config or {}
        self._plugins: Dict[str, BasePlugin] = {}
        self._fix_id_map: Dict[int, str] = {}
        self._feature_id_map: Dict[int, str] = {}
        self._lock = threading.Lock()
        
        # Auto-register built-in plugins
        self._register_builtin_plugins()
    
    def _register_builtin_plugins(self):
        """Register all built-in plugins."""
        from .grammar import GrammarPlugin
        from .markdown import MarkdownPlugin, MalformedCodeBlockPlugin
        from .heading_hierarchy import HeadingHierarchyPlugin
        from .orphan_page import OrphanPagePlugin
        from .orphan_link import OrphanLinkPlugin
        from .orphan_image import OrphanImagePlugin
        from .image_alignment import ImageAlignmentPlugin
        from .formatting import FormattingPlugin
        from .backtick_errors import BacktickErrorsPlugin
        from .indentation import IndentationPlugin
        from .deprecated_url import DeprecatedUrlPlugin
        from .spelling import SpellingPlugin, BrokenEmailPlugin, HtmlCommentPlugin
        from .shell_prompt import ShellPromptPlugin
        from .mixed_command_output import MixedCommandOutputPlugin
        
        # Register fix plugins (ordered by FIX_ID)
        fix_plugins = [
            BrokenEmailPlugin,       # FIX_ID 1
            SpellingPlugin,          # FIX_ID 2 (VMware)
            DeprecatedUrlPlugin,     # FIX_ID 3
            FormattingPlugin,        # FIX_ID 4
            BacktickErrorsPlugin,    # FIX_ID 5
            HeadingHierarchyPlugin,  # FIX_ID 6
            # FIX_ID 7 is header-spacing (handled in MarkdownPlugin)
            HtmlCommentPlugin,       # FIX_ID 8
            GrammarPlugin,           # FIX_ID 9
            MarkdownPlugin,          # FIX_ID 10
            IndentationPlugin,       # FIX_ID 11
            MalformedCodeBlockPlugin, # FIX_ID 12
            # FIX_ID 13 is numbered-lists (to be added)
        ]
        
        for plugin_class in fix_plugins:
            self.register_plugin(plugin_class)
        
        # Register feature plugins
        feature_plugins = [
            ShellPromptPlugin,        # FEATURE_ID 1
            MixedCommandOutputPlugin, # FEATURE_ID 2
        ]
        
        for plugin_class in feature_plugins:
            self.register_plugin(plugin_class)
        
        # Register detection-only plugins (no auto-fix)
        detection_plugins = [
            OrphanPagePlugin,
            OrphanLinkPlugin,
            OrphanImagePlugin,
            ImageAlignmentPlugin,
        ]
        
        for plugin_class in detection_plugins:
            self.register_plugin(plugin_class)
    
    def register_plugin(self, plugin_class: Type[BasePlugin]):
        """Register a plugin class.
        
        Args:
            plugin_class: The plugin class to register
        """
        with self._lock:
            # Create plugin instance
            plugin_config = self.config.copy()
            plugin = plugin_class(llm_client=self.llm_client, config=plugin_config)
            
            # Register by name
            self._plugins[plugin.PLUGIN_NAME] = plugin
            
            # Map fix ID if available
            if hasattr(plugin, 'FIX_ID') and plugin.FIX_ID is not None:
                self._fix_id_map[plugin.FIX_ID] = plugin.PLUGIN_NAME
            
            # Map feature ID if available
            if hasattr(plugin, 'FEATURE_ID') and plugin.FEATURE_ID is not None:
                self._feature_id_map[plugin.FEATURE_ID] = plugin.PLUGIN_NAME
    
    def get_plugin(self, name: str) -> Optional[BasePlugin]:
        """Get a plugin by name.
        
        Args:
            name: Plugin name
            
        Returns:
            Plugin instance or None
        """
        with self._lock:
            return self._plugins.get(name)
    
    def get_plugin_by_fix_id(self, fix_id: int) -> Optional[BasePlugin]:
        """Get a plugin by its fix ID.
        
        Args:
            fix_id: The fix ID
            
        Returns:
            Plugin instance or None
        """
        with self._lock:
            name = self._fix_id_map.get(fix_id)
            return self._plugins.get(name) if name else None
    
    def get_plugin_by_feature_id(self, feature_id: int) -> Optional[BasePlugin]:
        """Get a plugin by its feature ID.
        
        Args:
            feature_id: The feature ID
            
        Returns:
            Plugin instance or None
        """
        with self._lock:
            name = self._feature_id_map.get(feature_id)
            return self._plugins.get(name) if name else None
    
    def get_all_plugins(self) -> List[BasePlugin]:
        """Get all registered plugins.
        
        Returns:
            List of all plugins
        """
        with self._lock:
            return list(self._plugins.values())
    
    def get_fix_plugins(self) -> List[BasePlugin]:
        """Get all plugins that have fix IDs.
        
        Returns:
            List of fix plugins ordered by ID
        """
        with self._lock:
            plugins = []
            for fix_id in sorted(self._fix_id_map.keys()):
                name = self._fix_id_map[fix_id]
                if name in self._plugins:
                    plugins.append(self._plugins[name])
            return plugins
    
    def get_feature_plugins(self) -> List[BasePlugin]:
        """Get all plugins that have feature IDs.
        
        Returns:
            List of feature plugins ordered by ID
        """
        with self._lock:
            plugins = []
            for feature_id in sorted(self._feature_id_map.keys()):
                name = self._feature_id_map[feature_id]
                if name in self._plugins:
                    plugins.append(self._plugins[name])
            return plugins
    
    def detect_all(self, content: str, url: str, enabled_fixes: Optional[Set[int]] = None,
                   enabled_features: Optional[Set[int]] = None, **kwargs) -> Dict[str, List[Issue]]:
        """Run detection on all enabled plugins.
        
        Args:
            content: Content to analyze
            url: URL of the page
            enabled_fixes: Set of enabled fix IDs (None = all)
            enabled_features: Set of enabled feature IDs (None = none)
            **kwargs: Additional context
            
        Returns:
            Dictionary mapping plugin names to their detected issues
        """
        all_issues = {}
        
        with self._lock:
            plugins_to_run = []
            
            # Add enabled fix plugins
            for fix_id, name in self._fix_id_map.items():
                if enabled_fixes is None or fix_id in enabled_fixes:
                    if name in self._plugins:
                        plugins_to_run.append(self._plugins[name])
            
            # Add enabled feature plugins
            if enabled_features:
                for feature_id, name in self._feature_id_map.items():
                    if feature_id in enabled_features:
                        if name in self._plugins:
                            plugins_to_run.append(self._plugins[name])
            
            # Add detection-only plugins
            for name, plugin in self._plugins.items():
                if (not hasattr(plugin, 'FIX_ID') or plugin.FIX_ID is None) and \
                   (not hasattr(plugin, 'FEATURE_ID') or plugin.FEATURE_ID is None):
                    plugins_to_run.append(plugin)
        
        # Run detection (can be parallelized if needed)
        for plugin in plugins_to_run:
            try:
                issues = plugin.detect(content, url, **kwargs)
                if issues:
                    all_issues[plugin.PLUGIN_NAME] = issues
            except Exception as e:
                plugin.log_error(f"Detection failed for {url}: {e}")
        
        return all_issues
    
    def fix_all(self, content: str, issues_by_plugin: Dict[str, List[Issue]],
                enabled_fixes: Optional[Set[int]] = None,
                enabled_features: Optional[Set[int]] = None, **kwargs) -> FixResult:
        """Apply fixes from all enabled plugins.
        
        Args:
            content: Content to fix
            issues_by_plugin: Issues grouped by plugin name
            enabled_fixes: Set of enabled fix IDs (None = all)
            enabled_features: Set of enabled feature IDs (None = none)
            **kwargs: Additional context
            
        Returns:
            Combined FixResult
        """
        result = content
        all_changes = []
        
        # Determine which plugins to run
        plugins_to_run = []
        
        with self._lock:
            # Add enabled fix plugins in order
            for fix_id in sorted(self._fix_id_map.keys()):
                if enabled_fixes is None or fix_id in enabled_fixes:
                    name = self._fix_id_map[fix_id]
                    if name in self._plugins and name in issues_by_plugin:
                        plugins_to_run.append((self._plugins[name], issues_by_plugin[name]))
            
            # Add enabled feature plugins
            if enabled_features:
                for feature_id in sorted(self._feature_id_map.keys()):
                    if feature_id in enabled_features:
                        name = self._feature_id_map[feature_id]
                        if name in self._plugins and name in issues_by_plugin:
                            plugins_to_run.append((self._plugins[name], issues_by_plugin[name]))
        
        # Apply fixes in order
        for plugin, issues in plugins_to_run:
            if not issues:
                continue
            
            try:
                fix_result = plugin.fix(result, issues, **kwargs)
                if fix_result.success and fix_result.modified_content:
                    result = fix_result.modified_content
                    all_changes.extend(fix_result.changes_made)
            except Exception as e:
                plugin.log_error(f"Fix failed: {e}")
        
        return FixResult(
            success=True,
            modified_content=result,
            changes_made=all_changes
        )
    
    def get_stats(self) -> Dict[str, Dict[str, int]]:
        """Get statistics from all plugins.
        
        Returns:
            Dictionary mapping plugin names to their stats
        """
        stats = {}
        with self._lock:
            for name, plugin in self._plugins.items():
                stats[name] = plugin.get_stats()
        return stats
    
    def reset_stats(self):
        """Reset statistics for all plugins."""
        with self._lock:
            for plugin in self._plugins.values():
                plugin.reset_stats()
    
    def cleanup(self):
        """Clean up all plugin resources."""
        with self._lock:
            for plugin in self._plugins.values():
                if hasattr(plugin, 'cleanup'):
                    try:
                        plugin.cleanup()
                    except Exception:
                        pass


# Convenience function for getting fix types info
def get_fix_types() -> Dict[int, Dict]:
    """Get information about all fix types.
    
    Returns:
        Dictionary mapping fix IDs to their info
    """
    return {
        1: {'key': 'broken_email', 'name': 'broken-emails', 'desc': 'Fix broken email addresses', 'llm': False},
        2: {'key': 'spelling', 'name': 'vmware-spelling', 'desc': 'Fix VMware spelling', 'llm': False},
        3: {'key': 'deprecated_url', 'name': 'deprecated-urls', 'desc': 'Fix deprecated URLs', 'llm': False},
        4: {'key': 'formatting', 'name': 'backtick-spacing', 'desc': 'Fix missing spaces around backticks', 'llm': False},
        5: {'key': 'backtick_errors', 'name': 'backtick-errors', 'desc': 'Fix spaces inside backticks', 'llm': False},
        6: {'key': 'heading_hierarchy', 'name': 'heading-hierarchy', 'desc': 'Fix heading hierarchy violations', 'llm': False},
        7: {'key': 'header_spacing', 'name': 'header-spacing', 'desc': 'Fix markdown headers missing space', 'llm': False},
        8: {'key': 'html_comment', 'name': 'html-comments', 'desc': 'Fix HTML comments', 'llm': False},
        9: {'key': 'grammar', 'name': 'grammar', 'desc': 'Fix grammar and spelling issues', 'llm': True},
        10: {'key': 'markdown', 'name': 'markdown-artifacts', 'desc': 'Fix markdown artifacts', 'llm': True},
        11: {'key': 'indentation', 'name': 'indentation', 'desc': 'Fix indentation issues', 'llm': True},
        12: {'key': 'malformed_code_block', 'name': 'malformed-codeblocks', 'desc': 'Fix malformed code blocks', 'llm': False},
        13: {'key': 'numbered_list', 'name': 'numbered-lists', 'desc': 'Fix numbered list sequence errors', 'llm': False},
    }


def get_feature_types() -> Dict[int, Dict]:
    """Get information about all feature types.
    
    Returns:
        Dictionary mapping feature IDs to their info
    """
    return {
        1: {'key': 'shell_prompt', 'name': 'shell-prompts', 'desc': 'Remove shell prompts in code blocks', 'llm': False},
        2: {'key': 'mixed_command_output', 'name': 'mixed-cmd-output', 'desc': 'Separate mixed command/output', 'llm': True},
    }
