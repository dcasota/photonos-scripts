"""
Common utility functions for the kernelpatches solution.
"""

import hashlib
import logging
import os
import re
import shutil
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

import requests
from rich.console import Console
from rich.logging import RichHandler

from scripts.config import KernelConfig, DEFAULT_CONFIG, KERNEL_MAPPINGS
from scripts.models import KernelVersion, Patch, PatchTarget


# Rich console for output
console = Console()


def setup_logging(
    name: str = "kernelpatches",
    level: int = logging.INFO,
    log_file: Optional[Path] = None,
) -> logging.Logger:
    """Set up logging with Rich handler."""
    logger = logging.getLogger(name)
    logger.setLevel(level)
    
    # Clear existing handlers
    logger.handlers.clear()
    
    # Console handler with Rich
    console_handler = RichHandler(
        console=console,
        show_time=True,
        show_path=False,
        rich_tracebacks=True,
    )
    console_handler.setLevel(level)
    logger.addHandler(console_handler)
    
    # File handler if specified
    if log_file:
        log_file.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(level)
        file_handler.setFormatter(
            logging.Formatter("%(asctime)s - %(name)s - %(levelname)s - %(message)s")
        )
        logger.addHandler(file_handler)
    
    return logger


# Default logger
logger = setup_logging()


def check_network(
    hosts: Optional[List[str]] = None,
    timeout: int = 30,
    retries: int = 3,
) -> bool:
    """
    Check network connectivity to required hosts.
    
    Args:
        hosts: List of hosts to check (default: github.com, cdn.kernel.org, nvd.nist.gov)
        timeout: Connection timeout in seconds
        retries: Number of retry attempts
    
    Returns:
        True if any host is reachable, False otherwise
    """
    if hosts is None:
        hosts = ["github.com", "cdn.kernel.org", "nvd.nist.gov"]
    
    for attempt in range(1, retries + 1):
        for host in hosts:
            try:
                response = requests.head(
                    f"https://{host}",
                    timeout=timeout,
                    allow_redirects=True,
                )
                if response.status_code < 500:
                    logger.debug(f"Network check passed: {host} reachable")
                    return True
            except requests.RequestException:
                continue
        
        if attempt < retries:
            logger.warning(f"Network check attempt {attempt}/{retries} failed, retrying...")
            time.sleep(5)
    
    logger.error(f"Network is not available after {retries} attempts")
    return False


def calculate_sha512(file_path: Path) -> str:
    """
    Calculate SHA512 hash of a file.
    
    Args:
        file_path: Path to the file
    
    Returns:
        Hexadecimal SHA512 hash string
    """
    sha512 = hashlib.sha512()
    with open(file_path, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            sha512.update(chunk)
    return sha512.hexdigest()


def download_file(
    url: str,
    dest_path: Path,
    timeout: int = 60,
    show_progress: bool = True,
) -> bool:
    """
    Download a file from URL.
    
    Args:
        url: URL to download from
        dest_path: Destination file path
        timeout: Request timeout in seconds
        show_progress: Show download progress
    
    Returns:
        True if download succeeded, False otherwise
    """
    try:
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        
        with requests.get(url, stream=True, timeout=timeout) as response:
            response.raise_for_status()
            total_size = int(response.headers.get("content-length", 0))
            
            with open(dest_path, "wb") as f:
                if show_progress and total_size > 0:
                    from rich.progress import Progress
                    with Progress(console=console) as progress:
                        task = progress.add_task(f"Downloading {dest_path.name}", total=total_size)
                        for chunk in response.iter_content(chunk_size=8192):
                            f.write(chunk)
                            progress.update(task, advance=len(chunk))
                else:
                    for chunk in response.iter_content(chunk_size=8192):
                        f.write(chunk)
        
        return True
    except Exception as e:
        logger.error(f"Failed to download {url}: {e}")
        if dest_path.exists():
            dest_path.unlink()
        return False


def run_command(
    cmd: List[str],
    cwd: Optional[Path] = None,
    timeout: Optional[int] = None,
    capture_output: bool = True,
    check: bool = False,
) -> Tuple[int, str, str]:
    """
    Run a shell command.
    
    Args:
        cmd: Command and arguments as list
        cwd: Working directory
        timeout: Command timeout in seconds
        capture_output: Capture stdout and stderr
        check: Raise exception on non-zero exit
    
    Returns:
        Tuple of (return_code, stdout, stderr)
    """
    try:
        result = subprocess.run(
            cmd,
            cwd=cwd,
            timeout=timeout,
            capture_output=capture_output,
            text=True,
            check=check,
        )
        return result.returncode, result.stdout or "", result.stderr or ""
    except subprocess.TimeoutExpired:
        logger.error(f"Command timed out after {timeout}s: {' '.join(cmd)}")
        return -1, "", f"Command timed out after {timeout}s"
    except subprocess.CalledProcessError as e:
        return e.returncode, e.stdout or "", e.stderr or ""
    except Exception as e:
        logger.error(f"Command failed: {e}")
        return -1, "", str(e)


def safe_remove_dir(dir_path: Path) -> None:
    """Safely remove a directory and its contents."""
    if dir_path.exists() and dir_path.is_dir():
        # Remove lock files first
        for lock_file in dir_path.glob("**/*.lock"):
            try:
                lock_file.unlink()
            except Exception:
                pass
        
        try:
            shutil.rmtree(dir_path)
        except Exception as e:
            logger.warning(f"Failed to remove directory {dir_path}: {e}")


def create_output_dir(prefix: str = "backport") -> Path:
    """Create a timestamped output directory."""
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_dir = Path(f"/tmp/{prefix}_{timestamp}")
    output_dir.mkdir(parents=True, exist_ok=True)
    return output_dir


def version_less_than(v1: str, v2: str) -> bool:
    """
    Compare two kernel versions.
    
    Args:
        v1: First version string
        v2: Second version string
    
    Returns:
        True if v1 < v2
    """
    kv1 = KernelVersion.parse(v1)
    kv2 = KernelVersion.parse(v2)
    return kv1 < kv2


def get_photon_kernel_version(kernel_version: str, repo_dir: Path) -> Optional[str]:
    """
    Get current Photon kernel version from spec file.
    
    Args:
        kernel_version: Kernel series (e.g., "6.1")
        repo_dir: Path to Photon repository
    
    Returns:
        Full version string or None
    """
    mapping = KERNEL_MAPPINGS.get(kernel_version)
    if not mapping:
        return None
    
    spec_path = repo_dir / mapping.spec_dir / "linux.spec"
    if not spec_path.exists():
        return None
    
    # Import here to avoid circular dependency
    from scripts.spec_file import SpecFile
    spec = SpecFile(spec_path)
    return spec.version


def determine_patch_targets(
    patch: Patch,
    patch_content: str,
    skills_file: Optional[Path] = None,
) -> PatchTarget:
    """
    Determine which spec files should receive a patch.
    
    Args:
        patch: Patch object
        patch_content: Patch file content
        skills_file: Optional skills file for explicit routing
    
    Returns:
        PatchTarget indicating where patch should be applied
    """
    # Check skills file first
    if skills_file and skills_file.exists():
        with open(skills_file) as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split("|")
                if len(parts) >= 2 and patch.sha.startswith(parts[0]):
                    target = parts[1].lower()
                    try:
                        return PatchTarget(target)
                    except ValueError:
                        # Handle comma-separated targets
                        if "," in target:
                            return PatchTarget.ALL  # Simplified
    
    # Auto-detect based on patch content
    if not patch_content:
        return PatchTarget.ALL
    
    # Check for GPU drivers (base only, not ESX)
    if re.search(r"^\+\+\+.*drivers/gpu/", patch_content, re.MULTILINE):
        return PatchTarget.BASE
    
    # Check for KVM/virtualization (base + esx)
    if re.search(r"^\+\+\+.*arch/x86/kvm/", patch_content, re.MULTILINE):
        return PatchTarget.ALL  # Simplified to ALL for safety
    
    # Check for hypervisor drivers (base + esx)
    if re.search(r"^\+\+\+.*(hyperv|vmw|xen)/", patch_content, re.MULTILINE):
        return PatchTarget.ALL
    
    # Check for RT scheduler (base + rt)
    if re.search(r"^\+\+\+.*kernel/sched/.*rt", patch_content, re.MULTILINE):
        return PatchTarget.ALL
    
    # Default: apply to all
    return PatchTarget.ALL


def expand_targets_to_specs(target: PatchTarget, available_specs: List[str]) -> List[str]:
    """
    Expand a PatchTarget to actual spec file names.
    
    Args:
        target: PatchTarget enum value
        available_specs: List of available spec files
    
    Returns:
        List of spec file names to apply patch to
    """
    if target == PatchTarget.NONE:
        return []
    
    if target == PatchTarget.ALL:
        return available_specs
    
    target_map = {
        PatchTarget.BASE: ["linux.spec"],
        PatchTarget.ESX: ["linux-esx.spec"],
        PatchTarget.RT: ["linux-rt.spec"],
    }
    
    requested = target_map.get(target, [])
    return [spec for spec in requested if spec in available_specs]


def extract_cve_ids(text: str) -> List[str]:
    """Extract CVE IDs from text."""
    pattern = r"CVE-\d{4}-\d{4,}"
    return list(set(re.findall(pattern, text, re.IGNORECASE)))


def extract_commit_sha(url: str) -> Optional[str]:
    """Extract commit SHA from a git URL."""
    patterns = [
        r"commit/([a-f0-9]{40})",
        r"/c/([a-f0-9]{40})",
        r"\?id=([a-f0-9]{40})",
    ]
    for pattern in patterns:
        match = re.search(pattern, url)
        if match:
            return match.group(1)
    return None


def get_github_token() -> Optional[str]:
    """Get GitHub token from environment or gh CLI."""
    # Check environment variable
    token = os.environ.get("GITHUB_TOKEN")
    if token:
        return token
    
    # Try gh CLI
    try:
        returncode, stdout, _ = run_command(["gh", "auth", "token"])
        if returncode == 0 and stdout.strip():
            return stdout.strip()
    except Exception:
        pass
    
    return None


def format_duration(seconds: int) -> str:
    """Format duration in seconds to human-readable string."""
    if seconds < 60:
        return f"{seconds}s"
    elif seconds < 3600:
        minutes = seconds // 60
        secs = seconds % 60
        return f"{minutes}m {secs}s"
    else:
        hours = seconds // 3600
        minutes = (seconds % 3600) // 60
        return f"{hours}h {minutes}m"
