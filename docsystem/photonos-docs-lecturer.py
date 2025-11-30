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
VERSION = "1.0"
TOOL_NAME = "photonos-docs-lecturer.py"

# Check and import required libraries with install suggestions
def check_import(module_name: str, package_name: str = None, pip_name: str = None):
    """Check if module can be imported, provide install suggestion if not."""
    pip_name = pip_name or package_name or module_name
    try:
        return __import__(module_name)
    except ImportError:
        print(f"ERROR: '{module_name}' library not found. Install with: pip install {pip_name}", file=sys.stderr)
        sys.exit(1)

# Required external libraries
requests = check_import('requests')
from requests.adapters import HTTPAdapter
try:
    from requests.packages.urllib3.util.retry import Retry
except ImportError:
    from urllib3.util.retry import Retry

bs4 = check_import('bs4', 'beautifulsoup4')
from bs4 import BeautifulSoup

language_tool_python = check_import('language_tool_python', pip_name='language-tool-python')

# Optional: tqdm for progress bars
try:
    from tqdm import tqdm
    HAS_TQDM = True
except ImportError:
    HAS_TQDM = False
    tqdm = None

# Optional: PIL for image checks
try:
    from PIL import Image
    HAS_PIL = True
except ImportError:
    HAS_PIL = False

# Optional: Google Generative AI for Gemini LLM
try:
    import google.generativeai as genai
    HAS_GEMINI = True
except ImportError:
    HAS_GEMINI = False
    genai = None

# Suppress SSL warnings
requests.packages.urllib3.disable_warnings()


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
            self.model = genai.GenerativeModel('gemini-pro')
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
        """
        issues = []
        
        for match in self.VMWARE_SPELLING_PATTERN.finditer(text_content):
            incorrect_spelling = match.group(0)
            
            # Get context around the match
            start = max(0, match.start() - 30)
            end = min(len(text_content), match.end() + 30)
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
    
    def _map_url_to_local_path(self, page_url: str) -> Optional[str]:
        """Map a page URL to local markdown file path."""
        if not self.local_webserver:
            return None
        
        try:
            parsed = urllib.parse.urlparse(page_url)
            path = parsed.path.strip('/')
            
            # Handle index pages
            if path.endswith('/') or not path:
                path = os.path.join(path, '_index.md')
            elif not path.endswith('.md'):
                path = path + '.md'
            
            # Content path with language
            local_path = os.path.join(
                self.local_webserver, 
                'content', 
                self.language,
                path
            )
            
            # Try alternate paths
            if not os.path.exists(local_path):
                alt_path = os.path.join(self.local_webserver, 'content', path)
                if os.path.exists(alt_path):
                    local_path = alt_path
            
            return local_path if os.path.exists(local_path) else None
            
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
                self._apply_fixes(page_url, all_issues)
            
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
    
    def _apply_fixes(self, page_url: str, issues: Dict[str, List]):
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
        """
        local_path = self._map_url_to_local_path(page_url)
        if not local_path or not os.path.exists(local_path):
            self.logger.debug(f"No local file found for {page_url}")
            return
        
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
                    self.logger.info(f"Applied fixes to {local_path}")
                
        except Exception as e:
            self.logger.error(f"Failed to apply fixes to {local_path}: {e}")
    
    def _fix_vmware_spelling(self, content: str) -> str:
        """Fix incorrect VMware spelling in content.
        
        Replaces variations like 'vmware', 'Vmware', 'VMWare', 'VMWARE' with 'VMware'.
        Preserves URLs and code blocks.
        """
        # Split content to preserve code blocks
        parts = re.split(r'(```[\s\S]*?```|`[^`]+`)', content)
        
        for i, part in enumerate(parts):
            # Skip code blocks
            if part.startswith('```') or part.startswith('`'):
                continue
            # Fix VMware spelling (but not in URLs)
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
        """Fix missing spaces before/after backticks.
        
        - 'word`code`' -> 'word `code`'
        - '`code`word' -> '`code` word'
        """
        # Fix missing space before backtick
        content = self.MISSING_SPACE_BEFORE_BACKTICK.sub(r'\1 \2', content)
        
        # Fix missing space after backtick
        content = self.MISSING_SPACE_AFTER_BACKTICK.sub(r'\1 \2', content)
        
        return content
    
    def _fix_shell_prompts_in_markdown(self, content: str) -> str:
        """Remove shell prompt prefixes from code blocks in markdown.
        
        Transforms:
        ```bash
        $ ls -la
        ```
        
        To:
        ```bash
        ls -la
        ```
        """
        # Find all fenced code blocks
        def fix_code_block(match):
            code_block = match.group(0)
            lines = code_block.split('\n')
            
            fixed_lines = [lines[0]]  # Keep the opening ```lang
            
            for line in lines[1:-1]:  # Skip first and last lines (``` markers)
                fixed_line = line
                for pattern in self.SHELL_PROMPT_PATTERNS:
                    prompt_match = pattern.match(line)
                    if prompt_match:
                        # Remove the prompt, keep the command
                        fixed_line = prompt_match.group(2)
                        break
                fixed_lines.append(fixed_line)
            
            if lines:
                fixed_lines.append(lines[-1])  # Keep the closing ```
            
            return '\n'.join(fixed_lines)
        
        # Match fenced code blocks
        content = re.sub(r'```[\w]*\n[\s\S]*?```', fix_code_block, content)
        
        return content
    
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
    
    def _git_commit_and_push(self) -> bool:
        """Commit and push changes to git repository."""
        if not self.ghrepo_url or not self.gh_repotoken:
            return False
        
        try:
            # Check git
            subprocess.run(['git', '--version'], check=True, capture_output=True)
            
            # Check if in git repo
            result = subprocess.run(['git', 'rev-parse', '--git-dir'], capture_output=True, text=True)
            if result.returncode != 0:
                self.logger.warning("Not in a git repository")
                return False
            
            # Add files
            files_to_add = [self.report_filename, self.log_filename]
            files_to_add.extend(list(self.modified_files))
            
            for f in files_to_add:
                if os.path.exists(f):
                    subprocess.run(['git', 'add', f], check=True)
            
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
        """Run full workflow with fixes and PR."""
        print(f"{TOOL_NAME} v{VERSION} - Run Mode")
        print(f"Log: {self.log_filename}")
        print(f"Report: {self.report_filename}")
        print(f"URL: {self.base_url}")
        print(f"Workers: {self.num_workers}")
        if self.gh_pr:
            print(f"PR Target: {self.ref_ghrepo}")
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
        
        # Analyze and apply fixes
        self.analyze_all_pages()
        
        # Finalize report
        self.finalize_report()
        
        # Git operations
        if self.gh_pr:
            if self._git_commit_and_push():
                self._create_pull_request()
        
        # Summary
        print(f"\n[OK] Workflow complete!")
        print(f"   Report: {self.report_filename}")
        print(f"   Log: {self.log_filename}")
        print(f"   Pages: {self.pages_analyzed}")
        print(f"   Issues: {self.issues_found}")
        print(f"   Fixes: {self.fixes_applied}")
    
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

Examples:
  # Install required tools (run as root/sudo)
  sudo python3 {TOOL_NAME} install-tools

  # Analyze only
  python3 {TOOL_NAME} analyze --website https://127.0.0.1/docs-v5 --parallel 5
  
  # Full workflow with PR
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
        if args.llm == 'gemini' and not args.GEMINI_API_KEY:
            print("[ERROR] --GEMINI_API_KEY required when --llm gemini", file=sys.stderr)
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
    
    # Step 3: Install language-tool-python
    print()
    print("[STEP 3/3] Installing language-tool-python...")
    
    if pip_available:
        try:
            # Check if already installed
            result = subprocess.run(
                [sys.executable, '-m', 'pip', 'show', 'language-tool-python'],
                capture_output=True, text=True
            )
            if result.returncode == 0:
                print("[OK] language-tool-python is already installed")
            else:
                # Install language-tool-python
                subprocess.run(
                    [sys.executable, '-m', 'pip', 'install', 'language-tool-python'],
                    check=True
                )
                print("[OK] language-tool-python installed")
        except subprocess.CalledProcessError as e:
            print(f"[ERROR] Failed to install language-tool-python: {e}", file=sys.stderr)
            success = False
    else:
        print("[ERROR] Cannot install language-tool-python without pip", file=sys.stderr)
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
    
    # Handle install-tools command
    if args.command == 'install-tools':
        sys.exit(install_tools())
    
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
