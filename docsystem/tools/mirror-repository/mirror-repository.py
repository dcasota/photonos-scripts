#!/usr/bin/env python3
"""
Mirror a GitHub repository to another GitHub repository.

Usage:
    ./mirror-repository.py --original-repo <URL> --target-repo <URL> [--local-path <PATH>]
    
Required environment variables: GITHUB_USERNAME, GITHUB_TOKEN
"""

import argparse
import base64
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from urllib.parse import urlparse

import requests


def check_command(cmd: str) -> bool:
    """Check if a command is available."""
    return shutil.which(cmd) is not None


def is_root() -> bool:
    """Check if script is running as root."""
    return os.geteuid() == 0


def install_git_lfs() -> bool:
    """Install git-lfs using tdnf if running as root."""
    if not is_root():
        print("Error: git-lfs is required for this repository but not installed.")
        print("Run as root to auto-install, or install manually: tdnf install -y git-lfs")
        return False
    
    print("git-lfs not found. Installing automatically (running as root)...")
    
    if not check_command('tdnf'):
        print("Error: tdnf not found. Cannot auto-install git-lfs.")
        return False
    
    result = subprocess.run(['tdnf', 'install', '-y', 'git-lfs'], capture_output=False)
    if result.returncode != 0:
        print("Error: Failed to install git-lfs.")
        return False
    
    print("git-lfs installed successfully.")
    return True


def parse_github_url(url: str) -> tuple[str, str] | None:
    """Extract owner and repo name from a GitHub URL."""
    pattern = r'https://github\.com/([^/]+)/([^/.]+)(?:\.git)?'
    match = re.match(pattern, url)
    if match:
        return match.group(1), match.group(2)
    return None


def check_lfs(owner: str, repo: str, token: str) -> bool:
    """Check if the repository uses Git LFS."""
    headers = {
        'Accept': 'application/vnd.github.v3+json',
        'Authorization': f'token {token}'
    }
    url = f'https://api.github.com/repos/{owner}/{repo}/contents/.gitattributes'
    
    try:
        response = requests.get(url, headers=headers)
        if response.status_code == 404:
            return False
        
        data = response.json()
        if 'content' in data:
            content = base64.b64decode(data['content']).decode('utf-8', errors='ignore')
            return 'filter=lfs' in content
    except Exception:
        pass
    
    return False


def check_repo_exists(owner: str, repo: str, token: str) -> bool:
    """Check if a repository exists."""
    headers = {'Authorization': f'token {token}'}
    url = f'https://api.github.com/repos/{owner}/{repo}'
    
    response = requests.get(url, headers=headers)
    if response.status_code == 200:
        return True
    elif response.status_code == 404:
        return False
    else:
        print(f"Error checking repository: HTTP {response.status_code}")
        sys.exit(1)


def create_repo(repo_name: str, token: str) -> bool:
    """Create a new repository."""
    headers = {
        'Authorization': f'token {token}',
        'Accept': 'application/vnd.github.v3+json'
    }
    url = 'https://api.github.com/user/repos'
    data = {
        'name': repo_name,
        'auto_init': False,
        'private': False
    }
    
    response = requests.post(url, headers=headers, json=data)
    if response.status_code in [200, 201]:
        print("Repository created successfully.")
        return True
    else:
        print(f"Error creating repository: {response.status_code} - {response.text}")
        return False


def run_command(cmd: list[str], cwd: str = None, check: bool = True) -> subprocess.CompletedProcess:
    """Run a shell command."""
    print(f"Running: {' '.join(cmd)}")
    result = subprocess.run(cmd, cwd=cwd, capture_output=False)
    if check and result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, cmd)
    return result


def delete_refs(clone_dir: str, ref_prefix: str):
    """Delete refs matching a prefix."""
    result = subprocess.run(
        ['git', 'for-each-ref', '--format=%(refname)', ref_prefix],
        cwd=clone_dir,
        capture_output=True,
        text=True
    )
    
    refs = result.stdout.strip().split('\n')
    for ref in refs:
        if ref:
            subprocess.run(['git', 'update-ref', '-d', ref], cwd=clone_dir)


def main():
    parser = argparse.ArgumentParser(
        description='Mirror a GitHub repository to another GitHub repository.',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog='''
Examples:
    %(prog)s --original-repo https://github.com/vmware/photon --target-repo https://github.com/user/photon-mirror
    %(prog)s --original-repo https://github.com/vmware/photon --target-repo https://github.com/user/photon-mirror --local-path /tmp/photon-clone

Environment variables:
    GITHUB_USERNAME    Your GitHub username
    GITHUB_TOKEN       Your GitHub personal access token
        '''
    )
    
    parser.add_argument(
        '--original-repo', '-o',
        required=True,
        help='URL of the original GitHub repository to mirror'
    )
    parser.add_argument(
        '--target-repo', '-t',
        required=True,
        help='URL of the target GitHub repository (mirror destination)'
    )
    parser.add_argument(
        '--local-path', '-l',
        default=None,
        help='Working directory for the clone (optional, temp directory will be created inside it; uses system temp if not specified)'
    )
    
    args = parser.parse_args()
    
    # Check required commands
    for cmd in ['git', 'curl']:
        if not check_command(cmd):
            print(f"Error: {cmd} is required but not installed.")
            sys.exit(1)
    
    # Get environment variables
    github_username = os.environ.get('GITHUB_USERNAME')
    github_token = os.environ.get('GITHUB_TOKEN')
    
    if not github_username or not github_token:
        print("Error: GITHUB_USERNAME and GITHUB_TOKEN environment variables must be set.")
        sys.exit(1)
    
    # Parse original repo URL
    original_parsed = parse_github_url(args.original_repo)
    if not original_parsed:
        print("Error: --original-repo must be a valid GitHub repository URL.")
        sys.exit(1)
    original_owner, original_repo = original_parsed
    
    # Parse target repo URL
    target_parsed = parse_github_url(args.target_repo)
    if not target_parsed:
        print("Error: --target-repo must be a valid GitHub repository URL.")
        sys.exit(1)
    target_owner, target_repo = target_parsed
    
    print(f"Original repository: {original_owner}/{original_repo}")
    print(f"Target repository: {target_owner}/{target_repo}")
    
    # Check for LFS
    uses_lfs = check_lfs(original_owner, original_repo, github_token)
    if uses_lfs:
        if not check_command('git-lfs'):
            if not install_git_lfs():
                sys.exit(1)
        print("Git LFS detected in original repository.")
    
    # Configure git
    subprocess.run(['git', 'config', '--global', 'user.email', f'{github_username}@gmail.com'])
    subprocess.run(['git', 'config', '--global', 'user.name', github_username])
    
    # Check if target repo exists, create if not
    if check_repo_exists(target_owner, target_repo, github_token):
        print("Target repository already exists. Proceeding with mirroring (note: this will overwrite existing content).")
    else:
        print("Target repository does not exist. Creating it now...")
        if not create_repo(target_repo, github_token):
            sys.exit(1)
        time.sleep(2)
    
    # Determine clone directory
    # If local_path is provided, create temp directory inside it; otherwise use system temp
    if args.local_path:
        os.makedirs(args.local_path, exist_ok=True)
        clone_dir = tempfile.mkdtemp(prefix=f"{original_repo}.", dir=args.local_path)
    else:
        clone_dir = tempfile.mkdtemp(prefix=f"{original_repo}.")
    
    print(f"Clone directory: {clone_dir}")
    
    try:
        # Clone the original repository as a mirror
        run_command(['git', 'clone', '--mirror', '--progress', args.original_repo, clone_dir])
        
        # Delete non-standard refs
        print("Cleaning up non-standard refs...")
        delete_refs(clone_dir, 'refs/users')
        delete_refs(clone_dir, 'refs/changes')
        delete_refs(clone_dir, 'refs/pull')
        
        # Handle LFS if present
        config_path = os.path.join(clone_dir, 'config')
        if os.path.exists(config_path):
            with open(config_path, 'r') as f:
                if '[lfs]' in f.read():
                    print("Git LFS detected. Handling LFS objects...")
                    # Ensure git-lfs is installed
                    if not check_command('git-lfs'):
                        if not install_git_lfs():
                            raise subprocess.CalledProcessError(1, ['git-lfs'])
                    mirror_url = f'https://{github_username}:{github_token}@github.com/{target_owner}/{target_repo}.git'
                    run_command(['git', 'lfs', 'fetch', '--all'], cwd=clone_dir)
                    run_command(['git', 'lfs', 'push', '--all', mirror_url], cwd=clone_dir)
        
        # Push to mirror (--force ensures all refs are updated even if up-to-date)
        mirror_url = f'https://{github_username}:{github_token}@github.com/{target_owner}/{target_repo}.git'
        run_command(['git', 'push', '--mirror', '--force', '--progress', mirror_url], cwd=clone_dir)
        
        # Show summary of all branches pushed
        result = subprocess.run(
            ['git', 'for-each-ref', '--format=%(refname:short)', 'refs/heads'],
            cwd=clone_dir,
            capture_output=True,
            text=True
        )
        branches = [b for b in result.stdout.strip().split('\n') if b]
        print(f"\nAll {len(branches)} branches synchronized: {', '.join(branches)}")
        
        print(f"\nMirroring complete. The repository has been duplicated to https://github.com/{target_owner}/{target_repo}")
        
    except subprocess.CalledProcessError as e:
        print(f"Error during mirroring: {e}")
        sys.exit(1)
    finally:
        # Always clean up the temporary clone directory
        shutil.rmtree(clone_dir, ignore_errors=True)
        print("Temporary directory cleaned up.")


if __name__ == '__main__':
    main()
