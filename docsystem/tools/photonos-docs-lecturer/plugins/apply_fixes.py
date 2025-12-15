#!/usr/bin/env python3
"""
Apply Fixes Module for Photon OS Documentation Lecturer

Provides functionality to apply fixes to local markdown files based on detected issues.

Version: 1.1.0
"""

from __future__ import annotations

import os
import re
import urllib.parse
from typing import Any, Dict, List, Optional, Set, TYPE_CHECKING

from .base import Issue

if TYPE_CHECKING:
    from ..photonos_docs_lecturer import DocumentationLecturer

__version__ = "1.1.0"


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
        # Track files that have already had content restoration applied
        # to prevent duplicate restorations when same file accessed via multiple URLs
        self._content_restored_files = set()
    
    @property
    def local_webserver(self) -> Optional[str]:
        return self.lecturer.local_webserver
    
    @property
    def logger(self):
        return self.lecturer.logger
    
    @property
    def language(self) -> str:
        return self.lecturer.language
    
    def _get_git_file_content(self, file_path: str) -> Optional[str]:
        """Get the git HEAD version of a file.
        
        This is used to compare against the original git content when the local
        file may have been modified by installer.sh (e.g., relative paths changed).
        
        Args:
            file_path: Absolute path to the file
            
        Returns:
            Content from git HEAD, or None if not in a git repo or file not tracked
        """
        import subprocess
        
        try:
            # Find the git root directory
            result = subprocess.run(
                ['git', 'rev-parse', '--show-toplevel'],
                cwd=os.path.dirname(file_path),
                capture_output=True,
                text=True,
                timeout=5
            )
            if result.returncode != 0:
                return None
            
            git_root = result.stdout.strip()
            
            # Get relative path from git root
            rel_path = os.path.relpath(file_path, git_root)
            
            # Get file content from HEAD
            result = subprocess.run(
                ['git', 'show', f'HEAD:{rel_path}'],
                cwd=git_root,
                capture_output=True,
                text=True,
                timeout=10
            )
            if result.returncode != 0:
                return None
            
            return result.stdout
            
        except Exception as e:
            self.logger.debug(f"Could not get git version of {file_path}: {e}")
            return None
    
    # Pattern to match relative paths in markdown links: [text](./path), [text](../path) or [text](../../path)
    # Also matches image references: ![alt](../images/file.png)
    # Matches BOTH ./ (single dot) and ../ (double dots) paths
    RELATIVE_PATH_PATTERN = re.compile(
        r'(\[!?\[[^\]]*\]\()'  # Opening: [text]( or [![text](
        r'(\.{1,2}(?:/\.\.)*'  # Relative path: ./ or ../ or ../../ etc. (\.{1,2} matches 1-2 dots)
        r'/[^)\s]+)'           # Rest of path until )
        r'(\))'                # Closing )
    )
    
    # Pattern to match standalone relative paths in parentheses (for images)
    # Matches BOTH ./ (single dot) and ../ (double dots) paths
    STANDALONE_RELATIVE_PATH = re.compile(
        r'(\()'                # Opening (
        r'(\.{1,2}(?:/\.\.)*'  # Relative path: ./ or ../ or ../../ etc. (\.{1,2} matches 1-2 dots)
        r'/[^)\s]+)'           # Rest of path until )
        r'(\))'                # Closing )
    )
    
    def _revert_relative_path_changes(self, content: str, original: str) -> str:
        """Revert any relative path modifications back to original paths.
        
        Compares relative paths in content with original and reverts any changes.
        This is used when FIX_ID 13 (relative-paths) is not enabled.
        
        Uses two strategies:
        1. Line-by-line comparison for paths that have identical surrounding context
        2. Context-based matching for paths where surrounding text also changed
        
        Args:
            content: The modified content
            original: The original content before fixes
            
        Returns:
            Content with relative paths reverted to original values
        """
        if content == original:
            return content
        
        result = content
        reverted_count = 0
        
        # Strategy 1: Extract all markdown links/images with relative paths using position tracking
        # Pattern matches: [text](./path), [text](../path) or ![alt](../path)
        # Matches BOTH ./ (single dot) and ../ (double dots) paths
        MARKDOWN_LINK_WITH_PATH = re.compile(
            r'(!?\[[^\]]*\])'           # Link/image text: [text] or ![alt]
            r'\('                        # Opening paren
            r'(\.{1,2}(?:/\.\.)*'        # Relative path: ./ or ../ or ../../ etc.
            r'/[^)\s]+)'                 # Rest of path until ) or space
            r'\)'                        # Closing paren
        )
        
        # Extract paths as a list of (link_text, path, start_pos, end_pos) tuples from original
        # Using positions allows accurate matching even with duplicate link texts
        original_links = []
        for match in MARKDOWN_LINK_WITH_PATH.finditer(original):
            link_text = match.group(1)  # [text] or ![alt]
            path = match.group(2)        # ../images/foo.png or ./path/
            original_links.append((link_text, path, match.start(), match.end()))
        
        # Extract paths from content as a list with positions
        content_links = []
        for match in MARKDOWN_LINK_WITH_PATH.finditer(result):
            link_text = match.group(1)
            path = match.group(2)
            content_links.append((link_text, path, match.start(), match.end()))
        
        # Build list of replacements to make (process in reverse order to preserve positions)
        replacements = []
        
        # Match links by position: compare original[i] with content[i]
        # This handles cases where the same link text appears multiple times with different paths
        for i, (orig_link_text, orig_path, _, _) in enumerate(original_links):
            if i < len(content_links):
                content_link_text, content_path, start_pos, end_pos = content_links[i]
                # Only revert if link text matches but path differs
                if orig_link_text == content_link_text and orig_path != content_path:
                    # Schedule replacement using exact string positions
                    old_link = f"{content_link_text}({content_path})"
                    new_link = f"{orig_link_text}({orig_path})"
                    replacements.append((start_pos, end_pos, old_link, new_link, content_path, orig_path))
        
        # Apply replacements in reverse order (from end to start) to preserve string positions
        for start_pos, end_pos, old_link, new_link, content_path, orig_path in reversed(replacements):
            # Verify the old_link is at the expected position
            actual_text = result[start_pos:end_pos]
            if actual_text == old_link:
                result = result[:start_pos] + new_link + result[end_pos:]
                reverted_count += 1
                self.logger.info(f"Reverted relative path: {content_path} -> {orig_path}")
        
        # Strategy 2: Fallback context-based matching for any remaining differences
        # This catches paths where the link text might have changed slightly
        def extract_paths_with_context(text: str) -> dict:
            """Extract relative paths with surrounding context."""
            paths = {}
            for match in self.STANDALONE_RELATIVE_PATH.finditer(text):
                path = match.group(2)
                start = max(0, match.start() - 50)
                end = min(len(text), match.end() + 50)
                context = text[start:end]
                paths[context] = path
            return paths
        
        original_paths = extract_paths_with_context(original)
        content_paths = extract_paths_with_context(result)
        
        for orig_context, orig_path in original_paths.items():
            for content_context, new_path in content_paths.items():
                if orig_path != new_path:
                    orig_context_clean = orig_context.replace(orig_path, '')
                    content_context_clean = content_context.replace(new_path, '')
                    
                    if self._contexts_match(orig_context_clean, content_context_clean):
                        old_str = f'({new_path})'
                        new_str = f'({orig_path})'
                        if old_str in result:
                            result = result.replace(old_str, new_str)
                            reverted_count += 1
                            self.logger.info(f"Reverted relative path (context): {new_path} -> {orig_path}")
        
        if reverted_count > 0:
            self.logger.info(f"Reverted {reverted_count} relative path modification(s)")
        
        return result
    
    def _contexts_match(self, ctx1: str, ctx2: str) -> bool:
        """Check if two contexts are similar enough to be the same location."""
        # Remove whitespace and compare
        ctx1_clean = re.sub(r'\s+', '', ctx1)
        ctx2_clean = re.sub(r'\s+', '', ctx2)
        
        # Check for significant overlap
        if len(ctx1_clean) < 10 or len(ctx2_clean) < 10:
            return ctx1_clean == ctx2_clean
        
        # Check if one is substring of the other or they share most characters
        if ctx1_clean in ctx2_clean or ctx2_clean in ctx1_clean:
            return True
        
        # Calculate similarity
        common = sum(1 for a, b in zip(ctx1_clean, ctx2_clean) if a == b)
        similarity = common / max(len(ctx1_clean), len(ctx2_clean))
        
        return similarity > 0.7
    
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
    
    def extract_title_from_markdown(self, file_path: str) -> Optional[str]:
        """Extract the title from a markdown file's frontmatter.
        
        Args:
            file_path: Path to the markdown file
            
        Returns:
            The title string, or None if not found
        """
        try:
            with open(file_path, 'r', encoding='utf-8') as f:
                content = f.read(1000)  # Read first 1000 chars for frontmatter
            
            # Check for YAML frontmatter
            if content.startswith('---'):
                end = content.find('---', 3)
                if end > 0:
                    frontmatter = content[3:end]
                    # Extract title
                    for line in frontmatter.split('\n'):
                        if line.strip().startswith('title:'):
                            title = line.split(':', 1)[1].strip()
                            # Remove quotes if present
                            if (title.startswith('"') and title.endswith('"')) or \
                               (title.startswith("'") and title.endswith("'")):
                                title = title[1:-1]
                            return title
        except Exception:
            pass
        return None
    
    def normalize_slug(self, text: str) -> str:
        """Normalize text to a URL slug format for comparison.
        
        Args:
            text: Text to normalize (e.g., "Building OVA image")
            
        Returns:
            Normalized slug (e.g., "building-ova-image")
        """
        # Convert to lowercase
        slug = text.lower()
        # Replace spaces and underscores with hyphens
        slug = re.sub(r'[\s_]+', '-', slug)
        # Remove non-alphanumeric characters except hyphens
        slug = re.sub(r'[^a-z0-9-]', '', slug)
        # Remove multiple consecutive hyphens
        slug = re.sub(r'-+', '-', slug)
        # Strip leading/trailing hyphens
        slug = slug.strip('-')
        return slug
    
    def find_matching_file_by_content(self, parent_dir: str, webpage_text: str, 
                                      min_similarity: float = 0.3,
                                      url_slug: str = None) -> Optional[str]:
        """Find a markdown file in parent_dir that best matches the webpage content.
        
        This is a fallback when path-based matching fails. It first tries to match
        by comparing the URL slug with file titles (from frontmatter), then falls
        back to content similarity matching.
        
        Args:
            parent_dir: Directory to search for markdown files
            webpage_text: Text content extracted from the webpage
            min_similarity: Minimum similarity threshold (0.0 to 1.0)
            url_slug: Optional URL slug to match against file titles
            
        Returns:
            Path to the best matching file, or None if no match above threshold
        """
        if not os.path.isdir(parent_dir) or not webpage_text:
            return None
        
        best_match = None
        best_score = min_similarity
        title_match = None
        
        try:
            for entry in os.listdir(parent_dir):
                if not entry.endswith('.md') or entry.startswith('_'):
                    continue
                
                file_path = os.path.join(parent_dir, entry)
                if not os.path.isfile(file_path):
                    continue
                
                try:
                    # First, try title-based matching if url_slug is provided
                    if url_slug and not title_match:
                        file_title = self.extract_title_from_markdown(file_path)
                        if file_title:
                            title_slug = self.normalize_slug(file_title)
                            if title_slug == url_slug:
                                self.logger.debug(f"Title match found: {entry} (title: '{file_title}' -> slug: '{title_slug}')")
                                title_match = file_path
                    
                    # Also compute content similarity for fallback
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
            
            # Prefer title match over content match
            if title_match:
                self.logger.debug(f"Using title-based match: {title_match}")
                return title_match
            
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
                # Extract the last part of the URL path as the slug for title matching
                url_slug = path_parts[-1] if path_parts else None
                content_match = self.find_matching_file_by_content(
                    deepest_resolved_dir, webpage_text, url_slug=url_slug
                )
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
                
                # Fix hardcoded typos and errors (using plugin)
                # NOTE: Must run BEFORE deprecated_url to allow specific full-string replacements
                # (like "[https://packages.vmware.com/photon](https://packages.vmware.com/photon)")
                # to take precedence over regex-based URL replacements
                hardcoded_replaces_issues = issues.get('hardcoded_replaces_issues', [])
                if hardcoded_replaces_issues and 'hardcoded_replaces_issues' in self.lecturer.enabled_fix_keys:
                    hardcoded_plugin = self.lecturer.plugin_manager.get_plugin('hardcoded_replaces')
                    if hardcoded_plugin:
                        plugin_issues = [Issue(category='hardcoded_replaces', location='', description=str(i)) for i in hardcoded_replaces_issues]
                        result = hardcoded_plugin.fix(content, plugin_issues)
                        if result.success and result.modified_content:
                            content = result.modified_content
                
                # Fix deprecated VMware URLs (using plugin)
                # NOTE: Runs AFTER hardcoded_replaces so specific replacements take precedence
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
                
                # Revert relative path modifications if FIX_ID 13 is not enabled
                # The local file may have relative paths modified by installer.sh
                # Compare against git HEAD version to get the TRUE original paths
                if 'relative_path_issues' not in self.lecturer.enabled_fix_keys:
                    # Get git version for true original paths (installer.sh may have modified local file)
                    git_content = self._get_git_file_content(local_path)
                    if git_content:
                        content = self._revert_relative_path_changes(content, git_content)
                    else:
                        # Fallback to local original if git version not available
                        content = self._revert_relative_path_changes(content, original)
                
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
