"""
CVE Coverage Build Workflow - Two-phase kernel build with comprehensive reporting.

This script performs:
Phase 1: Build current kernel (e.g., 6.12.60) with CVE patches
Phase 2: Build latest stable kernel (e.g., 6.12.63) with CVE patches

Each phase generates CVE coverage matrix, downloads missing patches,
builds RPMs, and produces comprehensive reports.
"""

import asyncio
import json
import shutil
import uuid
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

from rich.console import Console
from rich.panel import Panel
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.table import Table

from scripts.common import (
    download_file,
    logger,
    run_command,
    safe_remove_dir,
    setup_logging,
)
from scripts.config import (
    DEFAULT_CONFIG,
    KERNEL_MAPPINGS,
    KernelConfig,
    get_kernel_org_url,
)
from scripts.build import KernelBuilder
from scripts.cve_gap_detection import GapDetector, NVDFeedCache
from scripts.cve_matrix import CVEMatrixBuilder, CVEPatchState
from scripts.cve_sources import NVDFetcher
from scripts.models import BuildResult, CVE, Severity
from scripts.spec_file import SpecFile
from scripts.stable_patches import StablePatchManager

console = Console()


@dataclass
class CVECoverageStats:
    """Statistics for CVE coverage."""
    total_cves: int = 0
    cve_included: int = 0
    cve_in_newer_stable: int = 0
    cve_patch_available: int = 0
    cve_patch_missing: int = 0
    cve_not_applicable: int = 0
    
    @property
    def coverage_percent(self) -> float:
        """Calculate coverage percentage (applicable CVEs that have patches)."""
        applicable = self.total_cves - self.cve_not_applicable
        if applicable == 0:
            return 100.0
        covered = self.cve_included + self.cve_in_newer_stable + self.cve_patch_available
        return round(covered / applicable * 100, 2)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "total_cves": self.total_cves,
            "cve_included": self.cve_included,
            "cve_in_newer_stable": self.cve_in_newer_stable,
            "cve_patch_available": self.cve_patch_available,
            "cve_patch_missing": self.cve_patch_missing,
            "cve_not_applicable": self.cve_not_applicable,
            "coverage_percent": self.coverage_percent,
        }


@dataclass
class PhaseBuildInfo:
    """Build information for a phase."""
    success: bool = False
    spec_file: str = ""
    version: str = ""
    release: str = ""
    rpm_version: str = ""
    duration_seconds: int = 0
    log_file: str = ""
    rpm_path: str = ""
    error_message: str = ""
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "success": self.success,
            "spec_file": self.spec_file,
            "version": self.version,
            "release": self.release,
            "rpm_version": self.rpm_version,
            "duration_seconds": self.duration_seconds,
            "log_file": self.log_file,
            "rpm_path": self.rpm_path,
            "error_message": self.error_message,
        }


@dataclass
class PhaseResult:
    """Result of a workflow phase."""
    phase: int
    name: str
    kernel_version: str
    rpm_version: str = ""
    cve_coverage: CVECoverageStats = field(default_factory=CVECoverageStats)
    patches_downloaded: int = 0
    patches_integrated: int = 0
    stable_patch_applied: str = ""
    cves_fixed_by_stable: int = 0
    build: PhaseBuildInfo = field(default_factory=PhaseBuildInfo)
    missing_cves: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "phase": self.phase,
            "name": self.name,
            "kernel_version": self.kernel_version,
            "rpm_version": self.rpm_version,
            "cve_coverage": self.cve_coverage.to_dict(),
            "patches_downloaded": self.patches_downloaded,
            "patches_integrated": self.patches_integrated,
            "stable_patch_applied": self.stable_patch_applied,
            "cves_fixed_by_stable": self.cves_fixed_by_stable,
            "build": self.build.to_dict(),
            "missing_cves_sample": self.missing_cves[:20],
            "missing_cves_count": len(self.missing_cves),
            "errors": self.errors,
        }


@dataclass
class WorkflowReport:
    """Complete workflow report."""
    workflow_id: str = field(default_factory=lambda: str(uuid.uuid4())[:8])
    generated: datetime = field(default_factory=datetime.now)
    kernel_series: str = ""
    phases: List[PhaseResult] = field(default_factory=list)
    total_runtime_seconds: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "workflow_id": self.workflow_id,
            "generated": self.generated.isoformat(),
            "kernel_series": self.kernel_series,
            "phases": [p.to_dict() for p in self.phases],
            "summary": {
                "total_runtime_seconds": self.total_runtime_seconds,
                "phase1_build_success": self.phases[0].build.success if self.phases else False,
                "phase2_build_success": self.phases[1].build.success if len(self.phases) > 1 else False,
                "coverage_improvement": self._calculate_improvement(),
            },
        }
    
    def _calculate_improvement(self) -> str:
        if len(self.phases) < 2:
            return "N/A"
        p1_coverage = self.phases[0].cve_coverage.coverage_percent
        p2_coverage = self.phases[1].cve_coverage.coverage_percent
        diff = p2_coverage - p1_coverage
        return f"{'+' if diff >= 0 else ''}{diff:.2f}%"
    
    def save_json(self, output_path: Path) -> None:
        """Save report as JSON."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(self.to_dict(), f, indent=2)
        logger.info(f"Report saved: {output_path}")
    
    def save_markdown(self, output_path: Path) -> None:
        """Save report as Markdown."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        lines = [
            f"# CVE Coverage Build Workflow Report",
            f"",
            f"**Workflow ID:** {self.workflow_id}",
            f"**Generated:** {self.generated.strftime('%Y-%m-%d %H:%M:%S')}",
            f"**Kernel Series:** {self.kernel_series}",
            f"**Total Runtime:** {self.total_runtime_seconds}s",
            f"",
        ]
        
        for phase in self.phases:
            lines.extend([
                f"## Phase {phase.phase}: {phase.name}",
                f"",
                f"**Kernel Version:** {phase.kernel_version}",
                f"**RPM Version:** {phase.rpm_version}",
                f"",
                f"### CVE Coverage",
                f"",
                f"| Metric | Count |",
                f"|--------|-------|",
                f"| Total CVEs | {phase.cve_coverage.total_cves} |",
                f"| Included (built-in) | {phase.cve_coverage.cve_included} |",
                f"| In Newer Stable | {phase.cve_coverage.cve_in_newer_stable} |",
                f"| Patch Available | {phase.cve_coverage.cve_patch_available} |",
                f"| Patch Missing | {phase.cve_coverage.cve_patch_missing} |",
                f"| Not Applicable | {phase.cve_coverage.cve_not_applicable} |",
                f"| **Coverage** | **{phase.cve_coverage.coverage_percent}%** |",
                f"",
                f"### Patches",
                f"",
                f"- Downloaded: {phase.patches_downloaded}",
                f"- Integrated: {phase.patches_integrated}",
            ])
            
            if phase.stable_patch_applied:
                lines.extend([
                    f"- Stable Patch: {phase.stable_patch_applied}",
                    f"- CVEs Fixed by Stable: {phase.cves_fixed_by_stable}",
                ])
            
            lines.extend([
                f"",
                f"### Build Result",
                f"",
                f"| Field | Value |",
                f"|-------|-------|",
                f"| Success | {'Yes' if phase.build.success else 'No'} |",
                f"| Spec File | {phase.build.spec_file} |",
                f"| Version | {phase.build.version}-{phase.build.release} |",
                f"| Duration | {phase.build.duration_seconds}s |",
            ])
            
            if phase.build.rpm_path:
                lines.append(f"| RPM Path | {phase.build.rpm_path} |")
            if phase.build.error_message:
                lines.append(f"| Error | {phase.build.error_message} |")
            
            lines.append(f"")
            
            if phase.errors:
                lines.extend([
                    f"### Errors",
                    f"",
                ])
                for err in phase.errors:
                    lines.append(f"- {err}")
                lines.append(f"")
        
        # Summary
        lines.extend([
            f"## Summary",
            f"",
            f"| Metric | Value |",
            f"|--------|-------|",
            f"| Phase 1 Build | {'Success' if self.phases[0].build.success else 'Failed'} |" if self.phases else "",
            f"| Phase 2 Build | {'Success' if len(self.phases) > 1 and self.phases[1].build.success else 'Failed'} |" if len(self.phases) > 1 else "",
            f"| Coverage Improvement | {self._calculate_improvement()} |",
        ])
        
        with open(output_path, "w") as f:
            f.write("\n".join(lines))
        logger.info(f"Markdown report saved: {output_path}")


class CVECoverageBuildWorkflow:
    """Two-phase CVE coverage and kernel build workflow."""
    
    def __init__(
        self,
        kernel_version: str = "6.12",
        cleanup: bool = True,
        output_dir: Optional[Path] = None,
        config: Optional[KernelConfig] = None,
        spec_filter: Optional[List[str]] = None,
        repo_base: Optional[Path] = None,
    ):
        self.kernel_version = kernel_version
        self.cleanup = cleanup
        self.config = config or KernelConfig.from_env()
        self.spec_filter = spec_filter or ["linux-esx.spec"]
        self.repo_base = repo_base
        
        self.mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not self.mapping:
            raise ValueError(f"Unsupported kernel version: {kernel_version}")
        
        # Determine repo directory - use repo_base if provided
        if repo_base:
            self.repo_dir = repo_base / self.mapping.branch.value
        else:
            self.repo_dir = self.config.get_repo_dir(kernel_version)
        self.spec_dir = self.repo_dir / self.mapping.spec_dir
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        self.output_dir = output_dir or (self.config.report_dir / f"cve_build_workflow_{timestamp}")
        self.output_dir.mkdir(parents=True, exist_ok=True)
        
        self.report = WorkflowReport(kernel_series=kernel_version)
        self.builder = KernelBuilder(self.config)
        self.stable_manager = StablePatchManager(self.config)
        
        self._cves: List[CVE] = []
        self._repo_cloned: bool = False
        self._feed_cache: Optional[NVDFeedCache] = None
        
        log_file = self.output_dir / "workflow.log"
        setup_logging("cve_workflow", log_file=log_file)
    
    def cleanup_previous_run(self) -> None:
        """Remove build artifacts and caches from previous runs."""
        console.print("\n[bold blue]Cleanup: Removing previous run artifacts[/bold blue]")
        
        dirs_to_clean = [
            Path("/usr/local/src/BUILD"),
            Path("/usr/local/src/BUILDROOT"),
            Path("/usr/local/src/RPMS"),
            Path("/usr/local/src/SPECS"),
            Path("/usr/local/src/SOURCES"),
        ]
        
        for dir_path in dirs_to_clean:
            if dir_path.exists():
                try:
                    shutil.rmtree(dir_path)
                    console.print(f"  Removed: {dir_path}")
                except Exception as e:
                    console.print(f"  [yellow]Warning: Could not remove {dir_path}: {e}[/yellow]")
        
        cache_dirs = [
            self.config.cache_dir / "nvd_feeds",
            self.config.cache_dir / "stable_markers",
        ]
        
        for cache_dir in cache_dirs:
            marker_files = list(cache_dir.glob("*.marker")) if cache_dir.exists() else []
            for mf in marker_files:
                mf.unlink()
                console.print(f"  Removed marker: {mf}")
        
        console.print("  [green]Cleanup complete[/green]")
    
    def ensure_repo_cloned(self, force_update: bool = False) -> bool:
        """Ensure Photon repository is cloned using the centralized clone routine."""
        from scripts.common import ensure_photon_repo
        
        repo_dir = ensure_photon_repo(
            self.kernel_version,
            config=self.config,
            repo_base=self.repo_base,
            force_update=force_update,
        )
        
        if repo_dir:
            self.repo_dir = repo_dir
            self.spec_dir = repo_dir / self.mapping.spec_dir
            self._repo_cloned = True
            return True
        return False
    
    async def fetch_all_cves(self) -> List[CVE]:
        """Fetch all CVEs from NVD feeds."""
        if self._cves:
            return self._cves
        
        console.print("\n[bold blue]Fetching CVEs from NVD feeds[/bold blue]")
        
        nvd_fetcher = NVDFetcher(self.config)
        self._cves = await nvd_fetcher.fetch_async(self.kernel_version, self.output_dir)
        
        console.print(f"  [green]Fetched {len(self._cves)} CVEs[/green]")
        return self._cves
    
    def get_current_kernel_version(self) -> str:
        """Get current Photon kernel version from spec file."""
        spec_path = self.spec_dir / "linux.spec"
        if not spec_path.exists():
            spec_path = self.spec_dir / self.spec_filter[0]
        
        spec = SpecFile(spec_path)
        return spec.version
    
    def get_latest_stable_version(self) -> Optional[str]:
        """Get latest stable version from kernel.org."""
        return self.stable_manager.get_latest_stable_version(self.kernel_version)
    
    def generate_cve_matrix(
        self,
        kernel_version: str,
        phase_name: str = "phase1",
    ) -> Tuple[CVECoverageStats, List[str]]:
        """
        Generate CVE coverage matrix and return stats with missing CVE IDs.
        
        Also saves detailed matrix to JSON and CSV files.
        
        Returns:
            Tuple of (CVECoverageStats, list of missing CVE IDs)
        """
        console.print(f"\n[bold]Generating CVE matrix for {kernel_version}[/bold]")
        
        builder = CVEMatrixBuilder([self.kernel_version], self.config)
        
        repo_dirs = {self.kernel_version: self.repo_dir}
        matrix = builder.build_from_cves(self._cves, repo_dirs, {})
        
        stats = CVECoverageStats(total_cves=matrix.total_cves)
        missing_cves = []
        
        if matrix.kernel_coverage:
            kc = matrix.kernel_coverage.get(self.kernel_version)
            if kc:
                stats.cve_included = kc.total_included
                stats.cve_in_newer_stable = kc.total_cve_in_newer_stable
                stats.cve_patch_available = kc.total_cve_patch_available
                stats.cve_patch_missing = kc.total_cve_patch_missing
                stats.cve_not_applicable = kc.total_not_applicable
                
                if kc.stable_patches:
                    missing_cves = kc.stable_patches[0].cve_patch_missing
        
        console.print(f"  Total CVEs: {stats.total_cves}")
        console.print(f"  Included: {stats.cve_included}")
        console.print(f"  In Newer Stable: {stats.cve_in_newer_stable}")
        console.print(f"  Patch Available: {stats.cve_patch_available}")
        console.print(f"  [yellow]Patch Missing: {stats.cve_patch_missing}[/yellow]")
        console.print(f"  Not Applicable: {stats.cve_not_applicable}")
        console.print(f"  [cyan]Coverage: {stats.coverage_percent}%[/cyan]")
        
        # Save detailed CVE matrix to files
        matrix_dir = self.output_dir / f"{phase_name}_cve_matrix"
        matrix_dir.mkdir(parents=True, exist_ok=True)
        
        matrix.save_json(matrix_dir / f"cve_matrix_{kernel_version}.json")
        matrix.save_csv(matrix_dir / f"cve_matrix_{kernel_version}.csv")
        matrix.save_stable_patch_csv(matrix_dir / f"cve_stable_patch_{kernel_version}.csv")
        
        console.print(f"  [green]Saved detailed CVE matrix to {matrix_dir}[/green]")
        
        return stats, missing_cves
    
    def download_cve_patches(
        self,
        cve_ids: List[str],
        patch_dir: Path,
    ) -> Tuple[int, List[str]]:
        """
        Download patches for missing CVEs.
        
        Returns:
            Tuple of (count downloaded, list of patch files)
        """
        if not cve_ids:
            return 0, []
        
        console.print(f"\n[bold]Downloading patches for {len(cve_ids)} missing CVEs[/bold]")
        
        patch_dir.mkdir(parents=True, exist_ok=True)
        downloaded = []
        
        if not self._feed_cache:
            self._feed_cache = NVDFeedCache(self.config)
            self._feed_cache.update_feeds()
            self._feed_cache.load_index()
        
        for cve_id in cve_ids[:100]:
            cve_data = self._feed_cache.get_cve(cve_id)
            if not cve_data:
                continue
            
            for ref in cve_data.get("references", []):
                url = ref.get("url", "")
                if "git.kernel.org" in url and "/commit/" in url:
                    commit_match = __import__("re").search(r"/([a-f0-9]{40})", url)
                    if commit_match:
                        commit_sha = commit_match.group(1)
                        patch_url = f"https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/patch/?id={commit_sha}"
                        patch_file = patch_dir / f"{commit_sha[:12]}-{cve_id}.patch"
                        
                        if patch_file.exists():
                            downloaded.append(str(patch_file))
                            break
                        
                        if download_file(patch_url, patch_file):
                            downloaded.append(str(patch_file))
                            break
        
        console.print(f"  [green]Downloaded {len(downloaded)} patches[/green]")
        return len(downloaded), downloaded
    
    def integrate_patches_to_spec(
        self,
        patch_files: List[str],
        spec_name: str = "linux-esx.spec",
    ) -> int:
        """
        Integrate downloaded patches into spec file.
        
        Returns:
            Number of patches integrated
        """
        if not patch_files:
            return 0
        
        console.print(f"\n[bold]Integrating {len(patch_files)} patches into {spec_name}[/bold]")
        
        spec_path = self.spec_dir / spec_name
        if not spec_path.exists():
            console.print(f"  [red]Spec file not found: {spec_path}[/red]")
            return 0
        
        spec = SpecFile(spec_path)
        integrated = 0
        
        sources_dir = self.spec_dir
        
        for patch_file in patch_files:
            patch_path = Path(patch_file)
            if not patch_path.exists():
                continue
            
            patch_name = patch_path.name
            sha_prefix = patch_name[:12]
            
            if spec.has_patch(sha_prefix):
                continue
            
            dest_path = sources_dir / patch_name
            if not dest_path.exists():
                shutil.copy2(patch_path, dest_path)
            
            next_num = spec.get_next_patch_number(100, 499)
            if next_num > 0:
                if spec.add_patch(patch_name, next_num):
                    integrated += 1
        
        if integrated > 0:
            spec.increment_release()
            spec.save()
        
        console.print(f"  [green]Integrated {integrated} patches[/green]")
        return integrated
    
    def build_kernel_rpm(self, phase_name: str) -> PhaseBuildInfo:
        """Build kernel RPM using SRPM approach."""
        console.print(f"\n[bold]Building kernel RPM ({phase_name})[/bold]")
        
        build_info = PhaseBuildInfo()
        
        deps_ok, missing = self.builder.verify_build_deps()
        if not deps_ok:
            build_info.error_message = f"Missing build deps: {', '.join(missing)}"
            console.print(f"  [red]{build_info.error_message}[/red]")
            return build_info
        
        results = self.builder.build_all_from_srpm(
            kernel_version=self.kernel_version,
            canister=0,
            acvp=0,
            install_deps=True,
            spec_filter=self.spec_filter,
            use_srpm_spec=True,  # Use SRPM specs to ensure all patches exist
        )
        
        if results:
            result = results[0]
            build_info.success = result.success
            build_info.spec_file = Path(result.spec_file).name if result.spec_file else ""
            build_info.version = result.version
            build_info.release = str(result.release)
            build_info.rpm_version = f"{result.version}-{result.release}"
            build_info.duration_seconds = result.duration_seconds
            build_info.log_file = result.log_file or ""
            build_info.error_message = result.error_message or ""
            
            if result.success:
                rpm_dir = Path("/usr/local/src/RPMS/x86_64")
                rpms = list(rpm_dir.glob(f"*{result.version}*.rpm")) if rpm_dir.exists() else []
                if rpms:
                    build_info.rpm_path = str(rpms[0])
                console.print(f"  [green]Build successful: {build_info.rpm_version}[/green]")
            else:
                console.print(f"  [red]Build failed: {build_info.error_message}[/red]")
        
        return build_info
    
    def update_spec_to_stable(self, new_version: str) -> bool:
        """Update spec file to new stable version."""
        console.print(f"\n[bold]Updating spec to {new_version}[/bold]")
        
        for spec_name in self.spec_filter:
            spec_path = self.spec_dir / spec_name
            if not spec_path.exists():
                continue
            
            spec = SpecFile(spec_path)
            old_version = spec.version
            
            if spec.set_version(new_version):
                spec.reset_release()
                spec.save()
                console.print(f"  Updated {spec_name}: {old_version} -> {new_version}")
            else:
                console.print(f"  [yellow]Could not update {spec_name}[/yellow]")
                return False
        
        return True
    
    async def download_stable_patch(self, target_version: str) -> Optional[str]:
        """Download stable patch from kernel.org."""
        console.print(f"\n[bold]Downloading stable patch for {target_version}[/bold]")
        
        kernel_url = get_kernel_org_url(self.kernel_version)
        if not kernel_url:
            return None
        
        patch_name = f"patch-{target_version}.xz"
        patch_url = f"{kernel_url}{patch_name}"
        patch_dir = self.output_dir / "stable_patches"
        patch_dir.mkdir(parents=True, exist_ok=True)
        patch_path = patch_dir / patch_name
        
        if download_file(patch_url, patch_path):
            console.print(f"  [green]Downloaded: {patch_name}[/green]")
            return str(patch_path)
        
        console.print(f"  [red]Failed to download: {patch_url}[/red]")
        return None
    
    async def phase1_current_kernel(self) -> PhaseResult:
        """Phase 1: Process current Photon kernel version."""
        console.print(Panel.fit(
            "[bold cyan]Phase 1: Current Kernel Build[/bold cyan]",
            border_style="cyan",
        ))
        
        result = PhaseResult(
            phase=1,
            name="current_kernel",
            kernel_version="unknown",
        )
        
        if not self.ensure_repo_cloned():
            result.errors.append(f"Failed to clone repository for {self.kernel_version}")
            return result
        
        current_version = self.get_current_kernel_version()
        result.kernel_version = current_version
        
        console.print(f"Current Photon kernel version: [cyan]{current_version}[/cyan]")
        
        await self.fetch_all_cves()
        
        stats, missing_cves = self.generate_cve_matrix(current_version)
        result.cve_coverage = stats
        result.missing_cves = missing_cves
        
        patch_dir = self.output_dir / "phase1_patches"
        downloaded, patch_files = self.download_cve_patches(missing_cves, patch_dir)
        result.patches_downloaded = downloaded
        
        integrated = self.integrate_patches_to_spec(patch_files, self.spec_filter[0])
        result.patches_integrated = integrated
        
        build_info = self.build_kernel_rpm("phase1")
        result.build = build_info
        result.rpm_version = build_info.rpm_version
        
        return result
    
    async def phase2_latest_stable(self, phase1_coverage: CVECoverageStats) -> PhaseResult:
        """Phase 2: Process latest stable kernel."""
        console.print(Panel.fit(
            "[bold cyan]Phase 2: Latest Stable Kernel Build[/bold cyan]",
            border_style="cyan",
        ))
        
        current_version = self.get_current_kernel_version()
        latest_version = self.get_latest_stable_version()
        
        result = PhaseResult(
            phase=2,
            name="latest_stable",
            kernel_version=latest_version or current_version,
        )
        
        if not latest_version:
            result.errors.append("Could not determine latest stable version")
            console.print("[red]Could not determine latest stable version[/red]")
            return result
        
        console.print(f"Current version: [cyan]{current_version}[/cyan]")
        console.print(f"Latest stable: [cyan]{latest_version}[/cyan]")
        
        if current_version == latest_version:
            console.print("[green]Already at latest stable version[/green]")
            result.cve_coverage = phase1_coverage
            return result
        
        stable_patch = await self.download_stable_patch(latest_version)
        if stable_patch:
            result.stable_patch_applied = Path(stable_patch).name
        
        if not self.update_spec_to_stable(latest_version):
            result.errors.append("Failed to update spec version")
            return result
        
        result.cves_fixed_by_stable = phase1_coverage.cve_in_newer_stable
        
        stats, missing_cves = self.generate_cve_matrix(latest_version)
        result.cve_coverage = stats
        result.missing_cves = missing_cves
        
        patch_dir = self.output_dir / "phase2_patches"
        downloaded, patch_files = self.download_cve_patches(missing_cves, patch_dir)
        result.patches_downloaded = downloaded
        
        integrated = self.integrate_patches_to_spec(patch_files, self.spec_filter[0])
        result.patches_integrated = integrated
        
        build_info = self.build_kernel_rpm("phase2")
        result.build = build_info
        result.rpm_version = build_info.rpm_version
        
        return result
    
    async def run(self) -> WorkflowReport:
        """Run the complete two-phase workflow."""
        start_time = datetime.now()
        
        console.print(Panel.fit(
            f"[bold green]CVE Coverage Build Workflow[/bold green]\n"
            f"Kernel: {self.kernel_version}\n"
            f"Output: {self.output_dir}",
            border_style="green",
        ))
        
        if self.cleanup:
            self.cleanup_previous_run()
        
        phase1_result = await self.phase1_current_kernel()
        self.report.phases.append(phase1_result)
        
        phase2_result = await self.phase2_latest_stable(phase1_result.cve_coverage)
        self.report.phases.append(phase2_result)
        
        end_time = datetime.now()
        self.report.total_runtime_seconds = int((end_time - start_time).total_seconds())
        
        self.report.save_json(self.output_dir / "report.json")
        self.report.save_markdown(self.output_dir / "report.md")
        
        self._print_summary()
        
        return self.report
    
    def _print_summary(self) -> None:
        """Print workflow summary to console."""
        console.print("\n")
        console.print(Panel.fit(
            "[bold green]Workflow Complete[/bold green]",
            border_style="green",
        ))
        
        table = Table(title="Phase Summary")
        table.add_column("Phase", style="cyan")
        table.add_column("Kernel", style="white")
        table.add_column("Coverage", style="yellow")
        table.add_column("Build", style="white")
        
        for phase in self.report.phases:
            build_status = "[green]Success[/green]" if phase.build.success else "[red]Failed[/red]"
            table.add_row(
                f"Phase {phase.phase}",
                phase.kernel_version,
                f"{phase.cve_coverage.coverage_percent}%",
                build_status,
            )
        
        console.print(table)
        console.print(f"\nTotal runtime: {self.report.total_runtime_seconds}s")
        console.print(f"Report: {self.output_dir / 'report.json'}")


def run_cve_build_workflow(
    kernel_version: str = "6.12",
    cleanup: bool = True,
    output_dir: Optional[str] = None,
    repo_base: Optional[Path] = None,
    repo_url: str = "https://github.com/vmware/photon.git",
    phase1_only: bool = False,
    spec_filter: Optional[List[str]] = None,
) -> WorkflowReport:
    """
    Run the CVE coverage build workflow.
    
    Args:
        kernel_version: Kernel version (e.g., "6.12")
        cleanup: Whether to cleanup previous run artifacts
        output_dir: Output directory for reports
        repo_base: Base directory for cloning repos (overrides config default)
        repo_url: Photon repository URL
        phase1_only: Only run phase 1 (current kernel)
        spec_filter: List of spec files to build
    
    Returns:
        WorkflowReport with complete results
    """
    config = KernelConfig.from_env()
    if repo_url != "https://github.com/vmware/photon.git":
        config.repo_url = repo_url
    
    workflow = CVECoverageBuildWorkflow(
        kernel_version=kernel_version,
        cleanup=cleanup,
        output_dir=Path(output_dir) if output_dir else None,
        config=config,
        spec_filter=spec_filter,
        repo_base=repo_base,
    )
    
    async def _run():
        if phase1_only:
            await workflow.fetch_all_cves()
            if cleanup:
                workflow.cleanup_previous_run()
            result = await workflow.phase1_current_kernel()
            workflow.report.phases.append(result)
            workflow.report.save_json(workflow.output_dir / "report.json")
            workflow.report.save_markdown(workflow.output_dir / "report.md")
            return workflow.report
        else:
            return await workflow.run()
    
    return asyncio.run(_run())


if __name__ == "__main__":
    import argparse
    
    parser = argparse.ArgumentParser(description="CVE Coverage Build Workflow")
    parser.add_argument("--kernel", "-k", default="6.12", help="Kernel version")
    parser.add_argument("--no-cleanup", action="store_true", help="Skip cleanup")
    parser.add_argument("--output", "-o", help="Output directory")
    parser.add_argument("--phase1-only", action="store_true", help="Only run phase 1")
    parser.add_argument("--specs", help="Comma-separated spec files to build")
    
    args = parser.parse_args()
    
    spec_filter = None
    if args.specs:
        spec_filter = [s.strip() for s in args.specs.split(",")]
    
    report = run_cve_build_workflow(
        kernel_version=args.kernel,
        cleanup=not args.no_cleanup,
        output_dir=args.output,
        phase1_only=args.phase1_only,
        spec_filter=spec_filter,
    )
    
    print(f"\nWorkflow ID: {report.workflow_id}")
    print(f"Success: Phase1={report.phases[0].build.success if report.phases else False}, "
          f"Phase2={report.phases[1].build.success if len(report.phases) > 1 else 'N/A'}")
