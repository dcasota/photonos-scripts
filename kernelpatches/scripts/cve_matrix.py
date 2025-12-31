"""
CVE Coverage Matrix - Track CVE status across multiple kernel versions.

Provides a comprehensive view of CVE coverage including:
- CVE ID and CVSS score (numeric 1.0-10.0)
- Severity level
- Per kernel version, per stable patch: CVE state tracking
- Reference weblinks
- Photon OS current version vs latest stable comparison

CVE States per stable patch per kernel version:
- cve_not_applicable: CVE doesn't affect this kernel version
- cve_included: CVE fix is included in Photon's current stable version
- cve_in_newer_stable: CVE fix exists in a newer stable patch (upgrade available)
- cve_patch_available: CVE has a patch (in spec file) but not in any stable patch
- cve_patch_missing: CVE affects this kernel but no patch exists (gap)
"""

import csv
import json
import re
from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from pathlib import Path
from typing import Any, Dict, List, Optional, Set, Tuple

from rich.console import Console
from rich.table import Table

from scripts.common import extract_cve_ids, logger
from scripts.config import DEFAULT_CONFIG, KERNEL_MAPPINGS, KernelConfig, SUPPORTED_KERNELS
from scripts.models import CVE, CVESource, Severity
from scripts.spec_file import SpecFile


class CVEPatchState(str, Enum):
    """
    CVE patch state for a specific stable patch version.
    
    Five possible states:
    - CVE_NOT_APPLICABLE: CVE doesn't affect this kernel version
    - CVE_INCLUDED: CVE fix is included in Photon's current stable version
    - CVE_IN_NEWER_STABLE: CVE fix exists in a newer stable patch (upgrade available)
    - CVE_PATCH_AVAILABLE: CVE patch exists (in spec file) but not in any stable patch
    - CVE_PATCH_MISSING: CVE affects kernel but no patch exists anywhere (gap)
    """
    CVE_NOT_APPLICABLE = "cve_not_applicable"
    CVE_INCLUDED = "cve_included"
    CVE_IN_NEWER_STABLE = "cve_in_newer_stable"
    CVE_PATCH_AVAILABLE = "cve_patch_available"
    CVE_PATCH_MISSING = "cve_patch_missing"


# Legacy status for backward compatibility
class CVEStatus:
    """CVE status constants (legacy)."""
    FIXED = "fixed"
    PENDING = "pending"
    NOT_AFFECTED = "not_affected"
    NEEDS_BACKPORT = "needs_backport"
    UNKNOWN = "unknown"


@dataclass
class CVEPatchInfo:
    """
    Information about a CVE's patch state for a specific kernel/patch combination.
    """
    cve_id: str
    state: CVEPatchState
    stable_patch: Optional[str] = None  # Which stable patch includes the fix (if any)
    spec_patch: Optional[str] = None  # Spec patch reference (if manually added)
    fix_commit: Optional[str] = None  # Commit SHA
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "cve_id": self.cve_id,
            "state": self.state.value,
            "stable_patch": self.stable_patch,
            "spec_patch": self.spec_patch,
            "fix_commit": self.fix_commit,
        }


@dataclass
class StablePatchCVECoverage:
    """
    CVE coverage for a specific stable patch version.
    
    Tracks all five states for each CVE at this stable patch version:
    - not_applicable: CVEs that don't affect this kernel
    - included: CVEs fixed in Photon's current stable version
    - cve_in_newer_stable: CVEs fixed in newer stable patches (upgrade available)
    - cve_patch_available: CVEs with patches in spec file but not in stable
    - cve_patch_missing: CVEs with no CVE patch anywhere (gaps)
    """
    patch_version: str  # e.g., "6.1.155"
    kernel_series: str  # e.g., "6.1"
    
    # CVEs in each state
    not_applicable: List[str] = field(default_factory=list)
    included: List[str] = field(default_factory=list)
    cve_in_newer_stable: List[str] = field(default_factory=list)
    cve_patch_available: List[str] = field(default_factory=list)
    cve_patch_missing: List[str] = field(default_factory=list)
    
    release_date: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "stable_patch_version": self.patch_version,
            "kernel_series": self.kernel_series,
            "cve_not_applicable": self.not_applicable,
            "cve_not_applicable_count": len(self.not_applicable),
            "cve_included": self.included,
            "cve_included_count": len(self.included),
            "cve_in_newer_stable": self.cve_in_newer_stable,
            "cve_in_newer_stable_count": len(self.cve_in_newer_stable),
            "cve_patch_available": self.cve_patch_available,
            "cve_patch_available_count": len(self.cve_patch_available),
            "cve_patch_missing": self.cve_patch_missing,
            "cve_patch_missing_count": len(self.cve_patch_missing),
            "total_applicable": self.total_applicable,
            "coverage_percent": self.coverage_percent,
            "release_date": self.release_date,
        }
    
    @property
    def total_applicable(self) -> int:
        """Total CVEs that apply to this kernel (excludes not_applicable)."""
        return (len(self.included) + len(self.cve_in_newer_stable) + 
                len(self.cve_patch_available) + len(self.cve_patch_missing))
    
    @property
    def total_with_patch(self) -> int:
        """CVEs that have a patch (included + in_newer_stable + patch_available)."""
        return len(self.included) + len(self.cve_in_newer_stable) + len(self.cve_patch_available)
    
    @property
    def coverage_percent(self) -> float:
        """Percentage of applicable CVEs that are included in current Photon version."""
        if self.total_applicable == 0:
            return 100.0
        return round(len(self.included) / self.total_applicable * 100, 1)
    
    @property
    def gap_count(self) -> int:
        """Number of CVEs missing patches (true gaps)."""
        return len(self.cve_patch_missing)
    
    @property
    def upgrade_available_count(self) -> int:
        """Number of CVEs that would be fixed by upgrading to latest stable."""
        return len(self.cve_in_newer_stable)
    
    def get_state(self, cve_id: str) -> CVEPatchState:
        """Get the state of a specific CVE at this stable patch version."""
        if cve_id in self.not_applicable:
            return CVEPatchState.CVE_NOT_APPLICABLE
        elif cve_id in self.included:
            return CVEPatchState.CVE_INCLUDED
        elif cve_id in self.cve_in_newer_stable:
            return CVEPatchState.CVE_IN_NEWER_STABLE
        elif cve_id in self.cve_patch_available:
            return CVEPatchState.CVE_PATCH_AVAILABLE
        elif cve_id in self.cve_patch_missing:
            return CVEPatchState.CVE_PATCH_MISSING
        return CVEPatchState.CVE_PATCH_MISSING  # Default to missing if not tracked


@dataclass
class KernelVersionCoverage:
    """
    Complete CVE coverage for a kernel version across all its stable patches.
    
    Tracks Photon's current version vs latest available stable version.
    """
    kernel_version: str  # e.g., "6.1"
    photon_version: str  # Photon's current version from spec, e.g., "6.1.159"
    latest_stable: str   # Latest available from kernel.org, e.g., "6.1.163"
    
    # Coverage per stable patch version
    stable_patches: List[StablePatchCVECoverage] = field(default_factory=list)
    
    # Summary totals (at Photon's current version)
    total_not_applicable: int = 0
    total_included: int = 0
    total_cve_in_newer_stable: int = 0
    total_cve_patch_available: int = 0
    total_cve_patch_missing: int = 0
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "kernel_version": self.kernel_version,
            "photon_version": self.photon_version,
            "latest_stable": self.latest_stable,
            "upgrade_available": self.photon_version != self.latest_stable,
            "stable_patches": [sp.to_dict() for sp in self.stable_patches],
            "summary": {
                "cve_not_applicable": self.total_not_applicable,
                "cve_included": self.total_included,
                "cve_in_newer_stable": self.total_cve_in_newer_stable,
                "cve_patch_available": self.total_cve_patch_available,
                "cve_patch_missing": self.total_cve_patch_missing,
                "total_applicable": self.total_applicable,
                "coverage_percent": self.coverage_percent,
                "upgrade_would_fix": self.total_cve_in_newer_stable,
            },
        }
    
    @property
    def total_applicable(self) -> int:
        """Total CVEs that apply to this kernel."""
        return (self.total_included + self.total_cve_in_newer_stable + 
                self.total_cve_patch_available + self.total_cve_patch_missing)
    
    @property
    def total_with_patch(self) -> int:
        """CVEs that have a patch somewhere (included or available)."""
        return self.total_included + self.total_cve_in_newer_stable + self.total_cve_patch_available
    
    @property
    def coverage_percent(self) -> float:
        """Percentage of applicable CVEs included in Photon's current version."""
        if self.total_applicable == 0:
            return 100.0
        return round(self.total_included / self.total_applicable * 100, 1)
    
    @property
    def potential_coverage_percent(self) -> float:
        """Coverage if upgraded to latest stable."""
        if self.total_applicable == 0:
            return 100.0
        return round((self.total_included + self.total_cve_in_newer_stable) / self.total_applicable * 100, 1)
    
    def get_patch_coverage(self, patch_version: str) -> Optional[StablePatchCVECoverage]:
        """Get coverage for a specific stable patch."""
        for sp in self.stable_patches:
            if sp.patch_version == patch_version:
                return sp
        return None


@dataclass
class KernelCVEStatus:
    """CVE status for a specific kernel version (summary view)."""
    state: CVEPatchState
    stable_patch: Optional[str] = None  # Patch version where fix is included
    spec_patch: Optional[str] = None  # Spec patch if manually added
    fix_commit: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        return {
            "state": self.state.value,
            "stable_patch": self.stable_patch,
            "spec_patch": self.spec_patch,
            "fix_commit": self.fix_commit,
        }
    
    @property
    def has_patch(self) -> bool:
        """Returns True if this CVE has a patch."""
        return self.state in (CVEPatchState.CVE_INCLUDED, CVEPatchState.CVE_PATCH_AVAILABLE)
    
    @property
    def is_gap(self) -> bool:
        """Returns True if this CVE is a gap (needs patch but none exists)."""
        return self.state == CVEPatchState.CVE_PATCH_MISSING


@dataclass
class MatrixEntry:
    """Entry in the CVE coverage matrix with all details."""
    cve_id: str
    cvss_score: float  # Numeric score 1.0-10.0
    severity: str  # CRITICAL, HIGH, MEDIUM, LOW
    description: str
    references: List[str]
    kernel_status: Dict[str, KernelCVEStatus]  # kernel_version -> status
    fix_commits: List[str] = field(default_factory=list)
    published_date: Optional[str] = None
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert to dictionary."""
        return {
            "cve_id": self.cve_id,
            "cvss_score": self.cvss_score,
            "severity": self.severity,
            "description": self.description,
            "references": self.references,
            "kernel_status": {
                kv: status.to_dict() for kv, status in self.kernel_status.items()
            },
            "fix_commits": self.fix_commits,
            "published_date": self.published_date,
        }
    
    def get_state(self, kernel_version: str) -> CVEPatchState:
        """Get patch state for a kernel version."""
        if kernel_version in self.kernel_status:
            return self.kernel_status[kernel_version].state
        return CVEPatchState.CVE_PATCH_MISSING
    
    def get_stable_patch(self, kernel_version: str) -> Optional[str]:
        """Get stable patch version that includes the fix."""
        if kernel_version in self.kernel_status:
            return self.kernel_status[kernel_version].stable_patch
        return None
    
    def has_patch_for_kernel(self, kernel_version: str) -> bool:
        """Check if this CVE has a patch for the given kernel."""
        if kernel_version in self.kernel_status:
            return self.kernel_status[kernel_version].has_patch
        return False
    
    def is_gap_for_kernel(self, kernel_version: str) -> bool:
        """Check if this CVE is a gap for the given kernel."""
        if kernel_version in self.kernel_status:
            return self.kernel_status[kernel_version].is_gap
        return True
    
    @classmethod
    def from_cve(
        cls,
        cve: CVE,
        kernel_versions: List[str],
        status_map: Optional[Dict[str, KernelCVEStatus]] = None,
    ) -> "MatrixEntry":
        """Create MatrixEntry from CVE object."""
        status_map = status_map or {}
        kernel_status = {
            kv: status_map.get(kv, KernelCVEStatus(state=CVEPatchState.CVE_PATCH_MISSING))
            for kv in kernel_versions
        }
        
        return cls(
            cve_id=cve.cve_id,
            cvss_score=cve.cvss_score,
            severity=cve.severity.value,
            description=cve.description[:300] if cve.description else "",
            references=[ref.url for ref in cve.references[:5]],
            kernel_status=kernel_status,
            fix_commits=cve.fix_commits,
            published_date=cve.published_date.isoformat() if cve.published_date else None,
        )


@dataclass
class CVECoverageMatrix:
    """
    Complete CVE coverage matrix across kernel versions.
    
    Tracks four states for each CVE per kernel version per stable patch:
    - not_applicable: CVE doesn't affect this kernel
    - included: Fix included in stable patch
    - cve_patch_available: CVE patch exists elsewhere
    - cve_patch_missing: No CVE patch exists (gap)
    """
    kernel_versions: List[str]
    entries: List[MatrixEntry]
    
    # Per-kernel coverage with patch-level detail
    kernel_coverage: Dict[str, KernelVersionCoverage] = field(default_factory=dict)
    
    generated: datetime = field(default_factory=datetime.now)
    source: str = "nvd"
    
    @property
    def total_cves(self) -> int:
        """Total number of CVEs in matrix."""
        return len(self.entries)
    
    def get_by_severity(self, severity: str) -> List[MatrixEntry]:
        """Get entries by severity level."""
        return [e for e in self.entries if e.severity == severity]
    
    def get_by_state(self, kernel_version: str, state: CVEPatchState) -> List[MatrixEntry]:
        """Get entries by state for a specific kernel."""
        return [e for e in self.entries if e.get_state(kernel_version) == state]
    
    def get_included(self, kernel_version: str) -> List[MatrixEntry]:
        """Get CVEs with fix included for kernel."""
        return self.get_by_state(kernel_version, CVEPatchState.CVE_INCLUDED)
    
    def get_cve_in_newer_stable(self, kernel_version: str) -> List[MatrixEntry]:
        """Get CVEs fixed in newer stable patches (upgrade available)."""
        return self.get_by_state(kernel_version, CVEPatchState.CVE_IN_NEWER_STABLE)
    
    def get_cve_patch_available(self, kernel_version: str) -> List[MatrixEntry]:
        """Get CVEs with patch available in spec but not in stable."""
        return self.get_by_state(kernel_version, CVEPatchState.CVE_PATCH_AVAILABLE)
    
    def get_cve_patch_missing(self, kernel_version: str) -> List[MatrixEntry]:
        """Get CVEs with no patch (gaps)."""
        return self.get_by_state(kernel_version, CVEPatchState.CVE_PATCH_MISSING)
    
    def get_not_applicable(self, kernel_version: str) -> List[MatrixEntry]:
        """Get CVEs not applicable to kernel."""
        return self.get_by_state(kernel_version, CVEPatchState.CVE_NOT_APPLICABLE)
    
    def get_patch_coverage(
        self, kernel_version: str, patch_version: str
    ) -> Optional[StablePatchCVECoverage]:
        """Get coverage details for a specific stable patch."""
        if kernel_version in self.kernel_coverage:
            return self.kernel_coverage[kernel_version].get_patch_coverage(patch_version)
        return None
    
    def get_critical_gaps(self) -> List[MatrixEntry]:
        """Get CRITICAL/HIGH severity CVEs that are gaps in any kernel."""
        gaps = []
        for entry in self.entries:
            if entry.severity in ("CRITICAL", "HIGH"):
                for kv in self.kernel_versions:
                    if entry.is_gap_for_kernel(kv):
                        gaps.append(entry)
                        break
        return gaps
    
    def summary(self) -> Dict[str, Dict[str, Any]]:
        """Generate summary statistics per kernel version with Photon version info."""
        result = {}
        for kv in self.kernel_versions:
            # Get version info from kernel_coverage
            kc = self.kernel_coverage.get(kv)
            photon_ver = kc.photon_version if kc else f"{kv}.0"
            latest_stable = kc.latest_stable if kc else f"{kv}.0"
            
            result[kv] = {
                "photon_version": photon_ver,
                "latest_stable": latest_stable,
                "upgrade_available": photon_ver != latest_stable,
                "cve_not_applicable": len(self.get_not_applicable(kv)),
                "cve_included": len(self.get_included(kv)),
                "cve_in_newer_stable": len(self.get_cve_in_newer_stable(kv)),
                "cve_patch_available": len(self.get_cve_patch_available(kv)),
                "cve_patch_missing": len(self.get_cve_patch_missing(kv)),
            }
            # Calculate totals
            result[kv]["total_applicable"] = (
                result[kv]["cve_included"] + 
                result[kv]["cve_in_newer_stable"] +
                result[kv]["cve_patch_available"] + 
                result[kv]["cve_patch_missing"]
            )
            result[kv]["total_with_patch"] = (
                result[kv]["cve_included"] + 
                result[kv]["cve_in_newer_stable"] + 
                result[kv]["cve_patch_available"]
            )
            total = result[kv]["total_applicable"]
            # Coverage = CVEs included in Photon's current version
            result[kv]["coverage_percent"] = (
                round(result[kv]["cve_included"] / total * 100, 1) if total > 0 else 100.0
            )
            # Potential coverage if upgraded to latest stable
            result[kv]["potential_coverage_percent"] = (
                round((result[kv]["cve_included"] + result[kv]["cve_in_newer_stable"]) / total * 100, 1) 
                if total > 0 else 100.0
            )
        return result
    
    def severity_summary(self) -> Dict[str, int]:
        """Summary by severity level."""
        result = {"CRITICAL": 0, "HIGH": 0, "MEDIUM": 0, "LOW": 0, "UNKNOWN": 0}
        for entry in self.entries:
            sev = entry.severity if entry.severity in result else "UNKNOWN"
            result[sev] += 1
        return result
    
    def stable_patch_summary(self) -> Dict[str, List[Dict[str, Any]]]:
        """Summary per stable patch per kernel with all five states."""
        result = {}
        for kv in self.kernel_versions:
            result[kv] = []
            if kv in self.kernel_coverage:
                for sp in self.kernel_coverage[kv].stable_patches:
                    result[kv].append({
                        "stable_patch_version": sp.patch_version,
                        "cve_not_applicable": len(sp.not_applicable),
                        "cve_included": len(sp.included),
                        "cve_in_newer_stable": len(sp.cve_in_newer_stable),
                        "cve_patch_available": len(sp.cve_patch_available),
                        "cve_patch_missing": len(sp.cve_patch_missing),
                        "coverage_percent": sp.coverage_percent,
                        "upgrade_available_count": sp.upgrade_available_count,
                    })
        return result
    
    def to_dict(self) -> Dict[str, Any]:
        """Convert matrix to dictionary."""
        return {
            "generated": self.generated.isoformat(),
            "source": self.source,
            "kernel_versions": self.kernel_versions,
            "total_cves": self.total_cves,
            "summary": self.summary(),
            "severity_summary": self.severity_summary(),
            "kernel_coverage": {
                kv: cov.to_dict() for kv, cov in self.kernel_coverage.items()
            },
            "entries": [e.to_dict() for e in self.entries],
        }
    
    def save_json(self, output_path: Path) -> None:
        """Save matrix as JSON."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w") as f:
            json.dump(self.to_dict(), f, indent=2)
        logger.info(f"Saved JSON matrix: {output_path}")
    
    def save_csv(self, output_path: Path) -> None:
        """Save matrix as CSV."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        headers = ["CVE ID", "CVSS Score", "Severity", "Description"]
        for kv in self.kernel_versions:
            headers.extend([f"State ({kv})", f"Stable Patch ({kv})"])
        headers.extend(["References", "Fix Commits", "Published"])
        
        with open(output_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(headers)
            
            for entry in self.entries:
                row = [
                    entry.cve_id,
                    f"{entry.cvss_score:.1f}",
                    entry.severity,
                    entry.description[:100],
                ]
                for kv in self.kernel_versions:
                    status = entry.kernel_status.get(
                        kv, KernelCVEStatus(state=CVEPatchState.CVE_PATCH_MISSING)
                    )
                    row.append(status.state.value)
                    row.append(status.stable_patch or status.spec_patch or "")
                row.append("; ".join(entry.references[:3]))
                row.append("; ".join(entry.fix_commits[:3]))
                row.append(entry.published_date or "")
                
                writer.writerow(row)
        
        logger.info(f"Saved CSV matrix: {output_path}")
    
    def save_stable_patch_csv(self, output_path: Path) -> None:
        """Save stable patch -> CVE mapping with all four states."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        with open(output_path, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow([
                "Kernel", "Stable Patch Version",
                "CVE N/A", "CVE Included", "CVE In Newer Stable", "CVE Spec Patch", "CVE Patch Missing",
                "Coverage %",
                "CVE Included List", "CVE Missing List"
            ])
            
            for kv in self.kernel_versions:
                if kv in self.kernel_coverage:
                    for sp in self.kernel_coverage[kv].stable_patches:
                        writer.writerow([
                            sp.kernel_series,
                            sp.patch_version,
                            len(sp.not_applicable),
                            len(sp.included),
                            len(sp.cve_in_newer_stable),
                            len(sp.cve_patch_available),
                            len(sp.cve_patch_missing),
                            f"{sp.coverage_percent:.1f}%",
                            "; ".join(sp.included[:5]) + ("..." if len(sp.included) > 5 else ""),
                            "; ".join(sp.cve_patch_missing[:5]) + ("..." if len(sp.cve_patch_missing) > 5 else ""),
                        ])
        
        logger.info(f"Saved stable patch CSV: {output_path}")
    
    def save_markdown(self, output_path: Path) -> None:
        """Save matrix as Markdown with all five states including Photon version info."""
        output_path.parent.mkdir(parents=True, exist_ok=True)
        
        lines = [
            "# CVE Coverage Matrix",
            "",
            f"Generated: {self.generated.strftime('%Y-%m-%d %H:%M:%S')}",
            f"Source: {self.source}",
            f"Total CVEs: {self.total_cves}",
            "",
            "## CVE States",
            "",
            "| State | Description |",
            "|-------|-------------|",
            "| cve_not_applicable | CVE doesn't affect this kernel version |",
            "| cve_included | CVE fix is included in Photon's current stable version |",
            "| cve_in_newer_stable | CVE fix exists in a newer stable patch (upgrade available) |",
            "| cve_patch_available | CVE patch exists in spec file but not in any stable patch |",
            "| cve_patch_missing | CVE affects kernel but no CVE patch exists (gap) |",
            "",
            "## Coverage Summary",
            "",
        ]
        
        # Summary table with version info
        summary = self.summary()
        lines.append("| Kernel | Photon Version | Latest Stable | CVE Included | In Newer Stable | Spec Patch | Missing | Coverage |")
        lines.append("|--------|----------------|---------------|--------------|-----------------|------------|---------|----------|")
        for kv in self.kernel_versions:
            s = summary[kv]
            upgrade_note = " ⬆️" if s.get('upgrade_available') else ""
            lines.append(
                f"| {kv} | {s['photon_version']} | {s['latest_stable']}{upgrade_note} | "
                f"{s['cve_included']} | {s['cve_in_newer_stable']} | {s['cve_patch_available']} | "
                f"{s['cve_patch_missing']} | {s['coverage_percent']:.1f}% |"
            )
        
        # Upgrade recommendations
        lines.extend(["", "## Upgrade Impact", ""])
        lines.append("| Kernel | Current Coverage | After Upgrade | CVEs Fixed by Upgrade |")
        lines.append("|--------|------------------|---------------|----------------------|")
        for kv in self.kernel_versions:
            s = summary[kv]
            if s.get('upgrade_available') and s['cve_in_newer_stable'] > 0:
                lines.append(
                    f"| {kv} | {s['coverage_percent']:.1f}% | {s['potential_coverage_percent']:.1f}% | "
                    f"{s['cve_in_newer_stable']} |"
                )
        
        # Severity distribution
        lines.extend(["", "## Severity Distribution", ""])
        sev_summary = self.severity_summary()
        lines.append("| Severity | Count |")
        lines.append("|----------|-------|")
        for sev, count in sev_summary.items():
            lines.append(f"| {sev} | {count} |")
        
        # Kernel Version Details
        lines.extend(["", "## Kernel Version Details", ""])
        
        for kv in self.kernel_versions:
            if kv in self.kernel_coverage:
                kc = self.kernel_coverage[kv]
                lines.append(f"### Kernel {kv}")
                lines.append("")
                lines.append(f"- **Photon Version:** {kc.photon_version}")
                lines.append(f"- **Latest Stable:** {kc.latest_stable}")
                if kc.photon_version != kc.latest_stable:
                    lines.append(f"- **Upgrade Available:** Yes ({kc.total_cve_in_newer_stable} CVEs would be fixed)")
                lines.append("")
                
                lines.append("| Metric | Count |")
                lines.append("|--------|-------|")
                lines.append(f"| CVE Included | {kc.total_included} |")
                lines.append(f"| In Newer Stable | {kc.total_cve_in_newer_stable} |")
                lines.append(f"| Spec Patch Only | {kc.total_cve_patch_available} |")
                lines.append(f"| Missing (Gap) | {kc.total_cve_patch_missing} |")
                lines.append("")
        # CVE Details table
        lines.extend(["", "## CVE Details", ""])
        
        header = "| CVE ID | CVSS | Severity |"
        for kv in self.kernel_versions:
            header += f" {kv} | Patch |"
        lines.append(header)
        
        sep = "|--------|------|----------|"
        for _ in self.kernel_versions:
            sep += "------|-------|"
        lines.append(sep)
        
        # State icons
        state_icons = {
            CVEPatchState.CVE_NOT_APPLICABLE: "➖",
            CVEPatchState.CVE_INCLUDED: "✅",
            CVEPatchState.CVE_IN_NEWER_STABLE: "⬆️",
            CVEPatchState.CVE_PATCH_AVAILABLE: "🔄",
            CVEPatchState.CVE_PATCH_MISSING: "❌",
        }
        
        sorted_entries = sorted(self.entries, key=lambda e: e.cvss_score, reverse=True)
        
        for entry in sorted_entries[:100]:
            row = f"| {entry.cve_id} | {entry.cvss_score:.1f} | {entry.severity} |"
            
            for kv in self.kernel_versions:
                status = entry.kernel_status.get(
                    kv, KernelCVEStatus(state=CVEPatchState.CVE_PATCH_MISSING)
                )
                icon = state_icons.get(status.state, "❓")
                patch = status.stable_patch or status.spec_patch or "-"
                if len(str(patch)) > 10:
                    patch = str(patch)[:10] + "..."
                row += f" {icon} | {patch} |"
            
            lines.append(row)
        
        if len(self.entries) > 100:
            lines.append(f"\n*... and {len(self.entries) - 100} more CVEs*")
        
        # Legend
        lines.extend([
            "",
            "## Legend",
            "",
            "- ➖ CVE N/A - CVE doesn't affect this kernel",
            "- ✅ CVE Included - Fix included in Photon's current stable version",
            "- ⬆️ In Newer Stable - Fix available by upgrading to latest stable",
            "- 🔄 Spec Patch - CVE patch exists in spec file but not in stable",
            "- ❌ CVE Patch Missing - No CVE patch exists (gap)",
        ])
        
        with open(output_path, "w") as f:
            f.write("\n".join(lines))
        
        logger.info(f"Saved Markdown matrix: {output_path}")
    
    def print_table(self, console: Optional[Console] = None, max_rows: int = 50) -> None:
        """Print matrix as rich table to console."""
        if console is None:
            console = Console()
        
        # Coverage summary with Photon version info
        console.print("\n[bold]CVE Coverage Summary (5 States):[/bold]")
        summary = self.summary()
        for kv in self.kernel_versions:
            s = summary[kv]
            upgrade_note = f" [cyan]→ {s['latest_stable']}[/cyan]" if s.get('upgrade_available') else ""
            console.print(
                f"  Kernel {kv} ({s['photon_version']}{upgrade_note}): "
                f"[green]Included: {s['cve_included']}[/green], "
                f"[cyan]In Newer: {s['cve_in_newer_stable']}[/cyan], "
                f"[yellow]Spec Patch: {s['cve_patch_available']}[/yellow], "
                f"[red]Missing: {s['cve_patch_missing']}[/red] "
                f"([bold]{s['coverage_percent']:.1f}%[/bold])"
            )
        
        # Main table
        table = Table(title="\nCVE Coverage Matrix", show_header=True, header_style="bold")
        
        table.add_column("CVE ID", style="cyan")
        table.add_column("CVSS", justify="right")
        table.add_column("Severity")
        
        for kv in self.kernel_versions:
            table.add_column(f"{kv}", justify="center")
            table.add_column("Patch", style="dim")
        
        severity_colors = {
            "CRITICAL": "red",
            "HIGH": "orange1",
            "MEDIUM": "yellow",
            "LOW": "green",
            "UNKNOWN": "grey50",
        }
        
        state_symbols = {
            CVEPatchState.CVE_NOT_APPLICABLE: "[grey50]—[/grey50]",
            CVEPatchState.CVE_INCLUDED: "[green]✓[/green]",
            CVEPatchState.CVE_IN_NEWER_STABLE: "[cyan]⬆[/cyan]",
            CVEPatchState.CVE_PATCH_AVAILABLE: "[yellow]○[/yellow]",
            CVEPatchState.CVE_PATCH_MISSING: "[red]✗[/red]",
        }
        
        sorted_entries = sorted(self.entries, key=lambda e: e.cvss_score, reverse=True)
        
        for entry in sorted_entries[:max_rows]:
            sev_color = severity_colors.get(entry.severity, "white")
            
            row = [
                entry.cve_id,
                f"{entry.cvss_score:.1f}",
                f"[{sev_color}]{entry.severity}[/{sev_color}]",
            ]
            
            for kv in self.kernel_versions:
                status = entry.kernel_status.get(
                    kv, KernelCVEStatus(state=CVEPatchState.CVE_PATCH_MISSING)
                )
                row.append(state_symbols.get(status.state, "?"))
                row.append(status.stable_patch or "-")
            
            table.add_row(*row)
        
        if len(self.entries) > max_rows:
            row = [f"... +{len(self.entries) - max_rows} more", "", ""]
            for _ in self.kernel_versions:
                row.extend(["", ""])
            table.add_row(*row)
        
        console.print(table)
        
        # Legend
        console.print("\n[bold]Legend:[/bold]")
        console.print("  [grey50]—[/grey50] N/A  [green]✓[/green] Included  [cyan]⬆[/cyan] In Newer Stable  [yellow]○[/yellow] Spec Patch  [red]✗[/red] Missing (Gap)")


class StablePatchCVEMapper:
    """Maps stable patches to CVEs with five-state tracking including Photon version awareness."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
    
    def extract_cves_from_patch_file(self, patch_path: Path) -> List[str]:
        """Extract CVE IDs from a patch file."""
        if not patch_path.exists():
            return []
        try:
            content = patch_path.read_text(errors="ignore")
            return extract_cve_ids(content)
        except Exception:
            return []
    
    def _parse_version(self, filename: str) -> Tuple[int, int, int]:
        """Parse patch filename to version tuple for sorting."""
        match = re.search(r"patch-(\d+)\.(\d+)\.(\d+)", filename)
        if match:
            return (int(match.group(1)), int(match.group(2)), int(match.group(3)))
        return (0, 0, 0)
    
    def _version_to_tuple(self, version: str) -> Tuple[int, int, int]:
        """Convert version string to tuple for comparison."""
        parts = version.split(".")
        if len(parts) >= 3:
            try:
                return (int(parts[0]), int(parts[1]), int(parts[2]))
            except ValueError:
                pass
        return (0, 0, 0)
    
    def build_patch_coverage(
        self,
        kernel_version: str,
        patch_dir: Optional[Path],
        all_cves: Dict[str, CVE],  # CVE ID -> CVE object
        spec_cves: Dict[str, str],  # CVE ID -> spec patch
        not_applicable_cves: Set[str],  # CVEs that don't affect this kernel
        photon_version: Optional[str] = None,  # Photon's current version from spec
    ) -> Tuple[List[StablePatchCVECoverage], str, Dict[str, str]]:
        """
        Build coverage for all stable patches with five states.
        
        States are calculated relative to Photon's current version:
        - cve_included: Fixed in Photon's version or earlier
        - cve_in_newer_stable: Fixed in stable patches after Photon's version
        - cve_patch_available: Patch in spec file but not in any stable
        - cve_patch_missing: No patch exists anywhere (gap)
        
        Args:
            kernel_version: Kernel series (e.g., "6.12")
            patch_dir: Directory containing stable patch files
            all_cves: All CVEs to analyze
            spec_cves: CVEs with patches in spec file
            not_applicable_cves: CVEs that don't affect this kernel
            photon_version: Photon's current kernel version (e.g., "6.12.60")
        
        Returns:
            Tuple of (coverage_list, latest_stable, cve_to_first_patch_map)
        """
        result = []
        latest_stable = f"{kernel_version}.0"
        cve_to_first_patch: Dict[str, str] = {}  # CVE ID -> first patch that includes it
        
        all_cve_ids = set(all_cves.keys())
        applicable_cves = all_cve_ids - not_applicable_cves
        
        # Parse Photon version for comparison
        photon_ver_tuple = self._version_to_tuple(photon_version) if photon_version else (0, 0, 0)
        
        # First pass: build cumulative CVE coverage for all patches
        cumulative_included: Set[str] = set()
        patch_cve_map: Dict[str, Set[str]] = {}  # version -> cumulative CVEs at that version
        
        if patch_dir and patch_dir.exists():
            patch_files = sorted(
                [p for p in patch_dir.glob(f"patch-{kernel_version}.*") if p.suffix != ".xz"],
                key=lambda p: self._parse_version(p.name)
            )
            
            for patch_file in patch_files:
                version = patch_file.name.replace("patch-", "")
                latest_stable = version
                
                # CVEs newly fixed in THIS patch
                patch_cves = set(self.extract_cves_from_patch_file(patch_file))
                newly_included = patch_cves - cumulative_included
                
                # Update cumulative
                cumulative_included.update(newly_included)
                patch_cve_map[version] = cumulative_included.copy()
                
                # Track first patch for each CVE
                for cve_id in newly_included:
                    if cve_id not in cve_to_first_patch:
                        cve_to_first_patch[cve_id] = version
        
        # Determine CVEs included in Photon's version
        if photon_version and photon_version in patch_cve_map:
            cves_in_photon = patch_cve_map[photon_version]
        elif photon_version:
            # Find the closest version <= photon_version
            cves_in_photon = set()
            for ver, cves in patch_cve_map.items():
                if self._version_to_tuple(ver) <= photon_ver_tuple:
                    cves_in_photon = cves
        else:
            cves_in_photon = cumulative_included  # Use all if no Photon version specified
        
        # CVEs fixed in newer stable patches (after Photon's version)
        cves_in_newer_stable = cumulative_included - cves_in_photon
        
        # Build coverage for Photon's current version
        # cve_included: Fixed in Photon's current version
        included = list(cves_in_photon & applicable_cves)
        
        # cve_in_newer_stable: Fixed in newer stable patches
        in_newer_stable = list(cves_in_newer_stable & applicable_cves)
        
        # cve_patch_available: Has spec patch but not in any stable
        spec_only_cves = set(spec_cves.keys()) - cumulative_included
        cve_patch_available = list(spec_only_cves & applicable_cves)
        
        # cve_patch_missing: No patch anywhere
        all_patched = cumulative_included | set(spec_cves.keys())
        cve_patch_missing = list(applicable_cves - all_patched)
        
        # Create coverage entry for Photon's current version
        coverage = StablePatchCVECoverage(
            patch_version=photon_version or latest_stable,
            kernel_series=kernel_version,
            not_applicable=list(not_applicable_cves & all_cve_ids),
            included=included,
            cve_in_newer_stable=in_newer_stable,
            cve_patch_available=cve_patch_available,
            cve_patch_missing=cve_patch_missing,
        )
        result.append(coverage)
        
        return result, latest_stable, cve_to_first_patch


class CVEMatrixBuilder:
    """Build CVE coverage matrix with five-state tracking including Photon version awareness."""
    
    def __init__(
        self,
        kernel_versions: Optional[List[str]] = None,
        config: Optional[KernelConfig] = None,
    ):
        self.kernel_versions = kernel_versions or SUPPORTED_KERNELS
        self.config = config or DEFAULT_CONFIG
        self.patch_mapper = StablePatchCVEMapper(config)
    
    def get_photon_version(self, kernel_version: str, repo_dir: Path) -> Optional[str]:
        """Get Photon's current kernel version from spec file."""
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            return None
        
        spec_dir = repo_dir / mapping.spec_dir
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            if spec_path.exists():
                spec = SpecFile(spec_path)
                version = spec.version
                if version:
                    return version
        return None
    
    def get_cves_in_spec(self, spec_path: Path) -> Dict[str, str]:
        """Get CVE IDs in spec file with patch references."""
        if not spec_path.exists():
            return {}
        
        spec = SpecFile(spec_path)
        cve_patches = {}
        
        for patch in spec.get_cve_patches():
            for cve_id in patch.cve_ids:
                cve_patches[cve_id] = f"Patch{patch.number}: {patch.name}"
        
        return cve_patches
    
    def get_all_spec_cves(self, kernel_version: str, repo_dir: Path) -> Dict[str, str]:
        """Get all CVEs in spec files."""
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            return {}
        
        spec_dir = repo_dir / mapping.spec_dir
        all_cves = {}
        
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            all_cves.update(self.get_cves_in_spec(spec_path))
        
        return all_cves
    
    def determine_not_applicable(
        self, cve: CVE, kernel_version: str
    ) -> bool:
        """Determine if CVE is not applicable to kernel version."""
        # Check affected versions from CVE data
        if cve.affected_versions:
            return not any(kernel_version in v for v in cve.affected_versions)
        
        # If no version info, assume it might apply
        return False
    
    def determine_status(
        self,
        cve: CVE,
        kernel_version: str,
        spec_cves: Dict[str, str],
        stable_cve_patch: Dict[str, str],  # CVE ID -> stable patch version
        is_not_applicable: bool,
    ) -> KernelCVEStatus:
        """Determine CVE status with four states."""
        
        if is_not_applicable:
            return KernelCVEStatus(state=CVEPatchState.CVE_NOT_APPLICABLE)
        
        # Check if in spec (manual patch)
        if cve.cve_id in spec_cves:
            return KernelCVEStatus(
                state=CVEPatchState.CVE_INCLUDED,
                spec_patch=spec_cves[cve.cve_id],
            )
        
        # Check if in stable patch
        if cve.cve_id in stable_cve_patch:
            return KernelCVEStatus(
                state=CVEPatchState.CVE_INCLUDED,
                stable_patch=stable_cve_patch[cve.cve_id],
            )
        
        # Check if patch available elsewhere (fix_branches from CVE data)
        if cve.fix_branches and kernel_version in cve.fix_branches:
            return KernelCVEStatus(
                state=CVEPatchState.CVE_PATCH_AVAILABLE,
                fix_commit=cve.fix_commits[0] if cve.fix_commits else None,
            )
        
        # No patch - this is a gap
        return KernelCVEStatus(
            state=CVEPatchState.CVE_PATCH_MISSING,
            fix_commit=cve.fix_commits[0] if cve.fix_commits else None,
        )
    
    def build_from_cves(
        self,
        cves: List[CVE],
        repo_dirs: Optional[Dict[str, Path]] = None,
        patch_dirs: Optional[Dict[str, Path]] = None,
        photon_versions: Optional[Dict[str, str]] = None,  # kernel -> Photon version
    ) -> CVECoverageMatrix:
        """Build matrix from CVE list with five-state tracking.
        
        Args:
            cves: List of CVE objects to analyze
            repo_dirs: Mapping of kernel version to Photon repo directory
            patch_dirs: Mapping of kernel version to stable patch directory
            photon_versions: Mapping of kernel version to Photon's current version
                           (e.g., {"6.12": "6.12.60", "6.1": "6.1.159"})
                           If not provided, will be read from spec files.
        """
        repo_dirs = repo_dirs or {}
        patch_dirs = patch_dirs or {}
        photon_versions = photon_versions or {}
        
        # Index CVEs
        cve_map = {cve.cve_id: cve for cve in cves if cve.cve_id.startswith("CVE-")}
        
        # Build per-kernel data
        kernel_coverage: Dict[str, KernelVersionCoverage] = {}
        kernel_spec_cves: Dict[str, Dict[str, str]] = {}
        kernel_stable_patches: Dict[str, Dict[str, str]] = {}
        kernel_not_applicable: Dict[str, Set[str]] = {}
        
        for kv in self.kernel_versions:
            # Get Photon version from parameter or spec file
            photon_ver = photon_versions.get(kv)
            if not photon_ver and kv in repo_dirs:
                photon_ver = self.get_photon_version(kv, repo_dirs[kv])
            
            # Get spec CVEs
            if kv in repo_dirs:
                kernel_spec_cves[kv] = self.get_all_spec_cves(kv, repo_dirs[kv])
            else:
                kernel_spec_cves[kv] = {}
            
            # Determine not applicable CVEs
            not_applicable = set()
            for cve in cves:
                if cve.cve_id.startswith("CVE-") and self.determine_not_applicable(cve, kv):
                    not_applicable.add(cve.cve_id)
            kernel_not_applicable[kv] = not_applicable
            
            # Build stable patch coverage with Photon version awareness
            patch_dir = patch_dirs.get(kv)
            patches, latest_stable, cve_to_patch = self.patch_mapper.build_patch_coverage(
                kv, patch_dir, cve_map, kernel_spec_cves[kv], not_applicable,
                photon_version=photon_ver,
            )
            kernel_stable_patches[kv] = cve_to_patch
            
            # Calculate totals from the coverage
            if patches:
                coverage_data = patches[0]  # Only one entry now (at Photon version)
                kernel_coverage[kv] = KernelVersionCoverage(
                    kernel_version=kv,
                    photon_version=photon_ver or latest_stable,
                    latest_stable=latest_stable,
                    stable_patches=patches,
                    total_not_applicable=len(coverage_data.not_applicable),
                    total_included=len(coverage_data.included),
                    total_cve_in_newer_stable=len(coverage_data.cve_in_newer_stable),
                    total_cve_patch_available=len(coverage_data.cve_patch_available),
                    total_cve_patch_missing=len(coverage_data.cve_patch_missing),
                )
            else:
                # No patches available
                applicable = set(cve_map.keys()) - not_applicable
                kernel_coverage[kv] = KernelVersionCoverage(
                    kernel_version=kv,
                    photon_version=photon_ver or f"{kv}.0",
                    latest_stable=f"{kv}.0",
                    stable_patches=[],
                    total_not_applicable=len(not_applicable),
                    total_included=0,
                    total_cve_in_newer_stable=0,
                    total_cve_patch_available=len(kernel_spec_cves[kv]),
                    total_cve_patch_missing=len(applicable) - len(kernel_spec_cves[kv]),
                )
        
        # Build matrix entries
        entries = []
        for cve in cves:
            if not cve.cve_id.startswith("CVE-"):
                continue
            
            status_map = {}
            for kv in self.kernel_versions:
                is_na = cve.cve_id in kernel_not_applicable[kv]
                status_map[kv] = self.determine_status(
                    cve, kv,
                    kernel_spec_cves.get(kv, {}),
                    kernel_stable_patches.get(kv, {}),
                    is_na,
                )
            
            entry = MatrixEntry.from_cve(cve, self.kernel_versions, status_map)
            entries.append(entry)
        
        entries.sort(key=lambda e: e.cvss_score, reverse=True)
        
        return CVECoverageMatrix(
            kernel_versions=self.kernel_versions,
            entries=entries,
            kernel_coverage=kernel_coverage,
        )
    
    def build_from_nvd(
        self,
        output_dir: Path,
        repo_dirs: Optional[Dict[str, Path]] = None,
        patch_dirs: Optional[Dict[str, Path]] = None,
    ) -> CVECoverageMatrix:
        """Build matrix by fetching CVEs from NVD."""
        from scripts.cve_sources import fetch_cves_sync
        
        logger.info("Fetching CVEs from NVD for matrix...")
        
        cves = fetch_cves_sync(
            CVESource.NVD,
            self.kernel_versions[0],
            output_dir,
        )
        
        logger.info(f"Fetched {len(cves)} CVEs, building matrix...")
        
        matrix = self.build_from_cves(cves, repo_dirs, patch_dirs)
        matrix.source = "nvd"
        
        return matrix


def generate_cve_matrix(
    output_dir: Path,
    kernel_versions: Optional[List[str]] = None,
    repo_dirs: Optional[Dict[str, Path]] = None,
    patch_dirs: Optional[Dict[str, Path]] = None,
    format: str = "all",
    config: Optional[KernelConfig] = None,
) -> CVECoverageMatrix:
    """Generate CVE coverage matrix and save to files."""
    builder = CVEMatrixBuilder(kernel_versions, config)
    matrix = builder.build_from_nvd(output_dir, repo_dirs, patch_dirs)
    
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    base_name = f"cve_matrix_{timestamp}"
    
    output_dir.mkdir(parents=True, exist_ok=True)
    
    if format in ("json", "all"):
        matrix.save_json(output_dir / f"{base_name}.json")
    
    if format in ("csv", "all"):
        matrix.save_csv(output_dir / f"{base_name}.csv")
        matrix.save_stable_patch_csv(output_dir / f"{base_name}_patches.csv")
    
    if format in ("markdown", "all"):
        matrix.save_markdown(output_dir / f"{base_name}.md")
    
    return matrix


def print_cve_matrix(
    kernel_versions: Optional[List[str]] = None,
    repo_dirs: Optional[Dict[str, Path]] = None,
    patch_dirs: Optional[Dict[str, Path]] = None,
    max_rows: int = 50,
    config: Optional[KernelConfig] = None,
) -> None:
    """Generate and print CVE matrix to console."""
    from tempfile import mkdtemp
    import shutil
    
    output_dir = Path(mkdtemp())
    
    try:
        matrix = generate_cve_matrix(
            output_dir, kernel_versions, repo_dirs, patch_dirs, "json", config
        )
        matrix.print_table(Console(), max_rows)
    finally:
        shutil.rmtree(output_dir, ignore_errors=True)
