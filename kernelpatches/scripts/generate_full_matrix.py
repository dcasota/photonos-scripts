#!/usr/bin/env python3
"""
Generate a comprehensive CVE coverage matrix for all supported kernels.

This script:
1. Downloads stable patches from kernel.org for each kernel version
2. Fetches CVEs from all sources (NVD with yearly feeds)
3. Builds a complete coverage matrix with patch-level analysis
4. Collects existing CVE patches and analyzes against kernel source
5. Exports to JSON, CSV, and Markdown formats

Usage:
    python scripts/generate_full_matrix.py --output /tmp/full_matrix
    python scripts/generate_full_matrix.py --output /tmp/full_matrix --download-patches
"""

import argparse
import asyncio
import lzma
import subprocess
import sys
import tarfile
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.config import DEFAULT_CONFIG, SUPPORTED_KERNELS, KernelConfig, get_kernel_org_url
from scripts.cve_sources import NVDFetcher, GHSAFetcher, AtomFetcher
from scripts.cve_matrix import CVEMatrixBuilder, CVECoverageMatrix, CVEPatchState, KernelCVEStatus
from scripts.stable_patches import StablePatchManager
from scripts.common import logger, extract_cve_ids

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn

console = Console()


async def fetch_all_cves(output_dir: Path, config: KernelConfig, kernel_version: str = "5.10") -> list:
    """Fetch CVEs from all sources and merge them."""
    all_cves = {}
    
    console.print("\n[bold blue]Step 3: Fetching CVEs from all sources[/bold blue]")
    
    # NVD (primary source with yearly feeds)
    console.print("  Fetching from NVD (with yearly feeds)...")
    nvd_fetcher = NVDFetcher(config)
    
    # Force yearly feeds refresh for comprehensive data
    nvd_fetcher.yearly_marker_file.unlink(missing_ok=True)
    
    nvd_cves = await nvd_fetcher.fetch_async(kernel_version, output_dir)
    for cve in nvd_cves:
        all_cves[cve.cve_id] = cve
    console.print(f"    NVD: {len(nvd_cves)} CVEs")
    
    # GHSA (supplementary)
    try:
        console.print("  Fetching from GitHub Advisory Database...")
        ghsa_fetcher = GHSAFetcher(config)
        ghsa_cves = await ghsa_fetcher.fetch_async(kernel_version, output_dir)
        new_from_ghsa = 0
        for cve in ghsa_cves:
            if cve.cve_id not in all_cves:
                all_cves[cve.cve_id] = cve
                new_from_ghsa += 1
            else:
                # Merge references
                existing = all_cves[cve.cve_id]
                existing_urls = {r.url for r in existing.references}
                for ref in cve.references:
                    if ref.url not in existing_urls:
                        existing.references.append(ref)
        console.print(f"    GHSA: {len(ghsa_cves)} CVEs ({new_from_ghsa} new)")
    except Exception as e:
        console.print(f"    [yellow]GHSA fetch failed: {e}[/yellow]")
    
    # Atom feed (supplementary)
    try:
        console.print("  Fetching from linux-cve-announce Atom feed...")
        atom_fetcher = AtomFetcher(config)
        atom_cves = await atom_fetcher.fetch_async(kernel_version, output_dir)
        new_from_atom = 0
        for cve in atom_cves:
            if cve.cve_id not in all_cves:
                all_cves[cve.cve_id] = cve
                new_from_atom += 1
        console.print(f"    Atom: {len(atom_cves)} CVEs ({new_from_atom} new)")
    except Exception as e:
        console.print(f"    [yellow]Atom fetch failed: {e}[/yellow]")
    
    console.print(f"  [green]Total unique CVEs: {len(all_cves)}[/green]")
    
    return list(all_cves.values())


async def download_stable_patches_async(
    kernel_versions: list,
    output_base: Path,
    config: KernelConfig,
    repo_dirs: Optional[dict] = None,
) -> dict:
    """Download stable patches for all kernel versions.
    
    Only downloads patches from current Photon version to latest stable.
    This avoids downloading patches already included in the kernel tarball.
    
    Args:
        kernel_versions: List of kernel versions to process
        output_base: Base output directory
        config: Kernel configuration
        repo_dirs: Optional mapping of kernel version to repo directory
                   (used to determine current Photon version)
    
    Returns:
        Dictionary mapping kernel version to patch directory
    """
    console.print("\n[bold blue]Step 4: Downloading stable patches from kernel.org[/bold blue]")
    
    patch_dirs = {}
    photon_versions = {}
    manager = StablePatchManager(config)
    repo_dirs = repo_dirs or {}
    
    for kv in kernel_versions:
        console.print(f"  Downloading patches for kernel {kv}...")
        patch_dir = output_base / "patches" / kv
        patch_dir.mkdir(parents=True, exist_ok=True)
        
        try:
            # Get current Photon version from spec file
            current_version = None
            if kv in repo_dirs:
                current_version = manager.get_current_photon_version(kv, repo_dirs[kv])
            
            # Get latest stable version
            latest = manager.get_latest_stable_version(kv)
            if latest:
                console.print(f"    Latest stable: {latest}")
                
                # Determine start subversion
                if current_version:
                    console.print(f"    Photon version: {current_version}")
                    # Parse current version to get patch number
                    from scripts.models import KernelVersion
                    current_kv = KernelVersion.parse(current_version)
                    # Start from current version (patches already in tarball are skipped)
                    start_subver = current_kv.patch
                    photon_versions[kv] = current_version
                else:
                    console.print(f"    [yellow]Photon version unknown, downloading all patches[/yellow]")
                    start_subver = 1
                
                # Download patches from current to latest
                patches = await manager.download_patches(
                    kv, patch_dir,
                    start_subver=start_subver,
                    end_subver=None,  # Download all available
                )
                console.print(f"    Downloaded {len(patches)} patches (from {kv}.{start_subver})")
                patch_dirs[kv] = patch_dir / "stable_patches"
            else:
                console.print(f"    [yellow]Could not determine latest version[/yellow]")
        except Exception as e:
            console.print(f"    [red]Failed: {e}[/red]")
    
    return patch_dirs, photon_versions


def collect_existing_cve_patches(
    matrix: CVECoverageMatrix,
    output_base: Path,
    config: KernelConfig,
    step_num: int = 6,
) -> Dict[str, List[Path]]:
    """Collect existing CVE patches from the cve_patches directory.
    
    Scans the cve_patches directory for existing .patch files and returns
    them grouped by kernel version. Does NOT download any patches.
    
    Args:
        matrix: The CVE coverage matrix (already built)
        output_base: Base output directory
        config: Kernel configuration
        step_num: Step number for display
    
    Returns:
        Dictionary mapping kernel version to list of existing patch files
    """
    console.print(f"\n[bold blue]Step {step_num}: Collecting existing CVE patches[/bold blue]")
    
    collected_patches: Dict[str, List[Path]] = {}
    
    for kv in matrix.kernel_versions:
        patch_dir = output_base / "cve_patches" / kv
        collected_patches[kv] = []
        
        if not patch_dir.exists():
            console.print(f"  {kv}: No CVE patches directory found at {patch_dir}")
            continue
        
        # Collect all existing .patch files
        existing_files = list(patch_dir.glob("*.patch"))
        collected_patches[kv] = existing_files
        
        console.print(f"  {kv}: Found {len(existing_files)} existing CVE patches in {patch_dir}")
    
    return collected_patches


async def download_cve_patches(
    matrix: CVECoverageMatrix,
    output_base: Path,
    config: KernelConfig,
    step_num: int = 6,
) -> Dict[str, List[Path]]:
    """Download CVE patches for CVEs that have fix commits.
    
    Downloads patches from git.kernel.org for each CVE that has fix_commits
    but is not yet included in the kernel.
    
    Args:
        matrix: The CVE coverage matrix (already built)
        output_base: Base output directory
        config: Kernel configuration
        step_num: Step number for display
    
    Returns:
        Dictionary mapping kernel version to list of downloaded patch files
    """
    import re
    import aiohttp
    
    console.print(f"\n[bold blue]Step {step_num}: Downloading CVE patches[/bold blue]")
    
    downloaded_patches: Dict[str, List[Path]] = {}
    
    for kv in matrix.kernel_versions:
        patch_dir = output_base / "cve_patches" / kv
        patch_dir.mkdir(parents=True, exist_ok=True)
        downloaded_patches[kv] = []
        
        # Get CVEs that need patches (have fix_commits but not included)
        cves_to_download = []
        for entry in matrix.entries:
            status = entry.kernel_status.get(kv)
            if status and status.state != CVEPatchState.CVE_INCLUDED:
                if entry.fix_commits:
                    cves_to_download.append(entry)
        
        if not cves_to_download:
            console.print(f"  {kv}: No CVE patches to download")
            continue
        
        console.print(f"  {kv}: Downloading patches for {len(cves_to_download)} CVEs...")
        
        downloaded_count = 0
        async with aiohttp.ClientSession() as session:
            for entry in cves_to_download:
                for commit in entry.fix_commits[:3]:  # Limit to first 3 commits per CVE
                    # Extract commit SHA from URL or use directly
                    if "/" in commit:
                        match = re.search(r"/([a-f0-9]{40})", commit)
                        if match:
                            commit_sha = match.group(1)
                        else:
                            continue
                    else:
                        commit_sha = commit
                    
                    patch_file = patch_dir / f"{commit_sha[:12]}-{entry.cve_id}.patch"
                    
                    if patch_file.exists():
                        downloaded_patches[kv].append(patch_file)
                        continue
                    
                    patch_url = f"https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id={commit_sha}"
                    
                    try:
                        async with session.get(patch_url, timeout=aiohttp.ClientTimeout(total=30)) as response:
                            if response.status == 200:
                                content = await response.text()
                                patch_file.write_text(content)
                                downloaded_patches[kv].append(patch_file)
                                downloaded_count += 1
                                break  # Got patch for this CVE
                    except Exception:
                        continue
        
        console.print(f"    Downloaded {downloaded_count} new patches")
        
        # Also collect existing patches
        existing = list(patch_dir.glob("*.patch"))
        for p in existing:
            if p not in downloaded_patches[kv]:
                downloaded_patches[kv].append(p)
        
        console.print(f"    Total: {len(downloaded_patches[kv])} patches available")
    
    return downloaded_patches


def _get_expected_tarball_size(tarball_url: str) -> Optional[int]:
    """Get expected file size from HTTP headers."""
    try:
        result = subprocess.run(
            ["curl", "-sI", tarball_url],
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            for line in result.stdout.split("\n"):
                if line.lower().startswith("content-length:"):
                    return int(line.split(":")[1].strip())
    except Exception:
        pass
    return None


def _verify_tarball_integrity(tarball_path: Path, expected_size: Optional[int] = None) -> Tuple[bool, str]:
    """Verify tarball integrity using xz test and optionally size check.
    
    Returns:
        Tuple of (is_valid, error_message)
    """
    if not tarball_path.exists():
        return False, "File does not exist"
    
    actual_size = tarball_path.stat().st_size
    
    # Check file size if expected size is known
    if expected_size and actual_size != expected_size:
        return False, f"Size mismatch: {actual_size} bytes vs expected {expected_size} bytes (download truncated)"
    
    # Verify xz integrity
    try:
        result = subprocess.run(
            ["xz", "-t", str(tarball_path)],
            capture_output=True,
            text=True,
            timeout=120,
        )
        if result.returncode != 0:
            return False, f"xz integrity check failed: {result.stderr.strip()}"
    except subprocess.TimeoutExpired:
        return False, "xz integrity check timed out"
    except FileNotFoundError:
        # xz not available, skip integrity check
        pass
    except Exception as e:
        return False, f"xz integrity check error: {e}"
    
    return True, ""


async def download_kernel_tarball(
    kernel_version: str,
    photon_version: str,
    output_base: Path,
    config: KernelConfig,
) -> Optional[Path]:
    """Download kernel tarball from kernel.org.
    
    Downloads the tarball for the Photon kernel version (e.g., linux-5.10.247.tar.xz).
    Verifies download integrity and retries on failure.
    
    Args:
        kernel_version: Kernel series (e.g., "5.10")
        photon_version: Full Photon kernel version (e.g., "5.10.247")
        output_base: Base output directory
        config: Kernel configuration
    
    Returns:
        Path to extracted kernel source directory, or None if failed
    """
    import aiohttp
    
    kernel_url = get_kernel_org_url(kernel_version)
    if not kernel_url:
        return None
    
    tarball_name = f"linux-{photon_version}.tar.xz"
    tarball_url = f"{kernel_url}{tarball_name}"
    tarball_dir = output_base / "tarballs"
    tarball_dir.mkdir(parents=True, exist_ok=True)
    tarball_path = tarball_dir / tarball_name
    extract_dir = output_base / "kernel_source"
    extract_dir.mkdir(parents=True, exist_ok=True)
    source_dir = extract_dir / f"linux-{photon_version}"
    
    # Check if already extracted
    if source_dir.exists() and (source_dir / "Makefile").exists():
        console.print(f"    Kernel source already extracted: {source_dir}")
        return source_dir
    
    # Get expected file size for verification
    expected_size = _get_expected_tarball_size(tarball_url)
    
    # Check if cached tarball is valid
    if tarball_path.exists():
        is_valid, error_msg = _verify_tarball_integrity(tarball_path, expected_size)
        if is_valid:
            console.print(f"    Tarball cached: {tarball_path}")
        else:
            console.print(f"    [yellow]Cached tarball is corrupted: {error_msg}[/yellow]")
            console.print(f"    [yellow]Removing and re-downloading...[/yellow]")
            tarball_path.unlink()
    
    # Download tarball if not cached or was corrupted
    max_retries = 3
    for attempt in range(max_retries):
        if tarball_path.exists():
            break
            
        if attempt > 0:
            console.print(f"    [yellow]Retry {attempt + 1}/{max_retries}...[/yellow]")
        
        console.print(f"    Downloading {tarball_name}...")
        
        # Use wget/curl for faster downloads of large files with resume support
        try:
            # Try wget first with continue flag for resume capability
            result = subprocess.run(
                ["wget", "-c", "--progress=dot:giga", "-O", str(tarball_path), tarball_url],
                timeout=900,  # 15 min timeout for large files
                capture_output=False,
            )
            if result.returncode == 0:
                # Verify download integrity
                is_valid, error_msg = _verify_tarball_integrity(tarball_path, expected_size)
                if is_valid:
                    console.print(f"    Downloaded {tarball_name}")
                else:
                    console.print(f"    [red]Download verification failed: {error_msg}[/red]")
                    tarball_path.unlink()
                    continue
            else:
                raise Exception(f"wget failed with code {result.returncode}")
        except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as wget_err:
            # Fallback to curl with resume support
            try:
                result = subprocess.run(
                    ["curl", "-C", "-", "-#", "-L", "-o", str(tarball_path), tarball_url],
                    timeout=900,
                    capture_output=False,
                )
                if result.returncode == 0:
                    # Verify download integrity
                    is_valid, error_msg = _verify_tarball_integrity(tarball_path, expected_size)
                    if is_valid:
                        console.print(f"    Downloaded {tarball_name}")
                    else:
                        console.print(f"    [red]Download verification failed: {error_msg}[/red]")
                        if tarball_path.exists():
                            tarball_path.unlink()
                        continue
                else:
                    raise Exception(f"curl failed with code {result.returncode}")
            except (subprocess.TimeoutExpired, FileNotFoundError, Exception) as curl_err:
                # Final fallback to aiohttp with optimized settings
                if tarball_path.exists():
                    tarball_path.unlink()
                console.print(f"    [yellow]wget/curl unavailable, using slower Python download[/yellow]")
                try:
                    async with aiohttp.ClientSession() as session:
                        async with session.get(
                            tarball_url,
                            timeout=aiohttp.ClientTimeout(total=900),
                            headers={"User-Agent": "kernel-backport-tool/1.0"},
                        ) as response:
                            if response.status != 200:
                                console.print(f"    [red]Failed to download tarball: HTTP {response.status}[/red]")
                                continue
                            
                            total_size = int(response.headers.get("content-length", 0))
                            downloaded = 0
                            last_pct = -5
                            
                            with open(tarball_path, "wb") as f:
                                # Use 1MB chunks for faster download
                                async for chunk in response.content.iter_chunked(1024 * 1024):
                                    f.write(chunk)
                                    downloaded += len(chunk)
                                    if total_size > 0:
                                        pct = downloaded * 100 // total_size
                                        # Only update every 5%
                                        if pct >= last_pct + 5:
                                            console.print(f"\r    Downloading: {pct}%", end="")
                                            last_pct = pct
                            console.print(f"\r    Downloaded {tarball_name} ({downloaded // (1024*1024)} MB)")
                            
                            # Verify download integrity
                            is_valid, error_msg = _verify_tarball_integrity(tarball_path, expected_size)
                            if not is_valid:
                                console.print(f"    [red]Download verification failed: {error_msg}[/red]")
                                tarball_path.unlink()
                                continue
                except Exception as e:
                    console.print(f"    [red]Failed to download tarball: {e}[/red]")
                    if tarball_path.exists():
                        tarball_path.unlink()
                    continue
    
    # Final check - did we get a valid tarball?
    if not tarball_path.exists():
        console.print(f"    [red]Failed to download tarball after {max_retries} attempts[/red]")
        return None
    
    # Extract tarball
    console.print(f"    Extracting {tarball_name}...")
    try:
        with tarfile.open(tarball_path, "r:xz") as tar:
            tar.extractall(path=extract_dir)
        console.print(f"    Extracted to: {source_dir}")
        return source_dir
    except Exception as e:
        console.print(f"    [red]Failed to extract tarball: {e}[/red]")
        return None


def _try_patch_in_dir(patch_path: Path, work_dir: Path) -> Tuple[Optional[bool], str]:
    """Try to apply patch in a specific directory.
    
    Args:
        patch_path: Path to the patch file
        work_dir: Directory to try applying the patch in
    
    Returns:
        Tuple of (is_included, reason) or (None, reason) if inconclusive
    """
    try:
        # Try reverse-apply first (if it succeeds, patch is already applied)
        result = subprocess.run(
            ["git", "apply", "--check", "--reverse", str(patch_path)],
            cwd=work_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            return True, "patch_already_applied"
        
        # Try forward apply to see if it would apply cleanly
        result = subprocess.run(
            ["git", "apply", "--check", str(patch_path)],
            cwd=work_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        if result.returncode == 0:
            return False, "patch_applicable"
        
        # Neither worked in this directory
        return None, "no_match"
        
    except subprocess.TimeoutExpired:
        return None, "timeout"
    except Exception as e:
        return None, f"error: {e}"


def analyze_patch_against_source(
    patch_path: Path,
    source_dir: Path,
) -> Tuple[bool, str]:
    """Check if a patch is already included in the kernel source.
    
    Tries applying patch in order: drivers/, crypto/, then root source dir.
    Uses git apply --check --reverse first (already applied), then
    git apply --check (applicable).
    
    Args:
        patch_path: Path to the patch file
        source_dir: Path to the kernel source directory (e.g. linux-5.10.247)
    
    Returns:
        Tuple of (is_included, reason)
        - is_included: True if patch appears to be already in source
        - reason: Description of the result
    """
    # Try subdirectories first, then root
    dirs_to_try = [
        source_dir / "drivers",
        source_dir / "crypto",
        source_dir,
    ]
    
    for try_dir in dirs_to_try:
        if not try_dir.exists():
            continue
        
        is_included, reason = _try_patch_in_dir(patch_path, try_dir)
        if is_included is not None:
            return is_included, reason
    
    # All directories failed
    return False, "patch_conflicts_or_missing_context"


async def download_kernel_tarballs_for_analysis(
    kernel_versions: List[str],
    photon_versions: Dict[str, str],
    output_base: Path,
    config: KernelConfig,
) -> Dict[str, Optional[Path]]:
    """Download kernel tarballs for all versions that need analysis.
    
    Args:
        kernel_versions: List of kernel versions to process
        photon_versions: Mapping of kernel version to Photon version
        output_base: Base output directory
        config: Kernel configuration
    
    Returns:
        Dictionary mapping kernel version to source directory path (or None if failed)
    """
    source_dirs: Dict[str, Optional[Path]] = {}
    
    for kv in kernel_versions:
        photon_ver = photon_versions.get(kv)
        if not photon_ver:
            console.print(f"  {kv}: [yellow]No Photon version available, skipping tarball download[/yellow]")
            source_dirs[kv] = None
            continue
        
        # Check if already extracted
        kernel_source_base = output_base / "kernel_source"
        source_dir = kernel_source_base / f"linux-{photon_ver}"
        
        if source_dir.exists() and (source_dir / "Makefile").exists():
            console.print(f"  {kv}: Kernel source already extracted: {source_dir}")
            source_dirs[kv] = source_dir
            continue
        
        # Download and extract tarball
        console.print(f"  {kv}: Downloading kernel tarball for {photon_ver}...")
        result = await download_kernel_tarball(kv, photon_ver, output_base, config)
        source_dirs[kv] = result
        
        if result:
            console.print(f"  {kv}: [green]Kernel source ready: {result}[/green]")
        else:
            console.print(f"  {kv}: [red]Failed to download kernel tarball[/red]")
    
    return source_dirs


def analyze_cve_patches_against_source(
    kernel_versions: List[str],
    photon_versions: Dict[str, str],
    cve_patch_dirs: Dict[str, List[Path]],
    output_base: Path,
    config: KernelConfig,
    step_num: int = 7,
    source_dirs: Optional[Dict[str, Optional[Path]]] = None,
    cve_map: Optional[Dict[str, Any]] = None,
) -> Dict[str, Dict[str, Tuple[bool, str]]]:
    """Analyze CVE patches against kernel source to detect already-included fixes.
    
    Uses CPE data from cve_map (if provided) to skip unnecessary patch checks.
    Falls back to git apply check when CPE data is unavailable.
    
    Args:
        kernel_versions: List of kernel versions to analyze
        photon_versions: Mapping of kernel version to Photon version
        cve_patch_dirs: Mapping of kernel version to list of CVE patch files
        output_base: Base output directory
        config: Kernel configuration
        step_num: Step number for display
        source_dirs: Optional pre-downloaded source directories
        cve_map: Optional mapping of CVE ID to CVE object (with cpe_ranges)
    
    Returns:
        Dictionary mapping kernel version to dict of {cve_id: (is_included, reason)}
    """
    console.print(f"\n[bold blue]Step {step_num}: Analyzing CVE patches against kernel source[/bold blue]")
    
    analysis_results: Dict[str, Dict[str, Tuple[bool, str]]] = {}
    
    # Find existing kernel sources and patches
    versions_to_analyze = []
    for kv in kernel_versions:
        analysis_results[kv] = {}
        photon_ver = photon_versions.get(kv)
        
        # Scan ALL .patch files in the CVE patches directory (not just from cve_patch_dirs)
        patch_dir = output_base / "cve_patches" / kv
        if patch_dir.exists():
            all_patches = list(patch_dir.glob("*.patch"))
        else:
            all_patches = cve_patch_dirs.get(kv, [])
        
        if not photon_ver:
            console.print(f"  {kv}: [yellow]No Photon version available, skipping[/yellow]")
            continue
        if not all_patches:
            console.print(f"  {kv}: No CVE patches to analyze")
            continue
        
        versions_to_analyze.append((kv, photon_ver, all_patches))
    
    if not versions_to_analyze:
        console.print("  No kernel versions to analyze")
        return analysis_results
    
    # Use provided source_dirs or check for existing ones
    if source_dirs is None:
        source_dirs = {}
        kernel_source_base = output_base / "kernel_source"
        for kv, photon_ver, _ in versions_to_analyze:
            source_dir = kernel_source_base / f"linux-{photon_ver}"
            if source_dir.exists():
                source_dirs[kv] = source_dir
                console.print(f"    Kernel source found: {source_dir}")
            else:
                source_dirs[kv] = None
                console.print(f"  {kv}: [red]No kernel source at {source_dir} - run with tarball download enabled[/red]")
    
    # Now analyze patches for each kernel version
    for kv, photon_ver, patches in versions_to_analyze:
        source_dir = source_dirs.get(kv)
        if not source_dir:
            console.print(f"  {kv}: [red]Could not get kernel source, skipping analysis[/red]")
            continue
        
        console.print(f"  {kv} ({photon_ver}): Analyzing {len(patches)} CVE patches...")
        
        # Initialize git repo in source dir for patch analysis
        if not (source_dir / ".git").exists():
            console.print(f"    Initializing git repo for patch analysis...")
            subprocess.run(
                ["git", "init"],
                cwd=source_dir,
                capture_output=True,
                timeout=60,
            )
            subprocess.run(
                ["git", "add", "-A"],
                cwd=source_dir,
                capture_output=True,
                timeout=120,
            )
            subprocess.run(
                ["git", "commit", "-m", "Initial kernel source"],
                cwd=source_dir,
                capture_output=True,
                timeout=120,
            )
        
        # Analyze each patch - first try CPE check, then fall back to git apply
        included_count = 0
        applicable_count = 0
        conflict_count = 0
        cpe_skipped_count = 0  # CVEs skipped due to CPE showing not vulnerable
        cpe_checked_count = 0
        
        for patch_path in patches:
            # Extract CVE ID from filename
            cve_ids = extract_cve_ids(patch_path.name)
            if not cve_ids:
                continue
            cve_id = cve_ids[0]
            
            # Step 1: Try CPE range check first using cached CVE data (no API calls!)
            cpe_affects = None
            cpe_reason = "no_cpe_data"
            
            if cve_map and cve_id in cve_map:
                cve_obj = cve_map[cve_id]
                # Use the is_version_affected method from the CVE model
                cpe_affects = cve_obj.is_version_affected(photon_ver)
                if cpe_affects is False:
                    cpe_reason = "cpe_not_in_range"
                elif cpe_affects is True:
                    cpe_reason = "cpe_vulnerable"
            
            if cpe_affects is False:
                # CPE data shows this kernel version is NOT vulnerable
                # (either patched or not in affected range)
                analysis_results[kv][cve_id] = (True, f"cpe_not_affected:{cpe_reason}")
                included_count += 1
                cpe_skipped_count += 1
                cpe_checked_count += 1
                continue
            
            if cpe_affects is True:
                cpe_checked_count += 1
                # CPE shows vulnerable - still need to verify with patch analysis
                # because the patch might have been applied manually
            
            # Step 2: Fall back to git apply check (slow but accurate)
            is_included, reason = analyze_patch_against_source(patch_path, source_dir)
            analysis_results[kv][cve_id] = (is_included, reason)
            
            if is_included:
                included_count += 1
            elif reason == "patch_applicable":
                applicable_count += 1
            else:
                conflict_count += 1
        
        console.print(
            f"    Results: {included_count} already included, "
            f"{applicable_count} applicable, {conflict_count} conflicts/other"
        )
        if cpe_skipped_count > 0:
            console.print(
                f"    CPE optimization: {cpe_skipped_count}/{cpe_checked_count} CVEs skipped via CPE range check"
            )
    
    return analysis_results


def update_matrix_with_source_analysis(
    matrix: CVECoverageMatrix,
    analysis_results: Dict[str, Dict[str, Tuple[bool, str]]],
    step_num: int = 8,
) -> CVECoverageMatrix:
    """Update the CVE matrix with source code analysis results.
    
    CVEs that are found to be already included in the kernel source
    should be marked as CVE_INCLUDED rather than CVE_PATCH_MISSING.
    
    Args:
        matrix: The CVE coverage matrix to update
        analysis_results: Results from analyze_cve_patches_against_source
        step_num: Step number for display
    
    Returns:
        Updated matrix
    """
    console.print(f"\n[bold blue]Step {step_num}: Updating matrix with source analysis[/bold blue]")
    
    updates_made = 0
    
    for entry in matrix.entries:
        for kv in matrix.kernel_versions:
            if kv not in analysis_results:
                continue
            
            kv_results = analysis_results[kv]
            if entry.cve_id not in kv_results:
                continue
            
            is_included, reason = kv_results[entry.cve_id]
            
            if is_included:
                # Update the entry's kernel status
                current_status = entry.kernel_status.get(kv)
                # Update if no status exists OR status is not already CVE_INCLUDED
                if current_status is None or current_status.state != CVEPatchState.CVE_INCLUDED:
                    # Get the photon version from kernel_coverage
                    kc = matrix.kernel_coverage.get(kv)
                    stable_patch = kc.photon_version if kc else None
                    
                    entry.kernel_status[kv] = KernelCVEStatus(
                        state=CVEPatchState.CVE_INCLUDED,
                        stable_patch=stable_patch,
                        fix_commit=current_status.fix_commit if current_status else None,
                    )
                    updates_made += 1
    
    # Update kernel_coverage totals
    for kv in matrix.kernel_versions:
        if kv in matrix.kernel_coverage:
            kc = matrix.kernel_coverage[kv]
            # Recalculate totals
            included = len(matrix.get_included(kv))
            in_newer = len(matrix.get_cve_in_newer_stable(kv))
            patch_avail = len(matrix.get_cve_patch_available(kv))
            missing = len(matrix.get_cve_patch_missing(kv))
            not_applicable = len(matrix.get_not_applicable(kv))
            
            kc.total_included = included
            kc.total_cve_in_newer_stable = in_newer
            kc.total_cve_patch_available = patch_avail
            kc.total_cve_patch_missing = missing
            kc.total_not_applicable = not_applicable
            
            # Update the stable patch coverage if exists
            if kc.stable_patches:
                sp = kc.stable_patches[0]
                sp.included = [e.cve_id for e in matrix.get_included(kv)]
                sp.cve_in_newer_stable = [e.cve_id for e in matrix.get_cve_in_newer_stable(kv)]
                sp.cve_patch_available = [e.cve_id for e in matrix.get_cve_patch_available(kv)]
                sp.cve_patch_missing = [e.cve_id for e in matrix.get_cve_patch_missing(kv)]
    
    console.print(f"  Updated {updates_made} CVE entries based on source analysis")
    
    return matrix


def build_matrix(
    cves: list,
    kernel_versions: list,
    repo_dirs: dict,
    patch_dirs: dict,
    config: KernelConfig,
    photon_versions: Optional[Dict[str, str]] = None,
    step_num: int = 6,
) -> CVECoverageMatrix:
    """Build the CVE coverage matrix."""
    console.print(f"\n[bold blue]Step {step_num}: Building CVE coverage matrix[/bold blue]")
    
    builder = CVEMatrixBuilder(kernel_versions, config)
    
    console.print(f"  Kernel versions: {', '.join(kernel_versions)}")
    console.print(f"  Total CVEs: {len(cves)}")
    console.print(f"  Repo dirs: {list(repo_dirs.keys()) or 'none'}")
    console.print(f"  Patch dirs: {list(patch_dirs.keys()) or 'none'}")
    if photon_versions:
        console.print(f"  Photon versions: {photon_versions}")
    
    matrix = builder.build_from_cves(cves, repo_dirs, patch_dirs, photon_versions)
    
    console.print(f"  [green]Matrix built with {matrix.total_cves} entries[/green]")
    
    return matrix


def save_matrix(matrix: CVECoverageMatrix, output_dir: Path, step_num: int = 7):
    """Save matrix in all formats."""
    console.print(f"\n[bold blue]Step {step_num}: Saving matrix files[/bold blue]")
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = f"full_cve_matrix_{timestamp}"
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # JSON
    json_path = output_dir / f"{base_name}.json"
    matrix.save_json(json_path)
    console.print(f"  JSON: {json_path}")
    
    # CSV
    csv_path = output_dir / f"{base_name}.csv"
    matrix.save_csv(csv_path)
    console.print(f"  CSV: {csv_path}")
    
    # Stable patch CSV
    patch_csv_path = output_dir / f"{base_name}_patches.csv"
    matrix.save_stable_patch_csv(patch_csv_path)
    console.print(f"  Patches CSV: {patch_csv_path}")
    
    # Markdown
    md_path = output_dir / f"{base_name}.md"
    matrix.save_markdown(md_path)
    console.print(f"  Markdown: {md_path}")


def print_summary(
    matrix: CVECoverageMatrix,
    analysis_results: Optional[Dict[str, Dict[str, Tuple[bool, str]]]] = None,
    cve_patch_dirs: Optional[Dict[str, List[Path]]] = None,
):
    """Print matrix summary including CVE patch analysis."""
    console.print("\n[bold blue]Matrix Summary[/bold blue]")
    
    summary = matrix.summary()
    sev_summary = matrix.severity_summary()
    
    console.print(f"\n  Total CVEs: {matrix.total_cves}")
    console.print(f"\n  Severity Distribution:")
    for sev, count in sev_summary.items():
        if count > 0:
            console.print(f"    {sev}: {count}")
    
    console.print(f"\n  Coverage by Kernel:")
    for kv in matrix.kernel_versions:
        s = summary[kv]
        photon_ver = s.get('photon_version', f'{kv}.0')
        latest_stable = s.get('latest_stable', f'{kv}.0')
        upgrade_note = f" → {latest_stable}" if s.get('upgrade_available') else ""
        console.print(
            f"    {kv} ({photon_ver}{upgrade_note}): "
            f"{s['cve_included']} included, {s.get('cve_in_newer_stable', 0)} in newer, "
            f"{s['cve_patch_available']} spec patch, {s['cve_patch_missing']} missing "
            f"({s['coverage_percent']:.1f}% coverage)"
        )
    
    # Critical gaps
    critical_gaps = matrix.get_critical_gaps()
    if critical_gaps:
        console.print(f"\n  [red]Critical/High Gaps: {len(critical_gaps)}[/red]")
        for gap in critical_gaps[:5]:
            console.print(f"    - {gap.cve_id} (CVSS {gap.cvss_score})")
        if len(critical_gaps) > 5:
            console.print(f"    ... and {len(critical_gaps) - 5} more")
    
    # Applicable CVE Patches Summary
    if analysis_results:
        console.print("\n[bold blue]Applicable CVE Patches[/bold blue]")
        
        # Collect all applicable CVEs across kernels
        all_applicable: Dict[str, List[str]] = {}  # cve_id -> list of kernel versions
        
        for kv in matrix.kernel_versions:
            if kv not in analysis_results:
                continue
            kv_results = analysis_results[kv]
            for cve_id, (is_inc, reason) in kv_results.items():
                if not is_inc and reason == "patch_applicable":
                    if cve_id not in all_applicable:
                        all_applicable[cve_id] = []
                    all_applicable[cve_id].append(kv)
        
        if not all_applicable:
            console.print("  No applicable CVE patches found")
        else:
            console.print(f"\n  Total Applicable: {len(all_applicable)}")
            
            # Severity Distribution for applicable patches
            sev_counts = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "UNKNOWN": 0}
            cve_entries: Dict[str, any] = {}
            
            for cve_id in all_applicable:
                for entry in matrix.entries:
                    if entry.cve_id == cve_id:
                        cve_entries[cve_id] = entry
                        sev = entry.severity.upper() if entry.severity else "UNKNOWN"
                        if sev in sev_counts:
                            sev_counts[sev] += 1
                        else:
                            sev_counts["UNKNOWN"] += 1
                        break
                else:
                    sev_counts["UNKNOWN"] += 1
            
            console.print(f"\n  Severity Distribution:")
            for sev in ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]:
                if sev_counts[sev] > 0:
                    console.print(f"    {sev}: {sev_counts[sev]}")
            
            # Coverage by Kernel
            console.print(f"\n  Coverage by Kernel:")
            for kv in matrix.kernel_versions:
                if kv not in analysis_results:
                    continue
                kv_results = analysis_results[kv]
                kv_applicable = sum(1 for is_inc, reason in kv_results.values() if not is_inc and reason == "patch_applicable")
                if kv_applicable > 0:
                    console.print(f"    {kv}: {kv_applicable} applicable patches")
            
            # Critical/High Gaps
            crit_high = []
            for cve_id, entry in cve_entries.items():
                sev = entry.severity.upper() if entry.severity else ""
                if sev in ["CRITICAL", "HIGH"]:
                    crit_high.append((cve_id, entry.cvss_score or 0.0, all_applicable[cve_id]))
            
            if crit_high:
                crit_high.sort(key=lambda x: x[1], reverse=True)
                console.print(f"\n  [red]Critical/High Gaps: {len(crit_high)}[/red]")
                for cve_id, cvss, kernels in crit_high:
                    console.print(f"    - {cve_id} (CVSS {cvss}) [{', '.join(kernels)}]")


async def main():
    parser = argparse.ArgumentParser(
        description="Generate comprehensive CVE coverage matrix for all supported kernels"
    )
    parser.add_argument(
        "--output", "-o",
        type=Path,
        default=Path("/tmp/cve_matrix"),
        help="Output directory for matrix files"
    )
    parser.add_argument(
        "--skip-patch-download",
        action="store_true",
        help="Skip downloading stable patches from kernel.org (not recommended)"
    )
    parser.add_argument(
        "--kernels",
        type=str,
        default=",".join(SUPPORTED_KERNELS),
        help=f"Comma-separated kernel versions (default: {','.join(SUPPORTED_KERNELS)})"
    )
    parser.add_argument(
        "--repo-base",
        type=Path,
        default=None,
        help="Base directory containing Photon repo clones (e.g., ./4.0, ./5.0)"
    )
    
    args = parser.parse_args()
    
    kernel_versions = [k.strip() for k in args.kernels.split(",")]
    config = KernelConfig.from_env()
    
    console.print("[bold]Comprehensive CVE Coverage Matrix Generator[/bold]")
    console.print(f"Kernels: {', '.join(kernel_versions)}")
    console.print(f"Output: {args.output}")
    
    # Step 1: Fetch CVEs
    cves = await fetch_all_cves(args.output, config, kernel_versions[0])
    
    # Step 2: Download stable patches (required for accurate CVE detection)
    patch_dirs = {}
    photon_versions = {}
    if args.skip_patch_download:
        console.print("\n[yellow]Skipping patch download (CVE detection will be incomplete!)[/yellow]")
        # Still try to get photon versions from remote
        manager = StablePatchManager(config)
        for kv in kernel_versions:
            pv = manager.get_current_photon_version_remote(kv)
            if pv:
                photon_versions[kv] = pv
    else:
        patch_dirs, photon_versions = await download_stable_patches_async(kernel_versions, args.output, config)
    
    # Build repo_dirs from repo_base or config
    repo_dirs = {}
    if args.repo_base:
        for kv in kernel_versions:
            mapping = {
                "5.10": "4.0",
                "6.1": "5.0", 
                "6.12": "common",
            }
            branch = mapping.get(kv, kv)
            repo_path = args.repo_base / branch
            if repo_path.exists():
                repo_dirs[kv] = repo_path
                console.print(f"  Found repo for {kv}: {repo_path}")
    
    # Determine step numbers based on options
    # Steps: 1=repos, 2=status, 3=CVEs, 4=stable patches, 5=matrix, 6=CVE patches, 7=analyze, 8=update, 9=save
    current_step = 5
    
    # Step 5: Build initial matrix
    matrix = build_matrix(cves, kernel_versions, repo_dirs, patch_dirs, config, photon_versions, step_num=current_step)
    current_step += 1
    
    # Step 6: Collect existing CVE patches
    cve_patch_dirs = collect_existing_cve_patches(matrix, args.output, config, step_num=current_step)
    current_step += 1
    
    # Step 7: Download kernel tarballs for source analysis
    console.print(f"\n[bold blue]Step {current_step}: Downloading kernel tarballs for source analysis[/bold blue]")
    source_dirs = await download_kernel_tarballs_for_analysis(
        kernel_versions,
        photon_versions,
        args.output,
        config,
    )
    current_step += 1
    
    # Build CVE map for CPE lookup (no API calls needed - data from NVD feeds)
    cve_map = {cve.cve_id: cve for cve in cves}
    
    # Step 8: Analyze CVE patches against kernel source
    analysis_results = analyze_cve_patches_against_source(
        kernel_versions,
        photon_versions,
        cve_patch_dirs,
        args.output,
        config,
        step_num=current_step,
        source_dirs=source_dirs,
        cve_map=cve_map,
    )
    current_step += 1
    
    # Step 8: Update matrix with source analysis
    matrix = update_matrix_with_source_analysis(matrix, analysis_results, step_num=current_step)
    current_step += 1
    
    # Save files
    save_matrix(matrix, args.output, step_num=current_step)
    
    # Print summary
    print_summary(matrix, analysis_results, cve_patch_dirs)
    
    console.print("\n[bold green]Done![/bold green]")


if __name__ == "__main__":
    asyncio.run(main())
