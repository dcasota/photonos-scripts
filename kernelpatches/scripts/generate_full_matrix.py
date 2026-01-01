#!/usr/bin/env python3
"""
Generate a comprehensive CVE coverage matrix for all supported kernels.

This script:
1. Downloads stable patches from kernel.org for each kernel version
2. Fetches CVEs from all sources (NVD with yearly feeds)
3. Builds a complete coverage matrix with patch-level analysis
4. Downloads kernel tarball and analyzes CVE patches against source
5. Exports to JSON, CSV, and Markdown formats

Usage:
    python scripts/generate_full_matrix.py --output /tmp/full_matrix
    python scripts/generate_full_matrix.py --output /tmp/full_matrix --download-patches
    python scripts/generate_full_matrix.py --output /tmp/full_matrix --analyze-source
"""

import argparse
import asyncio
import lzma
import subprocess
import sys
import tarfile
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple

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


async def fetch_all_cves(output_dir: Path, config: KernelConfig) -> list:
    """Fetch CVEs from all sources and merge them."""
    all_cves = {}
    
    console.print("\n[bold blue]Step 3: Fetching CVEs from all sources[/bold blue]")
    
    # NVD (primary source with yearly feeds)
    console.print("  Fetching from NVD (with yearly feeds)...")
    nvd_fetcher = NVDFetcher(config)
    
    # Force yearly feeds refresh for comprehensive data
    nvd_fetcher.yearly_marker_file.unlink(missing_ok=True)
    
    nvd_cves = await nvd_fetcher.fetch_async("5.10", output_dir)
    for cve in nvd_cves:
        all_cves[cve.cve_id] = cve
    console.print(f"    NVD: {len(nvd_cves)} CVEs")
    
    # GHSA (supplementary)
    try:
        console.print("  Fetching from GitHub Advisory Database...")
        ghsa_fetcher = GHSAFetcher(config)
        ghsa_cves = await ghsa_fetcher.fetch_async("5.10", output_dir)
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
        atom_cves = await atom_fetcher.fetch_async("5.10", output_dir)
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


async def download_missing_cve_patches(
    matrix: CVECoverageMatrix,
    output_base: Path,
    config: KernelConfig,
) -> Dict[str, List[Path]]:
    """Download CVE patches that are missing from stable patches and spec files.
    
    Downloads patches for CVEs that:
    - Are NOT already included in the current stable patch (not built-in)
    - Are NOT already in the spec file
    - Have fix commits available
    - Are applicable to this kernel version
    
    Args:
        matrix: The CVE coverage matrix (already built)
        output_base: Base output directory
        config: Kernel configuration
    
    Returns:
        Dictionary mapping kernel version to list of downloaded patch files
    """
    from scripts.common import download_file
    import aiohttp
    
    console.print("\n[bold blue]Step 5: Downloading missing CVE patches[/bold blue]")
    
    downloaded_patches: Dict[str, List[Path]] = {}
    
    for kv in matrix.kernel_versions:
        patch_dir = output_base / "cve_patches" / kv
        patch_dir.mkdir(parents=True, exist_ok=True)
        downloaded_patches[kv] = []
        
        # Get CVEs that are missing patches (gaps)
        missing_entries = matrix.get_cve_patch_missing(kv)
        
        # Also get CVEs in newer stable patches that we might want to backport
        in_newer_entries = matrix.get_cve_in_newer_stable(kv)
        
        # Combine: these are CVEs not yet in our current version
        eligible_entries = missing_entries + in_newer_entries
        
        if not eligible_entries:
            console.print(f"  {kv}: No missing CVE patches to download")
            continue
        
        # Pre-scan to count already downloaded patches
        already_downloaded = 0
        to_download = []
        for entry in eligible_entries:
            if not entry.fix_commits:
                continue
            commit_sha = entry.fix_commits[0]
            patch_file = patch_dir / f"{commit_sha[:12]}-{entry.cve_id}.patch"
            if patch_file.exists():
                downloaded_patches[kv].append(patch_file)
                already_downloaded += 1
            else:
                to_download.append((entry, commit_sha, patch_file))
        
        console.print(f"  {kv}: {len(eligible_entries)} eligible CVE patches ({len(missing_entries)} missing, {len(in_newer_entries)} in newer stable)")
        if already_downloaded > 0:
            console.print(f"    {already_downloaded} already downloaded, {len(to_download)} to download")
        
        if not to_download:
            console.print(f"    All patches already cached in {patch_dir}")
            continue
        
        downloaded_count = 0
        async with aiohttp.ClientSession() as session:
            for entry, commit_sha, patch_file in to_download:
                patch_url = f"https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id={commit_sha}"
                
                try:
                    async with session.get(
                        patch_url,
                        timeout=aiohttp.ClientTimeout(total=30),
                        headers={"User-Agent": "kernel-backport-tool/1.0"},
                    ) as response:
                        if response.status == 200:
                            content = await response.read()
                            patch_file.write_bytes(content)
                            downloaded_patches[kv].append(patch_file)
                            downloaded_count += 1
                except Exception as e:
                    logger.debug(f"Failed to download patch for {entry.cve_id}: {e}")
        
        console.print(f"    Downloaded {downloaded_count} new patches to {patch_dir}")
    
    return downloaded_patches


async def download_kernel_tarball(
    kernel_version: str,
    photon_version: str,
    output_base: Path,
    config: KernelConfig,
) -> Optional[Path]:
    """Download kernel tarball from kernel.org.
    
    Downloads the tarball for the Photon kernel version (e.g., linux-5.10.247.tar.xz).
    
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
    
    # Download tarball if not cached
    if not tarball_path.exists():
        console.print(f"    Downloading {tarball_name}...")
        try:
            async with aiohttp.ClientSession() as session:
                async with session.get(
                    tarball_url,
                    timeout=aiohttp.ClientTimeout(total=600),
                    headers={"User-Agent": "kernel-backport-tool/1.0"},
                ) as response:
                    if response.status != 200:
                        console.print(f"    [red]Failed to download tarball: HTTP {response.status}[/red]")
                        return None
                    
                    total_size = int(response.headers.get("content-length", 0))
                    downloaded = 0
                    
                    with open(tarball_path, "wb") as f:
                        async for chunk in response.content.iter_chunked(65536):
                            f.write(chunk)
                            downloaded += len(chunk)
                            if total_size > 0:
                                pct = downloaded * 100 // total_size
                                console.print(f"\r    Downloading: {pct}%", end="")
                    console.print(f"\r    Downloaded {tarball_name} ({downloaded // (1024*1024)} MB)")
        except Exception as e:
            console.print(f"    [red]Failed to download tarball: {e}[/red]")
            if tarball_path.exists():
                tarball_path.unlink()
            return None
    else:
        console.print(f"    Tarball cached: {tarball_path}")
    
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


def analyze_patch_against_source(
    patch_path: Path,
    source_dir: Path,
) -> Tuple[bool, str]:
    """Check if a patch is already included in the kernel source.
    
    Uses git apply --check in reverse mode to see if the patch
    can be reversed (meaning it's already applied).
    
    Args:
        patch_path: Path to the patch file
        source_dir: Path to the kernel source directory
    
    Returns:
        Tuple of (is_included, reason)
        - is_included: True if patch appears to be already in source
        - reason: Description of the result
    """
    try:
        # Try to reverse-apply the patch (if it can be reversed, it's already applied)
        result = subprocess.run(
            ["git", "apply", "--check", "--reverse", str(patch_path)],
            cwd=source_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        
        if result.returncode == 0:
            return True, "patch_already_applied"
        
        # Try forward apply to see if it would apply cleanly
        result = subprocess.run(
            ["git", "apply", "--check", str(patch_path)],
            cwd=source_dir,
            capture_output=True,
            text=True,
            timeout=30,
        )
        
        if result.returncode == 0:
            return False, "patch_applicable"
        else:
            # Patch doesn't apply - could be already included or conflicts
            # Check if files exist and have similar content
            return False, "patch_conflicts_or_missing_context"
            
    except subprocess.TimeoutExpired:
        return False, "analysis_timeout"
    except Exception as e:
        return False, f"analysis_error: {e}"


async def analyze_cve_patches_against_source(
    kernel_versions: List[str],
    photon_versions: Dict[str, str],
    cve_patch_dirs: Dict[str, List[Path]],
    output_base: Path,
    config: KernelConfig,
) -> Dict[str, Dict[str, Tuple[bool, str]]]:
    """Analyze CVE patches against kernel source to detect already-included fixes.
    
    Downloads the kernel tarball for each version and checks if CVE patches
    are already included in the source.
    
    Args:
        kernel_versions: List of kernel versions to analyze
        photon_versions: Mapping of kernel version to Photon version
        cve_patch_dirs: Mapping of kernel version to list of CVE patch files
        output_base: Base output directory
        config: Kernel configuration
    
    Returns:
        Dictionary mapping kernel version to dict of {cve_id: (is_included, reason)}
    """
    console.print("\n[bold blue]Step 6: Analyzing CVE patches against kernel source[/bold blue]")
    
    analysis_results: Dict[str, Dict[str, Tuple[bool, str]]] = {}
    
    for kv in kernel_versions:
        analysis_results[kv] = {}
        
        photon_ver = photon_versions.get(kv)
        if not photon_ver:
            console.print(f"  {kv}: [yellow]No Photon version available, skipping[/yellow]")
            continue
        
        patches = cve_patch_dirs.get(kv, [])
        if not patches:
            console.print(f"  {kv}: No CVE patches to analyze")
            continue
        
        console.print(f"  {kv} ({photon_ver}): Analyzing {len(patches)} CVE patches...")
        
        # Download and extract kernel tarball
        source_dir = await download_kernel_tarball(kv, photon_ver, output_base, config)
        if not source_dir:
            console.print(f"    [red]Could not get kernel source, skipping analysis[/red]")
            continue
        
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
        
        # Analyze each patch
        included_count = 0
        applicable_count = 0
        conflict_count = 0
        
        for patch_path in patches:
            # Extract CVE ID from filename
            cve_ids = extract_cve_ids(patch_path.name)
            if not cve_ids:
                continue
            cve_id = cve_ids[0]
            
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
    
    return analysis_results


def update_matrix_with_source_analysis(
    matrix: CVECoverageMatrix,
    analysis_results: Dict[str, Dict[str, Tuple[bool, str]]],
) -> CVECoverageMatrix:
    """Update the CVE matrix with source code analysis results.
    
    CVEs that are found to be already included in the kernel source
    should be marked as CVE_INCLUDED rather than CVE_PATCH_MISSING.
    
    Args:
        matrix: The CVE coverage matrix to update
        analysis_results: Results from analyze_cve_patches_against_source
    
    Returns:
        Updated matrix
    """
    console.print("\n[bold blue]Step 7: Updating matrix with source analysis[/bold blue]")
    
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
                if current_status and current_status.state != CVEPatchState.CVE_INCLUDED:
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


def print_summary(matrix: CVECoverageMatrix):
    """Print matrix summary."""
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
        "--download-patches",
        action="store_true",
        help="Download stable patches from kernel.org (takes time)"
    )
    parser.add_argument(
        "--analyze-source",
        action="store_true",
        help="Download kernel tarball and analyze CVE patches against source code"
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
    if args.analyze_source:
        console.print("[cyan]Source analysis enabled[/cyan]")
    
    # Step 1: Fetch CVEs
    cves = await fetch_all_cves(args.output, config)
    
    # Step 2: Download stable patches (optional)
    patch_dirs = {}
    photon_versions = {}
    if args.download_patches:
        patch_dirs, photon_versions = await download_stable_patches_async(kernel_versions, args.output, config)
    else:
        console.print("\n[yellow]Skipping patch download (use --download-patches to enable)[/yellow]")
        # Still try to get photon versions from remote
        manager = StablePatchManager(config)
        for kv in kernel_versions:
            pv = manager.get_current_photon_version_remote(kv)
            if pv:
                photon_versions[kv] = pv
    
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
    current_step = 6
    
    # Step 6 (initial): Build matrix
    matrix = build_matrix(cves, kernel_versions, repo_dirs, patch_dirs, config, photon_versions, step_num=current_step)
    current_step += 1
    
    # Step 5 (download missing CVE patches) - only if analyze_source is enabled
    cve_patch_dirs: Dict[str, List[Path]] = {}
    if args.analyze_source:
        cve_patch_dirs = await download_missing_cve_patches(matrix, args.output, config)
        
        # Step 6: Analyze CVE patches against kernel source
        analysis_results = await analyze_cve_patches_against_source(
            kernel_versions,
            photon_versions,
            cve_patch_dirs,
            args.output,
            config,
        )
        
        # Step 7: Update matrix with source analysis
        matrix = update_matrix_with_source_analysis(matrix, analysis_results)
        current_step = 8
    
    # Save files
    save_matrix(matrix, args.output, step_num=current_step)
    
    # Print summary
    print_summary(matrix)
    
    console.print("\n[bold green]Done![/bold green]")


if __name__ == "__main__":
    asyncio.run(main())
