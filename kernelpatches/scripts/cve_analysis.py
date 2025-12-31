"""
CVE analysis for detecting redundant patches after stable updates.
"""

import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Set

from scripts.common import extract_cve_ids, logger
from scripts.config import DEFAULT_CONFIG, KernelConfig, get_spec_files_for_kernel
from scripts.models import CVE, ReportSummary
from scripts.spec_file import SpecFile


@dataclass
class PatchAnalysisResult:
    """Result of analyzing a single patch."""
    patch_name: str
    applied: bool
    cves_fixed: List[str] = field(default_factory=list)
    cves_now_redundant: List[str] = field(default_factory=list)


@dataclass
class CVEAnalysisReport:
    """Complete CVE analysis report."""
    kernel_version: str
    generated: datetime = field(default_factory=datetime.now)
    patch_results: List[PatchAnalysisResult] = field(default_factory=list)
    summary: ReportSummary = field(default_factory=ReportSummary)
    
    def to_dict(self) -> Dict:
        """Convert report to dictionary."""
        return {
            "kernel_version": self.kernel_version,
            "generated": self.generated.isoformat(),
            "stable_patches": [
                {
                    "patch": r.patch_name,
                    "applied": r.applied,
                    "cves_fixed": r.cves_fixed,
                    "cves_now_redundant": r.cves_now_redundant,
                }
                for r in self.patch_results
            ],
            "summary": {
                "total_stable_patches": self.summary.total_stable_patches,
                "total_cves_in_spec": self.summary.total_cves_in_spec,
                "cves_fixed_by_stable": self.summary.cves_fixed_by_stable,
                "cves_still_needed": self.summary.cves_still_needed,
            },
        }
    
    def save_json(self, output_path: Path) -> None:
        """Save report as JSON."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(self.to_dict(), f, indent=2)
        logger.info(f"Saved JSON report: {output_path}")
    
    def save_text(self, output_path: Path) -> None:
        """Save report as text."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        lines = [
            "=" * 80,
            f"CVE Analysis Report for Kernel {self.kernel_version}",
            f"Generated: {self.generated.strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 80,
            "",
            "SUMMARY",
            "-" * 40,
            f"Total stable patches analyzed: {self.summary.total_stable_patches}",
            f"Total CVE patches in spec:     {self.summary.total_cves_in_spec}",
            f"CVEs fixed by stable patches:  {self.summary.cves_fixed_by_stable}",
            f"CVEs still needed:             {self.summary.cves_still_needed}",
            "",
            "DETAILS",
            "-" * 40,
        ]
        
        for result in self.patch_results:
            lines.append(f"Patch: {result.patch_name}")
            lines.append(f"  Applied: {result.applied}")
            lines.append(f"  CVEs Fixed: {', '.join(result.cves_fixed) or 'none'}")
            lines.append(f"  CVEs Redundant: {', '.join(result.cves_now_redundant) or 'none'}")
            lines.append("")
        
        with open(output_path, "w") as f:
            f.write("\n".join(lines))
        logger.info(f"Saved text report: {output_path}")


class CVEAnalyzer:
    """Analyze CVE patches for redundancy after stable updates."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
    
    def extract_cves_from_patch(self, patch_path: Path) -> List[str]:
        """Extract CVE IDs from a patch file."""
        if not patch_path.exists():
            return []
        
        content = patch_path.read_text(errors="ignore")
        return extract_cve_ids(content)
    
    def compare_patch_content(
        self,
        patch1_path: Path,
        patch2_path: Path,
        threshold: int = 70,
    ) -> bool:
        """
        Compare two patches to detect if they address the same issue.
        
        Args:
            patch1_path: Path to first patch
            patch2_path: Path to second patch
            threshold: Similarity threshold percentage
        
        Returns:
            True if patches are similar
        """
        if not patch1_path.exists() or not patch2_path.exists():
            return False
        
        try:
            content1 = patch1_path.read_text(errors="ignore")
            content2 = patch2_path.read_text(errors="ignore")
        except Exception:
            return False
        
        # Extract code changes (lines starting with + or -)
        def get_changes(content: str) -> Set[str]:
            changes = set()
            for line in content.splitlines():
                if line.startswith(("+", "-")) and not line.startswith(("+++", "---")):
                    changes.add(line)
            return changes
        
        changes1 = get_changes(content1)
        changes2 = get_changes(content2)
        
        if not changes1 or not changes2:
            return False
        
        # Calculate similarity
        common = changes1 & changes2
        max_total = max(len(changes1), len(changes2))
        
        if max_total == 0:
            return False
        
        similarity = (len(common) * 100) // max_total
        return similarity >= threshold
    
    def get_files_changed(self, patch_path: Path) -> Set[str]:
        """Extract files changed by a patch."""
        if not patch_path.exists():
            return set()
        
        files = set()
        content = patch_path.read_text(errors="ignore")
        
        for line in content.splitlines():
            if line.startswith("+++"):
                # Extract filename from +++ b/path/to/file
                match = re.match(r"\+\+\+ [ab]/(.+)", line)
                if match:
                    files.add(match.group(1))
        
        return files
    
    def check_redundancy(
        self,
        stable_patch_path: Path,
        cve_patch_path: Path,
    ) -> str:
        """
        Check if a stable patch makes a CVE patch redundant.
        
        Returns:
            "direct_match" - CVE ID found in stable patch
            "content_similar" - Patch content is similar
            "same_files" - Patches modify same files
            "no_match" - No redundancy detected
        """
        if not stable_patch_path.exists():
            return "stable_not_found"
        if not cve_patch_path.exists():
            return "cve_not_found"
        
        stable_content = stable_patch_path.read_text(errors="ignore")
        
        # Check for direct CVE reference
        cve_patch_name = cve_patch_path.name
        cve_ids = extract_cve_ids(cve_patch_name)
        
        for cve_id in cve_ids:
            if cve_id in stable_content:
                return "direct_match"
        
        # Check content similarity
        if self.compare_patch_content(stable_patch_path, cve_patch_path, 60):
            return "content_similar"
        
        # Check for same files
        stable_files = self.get_files_changed(stable_patch_path)
        cve_files = self.get_files_changed(cve_patch_path)
        
        if stable_files & cve_files:
            return "same_files"
        
        return "no_match"
    
    def analyze_stable_patch(
        self,
        stable_patch_path: Path,
        spec_file: SpecFile,
        spec_dir: Path,
    ) -> PatchAnalysisResult:
        """
        Analyze CVE coverage of a single stable patch.
        
        Args:
            stable_patch_path: Path to stable patch file
            spec_file: Spec file to analyze
            spec_dir: Directory containing patch files
        
        Returns:
            PatchAnalysisResult with analysis results
        """
        patch_name = stable_patch_path.name
        cves_fixed = self.extract_cves_from_patch(stable_patch_path)
        cves_redundant = []
        
        # Check each CVE patch in the spec
        cve_patches = spec_file.get_cve_patches()
        
        for cve_patch in cve_patches:
            cve_patch_path = spec_dir / cve_patch.name
            result = self.check_redundancy(stable_patch_path, cve_patch_path)
            
            if result in ("direct_match", "content_similar"):
                cves_redundant.extend(cve_patch.cve_ids)
        
        return PatchAnalysisResult(
            patch_name=patch_name,
            applied=True,
            cves_fixed=list(set(cves_fixed)),
            cves_now_redundant=list(set(cves_redundant)),
        )
    
    def analyze_kernel(
        self,
        kernel_version: str,
        repo_dir: Path,
        stable_patch_dir: Path,
        cve_since: Optional[str] = None,
    ) -> CVEAnalysisReport:
        """
        Run full CVE analysis for a kernel version.
        
        Args:
            kernel_version: Kernel version (e.g., "6.1")
            repo_dir: Path to Photon repository
            stable_patch_dir: Directory containing stable patches
            cve_since: Filter CVEs since this date (YYYY or YYYY-MM)
        
        Returns:
            CVEAnalysisReport with full analysis
        """
        from scripts.config import KERNEL_MAPPINGS
        
        logger.info(f"Starting CVE analysis for kernel {kernel_version}")
        
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            raise ValueError(f"Unsupported kernel version: {kernel_version}")
        
        spec_dir = repo_dir / mapping.spec_dir
        spec_files = mapping.spec_files
        
        report = CVEAnalysisReport(kernel_version=kernel_version)
        
        # Get stable patches
        stable_patches = sorted(
            stable_patch_dir.glob(f"patch-{kernel_version}.*"),
            key=lambda p: p.name,
        )
        stable_patches = [p for p in stable_patches if not p.suffix == ".xz"]
        
        if not stable_patches:
            logger.warning(f"No stable patches found in {stable_patch_dir}")
            return report
        
        report.summary.total_stable_patches = len(stable_patches)
        
        # Count CVEs in spec files
        all_cves: Set[str] = set()
        all_redundant: Set[str] = set()
        
        for spec_name in spec_files:
            spec_path = spec_dir / spec_name
            if not spec_path.exists():
                continue
            
            spec = SpecFile(spec_path)
            spec_cves = spec.extract_all_cve_ids()
            all_cves.update(spec_cves)
            
            # Analyze each stable patch
            for stable_patch_path in stable_patches:
                result = self.analyze_stable_patch(stable_patch_path, spec, spec_dir)
                
                # Filter by date if specified
                if cve_since:
                    result.cves_fixed = self._filter_cves_by_date(result.cves_fixed, cve_since)
                    result.cves_now_redundant = self._filter_cves_by_date(
                        result.cves_now_redundant, cve_since
                    )
                
                all_redundant.update(result.cves_now_redundant)
                
                # Only add unique results
                existing = {r.patch_name for r in report.patch_results}
                if result.patch_name not in existing:
                    report.patch_results.append(result)
        
        # Calculate summary
        report.summary.total_cves_in_spec = len(all_cves)
        report.summary.cves_fixed_by_stable = len(all_redundant)
        report.summary.cves_still_needed = max(0, len(all_cves) - len(all_redundant))
        
        logger.info(f"Analysis complete: {report.summary.cves_fixed_by_stable} CVEs fixed by stable")
        
        return report
    
    def _filter_cves_by_date(self, cve_ids: List[str], since_date: str) -> List[str]:
        """Filter CVE IDs by year."""
        if not since_date:
            return cve_ids
        
        since_year = int(since_date.split("-")[0])
        
        filtered = []
        for cve_id in cve_ids:
            match = re.search(r"CVE-(\d{4})-", cve_id)
            if match:
                cve_year = int(match.group(1))
                if cve_year >= since_year:
                    filtered.append(cve_id)
        
        return filtered


def run_cve_analysis(
    kernel_version: str,
    repo_dir: Path,
    stable_patch_dir: Path,
    report_dir: Path,
    cve_since: Optional[str] = None,
    config: Optional[KernelConfig] = None,
) -> Path:
    """
    Run CVE analysis and save reports.
    
    Args:
        kernel_version: Target kernel version
        repo_dir: Path to Photon repository
        stable_patch_dir: Directory containing stable patches
        report_dir: Directory for output reports
        cve_since: Filter CVEs since this date
        config: Optional configuration
    
    Returns:
        Path to JSON report file
    """
    analyzer = CVEAnalyzer(config)
    report = analyzer.analyze_kernel(kernel_version, repo_dir, stable_patch_dir, cve_since)
    
    # Generate report paths
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = report_dir / f"cve_analysis_{kernel_version}_{timestamp}.json"
    text_path = report_dir / f"cve_analysis_{kernel_version}_{timestamp}.txt"
    
    # Save reports
    report.save_json(json_path)
    report.save_text(text_path)
    
    return json_path
