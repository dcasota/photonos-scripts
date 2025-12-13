#!/usr/bin/env python3
"""
Apply Fixes Module for Photon OS Documentation Lecturer

Provides functionality to apply fixes to local markdown files based on detected issues.

Version: 1.0.0
"""

from __future__ import annotations

import os
import re
import urllib.parse
from typing import Any, Dict, List, Optional, Set, TYPE_CHECKING

from .base import Issue

if TYPE_CHECKING:
    from ..photonos_docs_lecturer import DocumentationLecturer

__version__ = "1.0.0"


class FixApplicator:
    """Applies fixes to local markdown files based on detected issues.
    
    This class encapsulates the fix application logic, working with a
    DocumentationLecturer instance to access configuration and plugins.
    """
    
    def __init__(self, lecturer: 'DocumentationLecturer'):
        """Initialize the fix applicator.
        
        Args:
            lecturer: The DocumentationLecturer instance providing context
        """
        self.lecturer = lecturer
    
    @property
    def local_webserver(self) -> Optional[str]:
        return self.lecturer.local_webserver
    
    @property
    def logger(self):
        return self.lecturer.logger
    
    @property
    def language(self) -> str:
        return self.lecturer.language
    
    def find_directory_case_insensitive(self, parent_dir: str, target_name: str) -> Optional[str]:
        """Find a directory or file matching target_name case-insensitively.
        
        Hugo normalizes URLs to lowercase, but the actual filesystem may have
        mixed-case directory names (e.g., 'command-line-Interfaces' vs 'command-line-interfaces').
        
        Args:
            parent_dir: The parent directory to search in
            target_name: The name to find (from URL, typically lowercase)
            
        Returns:
            The actual path if found, None otherwise
        """
        if not os.path.isdir(parent_dir):
            return None
        
        target_lower = target_name.lower()
        
        try:
            for entry in os.listdir(parent_dir):
                if entry.lower() == target_lower:
                    return os.path.join(parent_dir, entry)
        except OSError:
            pass
        
        return None
    
    def calculate_content_similarity(self, text1: str, text2: str) -> float:
        """Calculate similarity between two text strings using word overlap.
        
        Uses Jaccard similarity on word sets for a fast, reasonable approximation.
        
        Args:
            text1: First text string
            text2: Second text string
            
        Returns:
            Similarity score between 0.0 and 1.0
        """
        def extract_words(text: str) -> Set[str]:
            text = re.sub(r'[#*`\[\](){}|<>]', ' ', text.lower())
            words = set(re.findall(r'\b[a-z0-9]{3,}\b', text))
            return words
        
        words1 = extract_words(text1)
        words2 = extract_words(text2)
        
        if not words1 or not words2:
            return 0.0
        
        intersection = words1 & words2
        union = words1 | words2
        
        return len(intersection) / len(union) if union else 0.0
    
    def find_matching_file_by_content(self, parent_dir: str, webpage_text: str, 
                                      min_similarity: float = 0.3) -> Optional[str]:
        """Find a markdown file in parent_dir that best matches the webpage content.
        
        This is a fallback when path-based matching fails. It compares the webpage
        content with each markdown file in the directory and returns the best match.
        
        Args:
            parent_dir: Directory to search for markdown files
            webpage_text: Text content extracted from the webpage
            min_similarity: Minimum similarity threshold (0.0 to 1.0)
            
        Returns:
            Path to the best matching file, or None if no match above threshold
        """
        if not os.path.isdir(parent_dir) or not webpage_text:
            return None
        
        best_match = None
        best_score = min_similarity
        
        try:
            for entry in os.listdir(parent_dir):
                if not entry.endswith('.md') or entry.startswith('_'):
                    continue
                
                file_path = os.path.join(parent_dir, entry)
                if not os.path.isfile(file_path):
                    continue
                
                try:
                    with open(file_path, 'r', encoding='utf-8') as f:
                        file_content = f.read()
                    
                    score = self.calculate_content_similarity(webpage_text, file_content)
                    
                    if score > best_score:
                        best_score = score
                        best_match = file_path
                        self.logger.debug(f"Content match candidate: {entry} (score: {score:.3f})")
                        
                except Exception as e:
                    self.logger.debug(f"Could not read {file_path}: {e}")
                    continue
            
            if best_match:
                self.logger.debug(f"Best content match: {best_match} (score: {best_score:.3f})")
            
        except OSError as e:
            self.logger.debug(f"Could not list directory {parent_dir}: {e}")
        
        return best_match
    
    def map_url_to_local_path(self, page_url: str, webpage_text: str = None) -> Optional[str]:
        """Map a page URL to local markdown file path.
        
        Hugo content structure typically uses:
        - _index.md for section/directory pages (e.g., /docs-v5/ -> content/en/docs-v5/_index.md)
        - {name}.md or {name}/_index.md for leaf pages
        
        This function performs case-insensitive matching because Hugo normalizes
        URLs to lowercase while the filesystem may have mixed-case names.
        
        When path-based matching fails, it falls back to content-based matching
        by comparing the webpage content with markdown files in the parent directory.
        
        Args:
            page_url: The URL of the page (e.g., https://127.0.0.1/docs-v5/admin-guide/)
            webpage_text: Optional text content from the webpage for content-based matching
            
        Returns:
            Absolute path to the markdown file, or None if not found.
        """
        if not self.local_webserver:
            return None
        
        try:
            parsed = urllib.parse.urlparse(page_url)
            path = parsed.path.strip('/')
            path = path.rstrip('/')
            
            content_bases = [
                os.path.join(self.local_webserver, 'content', self.language),
                os.path.join(self.local_webserver, 'content'),
                self.local_webserver,
            ]
            
            if not path:
                for content_base in content_bases:
                    if not os.path.isdir(content_base):
                        continue
                    for md_file in ['_index.md', 'index.md']:
                        candidate = os.path.join(content_base, md_file)
                        if os.path.isfile(candidate):
                            return candidate
                return None
            
            path_parts = path.split('/')
            deepest_resolved_dir = None
            
            for content_base in content_bases:
                if not os.path.isdir(content_base):
                    continue
                
                current_dir = content_base
                resolved_parts = []
                all_parts_resolved = True
                
                for i, part in enumerate(path_parts):
                    is_last_part = (i == len(path_parts) - 1)
                    
                    exact_path = os.path.join(current_dir, part)
                    if os.path.isdir(exact_path):
                        current_dir = exact_path
                        resolved_parts.append(part)
                        continue
                    
                    if is_last_part and os.path.isfile(exact_path + '.md'):
                        return exact_path + '.md'
                    
                    found_dir = self.find_directory_case_insensitive(current_dir, part)
                    if found_dir and os.path.isdir(found_dir):
                        current_dir = found_dir
                        resolved_parts.append(os.path.basename(found_dir))
                        continue
                    
                    if is_last_part:
                        found_file = self.find_directory_case_insensitive(current_dir, part + '.md')
                        if found_file and os.path.isfile(found_file):
                            return found_file
                    
                    if current_dir != content_base:
                        deepest_resolved_dir = current_dir
                    
                    all_parts_resolved = False
                    break
                
                if all_parts_resolved and os.path.isdir(current_dir):
                    for md_file in ['_index.md', 'index.md', 'README.md']:
                        candidate = os.path.join(current_dir, md_file)
                        if os.path.isfile(candidate):
                            self.logger.debug(f"Mapped {page_url} -> {candidate}")
                            return candidate
                    
                    deepest_resolved_dir = current_dir
                    self.logger.debug(f"Directory exists but no _index.md: {current_dir}")
            
            if deepest_resolved_dir and webpage_text:
                self.logger.debug(f"Trying content-based matching in: {deepest_resolved_dir}")
                content_match = self.find_matching_file_by_content(deepest_resolved_dir, webpage_text)
                if content_match:
                    self.logger.info(f"Content-based match for {page_url}: {content_match}")
                    return content_match
            
            self.logger.debug(f"No local file found for {page_url}")
            return None
            
        except Exception as e:
            self.logger.error(f"Failed to map URL to local path: {e}")
            return None
    
    def apply_fixes(self, page_url: str, issues: Dict[str, List], webpage_text: str = None):
        """Apply fixes to local markdown files.
        
        Args:
            page_url: The URL of the page being fixed
            issues: Dictionary of issue types to their detected issues
            webpage_text: Optional text content from the webpage for content-based file matching
        """
        local_path = self.map_url_to_local_path(page_url, webpage_text)
        if not local_path or not os.path.exists(local_path):
            self.logger.warning(f"No local file found for {page_url} (local_webserver={self.local_webserver})")
            return
        
        # Skip _index.md files (Hugo section pages with navigation content only)
        if os.path.basename(local_path) == '_index.md':
            self.logger.debug(f"Skipping _index.md section page: {local_path}")
            return
        
        self.logger.info(f"Found local file for {page_url}: {local_path}")
        
        try:
            with self.lecturer.file_edit_lock:
                with open(local_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                original = content
                
                # =========================================================
                # Deterministic fixes (no LLM required)
                # =========================================================
                
                # Fix broken email addresses
                broken_email_issues = issues.get('broken_email_issues', [])
                if broken_email_issues and 'broken_email_issues' in self.lecturer.enabled_fix_keys:
                    content = self.lecturer._fix_broken_email_addresses(content)
                
                # Fix VMware spelling (using plugin)
                vmware_issues = issues.get('vmware_spelling_issues', [])
                if vmware_issues and 'vmware_spelling_issues' in self.lecturer.enabled_fix_keys:
                    spelling_plugin = self.lecturer.plugin_manager.get_plugin('spelling')
                    if spelling_plugin:
                        plugin_issues = [Issue(category='spelling', location='', description=str(i)) for i in vmware_issues]
                        result = spelling_plugin.fix(content, plugin_issues)
                        if result.success and result.modified_content:
                            content = result.modified_content
                
                # Fix deprecated VMware URLs (using plugin)
                deprecated_url_issues = issues.get('deprecated_url_issues', [])
                if deprecated_url_issues and 'deprecated_url_issues' in self.lecturer.enabled_fix_keys:
                    deprecated_plugin = self.lecturer.plugin_manager.get_plugin('deprecated_url')
                    if deprecated_plugin:
                        plugin_issues = [Issue(category='deprecated_url', location='', description=str(i)) for i in deprecated_url_issues]
                        result = deprecated_plugin.fix(content, plugin_issues)
                        if result.success and result.modified_content:
                            content = result.modified_content
                
                # Fix all backtick issues (unified LLM-based fix)
                backtick_issues = issues.get('backtick_issues', [])
                if backtick_issues and self.lecturer.llm_client and 'backtick_issues' in self.lecturer.enabled_fix_keys:
                    try:
                        fixed = self.lecturer.llm_client.fix_backticks(content, backtick_issues)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM backtick fix failed: {e}")
                
                # Fix shell prompts (using plugin) - FEATURE
                shell_prompt_issues = issues.get('shell_prompt_issues', [])
                if shell_prompt_issues and 'shell_prompt_issues' in self.lecturer.enabled_feature_keys:
                    shell_plugin = self.lecturer.plugin_manager.get_plugin('shell_prompt')
                    if shell_plugin:
                        plugin_issues = [Issue(category='shell_prompt', location='', description=str(i)) for i in shell_prompt_issues]
                        result = shell_plugin.fix(content, plugin_issues)
                        if result.success and result.modified_content:
                            content = result.modified_content
                
                # Fix heading hierarchy
                heading_hierarchy_issues = issues.get('heading_hierarchy_issues', [])
                if heading_hierarchy_issues and 'heading_hierarchy_issues' in self.lecturer.enabled_fix_keys:
                    content, hierarchy_fixes = self.lecturer._fix_heading_hierarchy(content)
                    if hierarchy_fixes:
                        self.logger.info(f"Applied {len(hierarchy_fixes)} heading hierarchy fixes to {local_path}")
                
                # Fix markdown header spacing
                header_spacing_issues = issues.get('header_spacing_issues', [])
                if header_spacing_issues and 'header_spacing_issues' in self.lecturer.enabled_fix_keys:
                    content = self.lecturer._fix_markdown_header_spacing(content)
                
                # Fix HTML comments
                html_comment_issues = issues.get('html_comment_issues', [])
                if html_comment_issues and 'html_comment_issues' in self.lecturer.enabled_fix_keys:
                    content = self.lecturer._fix_html_comments(content)
                
                # Fix numbered list sequence
                numbered_list_issues = issues.get('numbered_list_issues', [])
                if numbered_list_issues and 'numbered_list_issues' in self.lecturer.enabled_fix_keys:
                    content = self.lecturer._fix_numbered_list_sequence(content)
                
                # Fix hardcoded typos and errors (using plugin)
                hardcoded_replaces_issues = issues.get('hardcoded_replaces_issues', [])
                if hardcoded_replaces_issues and 'hardcoded_replaces_issues' in self.lecturer.enabled_fix_keys:
                    hardcoded_plugin = self.lecturer.plugin_manager.get_plugin('hardcoded_replaces')
                    if hardcoded_plugin:
                        plugin_issues = [Issue(category='hardcoded_replaces', location='', description=str(i)) for i in hardcoded_replaces_issues]
                        result = hardcoded_plugin.fix(content, plugin_issues)
                        if result.success and result.modified_content:
                            content = result.modified_content
                
                # =========================================================
                # LLM-based fixes
                # =========================================================
                
                grammar_issues = issues.get('grammar_issues', [])
                if grammar_issues and self.lecturer.llm_client and 'grammar_issues' in self.lecturer.enabled_fix_keys:
                    try:
                        fixed = self.lecturer.llm_client.fix_grammar(content, grammar_issues)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM grammar fix failed: {e}")
                
                md_artifacts = issues.get('md_artifacts', [])
                if md_artifacts and self.lecturer.llm_client and 'md_artifacts' in self.lecturer.enabled_fix_keys:
                    try:
                        fixed = self.lecturer.llm_client.fix_markdown(content, md_artifacts)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM markdown fix failed: {e}")
                
                mixed_cmd_output_issues = issues.get('mixed_cmd_output_issues', [])
                if mixed_cmd_output_issues and self.lecturer.llm_client and 'mixed_cmd_output_issues' in self.lecturer.enabled_feature_keys:
                    try:
                        content = self.lecturer._fix_mixed_command_output_llm(content, mixed_cmd_output_issues)
                    except Exception as e:
                        self.logger.error(f"LLM mixed command/output fix failed: {e}")
                
                indentation_issues = issues.get('indentation_issues', [])
                if indentation_issues and self.lecturer.llm_client and 'indentation_issues' in self.lecturer.enabled_fix_keys:
                    try:
                        fixed = self.lecturer.llm_client.fix_indentation(content, indentation_issues)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM indentation fix failed: {e}")
                
                # Translate if needed
                if self.lecturer.language != 'en' and self.lecturer.llm_client:
                    try:
                        translated = self.lecturer.llm_client.translate(content, self.lecturer.language)
                        if translated:
                            content = translated
                    except Exception as e:
                        self.logger.error(f"LLM translation failed: {e}")
                
                # =========================================================
                # Post-LLM cleanup
                # =========================================================
                
                # No additional cleanup needed - backtick fixes are now unified in LLM
                
                # Write back if changed
                if content != original:
                    with open(local_path, 'w', encoding='utf-8') as f:
                        f.write(content)
                    self.lecturer.modified_files.add(local_path)
                    self.lecturer.fixes_applied += 1
                    
                    applied_fixes = self._get_applied_fixes_list(issues)
                    fixes_str = ', '.join(applied_fixes) if applied_fixes else 'content changes'
                    self.logger.info(f"Applied fixes to {local_path}: {fixes_str}")
                    print(f"  [FIX] {os.path.basename(local_path)}: {fixes_str}")
                    
                    if self.lecturer.gh_pr and self.lecturer.repo_cloned:
                        self.lecturer._incremental_commit_push_and_pr(local_path, applied_fixes)
                else:
                    self.logger.debug(f"No changes needed for {local_path}")
                
        except Exception as e:
            self.logger.error(f"Failed to apply fixes to {local_path}: {e}")
    
    def _get_applied_fixes_list(self, issues: Dict[str, List]) -> List[str]:
        """Get list of fix descriptions that were applied."""
        applied_fixes = []
        
        if issues.get('broken_email_issues') and 'broken_email_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('broken emails')
        if issues.get('vmware_spelling_issues') and 'vmware_spelling_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('VMware spelling')
        if issues.get('deprecated_url_issues') and 'deprecated_url_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('deprecated URLs')
        if issues.get('backtick_issues') and self.lecturer.llm_client and 'backtick_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('backticks (LLM)')
        if issues.get('shell_prompt_issues') and 'shell_prompt_issues' in self.lecturer.enabled_feature_keys:
            applied_fixes.append('shell prompts')
        if issues.get('heading_hierarchy_issues') and 'heading_hierarchy_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('heading hierarchy')
        if issues.get('header_spacing_issues') and 'header_spacing_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('header spacing')
        if issues.get('html_comment_issues') and 'html_comment_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('HTML comments')
        if issues.get('grammar_issues') and self.lecturer.llm_client and 'grammar_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('grammar (LLM)')
        if issues.get('md_artifacts') and self.lecturer.llm_client and 'md_artifacts' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('markdown (LLM)')
        if issues.get('mixed_cmd_output_issues') and self.lecturer.llm_client and 'mixed_cmd_output_issues' in self.lecturer.enabled_feature_keys:
            applied_fixes.append('mixed cmd/output (LLM)')
        if issues.get('indentation_issues') and self.lecturer.llm_client and 'indentation_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('indentation (LLM)')
        if issues.get('hardcoded_replaces_issues') and 'hardcoded_replaces_issues' in self.lecturer.enabled_fix_keys:
            applied_fixes.append('hardcoded replaces')
        
        return applied_fixes
