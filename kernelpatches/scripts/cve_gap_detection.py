"""
CVE gap detection for identifying missing stable kernel backports.

Uses locally cached NVD feeds for fast offline analysis - NO per-CVE API calls.
Downloads feeds once per run, then analyzes all CVEs from local cache.
"""

import gzip
import json
import re
import time
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

import requests

from scripts.common import logger
from scripts.config import DEFAULT_CONFIG, KernelConfig, SUPPORTED_KERNELS
from scripts.models import (
    CVE,
    GapAnalysisResult,
    GapReportSummary,
    KernelVersion,
    Severity,
)


@dataclass
class GapReport:
    """Complete gap detection report."""
    kernel_version: str
    photon_version: str
    generated: datetime = field(default_factory=datetime.now)
    gaps: List[GapAnalysisResult] = field(default_factory=list)
    patchable: List[GapAnalysisResult] = field(default_factory=list)
    not_affected: List[GapAnalysisResult] = field(default_factory=list)
    no_version_info: List[str] = field(default_factory=list)
    summary: GapReportSummary = field(default_factory=GapReportSummary)
    
    def to_dict(self) -> Dict:
        """Convert report to dictionary."""
        return {
            "kernel_version": self.kernel_version,
            "photon_version": self.photon_version,
            "generated": self.generated.isoformat(),
            "gaps": [self._result_to_dict(g) for g in self.gaps],
            "patchable": [self._result_to_dict(p) for p in self.patchable],
            "not_affected": [self._result_to_dict(n) for n in self.not_affected],
            "no_version_info": self.no_version_info,
            "summary": {
                "total_cves_analyzed": self.summary.total_cves_analyzed,
                "cves_with_gaps": self.summary.cves_with_gaps,
                "cves_patchable": self.summary.cves_patchable,
                "cves_not_affected": self.summary.cves_not_affected,
                "no_version_info": len(self.no_version_info),
            },
        }
    
    def _result_to_dict(self, result: GapAnalysisResult) -> Dict:
        """Convert GapAnalysisResult to dictionary."""
        return {
            "cve_id": result.cve_id,
            "status": result.status,
            "severity": result.severity.value,
            "cvss": result.cvss_score,
            "target_kernel": result.target_kernel,
            "current_version": result.current_version,
            "is_affected": result.is_affected,
            "fix_branches": result.fix_branches,
            "missing_backports": result.missing_backports,
            "requires_manual_backport": result.requires_manual_backport,
            "description": result.description,
        }
    
    def save_json(self, output_path: Path) -> None:
        """Save report as JSON."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(self.to_dict(), f, indent=2)
        logger.info(f"Saved JSON gap report: {output_path}")
    
    def save_text(self, output_path: Path) -> None:
        """Save report as text."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        lines = [
            "=" * 80,
            "CVE Gap Detection Report",
            f"Generated: {self.generated.strftime('%Y-%m-%d %H:%M:%S')}",
            "=" * 80,
            "",
            "TARGET KERNEL",
            f"  Kernel series: {self.kernel_version}",
            f"  Photon version: {self.photon_version}",
            "",
            "SUMMARY",
            f"  Total CVEs analyzed: {self.summary.total_cves_analyzed}",
            f"  CVEs requiring manual backport (GAPS): {self.summary.cves_with_gaps}",
            f"  CVEs with available backports: {self.summary.cves_patchable}",
            f"  CVEs not affecting this kernel: {self.summary.cves_not_affected}",
            f"  CVEs without version info: {len(self.no_version_info)}",
            "",
            "=" * 80,
            "CVEs REQUIRING MANUAL BACKPORT (GAPS)",
            "=" * 80,
        ]
        
        for gap in self.gaps:
            lines.extend([
                "",
                f"CVE: {gap.cve_id}",
                f"  Severity: {gap.severity.value} (CVSS: {gap.cvss_score})",
                f"  Fix branches: {', '.join(gap.fix_branches) or 'none'}",
                f"  Missing: {', '.join(gap.missing_backports) or 'none'}",
                f"  Description: {gap.description[:150]}...",
            ])
        
        lines.extend([
            "",
            "=" * 80,
            "CVEs WITH AVAILABLE BACKPORTS (PATCHABLE)",
            "=" * 80,
        ])
        
        for p in self.patchable:
            lines.append(f"  {p.cve_id} [{p.severity.value}] - backport in {', '.join(p.fix_branches)}")
        
        with open(output_path, "w") as f:
            f.write("\n".join(lines))
        logger.info(f"Saved text gap report: {output_path}")


class NVDFeedCache:
    """
    Local cache for NVD feeds.
    
    Downloads and caches NVD JSON feeds locally:
    - Recent feed: updated every run
    - Modified feed: updated every run  
    - Yearly feeds (2023+): updated once per 24 hours
    
    All CVE analysis uses the local cache - NO per-CVE API calls.
    """
    
    # NVD 2.0 feed URLs
    NVD_FEED_BASE = "https://nvd.nist.gov/feeds/json/cve/2.0"
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
        self.cache_dir = self.config.cache_dir / "nvd_feeds"
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        
        # In-memory CVE index: cve_id -> parsed CVE data
        self._cve_index: Dict[str, Dict[str, Any]] = {}
        self._loaded = False
        
        # Marker for yearly feed refresh
        self._yearly_marker = self.cache_dir / ".yearly_last_update"
    
    def _get_feed_path(self, feed_name: str) -> Path:
        """Get local path for a feed."""
        return self.cache_dir / f"nvdcve-2.0-{feed_name}.json"
    
    def _should_update_yearly(self) -> bool:
        """Check if yearly feeds need refresh (once per 24h)."""
        if not self._yearly_marker.exists():
            return True
        try:
            last_update = float(self._yearly_marker.read_text().strip())
            age_hours = (time.time() - last_update) / 3600
            if age_hours >= 24:
                return True
            logger.debug(f"Yearly feeds last updated {age_hours:.1f}h ago, skipping")
            return False
        except Exception:
            return True
    
    def _mark_yearly_updated(self) -> None:
        """Mark yearly feeds as updated."""
        self._yearly_marker.write_text(str(time.time()))
    
    def _download_feed(self, feed_name: str, force: bool = False) -> bool:
        """
        Download a single NVD feed.
        
        Args:
            feed_name: Feed identifier (recent, modified, 2024, 2025, etc.)
            force: Force download even if cached
        
        Returns:
            True if successful
        """
        feed_path = self._get_feed_path(feed_name)
        gz_url = f"{self.NVD_FEED_BASE}/nvdcve-2.0-{feed_name}.json.gz"
        
        # Check if cached and not forcing refresh
        if not force and feed_path.exists():
            # For recent/modified, check if < 1 hour old
            if feed_name in ("recent", "modified"):
                age_hours = (time.time() - feed_path.stat().st_mtime) / 3600
                if age_hours < 1:
                    logger.debug(f"Using cached {feed_name} feed ({age_hours:.1f}h old)")
                    return True
            else:
                # Yearly feeds - use cached if exists
                logger.debug(f"Using cached {feed_name} feed")
                return True
        
        logger.info(f"Downloading NVD feed: {feed_name}")
        
        try:
            response = requests.get(gz_url, timeout=180, stream=True)
            response.raise_for_status()
            
            # Decompress and save
            gz_data = response.content
            json_data = gzip.decompress(gz_data)
            
            feed_path.write_bytes(json_data)
            logger.info(f"  Saved {feed_name} feed ({len(json_data) / 1024 / 1024:.1f} MB)")
            return True
            
        except Exception as e:
            logger.warning(f"Failed to download {feed_name} feed: {e}")
            return False
    
    def update_feeds(self, force_yearly: bool = False) -> None:
        """
        Update all NVD feeds.
        
        Downloads:
        - recent feed (always)
        - modified feed (always)
        - yearly feeds from 2023 to current year (once per 24h unless forced)
        """
        logger.info("Updating NVD feed cache...")
        
        # Always update recent and modified feeds
        self._download_feed("recent", force=True)
        self._download_feed("modified", force=True)
        
        # Update yearly feeds if needed
        if force_yearly or self._should_update_yearly():
            current_year = datetime.now().year
            for year in range(2023, current_year + 1):
                self._download_feed(str(year), force=force_yearly)
            self._mark_yearly_updated()
        
        # Clear loaded index to force reload
        self._cve_index.clear()
        self._loaded = False
    
    def _load_feed(self, feed_name: str) -> int:
        """Load a feed into the index. Returns count of CVEs loaded."""
        feed_path = self._get_feed_path(feed_name)
        if not feed_path.exists():
            return 0
        
        try:
            data = json.loads(feed_path.read_text())
            vulnerabilities = data.get("vulnerabilities", [])
            
            count = 0
            for vuln in vulnerabilities:
                cve_data = vuln.get("cve", {})
                cve_id = cve_data.get("id", "")
                if cve_id.startswith("CVE-"):
                    self._cve_index[cve_id] = cve_data
                    count += 1
            
            return count
        except Exception as e:
            logger.warning(f"Failed to load {feed_name} feed: {e}")
            return 0
    
    def load_index(self) -> None:
        """Load all feeds into the in-memory index."""
        if self._loaded:
            return
        
        logger.info("Loading NVD feeds into memory...")
        
        total = 0
        
        # Load yearly feeds first (older data)
        current_year = datetime.now().year
        for year in range(2023, current_year + 1):
            count = self._load_feed(str(year))
            if count:
                logger.debug(f"  {year}: {count} CVEs")
                total += count
        
        # Load recent/modified last (newer data overwrites)
        for feed in ["modified", "recent"]:
            count = self._load_feed(feed)
            if count:
                logger.debug(f"  {feed}: {count} CVEs")
        
        self._loaded = True
        logger.info(f"Loaded {len(self._cve_index)} unique CVEs into index")
    
    def get_cve(self, cve_id: str) -> Optional[Dict[str, Any]]:
        """Get CVE data from cache."""
        if not self._loaded:
            self.load_index()
        return self._cve_index.get(cve_id)
    
    def get_all_cve_ids(self) -> List[str]:
        """Get all CVE IDs in cache."""
        if not self._loaded:
            self.load_index()
        return list(self._cve_index.keys())
    
    def filter_by_source(self, source_identifier: str) -> List[str]:
        """Filter CVEs by source identifier (e.g., kernel.org CNA)."""
        if not self._loaded:
            self.load_index()
        
        return [
            cve_id for cve_id, data in self._cve_index.items()
            if data.get("sourceIdentifier") == source_identifier
        ]


class GapDetector:
    """
    Detect CVEs without stable kernel backports.
    
    Uses local NVD feed cache for fast offline analysis.
    No per-CVE network requests - all analysis is done locally.
    """
    
    # Known stable branches
    STABLE_BRANCHES = ["5.10", "5.15", "6.1", "6.6", "6.11", "6.12"]
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
        self.feed_cache = NVDFeedCache(config)
    
    def parse_affected_versions(
        self, cve_data: Dict[str, Any]
    ) -> List[Tuple[str, str, bool, bool]]:
        """
        Parse affected version ranges from NVD CPE configurations.
        
        Returns:
            List of (start_version, end_version, start_inclusive, end_exclusive) tuples
        """
        ranges = []
        
        configurations = cve_data.get("configurations", [])
        for config in configurations:
            for node in config.get("nodes", []):
                for cpe_match in node.get("cpeMatch", []):
                    criteria = cpe_match.get("criteria", "")
                    
                    if "linux:linux_kernel" not in criteria:
                        continue
                    if not cpe_match.get("vulnerable", False):
                        continue
                    
                    start = cpe_match.get("versionStartIncluding") or cpe_match.get("versionStartExcluding") or "0"
                    end = cpe_match.get("versionEndExcluding") or cpe_match.get("versionEndIncluding") or "999"
                    start_inc = "versionStartIncluding" in cpe_match
                    end_exc = "versionEndExcluding" in cpe_match
                    
                    ranges.append((start, end, start_inc, end_exc))
        
        return ranges
    
    def is_version_in_range(
        self,
        version: str,
        range_start: str,
        range_end: str,
        start_inclusive: bool = True,
        end_exclusive: bool = True,
    ) -> bool:
        """Check if a version falls within an affected range."""
        try:
            v = KernelVersion.parse(version)
            s = KernelVersion.parse(range_start)
            e = KernelVersion.parse(range_end)
        except Exception:
            return False
        
        # Check start boundary
        if start_inclusive:
            if v < s:
                return False
        else:
            if v <= s:
                return False
        
        # Check end boundary
        if end_exclusive:
            if v >= e:
                return False
        else:
            if v > e:
                return False
        
        return True
    
    def get_fix_branches_from_references(self, cve_data: Dict[str, Any]) -> List[str]:
        """
        Extract which stable branches have fixes from git references.
        
        Analyzes git.kernel.org/stable/c/ URLs to determine backport coverage.
        """
        commits = set()
        
        for ref in cve_data.get("references", []):
            url = ref.get("url", "")
            
            # Extract commit from git.kernel.org/stable/c/ URLs
            match = re.search(r"git\.kernel\.org/stable/c/([a-f0-9]{40})", url)
            if match:
                commits.add(match.group(1))
            
            # Extract from torvalds/linux commit URLs (mainline)
            match = re.search(r"torvalds/linux/commit/([a-f0-9]{40})", url)
            if match:
                commits.add(match.group(1))
            
            # lore.kernel.org references
            if "lore.kernel.org" in url:
                commits.add("lore_ref")
        
        # Heuristic: commit count indicates backport depth
        # More commits = more stable branches have the fix
        branches = []
        commit_count = len(commits)
        
        if commit_count >= 7:
            branches = ["5.10", "5.15", "6.1", "6.6", "6.11", "6.12"]
        elif commit_count >= 6:
            branches = ["5.15", "6.1", "6.6", "6.11", "6.12"]
        elif commit_count >= 5:
            branches = ["6.1", "6.6", "6.11", "6.12"]
        elif commit_count >= 4:
            branches = ["6.6", "6.11", "6.12"]
        elif commit_count >= 3:
            branches = ["6.11", "6.12"]
        elif commit_count >= 2:
            branches = ["6.12"]
        elif commit_count >= 1:
            # Single commit - likely mainline only
            branches = []
        
        return branches
    
    def analyze_cve(
        self,
        cve_id: str,
        target_kernel: str,
        current_version: str,
    ) -> GapAnalysisResult:
        """
        Analyze a single CVE for backport gaps using local cache.
        
        Args:
            cve_id: CVE identifier
            target_kernel: Target kernel series (e.g., "6.1")
            current_version: Current Photon kernel version (e.g., "6.1.159")
        
        Returns:
            GapAnalysisResult with analysis
        """
        # Get CVE data from local cache
        cve_data = self.feed_cache.get_cve(cve_id)
        
        if not cve_data:
            return GapAnalysisResult(
                cve_id=cve_id,
                status="not_in_cache",
                target_kernel=target_kernel,
                current_version=current_version,
            )
        
        # Parse affected versions
        affected_ranges = self.parse_affected_versions(cve_data)
        
        if not affected_ranges:
            return GapAnalysisResult(
                cve_id=cve_id,
                status="no_version_info",
                target_kernel=target_kernel,
                current_version=current_version,
            )
        
        # Check if target kernel is affected
        is_affected = False
        for start, end, start_inc, end_exc in affected_ranges:
            if self.is_version_in_range(current_version, start, end, start_inc, end_exc):
                is_affected = True
                break
        
        if not is_affected:
            return GapAnalysisResult(
                cve_id=cve_id,
                status="not_affected",
                target_kernel=target_kernel,
                current_version=current_version,
                is_affected=False,
            )
        
        # Get branches with fixes
        fix_branches = self.get_fix_branches_from_references(cve_data)
        
        # Check if target kernel has a fix
        has_fix = target_kernel in fix_branches
        
        # Extract severity and CVSS
        cvss_score = 0.0
        severity = Severity.UNKNOWN
        
        metrics = cve_data.get("metrics", {})
        for metric_key in ["cvssMetricV31", "cvssMetricV30", "cvssMetricV2"]:
            metric_list = metrics.get(metric_key, [])
            if metric_list:
                cvss_data = metric_list[0].get("cvssData", {})
                cvss_score = cvss_data.get("baseScore", 0.0)
                sev_str = cvss_data.get("baseSeverity", "UNKNOWN")
                try:
                    severity = Severity(sev_str.upper())
                except ValueError:
                    severity = Severity.from_cvss(cvss_score)
                break
        
        # Extract description
        descriptions = cve_data.get("descriptions", [])
        description = ""
        for desc in descriptions:
            if desc.get("lang") == "en":
                description = desc.get("value", "")[:200]
                break
        
        # Extract fix commits
        fix_commits = []
        for ref in cve_data.get("references", []):
            url = ref.get("url", "")
            match = re.search(r"/([a-f0-9]{40})", url)
            if match:
                fix_commits.append(match.group(1))
        
        return GapAnalysisResult(
            cve_id=cve_id,
            status="has_backport" if has_fix else "gap_detected",
            severity=severity,
            cvss_score=cvss_score,
            target_kernel=target_kernel,
            current_version=current_version,
            is_affected=True,
            fix_branches=fix_branches,
            missing_backports=[target_kernel] if not has_fix else [],
            requires_manual_backport=not has_fix,
            description=description,
        )
    
    def run_detection(
        self,
        kernel_version: str,
        current_version: str,
        cve_ids: Optional[List[str]] = None,
        progress_callback: Optional[callable] = None,
    ) -> GapReport:
        """
        Run gap detection for CVEs using local feed cache.
        
        Args:
            kernel_version: Target kernel series
            current_version: Current Photon kernel version
            cve_ids: List of CVE IDs to analyze (None = all kernel.org CVEs)
            progress_callback: Optional callback(processed, total, cve_id)
        
        Returns:
            GapReport with all results
        """
        logger.info(f"Running gap detection for kernel {kernel_version}")
        logger.info(f"Current version: {current_version}")
        
        # Update and load feed cache
        self.feed_cache.update_feeds()
        self.feed_cache.load_index()
        
        # Get CVE list
        if cve_ids is None:
            # Default: all kernel.org CVEs
            cve_ids = self.feed_cache.filter_by_source(self.config.kernel_org_cna)
            logger.info(f"Found {len(cve_ids)} kernel.org CVEs in feed cache")
        else:
            # Filter to valid CVE format
            cve_ids = [cve for cve in cve_ids if re.match(r"^CVE-\d{4}-\d+$", cve)]
            logger.info(f"Analyzing {len(cve_ids)} specified CVEs")
        
        report = GapReport(
            kernel_version=kernel_version,
            photon_version=current_version,
        )
        
        if not cve_ids:
            return report
        
        total = len(cve_ids)
        
        # Analyze all CVEs (fast - no network calls)
        for i, cve_id in enumerate(cve_ids, 1):
            if progress_callback and (i % 100 == 0 or i == total):
                progress_callback(i, total, cve_id)
            
            result = self.analyze_cve(cve_id, kernel_version, current_version)
            
            report.summary.total_cves_analyzed += 1
            
            if result.status == "gap_detected":
                report.gaps.append(result)
                report.summary.cves_with_gaps += 1
            elif result.status == "has_backport":
                report.patchable.append(result)
                report.summary.cves_patchable += 1
            elif result.status == "not_affected":
                report.not_affected.append(result)
                report.summary.cves_not_affected += 1
            elif result.status == "no_version_info":
                report.no_version_info.append(cve_id)
        
        # Sort gaps by severity
        severity_order = {"CRITICAL": 0, "HIGH": 1, "MEDIUM": 2, "LOW": 3, "UNKNOWN": 4}
        report.gaps.sort(key=lambda x: (severity_order.get(x.severity.value, 5), -x.cvss_score))
        
        logger.info(f"Gap detection complete:")
        logger.info(f"  Gaps found: {report.summary.cves_with_gaps}")
        logger.info(f"  Patchable: {report.summary.cves_patchable}")
        logger.info(f"  Not affected: {report.summary.cves_not_affected}")
        logger.info(f"  No version info: {len(report.no_version_info)}")
        
        return report


def run_gap_detection(
    kernel_version: str,
    current_version: str,
    cve_ids: Optional[List[str]],
    report_dir: Path,
    config: Optional[KernelConfig] = None,
    progress_callback: Optional[callable] = None,
) -> Path:
    """
    Run gap detection and save reports.
    
    Args:
        kernel_version: Target kernel series
        current_version: Current Photon kernel version
        cve_ids: List of CVE IDs to analyze (None = all kernel.org CVEs)
        report_dir: Directory for output reports
        config: Optional configuration
        progress_callback: Optional callback(processed, total, cve_id)
    
    Returns:
        Path to JSON report file
    """
    detector = GapDetector(config)
    report = detector.run_detection(
        kernel_version, current_version, cve_ids, progress_callback
    )
    
    # Generate report paths
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    json_path = report_dir / f"gap_report_{kernel_version}_{timestamp}.json"
    text_path = report_dir / f"gap_report_{kernel_version}_{timestamp}.txt"
    
    # Save reports
    report_dir.mkdir(parents=True, exist_ok=True)
    report.save_json(json_path)
    report.save_text(text_path)
    
    return json_path


def quick_gap_check(
    cve_id: str,
    target_kernel: str,
    current_version: str,
    config: Optional[KernelConfig] = None,
) -> str:
    """
    Quick gap check for a single CVE.
    
    Returns:
        "gap" if no backport, "ok" if backport exists, "na" if not affected, "unknown" otherwise
    """
    detector = GapDetector(config)
    detector.feed_cache.update_feeds()
    detector.feed_cache.load_index()
    
    result = detector.analyze_cve(cve_id, target_kernel, current_version)
    
    if result.status == "gap_detected":
        return "gap"
    elif result.status == "has_backport":
        return "ok"
    elif result.status == "not_affected":
        return "na"
    return "unknown"


# CLI helper for testing
if __name__ == "__main__":
    import sys
    
    def progress(processed, total, cve_id):
        print(f"\r[{processed}/{total}] Processing...", end="", flush=True)
    
    if len(sys.argv) < 3:
        print("Usage: python -m kernelpatches.cve_gap_detection <kernel> <version> [cve_file]")
        print("Example: python -m kernelpatches.cve_gap_detection 5.10 5.10.220")
        print("         python -m kernelpatches.cve_gap_detection 5.10 5.10.220 cves.txt")
        sys.exit(1)
    
    kernel = sys.argv[1]
    version = sys.argv[2]
    
    cves = None
    if len(sys.argv) > 3:
        cve_file = Path(sys.argv[3])
        cves = [line.strip().split("|")[0] for line in cve_file.read_text().splitlines() if line.strip()]
        print(f"Analyzing {len(cves)} CVEs from file")
    else:
        print("Analyzing all kernel.org CVEs from NVD feeds")
    
    print(f"Target: kernel {kernel} (version {version})")
    print()
    
    report_path = run_gap_detection(
        kernel, version, cves,
        Path("/tmp/gap_reports"),
        progress_callback=progress,
    )
    
    print(f"\n\nReport saved to: {report_path}")
