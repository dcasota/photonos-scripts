#!/bin/bash

# Installer script for Docs Web Server Content Inspector Daemon on Photon OS
# Uses tdnf for package management
# Sets up Crawl4AI MCP via Docker and local Filesystem MCP from modelcontextprotocol/servers

set -e  # Exit on error

# Define variables
INSTALL_DIR="/opt/docs-inspector"
MCP_CRAWL_PORT=11235
MCP_FS_PORT=8001
INSPECTOR_USER="inspector"
LOG_DIR="/var/log/inspector"
CONFIG_FILE="$INSTALL_DIR/config.yaml"
VENV_DIR="$INSTALL_DIR/venv"
OUTPUT_LOG="/var/log/fs-mcp.log"
DOCS_ROOT="/var/www/photon-site/public"

# Dynamically retrieve DHCP IP address
tdnf install -y iproute2
IP_ADDRESS=$(ip addr show | grep -oP 'inet \K[\d.]+(?=/)' | grep -v '127.0.0.1' | head -n 1)
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS=$(hostname -I | awk '{print $1}' | grep -v '127.0.0.1')
fi
if [ -z "$IP_ADDRESS" ]; then
  IP_ADDRESS="localhost"
  echo "Warning: Could not detect DHCP IP. Using 'localhost' for certificate. Set IP manually if needed."
else
  echo "Detected IP address: $IP_ADDRESS"
  echo "Testing access to https://$IP_ADDRESS/"
  if curl -s -I -k https://$IP_ADDRESS/ > /dev/null; then
    echo "Access to IP OK."
  else
    IP_ADDRESS="localhost"
    echo "Access to IP failed, using localhost instead."
  fi
fi

# Function to check prerequisites
check_prereqs() {
    echo "Checking prerequisites..."
    if ! command -v python3 &> /dev/null; then
        echo "Python3 not found. Will install."
    fi
    if ! command -v go &> /dev/null; then
        echo "Go not found. Will install."
    fi
    if ! command -v node &> /dev/null; then
        echo "Node.js not found. Will install."
    fi
    if ! command -v docker &> /dev/null; then
        echo "Docker not found. Will install."
    fi
    if ! command -v git &> /dev/null; then
        echo "Git not found. Will install."
    fi
    if ! command -v curl &> /dev/null; then
        echo "Curl not found. Will install."
    fi
    curl -s -I -k https://$IP_ADDRESS/ > /dev/null || echo "Warning: Docs server inaccessible via HTTPS."
    [ -d /var/www/photon-site/public ] || echo "Warning: Local FS directory not found; relying on web crawl."
}

# Function to install dependencies using tdnf
install_deps() {
    echo "Updating package cache..."
    tdnf makecache || true  # In case metadata needs refresh
    echo "Installing system packages..."
    tdnf install -y python3 python3-pip go nodejs docker git curl psmisc openjdk21
    tdnf install -y iptables  # For potential network needs
    # Configure Docker to disable IPv6
    mkdir -p /etc/docker
    cat <<EOF > /etc/docker/daemon.json
{
  "ipv6": false
}
EOF
    systemctl enable --now docker
    systemctl restart docker
    usermod -aG docker $USER || true  # Add current user to docker group
    echo "Installing markdownlint-cli via npm..."
    npm install -g markdownlint-cli
}

# Function to create inspector user
setup_user() {
    echo "Setting up inspector user..."
    id -u $INSPECTOR_USER > /dev/null 2>&1 || useradd -m $INSPECTOR_USER
}

# Function to setup Python virtual environment and libraries
setup_python_env() {
    echo "Setting up Python virtual environment..."
    mkdir -p $INSTALL_DIR
    chown $INSPECTOR_USER $INSTALL_DIR
    sudo -u $INSPECTOR_USER python3 -m venv $VENV_DIR
    sudo -u $INSPECTOR_USER $VENV_DIR/bin/pip install --upgrade pip
    sudo -u $INSPECTOR_USER $VENV_DIR/bin/pip install requests beautifulsoup4 lxml pandas pyyaml language-tool-python pyspellchecker markdown
}

# Function to setup Crawl4AI MCP using Docker
setup_crawl4ai() {
    echo "Setting up Crawl4AI MCP..."
    docker pull unclecode/crawl4ai:latest
    docker stop crawl4ai-mcp || true
    docker rm crawl4ai-mcp || true
    fuser -k $MCP_CRAWL_PORT/tcp || true
    echo "Waiting for port $MCP_CRAWL_PORT to be free..."
    while ss -tuln | grep -q ":$MCP_CRAWL_PORT "; do
        sleep 1
    done
    docker run -d --network host -p $MCP_CRAWL_PORT:11235 --name crawl4ai-mcp --shm-size=2g --ipc=host unclecode/crawl4ai:latest
    sleep 10  # Wait for startup
    curl -s http://localhost:$MCP_CRAWL_PORT/health || { echo "Crawl4AI setup failed."; exit 1; }
    echo "Crawl4AI MCP running on port $MCP_CRAWL_PORT"
}

# Function to setup local Filesystem MCP
setup_fs_mcp() {
    echo "Setting up local Filesystem MCP..."
    # Install supergateway
    npm install -g supergateway
    # Install and start @modelcontextprotocol/server-filesystem
    npm install @modelcontextprotocol/server-filesystem >> $OUTPUT_LOG 2>&1
    if [ $? -ne 0 ]; then
        echo "Error: npm install @modelcontextprotocol/server-filesystem failed. See $OUTPUT_LOG for details"
        cat $OUTPUT_LOG
        exit 1
    fi
    echo "Starting MCP filesystem server..."
    pkill -f "supergateway" || true
    pkill -f "@modelcontextprotocol/server-filesystem" || true
    fuser -k $MCP_FS_PORT/tcp || true
    echo "Waiting for port $MCP_FS_PORT to be free..."
    while ss -tuln | grep -q ":$MCP_FS_PORT "; do
        sleep 1
    done
    nohup supergateway --stdio "npx -y @modelcontextprotocol/server-filesystem /var/www/photon-site/public" --port $MCP_FS_PORT >> "$OUTPUT_LOG" 2>&1 < /dev/null &
    sleep 10
    if grep -q "Secure MCP Filesystem Server running on stdio" "$OUTPUT_LOG" && grep -q "Listening on port $MCP_FS_PORT" "$OUTPUT_LOG"; then
        echo "MCP server started successfully. Check $OUTPUT_LOG for details."
    else
        echo "Failed to start MCP server. Check $OUTPUT_LOG."
        cat $OUTPUT_LOG
        exit 1
    fi
}

# Function to install inspector code
install_inspector() {
    echo "Installing inspector code..."
    # Embed or generate main.py (simplified example; in production, git clone or copy from source)
    cat <<EOL_MAIN > $INSTALL_DIR/main.py
import requests
import yaml
import json
import difflib
from bs4 import BeautifulSoup
import datetime
import time
import sys
import subprocess
import os
import logging
import signal
import atexit
from urllib.parse import urljoin, urlparse, urlunparse
from collections import deque
import language_tool_python
from spellchecker import SpellChecker
from markdown import markdown
import threading
import concurrent.futures
import tempfile
import queue
import hashlib
# Add other imports as needed
# Note: markdownlint-cli is installed via npm; use subprocess to call it for linting

logging.info("Loading config from /opt/docs-inspector/config.yaml")
try:
    config = yaml.safe_load(open('/opt/docs-inspector/config.yaml'))
    logging.info(f"Loaded config: {config}")
except Exception as e:
    logging.error(f"Failed to load config: {str(e)}")
    config = {'base_url': 'https://localhost/', 'versions': [], 'mcp_crawl_port': 11235, 'mcp_fs_port': 8001, 'log_level': 'DEBUG'}

# Setup logging to file
LOG_DIR = '/var/log/inspector'
DOCS_ROOT = '/var/www/photon-site/public'
root = logging.getLogger()
for h in root.handlers[:]:
    root.removeHandler(h)
log_level = config.get('log_level', 'DEBUG').upper()
level = logging.getLevelName(log_level)
logging.basicConfig(filename=os.path.join(LOG_DIR, 'inspector.log'), level=level, format='%(asctime)s,%(msecs)03d - %(levelname)s - %(message)s')
logging.info("Starting inspector daemon...")

# Initialize language tools
try:
    tool = language_tool_python.LanguageTool('en-US')
    tool.disable_rule('MORFOLOGIK_RULE_EN_US')
except Exception as e:
    logging.error(f"Failed to initialize LanguageTool: {str(e)}")
    tool = None
try:
    spell = SpellChecker()
    exclusion_list = ['alternativename', 'alternativenamespolicy', 'api', 'auditd', 'aws', 'bc', 'bootable', 'btrfs', 'cgroup', 'cli', 'cntrctl', 'config', 'cpus', 'createrepo', 'dcerpc', 'dev', 'dhcp', 'dns', 'fcgi', 'filesystem', 'filesystems', 'fips', 'flavours', 'fsck', 'gcc', 'gce', 'genisoimage', 'github', 'glibc', 'gso', 'hostname', 'initrd', 'ip', 'iso', 'journalctl', 'json', 'kubernetes', 'lightwave', 'macaddress', 'macaddresspolicy', 'metadata', 'metalink', 'namepolicy', 'ndsend', 'netmgr', 'netplan', 'nfs', 'nftables', 'nics', 'nmctl', 'openjdk', 'openssl', 'oss', 'pmd', 'postgresql', 'pxe', 'rebase', 'repoquery', 'repos', 'rpm', 'rpms', 'runtime', 'selinux', 'sendmail', 'sizepercent', 'sriov', 'sshfs', 'ssl', 'systemd', 'tdnf', 'texinfo', 'tls', 'tndf', 'toolchain', 'uefi', 'ulogd', 'umask', 'urls', 'veth', 'vhd', 'vlan', 'vmware', 'vprobes', 'vsphere', 'vti', 'wireguard', 'wlan', 'xfs', 'yaml', 'zstd']
    for word in exclusion_list:
        spell.add(word)
except Exception as e:
    logging.error(f"Failed to initialize SpellChecker: {str(e)}")
    spell = None

shutdown_event = threading.Event()

# Function to log shutdown
def shutdown_handler(signum, frame):
    logging.debug("Inspector daemon stopping...")
    shutdown_event.set()

signal.signal(signal.SIGTERM, shutdown_handler)
signal.signal(signal.SIGINT, shutdown_handler)

atexit.register(lambda: logging.debug("Inspector daemon exiting..."))

def crawl_page(url):
    logging.debug(f"Crawling page: {url}")
    try:
        logging.debug(f"Sending crawl request for {url}")
        crawl_config = {
            "page_timeout": 300000,
            "browser_config": {
                "extra_args": ["--ignore-certificate-errors", "--disable-dev-shm-usage"]
            }
        }
        resp = requests.post(f"http://localhost:{config['mcp_crawl_port']}/crawl",
                             json={"urls": [url], "instructions": "Extract markdown content, all links, and html", "config": crawl_config}, timeout=600)
        logging.debug(f"Received response for {url}")
        if resp.status_code == 200:
            data = resp.json()
            if data.get('success') and 'results' in data and data['results']:
                logging.debug(f"Successfully crawled {url}")
                return data['results'][0]
            else:
                logging.error(f"Crawl failed for {url}: {data}")
                return {'success': False}
        else:
            logging.error(f"Error crawling {url}: {resp.status_code}")
            return {'success': False}
    except Exception as e:
        logging.error(f"Exception while crawling {url}: {str(e)}")
        return {'success': False}

def crawl_and_analyze(start_url, version_dir, timestamp, version):
    url_queue = queue.Queue()
    visited = set()
    visited_lock = threading.Lock()
    analyzed_local = set()
    local_lock = threading.Lock()
    with visited_lock:
        parsed_start = urlparse(start_url)
        normalized_start = urlunparse(parsed_start._replace(fragment=''))
        if normalized_start not in visited:
            visited.add(normalized_start)
            url_queue.put(normalized_start)
    num_workers = 2

    def crawl_worker():
        while not shutdown_event.is_set():
            try:
                url = url_queue.get(timeout=1)
                if url is None:
                    break
                data = crawl_page(url)
                # Analyze even if crawl failed
                _, page_analyzed_local, is_analyzed_crawled = analyze_page(url, data, start_url, version_dir, timestamp, version)
                with local_lock:
                    analyzed_local.update(page_analyzed_local)
                new_links = []
                if data.get('success', True):
                    try:
                        soup = BeautifulSoup(data.get('html', ''), 'lxml')
                        excluded_link_texts = ["Edit this page", "Create child page", "Create docs issue", "Create project issue", "Print entire section"]
                        for a in soup.find_all('a', href=True):
                            link_text = a.get_text().strip()
                            if link_text in excluded_link_texts:
                                continue
                            link = urljoin(url, a['href'])
                            parsed_link = urlparse(link)
                            normalized_link = urlunparse(parsed_link._replace(fragment=''))
                            if urlparse(normalized_link).netloc == urlparse(start_url).netloc and normalized_link.startswith(start_url):
                                with visited_lock:
                                    if normalized_link not in visited:
                                        visited.add(normalized_link)
                                        new_links.append(normalized_link)
                    except Exception as e:
                        logging.error(f"Failed to parse HTML for {url}: {str(e)}")
                for link in new_links:
                    url_queue.put(link)
                url_queue.task_done()
            except queue.Empty:
                continue

    with concurrent.futures.ThreadPoolExecutor(max_workers=num_workers) as executor:
        workers = [executor.submit(crawl_worker) for _ in range(num_workers)]
        url_queue.join()
        for _ in range(num_workers):
            url_queue.put(None)
        concurrent.futures.wait(workers)

    return list(visited), analyzed_local

# Function to list all files in a directory and subdirectories
def list_files(dir_path):
    files = []
    try:
        for root, dirs, filenames in os.walk(dir_path):
            for filename in filenames:
                files.append(os.path.join(root, filename))
    except Exception as e:
        logging.error(f"Failed to list files in {dir_path}: {str(e)}")
    return files

# Define the check link function
def check_link(full_link):
    retries = 3
    for attempt in range(retries):
        try:
            resp = requests.get(full_link, allow_redirects=True, timeout=30, verify=False)
            if resp.status_code == 429:
                time.sleep(5 * (attempt + 1))
                continue
            if resp.status_code >= 400:
                return {"issue": f"Broken link: {full_link} (status {resp.status_code})", "fix": "Replace or remove", "diff": ""}
            return None
        except Exception as e:
            logging.error(f"Exception in link check for {full_link}: {str(e)}")
            if attempt < retries - 1:
                time.sleep(5 * (attempt + 1))
                continue
            return {"issue": f"Broken link check failed: {full_link} ({str(e)})", "fix": "Investigate", "diff": ""}
    return {"issue": f"Broken link: {full_link} (status 429 after retries)", "fix": "Replace or remove", "diff": ""}

def write_changes(path, issues, timestamp):
    if not issues:
        return
    data = {"path": path, "issues": issues}
    hash_val = hashlib.sha256(path.encode()).hexdigest()[:10]
    page_file = os.path.join(LOG_DIR, f'changes_{hash_val}_{timestamp}.json')
    logging.info(f"Writing {len(issues)} issues for {path} to {page_file}")
    with open(page_file, 'w') as f:
        json.dump(data, f, indent=2)

# Define the analysis function for parallel execution
def analyze_page(url, data, start_url, version_dir, timestamp, version):
    page_changes = []
    page_analyzed_local = []
    is_analyzed_crawled = False
    try:
        logging.info(f"Analyzing web page: {url}")
        if data.get('success') == False:
            logging.warning(f"Crawl failed for {url}")
            page_changes.append({"issue": "Crawl failed", "fix": "Check server", "diff": ""})
            write_changes(url, page_changes, timestamp)
            return page_changes, page_analyzed_local, is_analyzed_crawled
        
        is_analyzed_crawled = True
        
        content = data.get('markdown', '')
        if not isinstance(content, str):
            content = ''
        # Check for broken links (orphaned web links) in parallel
        try:
            logging.debug(f"Checking for broken links in {url}")
            soup = BeautifulSoup(data.get('html', ''), 'lxml')
            links_to_check = []
            excluded_link_texts = ["Edit this page", "Create child page", "Create docs issue", "Create project issue", "Print entire section"]
            for a in soup.find_all('a', href=True):
                link_text = a.get_text().strip()
                if link_text in excluded_link_texts:
                    continue
                link = a['href']
                full_link = urljoin(url, link)
                parsed = urlparse(full_link)
                if parsed.scheme in ('http', 'https'):
                    links_to_check.append(full_link)
            # Check for duplicated version in internal links
            for full_link in links_to_check:
                parsed = urlparse(full_link)
                if parsed.netloc == urlparse(start_url).netloc and full_link.startswith(start_url):
                    path = parsed.path
                    version_str = f'docs-{version}'
                    if path.startswith(f'/{version_str}/') and path.count(f'/{version_str}/') > 1:
                        page_changes.append({"issue": f"Duplicated version in path: {full_link}", "fix": "Remove duplicate version segment", "diff": ""})
            if links_to_check:
                with concurrent.futures.ThreadPoolExecutor(max_workers=5) as link_executor:
                    link_futures = [link_executor.submit(check_link, fl) for fl in links_to_check]
                    for future in concurrent.futures.as_completed(link_futures):
                        result = future.result()
                        if result:
                            page_changes.append(result)
        except Exception as e:
            logging.error(f"Failed to process links for {url}: {str(e)}")
        
        # Extract plain text for grammar and spelling
        try:
            text = soup.get_text(separator='\n', strip=True)
        except Exception as e:
            logging.error(f"Failed to extract text for {url}: {str(e)}")
            write_changes(url, page_changes, timestamp)
            return page_changes, page_analyzed_local, is_analyzed_crawled
        
        # Grammar check
        if tool:
            try:
                logging.debug(f"Checking grammar in {url}")
                matches = tool.check(text)
                if matches:
                    issues = [f"{m.ruleId}: {m.message}" for m in matches]
                    page_changes.append({"issue": "Grammar issues", "fix": '\n'.join(issues), "diff": ""})
            except Exception as e:
                logging.error(f"Grammar check failed for {url}: {str(e)}")
        
        # Spelling check
        if spell:
            try:
                logging.debug(f"Checking spelling in {url}")
                misspelled = list(spell.unknown([word for word in text.split() if word.isalpha()]))
                if misspelled:
                    page_changes.append({"issue": "Spelling issues", "fix": ', '.join(misspelled), "diff": ""})
            except Exception as e:
                logging.error(f"Spelling check failed for {url}: {str(e)}")
        
        # Markdown glitches using markdownlint-cli
        if content and isinstance(content, str):
            temp_file = None
            try:
                logging.debug(f"Checking markdown in {url}")
                with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.md') as tmp:
                    temp_file = tmp.name
                    tmp.write(content)
                lint_result = subprocess.run(['markdownlint', temp_file], capture_output=True, text=True)
                if lint_result.returncode != 0:
                    page_changes.append({"issue": "Markdown issues", "fix": lint_result.stdout, "diff": ""})
                os.remove(temp_file)
            except Exception as e:
                logging.error(f"Markdown linting failed for {url}: {str(e)}")
                if temp_file and os.path.exists(temp_file):
                    os.remove(temp_file)
        
        # Comparison with local source
        relative = url.replace(start_url, '')
        if relative == '':
            write_changes(url, page_changes, timestamp)
            return page_changes, page_analyzed_local, is_analyzed_crawled  # Skip index page
        if not relative.endswith('.html'):
            write_changes(url, page_changes, timestamp)
            return page_changes, page_analyzed_local, is_analyzed_crawled
        md_file = relative[:-5] + '.md'
        local_path = os.path.join(version_dir, md_file)
        try:
            if os.path.exists(local_path):
                logging.debug(f"Comparing with local file: {local_path}")
                with open(local_path, 'r') as f:
                    local_content = f.read()
                if not isinstance(content, str):
                    content = ''
                if local_content.strip() != content.strip():
                    diff = '\n'.join(difflib.unified_diff(local_content.splitlines(), content.splitlines(), fromfile=local_path, tofile=url))
                    page_changes.append({"issue": "Content mismatch", "fix": "Review diff", "diff": diff})
                page_analyzed_local.append(local_path)
            else:
                page_changes.append({"issue": "Missing local source", "fix": "Add MD file", "diff": ""})
        except Exception as e:
            logging.error(f"Failed to compare with local file {local_path}: {str(e)}")
        
        # Add more checks: structure, sections, syntax similarly
        if page_changes:
            write_changes(url, page_changes, timestamp)
    except Exception as e:
        logging.error(f"Failed to analyze page {url}: {str(e)}")
    
    return page_changes, page_analyzed_local, is_analyzed_crawled

def analyze_local(local_path, timestamp):
    changes = []
    try:
        logging.info(f"Analyzing local file not on web: {local_path}")
        with open(local_path, 'r') as f:
            local_content = f.read()
        
        # Markdown glitches using markdownlint-cli
        temp_file = None
        try:
            logging.debug(f"Checking markdown in {local_path}")
            with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.md') as tmp:
                temp_file = tmp.name
                tmp.write(local_content)
            lint_result = subprocess.run(['markdownlint', temp_file], capture_output=True, text=True)
            if lint_result.returncode != 0:
                changes.append({"issue": "Markdown issues (local)", "fix": lint_result.stdout, "diff": ""})
            os.remove(temp_file)
        except Exception as e:
            logging.error(f"Markdown linting failed for {local_path}: {str(e)}")
            if temp_file and os.path.exists(temp_file):
                os.remove(temp_file)
        
        # Convert to HTML and extract text for grammar and spelling
        try:
            html = markdown(local_content)
            soup = BeautifulSoup(html, 'lxml')
            text = soup.get_text(separator='\n', strip=True)
        except Exception as e:
            logging.error(f"Failed to convert markdown for {local_path}: {str(e)}")
            if changes:
                write_changes(local_path, changes, timestamp)
            return changes
        
        # Grammar check
        if tool:
            try:
                logging.debug(f"Checking grammar in {local_path}")
                matches = tool.check(text)
                if matches:
                    issues = [f"{m.ruleId}: {m.message}" for m in matches]
                    changes.append({"issue": "Grammar issues (local)", "fix": '\n'.join(issues), "diff": ""})
            except Exception as e:
                logging.error(f"Grammar check failed for {local_path}: {str(e)}")
        
        # Spelling check
        if spell:
            try:
                logging.debug(f"Checking spelling in {local_path}")
                misspelled = list(spell.unknown([word for word in text.split() if word.isalpha()]))
                if misspelled:
                    changes.append({"issue": "Spelling issues (local)", "fix": ', '.join(misspelled), "diff": ""})
            except Exception as e:
                logging.error(f"Spelling check failed for {local_path}: {str(e)}")
        
        # Missing on web
        changes.append({"issue": "Missing on web", "fix": "Upload to server", "diff": ""})
        if changes:
            write_changes(local_path, changes, timestamp)
    except Exception as e:
        logging.error(f"Failed to process local file {local_path}: {str(e)}")
    return changes

# Verification functions (implement basic checks)
def verify_content(version, timestamp):
    timestamp_version = datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')
    start_dict = [{"issue": "Verification started", "fix": f"Initial verification cycle for version {version} at {timestamp_version}", "diff": ""}]
    try:
        write_changes(f"docs-{version}", start_dict, timestamp)
    except Exception as e:
        logging.error(f"Failed to write started for {version}: {str(e)}")

    start_url = f"{config['base_url']}docs-{version}/"
    version_dir = os.path.join(DOCS_ROOT, f'docs-{version}')
    logging.debug(f"Starting crawl for docs version: {version} at {start_url}")
    
    try:
        crawled_urls, analyzed_local = crawl_and_analyze(start_url, version_dir, timestamp, version)
        logging.debug(f"Crawled URLs for docs-{version}: {', '.join(crawled_urls)}")
        logging.debug(f"Crawled {len(crawled_urls)} pages for docs-{version}")
    except Exception as e:
        logging.error(f"Failed to crawl for {version}: {str(e)}")
        error_dict = [{"issue": "Crawl failed", "fix": str(e), "diff": ""}]
        try:
            write_changes(f"docs-{version}", error_dict, timestamp)
        except Exception as ee:
            logging.error(f"Failed to write crawl failed for {version}: {str(ee)}")
        return
    
    # List files from local filesystem
    logging.debug(f"Checking directory: {version_dir}")
    if os.path.exists(version_dir):
        files = list_files(version_dir)
        logging.debug(f"Files in docs-{version} subdirectories: {', '.join(files)}")
    else:
        logging.warning(f"Directory {version_dir} does not exist.")
        files = []
    
    # Check for local .md files not on web
    local_mds = [f for f in files if f.endswith('.md')]
    not_analyzed_local = [path for path in local_mds if path not in analyzed_local]
    if not_analyzed_local:
        with concurrent.futures.ThreadPoolExecutor(max_workers=10) as executor:
            local_futures = [executor.submit(analyze_local, path, timestamp) for path in not_analyzed_local]
            for future in concurrent.futures.as_completed(local_futures):
                try:
                    local_changes = future.result()
                except Exception as e:
                    logging.error(f"Exception in analyzing local file: {str(e)}")
    
    logging.debug(f"Analyzed local files for docs-{version}: {', '.join(analyzed_local)}")

if len(sys.argv) > 1 and sys.argv[1] == '--run':
    while not shutdown_event.is_set():
        logging.info("Running verification cycle...")
        timestamp = datetime.datetime.now().strftime('%Y%m%d_%H%M%S')
        try:
            versions = config['versions']
        except KeyError:
            logging.error("Versions not found in config")
            versions = []
            error_dict = [{"issue": "Config error", "fix": "Versions not found in config", "diff": ""}]
            try:
                write_changes("global", error_dict, timestamp)
            except Exception as e:
                logging.error(f"Failed to write config error: {str(e)}")
        logging.info(f"Processing {len(versions)} versions")
        with concurrent.futures.ThreadPoolExecutor(max_workers=5) as executor:
            version_futures = {executor.submit(verify_content, version, timestamp): version for version in versions}
            for future in concurrent.futures.as_completed(version_futures):
                version = version_futures[future]
                try:
                    future.result()
                except Exception as e:
                    logging.error(f"Failed to process version {version}: {str(e)}")
                    error_dict = [{"issue": "Verification failed", "fix": f"Exception: {str(e)}", "diff": ""}]
                    try:
                        write_changes(f"docs-{version}", error_dict, timestamp)
                    except Exception as ee:
                        logging.error(f"Failed to write error for {version}: {str(ee)}")
        logging.info("Verification cycle complete. Sleeping for 1 hour.")
        shutdown_event.wait(3600)  # Wait for 1 hour or until shutdown signal
    # Cleanup
    if tool is not None:
        try:
            tool.close()
        except Exception as e:
            logging.error(f"Failed to close LanguageTool: {str(e)}")
    sys.exit(0)
EOL_MAIN
    # Create config.yaml
    cat <<EOL_CONFIG > $CONFIG_FILE
base_url: https://$IP_ADDRESS/
versions: [v3, v4, v5]
mcp_crawl_port: $MCP_CRAWL_PORT
mcp_fs_port: $MCP_FS_PORT
log_level: DEBUG
EOL_CONFIG
    chown $INSPECTOR_USER $INSTALL_DIR/main.py $CONFIG_FILE
    chmod 644 $INSTALL_DIR/main.py $CONFIG_FILE
}

# Function to setup daemon with systemd
setup_daemon() {
    echo "Setting up systemd daemon..."
    mkdir -p $LOG_DIR
    rm -f $LOG_DIR/inspector.log $LOG_DIR/inspector.err
    chown -R $INSPECTOR_USER $INSTALL_DIR $LOG_DIR $VENV_DIR
    cat <<EOL_SERVICE > /etc/systemd/system/docs-inspector.service
[Unit]
Description=Docs Content Inspector Daemon

[Service]
ExecStart=$VENV_DIR/bin/python $INSTALL_DIR/main.py --run
Restart=always
User=$INSPECTOR_USER
TimeoutStopSec=90

[Install]
WantedBy=multi-user.target
EOL_SERVICE
    systemctl daemon-reload
    systemctl enable --now docs-inspector.service
    echo "Daemon installed and started."
}

# Main execution
check_prereqs
install_deps
setup_user
setup_python_env
setup_crawl4ai
setup_fs_mcp
install_inspector
setup_daemon

echo "Installation complete. Check logs in $LOG_DIR/inspector.log or with journalctl -u docs-inspector.service"
