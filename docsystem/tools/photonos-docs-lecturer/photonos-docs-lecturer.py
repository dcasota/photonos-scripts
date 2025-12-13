#!/usr/bin/env python3
"""
Photon OS Documentation Lecturer
A comprehensive command-line tool for crawling Photon OS documentation served by Nginx,
identifying issues (grammar/spelling, markdown artifacts, orphan links/images, unaligned images,
heading hierarchy violations), generating CSV reports, and optionally applying fixes via git 
push and GitHub PR.
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
VERSION = "2.4"
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

# Plugin system imports
from plugins import PluginManager, Issue, FixResult
from plugins.integration import create_plugin_manager, ALL_PLUGINS, FIX_ID_MAP
from plugins.install_tools import install_tools, set_tool_info
from plugins.apply_fixes import FixApplicator
from plugins.llm_client import LLMClient
from plugins.documentation_lecturer import DocumentationLecturer, set_dependencies, set_tool_info as set_lecturer_tool_info

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
    
    # Pass dependencies to the DocumentationLecturer plugin
    set_dependencies({
        'requests': requests,
        'BeautifulSoup': BeautifulSoup,
        'language_tool_python': language_tool_python,
        'Retry': Retry,
        'HTTPAdapter': HTTPAdapter,
        'tqdm': tqdm,
        'Image': Image,
        'HAS_TQDM': HAS_TQDM,
        'HAS_PIL': HAS_PIL,
    })
    
    # Pass tool info to the DocumentationLecturer plugin
    set_lecturer_tool_info(TOOL_NAME, VERSION)


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
  +--------------------------+-------------+---------------+------------------------------------------+
  | Issue Type               | Detected    | Fix Mode      | Description                              |
  +--------------------------+-------------+---------------+------------------------------------------+
  | Broken emails            | Always      | Automatic     | Fix domain split with whitespace         |
  | Deprecated URLs          | Always      | Automatic     | VMware, VDDK, OVFTOOL, AWS, bosh-stemcell|
  | Hardcoded replaces       | Always      | Automatic     | Fix known typos and errors               |
  | Heading hierarchy        | Always      | Automatic     | Fix heading level skips                  |
  | Header spacing           | Always      | Automatic     | ####Title -> #### Title                  |
  | HTML comments            | Always      | Automatic     | Remove <!-- --> markers, keep content    |
  | VMware spelling          | Always      | Automatic     | vmware -> VMware                         |
  | Backticks                | Always      | LLM-assisted  | All backtick issues (requires --llm)     |
  | Grammar/spelling         | Always      | LLM-assisted  | Grammar and spelling (requires --llm)    |
  | Markdown artifacts       | Always      | LLM-assisted  | Unrendered markdown (requires --llm)     |
  | Indentation issues       | Always      | LLM-assisted  | Fix indentation (requires --llm)         |
  | Numbered lists           | Always      | Automatic     | Fix duplicate list numbers               |
  | Broken links             | Always      | Report only   | Manual review needed                     |
  | Broken images            | Always      | Report only   | Manual review needed                     |
  | Unaligned images         | Always      | Report only   | Manual review needed                     |
  +--------------------------+-------------+---------------+------------------------------------------+

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
    ID  Name                  Description                                         [LLM]
    --  --------------------  --------------------------------------------------- -----
     1  broken-emails         Fix broken email addresses (domain split)           
     2  deprecated-urls       Fix deprecated URLs (VMware, VDDK, OVFTOOL, AWS)    
     3  hardcoded-replaces    Fix known typos and errors (hardcoded replacements) 
     4  heading-hierarchy     Fix heading hierarchy violations (skipped levels)   
     5  header-spacing        Fix markdown headers missing space                  
     6  html-comments         Fix HTML comments (remove markers, keep content)    
     7  vmware-spelling       Fix VMware spelling (vmware -> VMware)              
     8  backticks             Fix all backtick issues (spacing, errors, URLs)     [LLM]
     9  grammar               Fix grammar and spelling issues                     [LLM]
    10  markdown-artifacts    Fix unrendered markdown artifacts                   [LLM]
    11  indentation           Fix indentation issues                              [LLM]
    12  numbered-lists        Fix numbered list sequence errors                   

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
    """Run unit tests from plugins/tests.py module."""
    import sys
    import os
    
    # Add plugins directory to path
    plugins_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'plugins')
    sys.path.insert(0, plugins_dir)
    
    try:
        from tests import run_tests as _run_tests
        return _run_tests()
    except ImportError as e:
        print(f"ERROR: Could not import tests module: {e}", file=sys.stderr)
        print("Make sure plugins/tests.py exists.", file=sys.stderr)
        return 1


# =============================================================================
# Tool Installation
# =============================================================================


# NOTE: Unit tests have been moved to plugins/tests.py
# See README-tests.md for documentation


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
        set_tool_info(TOOL_NAME, VERSION)
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
