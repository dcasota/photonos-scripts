#!/usr/bin/env python3
"""
Photon OS Documentation Lecturer
A comprehensive command-line tool for crawling Photon OS documentation served by Nginx,
identifying issues (grammar/spelling, markdown artifacts, orphan links/images, unaligned images,
heading hierarchy violations), generating CSV reports, and optionally applying fixes via git 
push and GitHub PR.

Version: 1.5
Based on analyzer.py with extended features for complete documentation workflow.

Changes in 1.5:
- Added --fix parameter for selective fix application
- 13 enumerated fix types (9 automatic, 4 LLM-assisted)
- Use --list-fixes to see all available fix types

Usage:
    python3 photonos-docs-lecturer.py run --website <url> [options]
    python3 photonos-docs-lecturer.py analyze --website <url> [options]
    python3 photonos-docs-lecturer.py version

Commands:
    run      - Execute full workflow (analyze, generate fixes, push changes, create PR)
    analyze  - Generate report only (no fixes, git operations, or PR)
    version  - Display tool version

Issue Categories Detected:
    - grammar: Grammar and spelling issues
    - markdown: Unrendered markdown artifacts, missing header spacing, unclosed code blocks
    - heading_hierarchy: Heading level violations (skipped levels, wrong first heading)
    - orphan_page: Broken/inaccessible pages
    - orphan_link: Broken hyperlinks
    - orphan_image: Missing or broken images
    - image_alignment: Improperly aligned images
    - formatting: Missing spaces around backticks
    - backtick_errors: Spaces inside backticks, unclosed inline/fenced code blocks
    - indentation: List and code block indentation issues
    - shell_prompt: Shell prompt prefixes in code blocks
    - mixed_command_output: Commands mixed with output in code blocks
    - deprecated_url: Deprecated VMware package URLs
    - spelling: Incorrect VMware spelling (excludes URLs, file paths, emails, code blocks)

Example:
    python3 photonos-docs-lecturer.py run \\
        --website https://127.0.0.1/docs-v5 \\
        --local-webserver /var/www/photon-site \\
        --gh-repotoken ghp_xxxxxxxxx \\
        --gh-username test \\
        --ghrepo-url https://github.com/test/photon-0001.git \\
        --ghrepo-branch photon-hugo \\
        --ref-website https://vmware.github.io/photon/docs-v5 \\
        --ref-ghbranch photon-hugo \\
        --ref-ghrepo https://github.com/vmware/photon.git \\
        --parallel 10 \\
        --gh-pr \\
        --language en
"""

from __future__ import annotations

import argparse
import csv
import datetime
import logging
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.parse
import urllib.robotparser
from collections import deque
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple
import threading
import json

# Version info
VERSION = "1.7"
TOOL_NAME = "photonos-docs-lecturer.py"

# Lazy-loaded modules (populated by check_and_import_dependencies)
requests = None
bs4 = None
BeautifulSoup = None
language_tool_python = None
Retry = None
HTTPAdapter = None
tqdm = None
Image = None
genai = None
HAS_TQDM = False
HAS_PIL = False
HAS_GEMINI = False

def check_and_import_dependencies():
    """Check and import all required dependencies. Called after parsing commands."""
    global requests, bs4, BeautifulSoup, language_tool_python, Retry, HTTPAdapter
    global tqdm, Image, genai, HAS_TQDM, HAS_PIL, HAS_GEMINI
    
    missing_packages = []
    
    # Check required packages
    try:
        import requests as _requests
        requests = _requests
        from requests.adapters import HTTPAdapter as _HTTPAdapter
        HTTPAdapter = _HTTPAdapter
        try:
            from requests.packages.urllib3.util.retry import Retry as _Retry
        except ImportError:
            from urllib3.util.retry import Retry as _Retry
        Retry = _Retry
        requests.packages.urllib3.disable_warnings()
    except ImportError:
        missing_packages.append(('requests', 'requests'))
    
    try:
        import bs4 as _bs4
        bs4 = _bs4
        from bs4 import BeautifulSoup as _BeautifulSoup
        BeautifulSoup = _BeautifulSoup
    except ImportError:
        missing_packages.append(('bs4', 'beautifulsoup4'))
    
    try:
        import language_tool_python as _language_tool_python
        language_tool_python = _language_tool_python
    except ImportError:
        missing_packages.append(('language_tool_python', 'language-tool-python'))
    
    # Check optional packages
    try:
        from tqdm import tqdm as _tqdm
        tqdm = _tqdm
        HAS_TQDM = True
    except ImportError:
        HAS_TQDM = False
    
    try:
        from PIL import Image as _Image
        Image = _Image
        HAS_PIL = True
    except ImportError:
        HAS_PIL = False
    
    try:
        import google.generativeai as _genai
        genai = _genai
        HAS_GEMINI = True
    except ImportError:
        HAS_GEMINI = False
    
    # Report missing required packages
    if missing_packages:
        print("ERROR: Required libraries not found:", file=sys.stderr)
        for module_name, pip_name in missing_packages:
            print(f"       - {module_name} (pip install {pip_name})", file=sys.stderr)
        print(file=sys.stderr)
        print(f"       Run: python3 {TOOL_NAME} install-tools", file=sys.stderr)
        sys.exit(1)


class LLMClient:
    """Client for LLM API interactions (Gemini or xAI)."""
    
    # Pattern to match markdown links: [text](url)
    # Captures: group(1) = link text, group(2) = URL
    MARKDOWN_LINK_PATTERN = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
    
    # Pattern to match inline URLs (http/https)
    INLINE_URL_PATTERN = re.compile(r'(?<![(\[])(https?://[^\s<>"\')\]]+)')
    
    def __init__(self, provider: str, api_key: str, language: str = "en"):
        self.provider = provider.lower()
        self.api_key = api_key
        self.language = language
        self.model = None
        
        if self.provider == "gemini":
            if not HAS_GEMINI:
                raise ImportError("google-generativeai library required for Gemini. Install with: pip install google-generativeai")
            genai.configure(api_key=self.api_key)
            self.model = genai.GenerativeModel('gemini-2.5-flash')
        elif self.provider == "xai":
            # xAI uses HTTP API (OpenAI-compatible)
            self.xai_endpoint = "https://api.x.ai/v1/chat/completions"
            self.xai_model = "grok-3-mini"  # Default model (cost-efficient)
        else:
            raise ValueError(f"Unsupported LLM provider: {provider}")
    
    def _protect_urls(self, text: str) -> Tuple[str, Dict[str, str]]:
        """Replace URLs with placeholders to protect them from LLM modification.
        
        LLMs sometimes modify URLs despite explicit instructions not to do so.
        This method replaces all URLs with unique placeholders before sending
        to the LLM, allowing us to restore the original URLs afterwards.
        
        Args:
            text: Original text containing URLs
            
        Returns:
            Tuple of (protected_text, url_map) where url_map maps placeholders to original URLs
        """
        url_map = {}
        counter = [0]  # Use list to allow modification in nested function
        
        def replace_markdown_link(match):
            link_text = match.group(1)
            url = match.group(2)
            placeholder = f"__URL_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = url
            counter[0] += 1
            return f"[{link_text}]({placeholder})"
        
        def replace_inline_url(match):
            url = match.group(1)
            placeholder = f"__URL_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = url
            counter[0] += 1
            return placeholder
        
        # First protect markdown links [text](url)
        protected = self.MARKDOWN_LINK_PATTERN.sub(replace_markdown_link, text)
        
        # Then protect standalone URLs (not already in markdown links)
        protected = self.INLINE_URL_PATTERN.sub(replace_inline_url, protected)
        
        return protected, url_map
    
    def _restore_urls(self, text: str, url_map: Dict[str, str]) -> str:
        """Restore original URLs from placeholders.
        
        Args:
            text: Text with URL placeholders
            url_map: Map of placeholders to original URLs
            
        Returns:
            Text with original URLs restored
        """
        result = text
        for placeholder, original_url in url_map.items():
            result = result.replace(placeholder, original_url)
        return result
    
    def _generate_with_url_protection(self, prompt: str, text_to_protect: str) -> str:
        """Generate LLM response with URL protection and post-processing.
        
        Protects URLs in the input text before sending to LLM, then restores
        them in the output. This prevents LLMs from accidentally modifying
        URLs (e.g., removing .md extensions).
        
        Also cleans the LLM response to remove prompt leakage and artifacts.
        
        Args:
            prompt: The prompt template (should contain {text} placeholder)
            text_to_protect: The text content that may contain URLs
            
        Returns:
            LLM response with original URLs preserved and prompt leakage removed
        """
        # Protect URLs in the text
        protected_text, url_map = self._protect_urls(text_to_protect)
        
        # Generate response with protected text
        full_prompt = prompt.replace("{text}", protected_text)
        response = self._generate(full_prompt)
        
        if not response:
            return ""
        
        # Clean the response to remove prompt leakage
        cleaned_response = self._clean_llm_response(response, text_to_protect)
        
        # Restore original URLs in the response
        return self._restore_urls(cleaned_response, url_map)
    
    def translate(self, text: str, target_language: str) -> str:
        """Translate text to target language using LLM.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        prompt_template = f"""Translate the following text to {target_language}.

CRITICAL RULES - VIOLATIONS WILL CAUSE ERRORS:
1. Preserve ALL markdown formatting exactly as-is (headings, lists, code blocks, inline code)
2. Do NOT modify any URLs or placeholders (text like __URL_PLACEHOLDER_N__)
3. Do NOT translate or change any relative paths like ../../images/ or ../images/
4. Do NOT translate or change paths in markdown links [text](path) - keep the path exactly as-is
5. Do NOT translate content inside code blocks (```) or inline code (`)
6. Do NOT translate technical terms, product names, or command names (e.g., VMware, GitHub, Photon OS)
7. Do NOT add, remove, or reorder list items
8. Do NOT add any explanations, notes, or commentary to your response
9. Only translate the natural language text outside of code and technical terms

Text to translate:
{{text}}

Output the translated text directly without any preamble or explanation."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def fix_grammar(self, text: str, issues: List[Dict]) -> str:
        """Fix grammar issues in text using LLM.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        issue_desc = "\n".join([f"- {i['message']}: {i.get('suggestion', 'No suggestion')}" for i in issues[:10]])
        prompt_template = f"""Fix ONLY the following grammar issues in the text. 

CRITICAL RULES - VIOLATIONS WILL CAUSE ERRORS:
1. Preserve ALL markdown formatting exactly as-is (headings, lists, code blocks, inline code)
2. Do NOT modify any URLs or placeholders (text like __URL_PLACEHOLDER_N__)
3. Do NOT change any relative paths like ../../images/ or ../images/
4. Do NOT change paths in markdown links [text](path) - keep the path exactly as-is
5. Do NOT modify content inside code blocks (```) or inline code (`)
6. Do NOT change technical terms, product names, or command names (e.g., Tdnf, tdnf, VMware, GitHub)
7. Do NOT add, remove, or reorder list items - only fix grammar within existing items
8. Do NOT change the meaning or content of sentences - only fix grammar
9. Do NOT add any explanations, notes, or commentary to your response
10. Words at the start of sentences may be capitalized differently for technical reasons - leave them as-is

Issues to fix (ONLY fix these specific issues):
{issue_desc}

Text to fix:
{{text}}

Output the corrected text directly without any preamble or explanation."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def fix_markdown(self, text: str, artifacts: List[str]) -> str:
        """Fix markdown rendering artifacts.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        artifacts_str = ', '.join(artifacts[:5]) if artifacts else 'general markdown issues'
        prompt_template = f"""Fix ONLY the markdown rendering issues in the text. Issues detected: {artifacts_str}

CRITICAL RULES - VIOLATIONS WILL CAUSE ERRORS:
1. Do NOT modify any URLs or placeholders (text like __URL_PLACEHOLDER_N__)
2. Do NOT change any relative paths like ../../images/ or ../images/
3. Do NOT change paths in markdown links [text](path) - keep the path exactly as-is
4. Preserve all link URLs exactly as they appear in the original text
5. Do NOT convert single inline code (`) to fenced code blocks (```) if it's part of a sentence
6. Do NOT add language specifiers (like ```bash) to inline code that starts sentences
7. Do NOT change the content or meaning of any text - only fix markdown syntax
8. Do NOT add, remove, or reorder list items
9. Do NOT add any explanations, notes, or commentary to your response
10. Inline code like `cloud-init` or `nocloud` at the start of a sentence should remain as inline code

Text to fix:
{{text}}

Output the corrected markdown directly without any preamble or explanation."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def fix_indentation(self, text: str, issues: List[Dict]) -> str:
        """Fix indentation issues in markdown lists and code blocks.
        
        URLs are protected using placeholders to prevent LLM from modifying them.
        """
        issue_desc = "\n".join([f"- {i.get('context', i.get('type', 'unknown'))}" for i in issues[:10]])
        prompt_template = f"""Fix ONLY the indentation issues in the markdown text.

Indentation issues detected:
{issue_desc}

Common indentation problems to fix:
1. List items not properly aligned
2. Code blocks inside list items not indented correctly (need 4 spaces or 1 tab)
3. Nested content not properly indented under parent list items
4. Inconsistent indentation (mixing tabs and spaces)

CRITICAL RULES - VIOLATIONS WILL CAUSE ERRORS:
1. Do NOT modify any URLs or placeholders (text like __URL_PLACEHOLDER_N__)
2. Do NOT change any relative paths like ../../images/ or ../images/
3. Do NOT change paths in markdown links [text](path) - keep the path exactly as-is
4. ONLY fix indentation - do NOT change any words or content
5. Do NOT add, remove, or reorder list items
6. Do NOT change the text content of any list item
7. Do NOT add any explanations, notes, or commentary to your response
8. Preserve all existing whitespace within lines - only adjust leading whitespace

Text to fix:
{{text}}

Output the corrected markdown directly without any preamble or explanation."""
        return self._generate_with_url_protection(prompt_template, text)
    
    def _clean_llm_response(self, response: str, original_text: str) -> str:
        """Clean LLM response by removing prompt leakage and validating output.
        
        This method addresses several common LLM issues:
        1. Prompt leakage: LLM sometimes includes prompt instructions in output
        2. Artifacts: Phrases like "Return only the corrected text" appearing in output
        3. Content additions: LLM adding explanatory text not in original
        4. Content alteration: LLM changing meaning of original content
        
        Args:
            response: Raw LLM response
            original_text: Original text that was sent for fixing
            
        Returns:
            Cleaned response with prompt leakage removed
        """
        if not response:
            return ""
        
        # List of known prompt leakage patterns to remove
        prompt_leakage_patterns = [
            # Instruction fragments
            r'^Return only the corrected text\.?\s*',
            r'^Return only the corrected markdown text\.?\s*',
            r'^Return only the translated text\.?\s*',
            r'^Return only the fixed markdown content\.?\s*',
            r'Return only the corrected text\.?\s*$',
            r'Return only the corrected markdown text\.?\s*$',
            r'Return only the translated text\.?\s*$',
            r'Return only the fixed markdown content\.?\s*$',
            # Artifacts found prefix (from fix_markdown prompt)
            r'^Artifacts found:.*?\n',
            r'\nArtifacts found:.*$',
            # Issues found prefix (from fix_grammar/fix_indentation prompts)
            r'^Issues found:.*?\n(?:- .*\n)*',
            r'\nIssues found:.*$',
            # Common LLM meta-comments
            r'^Here is the (?:corrected|fixed|translated) text:\s*\n?',
            r'^Here\'s the (?:corrected|fixed|translated) text:\s*\n?',
            r'^\*\*(?:Corrected|Fixed|Translated) (?:Text|Markdown)\*\*:?\s*\n?',
            r'^IMPORTANT RULES:.*?(?=\n\n|\n[A-Z#`])',
            # No explanations trailer
            r'\n*No explanations\.?\s*$',
            r'\n*no explanations\.?\s*$',
        ]
        
        cleaned = response
        
        for pattern in prompt_leakage_patterns:
            cleaned = re.sub(pattern, '', cleaned, flags=re.MULTILINE | re.IGNORECASE | re.DOTALL)
        
        # Strip leading/trailing whitespace
        cleaned = cleaned.strip()
        
        # Sanity check: if response is drastically different in length, return original
        # This catches cases where LLM completely rewrote the content
        if len(cleaned) < len(original_text) * 0.5:
            logging.warning("LLM response too short compared to original, using original text")
            return original_text
        
        if len(cleaned) > len(original_text) * 2:
            logging.warning("LLM response much longer than original, may contain explanations")
            # Try to extract just the text portion if there's clear structure
            # Look for common patterns where LLM adds explanations
            lines = cleaned.split('\n')
            content_lines = []
            skip_mode = False
            for line in lines:
                # Skip lines that look like explanatory headers
                if re.match(r'^(?:Explanation|Note|Changes made|Here\'s what|I (?:have )?(?:fixed|corrected)|The following):', line, re.IGNORECASE):
                    skip_mode = True
                    continue
                if skip_mode and line.strip() == '':
                    skip_mode = False
                    continue
                if not skip_mode:
                    content_lines.append(line)
            cleaned = '\n'.join(content_lines).strip()
        
        return cleaned
    
    def _generate(self, prompt: str) -> str:
        """Generate response from LLM."""
        try:
            if self.provider == "gemini":
                response = self.model.generate_content(prompt)
                return response.text
            elif self.provider == "xai":
                return self._xai_generate(prompt)
        except Exception as e:
            logging.error(f"LLM generation failed: {e}")
            return ""
    
    def _xai_generate(self, prompt: str) -> str:
        """Generate response using xAI API (OpenAI-compatible)."""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": self.xai_model,
            "messages": [{"role": "user", "content": prompt}],
            "max_tokens": 2000
        }
        try:
            response = requests.post(self.xai_endpoint, headers=headers, json=payload, timeout=60)
            response.raise_for_status()
            data = response.json()
            return data.get("choices", [{}])[0].get("message", {}).get("content", "")
        except Exception as e:
            logging.error(f"xAI API call failed: {e}")
            return ""


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
        4: {'key': 'formatting_issues', 'name': 'backtick-spacing', 'desc': 'Fix missing spaces around backticks', 'llm': False},
        5: {'key': 'backtick_errors', 'name': 'backtick-errors', 'desc': 'Fix backtick errors (spaces inside backticks)', 'llm': False},
        6: {'key': 'heading_hierarchy_issues', 'name': 'heading-hierarchy', 'desc': 'Fix heading hierarchy violations (skipped levels)', 'llm': False},
        7: {'key': 'header_spacing_issues', 'name': 'header-spacing', 'desc': 'Fix markdown headers missing space (####Title -> #### Title)', 'llm': False},
        8: {'key': 'html_comment_issues', 'name': 'html-comments', 'desc': 'Fix HTML comments (remove <!-- --> markers, keep content)', 'llm': False},
        9: {'key': 'grammar_issues', 'name': 'grammar', 'desc': 'Fix grammar and spelling issues (requires --llm)', 'llm': True},
        10: {'key': 'md_artifacts', 'name': 'markdown-artifacts', 'desc': 'Fix unrendered markdown artifacts (requires --llm)', 'llm': True},
        11: {'key': 'indentation_issues', 'name': 'indentation', 'desc': 'Fix indentation issues (requires --llm)', 'llm': True},
        12: {'key': 'malformed_code_block_issues', 'name': 'malformed-codeblocks', 'desc': 'Fix malformed code blocks (mismatched backticks, inline->fenced)', 'llm': False},
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
        
        This prevents false grammar errors on technical expressions and commands.
        """
        # Remove fenced code blocks (``` ... ```) - including with language specifier
        text = re.sub(r'```[\w]*\s*[\s\S]*?```', ' ', text)
        
        # Remove inline code (` ... `) - be careful not to match empty backticks
        text = re.sub(r'`[^`]+`', ' ', text)
        
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
                with self.grammar_tool_lock:
                    matches = tool.check(chunk)
                
                # Filter false positives
                false_positive_rules = {
                    'MORFOLOGIK_RULE_EN_US', 'UPPERCASE_SENTENCE_START',
                    'MORFOLOGIK_RULE_EN_GB', 'COMMA_PARENTHESIS_WHITESPACE'
                }
                
                seen = set()
                for match in matches:
                    rule_id = getattr(match, 'rule_id', match.category)
                    if rule_id in false_positive_rules:
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
        """
        issues = []
        
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
    
    def _find_directory_case_insensitive(self, parent_dir: str, target_name: str) -> Optional[str]:
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
    
    def _calculate_content_similarity(self, text1: str, text2: str) -> float:
        """Calculate similarity between two text strings using word overlap.
        
        Uses Jaccard similarity on word sets for a fast, reasonable approximation.
        
        Args:
            text1: First text string
            text2: Second text string
            
        Returns:
            Similarity score between 0.0 and 1.0
        """
        # Normalize: lowercase, extract words only
        def extract_words(text: str) -> Set[str]:
            # Remove markdown syntax and extract alphanumeric words
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
    
    def _find_matching_file_by_content(self, parent_dir: str, webpage_text: str, 
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
                    
                    score = self._calculate_content_similarity(webpage_text, file_content)
                    
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
    
    def _map_url_to_local_path(self, page_url: str, webpage_text: str = None) -> Optional[str]:
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
            
            # Remove trailing slash for consistent handling
            path = path.rstrip('/')
            
            # Base content directories to search (in order of preference)
            content_bases = [
                os.path.join(self.local_webserver, 'content', self.language),  # e.g., /var/www/photon-site/content/en
                os.path.join(self.local_webserver, 'content'),                  # e.g., /var/www/photon-site/content
                self.local_webserver,                                            # e.g., /var/www/photon-site
            ]
            
            if not path:
                # Root path - look for _index.md at content root
                for content_base in content_bases:
                    if not os.path.isdir(content_base):
                        continue
                    for md_file in ['_index.md', 'index.md']:
                        candidate = os.path.join(content_base, md_file)
                        if os.path.isfile(candidate):
                            return candidate
                return None
            
            path_parts = path.split('/')
            
            # Track the deepest successfully resolved directory for content-based fallback
            deepest_resolved_dir = None
            
            # Try each content base with case-insensitive directory traversal
            for content_base in content_bases:
                if not os.path.isdir(content_base):
                    continue
                
                # Walk through path components using case-insensitive matching
                current_dir = content_base
                resolved_parts = []
                all_parts_resolved = True
                
                for i, part in enumerate(path_parts):
                    is_last_part = (i == len(path_parts) - 1)
                    
                    # First try exact match (faster)
                    exact_path = os.path.join(current_dir, part)
                    if os.path.isdir(exact_path):
                        current_dir = exact_path
                        resolved_parts.append(part)
                        continue
                    
                    # For the last component, also check if it's a file
                    if is_last_part and os.path.isfile(exact_path + '.md'):
                        return exact_path + '.md'
                    
                    # Try case-insensitive match for directory
                    found_dir = self._find_directory_case_insensitive(current_dir, part)
                    if found_dir and os.path.isdir(found_dir):
                        current_dir = found_dir
                        resolved_parts.append(os.path.basename(found_dir))
                        continue
                    
                    # For the last component, try case-insensitive file match
                    if is_last_part:
                        found_file = self._find_directory_case_insensitive(current_dir, part + '.md')
                        if found_file and os.path.isfile(found_file):
                            return found_file
                    
                    # Path component not found - save current_dir for content-based fallback
                    # This is the deepest directory we could resolve
                    if current_dir != content_base:
                        deepest_resolved_dir = current_dir
                    
                    all_parts_resolved = False
                    break
                
                if all_parts_resolved and os.path.isdir(current_dir):
                    # Found the directory, now look for the markdown file
                    for md_file in ['_index.md', 'index.md', 'README.md']:
                        candidate = os.path.join(current_dir, md_file)
                        if os.path.isfile(candidate):
                            self.logger.debug(f"Mapped {page_url} -> {candidate}")
                            return candidate
                    
                    # No _index.md in this directory - save for content-based fallback
                    deepest_resolved_dir = current_dir
                    self.logger.debug(f"Directory exists but no _index.md: {current_dir}")
            
            # Fallback: Try content-based matching in the deepest resolved directory
            if deepest_resolved_dir and webpage_text:
                self.logger.debug(f"Trying content-based matching in: {deepest_resolved_dir}")
                content_match = self._find_matching_file_by_content(deepest_resolved_dir, webpage_text)
                if content_match:
                    self.logger.info(f"Content-based match for {page_url}: {content_match}")
                    return content_match
            
            self.logger.debug(f"No local file found for {page_url}")
            return None
            
        except Exception as e:
            self.logger.error(f"Failed to map URL to local path: {e}")
            return None
    
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
            
            # Check for formatting issues (missing spaces around backticks)
            formatting_issues = self._check_missing_spaces_around_backticks(page_url, text_content)
            
            # Check for backtick errors (unclosed code blocks, spaces inside backticks)
            backtick_errors = self._check_backtick_errors(page_url, text_content)
            
            # Check for malformed code blocks (mismatched backticks, inline->fenced)
            malformed_code_block_issues = self._check_malformed_code_blocks(page_url, text_content)
            
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
            
            # Apply fixes if running with --gh-pr
            if self.command == 'run' and self.gh_pr:
                all_issues = {
                    'grammar_issues': grammar_issues,
                    'md_artifacts': md_artifacts,
                    'orphan_links': orphan_links,
                    'orphan_images': orphan_images,
                    'formatting_issues': formatting_issues,
                    'backtick_errors': backtick_errors,
                    'malformed_code_block_issues': malformed_code_block_issues,
                    'indentation_issues': indentation_issues,
                    'shell_prompt_issues': shell_prompt_issues,
                    'mixed_cmd_output_issues': mixed_cmd_output_issues,
                    'deprecated_url_issues': deprecated_url_issues,
                    'vmware_spelling_issues': vmware_spelling_issues,
                    'broken_email_issues': broken_email_issues,
                    'header_spacing_issues': header_spacing_issues,
                    'html_comment_issues': html_comment_issues,
                    'heading_hierarchy_issues': heading_hierarchy_issues,
                }
                self._apply_fixes(page_url, all_issues, text_content)
            
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
    
    def _apply_fixes(self, page_url: str, issues: Dict[str, List], webpage_text: str = None):
        """Apply fixes to local markdown files.
        
        Args:
            page_url: The URL of the page being fixed
            issues: Dictionary of issue types to their detected issues:
                - grammar_issues: Grammar/spelling issues
                - md_artifacts: Unrendered markdown artifacts
                - orphan_links: Broken links
                - orphan_images: Broken images
                - formatting_issues: Missing spaces around backticks
                - backtick_errors: Malformed backticks (spaces inside, unclosed)
                - malformed_code_block_issues: Mismatched backticks (e.g., `cmd``` -> fenced)
                - shell_prompt_issues: Shell prompts in code blocks
                - deprecated_url_issues: Deprecated VMware URLs
                - vmware_spelling_issues: Incorrect VMware spelling
                - broken_email_issues: Broken email addresses (domain split with whitespace)
                - mixed_cmd_output_issues: Mixed command/output in code blocks
                - heading_hierarchy_issues: Heading hierarchy violations (skipped levels, wrong first heading)
            webpage_text: Optional text content from the webpage for content-based file matching
        """
        local_path = self._map_url_to_local_path(page_url, webpage_text)
        if not local_path or not os.path.exists(local_path):
            self.logger.warning(f"No local file found for {page_url} (local_webserver={self.local_webserver})")
            return
        
        self.logger.info(f"Found local file for {page_url}: {local_path}")
        
        try:
            with self.file_edit_lock:
                with open(local_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                
                original = content
                
                # =========================================================
                # Deterministic fixes (no LLM required)
                # Only apply fixes that are enabled via --fix parameter
                # =========================================================
                
                # Fix broken email addresses (domain split with whitespace)
                # This must be done BEFORE VMware spelling fix to avoid false positives
                broken_email_issues = issues.get('broken_email_issues', [])
                if broken_email_issues and 'broken_email_issues' in self.enabled_fix_keys:
                    content = self._fix_broken_email_addresses(content)
                
                # Fix VMware spelling (vmware -> VMware)
                vmware_issues = issues.get('vmware_spelling_issues', [])
                if vmware_issues and 'vmware_spelling_issues' in self.enabled_fix_keys:
                    content = self._fix_vmware_spelling(content)
                
                # Fix deprecated VMware URLs
                deprecated_url_issues = issues.get('deprecated_url_issues', [])
                if deprecated_url_issues and 'deprecated_url_issues' in self.enabled_fix_keys:
                    content = self._fix_deprecated_urls(content)
                
                # Fix missing spaces around backticks
                formatting_issues = issues.get('formatting_issues', [])
                if formatting_issues and 'formatting_issues' in self.enabled_fix_keys:
                    content = self._fix_backtick_spacing(content)
                
                # Fix backtick errors (spaces inside backticks)
                backtick_errors = issues.get('backtick_errors', [])
                if backtick_errors and 'backtick_errors' in self.enabled_fix_keys:
                    content = self._fix_backtick_errors(content)
                
                # Fix malformed code blocks (mismatched backticks, inline->fenced)
                # Note: Detection must be done on markdown source, not rendered HTML
                if 'malformed_code_block_issues' in self.enabled_fix_keys:
                    # Detect malformed code blocks directly in markdown source
                    md_malformed_issues = self._check_malformed_code_blocks(page_url, content)
                    if md_malformed_issues:
                        content = self._fix_malformed_code_blocks(content)
                
                # Fix shell prompts in code blocks (in markdown source) - this is a FEATURE, not a fix
                shell_prompt_issues = issues.get('shell_prompt_issues', [])
                if shell_prompt_issues and 'shell_prompt_issues' in self.enabled_feature_keys:
                    content = self._fix_shell_prompts_in_markdown(content)
                
                # Fix heading hierarchy violations (H1 -> H3 skips, wrong first heading)
                heading_hierarchy_issues = issues.get('heading_hierarchy_issues', [])
                if heading_hierarchy_issues and 'heading_hierarchy_issues' in self.enabled_fix_keys:
                    content, hierarchy_fixes = self._fix_heading_hierarchy(content)
                    if hierarchy_fixes:
                        self.logger.info(f"Applied {len(hierarchy_fixes)} heading hierarchy fixes to {local_path}")
                
                # Fix markdown headers missing space after hash symbols (####Title -> #### Title)
                header_spacing_issues = issues.get('header_spacing_issues', [])
                if header_spacing_issues and 'header_spacing_issues' in self.enabled_fix_keys:
                    content = self._fix_markdown_header_spacing(content)
                
                # Fix HTML comments by removing markers and preserving inner content
                html_comment_issues = issues.get('html_comment_issues', [])
                if html_comment_issues and 'html_comment_issues' in self.enabled_fix_keys:
                    content = self._fix_html_comments(content)
                
                # =========================================================
                # LLM-based fixes (require LLM client)
                # Only apply fixes that are enabled via --fix parameter
                # =========================================================
                
                # Apply grammar fixes via LLM if available
                grammar_issues = issues.get('grammar_issues', [])
                if grammar_issues and self.llm_client and 'grammar_issues' in self.enabled_fix_keys:
                    try:
                        fixed = self.llm_client.fix_grammar(content, grammar_issues)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM grammar fix failed: {e}")
                
                # Apply markdown fixes via LLM if available
                md_artifacts = issues.get('md_artifacts', [])
                if md_artifacts and self.llm_client and 'md_artifacts' in self.enabled_fix_keys:
                    try:
                        fixed = self.llm_client.fix_markdown(content, md_artifacts)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM markdown fix failed: {e}")
                
                # Fix mixed command/output code blocks via LLM - this is a FEATURE, not a fix
                mixed_cmd_output_issues = issues.get('mixed_cmd_output_issues', [])
                if mixed_cmd_output_issues and self.llm_client and 'mixed_cmd_output_issues' in self.enabled_feature_keys:
                    try:
                        content = self._fix_mixed_command_output_llm(content, mixed_cmd_output_issues)
                    except Exception as e:
                        self.logger.error(f"LLM mixed command/output fix failed: {e}")
                
                # Fix indentation issues via LLM
                indentation_issues = issues.get('indentation_issues', [])
                if indentation_issues and self.llm_client and 'indentation_issues' in self.enabled_fix_keys:
                    try:
                        fixed = self.llm_client.fix_indentation(content, indentation_issues)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM indentation fix failed: {e}")
                
                # Translate if language != en
                if self.language != 'en' and self.llm_client:
                    try:
                        translated = self.llm_client.translate(content, self.language)
                        if translated:
                            content = translated
                    except Exception as e:
                        self.logger.error(f"LLM translation failed: {e}")
                
                # Write back if changed
                if content != original:
                    with open(local_path, 'w', encoding='utf-8') as f:
                        f.write(content)
                    self.modified_files.add(local_path)
                    self.fixes_applied += 1
                    
                    # Log what types of fixes were applied (only those that were enabled)
                    applied_fixes = []
                    if issues.get('broken_email_issues') and 'broken_email_issues' in self.enabled_fix_keys:
                        applied_fixes.append('broken emails')
                    if issues.get('vmware_spelling_issues') and 'vmware_spelling_issues' in self.enabled_fix_keys:
                        applied_fixes.append('VMware spelling')
                    if issues.get('deprecated_url_issues') and 'deprecated_url_issues' in self.enabled_fix_keys:
                        applied_fixes.append('deprecated URLs')
                    if issues.get('formatting_issues') and 'formatting_issues' in self.enabled_fix_keys:
                        applied_fixes.append('backtick spacing')
                    if issues.get('backtick_errors') and 'backtick_errors' in self.enabled_fix_keys:
                        applied_fixes.append('backtick errors')
                    if issues.get('malformed_code_block_issues') and 'malformed_code_block_issues' in self.enabled_fix_keys:
                        applied_fixes.append('malformed code blocks')
                    if issues.get('shell_prompt_issues') and 'shell_prompt_issues' in self.enabled_feature_keys:
                        applied_fixes.append('shell prompts')
                    if issues.get('heading_hierarchy_issues') and 'heading_hierarchy_issues' in self.enabled_fix_keys:
                        applied_fixes.append('heading hierarchy')
                    if issues.get('header_spacing_issues') and 'header_spacing_issues' in self.enabled_fix_keys:
                        applied_fixes.append('header spacing')
                    if issues.get('html_comment_issues') and 'html_comment_issues' in self.enabled_fix_keys:
                        applied_fixes.append('HTML comments')
                    if issues.get('grammar_issues') and self.llm_client and 'grammar_issues' in self.enabled_fix_keys:
                        applied_fixes.append('grammar (LLM)')
                    if issues.get('md_artifacts') and self.llm_client and 'md_artifacts' in self.enabled_fix_keys:
                        applied_fixes.append('markdown (LLM)')
                    if issues.get('mixed_cmd_output_issues') and self.llm_client and 'mixed_cmd_output_issues' in self.enabled_feature_keys:
                        applied_fixes.append('mixed cmd/output (LLM)')
                    if issues.get('indentation_issues') and self.llm_client and 'indentation_issues' in self.enabled_fix_keys:
                        applied_fixes.append('indentation (LLM)')
                    
                    fixes_str = ', '.join(applied_fixes) if applied_fixes else 'content changes'
                    self.logger.info(f"Applied fixes to {local_path}: {fixes_str}")
                    print(f"  [FIX] {os.path.basename(local_path)}: {fixes_str}")
                    
                    # Incremental commit/push/PR for each fix (when --gh-pr is enabled)
                    if self.gh_pr and self.repo_cloned:
                        self._incremental_commit_push_and_pr(local_path, applied_fixes)
                else:
                    self.logger.debug(f"No changes needed for {local_path}")
                
        except Exception as e:
            self.logger.error(f"Failed to apply fixes to {local_path}: {e}")
    
    def _fix_vmware_spelling(self, content: str) -> str:
        """Fix incorrect VMware spelling in content.
        
        Replaces variations like 'vmware', 'Vmware', 'VMWare', 'VMWARE' with 'VMware'.
        Preserves:
        - Code blocks (fenced and inline)
        - URLs (with or without protocol, including github.com/vmware/*)
        - Domain-like patterns (e.g., packages.vmware.com)
        - File paths (e.g., /var/log/VMware-imc/, /etc/pki/rpm-gpg/VMware-RPM-GPG-KEY)
        - Email addresses (e.g., linux-packages@VMware.com)
        - Broken email addresses (e.g., linux-packages@vmware.     com)
        """
        # Split content to preserve code blocks, URLs, file paths, and emails
        # Match: fenced code blocks, inline code, URLs with protocol, domain patterns,
        # file paths (Unix-style), email addresses, and broken email addresses
        # NOTE: URL patterns must be GREEDY (+) not non-greedy (+?) to capture full URLs
        # NOTE: Broken email pattern must come BEFORE normal email pattern to match first
        # NOTE: github.com/vmware/* pattern added to preserve GitHub organization paths
        preserve_pattern = re.compile(
            r'('
            r'```[\s\S]*?```'                          # Fenced code blocks
            r'|`[^`]+`'                                # Inline code
            r'|https?://[^\s<>"\')\]]+' # URLs with protocol (greedy to capture full URL)
            r'|www\.[^\s<>"\')\]]+' # www URLs (greedy to capture full URL)
            r'|github\.com/[^\s<>"\')\]]+' # GitHub paths without protocol
            r'|gitlab\.com/[^\s<>"\')\]]+' # GitLab paths without protocol
            r'|bitbucket\.org/[^\s<>"\')\]]+' # Bitbucket paths without protocol
            r'|[a-zA-Z0-9-]+\.vmware\.[a-zA-Z0-9-]+[^\s<>"\')\]]*'  # Domain patterns
            r'|[a-zA-Z0-9-]+\.(com|org|net|io|edu|gov)/[^\s<>"\')\]]*'  # Domain/path without protocol
            r'|(?:/[\w.-]+)+/?'                        # Unix file paths (e.g., /var/log/VMware-imc/)
            r'|[\w.+-]+@[\w.-]+\.\s+\w{2,6}'           # Broken email addresses (domain.  tld)
            r'|[\w.+-]+@[\w.-]+\.\w+'                  # Email addresses
            r')',
            re.IGNORECASE
        )
        
        parts = preserve_pattern.split(content)
        
        for i, part in enumerate(parts):
            # Handle None values (from non-capturing groups in split)
            if part is None:
                parts[i] = ''
                continue
            if not part:
                continue
            # Skip code blocks
            if part.startswith('```') or part.startswith('`'):
                continue
            # Skip URLs
            if part.startswith('http://') or part.startswith('https://') or part.startswith('www.'):
                continue
            # Skip GitHub/GitLab/Bitbucket paths (e.g., github.com/vmware/photon)
            if re.match(r'^(?:github|gitlab)\.com/', part, re.IGNORECASE) or part.startswith('bitbucket.org/'):
                continue
            # Skip domain-like patterns (e.g., packages.vmware.com)
            if re.match(r'^[a-zA-Z0-9-]+\.vmware\.[a-zA-Z0-9-]+', part, re.IGNORECASE):
                continue
            # Skip domain/path patterns (e.g., example.com/path)
            if re.match(r'^[a-zA-Z0-9-]+\.(com|org|net|io|edu|gov)/', part, re.IGNORECASE):
                continue
            # Skip file paths (start with / and contain path segments)
            if part.startswith('/') and '/' in part[1:]:
                continue
            # Skip broken email addresses (domain split with whitespace)
            if '@' in part and re.match(r'^[\w.+-]+@[\w.-]+\.\s+\w{2,6}$', part, re.IGNORECASE):
                continue
            # Skip email addresses
            if '@' in part and re.match(r'^[\w.+-]+@[\w.-]+\.\w+$', part, re.IGNORECASE):
                continue
            # Fix VMware spelling in regular text
            parts[i] = self.VMWARE_SPELLING_PATTERN.sub('VMware', part)
        
        return ''.join(parts)
    
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
    
    def _fix_deprecated_urls(self, content: str) -> str:
        """Fix deprecated packages.vmware.com URLs, VDDK URL, AWS EC2 CLI URL, and bosh-stemcell URL.
        
        Replaces https://packages.vmware.com/* with https://packages.broadcom.com/*
        Replaces deprecated VDDK URL with new Broadcom developer URL.
        Replaces deprecated AWS EC2 CLI URLs with new AWS CLI install guide URL.
        Replaces deprecated CloudFoundry bosh-stemcell URL with new main branch URL.
        """
        # Replace the base URL while preserving the path
        def replace_url(match):
            old_url = match.group(0)
            # Extract path after packages.vmware.com
            path_match = re.search(r'packages\.vmware\.com(/[^\s"\'<>]*)?', old_url)
            if path_match:
                path = path_match.group(1) or ''
                return f'https://packages.broadcom.com{path}'
            return old_url
        
        # Fix packages.vmware.com URLs
        content = self.DEPRECATED_VMWARE_URL.sub(replace_url, content)
        
        # Fix deprecated VDDK URLs (multiple sources)
        # First, try to replace full markdown link including text (VDDK 6.0 -> VDDK 6.7)
        content = content.replace(self.DEPRECATED_VDDK_60_LINK, self.VDDK_67_LINK_REPLACEMENT)
        # Then replace any remaining deprecated VDDK URLs
        for vddk_url in self.DEPRECATED_VDDK_URLS:
            content = content.replace(vddk_url, self.VDDK_URL_REPLACEMENT)
        
        # Fix deprecated AWS EC2 CLI URLs (both http and https versions)
        for aws_url in self.DEPRECATED_AWS_EC2_CLI_URLS:
            content = content.replace(aws_url, self.AWS_EC2_CLI_URL_REPLACEMENT)
        
        # Fix deprecated OVFTOOL URL
        content = content.replace(self.DEPRECATED_OVFTOOL_URL, self.OVFTOOL_URL_REPLACEMENT)
        
        # Fix deprecated CloudFoundry bosh-stemcell URL
        content = content.replace(self.DEPRECATED_BOSH_STEMCELL_URL, self.BOSH_STEMCELL_URL_REPLACEMENT)
        
        return content
    
    def _fix_backtick_spacing(self, content: str) -> str:
        """Fix missing spaces around backticks.
        
        Only fixes:
        - 'word`code`' -> 'word `code`' (missing space BEFORE opening backtick)
        - '`code`word' -> '`code` word' (missing space AFTER closing backtick)
        
        Does NOT add space before ending backtick (inside the code).
        """
        # Fix missing space before opening backtick (word immediately before backtick)
        content = self.MISSING_SPACE_BEFORE_BACKTICK.sub(r'\1 \2', content)
        
        # Fix missing space after closing backtick (word immediately after backtick)
        content = self.MISSING_SPACE_AFTER_BACKTICK.sub(r'\1 \2', content)
        
        return content
    
    def _fix_backtick_errors(self, content: str) -> str:
        """Fix backtick formatting errors in markdown content.
        
        Fixes:
        - Spaces after opening backtick: "` code`" -> "`code`"
        - Spaces before closing backtick: "`code `" -> "`code`"
        - Spaces on both sides: "` code `" -> "`code`"
        
        Note: Does NOT fix unclosed backticks as that requires manual review
        to determine the intended scope of the code block.
        """
        # First, handle fenced code blocks - we should not modify their content
        # Split content by fenced code blocks to preserve them
        fenced_pattern = re.compile(r'(```[\s\S]*?```)')
        parts = fenced_pattern.split(content)
        
        for i, part in enumerate(parts):
            # Skip fenced code blocks (odd indices after split with capturing group)
            if part.startswith('```'):
                continue
            
            # Fix inline code with spaces on both sides first (more specific)
            # "` code `" -> "`code`"
            part = self.INLINE_CODE_SPACES_BOTH.sub(lambda m: f'`{m.group(1).strip()}`', part)
            
            # Fix inline code with space after opening backtick
            # "` code`" -> "`code`"
            part = self.INLINE_CODE_SPACE_AFTER_OPEN.sub(lambda m: f'`{m.group(1).strip()}`', part)
            
            # Fix inline code with space before closing backtick
            # "`code `" -> "`code`"
            part = self.INLINE_CODE_SPACE_BEFORE_CLOSE.sub(lambda m: f'`{m.group(1).strip()}`', part)
            
            parts[i] = part
        
        return ''.join(parts)
    
    def _fix_malformed_code_blocks(self, content: str) -> str:
        """Fix malformed code blocks in markdown content.
        
        Fixes:
        - Excess backticks in code block closing: ```bash\\ncmd\\n````` -> ```bash\\ncmd\\n```
        - Single backtick + content + 3+ backticks: `command````` -> ```bash\\ncommand\\n```
        - Consecutive inline commands: `cmd1`\\n`cmd2` -> ```bash\\ncmd1\\ncmd2\\n```
        - Stray backticks inside fenced code blocks: ```\\ncmd`\\n``` -> ```\\ncmd\\n```
        
        These patterns indicate the author intended to create fenced code blocks
        but used incorrect backtick syntax.
        """
        # Fix pattern -1: Excess backticks in code block closing (````` instead of ```)
        # This must be done first before other patterns
        # Matches: 4+ backticks at start of a line (closing a code block incorrectly)
        content = re.sub(r'^(`{4,})$', '```', content, flags=re.MULTILINE)
        
        # Also fix excess backticks inline (e.g., "cmd`````" at end of line in a code block)
        # This catches patterns like "git clone url`````"
        content = re.sub(r'(`{4,})(\s*$)', '```\\2', content, flags=re.MULTILINE)
        
        # Fix pattern 0: Stray backticks inside fenced code blocks
        # This fixes lines inside code blocks that have trailing/leading backticks
        def fix_stray_backticks_in_block(match):
            full_block = match.group(0)
            lines = full_block.split('\n')
            if len(lines) < 2:
                return full_block
            
            # Keep first line (```lang) and last line (```) unchanged
            result = [lines[0]]
            for line in lines[1:-1]:
                # Remove stray backticks at start/end of code lines
                # But preserve proper inline code patterns
                cleaned = line
                # Remove trailing single backtick (but not ```)
                if cleaned.endswith('`') and not cleaned.endswith('```'):
                    cleaned = cleaned[:-1]
                # Remove leading single backtick (but not ```)
                stripped = cleaned.lstrip()
                if stripped.startswith('`') and not stripped.startswith('```'):
                    indent = len(cleaned) - len(stripped)
                    cleaned = cleaned[:indent] + stripped[1:]
                result.append(cleaned)
            result.append(lines[-1])
            return '\n'.join(result)
        
        content = re.sub(r'```[\w]*\n[\s\S]*?```', fix_stray_backticks_in_block, content)
        
        # Fix pattern 1: `content``` -> proper fenced code block
        # This pattern indicates someone started with inline code but ended with fenced syntax
        def fix_single_triple(match):
            content_text = match.group(1).strip()
            # Determine language hint based on content
            lang = 'bash'
            if content_text.startswith('python') or 'import ' in content_text:
                lang = 'python'
            return f'```{lang}\n{content_text}\n```'
        
        content = self.MALFORMED_CODE_BLOCK_SINGLE_TRIPLE.sub(fix_single_triple, content)
        
        # Fix pattern 2: Consecutive inline code blocks that should be fenced
        # Look for 2+ consecutive lines of `command` that should be a code block
        # This is more complex - we need to find all consecutive inline code lines
        lines = content.split('\n')
        result_lines = []
        i = 0
        
        while i < len(lines):
            line = lines[i]
            # Check if this line is a standalone inline code (command)
            # Pattern: optional indent + `command` (entire line is just inline code)
            inline_match = re.match(r'^(\s*)`([^`]+)`\s*$', line)
            
            if inline_match:
                indent = inline_match.group(1)
                commands = [inline_match.group(2)]
                
                # Look ahead for more consecutive inline commands
                j = i + 1
                while j < len(lines):
                    next_line = lines[j]
                    next_match = re.match(r'^\s*`([^`]+)`\s*$', next_line)
                    if next_match:
                        commands.append(next_match.group(1))
                        j += 1
                    else:
                        break
                
                # If we found 2+ consecutive inline commands, convert to fenced block
                if len(commands) >= 2:
                    # Determine language from content
                    lang = 'bash'
                    for cmd in commands:
                        if cmd.startswith('python') or 'import ' in cmd:
                            lang = 'python'
                            break
                    
                    result_lines.append(f'{indent}```{lang}')
                    for cmd in commands:
                        result_lines.append(f'{indent}{cmd}')
                    result_lines.append(f'{indent}```')
                    i = j
                    continue
            
            result_lines.append(line)
            i += 1
        
        return '\n'.join(result_lines)
    
    def _fix_shell_prompts_in_markdown(self, content: str) -> str:
        """Remove shell prompt prefixes from code blocks in markdown.
        
        Also adds language hints to code blocks without them:
        - Adds 'python' if content looks like Python code
        - Adds 'console' otherwise for shell commands
        
        Transforms:
        ```
        $ ls -la
        ```
        
        To:
        ```console
        ls -la
        ```
        """
        # Find all fenced code blocks
        def fix_code_block(match):
            code_block = match.group(0)
            lines = code_block.split('\n')
            
            if not lines:
                return code_block
            
            # Check if the opening line has a language specified
            opening_line = lines[0]
            has_language = len(opening_line) > 3  # More than just "```"
            
            fixed_lines = []
            code_content_lines = []
            
            for line in lines[1:-1]:  # Skip first and last lines (``` markers)
                fixed_line = line
                for pattern in self.SHELL_PROMPT_PATTERNS:
                    prompt_match = pattern.match(line)
                    if prompt_match:
                        # Remove the prompt, keep leading whitespace and command
                        # Pattern groups: (1) leading whitespace, (2) prompt, (3) command
                        leading_ws = prompt_match.group(1)
                        command = prompt_match.group(3)
                        fixed_line = leading_ws + command
                        break
                code_content_lines.append(fixed_line)
            
            # Determine language if not specified
            if not has_language and code_content_lines:
                code_text = '\n'.join(code_content_lines)
                if self._looks_like_python(code_text):
                    opening_line = '```python'
                else:
                    opening_line = '```console'
            
            fixed_lines.append(opening_line)
            fixed_lines.extend(code_content_lines)
            if lines:
                fixed_lines.append(lines[-1])  # Keep the closing ```
            
            return '\n'.join(fixed_lines)
        
        # Match fenced code blocks
        content = re.sub(r'```[\w]*\n[\s\S]*?```', fix_code_block, content)
        
        return content
    
    def _looks_like_python(self, code: str) -> bool:
        """Heuristic to detect if code content looks like Python.
        
        Returns True if the code appears to be Python, False otherwise.
        """
        python_indicators = [
            r'^\s*import\s+\w+',           # import statements
            r'^\s*from\s+\w+\s+import',    # from X import Y
            r'^\s*def\s+\w+\s*\(',         # function definitions
            r'^\s*class\s+\w+',            # class definitions
            r'^\s*if\s+.*:$',              # if statements with colon
            r'^\s*for\s+\w+\s+in\s+',      # for loops
            r'^\s*while\s+.*:$',           # while loops
            r'^\s*print\s*\(',             # print function
            r'^\s*return\s+',              # return statements
            r'^\s*#\s*!.*python',          # shebang
            r'^\s*"""',                    # docstrings
            r"^\s*'''",                    # docstrings
            r'^\s*@\w+',                   # decorators
            r'\s*=\s*\[.*\]',              # list assignments
            r'\s*=\s*\{.*\}',              # dict assignments
            r'\.append\(',                 # list methods
            r'\.format\(',                 # string format
            r'f".*\{',                     # f-strings
            r"f'.*\{",                     # f-strings
        ]
        
        for pattern in python_indicators:
            if re.search(pattern, code, re.MULTILINE):
                return True
        
        return False
    
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
                    time.sleep(0.5)
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
                
                # Log the fix for PR body (before git operations)
                self.fixed_files_log.append({
                    'file': rel_path,
                    'fixes': fixes_applied,
                    'timestamp': datetime.datetime.now().isoformat()
                })
                
                # Change to repo directory for git operations
                original_cwd = os.getcwd()
                os.chdir(self.temp_dir)
                
                try:
                    # Add the file
                    subprocess.run(['git', 'add', rel_path], check=True, capture_output=True)
                    
                    # Check if there are changes to commit
                    result = subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True)
                    if not result.stdout.strip():
                        self.logger.info(f"No changes to commit for {rel_path}")
                        return True  # No changes but not an error
                    
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


# =============================================================================
# Argument Parsing and Validation
# =============================================================================

def validate_url(url: str) -> str:
    """Validate URL format."""
    if not url:
        raise argparse.ArgumentTypeError("URL is required")
    
    parsed = urllib.parse.urlparse(url)
    
    if not parsed.scheme:
        url = f"https://{url}"
        parsed = urllib.parse.urlparse(url)
    
    if parsed.scheme not in ('http', 'https'):
        raise argparse.ArgumentTypeError(f"Invalid URL scheme '{parsed.scheme}'. Must be http or https.")
    
    if not parsed.netloc:
        raise argparse.ArgumentTypeError("Invalid URL: missing domain")
    
    return url


def validate_path(path: str) -> str:
    """Validate filesystem path exists."""
    if not path:
        return path
    
    expanded = os.path.expanduser(path)
    if not os.path.exists(expanded):
        raise argparse.ArgumentTypeError(f"Path does not exist: {path}")
    
    return expanded


def validate_parallel(value: str) -> int:
    """Validate parallel workers value (1-20)."""
    try:
        ivalue = int(value)
        if ivalue < 1 or ivalue > 20:
            raise argparse.ArgumentTypeError("--parallel must be between 1 and 20")
        return ivalue
    except ValueError:
        raise argparse.ArgumentTypeError(f"Invalid integer: {value}")


def create_parser() -> argparse.ArgumentParser:
    """Create argument parser."""
    parser = argparse.ArgumentParser(
        prog=TOOL_NAME,
        description='Photon OS Documentation Lecturer - Analyze and fix documentation issues',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Commands:
  run            Execute full workflow (analyze, fix, push, PR)
  analyze        Generate report only (no fixes or git operations)
  install-tools  Install required tools (Java, language-tool-python) - requires admin
  version        Display tool version

Issue Types and Fix Modes:
  +--------------------------+-------------+---------------+---------------------------+
  | Issue Type               | Detected    | Fix Mode      | Description               |
  +--------------------------+-------------+---------------+---------------------------+
  | VMware spelling          | Always      | Automatic     | vmware -> VMware          |
  |                          |             |               | (excludes URLs, paths,    |
  |                          |             |               | emails, code blocks)      |
  | Deprecated URLs          | Always      | Automatic     | packages.vmware.com ->    |
  |                          |             |               | packages.broadcom.com     |
  | Backtick spacing         | Always      | Automatic     | word`code` -> word `code` |
  | Backtick errors          | Always      | Automatic     | ` code ` -> `code`        |
  | Heading hierarchy        | Always      | Automatic     | Fix H1->H3 skips          |
  | Grammar/spelling         | Always      | LLM-assisted  | Requires --llm flag       |
  | Markdown artifacts       | Always      | LLM-assisted  | Requires --llm flag       |
  | Indentation issues       | Always      | LLM-assisted  | Requires --llm flag       |
  | Broken links             | Always      | Report only   | Manual review needed      |
  | Broken images            | Always      | Report only   | Manual review needed      |
  | Unaligned images         | Always      | Report only   | Manual review needed      |
  | Unclosed code blocks     | Always      | Report only   | ``` or ` without closing  |
  +--------------------------+-------------+---------------+---------------------------+

Optional Features (--feature parameter):
  +--------------------------+-------------+---------------+---------------------------+
  | Feature Type             | Detected    | Apply Mode    | Description               |
  +--------------------------+-------------+---------------+---------------------------+
  | Shell prompts            | Always      | Automatic     | Remove $, #, ~, etc.      |
  | Code block language      | Always      | Automatic     | Add python/console hint   |
  | Mixed command/output     | Always      | LLM-assisted  | Requires --llm flag       |
  +--------------------------+-------------+---------------+---------------------------+

Examples:
  # Install required tools (run as root/sudo)
  sudo python3 {TOOL_NAME} install-tools

  # Analyze only
  python3 {TOOL_NAME} analyze --website https://127.0.0.1/docs-v5 --parallel 5
  
  # Full workflow with PR (automatic fixes only)
  python3 {TOOL_NAME} run \\
    --website https://127.0.0.1/docs-v5 \\
    --local-webserver /var/www/photon-site \\
    --gh-repotoken ghp_xxxxxxxxx \\
    --gh-username myuser \\
    --ghrepo-url https://github.com/myuser/photon.git \\
    --ghrepo-branch photon-hugo \\
    --ref-ghrepo https://github.com/vmware/photon.git \\
    --ref-ghbranch photon-hugo \\
    --parallel 10 \\
    --gh-pr

  # Full workflow with LLM-assisted fixes
  python3 {TOOL_NAME} run \\
    --website https://127.0.0.1/docs-v5 \\
    --local-webserver /var/www/photon-site \\
    --gh-repotoken ghp_xxxxxxxxx \\
    --gh-username myuser \\
    --ghrepo-url https://github.com/myuser/photon.git \\
    --ghrepo-branch photon-hugo \\
    --ref-ghrepo https://github.com/vmware/photon.git \\
    --ref-ghbranch photon-hugo \\
    --parallel 10 \\
    --gh-pr \\
    --llm gemini --GEMINI_API_KEY your_api_key

  # Apply only specific fixes (e.g., VMware spelling and deprecated URLs)
  python3 {TOOL_NAME} run \\
    --website https://127.0.0.1/docs-v5 \\
    --local-webserver /var/www/photon-site \\
    --gh-pr --fix 2,3

Selective Fix Application (--fix parameter):
  The --fix parameter allows selecting specific fixes to apply. By default, all
  fixes are applied when using --gh-pr. Use --list-fixes to see all available fixes.

  Syntax: --fix SPEC where SPEC can be:
    - Single ID:     --fix 1
    - Multiple IDs:  --fix 1,2,3
    - Range:         --fix 1-5
    - Mixed:         --fix 1,3,5-9
    - All:           --fix all (default behavior)

  Available fixes (use --list-fixes for details):
    ID  Name                  Description                                    [LLM]
    --  --------------------  ---------------------------------------------  -----
     1  broken-emails         Fix broken email addresses                     
     2  vmware-spelling       Fix VMware spelling (vmware -> VMware)         
     3  deprecated-urls       Fix deprecated URLs (VMware, VDDK, etc.)       
     4  backtick-spacing      Fix missing spaces around backticks            
     5  backtick-errors       Fix spaces inside backticks                    
     6  heading-hierarchy     Fix heading hierarchy violations               
     7  header-spacing        Fix markdown header spacing                    
     8  html-comments         Remove HTML comment markers                    
     9  grammar               Fix grammar and spelling issues                [LLM]
    10  markdown-artifacts    Fix unrendered markdown artifacts              [LLM]
    11  indentation           Fix indentation issues                         [LLM]
    12  malformed-codeblocks  Fix malformed code blocks                      

  Note: Fixes marked [LLM] require --llm flag (gemini or xai) with API key.

Selective Feature Application (--feature parameter):
  The --feature parameter allows selecting specific features to apply.
  By default, no features are applied. Use --list-features to see all features.

  Syntax: --feature SPEC where SPEC can be:
    - Single ID:     --feature 1
    - Multiple IDs:  --feature 1,2
    - Range:         --feature 1-2
    - All:           --feature all

  Available features (use --list-features for details):
    ID  Name                  Description                                    [LLM]
    --  --------------------  ---------------------------------------------  -----
     1  shell-prompts         Remove shell prompts from code blocks          
     2  mixed-cmd-output      Separate mixed command/output in code blocks   [LLM]

  Note: Features marked [LLM] require --llm flag (gemini or xai) with API key.

Version: {VERSION}
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    # Version command
    version_parser = subparsers.add_parser('version', help='Display tool version')
    
    # Install-tools command
    install_parser = subparsers.add_parser('install-tools', help='Install required tools (Java, language-tool-python)')
    
    # Analyze command
    analyze_parser = subparsers.add_parser('analyze', help='Generate report only')
    _add_common_args(analyze_parser)
    _add_git_args(analyze_parser)  # For --fix and --list-fixes options
    
    # Run command
    run_parser = subparsers.add_parser('run', help='Execute full workflow')
    _add_common_args(run_parser)
    _add_git_args(run_parser)
    _add_llm_args(run_parser)
    
    return parser


def _add_common_args(parser: argparse.ArgumentParser):
    """Add common arguments to parser."""
    parser.add_argument(
        '--website',
        required=False,  # Not required when using --list-fixes or --list-features
        type=validate_url,
        help='Base URL of local Photon OS Nginx webserver (e.g., https://127.0.0.1/docs-v5)'
    )
    
    parser.add_argument(
        '--parallel',
        type=validate_parallel,
        default=1,
        metavar='N',
        help='Number of parallel threads (1-20, default: 1)'
    )
    
    parser.add_argument(
        '--language',
        type=str,
        default='en',
        help='Language code for grammar checking (e.g., "en", "fr", default: "en")'
    )
    
    parser.add_argument(
        '--ref-website',
        type=validate_url,
        default=None,
        help='Reference public website URL for comparison (e.g., https://vmware.github.io/photon/docs-v5)'
    )
    
    parser.add_argument(
        '--test',
        action='store_true',
        help='Run unit tests instead of analysis'
    )


def _add_git_args(parser: argparse.ArgumentParser):
    """Add git/GitHub arguments to parser."""
    parser.add_argument(
        '--local-webserver',
        type=validate_path,
        default=None,
        help='Local filesystem path to Nginx webserver root (required for --gh-pr)'
    )
    
    parser.add_argument(
        '--gh-repotoken',
        type=str,
        default=None,
        help='GitHub personal access token for authentication'
    )
    
    parser.add_argument(
        '--gh-username',
        type=str,
        default=None,
        help='GitHub username'
    )
    
    parser.add_argument(
        '--ghrepo-url',
        type=str,
        default=None,
        help='User\'s forked GitHub repo URL (e.g., https://github.com/user/photon.git)'
    )
    
    parser.add_argument(
        '--ghrepo-branch',
        type=str,
        default='photon-hugo',
        help='Branch in user\'s forked repo for pushes (default: photon-hugo)'
    )
    
    parser.add_argument(
        '--ref-ghrepo',
        type=str,
        default=None,
        help='Original GitHub repo to fork from (e.g., https://github.com/vmware/photon.git)'
    )
    
    parser.add_argument(
        '--ref-ghbranch',
        type=str,
        default='photon-hugo',
        help='Base branch in reference repo for PR target (default: photon-hugo)'
    )
    
    parser.add_argument(
        '--gh-pr',
        action='store_true',
        help='Generate fixes, commit/push, and create PR'
    )
    
    parser.add_argument(
        '--fix',
        type=str,
        default=None,
        metavar='FIXES',
        help='''Specify which fixes to apply (comma-separated IDs or ranges).
Examples: "1,2,3", "1-5", "1,3,5-9", "all"
If not specified with --gh-pr, all fixes are applied.
Use --list-fixes to see available fix IDs.'''
    )
    
    parser.add_argument(
        '--list-fixes',
        action='store_true',
        help='List all available fix types with their IDs and exit'
    )
    
    parser.add_argument(
        '--feature',
        type=str,
        default=None,
        metavar='FEATURES',
        help='''Specify which features to apply (comma-separated IDs or ranges).
Examples: "1,2", "1-2", "all"
Features are optional enhancements (shell-prompts, mixed-cmd-output).
By default, no features are applied.
Use --list-features to see available feature IDs.'''
    )
    
    parser.add_argument(
        '--list-features',
        action='store_true',
        help='List all available feature types with their IDs and exit'
    )


def _add_llm_args(parser: argparse.ArgumentParser):
    """Add LLM arguments to parser."""
    parser.add_argument(
        '--llm',
        type=str,
        choices=['gemini', 'xai'],
        default=None,
        help='LLM provider for translation/fixes ("gemini" or "xai")'
    )
    
    parser.add_argument(
        '--GEMINI_API_KEY',
        type=str,
        default=None,
        help='API key for Google Gemini LLM'
    )
    
    parser.add_argument(
        '--XAI_API_KEY',
        type=str,
        default=None,
        help='API key for xAI LLM'
    )


def validate_args(args) -> bool:
    """Validate argument combinations."""
    if args.command == 'version':
        return True
    
    if args.command in ('run', 'analyze') and not args.website:
        print(f"[ERROR] --website is required for {args.command} command", file=sys.stderr)
        return False
    
    if args.command == 'run' and args.gh_pr:
        required = ['local_webserver', 'gh_repotoken', 'gh_username', 'ghrepo_url', 'ref_ghrepo']
        missing = [r for r in required if not getattr(args, r, None)]
        if missing:
            print(f"[ERROR] --gh-pr requires: {', '.join(['--' + r.replace('_', '-') for r in missing])}", file=sys.stderr)
            return False
    
    if args.command == 'run':
        if args.llm == 'gemini':
            if not args.GEMINI_API_KEY:
                print("[ERROR] --GEMINI_API_KEY required when --llm gemini", file=sys.stderr)
                return False
            # Check if google-generativeai is installed
            if not HAS_GEMINI:
                print("[ERROR] google-generativeai library required for --llm gemini", file=sys.stderr)
                print("        Install with: pip install google-generativeai", file=sys.stderr)
                print(f"        Or run: sudo python3 {TOOL_NAME} install-tools", file=sys.stderr)
                return False
        if args.llm == 'xai' and not args.XAI_API_KEY:
            print("[ERROR] --XAI_API_KEY required when --llm xai", file=sys.stderr)
            return False
        
        if args.language != 'en' and not args.llm:
            print(f"[WARN] Translation to '{args.language}' requires --llm. Proceeding without translation.", file=sys.stderr)
    
    return True


# =============================================================================
# Unit Tests
# =============================================================================

def run_tests():
    """Run unit tests."""
    import unittest
    
    class TestDocumentationLecturer(unittest.TestCase):
        def test_validate_url(self):
            self.assertEqual(validate_url("https://example.com"), "https://example.com")
            self.assertEqual(validate_url("example.com"), "https://example.com")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_url("")
        
        def test_validate_parallel(self):
            self.assertEqual(validate_parallel("5"), 5)
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("0")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("25")
        
        def test_parse_fix_spec(self):
            """Test --fix parameter parsing."""
            parse = DocumentationLecturer.parse_fix_spec
            
            # Test single fix ID
            result = parse("1")
            self.assertEqual(result, {1})
            
            # Test multiple single fix IDs
            result = parse("1,2,3")
            self.assertEqual(result, {1, 2, 3})
            
            # Test range (use valid IDs within current FIX_TYPES)
            result = parse("5-8")
            self.assertEqual(result, {5, 6, 7, 8})
            
            # Test mixed single and range
            result = parse("1,3,5-7")
            self.assertEqual(result, {1, 3, 5, 6, 7})
            
            # Test 'all' keyword
            result = parse("all")
            self.assertEqual(result, set(DocumentationLecturer.FIX_TYPES.keys()))
            
            # Test None/empty returns all
            result = parse(None)
            self.assertEqual(result, set(DocumentationLecturer.FIX_TYPES.keys()))
            
            # Test with spaces
            result = parse("1, 2, 3")
            self.assertEqual(result, {1, 2, 3})
            
            # Test invalid fix ID
            with self.assertRaises(ValueError):
                parse("99")
            
            # Test invalid range (start > end)
            with self.assertRaises(ValueError):
                parse("9-5")
            
            # Test invalid format
            with self.assertRaises(ValueError):
                parse("abc")
        
        def test_parse_feature_spec(self):
            """Test --feature parameter parsing."""
            parse = DocumentationLecturer.parse_feature_spec
            
            # Test single feature ID
            result = parse("1")
            self.assertEqual(result, {1})
            
            # Test multiple feature IDs
            result = parse("1,2")
            self.assertEqual(result, {1, 2})
            
            # Test range
            result = parse("1-2")
            self.assertEqual(result, {1, 2})
            
            # Test 'all' keyword
            result = parse("all")
            self.assertEqual(result, set(DocumentationLecturer.FEATURE_TYPES.keys()))
            
            # Test None/empty returns all
            result = parse(None)
            self.assertEqual(result, set(DocumentationLecturer.FEATURE_TYPES.keys()))
            
            # Test invalid feature ID
            with self.assertRaises(ValueError):
                parse("99")
            
            # Test invalid format
            with self.assertRaises(ValueError):
                parse("abc")
        
        def test_markdown_patterns(self):
            patterns = DocumentationLecturer.MARKDOWN_PATTERNS
            test_text = "## Header\n* bullet\n[link](url)"
            for pattern in patterns[:3]:
                self.assertTrue(pattern.search(test_text))
        
        def test_missing_space_before_backtick(self):
            pattern = DocumentationLecturer.MISSING_SPACE_BEFORE_BACKTICK
            # Should match: word immediately followed by backtick code
            self.assertTrue(pattern.search("Clone`the`"))
            self.assertTrue(pattern.search("Run`command`"))
            # Should not match: proper spacing
            self.assertIsNone(pattern.search("Clone `the`"))
            self.assertIsNone(pattern.search("Run `command`"))
            # Should not match: inline code with space inside (invalid markdown)
            self.assertIsNone(pattern.search("Clone` the`"))
            # Critical bug fix test: should NOT match across multiple inline code blocks
            # In "The `top` tool and command`ps`", the pattern should only match "d`ps`"
            # and NOT match "p` tool and command`" (which would corrupt `top`)
            test_multi = "The `top` tool and command`ps` here"
            matches = pattern.findall(test_multi)
            self.assertEqual(len(matches), 1, "Should find exactly one match")
            self.assertEqual(matches[0], ('d', '`ps`'), "Should match 'd`ps`' not spanning across `top`")
        
        def test_missing_space_after_backtick(self):
            pattern = DocumentationLecturer.MISSING_SPACE_AFTER_BACKTICK
            # Should match: backtick code immediately followed by word
            self.assertTrue(pattern.search("`command`and"))
            self.assertTrue(pattern.search("`code`text"))
            # Should not match: proper spacing
            self.assertIsNone(pattern.search("`command` and"))
            self.assertIsNone(pattern.search("`code` text"))
            # Should not match: inline code with space inside (invalid markdown)
            self.assertIsNone(pattern.search("` command`and"))
            # Critical bug fix test: should NOT match across multiple inline code blocks
            test_multi = "Use `cmd1`and `cmd2` here"
            matches = pattern.findall(test_multi)
            self.assertEqual(len(matches), 1, "Should find exactly one match")
            self.assertEqual(matches[0], ('`cmd1`', 'a'), "Should match '`cmd1`a' not spanning blocks")
        
        def test_shell_prompt_patterns(self):
            patterns = DocumentationLecturer.SHELL_PROMPT_PATTERNS
            # Test "$ command" pattern (first pattern)
            # Pattern groups: (1) leading whitespace, (2) prompt, (3) command
            dollar_pattern = patterns[0]
            match = dollar_pattern.match("$ ls -la")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")  # no leading whitespace
            self.assertEqual(match.group(2), "$ ")
            self.assertEqual(match.group(3), "ls -la")
            
            # Test with indentation (tabs before $)
            match = dollar_pattern.match("\t$ tar -zxvf file.tar.gz")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "\t")  # leading tab
            self.assertEqual(match.group(2), "$ ")
            self.assertEqual(match.group(3), "tar -zxvf file.tar.gz")
            
            # Note: "# command" pattern was removed - # in code blocks are comments, not prompts
            # Verify that "# comment" lines are NOT matched by any pattern
            for pattern in patterns:
                self.assertIsNone(pattern.match("# This is a comment"))
            
            # Test "❯ command" pattern (fancy prompt like starship/powerline)
            fancy_pattern = patterns[4]  # index adjusted after removing # pattern
            match = fancy_pattern.match("❯ sudo wg show")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")
            self.assertEqual(match.group(2), "❯ ")
            self.assertEqual(match.group(3), "sudo wg show")
            
            # Test without space after ❯
            match = fancy_pattern.match("❯wg genkey")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")
            self.assertEqual(match.group(2), "❯")
            self.assertEqual(match.group(3), "wg genkey")
            
            # Test "➜  command" pattern (Oh My Zsh robbyrussell theme)
            omz_pattern = patterns[5]  # index adjusted
            match = omz_pattern.match("➜  git status")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "")
            self.assertEqual(match.group(2), "➜  ")
            self.assertEqual(match.group(3), "git status")
            
            # Should not match lines without prompts
            self.assertIsNone(dollar_pattern.match("ls -la"))
            self.assertIsNone(dollar_pattern.match("echo hello"))
        
        def test_strip_code_from_text(self):
            # Create a minimal mock args object for testing
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test removal of fenced code blocks
            text_with_code_block = "This is text ```python\nprint('hello')\n``` and more text"
            result = lecturer._strip_code_from_text(text_with_code_block)
            self.assertNotIn("print", result)
            self.assertIn("This is text", result)
            self.assertIn("and more text", result)
            
            # Test removal of inline code
            text_with_inline = "Run the `ls -la` command to list files"
            result = lecturer._strip_code_from_text(text_with_inline)
            self.assertNotIn("ls -la", result)
            self.assertIn("Run the", result)
            self.assertIn("command to list files", result)
            
            # Test mixed content
            text_mixed = "Use `export VAR=value` and ```bash\necho $VAR\n``` to set variables"
            result = lecturer._strip_code_from_text(text_mixed)
            self.assertNotIn("export", result)
            self.assertNotIn("echo", result)
            self.assertIn("Use", result)
            self.assertIn("to set variables", result)
            
            lecturer.cleanup()
        
        def test_deprecated_vmware_url_pattern(self):
            pattern = DocumentationLecturer.DEPRECATED_VMWARE_URL
            # Should match deprecated VMware package URLs
            self.assertIsNotNone(pattern.match("https://packages.vmware.com/photon/"))
            self.assertIsNotNone(pattern.match("https://packages.vmware.com/photon/4.0/"))
            self.assertIsNotNone(pattern.match("http://packages.vmware.com/tools/"))
            # Should not match other URLs
            self.assertIsNone(pattern.match("https://vmware.com/"))
            self.assertIsNone(pattern.match("https://packages.broadcom.com/"))
        
        def test_vmware_spelling_pattern(self):
            pattern = DocumentationLecturer.VMWARE_SPELLING_PATTERN
            # Should match incorrect spellings
            self.assertIsNotNone(pattern.search("vmware"))
            self.assertIsNotNone(pattern.search("Vmware"))
            self.assertIsNotNone(pattern.search("VMWare"))
            self.assertIsNotNone(pattern.search("VMWARE"))
            self.assertIsNotNone(pattern.search("VmWare"))
            # Should NOT match correct spelling
            self.assertIsNone(pattern.search("VMware"))
            self.assertIsNone(pattern.search("Use VMware products"))
        
        def test_markdown_header_no_space_pattern(self):
            pattern = DocumentationLecturer.MARKDOWN_HEADER_NO_SPACE
            # Should match headers without space
            match = pattern.search("####Install Google cloud SDK")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "####")
            self.assertEqual(match.group(2), "Install Google cloud SDK")
            
            match = pattern.search("###Subtitle without space")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "###")
            
            match = pattern.search("##Section")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "##")
            
            # Should NOT match headers with proper space
            self.assertIsNone(pattern.search("#### Install with space"))
            self.assertIsNone(pattern.search("### Proper subtitle"))
            self.assertIsNone(pattern.search("## Correct section"))
        
        def test_fix_markdown_header_spacing(self):
            """Test markdown header spacing fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test basic fix
            content = "####Install Google cloud SDK"
            fixed = lecturer._fix_markdown_header_spacing(content)
            self.assertEqual(fixed, "#### Install Google cloud SDK")
            
            # Test multiple headers
            content = """### GCE

The tar file can be uploaded to Google's cloud storage.

####Install Google cloud SDK on host machine

Some content here.

###Another section"""
            fixed = lecturer._fix_markdown_header_spacing(content)
            self.assertIn("#### Install Google cloud SDK on host machine", fixed)
            self.assertIn("### Another section", fixed)
            self.assertNotIn("####Install", fixed)
            self.assertNotIn("###Another", fixed)
            
            # Test that properly spaced headers are not modified
            content = "### Proper Header\n\n#### Another Header"
            fixed = lecturer._fix_markdown_header_spacing(content)
            self.assertEqual(content, fixed)
            
            lecturer.cleanup()
        
        def test_fix_html_comments(self):
            """Test HTML comment removal while preserving inner content."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test single-line comment
            content = "Some text\n\n<!-- Azure - A vhd file -->\n\nMore text"
            fixed = lecturer._fix_html_comments(content)
            self.assertIn("Azure - A vhd file", fixed)
            self.assertNotIn("<!--", fixed)
            self.assertNotIn("-->", fixed)
            
            # Test multi-line comment
            content = """Some text

<!-- ###How to build Photon bosh-stemcell

Please follow the link to build Photon bosh-stemcell
-->

More text"""
            fixed = lecturer._fix_html_comments(content)
            self.assertIn("###How to build Photon bosh-stemcell", fixed)
            self.assertIn("Please follow the link to build Photon bosh-stemcell", fixed)
            self.assertNotIn("<!--", fixed)
            self.assertNotIn("-->", fixed)
            
            # Test that code blocks are NOT modified
            content = """Some text

```html
<!-- This is a code example comment -->
<div>Content</div>
```

More text"""
            fixed = lecturer._fix_html_comments(content)
            self.assertIn("<!-- This is a code example comment -->", fixed)
            
            lecturer.cleanup()
        
        def test_mixed_command_output_detection(self):
            """Test detection of mixed command and output in code blocks."""
            # Create a minimal mock args object for testing
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test case 1: Mixed command with config output (should detect)
            html_mixed = '''
            <pre>sudo cat /etc/photon-mgmt/mgmt.toml
[System]
LogLevel="info"
UseAuthentication="false"

[Network]
ListenUnixSocket="true"</pre>
            '''
            soup = BeautifulSoup(html_mixed, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertGreater(len(issues), 0, "Should detect mixed command and output")
            self.assertEqual(issues[0]['type'], 'mixed_command_output')
            
            # Test case 2: Command only (should NOT detect)
            html_command_only = '''
            <pre>sudo systemctl restart nginx</pre>
            '''
            soup = BeautifulSoup(html_command_only, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertEqual(len(issues), 0, "Should not flag command-only code blocks")
            
            # Test case 3: Output only (should NOT detect)
            html_output_only = '''
            <pre>[System]
LogLevel="info"
UseAuthentication="false"</pre>
            '''
            soup = BeautifulSoup(html_output_only, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertEqual(len(issues), 0, "Should not flag output-only code blocks")
            
            # Test case 4: ls command with output (should detect)
            html_ls_output = '''
            <pre>ls -la /var/log
total 1234
drwxr-xr-x  2 root root 4096 Nov 30 10:00 .
drwxr-xr-x 14 root root 4096 Nov 30 10:00 ..
-rw-r--r--  1 root root 1234 Nov 30 10:00 syslog</pre>
            '''
            soup = BeautifulSoup(html_ls_output, 'html.parser')
            issues = lecturer._check_mixed_command_output_in_code_blocks("https://test.com/page", soup)
            self.assertGreater(len(issues), 0, "Should detect ls command with output")
            
            lecturer.cleanup()
        
        def test_llm_url_protection(self):
            """Test URL protection mechanism for LLM calls.
            
            Bug fix: LLMs sometimes modify URLs despite explicit instructions,
            such as removing .md extensions from GitHub links. The URL protection
            mechanism replaces URLs with placeholders before LLM calls and restores
            them afterwards.
            """
            # Test the LLMClient URL protection directly (without actual LLM calls)
            # Create a mock LLMClient to test _protect_urls and _restore_urls
            
            # Test _protect_urls
            text = """The GCE-ready version of Photon OS is licensed as described in the Photon OS [LICENSE guide](https://github.com/vmware/photon/blob/master/LICENSE.md).

See also [documentation](https://docs.example.com/guide.html) and visit https://example.com/path/file.pdf for more info."""
            
            protected, url_map = LLMClient._protect_urls(LLMClient, text)
            
            # Check that URLs are replaced with placeholders
            self.assertNotIn("https://github.com/vmware/photon/blob/master/LICENSE.md", protected)
            self.assertNotIn("https://docs.example.com/guide.html", protected)
            self.assertNotIn("https://example.com/path/file.pdf", protected)
            
            # Check that placeholders are present
            self.assertIn("__URL_PLACEHOLDER_0__", protected)
            self.assertIn("__URL_PLACEHOLDER_1__", protected)
            self.assertIn("__URL_PLACEHOLDER_2__", protected)
            
            # Check that link text is preserved
            self.assertIn("[LICENSE guide]", protected)
            self.assertIn("[documentation]", protected)
            
            # Check url_map contains the original URLs
            self.assertEqual(len(url_map), 3)
            self.assertIn("https://github.com/vmware/photon/blob/master/LICENSE.md", url_map.values())
            self.assertIn("https://docs.example.com/guide.html", url_map.values())
            self.assertIn("https://example.com/path/file.pdf", url_map.values())
            
            # Test _restore_urls
            restored = LLMClient._restore_urls(LLMClient, protected, url_map)
            
            # Check that original URLs are restored
            self.assertIn("https://github.com/vmware/photon/blob/master/LICENSE.md", restored)
            self.assertIn("https://docs.example.com/guide.html", restored)
            self.assertIn("https://example.com/path/file.pdf", restored)
            
            # Check that the full markdown links are intact
            self.assertIn("[LICENSE guide](https://github.com/vmware/photon/blob/master/LICENSE.md)", restored)
            self.assertIn("[documentation](https://docs.example.com/guide.html)", restored)
            
            # Check that placeholders are removed
            self.assertNotIn("__URL_PLACEHOLDER_", restored)
            
            # The restored text should match the original
            self.assertEqual(text, restored)
        
        def test_fix_vmware_spelling(self):
            """Test VMware spelling fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test basic fixes
            content = "Install vmware tools and Vmware Workstation"
            fixed = lecturer._fix_vmware_spelling(content)
            self.assertEqual(fixed, "Install VMware tools and VMware Workstation")
            
            # Test that code blocks are preserved
            content = "Use `vmware` command and vmware products"
            fixed = lecturer._fix_vmware_spelling(content)
            self.assertIn("`vmware`", fixed)  # Code should be unchanged
            self.assertIn("VMware products", fixed)  # Text should be fixed
            
            lecturer.cleanup()
        
        def test_fix_deprecated_urls(self):
            """Test deprecated URL fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test URL replacement
            content = "Download from https://packages.vmware.com/photon/5.0/"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("packages.broadcom.com", fixed)
            self.assertIn("/photon/5.0/", fixed)  # Path should be preserved
            self.assertNotIn("packages.vmware.com", fixed)
            
            # Test bosh-stemcell URL replacement
            content = "Please follow the link to [build](https://github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md) Photon bosh-stemcell"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("https://github.com/cloudfoundry/bosh/blob/main/README.md", fixed)
            self.assertNotIn("blob/develop/bosh-stemcell/README.md", fixed)
            
            # Test deprecated VDDK URL replacement (developercenter.vmware.com) with full link text update
            content = "[VDDK 6.0](https://developercenter.vmware.com/web/sdk/60/vddk)"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertEqual(fixed, "[VDDK 6.7](https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7)")
            self.assertNotIn("developercenter.vmware.com", fixed)
            self.assertNotIn("VDDK 6.0", fixed)
            
            # Test deprecated VDDK URL replacement (my.vmware.com)
            content = "[VDDK](https://my.vmware.com/web/vmware/downloads/details?downloadGroup=VDDK670&productId=742)"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("https://developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7", fixed)
            self.assertNotIn("my.vmware.com", fixed)
            
            # Test deprecated OVFTOOL URL replacement
            content = "[OVFTOOL](https://my.vmware.com/group/vmware/details?downloadGroup=OVFTOOL410&productId=491)"
            fixed = lecturer._fix_deprecated_urls(content)
            self.assertIn("https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest", fixed)
            self.assertNotIn("my.vmware.com/group/vmware/details", fixed)
            
            lecturer.cleanup()
        
        def test_fix_broken_email_addresses(self):
            """Test broken email address fix function.
            
            Bug fix: Email addresses in console output may be broken with whitespace
            when long lines are wrapped, e.g., "linux-packages@vmware.     com"
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test basic broken email fix
            content = "Summary     : gpg(VMware, Inc. -- Linux Packaging Key -- <linux-packages@vmware.                        com>)"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertIn("linux-packages@vmware.com", fixed)
            self.assertNotIn("vmware.                        com", fixed)
            
            # Test multiple whitespace patterns
            content = "Contact: user@example.   org for support"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertIn("user@example.org", fixed)
            self.assertNotIn("example.   org", fixed)
            
            # Test with newline in domain
            content = "Email: admin@company.\nnet"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertIn("admin@company.net", fixed)
            
            # Test that normal emails are not modified
            content = "Contact linux-packages@vmware.com for help"
            fixed = lecturer._fix_broken_email_addresses(content)
            self.assertEqual(content, fixed)  # Should be unchanged
            
            lecturer.cleanup()
        
        def test_vmware_spelling_excludes_broken_emails(self):
            """Test that VMware spelling check excludes broken email addresses.
            
            The 'vmware' in 'linux-packages@vmware.     com' should NOT be flagged
            as a spelling issue because it's part of an email domain.
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Broken email - vmware should NOT be flagged
            content = "Summary: gpg(VMware, Inc. -- <linux-packages@vmware.                        com>)"
            issues = lecturer._check_vmware_spelling("https://test.com", content)
            # Should have 0 issues - the vmware in the broken email should be excluded
            self.assertEqual(len(issues), 0, 
                "vmware in broken email 'linux-packages@vmware.     com' should not be flagged")
            
            # Normal email - vmware should NOT be flagged
            content = "Contact linux-packages@vmware.com for support"
            issues = lecturer._check_vmware_spelling("https://test.com", content)
            self.assertEqual(len(issues), 0, 
                "vmware in normal email should not be flagged")
            
            # Regular text with incorrect spelling - SHOULD be flagged
            content = "Install vmware tools on the system"
            issues = lecturer._check_vmware_spelling("https://test.com", content)
            self.assertGreater(len(issues), 0, 
                "vmware in regular text should be flagged")
            
            lecturer.cleanup()
        
        def test_fix_backtick_spacing(self):
            """Test backtick spacing fix function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test missing space before backtick
            content = "Run the command`ls`"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "Run the command `ls`")
            
            # Test missing space after backtick
            content = "`command`and then"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "`command` and then")
            
            # Test that properly spaced inline code is not modified
            content = "The `top` tool monitors system resources"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "The `top` tool monitors system resources")
            
            # Critical bug fix test: multiple inline codes on same line
            # Should only fix the actual issue, not corrupt other inline codes
            content = "The `top` tool and command`ps` here"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "The `top` tool and command `ps` here")
            self.assertIn("`top`", fixed, "The `top` inline code should remain unchanged")
            self.assertNotIn("` top `", fixed, "Should not add spaces inside `top`")
            self.assertNotIn("`top `", fixed, "Should not add trailing space inside `top`")
            
            # Test multiline content - should not match across lines
            content = "First `code` line\nSecond`code2` line"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "First `code` line\nSecond `code2` line")
            
            lecturer.cleanup()
        
        def test_fix_shell_prompts_in_markdown(self):
            """Test shell prompt removal from markdown code blocks."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test $ prompt removal
            content = "```bash\n$ ls -la\n$ echo hello\n```"
            fixed = lecturer._fix_shell_prompts_in_markdown(content)
            self.assertIn("ls -la", fixed)
            self.assertIn("echo hello", fixed)
            self.assertNotIn("$ ls", fixed)
            self.assertNotIn("$ echo", fixed)
            
            lecturer.cleanup()
        
        def test_fix_heading_hierarchy_preserves_first_heading(self):
            """Test that _fix_heading_hierarchy does NOT change first heading to H1.
            
            Bug fix: Previously, '## Example' was incorrectly changed to '# Example'
            because the code assumed the first heading must be H1. In Hugo/docs systems,
            the page title (H1) often comes from front matter, so content legitimately
            starts at H2.
            """
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test 1: First heading is H2 - should NOT be changed to H1
            content = "## Example\n\nSome content here.\n\n### Subsection\n\nMore content."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertEqual(fixed, content, "First heading '## Example' should NOT be changed to '# Example'")
            self.assertEqual(len(fixes), 0, "No fixes should be applied")
            
            # Test 2: First heading is H3 - should NOT be changed to H1
            content = "### Deep Start\n\nSome content.\n\n#### Even Deeper\n\nMore content."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertEqual(fixed, content, "First heading '### Deep Start' should NOT be changed")
            self.assertEqual(len(fixes), 0, "No fixes should be applied")
            
            # Test 3: Heading skip after first heading SHOULD be fixed
            # H2 -> H4 is a skip, should become H2 -> H3
            content = "## Example\n\nSome content.\n\n#### Skipped Level\n\nMore content."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertIn("### Skipped Level", fixed, "H4 should be fixed to H3 (heading skip)")
            self.assertNotIn("#### Skipped Level", fixed)
            self.assertEqual(len(fixes), 1, "One fix should be applied for the heading skip")
            
            # Test 4: Multiple heading skips
            content = "## Section\n\n##### Skip Many\n\nContent."
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertIn("### Skip Many", fixed, "H5 should be fixed to H3 (next valid level after H2)")
            
            # Test 5: Valid heading progression - no changes needed
            content = "## Section 1\n\n### Subsection 1.1\n\n#### Subsubsection 1.1.1\n\n## Section 2"
            fixed, fixes = lecturer._fix_heading_hierarchy(content)
            self.assertEqual(fixed, content, "Valid heading progression should not be changed")
            self.assertEqual(len(fixes), 0, "No fixes for valid progression")
            
            lecturer.cleanup()
        
        def test_analyze_heading_hierarchy_ignores_first_heading(self):
            """Test that _analyze_heading_hierarchy does NOT flag first heading as issue."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # First heading is H2 - should NOT be flagged as issue
            content = "## Example\n\nContent.\n\n### Subsection"
            issues = lecturer._analyze_heading_hierarchy(content)
            self.assertEqual(len(issues), 0, "First H2 heading should not be flagged as issue")
            
            # Heading skip should still be detected
            content = "## Example\n\n#### Skipped\n\nContent."
            issues = lecturer._analyze_heading_hierarchy(content)
            self.assertEqual(len(issues), 1, "Heading skip H2 -> H4 should be detected")
            self.assertIn("jumped from H2 to H4", issues[0]['issue'])
            
            lecturer.cleanup()
        
        def test_case_insensitive_directory_matching(self):
            """Test case-insensitive directory/file matching for URL to path mapping."""
            import tempfile
            import shutil
            
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Create a temporary directory structure mimicking Hugo content
            # with mixed-case directory names
            temp_dir = tempfile.mkdtemp(prefix='test_case_insensitive_')
            try:
                # Create structure: content/en/docs-v4/command-line-reference/command-line-Interfaces/_index.md
                content_dir = os.path.join(temp_dir, 'content', 'en', 'docs-v4', 
                                          'command-line-reference', 'command-line-Interfaces')
                os.makedirs(content_dir, exist_ok=True)
                
                # Create _index.md file
                index_file = os.path.join(content_dir, '_index.md')
                with open(index_file, 'w') as f:
                    f.write('# Command Line Interfaces\n')
                
                # Set up lecturer with temp directory as local_webserver
                lecturer.local_webserver = temp_dir
                lecturer.language = 'en'
                
                # Test case-insensitive matching (URL has lowercase, filesystem has mixed case)
                url = 'https://127.0.0.1/docs-v4/command-line-reference/command-line-interfaces/'
                result = lecturer._map_url_to_local_path(url)
                
                # Should find the file despite case difference
                self.assertIsNotNone(result, 
                    f"Should find file with case-insensitive matching. "
                    f"URL path: command-line-interfaces, Filesystem: command-line-Interfaces")
                self.assertTrue(os.path.isfile(result), f"Result should be a valid file: {result}")
                self.assertTrue(result.endswith('_index.md'), f"Should find _index.md, got: {result}")
                
            finally:
                # Cleanup
                shutil.rmtree(temp_dir, ignore_errors=True)
                lecturer.cleanup()
        
        def test_content_based_file_matching(self):
            """Test content-based file matching when path-based matching fails."""
            import tempfile
            import shutil
            
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Create a temporary directory structure mimicking Hugo content
            # where URL doesn't match filename (e.g., URL: building-cloud-images, file: build-cloud-images.md)
            temp_dir = tempfile.mkdtemp(prefix='test_content_matching_')
            try:
                # Create structure: content/en/docs-v4/build-other-images/
                content_dir = os.path.join(temp_dir, 'content', 'en', 'docs-v4', 'build-other-images')
                os.makedirs(content_dir, exist_ok=True)
                
                # Create _index.md for the parent directory
                index_file = os.path.join(content_dir, '_index.md')
                with open(index_file, 'w') as f:
                    f.write('# Build Other Images\n\nThis section covers building various image types.\n')
                
                # Create build-cloud-images.md with specific content
                cloud_file = os.path.join(content_dir, 'build-cloud-images.md')
                cloud_content = '''# Building Cloud Images

This guide explains how to build cloud images for AWS, Azure, and GCE.

## Prerequisites

- Photon OS build environment
- Cloud SDK installed
- Sufficient disk space

## Building AMI Images

Run the following command to build an AMI:

```bash
sudo make image IMG_NAME=ami
```

## Building Azure Images

For Azure, use:

```bash
sudo make image IMG_NAME=azure
```
'''
                with open(cloud_file, 'w') as f:
                    f.write(cloud_content)
                
                # Create another file to ensure we pick the right one
                ova_file = os.path.join(content_dir, 'build-ova.md')
                with open(ova_file, 'w') as f:
                    f.write('# Building OVA\n\nThis is about OVA images, virtual machines.\n')
                
                # Set up lecturer with temp directory as local_webserver
                lecturer.local_webserver = temp_dir
                lecturer.language = 'en'
                
                # Simulate webpage content that matches the cloud images file
                webpage_text = '''Building Cloud Images
                
This guide explains how to build cloud images for AWS, Azure, and GCE.

Prerequisites
- Photon OS build environment
- Cloud SDK installed
- Sufficient disk space

Building AMI Images
Run the following command to build an AMI:
sudo make image IMG_NAME=ami

Building Azure Images
For Azure, use:
sudo make image IMG_NAME=azure
'''
                
                # Test content-based matching
                # URL says "building-cloud-images" but file is "build-cloud-images.md"
                url = 'https://127.0.0.1/docs-v4/build-other-images/building-cloud-images/'
                result = lecturer._map_url_to_local_path(url, webpage_text)
                
                # Should find the file via content matching
                self.assertIsNotNone(result, 
                    "Should find file via content-based matching when URL doesn't match filename")
                self.assertTrue(os.path.isfile(result), f"Result should be a valid file: {result}")
                self.assertTrue(result.endswith('build-cloud-images.md'), 
                    f"Should find build-cloud-images.md via content matching, got: {result}")
                
            finally:
                # Cleanup
                shutil.rmtree(temp_dir, ignore_errors=True)
                lecturer.cleanup()
        
        def test_content_similarity_calculation(self):
            """Test the content similarity calculation function."""
            class MockArgs:
                command = 'analyze'
                website = 'https://example.com'
                parallel = 1
                language = 'en'
                ref_website = None
                test = False
            
            lecturer = DocumentationLecturer(MockArgs())
            
            # Test identical texts
            text1 = "Building cloud images for AWS Azure and GCE"
            text2 = "Building cloud images for AWS Azure and GCE"
            score = lecturer._calculate_content_similarity(text1, text2)
            self.assertEqual(score, 1.0, "Identical texts should have similarity of 1.0")
            
            # Test completely different texts
            text1 = "Building cloud images for AWS"
            text2 = "Installing packages with tdnf"
            score = lecturer._calculate_content_similarity(text1, text2)
            self.assertLess(score, 0.3, "Completely different texts should have low similarity")
            
            # Test partially similar texts
            text1 = "Building cloud images for AWS Azure GCE"
            text2 = "Cloud images for AWS and Azure deployment"
            score = lecturer._calculate_content_similarity(text1, text2)
            self.assertGreater(score, 0.3, "Partially similar texts should have moderate similarity")
            self.assertLess(score, 1.0, "Partially similar texts should not be identical")
            
            # Test empty texts
            score = lecturer._calculate_content_similarity("", "some text")
            self.assertEqual(score, 0.0, "Empty text should have zero similarity")
            
            lecturer.cleanup()
    
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestDocumentationLecturer)
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    return 0 if result.wasSuccessful() else 1


# =============================================================================
# Tool Installation
# =============================================================================

def check_admin_privileges() -> bool:
    """Check if running with administrative privileges."""
    try:
        # On Unix-like systems, check if running as root (uid 0)
        return os.geteuid() == 0
    except AttributeError:
        # On Windows, try a different approach
        try:
            import ctypes
            return ctypes.windll.shell32.IsUserAnAdmin() != 0
        except Exception:
            return False


def install_tools() -> int:
    """Install required tools: Java and language-tool-python.
    
    Returns:
        0 on success, 1 on failure
    """
    print(f"{TOOL_NAME} v{VERSION} - Install Tools")
    print()
    
    # Check for admin privileges
    if not check_admin_privileges():
        print("[ERROR] Administrative privileges required to install tools.", file=sys.stderr)
        print("        Please run as root or with sudo:", file=sys.stderr)
        print(f"        sudo python3 {TOOL_NAME} install-tools", file=sys.stderr)
        return 1
    
    print("[INFO] Running with administrative privileges")
    print()
    
    success = True
    
    # Install Java using tdnf (Photon OS package manager)
    # LanguageTool requires Java >= 17
    print("[STEP 1/3] Installing Java >= 17 (required for LanguageTool)...")
    java_ok = False
    java_version = None
    
    # Check if Java is already installed and get version
    try:
        result = subprocess.run(['java', '-version'], capture_output=True, text=True)
        if result.returncode == 0:
            # Java version is typically in stderr, format: 'openjdk version "21.0.x"' or 'java version "17.0.x"'
            version_output = result.stderr or result.stdout
            # Parse version number
            import re
            version_match = re.search(r'version\s+"?(\d+)(?:\.(\d+))?', version_output)
            if version_match:
                major_version = int(version_match.group(1))
                java_version = major_version
                if major_version >= 17:
                    print(f"[OK] Java {major_version} is installed (meets requirement >= 17)")
                    java_ok = True
                else:
                    print(f"[WARN] Java {major_version} is installed but version >= 17 is required")
    except FileNotFoundError:
        print("[INFO] Java is not installed")
    
    if not java_ok:
        print("[INFO] Installing openjdk21 via tdnf...")
        try:
            subprocess.run(['tdnf', 'install', '-y', 'openjdk21'], check=True)
            print("[OK] Java (openjdk21) installed via tdnf")
            java_ok = True
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to install openjdk21 via tdnf: {e}", file=sys.stderr)
            success = False
    
    if not java_ok:
        print("[WARN] Java >= 17 installation failed. LanguageTool requires Java >= 17.", file=sys.stderr)
        success = False
    
    # Step 2: Ensure pip is available
    print()
    print("[STEP 2/3] Ensuring pip is available...")
    pip_available = False
    
    try:
        result = subprocess.run([sys.executable, '-m', 'pip', '--version'], capture_output=True, text=True)
        if result.returncode == 0:
            print("[OK] pip is available")
            pip_available = True
    except Exception:
        pass
    
    if not pip_available:
        print("[INFO] Installing pip...")
        try:
            subprocess.run([sys.executable, '-m', 'ensurepip', '--default-pip'], check=True)
            print("[OK] pip installed")
            pip_available = True
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to install pip: {e}", file=sys.stderr)
            success = False
    
    # Step 3: Install required Python packages
    print()
    print("[STEP 3/3] Installing required Python packages...")
    
    # List of required packages: (pip_name, display_name)
    required_packages = [
        ('requests', 'requests'),
        ('beautifulsoup4', 'beautifulsoup4 (bs4)'),
        ('lxml', 'lxml'),
        ('language-tool-python', 'language-tool-python'),
        ('Pillow', 'Pillow (PIL)'),
        ('tqdm', 'tqdm'),
        ('google-generativeai', 'google-generativeai (for --llm gemini)'),
    ]
    
    if pip_available:
        for pip_name, display_name in required_packages:
            try:
                # Check if already installed
                result = subprocess.run(
                    [sys.executable, '-m', 'pip', 'show', pip_name],
                    capture_output=True, text=True
                )
                if result.returncode == 0:
                    print(f"[OK] {display_name} is already installed")
                else:
                    # Install package
                    print(f"[INFO] Installing {display_name}...")
                    subprocess.run(
                        [sys.executable, '-m', 'pip', 'install', pip_name],
                        check=True
                    )
                    print(f"[OK] {display_name} installed")
            except subprocess.CalledProcessError as e:
                print(f"[ERROR] Failed to install {display_name}: {e}", file=sys.stderr)
                success = False
    else:
        print("[ERROR] Cannot install Python packages without pip", file=sys.stderr)
        success = False
    
    # Summary
    print()
    if success:
        print("=" * 50)
        print("[OK] All tools installed successfully!")
        print()
        print("You can now use the analyzer:")
        print(f"  python3 {TOOL_NAME} analyze --website https://127.0.0.1/docs-v5")
        print("=" * 50)
        return 0
    else:
        print("=" * 50)
        print("[WARN] Some tools failed to install. Please check errors above.")
        print("=" * 50)
        return 1


# =============================================================================
# Main Entry Point
# =============================================================================

def main():
    """Main entry point."""
    parser = create_parser()
    args = parser.parse_args()
    
    if not args.command:
        parser.print_help()
        sys.exit(1)
    
    if args.command == 'version':
        print(f"{TOOL_NAME} v{VERSION}")
        sys.exit(0)
    
    # Handle --list-fixes flag
    if hasattr(args, 'list_fixes') and args.list_fixes:
        print(DocumentationLecturer.get_fix_help_text())
        sys.exit(0)
    
    # Handle --list-features flag
    if hasattr(args, 'list_features') and args.list_features:
        print(DocumentationLecturer.get_feature_help_text())
        sys.exit(0)
    
    # Handle install-tools command (no dependencies required)
    if args.command == 'install-tools':
        sys.exit(install_tools())
    
    # For analyze/run commands, check and import dependencies first
    check_and_import_dependencies()
    
    # Handle test flag
    if hasattr(args, 'test') and args.test:
        sys.exit(run_tests())
    
    # Validate arguments
    if not validate_args(args):
        sys.exit(1)
    
    # Test connectivity before starting
    session = requests.Session()
    session.verify = False
    try:
        response = session.head(args.website, timeout=10)
        if response.status_code >= 400:
            print(f"[ERROR] Server returned status {response.status_code} for {args.website}", file=sys.stderr)
            sys.exit(1)
    except requests.exceptions.RequestException as e:
        print(f"[ERROR] Cannot connect to {args.website}: {e}", file=sys.stderr)
        sys.exit(1)
    finally:
        session.close()
    
    # Create and run lecturer
    lecturer = DocumentationLecturer(args)
    lecturer.run()


if __name__ == '__main__':
    main()
