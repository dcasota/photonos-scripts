#!/usr/bin/env python3
"""
Plugin Manager for Photon OS Documentation Lecturer

Handles plugin discovery, loading, and execution coordination.

Version: 2.0.0
"""

from __future__ import annotations

import logging
from typing import Any, Dict, List, Optional, Type

from .base import BasePlugin, Issue, FixResult

__version__ = "2.0.0"


class PluginManager:
    """Manages plugin lifecycle and execution."""
    
    def __init__(self, config: Optional[Dict[str, Any]] = None):
        """Initialize the plugin manager."""
        self.config = config or {}
        self.plugins: Dict[str, BasePlugin] = {}
        self.logger = logging.getLogger("plugin.manager")
        self._llm_client = None
    
    def set_llm_client(self, client: Any):
        """Set LLM client for plugins that need it."""
        self._llm_client = client
        for plugin in self.plugins.values():
            if hasattr(plugin, 'set_llm_client'):
                plugin.set_llm_client(client)
    
    def register(self, plugin_class: Type[BasePlugin], config: Optional[Dict] = None):
        """Register a plugin class."""
        plugin_config = config or self.config.get(plugin_class.PLUGIN_NAME, {})
        plugin = plugin_class(plugin_config)
        
        if plugin.REQUIRES_LLM and self._llm_client:
            plugin.set_llm_client(self._llm_client)
        
        self.plugins[plugin.PLUGIN_NAME] = plugin
        self.logger.info(f"Registered plugin: {plugin.PLUGIN_NAME} v{plugin.PLUGIN_VERSION}")
    
    def get_plugin(self, name: str) -> Optional[BasePlugin]:
        """Get a plugin by name."""
        return self.plugins.get(name)
    
    def detect_all(self, content: str, url: str, **kwargs) -> Dict[str, List[Issue]]:
        """Run detection on all registered plugins.
        
        Args:
            content: The markdown content
            url: URL or path of the document
            **kwargs: Additional context
            
        Returns:
            Dict mapping plugin name to list of issues
        """
        all_issues = {}
        
        for name, plugin in self.plugins.items():
            try:
                issues = plugin.detect(content, url, **kwargs)
                if issues:
                    all_issues[name] = issues
                    self.logger.debug(f"Plugin {name} detected {len(issues)} issues")
            except Exception as e:
                self.logger.error(f"Plugin {name} detection failed: {e}")
        
        return all_issues
    
    def fix_all(
        self,
        content: str,
        issues: Dict[str, List[Issue]],
        enabled_fixes: Optional[List[str]] = None,
        **kwargs
    ) -> FixResult:
        """Apply fixes from all plugins.
        
        Args:
            content: The markdown content
            issues: Dict of issues by plugin name
            enabled_fixes: List of plugin names to apply fixes for (None = all)
            **kwargs: Additional context
            
        Returns:
            Combined FixResult
        """
        result_content = content
        all_changes = []
        
        for name, plugin in self.plugins.items():
            if enabled_fixes and name not in enabled_fixes:
                continue
            
            plugin_issues = issues.get(name, [])
            if not plugin_issues:
                continue
            
            try:
                result = plugin.fix(result_content, plugin_issues, **kwargs)
                if result.success and result.modified_content:
                    result_content = result.modified_content
                    all_changes.extend(result.changes_made)
                    self.logger.debug(f"Plugin {name} applied fixes")
            except Exception as e:
                self.logger.error(f"Plugin {name} fix failed: {e}")
        
        return FixResult(
            success=True,
            modified_content=result_content,
            changes_made=all_changes
        )
    
    def get_stats(self) -> Dict[str, Dict[str, int]]:
        """Get statistics from all plugins."""
        stats = {}
        for name, plugin in self.plugins.items():
            stats[name] = plugin.get_stats()
        return stats
    
    def reset_stats(self):
        """Reset statistics for all plugins."""
        for plugin in self.plugins.values():
            plugin.reset_stats()
    
    def list_plugins(self) -> List[Dict[str, Any]]:
        """List all registered plugins."""
        return [
            {
                "name": p.PLUGIN_NAME,
                "version": p.PLUGIN_VERSION,
                "description": p.PLUGIN_DESCRIPTION,
                "requires_llm": p.REQUIRES_LLM,
                "fix_id": p.FIX_ID
            }
            for p in self.plugins.values()
        ]
