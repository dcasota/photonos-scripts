#!/usr/bin/env python3
"""
Integration Module for Photon OS Documentation Lecturer

Provides integration between the legacy monolithic code and the new plugin system.
This module allows gradual migration to the plugin architecture while maintaining
backward compatibility.

Version: 1.0.0
"""

from __future__ import annotations

import logging
import threading
from typing import Any, Dict, List, Optional, Set, Tuple

from .base import BasePlugin, Issue, FixResult
from .manager import PluginManager, get_fix_types, get_feature_types

__version__ = "1.0.0"


class PluginIntegration:
    """Integration layer between legacy code and plugin system.
    
    This class provides methods to use the plugin system from the existing
    DocumentationLecturer class without requiring a complete rewrite.
    """
    
    def __init__(self, llm_client: Optional[Any] = None, config: Optional[Dict] = None):
        """Initialize the plugin integration.
        
        Args:
            llm_client: LLM client instance (LLMClient from main module)
            config: Configuration dictionary
        """
        self.config = config or {}
        self.manager = PluginManager(llm_client=llm_client, config=config)
        self.logger = logging.getLogger("plugin-integration")
        self._lock = threading.Lock()
    
    def detect_issues(self, content: str, url: str, 
                      enabled_fix_ids: Optional[Set[int]] = None,
                      enabled_feature_ids: Optional[Set[int]] = None,
                      **kwargs) -> Dict[str, List[Issue]]:
        """Run detection using plugins.
        
        Args:
            content: Content to analyze (markdown or HTML)
            url: URL of the page
            enabled_fix_ids: Set of enabled fix IDs (None = all)
            enabled_feature_ids: Set of enabled feature IDs (None = none)
            **kwargs: Additional context (soup, markdown_content, etc.)
            
        Returns:
            Dictionary mapping plugin names to detected issues
        """
        return self.manager.detect_all(
            content=content,
            url=url,
            enabled_fixes=enabled_fix_ids,
            enabled_features=enabled_feature_ids,
            **kwargs
        )
    
    def apply_fixes(self, content: str, issues_by_plugin: Dict[str, List[Issue]],
                    enabled_fix_ids: Optional[Set[int]] = None,
                    enabled_feature_ids: Optional[Set[int]] = None,
                    **kwargs) -> FixResult:
        """Apply fixes using plugins.
        
        Args:
            content: Content to fix
            issues_by_plugin: Issues grouped by plugin name
            enabled_fix_ids: Set of enabled fix IDs (None = all)
            enabled_feature_ids: Set of enabled feature IDs (None = none)
            **kwargs: Additional context
            
        Returns:
            Combined FixResult
        """
        return self.manager.fix_all(
            content=content,
            issues_by_plugin=issues_by_plugin,
            enabled_fixes=enabled_fix_ids,
            enabled_features=enabled_feature_ids,
            **kwargs
        )
    
    def get_plugin(self, name: str) -> Optional[BasePlugin]:
        """Get a specific plugin by name."""
        return self.manager.get_plugin(name)
    
    def get_stats(self) -> Dict[str, Dict[str, int]]:
        """Get statistics from all plugins."""
        return self.manager.get_stats()
    
    def cleanup(self):
        """Clean up plugin resources."""
        self.manager.cleanup()
    
    @staticmethod
    def get_fix_types_info() -> Dict[int, Dict]:
        """Get fix types information for --list-fixes."""
        return get_fix_types()
    
    @staticmethod
    def get_feature_types_info() -> Dict[int, Dict]:
        """Get feature types information for --list-features."""
        return get_feature_types()
    
    @staticmethod
    def parse_fix_spec(fix_spec: str) -> Set[int]:
        """Parse fix specification string.
        
        Args:
            fix_spec: Comma-separated list of fix IDs or ranges
            
        Returns:
            Set of fix IDs to apply
        """
        fix_types = get_fix_types()
        
        if not fix_spec or fix_spec.strip().lower() == 'all':
            return set(fix_types.keys())
        
        fix_ids = set()
        parts = fix_spec.replace(' ', '').split(',')
        
        for part in parts:
            if not part:
                continue
            
            if '-' in part:
                try:
                    start, end = part.split('-', 1)
                    start_id = int(start)
                    end_id = int(end)
                    
                    if start_id > end_id:
                        raise ValueError(f"Invalid range: {part}")
                    
                    for fix_id in range(start_id, end_id + 1):
                        if fix_id in fix_types:
                            fix_ids.add(fix_id)
                        else:
                            raise ValueError(f"Unknown fix ID: {fix_id}")
                except ValueError as e:
                    if "Unknown fix ID" in str(e) or "Invalid range" in str(e):
                        raise
                    raise ValueError(f"Invalid range format: {part}")
            else:
                try:
                    fix_id = int(part)
                    if fix_id in fix_types:
                        fix_ids.add(fix_id)
                    else:
                        raise ValueError(f"Unknown fix ID: {fix_id}")
                except ValueError as e:
                    if "Unknown fix ID" in str(e):
                        raise
                    raise ValueError(f"Invalid fix ID: {part}")
        
        return fix_ids
    
    @staticmethod
    def parse_feature_spec(feature_spec: str) -> Set[int]:
        """Parse feature specification string.
        
        Args:
            feature_spec: Comma-separated list of feature IDs or ranges
            
        Returns:
            Set of feature IDs to apply
        """
        feature_types = get_feature_types()
        
        if not feature_spec or feature_spec.strip().lower() == 'all':
            return set(feature_types.keys())
        
        feature_ids = set()
        parts = feature_spec.replace(' ', '').split(',')
        
        for part in parts:
            if not part:
                continue
            
            if '-' in part:
                try:
                    start, end = part.split('-', 1)
                    start_id = int(start)
                    end_id = int(end)
                    
                    if start_id > end_id:
                        raise ValueError(f"Invalid range: {part}")
                    
                    for feature_id in range(start_id, end_id + 1):
                        if feature_id in feature_types:
                            feature_ids.add(feature_id)
                        else:
                            raise ValueError(f"Unknown feature ID: {feature_id}")
                except ValueError as e:
                    if "Unknown feature ID" in str(e) or "Invalid range" in str(e):
                        raise
                    raise ValueError(f"Invalid range format: {part}")
            else:
                try:
                    feature_id = int(part)
                    if feature_id in feature_types:
                        feature_ids.add(feature_id)
                    else:
                        raise ValueError(f"Unknown feature ID: {feature_id}")
                except ValueError as e:
                    if "Unknown feature ID" in str(e):
                        raise
                    raise ValueError(f"Invalid feature ID: {part}")
        
        return feature_ids
    
    @staticmethod
    def get_fix_help_text() -> str:
        """Generate help text for --list-fixes."""
        lines = ["Available fixes:"]
        for fix_id, info in sorted(get_fix_types().items()):
            llm_marker = " [LLM]" if info.get('llm') else ""
            lines.append(f"  {fix_id:2d}. {info['name']:<22s} - {info['desc']}{llm_marker}")
        return '\n'.join(lines)
    
    @staticmethod
    def get_feature_help_text() -> str:
        """Generate help text for --list-features."""
        lines = ["Available features:"]
        for feature_id, info in sorted(get_feature_types().items()):
            llm_marker = " [LLM]" if info.get('llm') else ""
            lines.append(f"  {feature_id:2d}. {info['name']:<22s} - {info['desc']}{llm_marker}")
        return '\n'.join(lines)


def convert_legacy_issues_to_plugin_format(legacy_issues: Dict[str, List[Dict]], 
                                           url: str) -> Dict[str, List[Issue]]:
    """Convert legacy issue format to plugin Issue format.
    
    Args:
        legacy_issues: Dictionary of issue lists in legacy format
        url: Page URL
        
    Returns:
        Dictionary of Issue lists in plugin format
    """
    result = {}
    
    # Mapping from legacy keys to plugin names
    key_mapping = {
        'grammar_issues': 'grammar',
        'md_artifacts': 'markdown',
        'heading_hierarchy_issues': 'heading_hierarchy',
        'orphan_link_issues': 'orphan_link',
        'orphan_image_issues': 'orphan_image',
        'image_alignment_issues': 'image_alignment',
        'formatting_issues': 'formatting',
        'backtick_errors': 'backtick_errors',
        'indentation_issues': 'indentation',
        'shell_prompt_issues': 'shell_prompt',
        'mixed_cmd_output_issues': 'mixed_command_output',
        'deprecated_url_issues': 'deprecated_url',
        'vmware_spelling_issues': 'spelling',
        'broken_email_issues': 'broken_email',
        'html_comment_issues': 'html_comment',
        'malformed_code_block_issues': 'malformed_code_block',
        'numbered_list_issues': 'numbered_list',
        'header_spacing_issues': 'markdown',
    }
    
    for legacy_key, issues_list in legacy_issues.items():
        if not issues_list:
            continue
        
        plugin_name = key_mapping.get(legacy_key, legacy_key)
        
        if plugin_name not in result:
            result[plugin_name] = []
        
        for legacy_issue in issues_list:
            if isinstance(legacy_issue, dict):
                issue = Issue(
                    category=plugin_name,
                    location=legacy_issue.get('context', legacy_issue.get('location', url))[:100],
                    description=legacy_issue.get('message', legacy_issue.get('type', 'Issue detected')),
                    suggestion=legacy_issue.get('suggestion', 'Fix required'),
                    context=legacy_issue.get('context', ''),
                    metadata=legacy_issue
                )
            else:
                issue = Issue(
                    category=plugin_name,
                    location=str(legacy_issue)[:100],
                    description=str(legacy_issue),
                    suggestion='Fix required'
                )
            
            result[plugin_name].append(issue)
    
    return result


def convert_plugin_issues_to_legacy_format(plugin_issues: Dict[str, List[Issue]]) -> Dict[str, List[Dict]]:
    """Convert plugin Issue format to legacy format.
    
    Args:
        plugin_issues: Dictionary of Issue lists
        
    Returns:
        Dictionary of issue dictionaries in legacy format
    """
    result = {}
    
    # Reverse mapping
    name_to_key = {
        'grammar': 'grammar_issues',
        'markdown': 'md_artifacts',
        'heading_hierarchy': 'heading_hierarchy_issues',
        'orphan_link': 'orphan_link_issues',
        'orphan_image': 'orphan_image_issues',
        'image_alignment': 'image_alignment_issues',
        'formatting': 'formatting_issues',
        'backtick_errors': 'backtick_errors',
        'indentation': 'indentation_issues',
        'shell_prompt': 'shell_prompt_issues',
        'mixed_command_output': 'mixed_cmd_output_issues',
        'deprecated_url': 'deprecated_url_issues',
        'spelling': 'vmware_spelling_issues',
        'broken_email': 'broken_email_issues',
        'html_comment': 'html_comment_issues',
        'malformed_code_block': 'malformed_code_block_issues',
        'numbered_list': 'numbered_list_issues',
    }
    
    for plugin_name, issues in plugin_issues.items():
        legacy_key = name_to_key.get(plugin_name, f"{plugin_name}_issues")
        
        result[legacy_key] = []
        for issue in issues:
            legacy_dict = {
                'type': issue.category,
                'message': issue.description,
                'suggestion': issue.suggestion,
                'context': issue.context or issue.location,
                'location': issue.location,
            }
            legacy_dict.update(issue.metadata)
            result[legacy_key].append(legacy_dict)
    
    return result
