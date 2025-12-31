#!/usr/bin/env python3
"""
Generate a comprehensive CVE coverage matrix for all supported kernels.

This script:
1. Downloads stable patches from kernel.org for each kernel version
2. Fetches CVEs from all sources (NVD with yearly feeds)
3. Builds a complete coverage matrix with patch-level analysis
4. Exports to JSON, CSV, and Markdown formats

Usage:
    python scripts/generate_full_matrix.py --output /tmp/full_matrix
    python scripts/generate_full_matrix.py --output /tmp/full_matrix --download-patches
"""

import argparse
import asyncio
import sys
from datetime import datetime
from pathlib import Path

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent.parent))

from scripts.config import DEFAULT_CONFIG, SUPPORTED_KERNELS, KernelConfig
from scripts.cve_sources import NVDFetcher, GHSAFetcher, AtomFetcher
from scripts.cve_matrix import CVEMatrixBuilder, CVECoverageMatrix
from scripts.stable_patches import StablePatchManager
from scripts.common import logger

from rich.console import Console
from rich.progress import Progress, SpinnerColumn, TextColumn, BarColumn, TaskProgressColumn

console = Console()


async def fetch_all_cves(output_dir: Path, config: KernelConfig) -> list:
    """Fetch CVEs from all sources and merge them."""
    all_cves = {}
    
    console.print("\n[bold blue]Step 1: Fetching CVEs from all sources[/bold blue]")
    
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
) -> dict:
    """Download stable patches for all kernel versions."""
    console.print("\n[bold blue]Step 2: Downloading stable patches from kernel.org[/bold blue]")
    
    patch_dirs = {}
    manager = StablePatchManager(config)
    
    for kv in kernel_versions:
        console.print(f"  Downloading patches for kernel {kv}...")
        patch_dir = output_base / "patches" / kv
        patch_dir.mkdir(parents=True, exist_ok=True)
        
        try:
            # Get latest stable version
            latest = manager.get_latest_stable_version(kv)
            if latest:
                console.print(f"    Latest stable: {latest}")
                
                # Download all patches from .1 to latest (use async version directly)
                patches = await manager.download_patches(
                    kv, patch_dir,
                    start_subver=1,  # Start from .1
                    end_subver=None,  # Download all available
                )
                console.print(f"    Downloaded {len(patches)} patches")
                patch_dirs[kv] = patch_dir / "stable_patches"
            else:
                console.print(f"    [yellow]Could not determine latest version[/yellow]")
        except Exception as e:
            console.print(f"    [red]Failed: {e}[/red]")
    
    return patch_dirs


def build_matrix(
    cves: list,
    kernel_versions: list,
    repo_dirs: dict,
    patch_dirs: dict,
    config: KernelConfig,
) -> CVECoverageMatrix:
    """Build the CVE coverage matrix."""
    console.print("\n[bold blue]Step 3: Building CVE coverage matrix[/bold blue]")
    
    builder = CVEMatrixBuilder(kernel_versions, config)
    
    console.print(f"  Kernel versions: {', '.join(kernel_versions)}")
    console.print(f"  Total CVEs: {len(cves)}")
    console.print(f"  Repo dirs: {list(repo_dirs.keys()) or 'none'}")
    console.print(f"  Patch dirs: {list(patch_dirs.keys()) or 'none'}")
    
    matrix = builder.build_from_cves(cves, repo_dirs, patch_dirs)
    
    console.print(f"  [green]Matrix built with {matrix.total_cves} entries[/green]")
    
    return matrix


def save_matrix(matrix: CVECoverageMatrix, output_dir: Path):
    """Save matrix in all formats."""
    console.print("\n[bold blue]Step 4: Saving matrix files[/bold blue]")
    
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
    cves = await fetch_all_cves(args.output, config)
    
    # Step 2: Download stable patches (optional)
    patch_dirs = {}
    if args.download_patches:
        patch_dirs = await download_stable_patches_async(kernel_versions, args.output, config)
    else:
        console.print("\n[yellow]Skipping patch download (use --download-patches to enable)[/yellow]")
    
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
    
    # Step 3: Build matrix
    matrix = build_matrix(cves, kernel_versions, repo_dirs, patch_dirs, config)
    
    # Step 4: Save files
    save_matrix(matrix, args.output)
    
    # Print summary
    print_summary(matrix)
    
    console.print("\n[bold green]Done![/bold green]")


if __name__ == "__main__":
    asyncio.run(main())
