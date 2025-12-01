#!/usr/bin/env python3
"""
Photon OS Documentation Lecturer
A comprehensive command-line tool for crawling Photon OS documentation served by Nginx,
identifying issues (grammar/spelling, markdown artifacts, orphan links/images, unaligned images),
generating CSV reports, and optionally applying fixes via git push and GitHub PR.

Version: 1.0
Based on analyzer.py with extended features for complete documentation workflow.

Usage:
    python3 photonos-docs-lecturer.py run --website <url> [options]
    python3 photonos-docs-lecturer.py analyze --website <url> [options]
    python3 photonos-docs-lecturer.py version

Commands:
    run      - Execute full workflow (analyze, generate fixes, push changes, create PR)
    analyze  - Generate report only (no fixes, git operations, or PR)
    version  - Display tool version

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
VERSION = "1.3"
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
            # xAI uses HTTP API
            self.xai_endpoint = "https://api.x.ai/v1/chat/completions"
        else:
            raise ValueError(f"Unsupported LLM provider: {provider}")
    
    def translate(self, text: str, target_language: str) -> str:
        """Translate text to target language using LLM."""
        prompt = f"Translate the following text to {target_language}. Preserve any markdown formatting. Only return the translation, no explanations:\n\n{text}"
        return self._generate(prompt)
    
    def fix_grammar(self, text: str, issues: List[Dict]) -> str:
        """Fix grammar issues in text using LLM."""
        issue_desc = "\n".join([f"- {i['message']}: {i.get('suggestion', 'No suggestion')}" for i in issues[:10]])
        prompt = f"""Fix the following grammar issues in the text. Preserve markdown formatting.
Issues found:
{issue_desc}

Text to fix:
{text}

Return only the corrected text."""
        return self._generate(prompt)
    
    def fix_markdown(self, text: str, artifacts: List[str]) -> str:
        """Fix markdown rendering artifacts."""
        prompt = f"""Fix the following markdown rendering issues in the text:
Artifacts found: {', '.join(artifacts[:5])}

Text to fix:
{text}

Return only the corrected markdown text."""
        return self._generate(prompt)
    
    def fix_indentation(self, text: str, issues: List[Dict]) -> str:
        """Fix indentation issues in markdown lists and code blocks."""
        issue_desc = "\n".join([f"- {i.get('context', i.get('type', 'unknown'))}" for i in issues[:10]])
        prompt = f"""Fix the following indentation issues in the markdown text.

Issues found:
{issue_desc}

Common indentation problems to fix:
1. List items not properly aligned
2. Code blocks inside list items not indented correctly (need 4 spaces or 1 tab)
3. Nested content not properly indented under parent list items
4. Inconsistent indentation (mixing tabs and spaces)

Text to fix:
{text}

Return only the corrected markdown text with proper indentation."""
        return self._generate(prompt)
    
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
        """Generate response using xAI API."""
        headers = {
            "Authorization": f"Bearer {self.api_key}",
            "Content-Type": "application/json"
        }
        payload = {
            "model": "grok-beta",
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
    MISSING_SPACE_BEFORE_BACKTICK = re.compile(r'([a-zA-Z])(`[^`]+`)')
    
    # Pattern for missing space after backticks (e.g., "`command`text" should be "`command` text")
    MISSING_SPACE_AFTER_BACKTICK = re.compile(r'(`[^`]+`)([a-zA-Z])')
    
    # Pattern for detecting indentation issues in numbered/bulleted lists
    # Matches lines that start with a number followed by period/parenthesis
    NUMBERED_LIST_PATTERN = re.compile(r'^(\s*)(\d+)([.)])(\s+)(.*)$', re.MULTILINE)
    
    # Patterns for detecting shell prompt prefixes in code blocks that should be removed
    # These are common shell prompts that shouldn't be part of copyable commands
    SHELL_PROMPT_PATTERNS = [
        re.compile(r'^(\$\s+)(.+)$', re.MULTILINE),      # "$ command" - standard user prompt
        re.compile(r'^(#\s+)(.+)$', re.MULTILINE),       # "# command" - root prompt
        re.compile(r'^(>\s+)(.+)$', re.MULTILINE),       # "> command" - alternative prompt
        re.compile(r'^(%\s+)(.+)$', re.MULTILINE),       # "% command" - csh/tcsh prompt
        re.compile(r'^(~\s+)(.+)$', re.MULTILINE),       # "~ command" - home directory prompt
        re.compile(r'^(❯\s*)(.+)$', re.MULTILINE),       # "❯ command" - fancy prompt (e.g., starship, powerline)
        re.compile(r'^(➜\s+)(.+)$', re.MULTILINE),       # "➜  command" - Oh My Zsh robbyrussell theme
        re.compile(r'^(root@\S+[#$]\s*)(.+)$', re.MULTILINE),  # "root@host# command"
        re.compile(r'^(\w+@\S+[#$%]\s*)(.+)$', re.MULTILINE),  # "user@host$ command"
    ]
    
    # Deprecated VMware packages URL pattern
    DEPRECATED_VMWARE_URL = re.compile(r'https?://packages\.vmware\.com/[^\s"\'<>]*')
    VMWARE_URL_REPLACEMENT = 'https://packages-prod.broadcom.com/'
    
    # VMware spelling pattern - must be "VMware" with capital V and M
    # Matches incorrect spellings like "vmware", "Vmware", "VMWare", "VMWARE", etc.
    # Uses word boundaries and explicitly excludes the correct spelling
    VMWARE_SPELLING_PATTERN = re.compile(r'\b((?!VMware)[vV][mM][wW][aA][rR][eE])\b')
    
    # Markdown header without space pattern (e.g., "####Title" should be "#### Title")
    MARKDOWN_HEADER_NO_SPACE = re.compile(r'^(#{2,6})([^\s#].*)$', re.MULTILINE)
    
    # Alignment CSS classes to check
    ALIGNMENT_CLASSES = ['align-center', 'align-left', 'align-right', 'centered', 
                         'img-responsive', 'text-center', 'mx-auto', 'd-block']
    CONTAINER_CLASSES = ['image-container', 'figure', 'gallery', 'img-gallery', 'images-row']
    
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
                        prompt_prefix = match.group(1)
                        actual_command = match.group(2)
                        
                        # Skip if the line looks like a comment (# followed by explanation text)
                        # Comments typically have more words and don't look like commands
                        if prompt_prefix.startswith('#'):
                            # Heuristics to distinguish comments from root prompts:
                            # - Comments often have multiple words with spaces
                            # - Commands typically start with known command names or paths
                            words = actual_command.split()
                            if len(words) > 3 and not actual_command.startswith(('/', './', 'sudo', 'cd', 'ls', 'cat', 'echo', 'export', 'mkdir', 'rm', 'cp', 'mv', 'chmod', 'chown', 'apt', 'yum', 'dnf', 'tdnf', 'pip', 'python', 'npm', 'git', 'docker', 'systemctl', 'service')):
                                continue
                        
                        # Create a context snippet
                        context = line[:80] if len(line) > 80 else line
                        
                        location = f"Shell prompt in code block: '{context}'"
                        fix = f"Remove shell prompt prefix '{prompt_prefix.strip()}' - command should be: '{actual_command}'"
                        
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
                    clean_first_line = match.group(2)
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
        
        These URLs should be replaced with packages-prod.broadcom.com.
        """
        issues = []
        
        # Check all anchor tags for deprecated URLs
        for anchor in soup.find_all('a', href=True):
            href = anchor.get('href', '')
            if self.DEPRECATED_VMWARE_URL.match(href):
                link_text = anchor.get_text().strip()[:50]
                location = f"Deprecated VMware URL: {href}"
                fix = f"Replace with {self.VMWARE_URL_REPLACEMENT} - Link text: '{link_text}'"
                
                self._write_csv_row(page_url, 'deprecated_url', location, fix)
                issues.append({
                    'type': 'deprecated_vmware_url',
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
        
        return issues
    
    def _check_vmware_spelling(self, page_url: str, text_content: str) -> List[Dict]:
        """Check for incorrect VMware spelling.
        
        VMware must be spelled with capital V and M: "VMware"
        Incorrect: vmware, Vmware, VMWare, VMWARE, etc.
        
        Excludes:
        - URLs containing 'vmware' (e.g., github.com/vmware, packages.vmware.com)
        - Domain-like patterns (e.g., packages.vmware.com without https://)
        - Console commands containing vmware
        """
        issues = []
        
        # Pattern to detect if match is within a URL (with or without protocol)
        url_pattern = re.compile(r'https?://[^\s<>"\']+|www\.[^\s<>"\']+|[a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.(com|org|net|io|gov|edu)[^\s<>"\']*')
        
        for match in self.VMWARE_SPELLING_PATTERN.finditer(text_content):
            incorrect_spelling = match.group(0)
            match_start = match.start()
            match_end = match.end()
            
            # Get extended context to check for URL or domain pattern
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
            
            # Check if match is in a domain-like context (e.g., "packages.vmware.com")
            # Look for pattern like "word.vmware.word"
            local_context = text_content[max(0, match_start - 20):min(len(text_content), match_end + 20)]
            if re.search(r'\w+\.' + re.escape(incorrect_spelling) + r'\.\w+', local_context, re.IGNORECASE):
                continue  # Skip domain-like patterns
            
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
            
            # Check for markdown headers missing space after hash symbols
            header_spacing_issues = self._check_markdown_header_spacing(page_url, text_content)
            
            # Apply fixes if running with --gh-pr
            if self.command == 'run' and self.gh_pr:
                all_issues = {
                    'grammar_issues': grammar_issues,
                    'md_artifacts': md_artifacts,
                    'orphan_links': orphan_links,
                    'orphan_images': orphan_images,
                    'formatting_issues': formatting_issues,
                    'indentation_issues': indentation_issues,
                    'shell_prompt_issues': shell_prompt_issues,
                    'mixed_cmd_output_issues': mixed_cmd_output_issues,
                    'deprecated_url_issues': deprecated_url_issues,
                    'vmware_spelling_issues': vmware_spelling_issues,
                    'header_spacing_issues': header_spacing_issues,
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
                - shell_prompt_issues: Shell prompts in code blocks
                - deprecated_url_issues: Deprecated VMware URLs
                - vmware_spelling_issues: Incorrect VMware spelling
                - mixed_cmd_output_issues: Mixed command/output in code blocks
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
                # =========================================================
                
                # Fix VMware spelling (vmware -> VMware)
                vmware_issues = issues.get('vmware_spelling_issues', [])
                if vmware_issues:
                    content = self._fix_vmware_spelling(content)
                
                # Fix deprecated VMware URLs
                deprecated_url_issues = issues.get('deprecated_url_issues', [])
                if deprecated_url_issues:
                    content = self._fix_deprecated_urls(content)
                
                # Fix missing spaces around backticks
                formatting_issues = issues.get('formatting_issues', [])
                if formatting_issues:
                    content = self._fix_backtick_spacing(content)
                
                # Fix shell prompts in code blocks (in markdown source)
                shell_prompt_issues = issues.get('shell_prompt_issues', [])
                if shell_prompt_issues:
                    content = self._fix_shell_prompts_in_markdown(content)
                
                # =========================================================
                # LLM-based fixes (require LLM client)
                # =========================================================
                
                # Apply grammar fixes via LLM if available
                grammar_issues = issues.get('grammar_issues', [])
                if grammar_issues and self.llm_client:
                    try:
                        fixed = self.llm_client.fix_grammar(content, grammar_issues)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM grammar fix failed: {e}")
                
                # Apply markdown fixes via LLM if available
                md_artifacts = issues.get('md_artifacts', [])
                if md_artifacts and self.llm_client:
                    try:
                        fixed = self.llm_client.fix_markdown(content, md_artifacts)
                        if fixed:
                            content = fixed
                    except Exception as e:
                        self.logger.error(f"LLM markdown fix failed: {e}")
                
                # Fix mixed command/output code blocks via LLM
                mixed_cmd_output_issues = issues.get('mixed_cmd_output_issues', [])
                if mixed_cmd_output_issues and self.llm_client:
                    try:
                        content = self._fix_mixed_command_output_llm(content, mixed_cmd_output_issues)
                    except Exception as e:
                        self.logger.error(f"LLM mixed command/output fix failed: {e}")
                
                # Fix indentation issues via LLM
                indentation_issues = issues.get('indentation_issues', [])
                if indentation_issues and self.llm_client:
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
                    
                    # Log what types of fixes were applied
                    applied_fixes = []
                    if issues.get('vmware_spelling_issues'):
                        applied_fixes.append('VMware spelling')
                    if issues.get('deprecated_url_issues'):
                        applied_fixes.append('deprecated URLs')
                    if issues.get('formatting_issues'):
                        applied_fixes.append('backtick spacing')
                    if issues.get('shell_prompt_issues'):
                        applied_fixes.append('shell prompts')
                    if issues.get('grammar_issues') and self.llm_client:
                        applied_fixes.append('grammar (LLM)')
                    if issues.get('md_artifacts') and self.llm_client:
                        applied_fixes.append('markdown (LLM)')
                    if issues.get('indentation_issues') and self.llm_client:
                        applied_fixes.append('indentation (LLM)')
                    if issues.get('mixed_cmd_output_issues') and self.llm_client:
                        applied_fixes.append('mixed cmd/output (LLM)')
                    
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
        - URLs (with or without protocol)
        - Domain-like patterns (e.g., packages.vmware.com)
        """
        # Split content to preserve code blocks and URLs
        # Match: fenced code blocks, inline code, URLs with protocol, and domain patterns
        parts = re.split(r'(```[\s\S]*?```|`[^`]+`|https?://[^\s<>"\')\]]+|www\.[^\s<>"\')\]]+|[a-zA-Z0-9-]+\.vmware\.[a-zA-Z0-9-]+[^\s<>"\')\]]*)', content, flags=re.IGNORECASE)
        
        for i, part in enumerate(parts):
            # Skip code blocks
            if part.startswith('```') or part.startswith('`'):
                continue
            # Skip URLs
            if part.startswith('http://') or part.startswith('https://') or part.startswith('www.'):
                continue
            # Skip domain-like patterns (e.g., packages.vmware.com)
            if re.match(r'^[a-zA-Z0-9-]+\.vmware\.[a-zA-Z0-9-]+', part, re.IGNORECASE):
                continue
            # Fix VMware spelling in regular text
            parts[i] = self.VMWARE_SPELLING_PATTERN.sub('VMware', part)
        
        return ''.join(parts)
    
    def _fix_deprecated_urls(self, content: str) -> str:
        """Fix deprecated packages.vmware.com URLs.
        
        Replaces https://packages.vmware.com/* with https://packages-prod.broadcom.com/*
        """
        # Replace the base URL while preserving the path
        def replace_url(match):
            old_url = match.group(0)
            # Extract path after packages.vmware.com
            path_match = re.search(r'packages\.vmware\.com(/[^\s"\'<>]*)?', old_url)
            if path_match:
                path = path_match.group(1) or ''
                return f'https://packages-prod.broadcom.com{path}'
            return old_url
        
        return self.DEPRECATED_VMWARE_URL.sub(replace_url, content)
    
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
                        # Remove the prompt, keep the command
                        fixed_line = prompt_match.group(2)
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
        """
        if not self.llm_client or not issues:
            return content
        
        # Create prompt for LLM
        commands = [issue.get('command', '') for issue in issues[:5]]
        commands_str = '\n'.join(f"- {cmd}" for cmd in commands if cmd)
        
        prompt = f"""In the following markdown content, there are code blocks that mix commands with their output.
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

Content to fix:
{content}

Return only the fixed markdown content, no explanations."""

        try:
            fixed = self.llm_client._generate(prompt)
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
            return True  # No fork needed
        
        try:
            # Set GH_TOKEN environment
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            # Check gh CLI
            subprocess.run(['gh', '--version'], check=True, capture_output=True)
            
            # Parse ref repo
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/').rstrip('.git')
            
            # Check if fork already exists
            self.logger.info(f"Checking for existing fork of {repo_path}...")
            result = subprocess.run(
                ['gh', 'repo', 'view', f"{self.gh_username}/{repo_path.split('/')[-1]}"],
                capture_output=True, text=True, env=env
            )
            
            if result.returncode == 0:
                self.logger.info("Fork already exists")
                return True
            
            # Create fork
            self.logger.info(f"Forking {repo_path}...")
            result = subprocess.run(
                ['gh', 'repo', 'fork', repo_path, '--clone=false'],
                capture_output=True, text=True, check=True, env=env
            )
            self.logger.info("Fork created successfully")
            return True
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Fork failed: {e.stderr}")
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
- **VMware spelling**: Corrected incorrect spellings (vmware, Vmware, etc.) to VMware
- **Deprecated URLs**: Updated packages.vmware.com URLs to packages-prod.broadcom.com
- **Backtick spacing**: Fixed missing spaces before/after inline code
- **Shell prompts**: Removed shell prompt prefixes ($, #, ❯) from code blocks

### LLM-Assisted Fixes (Requires --llm flag)
- **Grammar/spelling errors**: Language and grammar corrections
- **Markdown artifacts**: Fixed unrendered markdown syntax
- **Mixed command/output**: Separated command and output into distinct code blocks

### Issues Reported (Manual Review Recommended)
- **Broken links**: Orphan URLs requiring manual verification
- **Broken images**: Missing or inaccessible image files
- **Unaligned images**: Images lacking proper CSS alignment
- **Indentation issues**: List item indentation problems

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
- **VMware spelling**: Corrected incorrect spellings (vmware, Vmware, etc.) to VMware
- **Deprecated URLs**: Updated packages.vmware.com URLs to packages-prod.broadcom.com
- **Backtick spacing**: Fixed missing spaces before/after inline code
- **Shell prompts**: Removed shell prompt prefixes ($, #, ❯) from code blocks

### LLM-Assisted Fixes (Requires --llm flag)
- **Grammar/spelling errors**: Language and grammar corrections
- **Markdown artifacts**: Fixed unrendered markdown syntax
- **Mixed command/output**: Separated command and output into distinct code blocks

### Issues Reported (Manual Review Recommended)
- **Broken links**: Orphan URLs requiring manual verification
- **Broken images**: Missing or inaccessible image files
- **Unaligned images**: Images lacking proper CSS alignment
- **Indentation issues**: List item indentation problems

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
        - If no, creates a new PR
        
        On subsequent calls:
        - Updates the existing PR body with new fix information
        
        Returns:
            True if PR was created/updated successfully, False otherwise.
        """
        if not self.gh_pr or not self.ref_ghrepo:
            return False
        
        try:
            env = os.environ.copy()
            env['GH_TOKEN'] = self.gh_repotoken
            
            # Parse ref repo
            parsed = urllib.parse.urlparse(self.ref_ghrepo)
            repo_path = parsed.path.strip('/').rstrip('.git')
            
            head_branch = self.ghrepo_branch
            base_branch = self.ref_ghbranch
            
            pr_body = self._generate_pr_body()
            
            if self.pr_url is None:
                # First, check if an open PR already exists (from previous runs)
                if self._find_existing_open_pr():
                    # Reuse existing PR - just update the body
                    return self._update_pr_body(pr_body)
                
                # No existing PR, create a new one
                pr_title = f"Documentation fixes - {self.timestamp}"
                result = subprocess.run([
                    'gh', 'pr', 'create',
                    '--title', pr_title,
                    '--body', pr_body,
                    '--head', f"{self.gh_username}:{head_branch}",
                    '--base', base_branch,
                    '--repo', repo_path
                ], capture_output=True, text=True, env=env)
                
                if result.returncode == 0:
                    self.pr_url = result.stdout.strip()
                    # Extract PR number from URL
                    pr_match = re.search(r'/pull/(\d+)', self.pr_url)
                    if pr_match:
                        self.pr_number = int(pr_match.group(1))
                    self.logger.info(f"Pull request created: {self.pr_url}")
                    print(f"\n[PR] Created: {self.pr_url}")
                    return True
                else:
                    self.logger.error(f"PR creation failed: {result.stderr}")
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
            repo_path = parsed.path.strip('/').rstrip('.git')
            
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
  | Deprecated URLs          | Always      | Automatic     | packages.vmware.com ->    |
  |                          |             |               | packages-prod.broadcom.com|
  | Backtick spacing         | Always      | Automatic     | word`code` -> word `code` |
  | Shell prompts            | Always      | Automatic     | Remove $, #, ~, etc.      |
  | Code block language      | Always      | Automatic     | Add python/console hint   |
  | Grammar/spelling         | Always      | LLM-assisted  | Requires --llm flag       |
  | Markdown artifacts       | Always      | LLM-assisted  | Requires --llm flag       |
  | Mixed command/output     | Always      | LLM-assisted  | Requires --llm flag       |
  | Indentation issues       | Always      | LLM-assisted  | Requires --llm flag       |
  | Broken links             | Always      | Report only   | Manual review needed      |
  | Broken images            | Always      | Report only   | Manual review needed      |
  | Unaligned images         | Always      | Report only   | Manual review needed      |
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
        required=True,
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
        
        def test_markdown_patterns(self):
            patterns = DocumentationLecturer.MARKDOWN_PATTERNS
            test_text = "## Header\n* bullet\n[link](url)"
            for pattern in patterns[:3]:
                self.assertTrue(pattern.search(test_text))
        
        def test_missing_space_before_backtick(self):
            pattern = DocumentationLecturer.MISSING_SPACE_BEFORE_BACKTICK
            # Should match: word immediately followed by backtick code
            self.assertTrue(pattern.search("Clone`the project`"))
            self.assertTrue(pattern.search("Run`command`"))
            # Should not match: proper spacing
            self.assertIsNone(pattern.search("Clone `the project`"))
            self.assertIsNone(pattern.search("Run `command`"))
        
        def test_missing_space_after_backtick(self):
            pattern = DocumentationLecturer.MISSING_SPACE_AFTER_BACKTICK
            # Should match: backtick code immediately followed by word
            self.assertTrue(pattern.search("`command`and"))
            self.assertTrue(pattern.search("`code`text"))
            # Should not match: proper spacing
            self.assertIsNone(pattern.search("`command` and"))
            self.assertIsNone(pattern.search("`code` text"))
        
        def test_shell_prompt_patterns(self):
            patterns = DocumentationLecturer.SHELL_PROMPT_PATTERNS
            # Test "$ command" pattern (first pattern)
            dollar_pattern = patterns[0]
            match = dollar_pattern.match("$ ls -la")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "$ ")
            self.assertEqual(match.group(2), "ls -la")
            
            # Test "# command" pattern (second pattern)
            hash_pattern = patterns[1]
            match = hash_pattern.match("# systemctl restart nginx")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "# ")
            self.assertEqual(match.group(2), "systemctl restart nginx")
            
            # Test "❯ command" pattern (fancy prompt like starship/powerline)
            fancy_pattern = patterns[4]
            match = fancy_pattern.match("❯ sudo wg show")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "❯ ")
            self.assertEqual(match.group(2), "sudo wg show")
            
            # Test without space after ❯
            match = fancy_pattern.match("❯wg genkey")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "❯")
            self.assertEqual(match.group(2), "wg genkey")
            
            # Test "➜  command" pattern (Oh My Zsh robbyrussell theme)
            omz_pattern = patterns[5]
            match = omz_pattern.match("➜  git status")
            self.assertIsNotNone(match)
            self.assertEqual(match.group(1), "➜  ")
            self.assertEqual(match.group(2), "git status")
            
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
            self.assertIsNone(pattern.match("https://packages-prod.broadcom.com/"))
        
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
            self.assertIn("packages-prod.broadcom.com", fixed)
            self.assertIn("/photon/5.0/", fixed)  # Path should be preserved
            self.assertNotIn("packages.vmware.com", fixed)
            
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
            content = "Run the command`ls -la`"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "Run the command `ls -la`")
            
            # Test missing space after backtick
            content = "`command`and then"
            fixed = lecturer._fix_backtick_spacing(content)
            self.assertEqual(fixed, "`command` and then")
            
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
