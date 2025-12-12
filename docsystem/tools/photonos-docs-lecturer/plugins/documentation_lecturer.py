#!/usr/bin/env python3
"""
Documentation Lecturer Module for Photon OS Documentation Lecturer

Provides the main DocumentationLecturer class for crawling, analyzing,
and fixing Photon OS documentation.

Version: 1.0.0
"""

from __future__ import annotations

import csv
import datetime
import json
import logging
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
import urllib.parse
import urllib.robotparser
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

# These will be set by set_dependencies() before class instantiation
requests = None
BeautifulSoup = None
language_tool_python = None
Retry = None
HTTPAdapter = None
tqdm = None
Image = None
HAS_TQDM = False
HAS_PIL = False

# Plugin imports
from . import PluginManager, Issue, FixResult
from .integration import create_plugin_manager, ALL_PLUGINS, FIX_ID_MAP
from .apply_fixes import FixApplicator
from .llm_client import LLMClient

__version__ = "1.0.0"

# Tool info (will be set from main module)
TOOL_NAME = "photonos-docs-lecturer.py"
VERSION = "2.4"


def set_tool_info(tool_name: str, version: str):
    """Set tool name and version from main module."""
    global TOOL_NAME, VERSION
    TOOL_NAME = tool_name
    VERSION = version


def set_dependencies(deps: dict):
    """Set module dependencies from the main script.
    
    This must be called before instantiating DocumentationLecturer.
    
    Args:
        deps: Dictionary with keys: requests, BeautifulSoup, language_tool_python,
              Retry, HTTPAdapter, tqdm, Image, HAS_TQDM, HAS_PIL
    """
    global requests, BeautifulSoup, language_tool_python, Retry, HTTPAdapter
    global tqdm, Image, HAS_TQDM, HAS_PIL
    
    requests = deps.get('requests')
    BeautifulSoup = deps.get('BeautifulSoup')
    language_tool_python = deps.get('language_tool_python')
    Retry = deps.get('Retry')
    HTTPAdapter = deps.get('HTTPAdapter')
    tqdm = deps.get('tqdm')
    Image = deps.get('Image')
    HAS_TQDM = deps.get('HAS_TQDM', False)
    HAS_PIL = deps.get('HAS_PIL', False)


class DocumentationLecturer:
    """Main class for Photon OS documentation analysis and fixing."""
    
    # Markdown artifacts patterns to detect
    MARKDOWN_PATTERNS = [
        re.compile(r'(?<!\`)##\s+\w+'),  # Headers not rendered
        re.compile(r'\*\s+\w+'),  # Unrendered bullet points
        re.compile(r'\[([^\]]+)\]\(([^\)]+)\)'),  # Unrendered links
        re.compile(r'```[\s\S]*?```'),  # Code blocks not rendered
        re.compile(r'`[^`]+`'),  # Inline code not rendered
        re.compile(r'\*\*([^\*]+)\*\*'),  # Bold text not rendered
        re.compile(r'_([^_]+)_'),  # Italic text not rendered
    ]
    
    # Pattern for missing space before backticks (e.g., "Clone`the" should be "Clone `the")
    # Uses [^\s`] after opening backtick to ensure we match valid inline code (content must start
    # with non-whitespace), preventing false matches from closing backticks of other code spans.
    # Uses [^`\n]*? (non-greedy, no newlines) to match minimal content within same line.
    MISSING_SPACE_BEFORE_BACKTICK = re.compile(r'([a-zA-Z])(`[^\s`][^`\n]*?`)')
    
    # Pattern for stray opening backtick followed by plain text (no closing backtick)
    # This detects patterns like "Clone`the Photon project:" where backtick is a typo
    # Match: word + backtick + word char (without closing backtick on the same line)
    # Requires whitespace or start of line before the word to avoid matching within valid inline code
    # The backtick is likely a typo for a space, so we remove it and add a space
    STRAY_BACKTICK_TYPO = re.compile(r'(?:^|(?<=\s))([a-zA-Z]+)`([a-zA-Z])(?![^`\n]*`)')
    
    # Pattern for missing space after backticks (e.g., "`command`text" should be "`command` text")
    # Same constraints as above to ensure we match complete, valid inline code spans.
    MISSING_SPACE_AFTER_BACKTICK = re.compile(r'(`[^\s`][^`\n]*?`)([a-zA-Z])')
    
    # Patterns for detecting malformed inline code backticks
    # These patterns match single inline code spans with space issues
    # Uses (?<!\S) lookbehind to ensure opening backtick is at word boundary
    # Uses (?!\S) lookahead to ensure closing backtick is at word boundary
    
    # Inline code with space after opening backtick: "` code`" should be "`code`"
    # Match: word boundary, backtick, whitespace, non-whitespace content, backtick, word boundary
    INLINE_CODE_SPACE_AFTER_OPEN = re.compile(r'(?<![`\w])`[ \t]+(\S[^`\n]*?)`(?![`\w])')
    
    # Inline code with space before closing backtick: "`code `" should be "`code`"
    # Match: word boundary, backtick, content ending in non-whitespace, whitespace, backtick, word boundary
    INLINE_CODE_SPACE_BEFORE_CLOSE = re.compile(r'(?<![`\w])`([^`\n]*?\S)[ \t]+`(?![`\w])')
    
    # Inline code with spaces on both sides: "` code `" should be "`code`"
    # Match: word boundary, backtick, whitespace, content, whitespace, backtick, word boundary
    INLINE_CODE_SPACES_BOTH = re.compile(r'(?<![`\w])`[ \t]+([^`\n]+?)[ \t]+`(?![`\w])')
    
    # Patterns for detecting malformed code blocks
    # Pattern 1: Single backtick followed by content and 3+ backticks: `content``` or `content`````
    # This is a common error where someone started inline code but ended with fenced code block syntax
    MALFORMED_CODE_BLOCK_SINGLE_TRIPLE = re.compile(r'`([^`\n]+)`{3,}')
    
    # Pattern 2: Consecutive lines starting with single backtick containing commands
    # These should be converted to a fenced code block
    # Matches: `command1`\n    `command2`
    CONSECUTIVE_INLINE_COMMANDS = re.compile(
        r'(?:^|\n)(\s*)`([^`\n]+)`\s*\n\s*`([^`\n]+)`',
        re.MULTILINE
    )
    
    # Pattern 3: Plain text commands that should be in code blocks or backticks
    # These are commands appearing as plain text after list items without proper formatting
    # Matches: indented line starting with common command patterns (git clone, cd $, sudo make, export)
    PLAIN_TEXT_COMMAND_PATTERN = re.compile(
        r'^(\s{4,})'  # At least 4 spaces of indentation (typical list content)
        r'((?:git\s+clone|cd\s+\$|sudo\s+make|export\s+\w+=)[^\n]*)',  # Command pattern
        re.MULTILINE
    )
    
    # Pattern 4: Consecutive plain text commands that should be in a single code block
    # Matches two or more consecutive indented command lines
    CONSECUTIVE_PLAIN_TEXT_COMMANDS = re.compile(
        r'^(\s{4,})'  # Indentation
        r'((?:git\s+clone|cd\s+\$|sudo\s+make|export\s+\w+=)[^\n]*\n)'  # First command
        r'(\s{4,}(?:git\s+clone|cd\s+\$|sudo\s+make|export\s+\w+=)[^\n]*)',  # Second command
        re.MULTILINE
    )
    
    # Pattern 5: Fenced code block used incorrectly for inline code within a sentence
    # This pattern detects when a fenced code block (```...```) contains a single word/term
    # and is followed by text that continues the sentence (like " is a", " are", etc.) or punctuation
    # Example: ```bash\ncloud-init\n``` is a multi-distribution... -> `cloud-init` is a multi-distribution...
    # Example: ...hostname is set to ```bash\ntesthost\n```. -> ...hostname is set to `testhost`.
    # Matches: optional lang specifier, single-line content, followed by sentence continuation or punctuation
    FENCED_INLINE_CODE_PATTERN = re.compile(
        r'```(?:bash|sh|shell|console|text)?\s*\n'  # Opening fence with optional language
        r'([a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+)?)\s*\n'  # Single word or two words (like "cloud-init" or "ec2 datasource")
        r'```'  # Closing fence
        r'(\s*(?:[.,;:!?]|(?:\s+(?:is|are|was|were|has|have|had|can|will|would|should|may|might|must|turned|configuration|data|with)\b)))',  # Punctuation or sentence continuation
        re.MULTILINE
    )
    
    # Pattern 6: Triple backticks used as inline code delimiters (on same line, no newlines)
    # This is a common error where authors use ```term``` instead of `term`
    # Example: ```cloud-init``` is a multi-distribution... -> `cloud-init` is a multi-distribution...
    # Note: This is different from Pattern 5 which handles fenced blocks with newlines
    TRIPLE_BACKTICK_INLINE_PATTERN = re.compile(
        r'```'  # Opening triple backtick
        r'([a-zA-Z0-9_-]+(?:\s+[a-zA-Z0-9_-]+)?)'  # Single word or two words (no newlines allowed)
        r'```'  # Closing triple backtick
    )
    
    # Pattern for detecting indentation issues in numbered/bulleted lists
    # Matches lines that start with a number followed by period/parenthesis
    NUMBERED_LIST_PATTERN = re.compile(r'^(\s*)(\d+)([.)])(\s+)(.*)$', re.MULTILINE)
    
    # Patterns for detecting shell prompt prefixes in code blocks that should be removed
    # These are common shell prompts that shouldn't be part of copyable commands
    # Note: Patterns include optional leading whitespace to handle indented code blocks
    # Note: "#" alone is NOT included as it's typically used for comments in code blocks, not root prompts
    SHELL_PROMPT_PATTERNS = [
        re.compile(r'^(\s*)(\$\s+)(.+)$', re.MULTILINE),      # "$ command" - standard user prompt
        re.compile(r'^(\s*)(>\s+)(.+)$', re.MULTILINE),       # "> command" - alternative prompt
        re.compile(r'^(\s*)(%\s+)(.+)$', re.MULTILINE),       # "% command" - csh/tcsh prompt
        re.compile(r'^(\s*)(~\s+)(.+)$', re.MULTILINE),       # "~ command" - home directory prompt
        re.compile(r'^(\s*)(❯\s*)(.+)$', re.MULTILINE),       # "❯ command" - fancy prompt (e.g., starship, powerline)
        re.compile(r'^(\s*)(➜\s+)(.+)$', re.MULTILINE),       # "➜  command" - Oh My Zsh robbyrussell theme
        re.compile(r'^(\s*)(root@\S+[#$]\s*)(.+)$', re.MULTILINE),  # "root@host# command"
        re.compile(r'^(\s*)(\w+@\S+[#$%]\s*)(.+)$', re.MULTILINE),  # "user@host$ command"
    ]
    
    # Deprecated VMware packages URL pattern
    DEPRECATED_VMWARE_URL = re.compile(r'https?://packages\.vmware\.com/[^\s"\'<>]*')
    VMWARE_URL_REPLACEMENT = 'https://packages.broadcom.com/'
    
    # Deprecated VDDK download URL patterns (multiple sources)
    DEPRECATED_VDDK_URLS = [
        'https://my.vmware.com/web/vmware/downloads/details?downloadGroup=VDDK670&productId=742',
        'https://developercenter.vmware.com/web/sdk/60/vddk'
    ]
    VDDK_URL_REPLACEMENT = 'https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7'
    # Full markdown link replacement for VDDK 6.0 -> VDDK 6.7
    DEPRECATED_VDDK_60_LINK = '[VDDK 6.0](https://developercenter.vmware.com/web/sdk/60/vddk)'
    VDDK_67_LINK_REPLACEMENT = '[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)'
    # Keep old constant for backward compatibility
    DEPRECATED_VDDK_URL = DEPRECATED_VDDK_URLS[0]
    
    # Deprecated OVFTOOL URL (my.vmware.com -> developer.broadcom.com)
    DEPRECATED_OVFTOOL_URL = 'https://my.vmware.com/group/vmware/details?downloadGroup=OVFTOOL410&productId=491'
    OVFTOOL_URL_REPLACEMENT = 'https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest'
    
    # Deprecated AWS EC2 CLI URL patterns (both http and https)
    DEPRECATED_AWS_EC2_CLI_URLS = [
        'http://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html',
        'https://docs.aws.amazon.com/AWSEC2/latest/CommandLineReference/set-up-ec2-cli-linux.html'
    ]
    AWS_EC2_CLI_URL_REPLACEMENT = 'https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html'
    
    # Deprecated CloudFoundry bosh-stemcell URL (branch changed from develop to main, path changed)
    DEPRECATED_BOSH_STEMCELL_URL = 'https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md'
    BOSH_STEMCELL_URL_REPLACEMENT = 'https://github.com/cloudfoundry/bosh/blob/main/README.md'
    
    # Deprecated Bintray URLs (Bintray service was discontinued in 2021)
    # These URLs should be replaced with the GitHub wiki download page
    DEPRECATED_BINTRAY_URL_PATTERN = re.compile(r'https?://(?:dl\.)?bintray\.com/[^\s"\'<>\)]*')
    BINTRAY_URL_REPLACEMENT = 'https://github.com/vmware/photon/wiki/downloading-photon-os'
    
    # VMware spelling pattern - must be "VMware" with capital V and M
    # Matches incorrect spellings like "vmware", "Vmware", "VMWare", "VMWARE", etc.
    # Uses word boundaries and explicitly excludes the correct spelling
    VMWARE_SPELLING_PATTERN = re.compile(r'\b((?!VMware)[vV][mM][wW][aA][rR][eE])\b')
    
    # Pattern for broken email addresses in console output
    # Matches email addresses where the domain is split with whitespace/newlines
    # e.g., "linux-packages@vmware.                        com" should be "linux-packages@vmware.com"
    # Pattern: localpart@domain. followed by whitespace then TLD (com, org, net, etc.)
    BROKEN_EMAIL_PATTERN = re.compile(
        r'([\w.+-]+@[\w.-]+\.)'  # Email local part + @ + domain + dot
        r'(\s+)'                  # Whitespace (including newlines)
        r'(\w{2,6})'              # TLD (2-6 chars: com, org, net, io, etc.)
        r'(?=[>\s\)\]"\']|$)',    # Followed by common delimiters or end
        re.MULTILINE
    )
    
    # Markdown header without space pattern (e.g., "####Title" should be "#### Title")
    MARKDOWN_HEADER_NO_SPACE = re.compile(r'^(#{2,6})([^\s#].*)$', re.MULTILINE)
    
    # HTML comment pattern - matches <!-- ... --> including multiline comments
    # Used to detect and remove HTML comment markers while preserving inner content
    # This is for commented-out content that should be uncommented/visible
    HTML_COMMENT_PATTERN = re.compile(r'<!--\s*([\s\S]*?)\s*-->', re.MULTILINE)
    
    # Alignment CSS classes to check
    ALIGNMENT_CLASSES = ['align-center', 'align-left', 'align-right', 'centered', 
                         'img-responsive', 'text-center', 'mx-auto', 'd-block']
    CONTAINER_CLASSES = ['image-container', 'figure', 'gallery', 'img-gallery', 'images-row']
    
    # Markdown heading pattern for hierarchy analysis (ATX-style: # ## ### etc.)
    MARKDOWN_HEADING_PATTERN = re.compile(r'^(#{1,6})\s+(.+)$', re.MULTILINE)
    
    # Enumerated fix types for --fix parameter
    # Each fix has an ID, key (used in issues dict), description, and whether it requires LLM
    # NOTE: shell-prompts (ID 6) and mixed-cmd-output (ID 12) were moved to FEATURE_TYPES
    FIX_TYPES = {
        1: {'key': 'broken_email_issues', 'name': 'broken-emails', 'desc': 'Fix broken email addresses (domain split with whitespace)', 'llm': False},
        2: {'key': 'vmware_spelling_issues', 'name': 'vmware-spelling', 'desc': 'Fix VMware spelling (vmware -> VMware)', 'llm': False},
        3: {'key': 'deprecated_url_issues', 'name': 'deprecated-urls', 'desc': 'Fix deprecated URLs (VMware, VDDK, OVFTOOL, AWS, bosh-stemcell)', 'llm': False},
        4: {'key': 'backtick_issues', 'name': 'backticks', 'desc': 'Fix all backtick issues (spacing, errors, malformed blocks, URLs in backticks) (requires --llm)', 'llm': True},
        5: {'key': 'heading_hierarchy_issues', 'name': 'heading-hierarchy', 'desc': 'Fix heading hierarchy violations (skipped levels)', 'llm': False},
        6: {'key': 'header_spacing_issues', 'name': 'header-spacing', 'desc': 'Fix markdown headers missing space (####Title -> #### Title)', 'llm': False},
        7: {'key': 'html_comment_issues', 'name': 'html-comments', 'desc': 'Fix HTML comments (remove <!-- --> markers, keep content)', 'llm': False},
        8: {'key': 'grammar_issues', 'name': 'grammar', 'desc': 'Fix grammar and spelling issues (requires --llm)', 'llm': True},
        9: {'key': 'md_artifacts', 'name': 'markdown-artifacts', 'desc': 'Fix unrendered markdown artifacts (requires --llm)', 'llm': True},
        10: {'key': 'indentation_issues', 'name': 'indentation', 'desc': 'Fix indentation issues (requires --llm)', 'llm': True},
        11: {'key': 'numbered_list_issues', 'name': 'numbered-lists', 'desc': 'Fix numbered list sequence errors (duplicate numbers)', 'llm': False},
    }
    
    # Enumerated feature types for --feature parameter
    # Features are optional enhancements that may modify code block formatting
    # Each feature has an ID, key (used in issues dict), description, and whether it requires LLM
    FEATURE_TYPES = {
        1: {'key': 'shell_prompt_issues', 'name': 'shell-prompts', 'desc': 'Remove shell prompts in code blocks ($ # etc.)', 'llm': False},
        2: {'key': 'mixed_cmd_output_issues', 'name': 'mixed-cmd-output', 'desc': 'Separate mixed command/output in code blocks (requires --llm)', 'llm': True},
    }
    
    @classmethod
    def get_fix_help_text(cls) -> str:
        """Generate help text listing all available fixes."""
        lines = ["Available fixes:"]
        for fix_id, fix_info in cls.FIX_TYPES.items():
            llm_marker = " [LLM]" if fix_info['llm'] else ""
            lines.append(f"  {fix_id:2d}. {fix_info['name']:<20s} - {fix_info['desc']}{llm_marker}")
        return '\n'.join(lines)
    
    @classmethod
    def get_feature_help_text(cls) -> str:
        """Generate help text listing all available features."""
        lines = ["Available features:"]
        for feature_id, feature_info in cls.FEATURE_TYPES.items():
            llm_marker = " [LLM]" if feature_info['llm'] else ""
            lines.append(f"  {feature_id:2d}. {feature_info['name']:<20s} - {feature_info['desc']}{llm_marker}")
        return '\n'.join(lines)
    
    @classmethod
    def parse_fix_spec(cls, fix_spec: str) -> set:
        """Parse fix specification string into a set of fix IDs.
        
        Args:
            fix_spec: Comma-separated list of fix IDs or ranges (e.g., "1,2,3,5-9")
            
        Returns:
            Set of fix IDs to apply
            
        Raises:
            ValueError: If the specification is invalid
        """
        if not fix_spec or fix_spec.strip().lower() == 'all':
            return set(cls.FIX_TYPES.keys())
        
        fix_ids = set()
        parts = fix_spec.replace(' ', '').split(',')
        
        for part in parts:
            if not part:
                continue
            
            if '-' in part:
                # Range specification (e.g., "5-9")
                try:
                    start, end = part.split('-', 1)
                    start_id = int(start)
                    end_id = int(end)
                    
                    if start_id > end_id:
                        raise ValueError(f"Invalid range: {part} (start > end)")
                    
                    for fix_id in range(start_id, end_id + 1):
                        if fix_id in cls.FIX_TYPES:
                            fix_ids.add(fix_id)
                        else:
                            raise ValueError(f"Unknown fix ID in range: {fix_id}")
                except ValueError as e:
                    if "Unknown fix ID" in str(e) or "Invalid range" in str(e):
                        raise
                    raise ValueError(f"Invalid range format: {part}")
            else:
                # Single fix ID
                try:
                    fix_id = int(part)
                    if fix_id in cls.FIX_TYPES:
                        fix_ids.add(fix_id)
                    else:
                        raise ValueError(f"Unknown fix ID: {fix_id}. Valid IDs are 1-{max(cls.FIX_TYPES.keys())}")
                except ValueError as e:
                    if "Unknown fix ID" in str(e):
                        raise
                    raise ValueError(f"Invalid fix ID: {part}")
        
        return fix_ids
    
    @classmethod
    def get_enabled_fix_keys(cls, fix_ids: set) -> set:
        """Convert fix IDs to their corresponding issue keys."""
        return {cls.FIX_TYPES[fix_id]['key'] for fix_id in fix_ids if fix_id in cls.FIX_TYPES}
    
    @classmethod
    def parse_feature_spec(cls, feature_spec: str) -> set:
        """Parse feature specification string into a set of feature IDs.
        
        Args:
            feature_spec: Comma-separated list of feature IDs or ranges (e.g., "1,2" or "1-2")
            
        Returns:
            Set of feature IDs to apply
            
        Raises:
            ValueError: If the specification is invalid
        """
        if not feature_spec or feature_spec.strip().lower() == 'all':
            return set(cls.FEATURE_TYPES.keys())
        
        feature_ids = set()
        parts = feature_spec.replace(' ', '').split(',')
        
        for part in parts:
            if not part:
                continue
            
            if '-' in part:
                # Range specification (e.g., "1-2")
                try:
                    start, end = part.split('-', 1)
                    start_id = int(start)
                    end_id = int(end)
                    
                    if start_id > end_id:
                        raise ValueError(f"Invalid range: {part} (start > end)")
                    
                    for feature_id in range(start_id, end_id + 1):
                        if feature_id in cls.FEATURE_TYPES:
                            feature_ids.add(feature_id)
                        else:
                            raise ValueError(f"Unknown feature ID in range: {feature_id}")
                except ValueError as e:
                    if "Unknown feature ID" in str(e) or "Invalid range" in str(e):
                        raise
                    raise ValueError(f"Invalid range format: {part}")
            else:
                # Single feature ID
                try:
                    feature_id = int(part)
                    if feature_id in cls.FEATURE_TYPES:
                        feature_ids.add(feature_id)
                    else:
                        raise ValueError(f"Unknown feature ID: {feature_id}. Valid IDs are 1-{max(cls.FEATURE_TYPES.keys())}")
                except ValueError as e:
                    if "Unknown feature ID" in str(e):
                        raise
                    raise ValueError(f"Invalid feature ID: {part}")
        
        return feature_ids
    
    @classmethod
    def get_enabled_feature_keys(cls, feature_ids: set) -> set:
        """Convert feature IDs to their corresponding issue keys."""
        return {cls.FEATURE_TYPES[feature_id]['key'] for feature_id in feature_ids if feature_id in cls.FEATURE_TYPES}
    
    def __init__(self, args):
        """Initialize the lecturer with parsed arguments."""
        self.args = args
        self.command = args.command
        
        # Generate unique filenames
        self.timestamp = datetime.datetime.now().isoformat().replace(':', '-')
        self.report_filename = f"report-{self.timestamp}.csv"
        self.log_filename = f"report-{self.timestamp}.log"
        
        # Setup logging
        self._setup_logging()
        
        # Website configuration
        self.base_url = getattr(args, 'website', '').rstrip('/') if hasattr(args, 'website') else ''
        self.local_webserver = getattr(args, 'local_webserver', None)
        self.ref_website = getattr(args, 'ref_website', None)
        self.language = getattr(args, 'language', 'en')
        
        # Parallel processing
        self.num_workers = max(1, min(20, getattr(args, 'parallel', 1)))
        
        # GitHub configuration
        self.gh_repotoken = getattr(args, 'gh_repotoken', None)
        self.gh_username = getattr(args, 'gh_username', None)
        self.ghrepo_url = getattr(args, 'ghrepo_url', None)
        self.ghrepo_branch = getattr(args, 'ghrepo_branch', 'photon-hugo')  # Branch in user's forked repo
        self.ref_ghrepo = getattr(args, 'ref_ghrepo', None)
        self.ref_ghbranch = getattr(args, 'ref_ghbranch', 'photon-hugo')  # Base branch in reference repo for PR
        self.gh_pr = getattr(args, 'gh_pr', False)
        
        # LLM configuration
        self.llm_provider = getattr(args, 'llm', None)
        self.gemini_api_key = getattr(args, 'GEMINI_API_KEY', None)
        self.xai_api_key = getattr(args, 'XAI_API_KEY', None)
        self.llm_client = None
        
        # Initialize LLM client if needed
        if self.llm_provider:
            self._init_llm_client()
        
        # HTTP session with retries
        self.session = self._create_session()
        
        # Tracking sets
        self.visited_urls: Set[str] = set()
        self.sitemap: List[str] = []
        
        # Grammar tool (lazy loaded)
        self.grammar_tool: Optional[language_tool_python.LanguageTool] = None
        self.grammar_tool_lock = threading.Lock()
        
        # Thread-safe locks
        self.csv_lock = threading.Lock()
        self.file_edit_lock = threading.Lock()
        
        # Issue counters
        self.issues_found = 0
        self.pages_analyzed = 0
        self.fixes_applied = 0
        
        # Files modified for git
        self.modified_files: Set[str] = set()
        
        # Progress bar
        self.progress_bar = None
        
        # Temp directory for cloning
        self.temp_dir = None
        
        # Incremental PR state
        self.pr_url: Optional[str] = None  # URL of created PR (None if not created yet)
        self.pr_number: Optional[int] = None  # PR number for updates
        self.repo_cloned: bool = False  # Whether repo has been cloned
        self.git_lock = threading.Lock()  # Lock for git operations (thread-safe)
        self.fixed_files_log: List[Dict] = []  # Log of fixes for PR body updates
        self.first_commit_made: bool = False  # Whether the first commit has been made (for amend logic)
        
        # Parse --fix specification to determine which fixes to apply
        fix_spec = getattr(args, 'fix', None)
        if fix_spec:
            try:
                self.enabled_fix_ids = self.parse_fix_spec(fix_spec)
                self.enabled_fix_keys = self.get_enabled_fix_keys(self.enabled_fix_ids)
            except ValueError as e:
                self.logger.error(f"Invalid --fix specification: {e}")
                raise
        else:
            # Default: all fixes enabled
            self.enabled_fix_ids = set(self.FIX_TYPES.keys())
            self.enabled_fix_keys = self.get_enabled_fix_keys(self.enabled_fix_ids)
        
        # Parse --feature specification to determine which features to apply
        feature_spec = getattr(args, 'feature', None)
        if feature_spec:
            try:
                self.enabled_feature_ids = self.parse_feature_spec(feature_spec)
                self.enabled_feature_keys = self.get_enabled_feature_keys(self.enabled_feature_ids)
            except ValueError as e:
                self.logger.error(f"Invalid --feature specification: {e}")
                raise
        else:
            # Default: no features enabled (features are opt-in)
            self.enabled_feature_ids = set()
            self.enabled_feature_keys = set()
        
        # Initialize plugin manager for fix operations
        self.plugin_manager = create_plugin_manager(llm_client=self.llm_client)
        
        # Initialize fix applicator
        self.fix_applicator = FixApplicator(self)
    
    def _setup_logging(self):
        """Configure logging to file and stderr."""
        handlers = [
            logging.FileHandler(self.log_filename, mode='w', encoding='utf-8'),
            logging.StreamHandler(sys.stderr)
        ]
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=handlers
        )
        self.logger = logging.getLogger(__name__)
    
    def _create_session(self) -> requests.Session:
        """Create requests session with retry logic."""
        session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["HEAD", "GET"]
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        session.mount("http://", adapter)
        session.mount("https://", adapter)
        session.verify = False  # Allow self-signed certs
        return session
    
    def _init_llm_client(self):
        """Initialize LLM client based on provider."""
        try:
            if self.llm_provider == "gemini":
                if not self.gemini_api_key:
                    self.logger.error("Gemini API key required when using --llm gemini")
                    return
                self.llm_client = LLMClient("gemini", self.gemini_api_key, self.language)
            elif self.llm_provider == "xai":
                if not self.xai_api_key:
                    self.logger.error("xAI API key required when using --llm xai")
                    return
                self.llm_client = LLMClient("xai", self.xai_api_key, self.language)
            self.logger.info(f"LLM client initialized: {self.llm_provider}")
        except Exception as e:
            self.logger.error(f"Failed to initialize LLM client: {e}")
    
    # =========================================================================
    # CSV Report Functions
    # =========================================================================
    
    def _initialize_csv(self):
        """Create CSV report file with headers."""
        try:
            with open(self.report_filename, 'w', newline='', encoding='utf-8') as csvfile:
                writer = csv.DictWriter(csvfile, fieldnames=[
                    'Page URL', 'Issue Category', 'Issue Location Description', 'Fix Suggestion'
                ])
                writer.writeheader()
            self.logger.info(f"Created report file: {self.report_filename}")
        except Exception as e:
            self.logger.error(f"Failed to create CSV file: {e}")
            sys.exit(1)
    
    def _write_csv_row(self, page_url: str, category: str, location: str, fix: str):
        """Append a row to the CSV report (thread-safe)."""
        try:
            with self.csv_lock:
                with open(self.report_filename, 'a', newline='', encoding='utf-8') as csvfile:
                    writer = csv.DictWriter(csvfile, fieldnames=[
                        'Page URL', 'Issue Category', 'Issue Location Description', 'Fix Suggestion'
                    ])
                    writer.writerow({
                        'Page URL': page_url,
                        'Issue Category': category,
                        'Issue Location Description': location,
                        'Fix Suggestion': fix
                    })
                self.issues_found += 1
        except Exception as e:
            self.logger.error(f"Failed to write CSV row: {e}")
    
    # =========================================================================
    # Connectivity and Validation
    # =========================================================================
    
    def validate_connectivity(self) -> bool:
        """Test connectivity to base URL with HEAD request."""
        self.logger.info(f"Testing connectivity to {self.base_url}")
        try:
            response = self.session.head(self.base_url, timeout=10)
            if response.status_code < 400:
                self.logger.info(f"Successfully connected to {self.base_url} (status: {response.status_code})")
                return True
            else:
                self.logger.error(f"Server returned status {response.status_code}")
                return False
        except requests.exceptions.SSLError as e:
            self.logger.warning(f"SSL error (trying without verification): {e}")
            try:
                response = self.session.head(self.base_url, timeout=10, verify=False)
                return response.status_code < 400
            except Exception as e2:
                self.logger.error(f"Failed to connect: {e2}")
                return False
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Failed to connect to {self.base_url}: {e}")
            return False
    
    def _validate_url_format(self, url: str) -> bool:
        """Validate URL is properly formatted HTTPS URL."""
        parsed = urllib.parse.urlparse(url)
        return parsed.scheme in ('http', 'https') and bool(parsed.netloc)
    
    # =========================================================================
    # Sitemap Generation
    # =========================================================================
    
    def _check_robots_txt(self) -> urllib.robotparser.RobotFileParser:
        """Check and parse robots.txt if available."""
        robots_url = f"{urllib.parse.urljoin(self.base_url, '/robots.txt')}"
        rp = urllib.robotparser.RobotFileParser()
        rp.set_url(robots_url)
        try:
            response = self.session.get(robots_url, timeout=10)
            if response.status_code == 200:
                rp.parse(response.text.splitlines())
                self.logger.info("robots.txt parsed successfully")
        except Exception as e:
            self.logger.warning(f"Could not parse robots.txt: {e}")
        return rp
    
    def _parse_sitemap_xml(self) -> List[str]:
        """Try to parse sitemap.xml if available."""
        parsed_base = urllib.parse.urlparse(self.base_url)
        
        # Try sitemap.xml at base URL first
        sitemap_url = f"{self.base_url}/sitemap.xml"
        self.logger.info(f"Checking for sitemap.xml at {sitemap_url}")
        
        urls = self._try_parse_sitemap(sitemap_url)
        if urls:
            return urls
        
        # Try at root domain
        if parsed_base.path and parsed_base.path != '/':
            root_url = f"{parsed_base.scheme}://{parsed_base.netloc}/sitemap.xml"
            self.logger.info(f"Checking for sitemap.xml at root: {root_url}")
            urls = self._try_parse_sitemap(root_url)
            if urls:
                # Filter to base path
                base_path = parsed_base.path.rstrip('/')
                filtered = [u for u in urls if u.startswith(self.base_url) or 
                           (base_path and base_path in urllib.parse.urlparse(u).path)]
                self.logger.info(f"Filtered to {len(filtered)} URLs under {self.base_url}")
                return filtered
        
        return []
    
    def _try_parse_sitemap(self, sitemap_url: str) -> List[str]:
        """Try to parse a sitemap from a specific URL."""
        try:
            response = self.session.get(sitemap_url, timeout=10)
            if response.status_code != 200:
                return []
            
            # Try XML parser
            for parser in ['xml', 'lxml-xml', 'lxml', 'html.parser']:
                try:
                    soup = BeautifulSoup(response.content, parser)
                    break
                except Exception:
                    continue
            else:
                return []
            
            urls = []
            base_parsed = urllib.parse.urlparse(self.base_url)
            base_path = base_parsed.path.rstrip('/')
            
            for url_tag in soup.find_all('url'):
                loc = url_tag.find('loc')
                if loc:
                    url_text = loc.get_text().strip()
                    parsed_url = urllib.parse.urlparse(url_text)
                    
                    # Map to base domain if different
                    if parsed_url.netloc != base_parsed.netloc:
                        original_path = parsed_url.path
                        if base_path:
                            base_suffix = base_path.split('/')[-1]
                            if base_suffix and f'/{base_suffix}/' in original_path:
                                idx = original_path.find(f'/{base_suffix}/')
                                new_path = original_path[idx:]
                            elif base_suffix and original_path.endswith(f'/{base_suffix}'):
                                idx = original_path.find(f'/{base_suffix}')
                                new_path = original_path[idx:]
                            else:
                                continue
                        else:
                            new_path = original_path.replace('/photon/', '/', 1) if original_path.startswith('/photon/') else original_path
                        
                        url_text = urllib.parse.urlunparse(
                            base_parsed._replace(path=new_path, query='', fragment='')
                        )
                    
                    urls.append(url_text)
            
            return urls
        except Exception as e:
            self.logger.debug(f"Could not parse sitemap at {sitemap_url}: {e}")
            return []
    
    def _is_valid_page_url(self, url: str) -> bool:
        """Check if URL is valid for analysis."""
        parsed = urllib.parse.urlparse(url)
        base_parsed = urllib.parse.urlparse(self.base_url)
        
        # Must be same domain and under base path
        if parsed.netloc != base_parsed.netloc:
            return False
        
        if not url.startswith(self.base_url):
            return False
        
        # Exclude non-HTML files
        path = parsed.path.lower()
        excluded = ('.pdf', '.zip', '.tar', '.gz', '.jpg', '.jpeg', '.png', '.gif', 
                   '.svg', '.css', '.js', '.ico', '.woff', '.woff2', '.ttf', '.eot')
        if path.endswith(excluded):
            return False
        
        return True
    
    def _crawl_page(self, url: str, depth: int, max_depth: int = 5) -> List[str]:
        """Crawl a single page and extract internal links."""
        if depth > max_depth:
            return []
        
        links = []
        try:
            response = self.session.get(url, timeout=10)
            if response.status_code >= 400:
                return []
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            for anchor in soup.find_all('a', href=True):
                href = anchor.get('href', '').strip()
                if not href or href.startswith('#') or href.startswith('javascript:'):
                    continue
                
                full_url = urllib.parse.urljoin(url, href)
                parsed = urllib.parse.urlparse(full_url)
                clean_url = urllib.parse.urlunparse(parsed._replace(fragment=''))
                
                if self._is_valid_page_url(clean_url) and clean_url not in self.visited_urls:
                    links.append(clean_url)
            
        except Exception as e:
            self.logger.error(f"Failed to crawl {url}: {e}")
        
        return links
    
    def generate_sitemap(self):
        """Generate sitemap by parsing sitemap.xml or crawling the site."""
        self.logger.info("Generating sitemap...")
        self.sitemap.clear()
        self.visited_urls.clear()
        
        # Try sitemap.xml first
        sitemap_urls = self._parse_sitemap_xml()
        if sitemap_urls:
            self.sitemap = sitemap_urls
            self.visited_urls.update(sitemap_urls)
            self.logger.info(f"Using sitemap.xml with {len(sitemap_urls)} pages")
            return
        
        # Fallback: crawl the site
        self.logger.info("sitemap.xml not found, crawling site...")
        robots = self._check_robots_txt()
        
        queue = deque([(self.base_url, 0)])
        self.visited_urls.add(self.base_url)
        
        while queue:
            url, depth = queue.popleft()
            
            if not robots.can_fetch("*", url):
                self.logger.debug(f"Skipping (robots.txt): {url}")
                continue
            
            self.sitemap.append(url)
            self.logger.info(f"Crawled [{len(self.sitemap)}]: {url}")
            
            # Parallel crawling for link extraction
            if self.num_workers > 1 and depth < 5:
                links = self._crawl_page(url, depth)
            else:
                links = self._crawl_page(url, depth)
            
            for link in links:
                if link not in self.visited_urls:
                    self.visited_urls.add(link)
                    queue.append((link, depth + 1))
            
            time.sleep(1)  # Rate limiting
        
        self.logger.info(f"Sitemap generated with {len(self.sitemap)} pages")
    
    # =========================================================================
    # Page Analysis Functions
    # =========================================================================
    
    def _get_grammar_tool(self) -> language_tool_python.LanguageTool:
        """Lazy load grammar checking tool (thread-safe)."""
        if self.grammar_tool is None:
            with self.grammar_tool_lock:
                if self.grammar_tool is None:
                    self.logger.info("Initializing grammar checker...")
                    try:
                        lang_code = self.language if self.language else 'en-US'
                        if len(lang_code) == 2:
                            lang_code = f"{lang_code}-{lang_code.upper()}"
                        self.grammar_tool = language_tool_python.LanguageTool(lang_code, remote_server=None)
                        self.logger.info(f"Grammar checker initialized for language: {lang_code}")
                    except Exception as e:
                        self.logger.error(f"Failed to initialize grammar checker: {e}")
                        raise
        return self.grammar_tool
    
    def initialize_grammar_checker(self) -> bool:
        """Initialize grammar checker and return True if successful.
        
        Returns:
            True if grammar checker initialized successfully, False otherwise.
        """
        try:
            print("Initializing grammar checker...")
            self._get_grammar_tool()
            print("[OK] Grammar checker initialized")
            return True
        except Exception as e:
            print(f"\n[ERROR] Failed to initialize grammar checker: {e}", file=sys.stderr)
            print(f"\n        This usually means Java is not installed or language-tool-python", file=sys.stderr)
            print(f"        is not properly configured.", file=sys.stderr)
            print(f"\n        Please run the following command to install required tools:", file=sys.stderr)
            print(f"        sudo python3 {TOOL_NAME} install-tools", file=sys.stderr)
            return False
    
    def _strip_code_from_text(self, text: str) -> str:
        """Remove code blocks and inline code from text before grammar checking.
        
        Removes:
        - Fenced code blocks (``` ... ```)
        - Inline code (` ... `)
        - Indented code blocks (lines starting with 4+ spaces or tab)
        
        This prevents false grammar errors on technical expressions and commands.
        """
        # Remove fenced code blocks (``` ... ```) - including with language specifier
        text = re.sub(r'```[\w]*\s*[\s\S]*?```', ' ', text)
        
        # Remove inline code (` ... `) - be careful not to match empty backticks
        text = re.sub(r'`[^`]+`', ' ', text)
        
        # Remove indented code blocks (lines starting with tab or 4+ spaces)
        # These are markdown code blocks without fences
        text = re.sub(r'^[\t].*$', ' ', text, flags=re.MULTILINE)
        text = re.sub(r'^[ ]{4,}.*$', ' ', text, flags=re.MULTILINE)
        
        # Clean up multiple spaces created by removals
        text = re.sub(r'\s+', ' ', text)
        
        return text
    
    def _check_grammar(self, page_url: str, text: str) -> List[Dict]:
        """Check text for grammar issues (thread-safe)."""
        issues = []
        try:
            tool = self._get_grammar_tool()
            
            # Strip code blocks and inline code before grammar checking
            text = self._strip_code_from_text(text)
            
            # Chunk large text
            max_chunk = 5000
            chunks = [text[i:i+max_chunk] for i in range(0, len(text), max_chunk)]
            
            for chunk in chunks:
                # Note: No lock needed - LanguageTool runs as an HTTP server
                # that handles concurrent requests internally
                matches = tool.check(chunk)
                
                # Filter false positives
                always_skip_rules = {
                    'UPPERCASE_SENTENCE_START',
                    'COMMA_PARENTHESIS_WHITESPACE',
                    'POSSESSIVE_APOSTROPHE',  # False positive for noun adjuncts (e.g., "updates repository")
                }
                
                # Rules to skip conditionally (for technical terms)
                spelling_rules = {'MORFOLOGIK_RULE_EN_US', 'MORFOLOGIK_RULE_EN_GB'}
                
                seen = set()
                for match in matches:
                    rule_id = getattr(match, 'rule_id', match.category)
                    if rule_id in always_skip_rules:
                        continue
                    
                    # For spelling rules, skip hyphenated terms and camelCase
                    if rule_id in spelling_rules:
                        error_len = getattr(match, 'error_length', getattr(match, 'errorLength', 0))
                        matched_text = chunk[match.offset:match.offset + error_len] if error_len else ''
                        
                        # Skip hyphenated terms (e.g., cloud-init, systemd-networkd)
                        if '-' in matched_text:
                            continue
                        
                        # Skip camelCase or PascalCase (e.g., NetworkManager, systemdNetworkd)
                        if any(c.isupper() for c in matched_text[1:]) and any(c.islower() for c in matched_text):
                            continue
                        
                        # Skip terms with underscores (e.g., cloud_init)
                        if '_' in matched_text:
                            continue
                    
                    suggestions = ', '.join(match.replacements[:3]) if match.replacements else 'No suggestions'
                    fix = f"[{rule_id}] {match.message}. Suggestions: {suggestions}"
                    
                    issue_key = (rule_id, fix)
                    if issue_key not in seen:
                        seen.add(issue_key)
                        
                        context = match.context
                        offset = match.offset
                        error_len = getattr(match, 'error_length', getattr(match, 'errorLength', 10))
                        start = max(0, offset - 20)
                        end = min(len(context), offset + error_len + 20)
                        location = f"...{context[start:end]}..."
                        
                        self._write_csv_row(page_url, 'grammar', location, fix)
                        issues.append({
                            'message': match.message,
                            'suggestion': suggestions,
                            'context': context,
                            'rule_id': rule_id
                        })
                        
                        if len(issues) >= 5:
                            break
                
                if len(issues) >= 5:
                    break
                
        except Exception as e:
            self.logger.error(f"Grammar check failed for {page_url}: {e}")
        
        return issues
    
    def _check_markdown_artifacts(self, page_url: str, html_content: str, text_content: str) -> List[str]:
        """Check for unrendered markdown artifacts."""
        artifacts = []
        
        for pattern in self.MARKDOWN_PATTERNS:
            matches = pattern.finditer(text_content)
            for match in matches:
                snippet = match.group(0)
                
                # Verify it's in visible text
                soup = BeautifulSoup(html_content, 'html.parser')
                for code in soup.find_all(['code', 'pre']):
                    code.decompose()
                
                clean_text = soup.get_text()
                if snippet in clean_text and len(artifacts) < 5:
                    artifacts.append(snippet)
                    self._write_csv_row(
                        page_url,
                        'markdown',
                        f"Unrendered markdown: {snippet[:100]}",
                        "Render properly or escape markdown syntax"
                    )
        
        return artifacts
    
    def _check_missing_spaces_around_backticks(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for missing spaces before or after inline code backticks.
        
        Detects issues like:
        - "Clone`the project" -> should be "Clone `the project"
        - "`command`and" -> should be "`command` and"
        - "Clone`the Photon project:" -> should be "Clone the Photon project:" (stray backtick typo)
        """
        issues = []
        
        # First, check for stray backtick typos (backtick not followed by closing backtick)
        # e.g., "Clone`the Photon project:" where backtick is a typo and should be replaced with space
        for match in self.STRAY_BACKTICK_TYPO.finditer(text_content):
            preceding_char = match.group(1)
            following_char = match.group(2)
            full_match = match.group(0)
            
            # Get context around the match
            start = max(0, match.start() - 20)
            end = min(len(text_content), match.end() + 20)
            context = text_content[start:end]
            
            location = f"Stray backtick (typo): ...{context}..."
            fix = f"Replace stray backtick with space: '{preceding_char} {following_char}' instead of '{full_match}'"
            
            self._write_csv_row(page_url, 'formatting', location, fix)
            issues.append({
                'type': 'stray_backtick_typo',
                'context': context,
                'original': full_match,
                'suggestion': f"{preceding_char} {following_char}"
            })
            
            if len(issues) >= 10:
                break
        
        # Check for missing space before backtick (e.g., "word`code`")
        for match in self.MISSING_SPACE_BEFORE_BACKTICK.finditer(text_content):
            preceding_char = match.group(1)
            code_block = match.group(2)
            full_match = match.group(0)
            
            # Get context around the match
            start = max(0, match.start() - 20)
            end = min(len(text_content), match.end() + 20)
            context = text_content[start:end]
            
            location = f"Missing space before backtick: ...{context}..."
            fix = f"Add space before backtick: '{preceding_char} {code_block}' instead of '{full_match}'"
            
            self._write_csv_row(page_url, 'formatting', location, fix)
            issues.append({
                'type': 'missing_space_before_backtick',
                'context': context,
                'original': full_match,
                'suggestion': f"{preceding_char} {code_block}"
            })
            
            if len(issues) >= 10:
                break
        
        # Check for missing space after backtick (e.g., "`code`word")
        for match in self.MISSING_SPACE_AFTER_BACKTICK.finditer(text_content):
            code_block = match.group(1)
            following_char = match.group(2)
            full_match = match.group(0)
            
            # Get context around the match
            start = max(0, match.start() - 20)
            end = min(len(text_content), match.end() + 20)
            context = text_content[start:end]
            
            location = f"Missing space after backtick: ...{context}..."
            fix = f"Add space after backtick: '{code_block} {following_char}' instead of '{full_match}'"
            
            self._write_csv_row(page_url, 'formatting', location, fix)
            issues.append({
                'type': 'missing_space_after_backtick',
                'context': context,
                'original': full_match,
                'suggestion': f"{code_block} {following_char}"
            })
            
            if len(issues) >= 10:
                break
        
        return issues
    
    def _check_backtick_errors(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for malformed backtick usage in markdown.
        
        Detects issues like:
        - Unclosed fenced code blocks (``` without closing ```)
        - Unclosed inline code (` without closing `)
        - Space after opening backtick: "` code`" should be "`code`"
        - Space before closing backtick: "`code `" should be "`code`"
        - Spaces on both sides: "` code `" should be "`code`"
        
        Args:
            page_url: URL of the page being analyzed
            text_content: Raw text/markdown content of the page
            
        Returns:
            List of backtick formatting issues found
        """
        issues = []
        
        # Check for unclosed fenced code blocks
        fenced_opens = list(re.finditer(r'^```', text_content, re.MULTILINE))
        if len(fenced_opens) % 2 != 0:
            # Odd number of ``` means at least one is unclosed
            # Find the last unclosed one
            last_open = fenced_opens[-1] if fenced_opens else None
            if last_open:
                start = max(0, last_open.start() - 20)
                end = min(len(text_content), last_open.end() + 50)
                context = text_content[start:end].replace('\n', '\\n')
                
                location = f"Unclosed fenced code block at position {last_open.start()}: ...{context}..."
                fix = "Add closing ``` to complete the fenced code block"
                
                self._write_csv_row(page_url, 'markdown', location, fix)
                issues.append({
                    'type': 'unclosed_fenced_code_block',
                    'position': last_open.start(),
                    'context': context
                })
        
        # For inline backtick checking, we need to exclude fenced code blocks first
        # Replace fenced code blocks with placeholder to avoid false positives
        text_without_fenced = re.sub(r'```[\s\S]*?```', lambda m: ' ' * len(m.group(0)), text_content)
        
        # Check for unclosed inline backticks
        # Count single backticks that are not part of ``` sequences
        single_backticks = list(re.finditer(r'(?<!`)`(?!`)', text_without_fenced))
        if len(single_backticks) % 2 != 0:
            # Odd number means at least one unclosed inline code
            # Try to find the unclosed one by checking pairs
            for i in range(0, len(single_backticks) - 1, 2):
                open_tick = single_backticks[i]
                close_tick = single_backticks[i + 1]
                
                # Check if there's a newline between them (likely unclosed)
                between = text_without_fenced[open_tick.end():close_tick.start()]
                if '\n' in between:
                    start = max(0, open_tick.start() - 10)
                    end = min(len(text_without_fenced), open_tick.end() + 40)
                    context = text_without_fenced[start:end].replace('\n', '\\n')
                    
                    location = f"Possibly unclosed inline code at position {open_tick.start()}: ...{context}..."
                    fix = "Add closing ` to complete the inline code or remove the opening `"
                    
                    self._write_csv_row(page_url, 'markdown', location, fix)
                    issues.append({
                        'type': 'unclosed_inline_code',
                        'position': open_tick.start(),
                        'context': context
                    })
                    break
            
            # Check the last unpaired backtick
            if len(single_backticks) % 2 != 0:
                last_tick = single_backticks[-1]
                start = max(0, last_tick.start() - 10)
                end = min(len(text_without_fenced), last_tick.end() + 40)
                context = text_without_fenced[start:end].replace('\n', '\\n')
                
                location = f"Unclosed inline code backtick at position {last_tick.start()}: ...{context}..."
                fix = "Add closing ` to complete the inline code or remove the backtick"
                
                self._write_csv_row(page_url, 'markdown', location, fix)
                issues.append({
                    'type': 'unclosed_inline_code',
                    'position': last_tick.start(),
                    'context': context
                })
        
        # Check for spaces after opening backtick: "` code`"
        for match in self.INLINE_CODE_SPACE_AFTER_OPEN.finditer(text_without_fenced):
            full_match = match.group(0)
            content = match.group(1)
            
            # Skip if this looks like it might be intentional (very long content)
            if len(content) > 100:
                continue
            
            start = max(0, match.start() - 15)
            end = min(len(text_without_fenced), match.end() + 15)
            context = text_without_fenced[start:end]
            
            location = f"Space after opening backtick: '{full_match}'"
            fix = f"Remove space after opening backtick: `{content.strip()}` instead of {full_match}"
            
            self._write_csv_row(page_url, 'markdown', location, fix)
            issues.append({
                'type': 'space_after_opening_backtick',
                'original': full_match,
                'context': context,
                'suggestion': f"`{content.strip()}`"
            })
            
            if len(issues) >= 20:
                break
        
        # Check for spaces before closing backtick: "`code `"
        for match in self.INLINE_CODE_SPACE_BEFORE_CLOSE.finditer(text_without_fenced):
            full_match = match.group(0)
            content = match.group(1)
            
            # Skip if already caught by SPACE_AFTER_OPEN pattern
            if full_match.startswith('` '):
                continue
            
            # Skip if this looks like it might be intentional (very long content)
            if len(content) > 100:
                continue
            
            start = max(0, match.start() - 15)
            end = min(len(text_without_fenced), match.end() + 15)
            context = text_without_fenced[start:end]
            
            location = f"Space before closing backtick: '{full_match}'"
            fix = f"Remove space before closing backtick: `{content.strip()}` instead of {full_match}"
            
            self._write_csv_row(page_url, 'markdown', location, fix)
            issues.append({
                'type': 'space_before_closing_backtick',
                'original': full_match,
                'context': context,
                'suggestion': f"`{content.strip()}`"
            })
            
            if len(issues) >= 20:
                break
        
        return issues
    
    def _check_malformed_code_blocks(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for malformed code blocks in markdown.
        
        Detects issues like:
        - Single backtick followed by content ending with triple backticks: `command```
          This should be a proper fenced code block: ```\\ncommand\\n```
        - Consecutive lines of inline code that should be a fenced code block:
          `command1`
          `command2`
          Should be:
          ```
          command1
          command2
          ```
        
        Args:
            page_url: URL of the page being analyzed
            text_content: Raw text/markdown content of the page
            
        Returns:
            List of malformed code block issues found
        """
        issues = []
        
        # Check for single backtick + content + triple backticks pattern
        # e.g., `git clone https://github.com/vmware/photon.git```
        for match in self.MALFORMED_CODE_BLOCK_SINGLE_TRIPLE.finditer(text_content):
            content = match.group(1)
            full_match = match.group(0)
            
            start = max(0, match.start() - 20)
            end = min(len(text_content), match.end() + 20)
            context = text_content[start:end].replace('\n', '\\n')
            
            location = f"Malformed code block (1 backtick start, 3 backtick end): ...{context}..."
            fix = f"Convert to fenced code block: ```\\n{content}\\n```"
            
            self._write_csv_row(page_url, 'malformed_code_block', location, fix)
            issues.append({
                'type': 'single_triple_backtick',
                'content': content,
                'original': full_match,
                'context': context
            })
            
            if len(issues) >= 20:
                break
        
        # Check for consecutive inline code lines that should be fenced
        # Look for patterns like:
        #   `command1`
        #   `command2`
        for match in self.CONSECUTIVE_INLINE_COMMANDS.finditer(text_content):
            indent = match.group(1)
            cmd1 = match.group(2)
            cmd2 = match.group(3)
            full_match = match.group(0)
            
            start = max(0, match.start() - 10)
            end = min(len(text_content), match.end() + 10)
            context = text_content[start:end].replace('\n', '\\n')
            
            location = f"Consecutive inline commands should be fenced code block: ...{context}..."
            fix = f"Convert to fenced code block: ```bash\\n{cmd1}\\n{cmd2}\\n```"
            
            self._write_csv_row(page_url, 'malformed_code_block', location, fix)
            issues.append({
                'type': 'consecutive_inline_commands',
                'commands': [cmd1, cmd2],
                'indent': indent,
                'original': full_match,
                'context': context
            })
            
            if len(issues) >= 20:
                break
        
        # Check for stray backticks inside fenced code blocks
        # Look for patterns like: ```bash\ncmd`\n```
        fenced_pattern = re.compile(r'```[\w]*\n([\s\S]*?)```')
        for match in fenced_pattern.finditer(text_content):
            block_content = match.group(1)
            for line_num, line in enumerate(block_content.split('\n')):
                # Check for stray trailing backtick
                if line.endswith('`') and not line.endswith('```'):
                    start = max(0, match.start())
                    end = min(len(text_content), match.end())
                    context = text_content[start:end][:100].replace('\n', '\\n')
                    
                    location = f"Stray backtick in code block line: {line[:50]}..."
                    fix = "Remove trailing backtick from code block line"
                    
                    self._write_csv_row(page_url, 'malformed_code_block', location, fix)
                    issues.append({
                        'type': 'stray_backtick_in_block',
                        'line': line,
                        'line_num': line_num,
                        'context': context
                    })
                    
                    if len(issues) >= 20:
                        break
                
                # Check for stray leading backtick
                stripped = line.lstrip()
                if stripped.startswith('`') and not stripped.startswith('```'):
                    start = max(0, match.start())
                    end = min(len(text_content), match.end())
                    context = text_content[start:end][:100].replace('\n', '\\n')
                    
                    location = f"Stray leading backtick in code block line: {line[:50]}..."
                    fix = "Remove leading backtick from code block line"
                    
                    self._write_csv_row(page_url, 'malformed_code_block', location, fix)
                    issues.append({
                        'type': 'stray_backtick_in_block',
                        'line': line,
                        'line_num': line_num,
                        'context': context
                    })
                    
                    if len(issues) >= 20:
                        break
            
            if len(issues) >= 20:
                break
        
        # Check for plain text commands that should be in code blocks
        # These are commands appearing as plain text after list items without backticks
        # First, exclude content already inside fenced code blocks
        text_without_fenced = re.sub(r'```[\s\S]*?```', lambda m: '\n' * m.group(0).count('\n'), text_content)
        
        for match in self.PLAIN_TEXT_COMMAND_PATTERN.finditer(text_without_fenced):
            indent = match.group(1)
            command = match.group(2)
            
            start = max(0, match.start() - 20)
            end = min(len(text_without_fenced), match.end() + 20)
            context = text_without_fenced[start:end].replace('\n', '\\n')
            
            location = f"Plain text command should be in code block: ...{context}..."
            fix = f"Wrap in code block: ```\\n{command}\\n```"
            
            self._write_csv_row(page_url, 'malformed_code_block', location, fix)
            issues.append({
                'type': 'plain_text_command',
                'command': command,
                'indent': indent,
                'context': context
            })
            
            if len(issues) >= 20:
                break
        
        # Check for triple backticks used as inline code delimiters (no newlines)
        # e.g., ```cloud-init``` should be `cloud-init`
        for match in self.TRIPLE_BACKTICK_INLINE_PATTERN.finditer(text_content):
            code_content = match.group(1)
            full_match = match.group(0)
            
            start = max(0, match.start() - 10)
            end = min(len(text_content), match.end() + 30)
            context = text_content[start:end].replace('\n', '\\n')
            
            location = f"Triple backticks used as inline code (should use single backticks): ...{context}..."
            fix = f"Convert to single backticks: `{code_content}`"
            
            self._write_csv_row(page_url, 'malformed_code_block', location, fix)
            issues.append({
                'type': 'triple_backtick_inline',
                'code_content': code_content,
                'context': context
            })
            
            if len(issues) >= 20:
                break
        
        # Check for fenced code blocks incorrectly used for inline code within sentences
        # e.g., ```bash\ncloud-init\n``` is a multi-distribution... should be `cloud-init` is a...
        for match in self.FENCED_INLINE_CODE_PATTERN.finditer(text_content):
            code_content = match.group(1)
            continuation = match.group(2)
            full_match = match.group(0)
            
            start = max(0, match.start() - 10)
            end = min(len(text_content), match.end() + 30)
            context = text_content[start:end].replace('\n', '\\n')
            
            location = f"Fenced code block should be inline code (part of sentence): ...{context}..."
            fix = f"Convert to inline code: `{code_content}`{continuation}"
            
            self._write_csv_row(page_url, 'malformed_code_block', location, fix)
            issues.append({
                'type': 'fenced_should_be_inline',
                'code_content': code_content,
                'continuation': continuation,
                'context': context
            })
            
            if len(issues) >= 20:
                break
        
        return issues
    
    def _check_list_indentation_issues(self, page_url: str, html_content: str) -> List[Dict]:
        """Check for indentation issues in numbered/bulleted lists.
        
        Detects issues like:
        - Inconsistent indentation in list items
        - List items that don't align properly
        - Nested content not properly indented under list items
        """
        issues = []
        soup = BeautifulSoup(html_content, 'html.parser')
        
        # Check ordered lists (ol) for indentation issues
        for ol in soup.find_all('ol'):
            list_items = ol.find_all('li', recursive=False)
            
            for i, li in enumerate(list_items):
                # Check if list item has nested content that might have indentation issues
                nested_elements = li.find_all(['p', 'pre', 'code', 'ul', 'ol'], recursive=True)
                
                # Get text content of the list item
                li_text = li.get_text(separator=' ', strip=True)
                
                # Check for common indentation-related issues in the HTML structure
                # Look for text nodes that might indicate improper markdown rendering
                for child in li.children:
                    if hasattr(child, 'name'):
                        # Check if there's a paragraph immediately after the list marker
                        # that should be on the same line
                        if child.name == 'p':
                            prev_text = child.previous_sibling
                            if prev_text and isinstance(prev_text, str) and prev_text.strip():
                                # There's text before the paragraph - might be indentation issue
                                context = f"List item {i+1}: {li_text[:80]}..."
                                location = f"Possible indentation issue in list item: {context}"
                                fix = "Ensure consistent indentation for list item content"
                                
                                self._write_csv_row(page_url, 'indentation', location, fix)
                                issues.append({
                                    'type': 'list_indentation',
                                    'item_number': i + 1,
                                    'context': context
                                })
                
                # Check for code blocks within list items that might not be properly indented
                code_blocks = li.find_all('pre')
                for code_block in code_blocks:
                    # Check if code block appears to be misaligned
                    parent_p = code_block.find_parent('p')
                    if parent_p and parent_p.parent == li:
                        # Code block inside paragraph inside list item - potential issue
                        code_text = code_block.get_text()[:50]
                        location = f"Code block in list item {i+1} may have indentation issues: {code_text}..."
                        fix = "Ensure code block is properly indented (4 spaces or 1 tab) under the list item"
                        
                        self._write_csv_row(page_url, 'indentation', location, fix)
                        issues.append({
                            'type': 'code_block_indentation',
                            'item_number': i + 1,
                            'context': code_text
                        })
            
            if len(issues) >= 10:
                break
        
        # Also check for unordered lists
        for ul in soup.find_all('ul'):
            list_items = ul.find_all('li', recursive=False)
            
            for i, li in enumerate(list_items):
                # Check for nested content indentation issues
                nested_pre = li.find_all('pre', recursive=True)
                for pre in nested_pre:
                    # Check if there's text content after the code block that might indicate
                    # the code block isn't properly nested
                    next_sibling = pre.next_sibling
                    if next_sibling and isinstance(next_sibling, str) and next_sibling.strip():
                        text_preview = next_sibling.strip()[:50]
                        location = f"Text after code block in list item may indicate indentation issue: {text_preview}..."
                        fix = "Ensure proper indentation for content following code blocks in list items"
                        
                        self._write_csv_row(page_url, 'indentation', location, fix)
                        issues.append({
                            'type': 'post_code_indentation',
                            'context': text_preview
                        })
            
            if len(issues) >= 10:
                break
        
        return issues
    
    def _check_shell_prompt_in_code_blocks(self, page_url: str, soup: BeautifulSoup) -> List[Dict]:
        """Check for shell prompt prefixes in code blocks that should be removed.
        
        Detects issues like:
        - "$ command" where "$ " is a shell prompt prefix
        - "# command" where "# " is a root prompt prefix
        - "user@host$ command" where the prompt should be removed
        
        These prompts make it harder for users to copy-paste commands.
        """
        issues = []
        
        # Find all code blocks (pre, code elements)
        code_blocks = soup.find_all(['pre', 'code'])
        
        for code_block in code_blocks:
            # Get the text content of the code block
            code_text = code_block.get_text()
            
            if not code_text or len(code_text.strip()) == 0:
                continue
            
            # Check each line in the code block
            lines = code_text.split('\n')
            for line_num, line in enumerate(lines):
                if not line.strip():
                    continue
                
                # Check against each shell prompt pattern
                for pattern in self.SHELL_PROMPT_PATTERNS:
                    match = pattern.match(line)
                    if match:
                        # Pattern groups: (1) leading whitespace, (2) prompt, (3) command
                        leading_whitespace = match.group(1)
                        prompt_prefix = match.group(2)
                        actual_command = match.group(3)
                        
                        # Create a context snippet
                        context = line[:80] if len(line) > 80 else line
                        
                        location = f"Shell prompt in code block: '{context}'"
                        fix = f"Remove shell prompt prefix '{prompt_prefix.strip()}' - command should be: '{leading_whitespace}{actual_command}'"
                        
                        self._write_csv_row(page_url, 'shell_prompt', location, fix)
                        issues.append({
                            'type': 'shell_prompt_prefix',
                            'line_number': line_num + 1,
                            'prompt': prompt_prefix,
                            'command': actual_command,
                            'original_line': line
                        })
                        
                        # Only report first match per line
                        break
                
                if len(issues) >= 20:
                    break
            
            if len(issues) >= 20:
                break
        
        return issues
    
    def _check_mixed_command_output_in_code_blocks(self, page_url: str, soup: BeautifulSoup) -> List[Dict]:
        """Check for code blocks that mix console commands with their output.
        
        Detects code blocks where a command (e.g., "sudo cat /etc/file") is followed by
        its output in the same code block. These should be separated into:
        - A command code block (for copy-button functionality)
        - An output code block (for display only)
        
        Heuristics used to detect mixed content:
        1. First line looks like a command (starts with sudo, cat, ls, etc.)
        2. Subsequent lines look like output (config format, JSON, multi-line text)
        3. No shell prompts on output lines
        """
        issues = []
        
        # Common command prefixes that indicate a line is a command
        COMMAND_PATTERNS = [
            re.compile(r'^(sudo\s+)'),           # sudo commands
            re.compile(r'^(cat\s+)'),            # cat file
            re.compile(r'^(ls\s+|ls$)'),         # ls commands
            re.compile(r'^(grep\s+)'),           # grep commands
            re.compile(r'^(find\s+)'),           # find commands
            re.compile(r'^(systemctl\s+)'),      # systemctl commands
            re.compile(r'^(journalctl\s+)'),     # journalctl commands
            re.compile(r'^(docker\s+)'),         # docker commands
            re.compile(r'^(kubectl\s+)'),        # kubectl commands
            re.compile(r'^(tdnf\s+)'),           # tdnf commands
            re.compile(r'^(rpm\s+)'),            # rpm commands
            re.compile(r'^(curl\s+)'),           # curl commands
            re.compile(r'^(wget\s+)'),           # wget commands
            re.compile(r'^(echo\s+)'),           # echo commands
            re.compile(r'^(head\s+|tail\s+)'),   # head/tail commands
            re.compile(r'^(awk\s+|sed\s+)'),     # awk/sed commands
            re.compile(r'^(chmod\s+|chown\s+)'), # permission commands
            re.compile(r'^(mkdir\s+|rm\s+)'),    # file operation commands
            re.compile(r'^(cp\s+|mv\s+)'),       # copy/move commands
            re.compile(r'^(ip\s+|ifconfig\s+)'), # network commands
            re.compile(r'^(nmctl\s+)'),          # network manager commands
            re.compile(r'^(hostnamectl\s+)'),    # hostname commands
            re.compile(r'^(timedatectl\s+)'),    # time/date commands
            re.compile(r'^(localectl\s+)'),      # locale commands
        ]
        
        # Patterns that indicate output (not commands)
        OUTPUT_PATTERNS = [
            re.compile(r'^\[[\w\s]+\]'),              # Section headers like [System], [Network]
            re.compile(r'^[\w_]+='),                  # Key=value config lines
            re.compile(r'^\s*"[\w_]+":\s*'),          # JSON key-value
            re.compile(r'^\s*{\s*$'),                 # JSON opening brace
            re.compile(r'^\s*}\s*$'),                 # JSON closing brace
            re.compile(r'^\s+\w+:\s+\w+'),            # YAML-like key: value with leading space
            re.compile(r'^[A-Z][a-z]+:\s+'),          # Capitalized labels like "Name:", "Status:"
            re.compile(r'^\s{2,}'),                   # Lines with significant indentation (likely output)
            re.compile(r'^─+|^━+|^═+'),               # Box drawing characters (table borders)
            re.compile(r'^\s*\d+\.\d+\.\d+'),         # Version numbers
            re.compile(r'^total\s+\d+'),              # ls output "total N"
            re.compile(r'^[drwx-]{10}'),              # ls -l output (file permissions)
        ]
        
        # Find all code blocks (pre elements, potentially containing code elements)
        code_blocks = soup.find_all('pre')
        
        for code_block in code_blocks:
            code_text = code_block.get_text()
            
            if not code_text or len(code_text.strip()) == 0:
                continue
            
            lines = code_text.strip().split('\n')
            
            if len(lines) < 2:
                continue  # Need at least 2 lines to have command + output
            
            # Check if first line looks like a command
            first_line = lines[0].strip()
            
            # Skip if first line is empty or looks like output
            if not first_line:
                continue
            
            # Remove shell prompt prefix if present for analysis
            clean_first_line = first_line
            for prompt_pattern in self.SHELL_PROMPT_PATTERNS:
                match = prompt_pattern.match(first_line)
                if match:
                    # Pattern groups: (1) leading whitespace, (2) prompt, (3) command
                    clean_first_line = match.group(3)
                    break
            
            # Check if first line matches a command pattern
            is_command = False
            for cmd_pattern in COMMAND_PATTERNS:
                if cmd_pattern.match(clean_first_line):
                    is_command = True
                    break
            
            if not is_command:
                continue
            
            # Now check if remaining lines look like output
            output_line_count = 0
            command_line_count = 1  # First line is a command
            
            for line in lines[1:]:
                line_stripped = line.strip()
                if not line_stripped:
                    continue
                
                # Check if this line looks like output
                is_output = False
                for output_pattern in OUTPUT_PATTERNS:
                    if output_pattern.match(line):
                        is_output = True
                        output_line_count += 1
                        break
                
                if not is_output:
                    # Check if it's another command
                    is_another_command = False
                    for cmd_pattern in COMMAND_PATTERNS:
                        if cmd_pattern.match(line_stripped):
                            is_another_command = True
                            command_line_count += 1
                            break
                    
                    # Check for shell prompts (indicating another command)
                    if not is_another_command:
                        for prompt_pattern in self.SHELL_PROMPT_PATTERNS:
                            if prompt_pattern.match(line):
                                is_another_command = True
                                command_line_count += 1
                                break
                    
                    # If not a command, treat as potential output
                    if not is_another_command:
                        output_line_count += 1
            
            # Report issue if we found significant output mixed with command
            if output_line_count >= 2 and command_line_count <= 2:
                # Get a preview of the content
                command_preview = clean_first_line[:60]
                if len(clean_first_line) > 60:
                    command_preview += "..."
                
                output_preview = lines[1].strip()[:60] if len(lines) > 1 else ""
                if len(lines) > 1 and len(lines[1].strip()) > 60:
                    output_preview += "..."
                
                location = f"Mixed command and output in code block. Command: '{command_preview}', Output starts: '{output_preview}'"
                fix = "Separate into two code blocks: one for the command (copyable) and one for the output (display only)"
                
                self._write_csv_row(page_url, 'mixed_command_output', location, fix)
                issues.append({
                    'type': 'mixed_command_output',
                    'command': clean_first_line,
                    'output_lines': output_line_count,
                    'total_lines': len(lines)
                })
                
                if len(issues) >= 10:
                    break
        
        return issues
    
    def _check_deprecated_vmware_urls(self, page_url: str, soup: BeautifulSoup) -> List[Dict]:
        """Check for deprecated packages.vmware.com URLs that should be updated.
        
        These URLs should be replaced with packages.broadcom.com.
        Also checks for deprecated VDDK download URL.
        """
        issues = []
        
        # Check all anchor tags for deprecated URLs
        for anchor in soup.find_all('a', href=True):
            href = anchor.get('href', '')
            link_text = anchor.get_text().strip()[:50]
            
            # Check for deprecated packages.vmware.com URLs
            if self.DEPRECATED_VMWARE_URL.match(href):
                location = f"Deprecated VMware URL: {href}"
                fix = f"Replace with {self.VMWARE_URL_REPLACEMENT} - Link text: '{link_text}'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_vmware_url',
                    'url': href,
                    'link_text': link_text
                })
            
            # Check for deprecated VDDK URLs (multiple sources)
            elif href in self.DEPRECATED_VDDK_URLS:
                location = f"Deprecated VDDK URL: {href}"
                fix = f"Replace with {self.VDDK_URL_REPLACEMENT} - Link text: '{link_text}'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_vddk_url',
                    'url': href,
                    'link_text': link_text
                })
            
            # Check for deprecated OVFTOOL URL
            elif href == self.DEPRECATED_OVFTOOL_URL:
                location = f"Deprecated OVFTOOL URL: {href}"
                fix = f"Replace with {self.OVFTOOL_URL_REPLACEMENT} - Link text: '{link_text}'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_ovftool_url',
                    'url': href,
                    'link_text': link_text
                })
            
            # Check for deprecated AWS EC2 CLI URL
            elif href in self.DEPRECATED_AWS_EC2_CLI_URLS:
                location = f"Deprecated AWS EC2 CLI URL: {href}"
                fix = f"Replace with {self.AWS_EC2_CLI_URL_REPLACEMENT} - Link text: '{link_text}'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_aws_ec2_cli_url',
                    'url': href,
                    'link_text': link_text
                })
            
            # Check for deprecated CloudFoundry bosh-stemcell URL
            elif href == self.DEPRECATED_BOSH_STEMCELL_URL:
                location = f"Deprecated bosh-stemcell URL: {href}"
                fix = f"Replace with {self.BOSH_STEMCELL_URL_REPLACEMENT} - Link text: '{link_text}'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_bosh_stemcell_url',
                    'url': href,
                    'link_text': link_text
                })
        
        # Also check text content for URLs that might not be hyperlinks
        text_content = soup.get_text()
        for match in self.DEPRECATED_VMWARE_URL.finditer(text_content):
            url_found = match.group(0)
            # Avoid duplicates from anchor check
            if not any(i['url'] == url_found for i in issues):
                location = f"Deprecated VMware URL in text: {url_found}"
                fix = f"Replace with {self.VMWARE_URL_REPLACEMENT}"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_vmware_url',
                    'url': url_found,
                    'link_text': ''
                })
        
        # Check for deprecated VDDK URLs in text content
        for vddk_url in self.DEPRECATED_VDDK_URLS:
            if vddk_url in text_content:
                if not any(i['url'] == vddk_url for i in issues):
                    location = f"Deprecated VDDK URL in text: {vddk_url}"
                    fix = f"Replace with {self.VDDK_URL_REPLACEMENT}"
                    
                    self._write_csv_row(page_url, 'deprecated_url', location, fix)
                    issues.append({
                        'type': 'deprecated_vddk_url',
                        'url': vddk_url,
                        'link_text': ''
                    })
        
        # Check for deprecated AWS EC2 CLI URL in text content
        for aws_url in self.DEPRECATED_AWS_EC2_CLI_URLS:
            if aws_url in text_content:
                if not any(i['url'] == aws_url for i in issues):
                    location = f"Deprecated AWS EC2 CLI URL in text: {aws_url}"
                    fix = f"Replace with {self.AWS_EC2_CLI_URL_REPLACEMENT}"
                    
                    self._write_csv_row(page_url, 'deprecated_url', location, fix)
                    issues.append({
                        'type': 'deprecated_aws_ec2_cli_url',
                        'url': aws_url,
                        'link_text': ''
                    })
        
        # Check for deprecated OVFTOOL URL in text content
        if self.DEPRECATED_OVFTOOL_URL in text_content:
            if not any(i['url'] == self.DEPRECATED_OVFTOOL_URL for i in issues):
                location = f"Deprecated OVFTOOL URL in text: {self.DEPRECATED_OVFTOOL_URL}"
                fix = f"Replace with {self.OVFTOOL_URL_REPLACEMENT}"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_ovftool_url',
                    'url': self.DEPRECATED_OVFTOOL_URL,
                    'link_text': ''
                })
        
        # Check for deprecated CloudFoundry bosh-stemcell URL in text content
        if self.DEPRECATED_BOSH_STEMCELL_URL in text_content:
            if not any(i['url'] == self.DEPRECATED_BOSH_STEMCELL_URL for i in issues):
                location = f"Deprecated bosh-stemcell URL in text: {self.DEPRECATED_BOSH_STEMCELL_URL}"
                fix = f"Replace with {self.BOSH_STEMCELL_URL_REPLACEMENT}"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_bosh_stemcell_url',
                    'url': self.DEPRECATED_BOSH_STEMCELL_URL,
                    'link_text': ''
                })
        
        # Check for deprecated Bintray URLs (service discontinued in 2021)
        for bintray_match in self.DEPRECATED_BINTRAY_URL_PATTERN.finditer(text_content):
            bintray_url = bintray_match.group(0)
            if not any(i.get('url') == bintray_url for i in issues):
                location = f"Deprecated Bintray URL in text: {bintray_url}"
                fix = f"Replace with {self.BINTRAY_URL_REPLACEMENT}"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_bintray_url',
                    'url': bintray_url,
                    'link_text': ''
                })
        
        # Check for plain "Bintray" word occurrences (even without URLs)
        # This ensures the word is replaced with "Download" even in prose text
        if 'Bintray' in text_content:
            # Only add issue if not already covered by a Bintray URL detection
            if not any(i.get('type') == 'deprecated_bintray_url' for i in issues):
                location = "Deprecated 'Bintray' reference in text"
                fix = "Replace 'Bintray' with 'Download'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_bintray_word',
                    'url': '',
                    'link_text': 'Bintray'
                })
        
        return issues
    
    def _check_vmware_spelling(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for incorrect VMware spelling.
        
        VMware must be spelled with capital V and M: "VMware"
        Incorrect: vmware, Vmware, VMWare, VMWARE, etc.
        
        Excludes:
        - URLs containing 'vmware' (e.g., github.com/vmware, packages.vmware.com)
        - Domain-like patterns (e.g., packages.vmware.com without https://)
        - File paths (e.g., /var/log/VMware-imc/, /etc/pki/rpm-gpg/VMware-RPM-GPG-KEY)
        - Email addresses (e.g., linux-packages@VMware.com)
        - Broken email addresses (e.g., linux-packages@vmware.     com)
        - Console commands/code blocks containing vmware
        """
        issues = []
        
        # Pattern to detect if match is within a URL (with or without protocol)
        url_pattern = re.compile(r'https?://[^\s<>"\']+|www\.[^\s<>"\']+|[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.(com|org|net|io|gov|edu)[^\s<>"\']*')
        
        # Pattern to detect file paths (Unix-style)
        file_path_pattern = re.compile(r'(?:/[\w.-]+)+/?')
        
        # Pattern to detect email addresses (normal)
        email_pattern = re.compile(r'[\w.+-]+@[\w.-]+\.\w+', re.IGNORECASE)
        
        # Pattern to detect broken email addresses (domain split with whitespace)
        # e.g., "linux-packages@vmware.                        com"
        broken_email_pattern = re.compile(r'[\w.+-]+@[\w.-]+\.\s+\w{2,6}', re.IGNORECASE)
        
        for match in self.VMWARE_SPELLING_PATTERN.finditer(text_content):
            incorrect_spelling = match.group(0)
            match_start = match.start()
            match_end = match.end()
            
            # Get extended context to check for URL, domain, file path, or email patterns
            context_start = max(0, match_start - 100)
            context_end = min(len(text_content), match_end + 50)
            context_region = text_content[context_start:context_end]
            
            # Check if this match is within a URL or domain-like pattern
            is_in_url = False
            for url_match in url_pattern.finditer(context_region):
                url_start_abs = context_start + url_match.start()
                url_end_abs = context_start + url_match.end()
                if url_start_abs <= match_start and match_end <= url_end_abs:
                    is_in_url = True
                    break
            
            if is_in_url:
                continue  # Skip VMware spelling in URLs/domains
            
            # Check if match is within a file path
            is_in_file_path = False
            for path_match in file_path_pattern.finditer(context_region):
                path_start_abs = context_start + path_match.start()
                path_end_abs = context_start + path_match.end()
                if path_start_abs <= match_start and match_end <= path_end_abs:
                    is_in_file_path = True
                    break
            
            if is_in_file_path:
                continue  # Skip VMware spelling in file paths
            
            # Check if match is within an email address (normal)
            is_in_email = False
            for email_match in email_pattern.finditer(context_region):
                email_start_abs = context_start + email_match.start()
                email_end_abs = context_start + email_match.end()
                if email_start_abs <= match_start and match_end <= email_end_abs:
                    is_in_email = True
                    break
            
            if is_in_email:
                continue  # Skip VMware spelling in email addresses
            
            # Check if match is within a broken email address (with whitespace in domain)
            is_in_broken_email = False
            for broken_match in broken_email_pattern.finditer(context_region):
                broken_start_abs = context_start + broken_match.start()
                broken_end_abs = context_start + broken_match.end()
                if broken_start_abs <= match_start and match_end <= broken_end_abs:
                    is_in_broken_email = True
                    break
            
            if is_in_broken_email:
                continue  # Skip VMware spelling in broken email addresses
            
            # Check if match is in a domain-like context (e.g., "packages.vmware.com")
            # Look for pattern like "word.vmware.word"
            local_context = text_content[max(0, match_start - 20):min(len(text_content), match_end + 20)]
            if re.search(r'\w+\.' + re.escape(incorrect_spelling) + r'\.\w+', local_context, re.IGNORECASE):
                continue  # Skip domain-like patterns
            
            # Also check for broken domain pattern (word.vmware.  whitespace  word)
            if re.search(r'\w+\.' + re.escape(incorrect_spelling) + r'\.\s+\w+', local_context, re.IGNORECASE):
                continue  # Skip broken domain-like patterns (will be fixed by broken email fix)
            
            # Get display context around the match
            start = max(0, match_start - 30)
            end = min(len(text_content), match_end + 30)
            context = text_content[start:end]
            
            location = f"Incorrect VMware spelling: '{incorrect_spelling}' in ...{context}..."
            fix = f"Change '{incorrect_spelling}' to 'VMware'"
            
            self._write_csv_row(page_url, 'spelling', location, fix)
            issues.append({
                'type': 'vmware_spelling',
                'incorrect': incorrect_spelling,
                'context': context
            })
            
            if len(issues) >= 10:
                break
        
        return issues
    
    def _check_broken_email_addresses(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for broken email addresses where domain is split with whitespace.
        
        Detects issues like:
        - "linux-packages@vmware.                        com" should be "linux-packages@vmware.com"
        - "user@example.   org" should be "user@example.org"
        
        This commonly happens in console output where long lines are wrapped.
        """
        issues = []
        
        for match in self.BROKEN_EMAIL_PATTERN.finditer(text_content):
            email_prefix = match.group(1)  # e.g., "linux-packages@vmware."
            whitespace = match.group(2)    # The whitespace/newlines
            tld = match.group(3)           # e.g., "com"
            
            broken_email = match.group(0)
            fixed_email = f"{email_prefix}{tld}"
            
            # Get context around the match
            start = max(0, match.start() - 20)
            end = min(len(text_content), match.end() + 20)
            context = text_content[start:end].replace('\n', '\\n')
            
            location = f"Broken email address: '{email_prefix}[whitespace]{tld}' in ...{context}..."
            fix = f"Remove whitespace: '{fixed_email}'"
            
            self._write_csv_row(page_url, 'broken_email', location, fix)
            issues.append({
                'type': 'broken_email',
                'original': broken_email,
                'fixed': fixed_email,
                'context': context
            })
            
            if len(issues) >= 10:
                break
        
        return issues
    
    def _check_markdown_header_spacing(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for markdown headers missing space after hash symbols.
        
        Detects issues like:
        - "####Title" should be "#### Title"
        - "###Subtitle" should be "### Subtitle"
        - "##Section" should be "## Section"
        """
        issues = []
        
        for match in self.MARKDOWN_HEADER_NO_SPACE.finditer(text_content):
            hashes = match.group(1)
            title = match.group(2)
            original = match.group(0)
            
            # Get context around the match
            start = max(0, match.start() - 10)
            end = min(len(text_content), match.end() + 20)
            context = text_content[start:end]
            
            location = f"Markdown header missing space: '{original}'"
            fix = f"Add space after '{hashes}': '{hashes} {title}'"
            
            self._write_csv_row(page_url, 'markdown', location, fix)
            issues.append({
                'type': 'markdown_header_no_space',
                'original': original,
                'hashes': hashes,
                'title': title,
                'suggestion': f"{hashes} {title}"
            })
            
            if len(issues) >= 10:
                break
        
        return issues
    
    def _check_html_comments(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for HTML comments (<!-- ... -->) that should be uncommented.
        
        Detects HTML comment blocks in markdown content that may contain
        valid content that was commented out and should be made visible.
        
        Note: This only checks content outside of fenced code blocks to avoid
        false positives on code examples that legitimately show HTML comments.
        """
        issues = []
        
        # First, remove fenced code blocks to avoid false positives
        # Replace code blocks with placeholder to preserve positions
        code_block_pattern = re.compile(r'```[\s\S]*?```')
        text_without_code = code_block_pattern.sub(lambda m: ' ' * len(m.group(0)), text_content)
        
        for match in self.HTML_COMMENT_PATTERN.finditer(text_without_code):
            comment_content = match.group(1).strip()
            full_match = match.group(0)
            
            # Skip empty comments
            if not comment_content:
                continue
            
            # Get context around the match
            start = max(0, match.start() - 10)
            end = min(len(text_without_code), match.end() + 10)
            
            # Create a preview of the comment content (truncated)
            preview = comment_content[:80].replace('\n', '\\n')
            if len(comment_content) > 80:
                preview += "..."
            
            location = f"HTML comment found: <!-- {preview} -->"
            fix = "Remove HTML comment markers to make content visible, or delete if obsolete"
            
            self._write_csv_row(page_url, 'html_comment', location, fix)
            issues.append({
                'type': 'html_comment',
                'content': comment_content,
                'full_match': full_match,
                'start': match.start(),
                'end': match.end()
            })
            
            if len(issues) >= 20:
                break
        
        return issues
    
    def _detect_heading_level(self, line: str) -> int:
        """Detect markdown heading level from a line.
        
        Returns the heading level (1-6) or 0 if not a heading.
        Only handles ATX-style headings (# ## ### etc.).
        """
        match = re.match(r'^(#{1,6})\s+', line)
        if match:
            return len(match.group(1))
        return 0
    
    def _analyze_heading_hierarchy(self, content: str) -> List[Dict]:
        """Analyze markdown content for heading hierarchy violations.
        
        Detects issues like:
        - Skipped heading levels (e.g., H2 -> H4 without H3)
        
        NOTE: Does NOT flag "first heading is not H1" as an issue. In Hugo/documentation
        systems, the page title (H1) often comes from front matter, so content headings
        legitimately start at H2 or lower.
        
        Returns list of issues found with line numbers and suggestions.
        """
        lines = content.split('\n')
        issues = []
        prev_level = 0
        
        for line_num, line in enumerate(lines, 1):
            level = self._detect_heading_level(line)
            
            if level > 0:
                # Record the first heading level as the baseline
                # Do NOT flag it as an issue - Hugo/docs often have H1 in front matter
                if prev_level == 0:
                    prev_level = level
                    continue
                
                # Check for heading level skips (only for subsequent headings)
                # A skip is when the level increases by more than 1
                if level - prev_level > 1:
                    issues.append({
                        'line': line_num,
                        'current_level': level,
                        'prev_level': prev_level,
                        'issue': f'Heading jumped from H{prev_level} to H{level}',
                        'suggestion': prev_level + 1,
                        'content': line.strip()
                    })
                
                prev_level = level
        
        return issues
    
    def _check_heading_hierarchy(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for heading hierarchy violations in page content.
        
        Detects issues like:
        - Skipped heading levels (e.g., ## followed by #### without ###)
        
        NOTE: Does NOT flag "first heading is not H1" as an issue. In Hugo/documentation
        systems, the page title (H1) often comes from front matter.
        
        Args:
            page_url: URL of the page being analyzed
            text_content: Raw text/markdown content of the page
            
        Returns:
            List of heading hierarchy issues found
        """
        issues = self._analyze_heading_hierarchy(text_content)
        
        for issue in issues:
            location = f"Line {issue['line']}: {issue['content'][:60]}..."
            fix = f"{issue['issue']}. Change to H{issue['suggestion']}"
            
            self._write_csv_row(page_url, 'heading_hierarchy', location, fix)
        
        return issues
    
    def _check_numbered_list_sequence(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for numbered list sequence errors.
        
        Detects issues like:
        - Duplicate numbers (e.g., 1, 2, 3, 3, 5)
        - Missing numbers in sequence
        - Out of order numbers
        
        Args:
            page_url: URL of the page being analyzed
            text_content: Raw text/markdown content of the page
            
        Returns:
            List of numbered list sequence issues found
        """
        issues = []
        lines = text_content.split('\n')
        
        # Track current list context
        in_list = False
        expected_number = 1
        list_indent = ''
        list_format = '.'  # '.' or ')'
        
        for line_num, line in enumerate(lines):
            # Check if this line is a numbered list item
            list_match = re.match(r'^(\s*)(\d+)([.)])(\s+.*)$', line)
            
            if list_match:
                indent = list_match.group(1)
                number = int(list_match.group(2))
                separator = list_match.group(3)
                
                if not in_list:
                    # Starting a new list
                    in_list = True
                    list_indent = indent
                    list_format = separator
                    expected_number = number + 1
                elif indent == list_indent and separator == list_format:
                    # Continuing the same list - check sequence
                    if number != expected_number:
                        if number == expected_number - 1:
                            # Duplicate number
                            issue = {
                                'type': 'duplicate_number',
                                'line': line_num + 1,
                                'number': number,
                                'expected': expected_number,
                                'content': line.strip()[:50]
                            }
                            issues.append(issue)
                            
                            location = f"Line {line_num + 1}: Duplicate list number {number}"
                            fix = f"Change to {expected_number}. (sequential numbering)"
                            self._write_csv_row(page_url, 'numbered_list', location, fix)
                        elif number > expected_number:
                            # Skipped number
                            issue = {
                                'type': 'skipped_number',
                                'line': line_num + 1,
                                'number': number,
                                'expected': expected_number,
                                'content': line.strip()[:50]
                            }
                            issues.append(issue)
                            
                            location = f"Line {line_num + 1}: Skipped from {expected_number - 1} to {number}"
                            fix = f"Change to {expected_number}. (sequential numbering)"
                            self._write_csv_row(page_url, 'numbered_list', location, fix)
                    
                    expected_number = number + 1
                else:
                    # Different indent or format - might be nested or new list
                    if indent != list_indent:
                        # Nested list - don't reset
                        pass
                    else:
                        # New list format
                        list_format = separator
                        expected_number = number + 1
            else:
                # Not a numbered list line
                if in_list:
                    if line.strip() == '' or (list_indent and line.startswith(list_indent) and len(line) > len(list_indent)):
                        # Blank line or indented content - list might continue
                        pass
                    else:
                        in_list = False
                        expected_number = 1
        
        return issues
    
    def _fix_heading_hierarchy(self, content: str) -> Tuple[str, List[Dict]]:
        """Fix heading hierarchy violations in markdown content.
        
        Applies conservative fixes:
        - Fixes skipped heading levels by adjusting to next valid level
        
        NOTE: Does NOT change the first heading to H1. In Hugo/documentation systems,
        the page title (H1) often comes from front matter, so content headings
        legitimately start at H2 or lower. Forcing the first heading to H1 would
        incorrectly modify valid markdown like "## Example" to "# Example".
        
        Args:
            content: Original markdown content
            
        Returns:
            Tuple of (fixed_content, list_of_fixes_applied)
        """
        lines = content.split('\n')
        fixes_applied = []
        prev_level = 0
        first_heading_level = 0  # Track the first heading level to use as baseline
        
        for i, line in enumerate(lines):
            level = self._detect_heading_level(line)
            
            if level > 0:
                new_level = level
                fix_reason = None
                
                # Record the first heading level as the baseline
                # Do NOT force it to be H1 - Hugo/docs often have H1 in front matter
                if prev_level == 0:
                    first_heading_level = level
                    prev_level = level
                    continue
                
                # Fix heading level skips (only for subsequent headings)
                # A skip is when the level increases by more than 1
                if level - prev_level > 1:
                    new_level = prev_level + 1
                    fix_reason = f'Heading skip: H{prev_level} -> H{level} becomes H{prev_level} -> H{new_level}'
                
                if new_level != level and fix_reason:
                    # Replace heading
                    old_line = line
                    new_line = re.sub(r'^#{1,6}', '#' * new_level, line)
                    lines[i] = new_line
                    
                    fixes_applied.append({
                        'line': i + 1,
                        'old_level': level,
                        'new_level': new_level,
                        'reason': fix_reason,
                        'old_content': old_line.strip(),
                        'new_content': new_line.strip()
                    })
                    
                    prev_level = new_level
                else:
                    prev_level = level
        
        return '\n'.join(lines), fixes_applied
    
    def _fix_markdown_header_spacing(self, content: str) -> str:
        """Fix markdown headers missing space after hash symbols.
        
        Fixes issues like:
        - "####Title" -> "#### Title"
        - "###Subtitle" -> "### Subtitle"
        - "##Section" -> "## Section"
        
        This is a deterministic fix that adds a space between the hash symbols
        and the title text when missing.
        """
        def add_space(match):
            hashes = match.group(1)
            title = match.group(2)
            return f"{hashes} {title}"
        
        return self.MARKDOWN_HEADER_NO_SPACE.sub(add_space, content)
    
    def _fix_html_comments(self, content: str) -> str:
        """Remove HTML comment markers while preserving inner content.
        
        Transforms:
        - "<!-- Azure - A vhd file -->" -> "Azure - A vhd file"
        - "<!-- ###Section\nContent -->" -> "###Section\nContent"
        
        This removes the comment markers (<!-- and -->) but keeps the content
        that was inside the comment, making it visible in the rendered output.
        
        Note: This operates on the raw content and does NOT modify content
        inside fenced code blocks (``` ... ```).
        """
        # First, protect fenced code blocks from modification
        code_blocks = []
        code_block_pattern = re.compile(r'```[\s\S]*?```')
        
        def save_code_block(match):
            code_blocks.append(match.group(0))
            return f'__CODE_BLOCK_{len(code_blocks) - 1}__'
        
        # Replace code blocks with placeholders
        content = code_block_pattern.sub(save_code_block, content)
        
        # Remove HTML comment markers, keeping the inner content
        def uncomment(match):
            inner_content = match.group(1)
            # Preserve leading/trailing whitespace structure
            return inner_content
        
        content = self.HTML_COMMENT_PATTERN.sub(uncomment, content)
        
        # Restore code blocks
        for i, code_block in enumerate(code_blocks):
            content = content.replace(f'__CODE_BLOCK_{i}__', code_block)
        
        return content
    
    def _check_url_link(self, url: str) -> Tuple[bool, int]:
        """Check if a URL link is valid."""
        try:
            response = self.session.head(url, timeout=3, allow_redirects=True)
            return response.status_code < 400, response.status_code
        except requests.exceptions.Timeout:
            return False, 0
        except Exception:
            return False, -1
    
    def _check_orphan_links(self, page_url: str, soup: BeautifulSoup) -> List[Dict]:
        """Check for broken links (orphan URLs)."""
        orphans = []
        page_parsed = urllib.parse.urlparse(page_url)
        page_domain = page_parsed.netloc
        checked = set()
        
        for anchor in soup.find_all('a', href=True):
            href = anchor.get('href', '').strip()
            if not href or href.startswith('#') or href.startswith('javascript:') or href.startswith('mailto:'):
                continue
            
            full_url = urllib.parse.urljoin(page_url, href)
            parsed = urllib.parse.urlparse(full_url)
            
            if parsed.scheme not in ('http', 'https'):
                continue
            
            if full_url in checked:
                continue
            checked.add(full_url)
            
            # Only check internal links for performance
            if parsed.netloc != page_domain:
                continue
            
            is_valid, status_code = self._check_url_link(full_url)
            if not is_valid:
                link_text = anchor.get_text().strip()[:50]
                location = f"Link text: '{link_text}', URL: {full_url}"
                fix = f"Remove or update link (status: {status_code})"
                self._write_csv_row(page_url, 'orphan_url', location, fix)
                orphans.append({'url': full_url, 'text': link_text, 'status': status_code})
            
            time.sleep(0.1)
        
        return orphans
    
    def _check_orphan_images(self, page_url: str, soup: BeautifulSoup) -> List[Dict]:
        """Check for broken image links."""
        orphans = []
        page_parsed = urllib.parse.urlparse(page_url)
        page_domain = page_parsed.netloc
        checked = set()
        
        for img in soup.find_all('img', src=True):
            src = img.get('src', '').strip()
            if not src:
                continue
            
            full_url = urllib.parse.urljoin(page_url, src)
            parsed = urllib.parse.urlparse(full_url)
            
            if parsed.scheme not in ('http', 'https'):
                continue
            
            if full_url in checked:
                continue
            checked.add(full_url)
            
            # Only check internal images
            if parsed.netloc != page_domain:
                continue
            
            is_valid, status_code = self._check_url_link(full_url)
            if not is_valid:
                alt_text = img.get('alt', '')[:50]
                location = f"Alt text: '{alt_text}', URL: {full_url}"
                fix = f"Remove or fix image path (status: {status_code})"
                self._write_csv_row(page_url, 'orphan_picture', location, fix)
                orphans.append({'url': full_url, 'alt': alt_text, 'status': status_code})
            
            time.sleep(0.1)
        
        return orphans
    
    def _check_image_alignment(self, page_url: str, soup: BeautifulSoup) -> bool:
        """Check for unaligned multiple images."""
        images = soup.find_all('img')
        
        if len(images) <= 1:
            return True
        
        unaligned = []
        for img in images:
            img_class = img.get('class', [])
            if isinstance(img_class, str):
                img_class = [img_class]
            
            has_alignment = any(cls in img_class for cls in self.ALIGNMENT_CLASSES)
            
            # Check parent container
            parent = img.parent
            if parent:
                parent_class = parent.get('class', [])
                if isinstance(parent_class, str):
                    parent_class = [parent_class]
                has_alignment = has_alignment or any(cls in parent_class for cls in self.CONTAINER_CLASSES)
                has_alignment = has_alignment or parent.name in ('figure', 'picture')
            
            if not has_alignment:
                unaligned.append(img)
        
        if len(unaligned) > 1:
            image_srcs = [img.get('src', '')[:50] for img in unaligned[:3]]
            location = f"{len(unaligned)} unaligned images: {', '.join(image_srcs)}"
            fix = "Add CSS alignment classes or wrap images in container div"
            self._write_csv_row(page_url, 'unaligned_images', location, fix)
            return False
        
        return True
    
    def analyze_page(self, page_url: str):
        """Analyze a single page for all issue types."""
        self.logger.info(f"Analyzing: {page_url}")
        
        try:
            response = self.session.get(page_url, timeout=10)
            if response.status_code >= 400:
                self.logger.warning(f"Orphaned page (HTTP {response.status_code}): {page_url}")
                self._write_csv_row(
                    page_url,
                    'orphan_page',
                    f"HTTP {response.status_code} - Page not accessible",
                    "Remove from sitemap or fix page availability"
                )
                return
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Extract main content
            main = soup.find('div', id='content') or soup.find('main') or soup.find('article') or soup
            
            # Clean content
            for elem in main.find_all(['script', 'style', 'nav', 'footer', 'header']):
                elem.decompose()
            
            text_content = main.get_text(separator=' ', strip=True)
            html_content = str(main)
            
            # Perform analyses
            grammar_issues = self._check_grammar(page_url, text_content)
            md_artifacts = self._check_markdown_artifacts(page_url, html_content, text_content)
            orphan_links = self._check_orphan_links(page_url, soup)
            orphan_images = self._check_orphan_images(page_url, soup)
            self._check_image_alignment(page_url, soup)
            
            # Check for all backtick issues (unified detection)
            backtick_issues = []
            backtick_issues.extend(self._check_missing_spaces_around_backticks(page_url, text_content))
            backtick_issues.extend(self._check_backtick_errors(page_url, text_content))
            backtick_issues.extend(self._check_malformed_code_blocks(page_url, text_content))
            
            # Check for indentation issues in lists
            indentation_issues = self._check_list_indentation_issues(page_url, html_content)
            
            # Check for shell prompt prefixes in code blocks
            shell_prompt_issues = self._check_shell_prompt_in_code_blocks(page_url, soup)
            
            # Check for mixed command and output in code blocks
            mixed_cmd_output_issues = self._check_mixed_command_output_in_code_blocks(page_url, soup)
            
            # Check for deprecated VMware package URLs
            deprecated_url_issues = self._check_deprecated_vmware_urls(page_url, soup)
            
            # Check for incorrect VMware spelling
            vmware_spelling_issues = self._check_vmware_spelling(page_url, text_content)
            
            # Check for broken email addresses (domain split with whitespace)
            broken_email_issues = self._check_broken_email_addresses(page_url, text_content)
            
            # Check for markdown headers missing space after hash symbols
            header_spacing_issues = self._check_markdown_header_spacing(page_url, text_content)
            
            # Check for HTML comments that should be uncommented
            html_comment_issues = self._check_html_comments(page_url, text_content)
            
            # Check for heading hierarchy violations (H1 -> H3 skips, wrong first heading level)
            heading_hierarchy_issues = self._check_heading_hierarchy(page_url, text_content)
            
            # Check for numbered list sequence errors (duplicate/skipped numbers)
            numbered_list_issues = self._check_numbered_list_sequence(page_url, text_content)
            
            # Apply fixes if running with --gh-pr
            if self.command == 'run' and self.gh_pr:
                all_issues = {
                    'grammar_issues': grammar_issues,
                    'md_artifacts': md_artifacts,
                    'orphan_links': orphan_links,
                    'orphan_images': orphan_images,
                    'backtick_issues': backtick_issues,
                    'indentation_issues': indentation_issues,
                    'shell_prompt_issues': shell_prompt_issues,
                    'mixed_cmd_output_issues': mixed_cmd_output_issues,
                    'deprecated_url_issues': deprecated_url_issues,
                    'vmware_spelling_issues': vmware_spelling_issues,
                    'broken_email_issues': broken_email_issues,
                    'header_spacing_issues': header_spacing_issues,
                    'html_comment_issues': html_comment_issues,
                    'heading_hierarchy_issues': heading_hierarchy_issues,
                    'numbered_list_issues': numbered_list_issues,
                }
                self.fix_applicator.apply_fixes(page_url, all_issues, text_content)
            
            self.pages_analyzed += 1
            
        except requests.exceptions.Timeout:
            self.logger.warning(f"Timeout: {page_url}")
            self._write_csv_row(page_url, 'orphan_page', "Connection timeout", "Check availability")
        except requests.exceptions.ConnectionError:
            self.logger.warning(f"Connection error: {page_url}")
            self._write_csv_row(page_url, 'orphan_page', "Connection error", "Check server status")
        except Exception as e:
            self.logger.error(f"Failed to analyze {page_url}: {e}")
            self._write_csv_row(page_url, 'analysis_error', str(e), "Check page structure")
    
    def _fix_broken_email_addresses(self, content: str) -> str:
        """Fix broken email addresses where domain is split with whitespace.
        
        Fixes issues like:
        - "linux-packages@vmware.                        com" -> "linux-packages@vmware.com"
        - "user@example.   org" -> "user@example.org"
        
        This commonly happens in console output where long lines are wrapped.
        """
        def fix_email(match):
            email_prefix = match.group(1)  # e.g., "linux-packages@vmware."
            tld = match.group(3)           # e.g., "com"
            return f"{email_prefix}{tld}"
        
        return self.BROKEN_EMAIL_PATTERN.sub(fix_email, content)
    
    def _fix_numbered_list_sequence(self, content: str) -> str:
        """Fix numbered list items with incorrect sequential numbering.
        
        Fixes issues like:
        1. First item
        2. Second item
        3. Third item
        3. Fourth item  <- Should be 4.
        
        Also handles:
        - Lists starting from any number (preserves first number)
        - Various formats: "1. Item" (standard) or "1) Item" (parenthesis)
        - Indented content between list items
        - Nested lists at different indentation levels
        """
        lines = content.split('\n')
        result_lines = []
        
        # Track current list context
        in_list = False
        expected_number = 1
        list_indent = ''
        list_format = '.'  # '.' or ')'
        
        for line in lines:
            # Check if this line is a numbered list item
            # Pattern: optional indent + number + (. or )) + space + content
            list_match = re.match(r'^(\s*)(\d+)([.)])(\s+.*)$', line)
            
            if list_match:
                indent = list_match.group(1)
                number = int(list_match.group(2))
                separator = list_match.group(3)
                rest = list_match.group(4)
                
                # Check if we're starting a new list or continuing
                if not in_list:
                    # Starting a new list - preserve the first number as-is
                    in_list = True
                    list_indent = indent
                    list_format = separator
                    expected_number = number + 1  # Next number should be this + 1
                    result_lines.append(line)
                elif indent == list_indent and separator == list_format:
                    # Continuing the same list - always use the expected number
                    # This fixes both duplicates and out-of-sequence numbers
                    fixed_line = f'{indent}{expected_number}{separator}{rest}'
                    result_lines.append(fixed_line)
                    expected_number += 1
                elif indent != list_indent:
                    # Different indent - this is a nested list, keep as-is
                    # Don't modify nested list numbering
                    result_lines.append(line)
                else:
                    # Same indent but different format (e.g., switching from "1." to "1)")
                    # Treat as a new list
                    list_format = separator
                    expected_number = number + 1
                    result_lines.append(line)
            else:
                # Not a numbered list line
                # Check if list continues (blank line or indented content under list item)
                if in_list:
                    # List continues if line is blank or indented under the list
                    is_continuation = (
                        line.strip() == '' or 
                        (list_indent and line.startswith(list_indent) and len(line.strip()) > 0) or
                        (not list_indent and line.startswith((' ', '\t')))
                    )
                    
                    if not is_continuation:
                        # Line doesn't belong to list - reset list tracking
                        in_list = False
                        expected_number = 1
                        list_indent = ''
                
                result_lines.append(line)
        
        return '\n'.join(result_lines)
    
    def _fix_mixed_command_output_llm(self, content: str, issues: List[Dict]) -> str:
        """Fix mixed command/output code blocks using LLM.
        
        Asks LLM to separate command and output into distinct code blocks.
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        if not self.llm_client or not issues:
            return content
        
        # Create prompt for LLM
        commands = [issue.get('command', '') for issue in issues[:5]]
        commands_str = '\n'.join(f"- {cmd}" for cmd in commands if cmd)
        
        prompt_template = f"""In the following markdown content, there are code blocks that mix commands with their output.
Please separate each such code block into two blocks:
1. A command block (just the command, copyable)
2. An output block (the command output, for display)

Commands to look for:
{commands_str}

For example, transform:
```
sudo cat /etc/config.toml
[Section]
Key="value"
```

Into:
```bash
sudo cat /etc/config.toml
```

Output:
```toml
[Section]
Key="value"
```

CRITICAL RULES - VIOLATIONS WILL CAUSE ERRORS:
1. Do NOT modify any URLs or placeholders (text like __URL_PLACEHOLDER_N__)
2. Do NOT change any relative paths like ../../images/ or ../images/
3. Do NOT change paths in markdown links [text](path) - keep the path exactly as-is
4. Only modify the code blocks that mix commands with output
5. Do NOT modify any other content outside of these specific code blocks
6. Do NOT add any explanations, notes, or commentary to your response
7. Do NOT change the content or meaning of any text outside code blocks
8. Do NOT add, remove, or reorder list items

Content to fix:
{{text}}

Output the fixed markdown directly without any preamble or explanation."""

        try:
            fixed = self.llm_client._generate_with_url_protection(prompt_template, content)
            if fixed and len(fixed) > len(content) * 0.5:  # Sanity check
                return fixed
        except Exception as e:
            self.logger.error(f"LLM fix for mixed command/output failed: {e}")
        
        return content
    
    def analyze_all_pages(self):
        """Analyze all pages in the sitemap."""
        total = len(self.sitemap)
        self.logger.info(f"Starting analysis of {total} pages...")
        
        if HAS_TQDM:
            self.progress_bar = tqdm(
                total=total,
                desc="Analyzing pages",
                unit="page",
                bar_format='{desc}: {percentage:3.0f}%|{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]'
            )
        
        try:
            if self.num_workers == 1:
                for page_url in self.sitemap:
                    self.analyze_page(page_url)
                    if self.progress_bar:
                        self.progress_bar.update(1)
            else:
                self._analyze_pages_parallel()
        finally:
            if self.progress_bar:
                self.progress_bar.close()
        
        self.logger.info(f"Analysis complete. Report: {self.report_filename}")
    
    def _analyze_pages_parallel(self):
        """Analyze pages in parallel using ThreadPoolExecutor."""
        progress_lock = threading.Lock()
        
        def analyze_with_progress(page_url):
            try:
                self.analyze_page(page_url)
            finally:
                with progress_lock:
                    if self.progress_bar:
                        self.progress_bar.update(1)
        
        with ThreadPoolExecutor(max_workers=self.num_workers) as executor:
            futures = [executor.submit(analyze_with_progress, url) for url in self.sitemap]
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    self.logger.error(f"Page analysis failed: {e}")
    
    # =========================================================================
    # Git and GitHub Operations
    # =========================================================================
    
    def _fork_repository(self) -> bool:
        """Fork the reference repository using gh CLI."""
        if not self.ref_ghrepo or not self.gh_repotoken:
            return True  # No reference repo specified
        
        try:
            # Set GH_TOKEN environment
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            # Check gh CLI
            subprocess.run(['gh', '--version'], check=True, capture_output=True)
            
            # Parse user's repo URL to verify it exists
            if self.ghrepo_url:
                user_repo_parsed = urllib.parse.urlparse(self.ghrepo_url)
                user_repo_path = user_repo_parsed.path.strip('/')
                if user_repo_path.endswith('.git'):
                    user_repo_path = user_repo_path[:-4]
            else:
                # Fallback to default naming convention
                parsed = urllib.parse.urlparse(self.ref_ghrepo)
                repo_path = parsed.path.strip('/')
                if repo_path.endswith('.git'):
                    repo_path = repo_path[:-4]
                user_repo_path = f"{self.gh_username}/{repo_path.split('/')[-1]}"
            
            # Verify the user's repository exists (works for both forks and mirrors)
            self.logger.info(f"Verifying repository {user_repo_path} exists...")
            result = subprocess.run(
                ['gh', 'repo', 'view', user_repo_path],
                capture_output=True, text=True, env=env
            )
            
            if result.returncode == 0:
                self.logger.info(f"Repository {user_repo_path} verified")
                return True
            else:
                self.logger.error(f"Repository {user_repo_path} not found or not accessible")
                return False
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Repository verification failed: {e.stderr}")
            return False
        except FileNotFoundError:
            self.logger.error("gh CLI not found. Install from: https://cli.github.com/")
            return False
    
    def _clone_repository(self) -> Optional[str]:
        """Clone the user's fork repository to a temp directory.
        
        Returns:
            Path to the cloned repository, or None if cloning failed.
        """
        if not self.ghrepo_url or not self.gh_repotoken:
            return None
        
        try:
            import shutil
            
            # Create temp directory
            self.temp_dir = tempfile.mkdtemp(prefix='photon-docs-')
            self.logger.info(f"Created temp directory: {self.temp_dir}")
            
            # Build auth URL for cloning
            parsed = urllib.parse.urlparse(self.ghrepo_url)
            auth_url = f"{parsed.scheme}://{self.gh_username}:{self.gh_repotoken}@{parsed.netloc}{parsed.path}"
            
            # Clone the repository
            self.logger.info(f"Cloning {self.ghrepo_url} branch {self.ghrepo_branch}...")
            result = subprocess.run(
                ['git', 'clone', '--branch', self.ghrepo_branch, '--depth', '1', auth_url, self.temp_dir],
                capture_output=True, text=True
            )
            
            if result.returncode != 0:
                self.logger.error(f"Clone failed: {result.stderr}")
                return None
            
            # Configure git user identity in the cloned repo (required for commits)
            subprocess.run(
                ['git', 'config', 'user.email', f'{self.gh_username}@users.noreply.github.com'],
                cwd=self.temp_dir, check=True, capture_output=True
            )
            subprocess.run(
                ['git', 'config', 'user.name', self.gh_username],
                cwd=self.temp_dir, check=True, capture_output=True
            )
            self.logger.info(f"Configured git user: {self.gh_username}")
            
            self.logger.info(f"Repository cloned to {self.temp_dir}")
            return self.temp_dir
            
        except Exception as e:
            self.logger.error(f"Failed to clone repository: {e}")
            return None
    
    def _map_local_path_to_repo_path(self, local_path: str, repo_dir: str) -> Optional[str]:
        """Map a local webserver file path to the cloned repository path.
        
        Args:
            local_path: Path to file in local_webserver (e.g., /var/www/photon-site/content/en/docs-v5/...)
            repo_dir: Path to cloned repository
            
        Returns:
            Corresponding path in the cloned repository, or None if mapping failed.
        """
        if not self.local_webserver or not local_path:
            return None
        
        try:
            # Get the relative path from local_webserver
            # e.g., /var/www/photon-site/content/en/docs-v5/file.md -> content/en/docs-v5/file.md
            rel_path = os.path.relpath(local_path, self.local_webserver)
            
            # Construct path in cloned repo
            repo_path = os.path.join(repo_dir, rel_path)
            
            return repo_path
            
        except Exception as e:
            self.logger.error(f"Failed to map path {local_path}: {e}")
            return None
    
    def _copy_modified_files_to_repo(self, repo_dir: str) -> List[str]:
        """Copy modified files from local_webserver to the cloned repository.
        
        Args:
            repo_dir: Path to cloned repository
            
        Returns:
            List of paths to copied files in the repo (relative to repo_dir).
        """
        import shutil
        
        copied_files = []
        
        for local_path in self.modified_files:
            repo_path = self._map_local_path_to_repo_path(local_path, repo_dir)
            if not repo_path:
                self.logger.warning(f"Could not map {local_path} to repo path")
                continue
            
            try:
                # Ensure parent directory exists in repo
                os.makedirs(os.path.dirname(repo_path), exist_ok=True)
                
                # Copy the file
                shutil.copy2(local_path, repo_path)
                
                # Store relative path for git add
                rel_path = os.path.relpath(repo_path, repo_dir)
                copied_files.append(rel_path)
                self.logger.info(f"Copied {local_path} -> {repo_path}")
                
            except Exception as e:
                self.logger.error(f"Failed to copy {local_path} to {repo_path}: {e}")
        
        return copied_files
    
    def _git_commit_and_push(self) -> bool:
        """Clone repo, copy modified files, commit and push changes."""
        if not self.ghrepo_url or not self.gh_repotoken:
            return False
        
        if not self.modified_files:
            self.logger.warning("No modified files to commit - no fixes were applied to local files")
            print("\n[WARN] No files were modified. Possible reasons:")
            print("       - No fixable issues found in markdown source files")
            print("       - Local webserver path doesn't match Hugo content structure")
            print(f"       - Check that {self.local_webserver}/content/{self.language}/ contains your docs")
            return False
        
        try:
            # Check git
            subprocess.run(['git', '--version'], check=True, capture_output=True)
            
            # Clone the repository to a temp directory
            repo_dir = self._clone_repository()
            if not repo_dir:
                self.logger.error("Failed to clone repository")
                return False
            
            # Copy modified files to the cloned repo
            copied_files = self._copy_modified_files_to_repo(repo_dir)
            if not copied_files:
                self.logger.warning("No files were copied to the repository")
                return False
            
            # Change to repo directory for git operations
            original_cwd = os.getcwd()
            os.chdir(repo_dir)
            
            try:
                # Add copied files
                for rel_path in copied_files:
                    subprocess.run(['git', 'add', rel_path], check=True)
                
                # Check if there are changes to commit
                result = subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True)
                if not result.stdout.strip():
                    self.logger.info("No changes to commit")
                    return False
                
                # Commit
                commit_msg = f"Documentation fixes - {self.timestamp}\n\nAutomated fixes by {TOOL_NAME}"
                subprocess.run(['git', 'commit', '-m', commit_msg], check=True, capture_output=True)
                
                # Push with auth
                parsed = urllib.parse.urlparse(self.ghrepo_url)
                auth_url = f"{parsed.scheme}://{self.gh_username}:{self.gh_repotoken}@{parsed.netloc}{parsed.path}"
                
                # Use ghrepo_branch for pushing to user's forked repo
                branch = self.ghrepo_branch
                
                subprocess.run(['git', 'push', auth_url, branch], check=True, capture_output=True)
                self.logger.info(f"Pushed to {self.ghrepo_url} branch {branch}")
                print(f"\n[OK] Git push successful to {parsed.netloc}{parsed.path}")
                return True
                
            finally:
                # Restore original working directory
                os.chdir(original_cwd)
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Git operation failed: {e}")
            return False
    
    def _create_pull_request(self) -> bool:
        """Create a pull request using gh CLI."""
        if not self.gh_pr or not self.ref_ghrepo:
            return False
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            # Use ghrepo_branch as the head branch (user's forked repo branch)
            head_branch = self.ghrepo_branch
            
            # Use ref_ghbranch as the base branch (reference repo branch for PR target)
            base_branch = self.ref_ghbranch
            
            # Parse ref repo
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/').rstrip('.git')
            
            # PR details
            pr_title = f"Documentation fixes - {self.timestamp}"
            pr_body = f"""# Documentation Analysis Report

**Generated:** {self.timestamp}
**Tool:** {TOOL_NAME} v{VERSION}
**Pages analyzed:** {self.pages_analyzed}
**Issues found:** {self.issues_found}
**Fixes applied:** {self.fixes_applied}
**LLM Provider:** {self.llm_provider or 'None (deterministic fixes only)'}

## Issue Categories Detected and Fixed

### Deterministic Fixes (Applied Automatically)
- **VMware spelling**: Corrected incorrect spellings (vmware, Vmware, etc.) to VMware (excludes URLs, file paths, emails, code blocks)
- **Deprecated URLs**: Updated packages.vmware.com URLs to packages.broadcom.com
- **Backtick spacing**: Fixed missing spaces before/after inline code
- **Backtick errors**: Fixed spaces inside backticks (e.g., "` code `" -> "`code`")
- **Heading hierarchy**: Fixed heading level violations (e.g., H1 -> H3 skips)
- **Shell prompts**: Removed shell prompt prefixes ($, #, ❯) from code blocks

### LLM-Assisted Fixes (Requires --llm flag)
- **Grammar/spelling errors**: Language and grammar corrections (preserves URLs exactly)
- **Markdown artifacts**: Fixed unrendered markdown syntax (preserves URLs exactly)
- **Mixed command/output**: Separated command and output into distinct code blocks
- **Indentation issues**: Fixed list and code block indentation

### Issues Reported (Manual Review Recommended)
- **Broken links**: Orphan URLs requiring manual verification
- **Broken images**: Missing or inaccessible image files
- **Unaligned images**: Images lacking proper CSS alignment
- **Unclosed code blocks**: Fenced (```) or inline (`) code blocks without closing markers

See attached CSV report for detailed issue locations and fix suggestions.
"""
            
            # Create PR from user's branch to reference repo's base branch
            result = subprocess.run([
                'gh', 'pr', 'create',
                '--title', pr_title,
                '--body', pr_body,
                '--head', f"{self.gh_username}:{head_branch}",
                '--base', base_branch,
                '--repo', repo_path
            ], capture_output=True, text=True, check=True, env=env)
            
            pr_url = result.stdout.strip()
            self.logger.info(f"Pull request created: {pr_url}")
            print(f"\n[OK] Pull request created: {pr_url}")
            return True
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"PR creation failed: {e.stderr}")
            print(f"\n[ERROR] Failed to create PR: {e.stderr}")
            return False
        except FileNotFoundError:
            self.logger.error("gh CLI not found")
            return False
    
    # =========================================================================
    # Incremental PR Operations (per-fix commit/push/PR)
    # =========================================================================
    
    def _initialize_repo_for_incremental_pr(self) -> bool:
        """Clone the repository once at the start for incremental PR workflow.
        
        Returns:
            True if repo was cloned successfully, False otherwise.
        """
        if not self.gh_pr or not self.ghrepo_url:
            return False
        
        if self.repo_cloned:
            return True
        
        try:
            # Clone the repository
            repo_dir = self._clone_repository()
            if not repo_dir:
                self.logger.error("Failed to clone repository for incremental PR")
                return False
            
            self.repo_cloned = True
            self.logger.info(f"Repository cloned for incremental PR workflow: {repo_dir}")
            return True
            
        except Exception as e:
            self.logger.error(f"Failed to initialize repo for incremental PR: {e}")
            return False
    
    def _incremental_commit_push_and_pr(self, local_path: str, fixes_applied: List[str]) -> bool:
        """Add file fix to a single squashed commit, push, and create/update PR.
        
        This is called immediately after each file fix is applied.
        Thread-safe via git_lock.
        
        Uses a single commit per run:
        - First fix: creates new commit with descriptive message
        - Subsequent fixes: amends the commit and force pushes
        
        Args:
            local_path: Path to the fixed local file
            fixes_applied: List of fix types applied (e.g., ['VMware spelling', 'backtick spacing'])
            
        Returns:
            True if commit/push/PR succeeded, False otherwise.
        """
        if not self.gh_pr or not self.repo_cloned or not self.temp_dir:
            return False
        
        with self.git_lock:
            try:
                import shutil
                
                # Map local path to repo path
                repo_path = self._map_local_path_to_repo_path(local_path, self.temp_dir)
                if not repo_path:
                    self.logger.warning(f"Could not map {local_path} to repo path")
                    return False
                
                # Ensure parent directory exists in repo
                os.makedirs(os.path.dirname(repo_path), exist_ok=True)
                
                # Copy the fixed file to the cloned repo
                shutil.copy2(local_path, repo_path)
                rel_path = os.path.relpath(repo_path, self.temp_dir)
                self.logger.info(f"Copied {local_path} -> {repo_path}")
                
                # Change to repo directory for git operations
                original_cwd = os.getcwd()
                os.chdir(self.temp_dir)
                
                try:
                    # Add the file
                    subprocess.run(['git', 'add', rel_path], check=True, capture_output=True)
                    
                    # Check if there are changes to commit
                    result = subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True)
                    if not result.stdout.strip():
                        self.logger.info(f"No changes to commit for {rel_path} (file content identical)")
                        return True  # No changes but not an error
                    
                    # Log the fix for PR body (only after confirming there are actual changes)
                    self.fixed_files_log.append({
                        'file': rel_path,
                        'fixes': fixes_applied,
                        'timestamp': datetime.datetime.now().isoformat()
                    })
                    
                    # Build commit message with all fixes so far
                    commit_msg = self._generate_commit_message()
                    
                    if not self.first_commit_made:
                        # First commit: create new commit
                        subprocess.run(['git', 'commit', '-m', commit_msg], check=True, capture_output=True)
                        self.first_commit_made = True
                        self.logger.info(f"Created initial commit with fix for {os.path.basename(local_path)}")
                    else:
                        # Subsequent fixes: amend the existing commit
                        subprocess.run(['git', 'commit', '--amend', '-m', commit_msg], check=True, capture_output=True)
                        self.logger.info(f"Amended commit with fix for {os.path.basename(local_path)}")
                    
                    # Push with auth (force push needed for amended commits)
                    parsed = urllib.parse.urlparse(self.ghrepo_url)
                    auth_url = f"{parsed.scheme}://{self.gh_username}:{self.gh_repotoken}@{parsed.netloc}{parsed.path}"
                    branch = self.ghrepo_branch
                    
                    if self.first_commit_made and len(self.fixed_files_log) > 1:
                        # Force push for amended commits
                        subprocess.run(['git', 'push', '--force', auth_url, branch], check=True, capture_output=True)
                    else:
                        # Regular push for first commit
                        subprocess.run(['git', 'push', auth_url, branch], check=True, capture_output=True)
                    
                    self.logger.info(f"Pushed to {self.ghrepo_url}")
                    print(f"  [PUSH] {os.path.basename(local_path)} added to commit")
                    
                    # Create or update PR
                    self._create_or_update_pr()
                    
                    return True
                    
                finally:
                    os.chdir(original_cwd)
                    
            except subprocess.CalledProcessError as e:
                self.logger.error(f"Git operation failed for {local_path}: {e}")
                return False
            except Exception as e:
                self.logger.error(f"Incremental commit/push failed for {local_path}: {e}")
                return False
    
    def _generate_commit_message(self) -> str:
        """Generate a commit message summarizing all fixes in this run.
        
        Returns:
            Commit message with title and list of fixed files.
        """
        title = f"Documentation fixes - {self.timestamp}"
        
        # Build list of fixed files
        files_summary = []
        for fix_entry in self.fixed_files_log:
            file_path = fix_entry['file']
            fixes = ', '.join(fix_entry['fixes'])
            files_summary.append(f"- {file_path}: {fixes}")
        
        body = "\n".join(files_summary) if files_summary else "- No fixes applied"
        
        return f"{title}\n\n{body}\n\nAutomated fixes by {TOOL_NAME} v{VERSION}"
    
    def _generate_pr_body(self) -> str:
        """Generate the PR body with current fix statistics."""
        # Build the files fixed section
        files_fixed_lines = []
        for fix_entry in self.fixed_files_log:
            file_path = fix_entry['file']
            fixes = ', '.join(fix_entry['fixes'])
            files_fixed_lines.append(f"- `{file_path}`: {fixes}")
        
        files_fixed_section = '\n'.join(files_fixed_lines) if files_fixed_lines else '- No fixes applied yet'
        
        pr_body = f"""# Documentation Analysis Report

**Generated:** {self.timestamp}
**Tool:** {TOOL_NAME} v{VERSION}
**Last Updated:** {datetime.datetime.now().isoformat()}
**Pages analyzed:** {self.pages_analyzed}
**Issues found:** {self.issues_found}
**Fixes applied:** {self.fixes_applied}
**LLM Provider:** {self.llm_provider or 'None (deterministic fixes only)'}

## Files Fixed

{files_fixed_section}

## Issue Categories Detected and Fixed

### Deterministic Fixes (Applied Automatically)
- **VMware spelling**: Corrected incorrect spellings (vmware, Vmware, etc.) to VMware (excludes URLs, file paths, emails, code blocks)
- **Deprecated URLs**: Updated packages.vmware.com URLs to packages.broadcom.com
- **Backtick spacing**: Fixed missing spaces before/after inline code
- **Backtick errors**: Fixed spaces inside backticks (e.g., "` code `" -> "`code`")
- **Heading hierarchy**: Fixed heading level violations (e.g., H1 -> H3 skips)
- **Shell prompts**: Removed shell prompt prefixes ($, #, ❯) from code blocks

### LLM-Assisted Fixes (Requires --llm flag)
- **Grammar/spelling errors**: Language and grammar corrections (preserves URLs exactly)
- **Markdown artifacts**: Fixed unrendered markdown syntax (preserves URLs exactly)
- **Mixed command/output**: Separated command and output into distinct code blocks
- **Indentation issues**: Fixed list and code block indentation

### Issues Reported (Manual Review Recommended)
- **Broken links**: Orphan URLs requiring manual verification
- **Broken images**: Missing or inaccessible image files
- **Unaligned images**: Images lacking proper CSS alignment
- **Unclosed code blocks**: Fenced (```) or inline (`) code blocks without closing markers

---
*This PR is updated incrementally as fixes are applied. Check the commit history for details.*
"""
        return pr_body
    
    def _find_existing_open_pr(self) -> bool:
        """Check if an open PR already exists from the fork branch to the target branch.
        
        If found, sets self.pr_url and self.pr_number.
        
        Returns:
            True if an existing open PR was found, False otherwise.
        """
        if not self.ref_ghrepo or not self.gh_repotoken:
            self.logger.debug("Cannot check for existing PR: missing ref_ghrepo or gh_repotoken")
            return False
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/').rstrip('.git')
            
            head_branch = self.ghrepo_branch
            base_branch = self.ref_ghbranch
            
            self.logger.info(f"Checking for existing open PR: {self.gh_username}:{head_branch} -> {repo_path}:{base_branch}")
            
            # Search for open PRs from our head branch to the base branch
            # Note: gh pr list --head works with just branch name when searching cross-repo
            # We also filter by author to ensure we only find our own PRs
            result = subprocess.run([
                'gh', 'pr', 'list',
                '--head', head_branch,
                '--base', base_branch,
                '--repo', repo_path,
                '--author', self.gh_username,
                '--state', 'open',
                '--json', 'number,url,title',
                '--limit', '1'
            ], capture_output=True, text=True, env=env)
            
            self.logger.debug(f"gh pr list result: returncode={result.returncode}, stdout={result.stdout[:200] if result.stdout else 'empty'}, stderr={result.stderr[:200] if result.stderr else 'empty'}")
            
            if result.returncode == 0 and result.stdout.strip():
                try:
                    pr_data = json.loads(result.stdout)
                    if pr_data:
                        self.pr_number = pr_data[0]['number']
                        self.pr_url = pr_data[0]['url']
                        pr_title = pr_data[0].get('title', '')
                        self.logger.info(f"Found existing open PR #{self.pr_number}: {pr_title}")
                        print(f"\n[PR] Reusing existing PR #{self.pr_number}: {self.pr_url}")
                        return True
                    else:
                        self.logger.info("No existing open PR found (empty result)")
                except json.JSONDecodeError as e:
                    self.logger.warning(f"Failed to parse PR list JSON: {e}")
            else:
                self.logger.info(f"No existing open PR found (returncode={result.returncode})")
                if result.stderr:
                    self.logger.debug(f"gh pr list stderr: {result.stderr}")
            
            return False
            
        except Exception as e:
            self.logger.warning(f"Error checking for existing PR: {e}")
            return False
    
    def _create_or_update_pr(self) -> bool:
        """Create a new PR or update the existing one with new fix information.
        
        On first call per run:
        - Checks if an open PR already exists (from previous runs)
        - If yes, reuses that PR
        - If no, creates a new PR using GitHub API
        
        On subsequent calls:
        - Updates the existing PR body with new fix information
        
        Note: Works with both forks and mirrors. Uses GitHub API directly to
        support cross-repository PRs from mirrors (non-fork repositories).
        
        Returns:
            True if PR was created/updated successfully, False otherwise.
        """
        if not self.gh_pr or not self.ref_ghrepo:
            return False
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            # Parse ref repo (target for PR)
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/')
            if repo_path.endswith('.git'):
                repo_path = repo_path[:-4]
            
            head_branch = self.ghrepo_branch
            base_branch = self.ref_ghbranch
            
            pr_body = self._generate_pr_body()
            
            if self.pr_url is None:
                # First, check if an open PR already exists (from previous runs)
                if self._find_existing_open_pr():
                    # Reuse existing PR - just update the body
                    return self._update_pr_body(pr_body)
                
                # No existing PR, create a new one using GitHub API
                # This works for both forks and mirrors
                pr_title = f"Documentation fixes - {self.timestamp}"
                
                # Create PR using gh api command (works for cross-repo PRs)
                pr_data = {
                    'title': pr_title,
                    'body': pr_body,
                    'head': f"{self.gh_username}:{head_branch}",
                    'base': base_branch
                }
                
                result = subprocess.run([
                    'gh', 'api',
                    f'repos/{repo_path}/pulls',
                    '-X', 'POST',
                    '-f', f'title={pr_title}',
                    '-f', f'body={pr_body}',
                    '-f', f'head={self.gh_username}:{head_branch}',
                    '-f', f'base={base_branch}'
                ], capture_output=True, text=True, env=env)
                
                if result.returncode == 0:
                    try:
                        pr_response = json.loads(result.stdout)
                        self.pr_url = pr_response.get('html_url', '')
                        self.pr_number = pr_response.get('number')
                        self.logger.info(f"Pull request created: {self.pr_url}")
                        print(f"\n[PR] Created: {self.pr_url}")
                        return True
                    except json.JSONDecodeError:
                        self.logger.error(f"Failed to parse PR response: {result.stdout}")
                        return False
                else:
                    error_msg = result.stderr
                    # Check if it's a "No commits between" error (mirror/non-fork scenario)
                    if "No commits between" in error_msg or "No commits between" in result.stdout:
                        # Get user repo path for the manual PR link
                        user_repo_parsed = urllib.parse.urlparse(self.ghrepo_url)
                        user_repo_path = user_repo_parsed.path.strip('/')
                        if user_repo_path.endswith('.git'):
                            user_repo_path = user_repo_path[:-4]
                        
                        self.logger.warning(f"Cannot create cross-repository PR (mirror detected)")
                        print(f"\n[INFO] Cross-repository PR not possible - changes pushed to {self.ghrepo_url}")
                        print(f"       Branch: {head_branch}")
                        print(f"       Your mirror repository has the documentation fixes.")
                        print(f"       To contribute these changes to {repo_path}, you would need to:")
                        print(f"       1. Fork {repo_path} on GitHub")
                        print(f"       2. Push your changes to your fork")
                        print(f"       3. Create a PR from your fork to {repo_path}")
                        # Mark as successful since changes were pushed
                        self.pr_url = "N/A (mirror - manual PR required)"
                        return True
                    else:
                        self.logger.error(f"PR creation failed: {error_msg}")
                        return False
            else:
                # Update existing PR body
                return self._update_pr_body(pr_body)
                
        except subprocess.CalledProcessError as e:
            self.logger.error(f"PR operation failed: {e.stderr if hasattr(e, 'stderr') else e}")
            return False
        except Exception as e:
            self.logger.error(f"PR operation failed: {e}")
            return False
    
    def _update_pr_body(self, pr_body: str) -> bool:
        """Update the body of an existing PR.
        
        Args:
            pr_body: New PR body content
            
        Returns:
            True if update succeeded, False otherwise.
        """
        if not self.pr_number or not self.ref_ghrepo:
            return False
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/')
            if repo_path.endswith('.git'):
                repo_path = repo_path[:-4]
            
            result = subprocess.run([
                'gh', 'pr', 'edit', str(self.pr_number),
                '--body', pr_body,
                '--repo', repo_path
            ], capture_output=True, text=True, env=env)
            
            if result.returncode == 0:
                self.logger.info(f"Updated PR #{self.pr_number} body")
                return True
            else:
                self.logger.warning(f"Failed to update PR body: {result.stderr}")
                return False
                
        except Exception as e:
            self.logger.error(f"Failed to update PR body: {e}")
            return False
    
    # =========================================================================
    # Main Workflow
    # =========================================================================
    
    def finalize_report(self):
        """Finalize the report."""
        try:
            with open(self.report_filename, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                if len(lines) <= 1:
                    self._write_csv_row(
                        self.base_url,
                        'info',
                        'No issues found',
                        'Documentation appears to be in good condition'
                    )
        except Exception as e:
            self.logger.error(f"Failed to finalize report: {e}")
    
    def cleanup(self):
        """Cleanup resources."""
        if self.grammar_tool:
            try:
                self.grammar_tool.close()
            except:
                pass
        try:
            self.session.close()
        except:
            pass
        if self.temp_dir and os.path.exists(self.temp_dir):
            import shutil
            try:
                shutil.rmtree(self.temp_dir)
            except:
                pass
    
    def run_analyze(self):
        """Run analyze command (report only, no fixes)."""
        print(f"{TOOL_NAME} v{VERSION} - Analyze Mode")
        print(f"Log: {self.log_filename}")
        print(f"Report: {self.report_filename}")
        print(f"URL: {self.base_url}")
        print(f"Workers: {self.num_workers}")
        print()
        
        # Initialize grammar checker first - exit if fails
        if not self.initialize_grammar_checker():
            sys.exit(1)
        
        # Initialize CSV
        self._initialize_csv()
        
        # Validate connectivity
        if not self.validate_connectivity():
            print(f"\n[ERROR] Cannot connect to {self.base_url}")
            sys.exit(1)
        
        # Generate sitemap
        print("Discovering pages...")
        self.generate_sitemap()
        
        if not self.sitemap:
            print(f"\n[ERROR] No pages found")
            sys.exit(1)
        
        print(f"Found {len(self.sitemap)} pages to analyze\n")
        
        # Analyze
        self.analyze_all_pages()
        
        # Finalize
        self.finalize_report()
        
        # Summary
        print(f"\n[OK] Analysis complete!")
        print(f"   Report: {self.report_filename}")
        print(f"   Log: {self.log_filename}")
        print(f"   Pages: {self.pages_analyzed}")
        print(f"   Issues: {self.issues_found}")
    
    def run_full(self):
        """Run full workflow with fixes and PR.
        
        When --gh-pr is enabled, uses incremental PR workflow:
        - Clones repo once at start
        - Commits/pushes each fix immediately after it's applied
        - Creates PR on first fix, updates PR body on subsequent fixes
        """
        print(f"{TOOL_NAME} v{VERSION} - Run Mode")
        print(f"Log: {self.log_filename}")
        print(f"Report: {self.report_filename}")
        print(f"URL: {self.base_url}")
        print(f"Workers: {self.num_workers}")
        if self.gh_pr:
            print(f"PR Target: {self.ref_ghrepo}")
            print(f"PR Mode: Incremental (per-fix commit/push)")
        if self.llm_provider:
            print(f"LLM Provider: {self.llm_provider}")
        print()
        
        # Initialize grammar checker first - exit if fails
        if not self.initialize_grammar_checker():
            sys.exit(1)
        
        # Initialize CSV
        self._initialize_csv()
        
        # Fork repository if needed
        if self.gh_pr and self.ref_ghrepo:
            if not self._fork_repository():
                print(f"\n[ERROR] Failed to fork repository")
                sys.exit(1)
        
        # Clone repository for incremental PR workflow (before analysis starts)
        if self.gh_pr:
            print("Cloning repository for incremental PR workflow...")
            if not self._initialize_repo_for_incremental_pr():
                print(f"\n[ERROR] Failed to clone repository for incremental PR")
                sys.exit(1)
            print(f"[OK] Repository cloned to {self.temp_dir}\n")
        
        # Validate connectivity
        if not self.validate_connectivity():
            print(f"\n[ERROR] Cannot connect to {self.base_url}")
            sys.exit(1)
        
        # Generate sitemap
        print("Discovering pages...")
        self.generate_sitemap()
        
        if not self.sitemap:
            print(f"\n[ERROR] No pages found")
            sys.exit(1)
        
        print(f"Found {len(self.sitemap)} pages to analyze\n")
        
        # Analyze and apply fixes (incremental commit/push/PR happens per-fix)
        self.analyze_all_pages()
        
        # Finalize report
        self.finalize_report()
        
        # Final PR body update with complete statistics
        if self.gh_pr and self.pr_url:
            self._update_pr_body(self._generate_pr_body())
        
        # Summary
        print(f"\n[OK] Workflow complete!")
        print(f"   Report: {self.report_filename}")
        print(f"   Log: {self.log_filename}")
        print(f"   Pages: {self.pages_analyzed}")
        print(f"   Issues: {self.issues_found}")
        print(f"   Fixes: {self.fixes_applied}")
        if self.pr_url:
            print(f"   PR: {self.pr_url}")
    
    def run(self):
        """Main entry point."""
        try:
            if self.command == 'analyze':
                self.run_analyze()
            elif self.command == 'run':
                self.run_full()
        except KeyboardInterrupt:
            print(f"\n\n[WARN] Interrupted by user")
            print(f"   Partial results: {self.report_filename}")
            sys.exit(1)
        except Exception as e:
            self.logger.error(f"Failed: {e}")
            print(f"\n[ERROR] {e}")
            sys.exit(1)
        finally:
            self.cleanup()

