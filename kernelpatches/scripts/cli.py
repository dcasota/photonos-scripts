"""
Command-line interface for the kernelpatches solution.
"""

import sys
from datetime import datetime
from pathlib import Path
from typing import Optional

import click
from rich.console import Console
from rich.panel import Panel

from scripts import __version__
from scripts.config import (
    DEFAULT_CONFIG,
    KernelConfig,
    KERNEL_MAPPINGS,
    SUPPORTED_KERNELS,
    validate_kernel_version,
)
from scripts.models import CVESource, PatchSource

console = Console()


def print_banner():
    """Print application banner."""
    console.print(Panel.fit(
        f"[bold blue]Kernel Backport Solution[/bold blue] v{__version__}\n"
        "[dim]Automated kernel patch backporting for Photon OS[/dim]",
        border_style="blue",
    ))


@click.group()
@click.version_option(version=__version__)
@click.option("--verbose", "-v", is_flag=True, help="Enable verbose output")
@click.option("--quiet", "-q", is_flag=True, help="Suppress non-essential output")
@click.pass_context
def main(ctx, verbose: bool, quiet: bool):
    """
    Photon OS Kernel Backport Tool.
    
    Automated tool for backporting CVE patches and stable kernel updates.
    """
    ctx.ensure_object(dict)
    ctx.obj["verbose"] = verbose
    ctx.obj["quiet"] = quiet
    
    if not quiet:
        print_banner()


@main.command()
@click.option("--kernel", "-k", required=True, type=click.Choice(SUPPORTED_KERNELS),
              help="Kernel version to process")
@click.option("--source", "-s", default="cve",
              type=click.Choice(["cve", "stable", "stable-full", "all"]),
              help="Patch source type")
@click.option("--cve-source", default="nvd",
              type=click.Choice(["nvd", "atom", "ghsa", "upstream"]),
              help="CVE source when using --source cve")
@click.option("--month", help="Month to scan (YYYY-MM) for upstream source")
@click.option("--analyze-cves", is_flag=True, help="Analyze CVE redundancy after stable patches")
@click.option("--cve-since", help="Filter CVE analysis to CVEs since date (YYYY-MM)")
@click.option("--detect-gaps", is_flag=True, help="Detect CVEs without stable backports")
@click.option("--gap-report", type=click.Path(), help="Directory for gap detection reports")
@click.option("--resume", is_flag=True, help="Resume from checkpoint")
@click.option("--report-dir", type=click.Path(), help="Directory for analysis reports")
@click.option("--repo-url", default="https://github.com/vmware/photon.git",
              help="Photon repository URL")
@click.option("--branch", help="Git branch to use (auto-detected by default)")
@click.option("--skip-clone", is_flag=True, help="Skip cloning if repo exists")
@click.option("--skip-review", is_flag=True, help="Skip CVE review step")
@click.option("--skip-push", is_flag=True, help="Skip git push and PR creation")
@click.option("--disable-build", is_flag=True, help="Disable RPM build")
@click.option("--limit", type=int, default=0, help="Limit to first N patches")
@click.option("--dry-run", is_flag=True, help="Show what would be done without changes")
@click.pass_context
def backport(
    ctx,
    kernel: str,
    source: str,
    cve_source: str,
    month: Optional[str],
    analyze_cves: bool,
    cve_since: Optional[str],
    detect_gaps: bool,
    gap_report: Optional[str],
    resume: bool,
    report_dir: Optional[str],
    repo_url: str,
    branch: Optional[str],
    skip_clone: bool,
    skip_review: bool,
    skip_push: bool,
    disable_build: bool,
    limit: int,
    dry_run: bool,
):
    """
    Run kernel patch backporting workflow.
    
    Examples:
    
        # CVE patches from NVD (default)
        kernel-backport backport --kernel 6.1
        
        # CVE patches from GitHub Advisory Database
        kernel-backport backport --kernel 6.1 --cve-source ghsa
        
        # Stable patches with CVE analysis
        kernel-backport backport --kernel 5.10 --source stable-full --analyze-cves
        
        # Detect CVE gaps
        kernel-backport backport --kernel 6.1 --detect-gaps
    """
    from scripts.backport import run_backport_workflow
    
    config = KernelConfig.from_env()
    
    if report_dir:
        config.report_dir = Path(report_dir)
    if gap_report:
        config.gap_report_dir = Path(gap_report)
    
    try:
        result = run_backport_workflow(
            kernel_version=kernel,
            patch_source=PatchSource(source),
            cve_source=CVESource(cve_source),
            scan_month=month,
            analyze_cves=analyze_cves,
            cve_since=cve_since,
            detect_gaps=detect_gaps,
            resume=resume,
            repo_url=repo_url,
            branch=branch,
            skip_clone=skip_clone,
            skip_review=skip_review,
            skip_push=skip_push,
            enable_build=not disable_build,
            patch_limit=limit,
            dry_run=dry_run,
            config=config,
        )
        
        if result:
            console.print("[green]Backport workflow completed successfully[/green]")
            sys.exit(0)
        else:
            console.print("[yellow]Backport workflow completed with no changes[/yellow]")
            sys.exit(0)
            
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if ctx.obj.get("verbose"):
            console.print_exception()
        sys.exit(1)


@main.command()
@click.option("--kernel", "-k", type=click.Choice(SUPPORTED_KERNELS),
              help="Filter by kernel version")
@click.option("--output", "-o", type=click.Path(), help="Output directory for reports")
@click.option("--format", "-f", default="all",
              type=click.Choice(["json", "csv", "markdown", "all"]),
              help="Output format")
@click.option("--print-table", is_flag=True, help="Print matrix to console")
@click.option("--max-rows", type=int, default=50, help="Max rows to display")
@click.pass_context
def matrix(
    ctx,
    kernel: Optional[str],
    output: Optional[str],
    format: str,
    print_table: bool,
    max_rows: int,
):
    """
    Generate CVE coverage matrix.
    
    Shows CVE status across kernel versions with CVSS scores and references.
    
    Examples:
    
        # Generate full matrix to files
        kernel-backport matrix --output /tmp/reports
        
        # Print matrix to console
        kernel-backport matrix --print-table
        
        # Generate CSV only
        kernel-backport matrix --format csv --output /tmp
    """
    from scripts.cve_matrix import generate_cve_matrix, print_cve_matrix
    
    config = KernelConfig.from_env()
    
    kernel_versions = [kernel] if kernel else SUPPORTED_KERNELS
    
    # Build repo_dirs map
    repo_dirs = {}
    for kv in kernel_versions:
        repo_dir = config.get_repo_dir(kv)
        if repo_dir and repo_dir.exists():
            repo_dirs[kv] = repo_dir
    
    try:
        if print_table:
            print_cve_matrix(kernel_versions, repo_dirs, None, max_rows, config)
        else:
            output_dir = Path(output) if output else config.report_dir
            matrix = generate_cve_matrix(
                output_dir,
                kernel_versions,
                repo_dirs,
                None,  # patch_dirs
                format,
                config,
            )
            console.print(f"[green]Generated CVE matrix with {matrix.total_cves} entries[/green]")
            
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if ctx.obj.get("verbose"):
            console.print_exception()
        sys.exit(1)


@main.command()
@click.option("--kernel", "-k", required=True, type=click.Choice(SUPPORTED_KERNELS),
              help="Kernel version to analyze")
@click.option("--cve-list", type=click.Path(exists=True),
              help="File with CVE IDs (one per line), or omit to analyze all kernel.org CVEs")
@click.option("--output", "-o", type=click.Path(), help="Output directory for reports")
@click.pass_context
def gaps(ctx, kernel: str, cve_list: Optional[str], output: Optional[str]):
    """
    Detect CVE backport gaps using local NVD feed cache.
    
    Downloads NVD feeds once, then analyzes all CVEs locally (fast, no per-CVE API calls).
    Identifies CVEs that affect the target kernel but have no official stable backport.
    
    Examples:
    
        # Analyze all kernel.org CVEs from NVD feeds
        kernel-backport gaps --kernel 6.1
        
        # Analyze specific CVEs from a file
        kernel-backport gaps --kernel 5.10 --cve-list /tmp/cves.txt
    """
    from scripts.cve_gap_detection import run_gap_detection
    from scripts.common import get_photon_kernel_version
    
    config = KernelConfig.from_env()
    
    report_dir = Path(output) if output else config.gap_report_dir
    
    # Get CVE list (None means analyze all kernel.org CVEs from feeds)
    cve_ids = None
    if cve_list:
        with open(cve_list) as f:
            cve_ids = [line.strip() for line in f if line.strip().startswith("CVE-")]
        console.print(f"Analyzing {len(cve_ids)} CVEs from file for kernel {kernel}...")
    else:
        console.print(f"Analyzing all kernel.org CVEs from NVD feeds for kernel {kernel}...")
    
    # Progress callback
    def progress(processed, total, cve_id):
        if processed % 500 == 0 or processed == total:
            console.print(f"  [{processed}/{total}] Processing...")
    
    # Get current version
    repo_dir = config.get_repo_dir(kernel)
    current_version = "unknown"
    if repo_dir and repo_dir.exists():
        current_version = get_photon_kernel_version(kernel, repo_dir) or "unknown"
    
    try:
        report_path = run_gap_detection(
            kernel,
            current_version,
            cve_ids,
            report_dir,
            config,
            progress_callback=progress,
        )
        console.print(f"[green]Gap detection complete. Report: {report_path}[/green]")
        
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if ctx.obj.get("verbose"):
            console.print_exception()
        sys.exit(1)


@main.command()
@click.option("--kernel", "-k", required=True, type=click.Choice(SUPPORTED_KERNELS),
              help="Kernel version")
@click.pass_context
def status(ctx, kernel: str):
    """
    Check kernel status and available updates.
    
    Shows current Photon kernel version and latest stable version.
    """
    from scripts.stable_patches import StablePatchManager
    
    config = KernelConfig.from_env()
    manager = StablePatchManager(config)
    
    repo_dir = config.get_repo_dir(kernel)
    
    console.print(f"\n[bold]Kernel {kernel} Status[/bold]\n")
    
    # Current version
    if repo_dir and repo_dir.exists():
        current = manager.get_current_photon_version(kernel, repo_dir)
        console.print(f"  Photon version: [cyan]{current or 'unknown'}[/cyan]")
    else:
        console.print(f"  Photon version: [yellow]Repository not cloned[/yellow]")
        current = None
    
    # Latest stable
    latest = manager.get_latest_stable_version(kernel)
    console.print(f"  Latest stable:  [cyan]{latest or 'unknown'}[/cyan]")
    
    # Status
    if current and latest:
        from scripts.common import version_less_than
        
        if version_less_than(current, latest):
            behind = manager.get_versions_behind(current, latest)
            console.print(f"\n  [yellow]⚠ Update available: {behind} version(s) behind[/yellow]")
        else:
            console.print(f"\n  [green]✓ Up to date[/green]")
    
    # Mapping info
    mapping = KERNEL_MAPPINGS.get(kernel)
    if mapping:
        console.print(f"\n  Branch: {mapping.branch.value}")
        console.print(f"  Spec dir: {mapping.spec_dir}")
        console.print(f"  Spec files: {', '.join(mapping.spec_files)}")


@main.command()
@click.option("--kernel", "-k", required=True, type=click.Choice(SUPPORTED_KERNELS),
              help="Kernel version")
@click.option("--output", "-o", type=click.Path(), help="Output directory")
@click.pass_context
def download(ctx, kernel: str, output: Optional[str]):
    """
    Download stable patches from kernel.org.
    
    Downloads incremental stable patches for the specified kernel version.
    """
    from scripts.stable_patches import find_and_download_stable_patches
    
    config = KernelConfig.from_env()
    output_dir = Path(output) if output else Path(f"/tmp/stable_patches_{kernel}")
    
    try:
        patches = find_and_download_stable_patches(kernel, output_dir, config)
        
        if patches:
            console.print(f"[green]Downloaded {len(patches)} patches to {output_dir}[/green]")
        else:
            console.print("[yellow]No new patches to download[/yellow]")
            
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if ctx.obj.get("verbose"):
            console.print_exception()
        sys.exit(1)


@main.command()
@click.option("--kernel", "-k", required=True, type=click.Choice(SUPPORTED_KERNELS),
              help="Kernel version")
@click.option("--output", "-o", type=click.Path(), help="Output directory for logs")
@click.option("--canister", type=int, default=0, help="canister_build value (0 or 1)")
@click.option("--acvp", type=int, default=0, help="acvp_build value (0 or 1)")
@click.option("--all-permutations", is_flag=True, help="Build all canister/acvp combinations")
@click.pass_context
def build(
    ctx,
    kernel: str,
    output: Optional[str],
    canister: int,
    acvp: int,
    all_permutations: bool,
):
    """
    Build kernel RPMs.
    
    Build kernel packages from spec files.
    """
    from scripts.build import KernelBuilder
    
    config = KernelConfig.from_env()
    builder = KernelBuilder(config)
    
    repo_dir = config.get_repo_dir(kernel)
    if not repo_dir or not repo_dir.exists():
        console.print(f"[red]Repository not found for kernel {kernel}[/red]")
        sys.exit(1)
    
    output_dir = Path(output) if output else Path(f"/tmp/build_{kernel}")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    # Verify dependencies
    deps_ok, missing = builder.verify_build_deps()
    if not deps_ok:
        console.print(f"[red]Missing dependencies: {', '.join(missing)}[/red]")
        sys.exit(1)
    
    try:
        if all_permutations:
            results = builder.build_all_permutations(kernel, repo_dir, output_dir)
        else:
            results = builder.build_all_specs(kernel, repo_dir, output_dir, canister, acvp)
        
        success = sum(1 for r in results if r.success)
        failed = len(results) - success
        
        console.print(f"\n[bold]Build Results:[/bold] {success} succeeded, {failed} failed")
        
        for r in results:
            status = "[green]✓[/green]" if r.success else "[red]✗[/red]"
            console.print(f"  {status} {Path(r.spec_file).name}: {r.version}-{r.release}")
            if not r.success and r.error_message:
                console.print(f"      Error: {r.error_message}")
        
        if failed > 0:
            sys.exit(1)
            
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if ctx.obj.get("verbose"):
            console.print_exception()
        sys.exit(1)


@main.group()
def cve():
    """CVE-related commands."""
    pass


@cve.command(name="fetch")
@click.option("--source", "-s", default="nvd",
              type=click.Choice(["nvd", "atom", "ghsa", "upstream"]),
              help="CVE source")
@click.option("--kernel", "-k", required=True, type=click.Choice(SUPPORTED_KERNELS),
              help="Kernel version")
@click.option("--output", "-o", type=click.Path(), help="Output directory")
@click.pass_context
def cve_fetch(ctx, source: str, kernel: str, output: Optional[str]):
    """
    Fetch CVEs from specified source.
    """
    from scripts.cve_sources import fetch_cves_sync
    
    output_dir = Path(output) if output else Path(f"/tmp/cve_fetch_{kernel}")
    output_dir.mkdir(parents=True, exist_ok=True)
    
    try:
        cves = fetch_cves_sync(CVESource(source), kernel, output_dir)
        
        console.print(f"\n[green]Fetched {len(cves)} CVEs from {source}[/green]")
        
        # Show top 10
        if cves:
            console.print("\n[bold]Top CVEs by CVSS:[/bold]")
            sorted_cves = sorted(cves, key=lambda c: c.cvss_score, reverse=True)[:10]
            for cve in sorted_cves:
                console.print(f"  {cve.cve_id}: {cve.cvss_score:.1f} ({cve.severity.value})")
                
    except Exception as e:
        console.print(f"[red]Error: {e}[/red]")
        if ctx.obj.get("verbose"):
            console.print_exception()
        sys.exit(1)


@main.command()
@click.option("--install-dir", default="/opt/kernel-backport",
              help="Installation directory")
@click.option("--log-dir", default="/var/log/kernel-backport",
              help="Log directory")
@click.option("--cron", default="0 */2 * * *",
              help="Cron schedule (default: every 2 hours)")
@click.option("--kernels", default=",".join(SUPPORTED_KERNELS),
              help="Comma-separated kernel versions")
@click.option("--no-cron", is_flag=True, help="Skip cron job installation")
@click.option("--uninstall", is_flag=True, help="Remove installation")
@click.pass_context
def install(ctx, install_dir: str, log_dir: str, cron: str, kernels: str, no_cron: bool, uninstall: bool):
    """
    Install the kernel backport solution with optional cron scheduling.
    
    Sets up automated kernel backporting with configurable schedule.
    """
    from scripts.installer import (
        create_config_file,
        create_cron_wrapper,
        create_status_script,
        create_run_now_script,
        install_cron_job,
        uninstall_cron_job,
    )
    import shutil
    import os
    
    install_path = Path(install_dir)
    log_path = Path(log_dir)
    
    if uninstall:
        console.print("[bold]Uninstalling kernel backport solution...[/bold]")
        if uninstall_cron_job():
            console.print("  Removed cron job")
        if install_path.exists():
            shutil.rmtree(install_path)
            console.print(f"  Removed {install_path}")
        console.print("[green]Uninstallation complete.[/green]")
        return
    
    if os.geteuid() != 0:
        console.print("[yellow]Warning: Not running as root. Some operations may fail.[/yellow]")
    
    console.print("[bold]Installing kernel backport solution...[/bold]")
    console.print(f"  Install directory: {install_path}")
    console.print(f"  Log directory: {log_path}")
    console.print(f"  Kernels: {kernels}")
    
    # Create directories
    install_path.mkdir(parents=True, exist_ok=True)
    log_path.mkdir(parents=True, exist_ok=True)
    (log_path / "reports").mkdir(exist_ok=True)
    (log_path / "gaps").mkdir(exist_ok=True)
    
    # Copy package
    source_dir = Path(__file__).parent
    dest_package = install_path / "scripts"
    if dest_package.exists():
        shutil.rmtree(dest_package)
    shutil.copytree(source_dir, dest_package)
    console.print(f"  Copied package to: {dest_package}")
    
    # Create scripts
    create_config_file(install_path, log_path, kernels)
    create_cron_wrapper(install_path, log_path)
    create_status_script(install_path, log_path)
    create_run_now_script(install_path)
    
    if not no_cron:
        if install_cron_job(install_path, cron):
            console.print(f"  Cron job installed: {cron}")
    
    console.print("\n[green bold]Installation Complete![/green bold]")
    console.print(f"  Check status:  python3 {install_path}/status.py")
    console.print(f"  Run manually:  {install_path}/run-now.sh")


@main.command(name="full-matrix")
@click.option("--output", "-o", type=click.Path(), default="/var/log/cve_matrix",
              help="Output directory for matrix files")
@click.option("--download-patches", is_flag=True,
              help="Download stable patches from kernel.org")
@click.option("--kernels", default=",".join(SUPPORTED_KERNELS),
              help="Comma-separated kernel versions")
@click.option("--repo-base", type=click.Path(exists=True),
              help="Base directory containing Photon repo clones")
@click.pass_context
def full_matrix(ctx, output: str, download_patches: bool, kernels: str, repo_base: Optional[str]):
    """
    Generate comprehensive CVE coverage matrix with all data.
    
    This command:
    1. Downloads NVD feeds and fetches all kernel CVEs
    2. Optionally downloads stable patches from kernel.org
    3. Builds complete coverage matrix with five-state tracking
    4. Exports to JSON, CSV, and Markdown formats
    """
    import asyncio
    from scripts.generate_full_matrix import (
        fetch_all_cves,
        download_stable_patches_async,
        build_matrix,
        save_matrix,
        print_summary,
    )
    
    kernel_versions = [k.strip() for k in kernels.split(",")]
    output_dir = Path(output)
    config = KernelConfig.from_env()
    
    console.print("[bold]Comprehensive CVE Coverage Matrix Generator[/bold]")
    console.print(f"Kernels: {', '.join(kernel_versions)}")
    console.print(f"Output: {output_dir}")
    
    async def run():
        # Fetch CVEs
        cves = await fetch_all_cves(output_dir, config)
        
        # Download patches
        patch_dirs = {}
        if download_patches:
            patch_dirs = await download_stable_patches_async(kernel_versions, output_dir, config)
        
        # Build repo_dirs
        repo_dirs = {}
        if repo_base:
            base = Path(repo_base)
            mapping = {"5.10": "4.0", "6.1": "5.0", "6.12": "common"}
            for kv in kernel_versions:
                branch = mapping.get(kv, kv)
                repo_path = base / branch
                if repo_path.exists():
                    repo_dirs[kv] = repo_path
        
        # Build and save matrix
        matrix = build_matrix(cves, kernel_versions, repo_dirs, patch_dirs, config)
        save_matrix(matrix, output_dir)
        print_summary(matrix)
    
    asyncio.run(run())
    console.print("\n[bold green]Done![/bold green]")


if __name__ == "__main__":
    main()
