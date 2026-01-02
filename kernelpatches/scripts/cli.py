"""
Command-line interface for the kernelpatches solution.
"""

import sys
from datetime import datetime
from pathlib import Path
from typing import List, Optional

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
        f"[bold blue]Kernel Backport Tool[/bold blue] v{__version__}\n"
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
@click.option("--repo-base", type=click.Path(),
              help="Base directory for cloning Photon repos (default: /root/photonos-scripts/kernelpatches)")
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
    repo_base: Optional[str],
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
            repo_base=Path(repo_base) if repo_base else None,
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


def parse_kernel_arg(kernel: str) -> List[str]:
    """Parse kernel argument: 'all', single value, or comma-separated list."""
    if kernel.lower() == "all":
        return list(SUPPORTED_KERNELS)
    return [k.strip() for k in kernel.split(",")]


@main.command()
@click.option("--output", "-o", type=click.Path(), default="/var/log/photon-kernel-backport/cve_matrix",
              help="Output directory for matrix files")
@click.option("--kernel", "-k", default="all",
              help="Kernel version(s): 5.10, 6.1, 6.12, comma-separated list, or 'all'")
@click.option("--repo-base", type=click.Path(),
              help="Base directory for cloning Photon repos (default: /root/photonos-scripts/kernelpatches)")
@click.option("--repo-url", default="https://github.com/vmware/photon.git",
              help="Photon repository URL")
@click.option("--skip-clone", is_flag=True, help="Skip cloning repos (use existing or fail)")
@click.option("--update-repos", is_flag=True, help="Force update existing repos")
@click.pass_context
def matrix(ctx, output: str, kernel: str, repo_base: Optional[str], repo_url: str, skip_clone: bool, update_repos: bool):
    """
    Generate comprehensive CVE coverage matrix.
    
    This command:
    1. Clones/updates Photon OS repos for the specified kernel(s)
    2. Downloads NVD feeds and fetches all kernel CVEs
    3. Downloads stable patches from kernel.org (from current Photon version to latest)
    4. Builds complete coverage matrix with five-state tracking
    5. Collects existing CVE patches
    6. Analyzes CVE patches against kernel source
    7. Exports to JSON, CSV, and Markdown formats
    
    Examples:
    
        # Generate matrix for all kernels (auto-clones repos)
        photon-kernel-backport matrix
        
        # Specific kernel
        photon-kernel-backport matrix --kernel 5.10
        
        # Multiple kernels
        photon-kernel-backport matrix --kernel 5.10,6.1
        
        # Custom output directory
        photon-kernel-backport matrix --output /tmp/cve_matrix
        
        # Custom repo location and URL
        photon-kernel-backport matrix --kernel 5.10 --repo-base /tmp/repos --repo-url https://github.com/myorg/photon.git
        
        # Update existing repos before generating matrix
        photon-kernel-backport matrix --kernel 5.10 --update-repos
    """
    import asyncio
    from scripts.generate_full_matrix import (
        fetch_all_cves,
        download_stable_patches_async,
        collect_existing_cve_patches,
        download_cve_patches,
        download_kernel_tarballs_for_analysis,
        analyze_cve_patches_against_source,
        update_matrix_with_source_analysis,
        build_matrix,
        save_matrix,
        print_summary,
    )
    from scripts.common import ensure_photon_repos_for_kernels
    
    kernel_versions = parse_kernel_arg(kernel)
    output_dir = Path(output)
    config = KernelConfig.from_env()
    
    console.print("[bold]Comprehensive CVE Coverage Matrix Generator[/bold]")
    console.print(f"Kernels: {', '.join(kernel_versions)}")
    console.print(f"Output: {output_dir}")
    if repo_base:
        console.print(f"Repo base: {repo_base}")
    if repo_url != "https://github.com/vmware/photon.git":
        console.print(f"Repo URL: {repo_url}")
    
    # Step 1: Ensure repos are cloned and show status
    from scripts.stable_patches import StablePatchManager
    
    repo_dirs = {}
    if not skip_clone:
        console.print(f"\n[bold blue]Step 1: Ensuring Photon repositories are cloned[/bold blue]")
        repo_dirs = ensure_photon_repos_for_kernels(
            kernel_versions,
            config=config,
            repo_url=repo_url,
            repo_base=Path(repo_base) if repo_base else None,
            force_update=update_repos,
        )
        if not repo_dirs:
            console.print("[red]Failed to clone any repositories[/red]")
            sys.exit(1)
    else:
        # Skip clone mode: try to use existing repos
        console.print(f"\n[bold blue]Step 1: Checking existing Photon repositories[/bold blue]")
        base = Path(repo_base) if repo_base else None
        mapping = {"5.10": "4.0", "6.1": "5.0", "6.12": "common"}
        for kv in kernel_versions:
            if base:
                repo_dir = base / mapping.get(kv, kv)
            else:
                repo_dir = config.get_repo_dir(kv)
            if repo_dir and repo_dir.exists():
                repo_dirs[kv] = repo_dir
                console.print(f"  Found existing repo for {kv}: {repo_dir}")
            else:
                console.print(f"  [red]No repo found for {kv}[/red]")
    
    # Show kernel status (like 'status' command)
    manager = StablePatchManager(config)
    console.print(f"\n[bold blue]Step 2: Checking kernel versions[/bold blue]")
    for kv in kernel_versions:
        if kv in repo_dirs:
            current = manager.get_current_photon_version(kv, repo_dirs[kv])
            latest = manager.get_latest_stable_version(kv)
            if current and latest:
                from scripts.common import version_less_than
                if version_less_than(current, latest):
                    behind = manager.get_versions_behind(current, latest)
                    console.print(f"  {kv}: Photon [cyan]{current}[/cyan] -> Latest stable [cyan]{latest}[/cyan] [yellow]({behind} versions behind)[/yellow]")
                else:
                    console.print(f"  {kv}: Photon [cyan]{current}[/cyan] [green](up to date)[/green]")
            elif current:
                console.print(f"  {kv}: Photon [cyan]{current}[/cyan] (could not check latest)")
            else:
                console.print(f"  {kv}: [yellow]Could not determine version[/yellow]")
    
    async def run():
        # Fetch CVEs (Step 3)
        cves = await fetch_all_cves(output_dir, config, kernel_versions[0])
        
        # Download stable patches (Step 4 - only from current Photon version to latest)
        patch_dirs, photon_versions = await download_stable_patches_async(
            kernel_versions, output_dir, config, repo_dirs
        )
        
        # Build initial matrix (Step 5) to determine which CVE patches are missing
        current_step = 5
        mat = build_matrix(cves, kernel_versions, repo_dirs, patch_dirs, config, photon_versions, step_num=current_step)
        current_step += 1
        
        # Download CVE patches (Step 6)
        cve_patch_dirs = await download_cve_patches(mat, output_dir, config, step_num=current_step)
        current_step += 1
        
        # Download kernel tarballs for source analysis (Step 7)
        from rich.console import Console
        console = Console()
        console.print(f"\n[bold blue]Step {current_step}: Downloading kernel tarballs for source analysis[/bold blue]")
        source_dirs = await download_kernel_tarballs_for_analysis(
            kernel_versions,
            photon_versions,
            output_dir,
            config,
        )
        current_step += 1
        
        # Build CVE map for CPE lookup (no API calls needed - data from NVD feeds)
        cve_map = {cve.cve_id: cve for cve in cves}
        
        # Analyze CVE patches against kernel source (Step 8)
        analysis_results = analyze_cve_patches_against_source(
            kernel_versions,
            photon_versions,
            cve_patch_dirs,
            output_dir,
            config,
            step_num=current_step,
            source_dirs=source_dirs,
            cve_map=cve_map,
        )
        current_step += 1
        
        # Update matrix with source analysis (Step 8)
        mat = update_matrix_with_source_analysis(mat, analysis_results, step_num=current_step)
        current_step += 1
        
        # Save matrix and print summary
        save_matrix(mat, output_dir, step_num=current_step)
        print_summary(mat, analysis_results)
    
    asyncio.run(run())
    console.print("\n[bold green]Done![/bold green]")


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
@click.option("--output", "-o", type=click.Path(), help="Output directory for logs (auto-generated if not specified)")
@click.option("--specs", "-s", default=None,
              help="Comma-separated spec files to build (e.g., 'linux.spec,linux-esx.spec'). If not specified, builds all.")
@click.option("--canister", type=int, default=0, help="canister_build value (0 or 1)")
@click.option("--acvp", type=int, default=0, help="acvp_build value (0 or 1)")
@click.option("--all-permutations", is_flag=True, help="Build all canister/acvp combinations")
@click.option("--skip-deps", is_flag=True, help="Skip installing build dependencies")
@click.pass_context
def build(
    ctx,
    kernel: str,
    output: Optional[str],
    specs: Optional[str],
    canister: int,
    acvp: int,
    all_permutations: bool,
    skip_deps: bool,
):
    """
    Build kernel RPMs using SRPM from packages.broadcom.com.
    
    This command downloads the official SRPM, extracts all sources,
    and builds the kernel RPMs. Build dependencies are automatically
    installed via tdnf unless --skip-deps is specified.
    
    Output RPMs are placed in /usr/local/src/RPMS/x86_64/
    
    Examples:
    
        # Build all kernel specs (linux.spec, linux-esx.spec, linux-rt.spec)
        photon-kernel-backport build --kernel 5.10
        
        # Build only linux-esx kernel
        photon-kernel-backport build --kernel 5.10 --specs linux-esx.spec
        
        # Build linux and linux-esx
        photon-kernel-backport build --kernel 5.10 --specs "linux.spec,linux-esx.spec"
        
        # Build all canister/acvp permutations
        photon-kernel-backport build --kernel 5.10 --all-permutations
    """
    from scripts.build import KernelBuilder
    
    config = KernelConfig.from_env()
    builder = KernelBuilder(config)
    
    # Verify basic dependencies
    deps_ok, missing = builder.verify_build_deps()
    if not deps_ok:
        console.print(f"[red]Missing dependencies: {', '.join(missing)}[/red]")
        sys.exit(1)
    
    # Parse spec filter
    spec_filter = None
    if specs:
        spec_filter = [s.strip() for s in specs.split(",")]
    
    try:
        if all_permutations:
            console.print(f"[bold]Building kernel {kernel} - all canister/acvp permutations[/bold]")
            # For permutations, use local build approach
            repo_dir = config.get_repo_dir(kernel)
            if not repo_dir or not repo_dir.exists():
                console.print(f"[red]Repository not found for kernel {kernel}[/red]")
                sys.exit(1)
            output_dir = Path(output) if output else builder.get_build_output_dir(kernel, repo_dir)
            results = builder.build_all_permutations(kernel, repo_dir, output_dir)
        else:
            if spec_filter:
                console.print(f"[bold]Building kernel {kernel} from SRPM: {', '.join(spec_filter)}[/bold]")
            else:
                console.print(f"[bold]Building all kernel specs for {kernel} from SRPM[/bold]")
            
            results = builder.build_all_from_srpm(
                kernel_version=kernel,
                canister=canister,
                acvp=acvp,
                install_deps=not skip_deps,
                spec_filter=spec_filter,
            )
        
        success = sum(1 for r in results if r.success)
        failed = len(results) - success
        
        console.print(f"\n[bold]Build Results:[/bold] {success} succeeded, {failed} failed")
        
        for r in results:
            status = "[green]OK[/green]" if r.success else "[red]FAIL[/red]"
            console.print(f"  {status} {Path(r.spec_file).name}: {r.version}-{r.release}")
            if r.duration_seconds:
                console.print(f"       Duration: {r.duration_seconds}s")
            if not r.success and r.error_message:
                console.print(f"       Error: {r.error_message}")
            if r.log_file:
                console.print(f"       Log: {r.log_file}")
        
        console.print(f"\n  RPMs: /usr/local/src/RPMS/x86_64/")
        
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
@click.option("--kernel", "-k", default="all",
              help="Kernel version(s): 5.10, 6.1, 6.12, comma-separated list, or 'all'")
@click.option("--no-cron", is_flag=True, help="Skip cron job installation")
@click.option("--uninstall", is_flag=True, help="Remove installation")
@click.pass_context
def install(ctx, install_dir: str, log_dir: str, cron: str, kernel: str, no_cron: bool, uninstall: bool):
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
    
    kernel_versions = parse_kernel_arg(kernel)
    kernels_str = ",".join(kernel_versions)
    
    console.print("[bold]Installing kernel backport solution...[/bold]")
    console.print(f"  Install directory: {install_path}")
    console.print(f"  Log directory: {log_path}")
    console.print(f"  Kernels: {kernels_str}")
    
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
    create_config_file(install_path, log_path, kernels_str)
    create_cron_wrapper(install_path, log_path)
    create_status_script(install_path, log_path)
    create_run_now_script(install_path)
    
    if not no_cron:
        if install_cron_job(install_path, cron):
            console.print(f"  Cron job installed: {cron}")
    
    console.print("\n[green bold]Installation Complete![/green bold]")
    console.print(f"  Check status:  python3 {install_path}/status.py")
    console.print(f"  Run manually:  {install_path}/run-now.sh")


@main.command(name="cve-build-workflow")
@click.option("--kernel", "-k", default="all",
              help="Kernel version(s): 5.10, 6.1, 6.12, comma-separated list, or 'all'")
@click.option("--output", "-o", type=click.Path(), help="Output directory for reports")
@click.option("--repo-base", type=click.Path(),
              help="Base directory for cloning Photon repos (default: /root/photonos-scripts/kernelpatches)")
@click.option("--repo-url", default="https://github.com/vmware/photon.git",
              help="Photon repository URL")
@click.option("--no-cleanup", is_flag=True, help="Skip cleanup of previous run artifacts")
@click.option("--phase1-only", is_flag=True, help="Only run phase 1 (current kernel)")
@click.option("--specs", "-s", default="linux-esx.spec",
              help="Comma-separated spec files to build (default: linux-esx.spec)")
@click.pass_context
def cve_build_workflow(
    ctx,
    kernel: str,
    output: Optional[str],
    repo_base: Optional[str],
    repo_url: str,
    no_cleanup: bool,
    phase1_only: bool,
    specs: str,
):
    """
    Run two-phase CVE coverage build workflow.
    
    Phase 1: Build current kernel version with CVE patches
    Phase 2: Build latest stable kernel with CVE patches
    
    Generates comprehensive reports with CVE coverage matrix,
    patch integration status, and build results.
    
    Examples:
    
        # Full workflow for all kernels
        photon-kernel-backport cve-build-workflow
        
        # Single kernel
        photon-kernel-backport cve-build-workflow --kernel 6.12
        
        # Multiple kernels
        photon-kernel-backport cve-build-workflow --kernel 5.10,6.1
        
        # Phase 1 only (current kernel)
        photon-kernel-backport cve-build-workflow --kernel 6.12 --phase1-only
        
        # Custom output directory
        photon-kernel-backport cve-build-workflow -k 6.12 -o /tmp/cve_report
        
        # Build multiple specs
        photon-kernel-backport cve-build-workflow -k 6.12 --specs "linux.spec,linux-esx.spec"
    """
    from scripts.cve_coverage_build_workflow import run_cve_build_workflow
    
    kernel_versions = parse_kernel_arg(kernel)
    spec_filter = [s.strip() for s in specs.split(",")]
    
    all_success = True
    for kv in kernel_versions:
        console.print(f"\n[bold cyan]{'='*60}[/bold cyan]")
        console.print(f"[bold cyan]Processing kernel {kv}[/bold cyan]")
        console.print(f"[bold cyan]{'='*60}[/bold cyan]\n")
        
        # Determine output directory for this kernel
        if output:
            kv_output = f"{output}_{kv}" if len(kernel_versions) > 1 else output
        else:
            kv_output = None
        
        try:
            report = run_cve_build_workflow(
                kernel_version=kv,
                cleanup=not no_cleanup,
                output_dir=kv_output,
                repo_base=Path(repo_base) if repo_base else None,
                repo_url=repo_url,
                phase1_only=phase1_only,
                spec_filter=spec_filter,
            )
            
            # Check build success
            if report.phases:
                phase_success = all(p.build.success for p in report.phases if p.build.spec_file)
                if not phase_success:
                    all_success = False
            
        except Exception as e:
            console.print(f"[red]Error processing kernel {kv}: {e}[/red]")
            if ctx.obj.get("verbose"):
                console.print_exception()
            all_success = False
    
    # Summary for multiple kernels
    if len(kernel_versions) > 1:
        console.print(f"\n[bold]{'='*60}[/bold]")
        console.print(f"[bold]Workflow Summary[/bold]")
        console.print(f"[bold]{'='*60}[/bold]")
        console.print(f"Kernels processed: {', '.join(kernel_versions)}")
        if all_success:
            console.print("[green]All builds completed successfully[/green]")
        else:
            console.print("[yellow]Some builds failed - check individual reports[/yellow]")
    
    if not all_success:
        sys.exit(1)


if __name__ == "__main__":
    main()
