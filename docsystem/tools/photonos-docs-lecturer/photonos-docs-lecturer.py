#!/usr/bin/env python3
"""
Photon OS Documentation Lecturer v3.0
A comprehensive command-line tool for crawling Photon OS documentation served by Nginx,
identifying issues (grammar/spelling, markdown artifacts, orphan links/images, unaligned images,
heading hierarchy violations), generating CSV reports, and optionally applying fixes via git 
push and GitHub PR.

Version: 3.0 - Plugin Architecture
All detection and fix logic has been moved to modular plugins in the plugins/ directory.
See plugins/README-*.md for per-plugin documentation.

Usage:
    python3 photonos-docs-lecturer.py run --website <url> [options]
    python3 photonos-docs-lecturer.py analyze --website <url> [options]
    python3 photonos-docs-lecturer.py version

Commands:
    run      - Execute full workflow (analyze, generate fixes, push changes, create PR)
    analyze  - Generate report only (no fixes, git operations, or PR)
    version  - Display tool version
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
from typing import Dict, List, Optional, Set, Tuple, Any
import threading
import json

# Version info
VERSION = "3.0"
TOOL_NAME = "photonos-docs-lecturer.py"

# Lazy-loaded modules
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
    """Check and import all required dependencies."""
    global requests, bs4, BeautifulSoup, language_tool_python, Retry, HTTPAdapter
    global tqdm, Image, genai, HAS_TQDM, HAS_PIL, HAS_GEMINI
    
    missing_packages = []
    
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
    
    if missing_packages:
        print("ERROR: Required libraries not found:", file=sys.stderr)
        for module_name, pip_name in missing_packages:
            print(f"       - {module_name} (pip install {pip_name})", file=sys.stderr)
        print(file=sys.stderr)
        print(f"       Run: python3 {TOOL_NAME} install-tools", file=sys.stderr)
        sys.exit(1)


class LLMClient:
    """Client for LLM API interactions (Gemini or xAI)."""
    
    MARKDOWN_LINK_PATTERN = re.compile(r'\[([^\]]*)\]\(([^)]+)\)')
    URL_PATTERN = re.compile(r'https?://[^\s<>"\'`\)]+')
    
    def __init__(self, provider: str, api_key: str, language: str = "en"):
        self.provider = provider
        self.api_key = api_key
        self.language = language
        self.logger = logging.getLogger(TOOL_NAME)
        
        if provider == 'gemini' and HAS_GEMINI:
            genai.configure(api_key=api_key)
            self.model = genai.GenerativeModel('gemini-2.0-flash')
        elif provider == 'xai':
            self.xai_endpoint = "https://api.x.ai/v1/chat/completions"
            self.xai_model = "grok-beta"
    
    def _protect_urls(self, text: str) -> Tuple[str, Dict[str, str]]:
        """Replace URLs with placeholders to prevent LLM modification."""
        url_map = {}
        counter = [0]
        
        def replace_url(match):
            url = match.group(0)
            placeholder = f"__URL_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = url
            counter[0] += 1
            return placeholder
        
        def replace_link(match):
            text_part = match.group(1)
            url = match.group(2)
            placeholder = f"__URL_PLACEHOLDER_{counter[0]}__"
            url_map[placeholder] = url
            counter[0] += 1
            return f"[{text_part}]({placeholder})"
        
        protected = self.MARKDOWN_LINK_PATTERN.sub(replace_link, text)
        protected = self.URL_PATTERN.sub(replace_url, protected)
        return protected, url_map
    
    def _restore_urls(self, text: str, url_map: Dict[str, str]) -> str:
        """Restore URLs from placeholders."""
        result = text
        for placeholder, url in url_map.items():
            result = result.replace(placeholder, url)
        return result
    
    def _generate_with_url_protection(self, prompt: str, text_to_protect: str) -> str:
        """Generate LLM response with URL protection."""
        protected_text, url_map = self._protect_urls(text_to_protect)
        modified_prompt = prompt.replace(text_to_protect, protected_text)
        
        response = self._generate(modified_prompt)
        if response:
            response = self._restore_urls(response, url_map)
            response = self._clean_llm_response(response, text_to_protect)
        return response
    
    def translate(self, text: str, target_language: str) -> str:
        """Translate text to target language."""
        prompt = f"""Translate the following markdown documentation to {target_language}.
Preserve all markdown formatting, code blocks, and technical terms.
NEVER modify URLs or file paths.
Output ONLY the translated text, no explanations.

{text}"""
        return self._generate_with_url_protection(prompt, text)
    
    def fix_grammar(self, text: str, issues: List[Dict]) -> str:
        """Fix grammar issues using LLM."""
        issues_desc = "\n".join([f"- {i.get('message', str(i))}" for i in issues[:10]])
        prompt = f"""Fix the following grammar issues in this markdown text.
CRITICAL RULES:
1. NEVER modify content inside code blocks (``` or `)
2. NEVER modify URLs or file paths
3. NEVER add or remove any text
4. ONLY fix the specific issues listed
5. Preserve all markdown formatting

Issues to fix:
{issues_desc}

Text:
{text}

Output ONLY the corrected text."""
        return self._generate_with_url_protection(prompt, text)
    
    def fix_markdown(self, text: str, artifacts: List[str]) -> str:
        """Fix markdown artifacts using LLM."""
        artifacts_desc = "\n".join([f"- {a}" for a in artifacts[:10]])
        prompt = f"""Fix the following markdown rendering issues.
CRITICAL RULES:
1. NEVER modify content inside code blocks
2. NEVER modify URLs or file paths
3. ONLY fix the specific issues listed

Issues:
{artifacts_desc}

Text:
{text}

Output ONLY the corrected text."""
        return self._generate_with_url_protection(prompt, text)
    
    def fix_indentation(self, text: str, issues: List[Dict]) -> str:
        """Fix indentation issues using LLM."""
        issues_desc = "\n".join([f"- {i.get('context', str(i))}" for i in issues[:10]])
        prompt = f"""Fix the following indentation issues in this markdown.
CRITICAL RULES:
1. NEVER modify content inside code blocks
2. NEVER modify URLs or file paths
3. Use consistent indentation (2 or 4 spaces)

Issues:
{issues_desc}

Text:
{text}

Output ONLY the corrected text."""
        return self._generate_with_url_protection(prompt, text)
    
    def _clean_llm_response(self, response: str, original_text: str) -> str:
        """Clean LLM response of common artifacts."""
        # Remove common LLM artifacts
        response = re.sub(r'^```(?:markdown|md)?\s*\n', '', response)
        response = re.sub(r'\n```\s*$', '', response)
        response = re.sub(r'Output ONLY the corrected text.*$', '', response, flags=re.MULTILINE | re.IGNORECASE)
        return response.strip()
    
    def _generate(self, prompt: str) -> str:
        """Generate response from LLM."""
        try:
            if self.provider == 'gemini' and HAS_GEMINI:
                response = self.model.generate_content(prompt)
                return response.text if response else ""
            elif self.provider == 'xai':
                return self._xai_generate(prompt)
        except Exception as e:
            self.logger.error(f"LLM generation failed: {e}")
        return ""
    
    def _xai_generate(self, prompt: str) -> str:
        """Generate response using xAI API."""
        try:
            headers = {
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json"
            }
            data = {
                "model": self.xai_model,
                "messages": [{"role": "user", "content": prompt}],
                "temperature": 0.1
            }
            response = requests.post(self.xai_endpoint, headers=headers, json=data, timeout=60)
            response.raise_for_status()
            return response.json().get("choices", [{}])[0].get("message", {}).get("content", "")
        except Exception as e:
            self.logger.error(f"xAI API call failed: {e}")
            return ""


class DocumentationLecturer:
    """Main class for Photon OS documentation analysis and fixing using plugin architecture."""
    
    def __init__(self, args):
        """Initialize the Documentation Lecturer."""
        self.args = args
        self.command = args.command
        self.base_url = getattr(args, 'website', None)
        self.num_workers = getattr(args, 'parallel', 1)
        self.language = getattr(args, 'language', 'en')
        self.ref_website = getattr(args, 'ref_website', None)
        
        # Git/GitHub options
        self.local_webserver = getattr(args, 'local_webserver', None)
        self.gh_repotoken = getattr(args, 'gh_repotoken', None)
        self.gh_username = getattr(args, 'gh_username', None)
        self.ghrepo_url = getattr(args, 'ghrepo_url', None)
        self.ghrepo_branch = getattr(args, 'ghrepo_branch', 'photon-hugo')
        self.ref_ghrepo = getattr(args, 'ref_ghrepo', None)
        self.ref_ghbranch = getattr(args, 'ref_ghbranch', 'photon-hugo')
        self.gh_pr = getattr(args, 'gh_pr', False)
        
        # Parse --fix and --feature parameters
        fix_spec = getattr(args, 'fix', None)
        feature_spec = getattr(args, 'feature', None)
        
        # Import plugin system
        from plugins.integration import PluginIntegration
        self.plugin_integration = PluginIntegration(config={'language': self.language})
        
        # Parse fix/feature specs using plugin integration
        self.enabled_fix_ids = self.plugin_integration.parse_fix_spec(fix_spec) if fix_spec else None
        self.enabled_feature_ids = self.plugin_integration.parse_feature_spec(feature_spec) if feature_spec else set()
        
        # State
        self.sitemap: List[str] = []
        self.visited_urls: Set[str] = set()
        self.session = None
        self.logger = None
        self.grammar_tool = None
        self.grammar_tool_lock = threading.Lock()
        self.llm_client = None
        self.progress_bar = None
        
        # Report
        self.timestamp = datetime.datetime.now().strftime('%Y-%m-%dT%H-%M-%S.%f')
        self.report_filename = f"report-{self.timestamp}.csv"
        self.log_filename = f"report-{self.timestamp}.log"
        self.csv_file = None
        self.csv_writer = None
        self.csv_lock = threading.Lock()
        
        # Statistics
        self.pages_analyzed = 0
        self.issues_found = 0
        self.fixes_applied = 0
        self.modified_files: Set[str] = set()
        self.file_edit_lock = threading.Lock()
        
        # Git/PR state
        self.temp_dir = None
        self.repo_cloned = False
        self.pr_url = None
        self.pr_created = False
        
        # Setup
        if self.base_url:
            self._setup_logging()
            self.session = self._create_session()
            self._init_llm_client()
            self._initialize_csv()
            
            # Initialize plugin integration with LLM client
            self.plugin_integration = PluginIntegration(
                llm_client=self.llm_client,
                config={'language': self.language}
            )
    
    @staticmethod
    def get_fix_help_text() -> str:
        """Generate help text listing all available fixes."""
        from plugins.integration import PluginIntegration
        return PluginIntegration.get_fix_help_text()
    
    @staticmethod
    def get_feature_help_text() -> str:
        """Generate help text listing all available features."""
        from plugins.integration import PluginIntegration
        return PluginIntegration.get_feature_help_text()
    
    @classmethod
    def parse_fix_spec(cls, fix_spec: str) -> set:
        """Parse fix specification string into a set of fix IDs."""
        from plugins.integration import PluginIntegration
        return PluginIntegration.parse_fix_spec(fix_spec)
    
    @classmethod
    def parse_feature_spec(cls, feature_spec: str) -> set:
        """Parse feature specification string into a set of feature IDs."""
        from plugins.integration import PluginIntegration
        return PluginIntegration.parse_feature_spec(feature_spec)
    
    def _setup_logging(self):
        """Setup logging configuration."""
        self.logger = logging.getLogger(TOOL_NAME)
        self.logger.setLevel(logging.DEBUG)
        
        fh = logging.FileHandler(self.log_filename)
        fh.setLevel(logging.DEBUG)
        fh.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
        self.logger.addHandler(fh)
    
    def _create_session(self):
        """Create HTTP session with retry logic."""
        session = requests.Session()
        retry = Retry(total=3, backoff_factor=0.5, status_forcelist=[500, 502, 503, 504])
        adapter = HTTPAdapter(max_retries=retry)
        session.mount('http://', adapter)
        session.mount('https://', adapter)
        session.verify = False
        return session
    
    def _init_llm_client(self):
        """Initialize LLM client if configured."""
        llm_provider = getattr(self.args, 'llm', None)
        if llm_provider == 'gemini':
            api_key = getattr(self.args, 'GEMINI_API_KEY', None)
            if api_key and HAS_GEMINI:
                self.llm_client = LLMClient('gemini', api_key, self.language)
                self.logger.info("Initialized Gemini LLM client")
        elif llm_provider == 'xai':
            api_key = getattr(self.args, 'XAI_API_KEY', None)
            if api_key:
                self.llm_client = LLMClient('xai', api_key, self.language)
                self.logger.info("Initialized xAI LLM client")
    
    def _initialize_csv(self):
        """Initialize CSV report file."""
        self.csv_file = open(self.report_filename, 'w', newline='', encoding='utf-8')
        self.csv_writer = csv.writer(self.csv_file)
        self.csv_writer.writerow(['page_url', 'category', 'location', 'fix'])
    
    def _write_csv_row(self, page_url: str, category: str, location: str, fix: str):
        """Write a row to the CSV report (thread-safe)."""
        with self.csv_lock:
            if self.csv_writer:
                self.csv_writer.writerow([page_url, category, location[:500], fix[:500]])
                self.csv_file.flush()
                self.issues_found += 1
    
    def validate_connectivity(self) -> bool:
        """Validate connectivity to base URL."""
        if not self.base_url:
            return False
        try:
            response = self.session.get(self.base_url, timeout=10)
            return response.status_code < 400
        except Exception as e:
            self.logger.error(f"Connectivity check failed: {e}")
            return False
    
    def _check_robots_txt(self):
        """Check robots.txt for crawling rules.
        
        Uses the session to handle SSL verification properly.
        Returns a RobotFileParser that allows all URLs if robots.txt
        cannot be fetched or parsed.
        """
        rp = urllib.robotparser.RobotFileParser()
        try:
            base_parsed = urllib.parse.urlparse(self.base_url)
            robots_url = f"{base_parsed.scheme}://{base_parsed.netloc}/robots.txt"
            
            # Use session to fetch robots.txt (handles SSL)
            response = self.session.get(robots_url, timeout=10)
            if response.status_code == 200:
                # Parse the robots.txt content
                rp.parse(response.text.splitlines())
            else:
                # If robots.txt doesn't exist, allow all
                rp.parse(["User-agent: *", "Allow: /"])
        except Exception as e:
            self.logger.debug(f"Could not fetch robots.txt: {e}")
            # On error, allow all URLs
            rp.parse(["User-agent: *", "Allow: /"])
        return rp
    
    def _parse_sitemap_xml(self) -> List[str]:
        """Parse sitemap.xml to get list of URLs."""
        sitemap_urls = []
        try:
            base_parsed = urllib.parse.urlparse(self.base_url)
            sitemap_url = f"{base_parsed.scheme}://{base_parsed.netloc}/sitemap.xml"
            response = self.session.get(sitemap_url, timeout=10)
            if response.status_code == 200:
                soup = BeautifulSoup(response.content, 'xml')
                for loc in soup.find_all('loc'):
                    url = loc.text.strip()
                    if url.startswith(self.base_url):
                        sitemap_urls.append(url)
        except Exception as e:
            self.logger.debug(f"Could not parse sitemap.xml: {e}")
        return sitemap_urls
    
    def _is_valid_page_url(self, url: str) -> bool:
        """Check if URL is valid for analysis."""
        parsed = urllib.parse.urlparse(url)
        base_parsed = urllib.parse.urlparse(self.base_url)
        
        if parsed.netloc != base_parsed.netloc:
            return False
        if not url.startswith(self.base_url):
            return False
        
        excluded = ('.pdf', '.zip', '.tar', '.gz', '.jpg', '.jpeg', '.png', '.gif', 
                   '.svg', '.css', '.js', '.ico', '.woff', '.woff2', '.ttf', '.eot')
        if parsed.path.lower().endswith(excluded):
            return False
        return True
    
    def _crawl_page(self, url: str, depth: int, max_depth: int = 5) -> List[str]:
        """Crawl a page and extract internal links."""
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
        """Generate sitemap by parsing sitemap.xml or crawling."""
        self.logger.info("Generating sitemap...")
        self.sitemap.clear()
        self.visited_urls.clear()
        
        sitemap_urls = self._parse_sitemap_xml()
        if sitemap_urls:
            self.sitemap = sitemap_urls
            self.visited_urls.update(sitemap_urls)
            self.logger.info(f"Using sitemap.xml with {len(sitemap_urls)} pages")
            return
        
        self.logger.info("sitemap.xml not found, crawling site...")
        robots = self._check_robots_txt()
        
        queue = deque([(self.base_url, 0)])
        self.visited_urls.add(self.base_url)
        
        while queue:
            url, depth = queue.popleft()
            if not robots.can_fetch("*", url):
                continue
            
            self.sitemap.append(url)
            self.logger.info(f"Crawled [{len(self.sitemap)}]: {url}")
            
            links = self._crawl_page(url, depth)
            for link in links:
                if link not in self.visited_urls:
                    self.visited_urls.add(link)
                    queue.append((link, depth + 1))
            
            time.sleep(1)
        
        self.logger.info(f"Sitemap generated with {len(self.sitemap)} pages")
    
    def _get_grammar_tool(self):
        """Lazy load grammar checking tool (thread-safe)."""
        if self.grammar_tool is None:
            with self.grammar_tool_lock:
                if self.grammar_tool is None:
                    lang_code = self.language if self.language else 'en-US'
                    if len(lang_code) == 2:
                        lang_code = f"{lang_code}-{lang_code.upper()}"
                    self.grammar_tool = language_tool_python.LanguageTool(lang_code, remote_server=None)
        return self.grammar_tool
    
    def initialize_grammar_checker(self) -> bool:
        """Initialize grammar checker."""
        try:
            print("Initializing grammar checker...")
            self._get_grammar_tool()
            print("[OK] Grammar checker initialized")
            return True
        except Exception as e:
            print(f"\n[ERROR] Failed to initialize grammar checker: {e}", file=sys.stderr)
            return False
    
    def _map_url_to_local_path(self, page_url: str, webpage_text: str = None) -> Optional[str]:
        """Map a page URL to local filesystem path."""
        if not self.local_webserver:
            return None
        
        try:
            parsed = urllib.parse.urlparse(page_url)
            url_path = parsed.path.strip('/')
            
            # Try common Hugo content paths
            search_paths = [
                os.path.join(self.local_webserver, 'content', self.language, url_path),
                os.path.join(self.local_webserver, 'content', url_path),
                os.path.join(self.local_webserver, url_path),
            ]
            
            for base_path in search_paths:
                # Try with .md extension
                if os.path.isfile(base_path + '.md'):
                    return base_path + '.md'
                # Try _index.md for directories
                index_path = os.path.join(base_path, '_index.md')
                if os.path.isfile(index_path):
                    return index_path
                # Try index.md
                index_path = os.path.join(base_path, 'index.md')
                if os.path.isfile(index_path):
                    return index_path
            
            return None
        except Exception as e:
            self.logger.error(f"Failed to map URL to local path: {e}")
            return None
    
    def analyze_page(self, page_url: str):
        """Analyze a single page using the plugin system."""
        self.logger.info(f"Analyzing: {page_url}")
        
        try:
            response = self.session.get(page_url, timeout=10)
            if response.status_code >= 400:
                self.logger.warning(f"Orphaned page (HTTP {response.status_code}): {page_url}")
                self._write_csv_row(page_url, 'orphan_page', 
                                   f"HTTP {response.status_code}", "Fix page availability")
                return
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Extract main content
            main = soup.find('div', id='content') or soup.find('main') or soup.find('article') or soup
            
            # Clean content
            for elem in main.find_all(['script', 'style', 'nav', 'footer', 'header']):
                elem.decompose()
            
            text_content = main.get_text(separator=' ', strip=True)
            html_content = str(main)
            
            # Get markdown content if available
            local_path = self._map_url_to_local_path(page_url, text_content)
            markdown_content = None
            if local_path and os.path.exists(local_path):
                with open(local_path, 'r', encoding='utf-8') as f:
                    markdown_content = f.read()
            
            # Use plugin system for detection
            issues_by_plugin = self.plugin_integration.detect_issues(
                content=markdown_content or text_content,
                url=page_url,
                enabled_fix_ids=self.enabled_fix_ids,
                enabled_feature_ids=self.enabled_feature_ids,
                soup=soup,
                html_content=html_content,
                text_content=text_content,
                markdown_content=markdown_content,
                grammar_tool=self._get_grammar_tool() if self.enabled_fix_ids is None or 9 in self.enabled_fix_ids else None
            )
            
            # Write issues to CSV
            for plugin_name, issues in issues_by_plugin.items():
                for issue in issues:
                    self._write_csv_row(page_url, issue.category, issue.location, issue.suggestion)
            
            # Apply fixes if running with --gh-pr
            if self.command == 'run' and self.gh_pr and local_path and markdown_content:
                self._apply_fixes(page_url, local_path, markdown_content, issues_by_plugin)
            
            self.pages_analyzed += 1
            
        except requests.exceptions.Timeout:
            self.logger.warning(f"Timeout: {page_url}")
            self._write_csv_row(page_url, 'orphan_page', "Connection timeout", "Check availability")
        except requests.exceptions.ConnectionError:
            self.logger.warning(f"Connection error: {page_url}")
            self._write_csv_row(page_url, 'orphan_page', "Connection error", "Check server status")
        except Exception as e:
            self.logger.error(f"Failed to analyze {page_url}: {e}")
            import traceback
            self.logger.error(traceback.format_exc())
    
    def _apply_fixes(self, page_url: str, local_path: str, content: str, 
                     issues_by_plugin: Dict[str, List]):
        """Apply fixes using the plugin system."""
        try:
            with self.file_edit_lock:
                original = content
                
                # Use plugin system for fixes
                result = self.plugin_integration.apply_fixes(
                    content=content,
                    issues_by_plugin=issues_by_plugin,
                    enabled_fix_ids=self.enabled_fix_ids,
                    enabled_feature_ids=self.enabled_feature_ids,
                    llm_client=self.llm_client
                )
                
                if result.success and result.modified_content and result.modified_content != original:
                    with open(local_path, 'w', encoding='utf-8') as f:
                        f.write(result.modified_content)
                    
                    self.modified_files.add(local_path)
                    self.fixes_applied += 1
                    
                    fixes_str = ', '.join(result.changes_made) if result.changes_made else 'content changes'
                    self.logger.info(f"Applied fixes to {local_path}: {fixes_str}")
                    print(f"  [FIX] {os.path.basename(local_path)}: {fixes_str}")
                    
                    # Incremental commit/push/PR
                    if self.gh_pr and self.repo_cloned:
                        self._incremental_commit_push_and_pr(local_path, result.changes_made)
                        
        except Exception as e:
            self.logger.error(f"Failed to apply fixes to {local_path}: {e}")
    
    def analyze_all_pages(self):
        """Analyze all pages in the sitemap."""
        total = len(self.sitemap)
        self.logger.info(f"Starting analysis of {total} pages...")
        
        if HAS_TQDM:
            self.progress_bar = tqdm(total=total, desc="Analyzing pages", unit="page")
        
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
        """Analyze pages in parallel."""
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
            return True
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            subprocess.run(['gh', '--version'], check=True, capture_output=True)
            
            if self.ghrepo_url:
                user_repo_parsed = urllib.parse.urlparse(self.ghrepo_url)
                user_repo_path = user_repo_parsed.path.strip('/')
                if user_repo_path.endswith('.git'):
                    user_repo_path = user_repo_path[:-4]
            else:
                parsed = urllib.parse.urlparse(self.ref_ghrepo)
                repo_path = parsed.path.strip('/')
                if repo_path.endswith('.git'):
                    repo_path = repo_path[:-4]
                user_repo_path = f"{self.gh_username}/{repo_path.split('/')[-1]}"
            
            result = subprocess.run(['gh', 'repo', 'view', user_repo_path],
                                   capture_output=True, text=True, env=env)
            return result.returncode == 0
        except Exception as e:
            self.logger.error(f"Repository verification failed: {e}")
            return False
    
    def _clone_repository(self) -> Optional[str]:
        """Clone the user's fork repository."""
        if not self.ghrepo_url or not self.gh_repotoken:
            return None
        
        try:
            self.temp_dir = tempfile.mkdtemp(prefix='photon-docs-')
            
            parsed = urllib.parse.urlparse(self.ghrepo_url)
            auth_url = f"{parsed.scheme}://{self.gh_username}:{self.gh_repotoken}@{parsed.netloc}{parsed.path}"
            
            result = subprocess.run(
                ['git', 'clone', '--branch', self.ghrepo_branch, '--depth', '1', auth_url, self.temp_dir],
                capture_output=True, text=True
            )
            
            if result.returncode != 0:
                self.logger.error(f"Clone failed: {result.stderr}")
                return None
            
            subprocess.run(['git', 'config', 'user.email', f'{self.gh_username}@users.noreply.github.com'],
                          cwd=self.temp_dir, check=True, capture_output=True)
            subprocess.run(['git', 'config', 'user.name', self.gh_username],
                          cwd=self.temp_dir, check=True, capture_output=True)
            
            return self.temp_dir
        except Exception as e:
            self.logger.error(f"Failed to clone repository: {e}")
            return None
    
    def _map_local_path_to_repo_path(self, local_path: str, repo_dir: str) -> Optional[str]:
        """Map local webserver path to cloned repository path."""
        if not self.local_webserver:
            return None
        try:
            rel_path = os.path.relpath(local_path, self.local_webserver)
            return os.path.join(repo_dir, rel_path)
        except Exception:
            return None
    
    def _copy_modified_files_to_repo(self, repo_dir: str) -> List[str]:
        """Copy modified files to the cloned repository."""
        import shutil
        copied_files = []
        
        for local_path in self.modified_files:
            repo_path = self._map_local_path_to_repo_path(local_path, repo_dir)
            if not repo_path:
                continue
            
            try:
                os.makedirs(os.path.dirname(repo_path), exist_ok=True)
                shutil.copy2(local_path, repo_path)
                copied_files.append(os.path.relpath(repo_path, repo_dir))
            except Exception as e:
                self.logger.error(f"Failed to copy {local_path}: {e}")
        
        return copied_files
    
    def _git_commit_and_push(self) -> bool:
        """Clone repo, copy modified files, commit and push."""
        if not self.ghrepo_url or not self.gh_repotoken or not self.modified_files:
            return False
        
        try:
            repo_dir = self._clone_repository()
            if not repo_dir:
                return False
            
            copied_files = self._copy_modified_files_to_repo(repo_dir)
            if not copied_files:
                return False
            
            original_cwd = os.getcwd()
            os.chdir(repo_dir)
            
            try:
                for rel_path in copied_files:
                    subprocess.run(['git', 'add', rel_path], check=True)
                
                result = subprocess.run(['git', 'status', '--porcelain'], capture_output=True, text=True)
                if not result.stdout.strip():
                    return False
                
                commit_msg = f"Documentation fixes - {self.timestamp}\n\nAutomated fixes by {TOOL_NAME}"
                subprocess.run(['git', 'commit', '-m', commit_msg], check=True, capture_output=True)
                
                parsed = urllib.parse.urlparse(self.ghrepo_url)
                auth_url = f"{parsed.scheme}://{self.gh_username}:{self.gh_repotoken}@{parsed.netloc}{parsed.path}"
                subprocess.run(['git', 'push', auth_url, self.ghrepo_branch], check=True, capture_output=True)
                
                print(f"\n[OK] Git push successful")
                return True
            finally:
                os.chdir(original_cwd)
        except Exception as e:
            self.logger.error(f"Git operation failed: {e}")
            return False
    
    def _create_pull_request(self) -> bool:
        """Create a pull request using gh CLI."""
        if not self.gh_pr or not self.ref_ghrepo:
            return False
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/').rstrip('.git')
            
            title = f"[Automated] Documentation fixes - {self.timestamp}"
            body = f"Automated documentation fixes by {TOOL_NAME}\n\nFixes applied: {self.fixes_applied}"
            
            result = subprocess.run(
                ['gh', 'pr', 'create', '--repo', repo_path,
                 '--head', f"{self.gh_username}:{self.ghrepo_branch}",
                 '--base', self.ref_ghbranch,
                 '--title', title, '--body', body],
                capture_output=True, text=True, env=env
            )
            
            if result.returncode == 0:
                self.pr_url = result.stdout.strip()
                print(f"\n[OK] Pull request created: {self.pr_url}")
                return True
            else:
                self.logger.error(f"PR creation failed: {result.stderr}")
                return False
        except Exception as e:
            self.logger.error(f"Failed to create PR: {e}")
            return False
    
    def _initialize_repo_for_incremental_pr(self) -> bool:
        """Initialize repository for incremental commits."""
        repo_dir = self._clone_repository()
        if repo_dir:
            self.repo_cloned = True
            return True
        return False
    
    def _incremental_commit_push_and_pr(self, local_path: str, fixes_applied: List[str]) -> bool:
        """Incrementally commit, push, and update PR for a single file."""
        if not self.temp_dir:
            return False
        
        try:
            import shutil
            repo_path = self._map_local_path_to_repo_path(local_path, self.temp_dir)
            if not repo_path:
                return False
            
            os.makedirs(os.path.dirname(repo_path), exist_ok=True)
            shutil.copy2(local_path, repo_path)
            
            original_cwd = os.getcwd()
            os.chdir(self.temp_dir)
            
            try:
                rel_path = os.path.relpath(repo_path, self.temp_dir)
                subprocess.run(['git', 'add', rel_path], check=True, capture_output=True)
                
                fixes_str = ', '.join(fixes_applied) if fixes_applied else 'fixes'
                commit_msg = f"Fix: {os.path.basename(local_path)} - {fixes_str}"
                subprocess.run(['git', 'commit', '-m', commit_msg], check=True, capture_output=True)
                
                parsed = urllib.parse.urlparse(self.ghrepo_url)
                auth_url = f"{parsed.scheme}://{self.gh_username}:{self.gh_repotoken}@{parsed.netloc}{parsed.path}"
                subprocess.run(['git', 'push', auth_url, self.ghrepo_branch], check=True, capture_output=True)
                
                if not self.pr_created and self.gh_pr:
                    self._create_pull_request()
                    self.pr_created = True
                
                return True
            finally:
                os.chdir(original_cwd)
        except Exception as e:
            self.logger.error(f"Incremental commit failed: {e}")
            return False
    
    def finalize_report(self):
        """Finalize the CSV report."""
        if self.csv_file:
            self.csv_file.close()
        print(f"\n[OK] Report saved: {self.report_filename}")
        print(f"     Pages analyzed: {self.pages_analyzed}")
        print(f"     Issues found: {self.issues_found}")
        print(f"     Fixes applied: {self.fixes_applied}")
    
    def cleanup(self):
        """Cleanup resources."""
        if self.grammar_tool:
            self.grammar_tool.close()
        if self.temp_dir and os.path.exists(self.temp_dir):
            import shutil
            shutil.rmtree(self.temp_dir, ignore_errors=True)
        if self.plugin_integration:
            self.plugin_integration.cleanup()
    
    def run_analyze(self):
        """Run analysis-only mode."""
        print(f"\n{TOOL_NAME} v{VERSION} - Analyze Mode")
        print(f"Website: {self.base_url}")
        print(f"Language: {self.language}")
        print(f"Workers: {self.num_workers}")
        
        if not self.validate_connectivity():
            print(f"\n[ERROR] Cannot connect to {self.base_url}")
            sys.exit(1)
        
        if not self.initialize_grammar_checker():
            sys.exit(1)
        
        self.generate_sitemap()
        if not self.sitemap:
            print("\n[ERROR] No pages found to analyze")
            sys.exit(1)
        
        print(f"\n[OK] Found {len(self.sitemap)} pages to analyze")
        self.analyze_all_pages()
        self.finalize_report()
    
    def run_full(self):
        """Run full workflow with fixes and PR."""
        print(f"\n{TOOL_NAME} v{VERSION} - Full Workflow")
        print(f"Website: {self.base_url}")
        print(f"Language: {self.language}")
        print(f"Workers: {self.num_workers}")
        
        if not self.validate_connectivity():
            print(f"\n[ERROR] Cannot connect to {self.base_url}")
            sys.exit(1)
        
        if not self.initialize_grammar_checker():
            sys.exit(1)
        
        if self.gh_pr:
            if not self._fork_repository():
                print("\n[ERROR] Repository verification failed")
                sys.exit(1)
            
            if not self._initialize_repo_for_incremental_pr():
                print("\n[ERROR] Failed to clone repository")
                sys.exit(1)
        
        self.generate_sitemap()
        if not self.sitemap:
            print("\n[ERROR] No pages found to analyze")
            sys.exit(1)
        
        print(f"\n[OK] Found {len(self.sitemap)} pages to analyze")
        self.analyze_all_pages()
        self.finalize_report()
        
        print(f"\n[OK] Workflow complete!")
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
            sys.exit(1)
        except Exception as e:
            self.logger.error(f"Failed: {e}")
            print(f"\n[ERROR] {e}")
            sys.exit(1)
        finally:
            self.cleanup()


# =============================================================================
# Argument Parsing
# =============================================================================

def validate_url(url: str) -> str:
    """Validate URL format."""
    if not url:
        raise argparse.ArgumentTypeError("URL is required")
    parsed = urllib.parse.urlparse(url)
    if not parsed.scheme:
        url = f"https://{url}"
    return url


def validate_path(path: str) -> str:
    """Validate filesystem path exists."""
    if path and not os.path.exists(os.path.expanduser(path)):
        raise argparse.ArgumentTypeError(f"Path does not exist: {path}")
    return os.path.expanduser(path) if path else path


def validate_parallel(value: str) -> int:
    """Validate parallel workers value."""
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
        description='Photon OS Documentation Lecturer v3.0 - Plugin Architecture',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Commands:
  run            Execute full workflow (analyze, fix, push, PR)
  analyze        Generate report only (no fixes or git operations)
  test           Run unit tests for the tool
  install-tools  Install required tools (Java, language-tool-python)
  version        Display tool version

Fix Types (--fix):
  1-8, 12-13   Automatic (no LLM required)
  9-11         LLM-assisted (requires --llm with API key)
  Use --list-fixes to see detailed descriptions

Feature Types (--feature):
  1            Automatic (shell prompt removal)
  2            LLM-assisted (mixed command/output separation)
  Use --list-features to see detailed descriptions

Examples:
  # Analyze only
  python3 {TOOL_NAME} analyze --website https://127.0.0.1/docs-v5 --parallel 10

  # Full workflow with automatic fixes only
  python3 {TOOL_NAME} run --website https://127.0.0.1/docs-v5 \\
    --local-webserver /var/www/photon-site --gh-pr --fix 1-8,12,13 \\
    --gh-repotoken TOKEN --gh-username USER --ghrepo-url FORK_URL --ref-ghrepo REF_URL

  # Full workflow with all fixes including LLM
  python3 {TOOL_NAME} run --website https://127.0.0.1/docs-v5 \\
    --local-webserver /var/www/photon-site --gh-pr --fix all \\
    --llm xai --XAI_API_KEY KEY ...

Version: {VERSION}
        """
    )
    
    subparsers = parser.add_subparsers(dest='command', help='Command to execute')
    
    subparsers.add_parser('version', help='Display tool version')
    subparsers.add_parser('install-tools', help='Install required tools')
    subparsers.add_parser('test', help='Run unit tests')
    
    analyze_parser = subparsers.add_parser('analyze', help='Generate report only')
    _add_common_args(analyze_parser)
    _add_git_args(analyze_parser)
    
    run_parser = subparsers.add_parser('run', help='Execute full workflow')
    _add_common_args(run_parser)
    _add_git_args(run_parser)
    _add_llm_args(run_parser)
    
    return parser


def _add_common_args(parser):
    """Add common arguments."""
    parser.add_argument('--website', type=validate_url, metavar='URL',
                       help='Base URL of documentation (e.g., https://127.0.0.1/docs-v5)')
    parser.add_argument('--parallel', type=validate_parallel, default=1, metavar='N',
                       help='Number of parallel worker threads (1-20, default: 1)')
    parser.add_argument('--language', type=str, default='en', metavar='CODE',
                       help='Language code for grammar checking (default: en)')
    parser.add_argument('--ref-website', type=validate_url, metavar='URL',
                       help='Reference website URL for comparison')


def _add_git_args(parser):
    """Add git/GitHub arguments."""
    parser.add_argument('--local-webserver', type=validate_path, metavar='PATH',
                       help='Local filesystem path to webserver root (e.g., /var/www/photon-site)')
    parser.add_argument('--gh-repotoken', type=str, metavar='TOKEN',
                       help='GitHub personal access token for authentication')
    parser.add_argument('--gh-username', type=str, metavar='USER',
                       help='GitHub username')
    parser.add_argument('--ghrepo-url', type=str, metavar='URL',
                       help='Your forked repository URL (e.g., https://github.com/user/photon.git)')
    parser.add_argument('--ghrepo-branch', type=str, default='photon-hugo', metavar='BRANCH',
                       help='Branch for commits/pushes (default: photon-hugo)')
    parser.add_argument('--ref-ghrepo', type=str, metavar='URL',
                       help='Original repo to create PR against')
    parser.add_argument('--ref-ghbranch', type=str, default='photon-hugo', metavar='BRANCH',
                       help='Base branch for PR target (default: photon-hugo)')
    parser.add_argument('--gh-pr', action='store_true',
                       help='Enable PR creation (commits and pushes fixes)')
    parser.add_argument('--fix', type=str, metavar='SPEC',
                       help='Fix IDs to apply: "1,2,3", "1-5", "all" (use --list-fixes)')
    parser.add_argument('--list-fixes', action='store_true',
                       help='List all available fix types with IDs and exit')
    parser.add_argument('--feature', type=str, metavar='SPEC',
                       help='Feature IDs to apply: "1,2", "all" (use --list-features)')
    parser.add_argument('--list-features', action='store_true',
                       help='List all available feature types with IDs and exit')


def _add_llm_args(parser):
    """Add LLM arguments."""
    parser.add_argument('--llm', type=str, choices=['gemini', 'xai'], metavar='PROVIDER',
                       help='LLM provider for fix IDs 9-11: gemini or xai')
    parser.add_argument('--GEMINI_API_KEY', type=str, metavar='KEY',
                       help='Google Gemini API key (required when --llm gemini)')
    parser.add_argument('--XAI_API_KEY', type=str, metavar='KEY',
                       help='xAI/Grok API key (required when --llm xai)')


def validate_args(args) -> bool:
    """Validate argument combinations."""
    if args.command == 'version':
        return True
    
    if args.command in ('run', 'analyze'):
        if getattr(args, 'list_fixes', False) or getattr(args, 'list_features', False):
            return True
        if not getattr(args, 'website', None):
            print("[ERROR] --website is required", file=sys.stderr)
            return False
    
    if args.command == 'run' and getattr(args, 'gh_pr', False):
        required = ['local_webserver', 'gh_repotoken', 'gh_username', 'ghrepo_url', 'ref_ghrepo']
        missing = [r for r in required if not getattr(args, r, None)]
        if missing:
            print(f"[ERROR] --gh-pr requires: {', '.join(['--' + r.replace('_', '-') for r in missing])}", 
                  file=sys.stderr)
            return False
    
    if args.command == 'run':
        llm = getattr(args, 'llm', None)
        if llm == 'gemini' and not getattr(args, 'GEMINI_API_KEY', None):
            print("[ERROR] --GEMINI_API_KEY required when --llm gemini", file=sys.stderr)
            return False
        if llm == 'xai' and not getattr(args, 'XAI_API_KEY', None):
            print("[ERROR] --XAI_API_KEY required when --llm xai", file=sys.stderr)
            return False
    
    return True


# =============================================================================
# Tool Installation
# =============================================================================

def check_admin_privileges() -> bool:
    """Check if running with admin privileges."""
    return os.geteuid() == 0


def install_tools() -> int:
    """Install required tools."""
    if not check_admin_privileges():
        print("[ERROR] install-tools requires root/admin privileges", file=sys.stderr)
        print("        Run: sudo python3 photonos-docs-lecturer.py install-tools", file=sys.stderr)
        return 1
    
    print("Installing required tools...")
    
    # Install Java
    print("\n[1/3] Installing Java...")
    try:
        subprocess.run(['tdnf', 'install', '-y', 'openjdk17'], check=True)
        print("[OK] Java installed")
    except Exception as e:
        print(f"[WARN] Failed to install Java: {e}")
    
    # Install Python packages
    print("\n[2/3] Installing Python packages...")
    packages = ['requests', 'beautifulsoup4', 'language-tool-python', 'tqdm', 'google-generativeai']
    for pkg in packages:
        try:
            subprocess.run([sys.executable, '-m', 'pip', 'install', pkg], check=True)
            print(f"[OK] {pkg} installed")
        except Exception as e:
            print(f"[WARN] Failed to install {pkg}: {e}")
    
    print("\n[3/3] Verifying installation...")
    try:
        import language_tool_python
        tool = language_tool_python.LanguageTool('en-US', remote_server=None)
        tool.close()
        print("[OK] language-tool-python verified")
    except Exception as e:
        print(f"[WARN] Verification failed: {e}")
    
    print("\n[OK] Installation complete")
    return 0


# =============================================================================
# Unit Tests
# =============================================================================

def run_tests() -> int:
    """Run unit tests for the tool.
    
    Returns:
        0 if all tests pass, 1 otherwise
    """
    import unittest
    
    class TestDocumentationLecturer(unittest.TestCase):
        """Unit tests for DocumentationLecturer."""
        
        def test_validate_url(self):
            """Test URL validation."""
            self.assertEqual(validate_url("https://example.com"), "https://example.com")
            self.assertEqual(validate_url("example.com"), "https://example.com")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_url("")
        
        def test_validate_parallel(self):
            """Test parallel workers validation."""
            self.assertEqual(validate_parallel("5"), 5)
            self.assertEqual(validate_parallel("1"), 1)
            self.assertEqual(validate_parallel("20"), 20)
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("0")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("25")
            with self.assertRaises(argparse.ArgumentTypeError):
                validate_parallel("abc")
        
        def test_fix_spec_parsing(self):
            """Test --fix parameter parsing."""
            from plugins.integration import PluginIntegration
            
            # Single ID
            result = PluginIntegration.parse_fix_spec("1")
            self.assertEqual(result, {1})
            
            # Multiple IDs
            result = PluginIntegration.parse_fix_spec("1,2,3")
            self.assertEqual(result, {1, 2, 3})
            
            # Range
            result = PluginIntegration.parse_fix_spec("1-5")
            self.assertEqual(result, {1, 2, 3, 4, 5})
            
            # Mixed
            result = PluginIntegration.parse_fix_spec("1,3,5-7")
            self.assertEqual(result, {1, 3, 5, 6, 7})
            
            # All
            result = PluginIntegration.parse_fix_spec("all")
            self.assertEqual(len(result), 13)  # 13 fix types
            
            # None returns all
            result = PluginIntegration.parse_fix_spec(None)
            self.assertEqual(len(result), 13)
        
        def test_feature_spec_parsing(self):
            """Test --feature parameter parsing."""
            from plugins.integration import PluginIntegration
            
            # Single ID
            result = PluginIntegration.parse_feature_spec("1")
            self.assertEqual(result, {1})
            
            # All
            result = PluginIntegration.parse_feature_spec("all")
            self.assertEqual(result, {1, 2})
        
        def test_plugin_manager_initialization(self):
            """Test plugin manager initializes correctly."""
            from plugins.manager import PluginManager
            
            manager = PluginManager()
            self.assertIsNotNone(manager)
            
            # Check fix types are registered
            from plugins.manager import get_fix_types, get_feature_types
            fix_types = get_fix_types()
            self.assertEqual(len(fix_types), 13)
            
            feature_types = get_feature_types()
            self.assertEqual(len(feature_types), 2)
        
        def test_plugin_detection(self):
            """Test basic plugin detection."""
            from plugins.integration import PluginIntegration
            
            integration = PluginIntegration()
            
            # Test with sample content
            content = "vmware is incorrect. Visit `https://example.com` for info."
            issues = integration.detect_issues(content, "https://test.com/page", 
                                               enabled_fix_ids={2, 4})
            
            # Should detect VMware spelling issue
            self.assertIn('spelling', issues)
            integration.cleanup()
    
    # Run the tests
    print(f"\n{TOOL_NAME} v{VERSION} - Unit Tests\n")
    print("=" * 60)
    
    # Create test suite
    loader = unittest.TestLoader()
    suite = loader.loadTestsFromTestCase(TestDocumentationLecturer)
    
    # Run with verbosity
    runner = unittest.TextTestRunner(verbosity=2)
    result = runner.run(suite)
    
    print("=" * 60)
    
    if result.wasSuccessful():
        print(f"\n[OK] All {result.testsRun} tests passed")
        return 0
    else:
        failures = len(result.failures) + len(result.errors)
        print(f"\n[FAIL] {failures} test(s) failed out of {result.testsRun}")
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
        sys.exit(0)
    
    if args.command == 'version':
        print(f"{TOOL_NAME} v{VERSION}")
        sys.exit(0)
    
    if args.command == 'install-tools':
        sys.exit(install_tools())
    
    if args.command == 'test':
        sys.exit(run_tests())
    
    # Handle --list-fixes and --list-features
    if getattr(args, 'list_fixes', False):
        print(DocumentationLecturer.get_fix_help_text())
        sys.exit(0)
    
    if getattr(args, 'list_features', False):
        print(DocumentationLecturer.get_feature_help_text())
        sys.exit(0)
    
    if not validate_args(args):
        sys.exit(1)
    
    # Import dependencies
    check_and_import_dependencies()
    
    # Run the tool
    lecturer = DocumentationLecturer(args)
    lecturer.run()


if __name__ == '__main__':
    main()
