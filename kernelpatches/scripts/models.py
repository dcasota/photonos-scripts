"""
Data models for the kernelpatches solution using Pydantic for validation.
"""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Set
from pydantic import BaseModel, Field, field_validator
import re


class CVESource(str, Enum):
    """Sources for CVE information."""
    NVD = "nvd"
    GHSA = "ghsa"
    ATOM = "atom"
    UPSTREAM = "upstream"


class PatchSource(str, Enum):
    """Sources for patches."""
    CVE = "cve"
    STABLE = "stable"
    STABLE_FULL = "stable-full"
    ALL = "all"


class PatchTarget(str, Enum):
    """Target spec files for patches."""
    ALL = "all"
    BASE = "base"
    ESX = "esx"
    RT = "rt"
    NONE = "none"


class Severity(str, Enum):
    """CVE severity levels."""
    CRITICAL = "CRITICAL"
    HIGH = "HIGH"
    MEDIUM = "MEDIUM"
    LOW = "LOW"
    UNKNOWN = "UNKNOWN"
    
    @classmethod
    def from_cvss(cls, score: float) -> "Severity":
        """Convert CVSS score to severity level."""
        if score >= 9.0:
            return cls.CRITICAL
        elif score >= 7.0:
            return cls.HIGH
        elif score >= 4.0:
            return cls.MEDIUM
        elif score > 0:
            return cls.LOW
        return cls.UNKNOWN


class KernelVersion(BaseModel):
    """Represents a kernel version with comparison support."""
    major: int
    minor: int
    patch: int = 0
    
    @classmethod
    def parse(cls, version_str: str) -> "KernelVersion":
        """Parse a version string like '6.1.159' into a KernelVersion."""
        parts = version_str.split(".")
        return cls(
            major=int(parts[0]) if len(parts) > 0 else 0,
            minor=int(parts[1]) if len(parts) > 1 else 0,
            patch=int(parts[2]) if len(parts) > 2 else 0,
        )
    
    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"
    
    def __lt__(self, other: "KernelVersion") -> bool:
        return (self.major, self.minor, self.patch) < (other.major, other.minor, other.patch)
    
    def __le__(self, other: "KernelVersion") -> bool:
        return (self.major, self.minor, self.patch) <= (other.major, other.minor, other.patch)
    
    def __gt__(self, other: "KernelVersion") -> bool:
        return (self.major, self.minor, self.patch) > (other.major, other.minor, other.patch)
    
    def __ge__(self, other: "KernelVersion") -> bool:
        return (self.major, self.minor, self.patch) >= (other.major, other.minor, other.patch)
    
    def __eq__(self, other: object) -> bool:
        if not isinstance(other, KernelVersion):
            return False
        return (self.major, self.minor, self.patch) == (other.major, other.minor, other.patch)
    
    def __hash__(self) -> int:
        return hash((self.major, self.minor, self.patch))
    
    @property
    def series(self) -> str:
        """Get the kernel series (e.g., '6.1' from '6.1.159')."""
        return f"{self.major}.{self.minor}"


class CVEReference(BaseModel):
    """A reference URL for a CVE."""
    url: str
    source: Optional[str] = None
    tags: List[str] = Field(default_factory=list)
    
    @property
    def is_commit(self) -> bool:
        """Check if this reference is a git commit."""
        return "commit" in self.url.lower() or "/c/" in self.url


class CPERange(BaseModel):
    """Represents a CPE version range for affected kernel versions."""
    criteria: str = ""
    version_start_including: Optional[str] = None
    version_start_excluding: Optional[str] = None
    version_end_including: Optional[str] = None
    version_end_excluding: Optional[str] = None
    vulnerable: bool = True
    
    def contains_version(self, version: str) -> bool:
        """Check if a kernel version falls within this range."""
        ver = KernelVersion.parse(version)
        
        # Check start boundary
        if self.version_start_including:
            start = KernelVersion.parse(self.version_start_including)
            if ver < start:
                return False
        if self.version_start_excluding:
            start = KernelVersion.parse(self.version_start_excluding)
            if ver <= start:
                return False
        
        # Check end boundary
        if self.version_end_including:
            end = KernelVersion.parse(self.version_end_including)
            if ver > end:
                return False
        if self.version_end_excluding:
            end = KernelVersion.parse(self.version_end_excluding)
            if ver >= end:
                return False
        
        return True


class CVE(BaseModel):
    """Represents a CVE with all relevant information."""
    cve_id: str
    cvss_score: float = 0.0
    severity: Severity = Severity.UNKNOWN
    description: str = ""
    published_date: Optional[datetime] = None
    modified_date: Optional[datetime] = None
    source: CVESource = CVESource.NVD
    references: List[CVEReference] = Field(default_factory=list)
    affected_versions: List[str] = Field(default_factory=list)
    fix_commits: List[str] = Field(default_factory=list)
    fix_branches: List[str] = Field(default_factory=list)
    ghsa_id: Optional[str] = None
    cwes: List[str] = Field(default_factory=list)
    cpe_ranges: List[CPERange] = Field(default_factory=list)
    
    def is_version_affected(self, kernel_version: str) -> Optional[bool]:
        """
        Check if a kernel version is affected by this CVE using CPE ranges.
        
        Returns:
            True: Version is vulnerable
            False: Version is NOT vulnerable (patched or not in affected range)
            None: No CPE data available to make determination
        """
        if not self.cpe_ranges:
            return None
        
        for cpe_range in self.cpe_ranges:
            if cpe_range.contains_version(kernel_version):
                return cpe_range.vulnerable
        
        # Version not in any range - not affected
        return False
    
    @field_validator("cve_id")
    @classmethod
    def validate_cve_id(cls, v: str) -> str:
        """Validate CVE ID format."""
        pattern = r"^CVE-\d{4}-\d{4,}$"
        if not re.match(pattern, v):
            raise ValueError(f"Invalid CVE ID format: {v}")
        return v
    
    @property
    def year(self) -> int:
        """Extract year from CVE ID."""
        match = re.search(r"CVE-(\d{4})-", self.cve_id)
        return int(match.group(1)) if match else 0
    
    @property
    def commit_urls(self) -> List[str]:
        """Get all commit URLs from references."""
        return [ref.url for ref in self.references if ref.is_commit]
    
    def extract_commit_shas(self) -> List[str]:
        """Extract commit SHAs from references."""
        shas = []
        sha_pattern = r"[a-f0-9]{40}"
        for ref in self.references:
            matches = re.findall(sha_pattern, ref.url)
            shas.extend(matches)
        shas.extend(self.fix_commits)
        return list(set(shas))


class Patch(BaseModel):
    """Represents a kernel patch."""
    sha: str
    filename: Optional[str] = None
    cve_ids: List[str] = Field(default_factory=list)
    target: PatchTarget = PatchTarget.ALL
    patch_number: Optional[int] = None
    source: PatchSource = PatchSource.CVE
    applied: bool = False
    content: Optional[str] = None
    files_changed: List[str] = Field(default_factory=list)
    
    @property
    def short_sha(self) -> str:
        """Get short SHA (first 12 characters)."""
        return self.sha[:12]
    
    @property
    def default_filename(self) -> str:
        """Generate default patch filename."""
        return f"{self.short_sha}-backport.patch"


class SpecPatch(BaseModel):
    """Represents a patch entry in a spec file."""
    number: int
    name: str
    cve_ids: List[str] = Field(default_factory=list)
    
    @classmethod
    def from_spec_line(cls, line: str) -> Optional["SpecPatch"]:
        """Parse a Patch line from spec file."""
        match = re.match(r"^Patch(\d+):\s*(.+)$", line)
        if match:
            number = int(match.group(1))
            name = match.group(2).strip()
            cve_ids = re.findall(r"CVE-\d{4}-\d+", name)
            return cls(number=number, name=name, cve_ids=cve_ids)
        return None


class GapAnalysisResult(BaseModel):
    """Result of CVE gap analysis for a specific CVE."""
    cve_id: str
    status: str  # "gap_detected", "has_backport", "not_affected", "fetch_failed"
    severity: Severity = Severity.UNKNOWN
    cvss_score: float = 0.0
    target_kernel: str
    current_version: str
    is_affected: bool = False
    fix_branches: List[str] = Field(default_factory=list)
    missing_backports: List[str] = Field(default_factory=list)
    requires_manual_backport: bool = False
    description: str = ""
    
    @property
    def has_gap(self) -> bool:
        """Check if this CVE has a backport gap."""
        return self.status == "gap_detected"


class CVEMatrixEntry(BaseModel):
    """Entry in the CVE coverage matrix."""
    cve_id: str
    cvss_score: float = 0.0
    severity: Severity = Severity.UNKNOWN
    description: str = ""
    references: List[str] = Field(default_factory=list)
    kernel_status: Dict[str, str] = Field(default_factory=dict)
    # kernel_status maps kernel version to status:
    # "fixed", "pending", "not_affected", "needs_backport", "unknown"
    
    @classmethod
    def create(
        cls,
        cve: CVE,
        kernel_versions: List[str],
        status_map: Optional[Dict[str, str]] = None,
    ) -> "CVEMatrixEntry":
        """Create a matrix entry from a CVE."""
        status_map = status_map or {}
        kernel_status = {kv: status_map.get(kv, "unknown") for kv in kernel_versions}
        
        return cls(
            cve_id=cve.cve_id,
            cvss_score=cve.cvss_score,
            severity=cve.severity,
            description=cve.description[:200] if cve.description else "",
            references=[ref.url for ref in cve.references[:5]],
            kernel_status=kernel_status,
        )


class CVEMatrix(BaseModel):
    """CVE coverage matrix across kernel versions."""
    generated: datetime = Field(default_factory=datetime.now)
    kernel_versions: List[str] = Field(default_factory=list)
    entries: List[CVEMatrixEntry] = Field(default_factory=list)
    
    @property
    def total_cves(self) -> int:
        """Total number of CVEs in the matrix."""
        return len(self.entries)
    
    def get_by_severity(self, severity: Severity) -> List[CVEMatrixEntry]:
        """Filter entries by severity."""
        return [e for e in self.entries if e.severity == severity]
    
    def get_gaps_for_kernel(self, kernel_version: str) -> List[CVEMatrixEntry]:
        """Get CVEs that need backport for a specific kernel."""
        return [
            e for e in self.entries
            if e.kernel_status.get(kernel_version) == "needs_backport"
        ]
    
    def summary(self) -> Dict[str, Dict[str, int]]:
        """Generate summary statistics per kernel version."""
        result = {}
        for kv in self.kernel_versions:
            result[kv] = {
                "fixed": 0,
                "pending": 0,
                "not_affected": 0,
                "needs_backport": 0,
                "unknown": 0,
            }
            for entry in self.entries:
                status = entry.kernel_status.get(kv, "unknown")
                if status in result[kv]:
                    result[kv][status] += 1
        return result


@dataclass
class StablePatchInfo:
    """Information about a stable kernel patch."""
    version: str  # e.g., "6.1.120"
    patch_file: str
    downloaded: bool = False
    applied: bool = False
    cves_fixed: List[str] = field(default_factory=list)


@dataclass 
class BuildResult:
    """Result of an RPM build operation."""
    spec_file: str
    success: bool
    version: str
    release: str
    duration_seconds: int = 0
    log_file: Optional[str] = None
    error_message: Optional[str] = None
    canister_build: int = 0
    acvp_build: int = 0


@dataclass
class ReportSummary:
    """Summary for CVE analysis reports."""
    total_stable_patches: int = 0
    total_cves_in_spec: int = 0
    cves_fixed_by_stable: int = 0
    cves_still_needed: int = 0


@dataclass
class GapReportSummary:
    """Summary for CVE gap detection reports."""
    total_cves_analyzed: int = 0
    cves_with_gaps: int = 0
    cves_patchable: int = 0
    cves_not_affected: int = 0
