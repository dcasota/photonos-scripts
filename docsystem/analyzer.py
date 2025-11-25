#!/usr/bin/env python3
"""
Photon OS Documentation Analyzer
A command-line tool for analyzing documentation pages served by Nginx on Photon OS.

Identifies issues:
- Grammar and spelling errors
- Markdown rendering artifacts
- Orphan URL links (broken links)
- Orphan picture links (broken images)
- Unaligned multiple pictures per page

Generates a CSV report with findings.
Optionally commits and pushes fixes to a git repository.
"""

import argparse
import csv
import datetime
import logging
import os
import re
import subprocess
import sys
import time
import urllib.parse
import urllib.robotparser
from collections import deque
from typing import Dict, List, Set, Tuple, Optional
import threading
from concurrent.futures import ThreadPoolExecutor, as_completed
from tqdm import tqdm

try:
    import requests
    from requests.adapters import HTTPAdapter
    from requests.packages.urllib3.util.retry import Retry
except ImportError:
    print("ERROR: 'requests' library not found. Install with: pip install requests", file=sys.stderr)
    sys.exit(1)

try:
    from bs4 import BeautifulSoup
except ImportError:
    print("ERROR: 'beautifulsoup4' library not found. Install with: pip install beautifulsoup4", file=sys.stderr)
    sys.exit(1)

try:
    import language_tool_python
except ImportError:
    print("ERROR: 'language-tool-python' library not found. Install with: pip install language-tool-python", file=sys.stderr)
    sys.exit(1)

try:
    from PIL import Image
    import io
except ImportError:
    print("ERROR: 'Pillow' library not found. Install with: pip install Pillow", file=sys.stderr)
    sys.exit(1)


class DocumentationAnalyzer:
    """Main analyzer class for Photon OS documentation."""
    
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
    
    def __init__(self, base_url: str, num_workers: int = 1, 
                 github_url: Optional[str] = None,
                 github_token: Optional[str] = None, 
                 github_username: Optional[str] = None,
                 github_branch: Optional[str] = None,
                 github_pr: bool = False):
        """Initialize the analyzer with base URL and worker count."""
        # Generate filenames first
        timestamp = datetime.datetime.now().isoformat()
        self.report_filename: str = f"report-{timestamp}.csv"
        self.log_filename: str = f"report-{timestamp}.log"
        
        # Git/GitHub configuration
        self.github_url = github_url
        self.github_token = github_token
        self.github_username = github_username
        self.github_branch = github_branch
        self.github_pr = github_pr
        self.git_enabled = bool(github_url and github_token and github_username)
        
        # Setup logging to file (not console)
        logging.basicConfig(
            level=logging.INFO,
            format='%(asctime)s - %(levelname)s - %(message)s',
            handlers=[
                logging.FileHandler(self.log_filename, mode='w', encoding='utf-8')
            ]
        )
        self.logger = logging.getLogger(__name__)
        
        self.base_url = base_url.rstrip('/')
        # Start from base URL - will discover structure automatically
        self.effective_url = self.base_url
        
        # Number of parallel workers
        self.num_workers = max(1, min(20, num_workers))
        self.logger.info(f"Using {self.num_workers} parallel worker(s)")
        
        # Setup HTTP session with retries
        self.session = self._create_session()
        
        # Initialize tracking sets
        self.visited_urls: Set[str] = set()
        self.sitemap: List[str] = []
        
        # Initialize grammar checker (will be loaded lazily)
        self.grammar_tool: Optional[language_tool_python.LanguageTool] = None
        self.grammar_tool_lock = threading.Lock()  # Thread-safe grammar checker access
        
        # CSV report data
        self.report_data: List[Dict[str, str]] = []
        
        # Thread-safe CSV writing lock
        self.csv_lock = threading.Lock()
        
        # Progress bar
        self.progress_bar: Optional[tqdm] = None
        
        # Initialize CSV immediately with headers (after logger is set up)
        self._initialize_csv()
    
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
        # Disable SSL verification for self-signed certificates
        session.verify = False
        # Suppress SSL warnings
        requests.packages.urllib3.disable_warnings()
        return session
    
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
            # Use lock to ensure thread-safe writes
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
        except Exception as e:
            self.logger.error(f"Failed to write CSV row: {e}")
    
    def validate_connectivity(self) -> bool:
        """Test connectivity to base URL."""
        self.logger.info(f"Testing connectivity to {self.base_url}")
        try:
            response = self.session.head(self.base_url, timeout=10)
            if response.status_code < 400:
                self.logger.info(f"Successfully connected to {self.base_url}")
                return True
            else:
                self.logger.error(f"Server returned status {response.status_code}")
                return False
        except requests.exceptions.RequestException as e:
            self.logger.error(f"Failed to connect to {self.base_url}: {e}")
            return False
    
    def _check_robots_txt(self) -> urllib.robotparser.RobotFileParser:
        """Check and parse robots.txt if available."""
        robots_url = f"{self.base_url}/robots.txt"
        rp = urllib.robotparser.RobotFileParser()
        rp.set_url(robots_url)
        try:
            # Try to fetch robots.txt using requests (SSL already disabled)
            response = self.session.get(robots_url, timeout=10)
            if response.status_code == 200:
                # Parse the content directly
                rp.parse(response.text.splitlines())
                self.logger.info("robots.txt parsed successfully")
        except Exception as e:
            self.logger.warning(f"Could not parse robots.txt: {e}")
        return rp
    
    def _parse_sitemap_xml(self) -> List[str]:
        """Try to parse sitemap.xml if available."""
        # Try sitemap.xml at base URL first, then at root domain
        parsed_base = urllib.parse.urlparse(self.base_url)
        
        # First try at the provided path
        sitemap_url = f"{self.base_url}/sitemap.xml"
        self.logger.info(f"Checking for sitemap.xml at {sitemap_url}")
        
        urls = self._try_parse_sitemap(sitemap_url)
        if urls:
            return urls
        
        # If not found and we're in a subdirectory, try at root
        if parsed_base.path and parsed_base.path != '/':
            root_url = f"{parsed_base.scheme}://{parsed_base.netloc}/sitemap.xml"
            self.logger.info(f"Checking for sitemap.xml at root: {root_url}")
            urls = self._try_parse_sitemap(root_url)
            if urls:
                # Filter URLs to only include those under our base path
                # Need to check both full URL and path component
                base_path = parsed_base.path.rstrip('/')
                filtered_urls = []
                for u in urls:
                    # Check if URL starts with base URL
                    if u.startswith(self.base_url):
                        filtered_urls.append(u)
                    # Or check if the path contains our base path
                    elif base_path and base_path in urllib.parse.urlparse(u).path:
                        filtered_urls.append(u)
                
                self.logger.info(f"Filtered to {len(filtered_urls)} URLs under {self.base_url}")
                if filtered_urls:
                    return filtered_urls
        
        return []
    
    def _try_parse_sitemap(self, sitemap_url: str) -> List[str]:
        """Try to parse a sitemap from a specific URL."""
        try:
            response = self.session.get(sitemap_url, timeout=10)
            if response.status_code != 200:
                return []
            
            # Try XML parser first, fallback to lxml or html.parser
            for parser in ['xml', 'lxml-xml', 'lxml', 'html.parser']:
                try:
                    soup = BeautifulSoup(response.content, parser)
                    break
                except Exception:
                    continue
            else:
                # No parser worked
                raise Exception("No suitable parser found for XML")
            
            urls = []
            base_parsed = urllib.parse.urlparse(self.base_url)
            base_path = base_parsed.path.rstrip('/')
            
            for url_tag in soup.find_all('url'):
                loc = url_tag.find('loc')
                if loc:
                    url_text = loc.get_text().strip()
                    parsed_url = urllib.parse.urlparse(url_text)
                    
                    # Replace domain and intelligently map paths
                    # The sitemap may have paths like /photon/docs-v5/
                    # But the actual server structure may be /docs-v5/
                    # We need to strip common prefixes and map correctly
                    
                    # If same domain and user specified a path, do early filtering
                    if parsed_url.netloc == base_parsed.netloc and base_path:
                        # Check if this URL is under the requested base path
                        if not (parsed_url.path.startswith(base_path + '/') or parsed_url.path == base_path):
                            # URL not under requested path, skip it
                            continue
                    
                    if parsed_url.netloc != base_parsed.netloc:
                        original_path = parsed_url.path
                        
                        if base_path:
                            # User specified a specific path (e.g., /docs-v5)
                            # Map sitemap paths to user's base path
                            # E.g., sitemap: /photon/docs-v5/page.html → /docs-v5/page.html
                            
                            base_suffix = base_path.split('/')[-1]  # e.g., "docs-v5"
                            
                            if base_suffix and f'/{base_suffix}/' in original_path:
                                # Found the suffix, extract everything FROM it
                                idx = original_path.find(f'/{base_suffix}/')
                                new_path = original_path[idx:]  # Keep /docs-v5/page.html
                            elif base_suffix and original_path.endswith(f'/{base_suffix}'):
                                # Exact match: /photon/docs-v5 → /docs-v5
                                idx = original_path.find(f'/{base_suffix}')
                                new_path = original_path[idx:]
                            else:
                                # No match - skip this URL as it's for a different version
                                continue
                        else:
                            # User provided NO base path (e.g., https://127.0.0.1)
                            # Strip known prefixes like /photon/ to get actual paths
                            # Sitemap: /photon/docs-v5/ → /docs-v5/
                            
                            # Try to strip /photon/ prefix if it exists
                            if original_path.startswith('/photon/'):
                                new_path = original_path[7:]  # Remove '/photon'
                            elif original_path == '/photon':
                                new_path = '/'
                            else:
                                # No /photon/ prefix, use as-is
                                new_path = original_path
                        
                        # Construct final URL with new domain and mapped path
                        url_text = urllib.parse.urlunparse(
                            base_parsed._replace(
                                path=new_path,
                                params=parsed_url.params,
                                query=parsed_url.query,
                                fragment=''
                            )
                        )
                    
                    urls.append(url_text)
            
            return urls
        except Exception as e:
            self.logger.debug(f"Could not parse sitemap at {sitemap_url}: {e}")
            return []
    
    def _is_valid_page_url(self, url: str) -> bool:
        """Check if URL is valid for analysis."""
        parsed = urllib.parse.urlparse(url)
        
        # Must be under effective URL
        if not url.startswith(self.effective_url):
            return False
        
        # Must be same domain
        base_parsed = urllib.parse.urlparse(self.base_url)
        if parsed.netloc != base_parsed.netloc:
            return False
        
        # Should be HTML page
        path = parsed.path.lower()
        if path.endswith(('.pdf', '.zip', '.tar', '.gz', '.jpg', '.png', '.gif', '.css', '.js')):
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
                self.logger.warning(f"Page returned {response.status_code}: {url}")
                return []
            
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Extract all links
            for anchor in soup.find_all('a', href=True):
                href = anchor.get('href', '').strip()
                if not href:
                    continue
                
                # Resolve relative URLs
                full_url = urllib.parse.urljoin(url, href)
                
                # Remove fragment
                parsed = urllib.parse.urlparse(full_url)
                clean_url = urllib.parse.urlunparse(parsed._replace(fragment=''))
                
                if self._is_valid_page_url(clean_url) and clean_url not in self.visited_urls:
                    links.append(clean_url)
            
        except Exception as e:
            self.logger.error(f"Failed to crawl {url}: {e}")
        
        return links
    
    def generate_sitemap(self):
        """Generate sitemap by crawling the site."""
        self.logger.info("Generating sitemap...")
        
        # Clear any previous state (important for reuse scenarios)
        self.sitemap.clear()
        self.visited_urls.clear()
        
        # Try sitemap.xml first
        sitemap_urls = self._parse_sitemap_xml()
        if sitemap_urls:
            self.sitemap = sitemap_urls
            self.visited_urls.update(sitemap_urls)
            self.logger.info(f"Using sitemap.xml with {len(sitemap_urls)} pages")
            return
        
        # Fallback to crawling
        self.logger.info("sitemap.xml not found, crawling site...")
        robots = self._check_robots_txt()
        
        queue = deque([(self.effective_url, 0)])
        self.visited_urls.add(self.effective_url)
        
        while queue:
            url, depth = queue.popleft()
            
            # Check robots.txt
            if not robots.can_fetch("*", url):
                self.logger.debug(f"Skipping (robots.txt): {url}")
                continue
            
            self.sitemap.append(url)
            self.logger.info(f"Crawling [{len(self.sitemap)}]: {url}")
            
            # Extract links from this page
            links = self._crawl_page(url, depth)
            for link in links:
                if link not in self.visited_urls:
                    self.visited_urls.add(link)
                    queue.append((link, depth + 1))
            
            # Rate limiting
            time.sleep(1)
        
        self.logger.info(f"Sitemap generated with {len(self.sitemap)} pages")
    
    def _get_grammar_tool(self) -> language_tool_python.LanguageTool:
        """Lazy load grammar checking tool (thread-safe)."""
        # Use double-checked locking pattern for thread-safe lazy initialization
        if self.grammar_tool is None:
            with self.grammar_tool_lock:
                # Check again inside lock to prevent race condition
                if self.grammar_tool is None:
                    self.logger.info("Initializing grammar checker (one-time setup)...")
                    try:
                        # Initialize once and keep alive for all pages
                        self.grammar_tool = language_tool_python.LanguageTool('en-US', remote_server=None)
                        self.logger.info("Grammar checker initialized and ready")
                    except Exception as e:
                        self.logger.error(f"Failed to initialize grammar checker: {e}")
                        raise
        return self.grammar_tool
    
    def _check_grammar(self, page_url: str, text: str):
        """Check text for grammar issues (thread-safe)."""
        try:
            tool = self._get_grammar_tool()
            
            # More aggressive text limiting for speed
            max_text_length = 5000  # Reduced from 10K to 5K for faster checking
            if len(text) > max_text_length:
                text = text[:max_text_length]
                self.logger.debug(f"Truncated text to {max_text_length} chars for grammar check")
            
            # Check grammar with lock (LanguageTool might not be thread-safe)
            with self.grammar_tool_lock:
                matches = tool.check(text)
            
            # Filter out false positives for technical documentation
            filtered_matches = []
            false_positive_rules = {
                'MORFOLOGIK_RULE_EN_US',  # Spell-checker: flags technical terms, commands, package names
                'UPPERCASE_SENTENCE_START',  # Technical docs often start list items with commands (lowercase)
            }
            
            for match in matches:
                rule_id = getattr(match, 'rule_id', match.category)
                
                # Skip rules that cause false positives in technical documentation
                if rule_id in false_positive_rules:
                    self.logger.debug(f"Skipping {rule_id} false positive: {match.context}")
                    continue
                
                filtered_matches.append(match)
            
            # Deduplicate matches by rule_id and fix suggestion to avoid duplicate entries
            seen_issues = set()
            unique_matches = []
            
            for match in filtered_matches:
                rule_id = getattr(match, 'rule_id', match.category)
                suggestions = ', '.join(match.replacements[:3]) if match.replacements else 'No suggestions'
                fix = f"[{rule_id}] {match.message}. Suggestions: {suggestions}"
                
                # Create a unique key for this issue type
                issue_key = (rule_id, fix)
                
                if issue_key not in seen_issues:
                    seen_issues.add(issue_key)
                    unique_matches.append(match)
            
            # Report only unique grammar issues (limit to 5 unique types per page)
            for match in unique_matches[:5]:
                try:
                    context = match.context
                    offset = match.offset
                    error_length = match.error_length  # Note: snake_case in this version
                    
                    # Extract sentence with error
                    start = max(0, offset - 20)
                    end = min(len(context), offset + error_length + 20)
                    location = f"...{context[start:end]}..."
                    
                    suggestions = ', '.join(match.replacements[:3]) if match.replacements else 'No suggestions'
                    rule_id = getattr(match, 'rule_id', match.category)  # Use rule_id (snake_case)
                    fix = f"[{rule_id}] {match.message}. Suggestions: {suggestions}"
                    
                    self._write_csv_row(page_url, 'grammar', location, fix)
                except Exception as e:
                    self.logger.debug(f"Error processing grammar match: {e}")
                
        except Exception as e:
            self.logger.error(f"Grammar check failed for {page_url}: {e}")
            # Don't fail the entire analysis, just skip grammar for this page
    
    def _check_markdown_artifacts(self, page_url: str, html_content: str, text_content: str):
        """Check for unrendered markdown artifacts."""
        issues_found = []
        
        for pattern in self.MARKDOWN_PATTERNS:
            matches = pattern.finditer(text_content)
            for match in matches:
                snippet = match.group(0)
                # Check if it's actually in the visible text (not in code blocks)
                soup = BeautifulSoup(html_content, 'html.parser')
                
                # Remove code blocks before checking
                for code in soup.find_all(['code', 'pre']):
                    code.decompose()
                
                clean_text = soup.get_text()
                if snippet in clean_text:
                    issues_found.append(snippet)
        
        for issue in issues_found[:5]:  # Limit to 5 per page
            self._write_csv_row(
                page_url,
                'markdown',
                f"Unrendered markdown: {issue[:100]}",
                "Render properly or escape markdown syntax"
            )
    
    def _check_url_link(self, url: str) -> Tuple[bool, int]:
        """Check if a URL link is valid (not broken)."""
        try:
            # Reduced timeout for faster checking
            response = self.session.head(url, timeout=3, allow_redirects=True)
            return response.status_code < 400, response.status_code
        except requests.exceptions.Timeout:
            return False, 0
        except Exception as e:
            self.logger.debug(f"Link check failed for {url}: {e}")
            return False, -1
    
    def _check_orphan_links(self, page_url: str, soup: BeautifulSoup):
        """Check for broken links (orphan URLs)."""
        links = soup.find_all('a', href=True)
        
        # Get base domain to distinguish internal vs external links
        page_parsed = urllib.parse.urlparse(page_url)
        page_domain = page_parsed.netloc
        
        checked_urls = set()  # Avoid checking same URL multiple times
        
        for anchor in links:
            href = anchor.get('href', '').strip()
            if not href:
                continue
            
            # Resolve relative URLs
            full_url = urllib.parse.urljoin(page_url, href)
            parsed = urllib.parse.urlparse(full_url)
            
            # Only check HTTP(S) links
            if parsed.scheme not in ('http', 'https'):
                continue
            
            # Skip if already checked
            if full_url in checked_urls:
                continue
            checked_urls.add(full_url)
            
            # Skip external links (too slow and often temporary failures)
            if parsed.netloc != page_domain:
                continue
            
            # Check link (only internal links now)
            is_valid, status_code = self._check_url_link(full_url)
            if not is_valid:
                link_text = anchor.get_text().strip()[:50]
                location = f"Link text: '{link_text}', URL: {full_url}"
                fix = f"Remove or update link (status: {status_code})"
                self._write_csv_row(page_url, 'orphan_url', location, fix)
            
            # Reduced rate limiting (only checking internal links now)
            time.sleep(0.1)
    
    def _check_orphan_images(self, page_url: str, soup: BeautifulSoup):
        """Check for broken image links (orphan pictures)."""
        images = soup.find_all('img', src=True)
        
        # Get base domain
        page_parsed = urllib.parse.urlparse(page_url)
        page_domain = page_parsed.netloc
        
        checked_urls = set()
        
        for img in images:
            src = img.get('src', '').strip()
            if not src:
                continue
            
            # Resolve relative URLs
            full_url = urllib.parse.urljoin(page_url, src)
            parsed = urllib.parse.urlparse(full_url)
            
            # Only check HTTP(S) images
            if parsed.scheme not in ('http', 'https'):
                continue
            
            # Skip if already checked
            if full_url in checked_urls:
                continue
            checked_urls.add(full_url)
            
            # Skip external images (too slow)
            if parsed.netloc != page_domain:
                continue
            
            # Check image (only internal images)
            is_valid, status_code = self._check_url_link(full_url)
            if not is_valid:
                alt_text = img.get('alt', '')[:50]
                location = f"Alt text: '{alt_text}', URL: {full_url}"
                fix = f"Remove or fix image path (status: {status_code})"
                self._write_csv_row(page_url, 'orphan_picture', location, fix)
            
            # Reduced rate limiting
            time.sleep(0.1)
    
    def _check_image_alignment(self, page_url: str, soup: BeautifulSoup):
        """Check for unaligned multiple images on a page."""
        images = soup.find_all('img')
        
        if len(images) <= 1:
            return  # No issue if only 0 or 1 image
        
        # Check if images have alignment classes or are in container
        unaligned_images = []
        
        for img in images:
            # Check for common alignment classes
            img_class = img.get('class', [])
            if isinstance(img_class, str):
                img_class = [img_class]
            
            has_alignment = any(cls in img_class for cls in 
                              ['align-center', 'align-left', 'align-right', 'centered', 'img-responsive'])
            
            # Check parent containers
            parent = img.parent
            if parent:
                parent_class = parent.get('class', [])
                if isinstance(parent_class, str):
                    parent_class = [parent_class]
                has_alignment = has_alignment or any(cls in parent_class for cls in 
                                                     ['image-container', 'figure', 'gallery'])
            
            if not has_alignment:
                unaligned_images.append(img)
        
        if len(unaligned_images) > 1:
            image_srcs = [img.get('src', '')[:50] for img in unaligned_images[:3]]
            location = f"{len(unaligned_images)} unaligned images: {', '.join(image_srcs)}"
            fix = "Add CSS alignment classes or wrap images in container div"
            self._write_csv_row(page_url, 'unaligned_images', location, fix)
    
    def analyze_page(self, page_url: str):
        """Analyze a single page for all issue types."""
        self.logger.info(f"Analyzing: {page_url}")
        
        try:
            response = self.session.get(page_url, timeout=10)
            if response.status_code >= 400:
                # Page is orphaned (404, 403, etc.) - log and skip all other checks
                self.logger.warning(f"Orphaned page detected (HTTP {response.status_code}): {page_url}")
                self._write_csv_row(
                    page_url,
                    'orphan_page',
                    f"HTTP {response.status_code} - Page not accessible",
                    "Remove from sitemap or fix page availability"
                )
                # Skip all other checks for orphaned pages
                return
            
            # Parse HTML
            soup = BeautifulSoup(response.content, 'html.parser')
            
            # Try to extract main content
            main_content = soup.find('div', id='content') or soup.find('main') or soup.find('article') or soup
            
            # Extract text (removing scripts and styles)
            for script in main_content.find_all(['script', 'style', 'nav', 'footer', 'header']):
                script.decompose()
            
            text_content = main_content.get_text(separator=' ', strip=True)
            html_content = str(main_content)
            
            # Perform analyses (only for accessible pages)
            self._check_grammar(page_url, text_content)
            self._check_markdown_artifacts(page_url, html_content, text_content)
            self._check_orphan_links(page_url, soup)
            self._check_orphan_images(page_url, soup)
            self._check_image_alignment(page_url, soup)
            
        except requests.exceptions.Timeout:
            # Connection timeout - treat as orphaned
            self.logger.warning(f"Timeout accessing page: {page_url}")
            self._write_csv_row(
                page_url,
                'orphan_page',
                "Connection timeout",
                "Check page availability or network connectivity"
            )
        except requests.exceptions.ConnectionError:
            # Connection error - treat as orphaned
            self.logger.warning(f"Connection error accessing page: {page_url}")
            self._write_csv_row(
                page_url,
                'orphan_page',
                "Connection error",
                "Check page availability or server status"
            )
        except Exception as e:
            # Other errors during analysis
            self.logger.error(f"Failed to analyze {page_url}: {e}")
            self._write_csv_row(
                page_url,
                'analysis_error',
                str(e),
                "Check page structure and content"
            )
    
    def analyze_all_pages(self):
        """Analyze all pages in the sitemap (with optional parallelization)."""
        total_pages = len(self.sitemap)
        self.logger.info(f"Starting analysis of {total_pages} pages...")
        
        # Create progress bar
        self.progress_bar = tqdm(
            total=total_pages,
            desc="Analyzing pages",
            unit="page",
            bar_format='{desc}: {percentage:3.0f}%|{bar}| {n_fmt}/{total_fmt} [{elapsed}<{remaining}]'
        )
        
        try:
            if self.num_workers == 1:
                # Sequential processing
                for idx, page_url in enumerate(self.sitemap, 1):
                    self.logger.info(f"Progress: {idx}/{total_pages}")
                    self.analyze_page(page_url)
                    self.progress_bar.update(1)
                    # Reduced rate limiting
                    time.sleep(0.5)
            else:
                # Parallel processing
                self._analyze_pages_parallel()
        finally:
            if self.progress_bar:
                self.progress_bar.close()
        
        self.logger.info(f"Analysis complete. Report saved to: {self.report_filename}")
    
    def _analyze_pages_parallel(self):
        """Analyze pages in parallel using ThreadPoolExecutor."""
        total_pages = len(self.sitemap)
        completed = 0
        progress_lock = threading.Lock()
        
        def analyze_with_progress(page_url):
            """Wrapper to track progress."""
            nonlocal completed
            try:
                self.analyze_page(page_url)
            finally:
                with progress_lock:
                    completed += 1
                    if self.progress_bar:
                        self.progress_bar.update(1)
                    if completed % 10 == 0 or completed == total_pages:
                        self.logger.info(f"Progress: {completed}/{total_pages}")
        
        # Use ThreadPoolExecutor for parallel processing
        with ThreadPoolExecutor(max_workers=self.num_workers) as executor:
            # Submit all tasks
            futures = [executor.submit(analyze_with_progress, url) for url in self.sitemap]
            
            # Wait for completion and handle exceptions
            for future in as_completed(futures):
                try:
                    future.result()
                except Exception as e:
                    self.logger.error(f"Page analysis failed: {e}")
    
    def _git_commit_and_push_fixes(self):
        """Commit and push fix suggestions to git repository."""
        if not self.git_enabled:
            self.logger.info("Git push disabled (missing credentials)")
            return False
        
        try:
            # Check if git is available
            subprocess.run(['git', '--version'], check=True, capture_output=True)
            
            # Check if we're in a git repository
            result = subprocess.run(
                ['git', 'rev-parse', '--git-dir'],
                capture_output=True,
                text=True
            )
            if result.returncode != 0:
                self.logger.warning("Not in a git repository, skipping git operations")
                return False
            
            # Add the report files
            self.logger.info(f"Adding report files to git: {self.report_filename}, {self.log_filename}")
            subprocess.run(['git', 'add', self.report_filename, self.log_filename], check=True)
            
            # Create commit message
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            commit_message = f"docs(analyzer): Add analysis report - {timestamp}\n\nAutomated documentation analysis report.\nGenerated by analyzer.py"
            
            # Commit changes
            self.logger.info("Creating git commit...")
            subprocess.run(
                ['git', 'commit', '-m', commit_message],
                check=True,
                capture_output=True
            )
            
            # Setup remote URL with authentication if needed
            if self.github_url and self.github_token and self.github_username:
                # Parse GitHub URL and inject credentials
                parsed_url = urllib.parse.urlparse(self.github_url)
                if parsed_url.scheme in ('https', 'http'):
                    # Format: https://username:token@github.com/owner/repo.git
                    auth_url = f"{parsed_url.scheme}://{self.github_username}:{self.github_token}@{parsed_url.netloc}{parsed_url.path}"
                    
                    # Get current branch
                    result = subprocess.run(
                        ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                        capture_output=True,
                        text=True,
                        check=True
                    )
                    current_branch = result.stdout.strip()
                    
                    self.logger.info(f"Pushing to remote: {parsed_url.netloc}{parsed_url.path} (branch: {current_branch})")
                    
                    # Push to remote
                    subprocess.run(
                        ['git', 'push', auth_url, current_branch],
                        check=True,
                        capture_output=True
                    )
                    
                    self.logger.info("Successfully pushed changes to remote repository")
                    print(f"\n✅ Git push successful to {parsed_url.netloc}{parsed_url.path}")
                    return True
                else:
                    self.logger.warning(f"Unsupported URL scheme: {parsed_url.scheme}")
                    return False
            else:
                self.logger.warning("GitHub URL not provided, skipping push")
                return False
                
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Git operation failed: {e}")
            if e.stderr:
                self.logger.error(f"Git error output: {e.stderr.decode('utf-8', errors='ignore')}")
            return False
        except Exception as e:
            self.logger.error(f"Git commit/push failed: {e}")
            return False
    
    def _create_pull_request(self):
        """Create a pull request using gh CLI."""
        if not self.github_pr:
            return
        
        if not self.git_enabled:
            self.logger.warning("Cannot create PR without git credentials")
            print("\n⚠️  Cannot create PR: Git credentials not configured")
            return
        
        try:
            # Check if gh CLI is available
            subprocess.run(['gh', '--version'], check=True, capture_output=True)
            
            # Setup environment with GitHub token for gh CLI
            env = os.environ.copy()
            if self.github_token:
                env['GH_TOKEN'] = self.github_token
                self.logger.info("Using GITHUB_TOKEN for gh CLI authentication")
            
            # Check if gh is authenticated (with token in environment)
            auth_check = subprocess.run(['gh', 'auth', 'status'], capture_output=True, env=env)
            if auth_check.returncode != 0:
                self.logger.warning("gh CLI authentication failed")
                print("\n⚠️  gh CLI not authenticated. Run: gh auth login")
                print("   Or set GH_TOKEN environment variable with your GitHub token")
                return
            
            # Get current branch
            result = subprocess.run(
                ['git', 'rev-parse', '--abbrev-ref', 'HEAD'],
                capture_output=True,
                text=True,
                check=True
            )
            current_branch = result.stdout.strip()
            
            # Create PR title and body
            timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            pr_title = f"docs: Documentation analysis report - {timestamp}"
            pr_body = f"""# Documentation Analysis Report

**Generated:** {timestamp}
**Analyzer:** analyzer.py
**Report file:** {self.report_filename}
**Log file:** {self.log_filename}

## Summary

This PR contains the automated documentation analysis report identifying:
- Grammar and spelling errors
- Markdown rendering artifacts
- Broken links (orphan URLs)
- Broken images (orphan pictures)
- Unaligned images

Please review the attached CSV report for detailed findings and fix suggestions.
"""
            
            # Determine base branch for PR
            base_branch = self.github_branch if self.github_branch else 'master'
            
            # Validate that base branch exists in the target repository
            # Use gh CLI to check the remote repository directly
            if self.github_url:
                # Extract repository from github_url for validation
                parsed_url = urllib.parse.urlparse(self.github_url)
                if parsed_url.netloc:
                    path = parsed_url.path.strip('/')
                    if path.endswith('.git'):
                        path = path[:-4]
                    repo_for_check = path
                    
                    # Use gh CLI to check if branch exists in target repo
                    branch_check = subprocess.run(
                        ['gh', 'api', f'/repos/{repo_for_check}/branches/{base_branch}'],
                        capture_output=True,
                        text=True,
                        env=env
                    )
                    if branch_check.returncode != 0:
                        self.logger.error(f"Base branch '{base_branch}' does not exist in {repo_for_check}")
                        print(f"\n❌ Base branch '{base_branch}' does not exist in repository {repo_for_check}")
                        print(f"   Check available branches: gh api /repos/{repo_for_check}/branches")
                        print(f"   Or visit: https://github.com/{repo_for_check}/branches")
                        return
                    self.logger.info(f"Validated branch '{base_branch}' exists in {repo_for_check}")
            else:
                # Fallback to local git check if no github_url provided
                branch_check = subprocess.run(
                    ['git', 'rev-parse', '--verify', f'origin/{base_branch}'],
                    capture_output=True,
                    text=True
                )
                if branch_check.returncode != 0:
                    self.logger.error(f"Base branch 'origin/{base_branch}' does not exist")
                    print(f"\n❌ Base branch '{base_branch}' does not exist in remote repository")
                    print(f"   Available branches: run 'git branch -r' to see remote branches")
                    print(f"   Specify correct branch with --github-branch parameter")
                    return
            
            # Check if there are commits to create PR from
            # Note: When using different repository (github_url != origin), we always proceed
            # because we can't easily check commit differences across repos
            if self.github_url:
                # Cross-repo scenario: skip commit count check, let gh handle it
                self.logger.info(f"Cross-repository PR - skipping commit count validation")
                commit_count = 1  # Assume we have commits
            else:
                # Same repo scenario: check commit count locally
                commits_check = subprocess.run(
                    ['git', 'rev-list', '--count', f'origin/{base_branch}..{current_branch}'],
                    capture_output=True,
                    text=True
                )
                commit_count = int(commits_check.stdout.strip()) if commits_check.returncode == 0 else 0
                
                if commit_count == 0:
                    self.logger.warning(f"No new commits between {base_branch} and {current_branch}")
                    print(f"\n⚠️  No new commits to create PR")
                    print(f"   Current branch: {current_branch}")
                    print(f"   Base branch: {base_branch}")
                    print(f"   The report was pushed but no PR was created (branch already in sync)")
                    return
            
            self.logger.info(f"Creating pull request: {current_branch} -> {base_branch} ({commit_count} commits)")
            
            # Extract repository from github_url if provided
            repo_arg = []
            if self.github_url:
                # Parse github_url to extract owner/repo
                # Expected formats:
                # - https://github.com/owner/repo.git
                # - https://github.com/owner/repo
                # - git@github.com:owner/repo.git
                parsed_url = urllib.parse.urlparse(self.github_url)
                
                if parsed_url.netloc:  # https://github.com/owner/repo.git
                    path = parsed_url.path.strip('/')
                    if path.endswith('.git'):
                        path = path[:-4]
                    repo_spec = path
                else:  # git@github.com:owner/repo.git
                    if '@' in self.github_url and ':' in self.github_url:
                        # Extract from git@github.com:owner/repo.git
                        path = self.github_url.split(':')[1]
                        if path.endswith('.git'):
                            path = path[:-4]
                        repo_spec = path
                    else:
                        repo_spec = None
                
                if repo_spec:
                    repo_arg = ['--repo', repo_spec]
                    self.logger.info(f"Creating PR in repository: {repo_spec}")
            
            # Build gh pr create command
            pr_command = [
                'gh', 'pr', 'create',
                '--title', pr_title,
                '--body', pr_body,
                '--head', current_branch,
                '--base', base_branch
            ] + repo_arg
            
            # Create PR using gh CLI (with token in environment)
            result = subprocess.run(
                pr_command,
                capture_output=True,
                text=True,
                check=True,
                env=env
            )
            
            pr_url = result.stdout.strip()
            self.logger.info(f"Pull request created: {pr_url}")
            print(f"\n✅ Pull request created: {pr_url}")
            
        except subprocess.CalledProcessError as e:
            self.logger.error(f"Failed to create pull request: {e}")
            if e.stderr:
                error_msg = e.stderr.decode('utf-8', errors='ignore') if isinstance(e.stderr, bytes) else e.stderr
                self.logger.error(f"gh CLI error: {error_msg}")
                print(f"\n❌ Failed to create PR: {error_msg}")
        except FileNotFoundError:
            self.logger.error("gh CLI not found. Install from: https://cli.github.com/")
            print("\n❌ gh CLI not found. Install from: https://cli.github.com/")
        except Exception as e:
            self.logger.error(f"PR creation failed: {e}")
            print(f"\n❌ PR creation failed: {e}")
    
    def finalize_report(self):
        """Finalize the report, add summary if no issues found."""
        try:
            # Check if any issues were found (file has more than just header)
            with open(self.report_filename, 'r', encoding='utf-8') as f:
                lines = f.readlines()
                if len(lines) <= 1:  # Only header
                    self._write_csv_row(
                        self.effective_url,
                        'info',
                        'No issues found',
                        'Documentation appears to be in good condition'
                    )
            
            # Commit and push changes if git is enabled
            if self.git_enabled:
                self.logger.info("Git operations enabled, committing and pushing changes...")
                if self._git_commit_and_push_fixes():
                    # Create PR if requested
                    if self.github_pr:
                        self._create_pull_request()
                    
        except Exception as e:
            self.logger.error(f"Failed to finalize report: {e}")
    
    def cleanup(self):
        """Cleanup resources."""
        if self.grammar_tool:
            try:
                self.logger.info("Closing grammar checker...")
                self.grammar_tool.close()
            except Exception as e:
                self.logger.warning(f"Error closing grammar tool: {e}")
        try:
            self.session.close()
        except:
            pass
    
    def run(self):
        """Main execution flow."""
        try:
            # Print initial info to console
            print(f"Documentation Analyzer")
            print(f"Log file: {self.log_filename}")
            print(f"Report file: {self.report_filename}")
            print(f"URL: {self.base_url}")
            print(f"Workers: {self.num_workers}")
            print()
            
            # Validate connectivity
            if not self.validate_connectivity():
                self.logger.error("Cannot proceed without valid connection to server")
                print(f"\n❌ ERROR: Cannot connect to {self.base_url}")
                print(f"   Check the log file for details: {self.log_filename}")
                sys.exit(1)
            
            # Generate sitemap
            print("Discovering pages...")
            self.generate_sitemap()
            
            if not self.sitemap:
                self.logger.error("No pages found to analyze")
                print(f"\n❌ ERROR: No pages found")
                print(f"   Check the log file for details: {self.log_filename}")
                sys.exit(1)
            
            print(f"Found {len(self.sitemap)} pages to analyze\n")
            
            # Analyze all pages
            self.analyze_all_pages()
            
            # Finalize report
            self.finalize_report()
            
            # Print completion info to console
            print(f"\n✅ Analysis complete!")
            print(f"   Report: {self.report_filename}")
            print(f"   Log: {self.log_filename}")
            print(f"   Pages analyzed: {len(self.sitemap)}")
            
        except KeyboardInterrupt:
            self.logger.warning("\nAnalysis interrupted by user")
            print(f"\n\n⚠️  Analysis interrupted by user")
            print(f"   Partial results saved to: {self.report_filename}")
            print(f"   Log file: {self.log_filename}")
            sys.exit(1)
        except Exception as e:
            self.logger.error(f"Analysis failed: {e}")
            print(f"\n❌ ERROR: Analysis failed")
            print(f"   Check the log file for details: {self.log_filename}")
            sys.exit(1)
        finally:
            self.cleanup()


def validate_url(url: str) -> str:
    """Validate URL format and scheme."""
    parsed = urllib.parse.urlparse(url)
    
    if not parsed.scheme:
        # Default to HTTPS if no scheme provided
        url = f"https://{url}"
        parsed = urllib.parse.urlparse(url)
    
    if parsed.scheme not in ('http', 'https'):
        raise argparse.ArgumentTypeError(
            f"Invalid URL scheme '{parsed.scheme}'. Must be http or https."
        )
    
    return url


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description='Analyze documentation for issues (grammar, markdown, broken links, images)',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Basic analysis
  python analyzer.py --url https://127.0.0.1
  python analyzer.py --url https://127.0.0.1 --parallel 5
  python analyzer.py --url https://example.com/docs --parallel 10
  
  # With git push (using environment variables)
  export GITHUB_URL=https://github.com/owner/repo.git
  export GITHUB_TOKEN=ghp_xxxxxxxxxxxx
  export GITHUB_USERNAME=myusername
  export GITHUB_BRANCH=master
  python analyzer.py --url https://127.0.0.1
  
  # With git push (using command-line arguments)
  python analyzer.py --url https://127.0.0.1 \\
    --github-url https://github.com/owner/repo.git \\
    --github-token ghp_xxxxxxxxxxxx \\
    --github-username myusername \\
    --github-branch master
  
  # With git push and PR creation to specific branch
  python analyzer.py --url https://127.0.0.1 \\
    --github-branch main --github-pr

Requirements:
  - Python 3.8+
  - Libraries: requests, beautifulsoup4, lxml, language-tool-python, Pillow
  - Install with: ./setup-analyzer.sh
  - For git push: git CLI
  - For PR creation: gh CLI (https://cli.github.com/)
        """
    )
    
    parser.add_argument(
        '--url',
        required=True,
        type=validate_url,
        help='Base URL of the documentation webserver (e.g., https://127.0.0.1)'
    )
    
    parser.add_argument(
        '--parallel',
        type=int,
        default=1,
        metavar='N',
        help='Number of parallel workers (1-20, default: 1 for sequential)'
    )
    
    parser.add_argument(
        '--github-url',
        type=str,
        default=None,
        help='GitHub repository URL (e.g., https://github.com/owner/repo.git). Defaults to GITHUB_URL env var'
    )
    
    parser.add_argument(
        '--github-token',
        type=str,
        default=None,
        help='GitHub personal access token. Defaults to GITHUB_TOKEN env var'
    )
    
    parser.add_argument(
        '--github-username',
        type=str,
        default=None,
        help='GitHub username. Defaults to GITHUB_USERNAME env var'
    )
    
    parser.add_argument(
        '--github-branch',
        type=str,
        default=None,
        help='GitHub base branch for pull request (e.g., master, main). Defaults to GITHUB_BRANCH env var or "master"'
    )
    
    parser.add_argument(
        '--github-pr',
        action='store_true',
        help='Create a pull request using gh CLI after pushing changes'
    )
    
    args = parser.parse_args()
    
    # Validate parallel workers
    if args.parallel < 1 or args.parallel > 20:
        parser.error("--parallel must be between 1 and 20")
    
    # Get GitHub credentials from environment variables if not provided
    github_url = args.github_url or os.getenv('GITHUB_URL')
    github_token = args.github_token or os.getenv('GITHUB_TOKEN')
    github_username = args.github_username or os.getenv('GITHUB_USERNAME')
    github_branch = args.github_branch or os.getenv('GITHUB_BRANCH')
    
    # Log git configuration status
    git_configured = bool(github_url and github_token and github_username)
    if git_configured:
        print(f"Git push enabled: {github_url}")
        if github_branch:
            print(f"Base branch: {github_branch}")
        if args.github_pr:
            print("PR creation enabled")
    else:
        print("Git push disabled (credentials not configured)")
    
    # Create and run analyzer
    analyzer = DocumentationAnalyzer(
        base_url=args.url,
        num_workers=args.parallel,
        github_url=github_url,
        github_token=github_token,
        github_username=github_username,
        github_branch=github_branch,
        github_pr=args.github_pr
    )
    
    analyzer.run()


if __name__ == '__main__':
    main()
