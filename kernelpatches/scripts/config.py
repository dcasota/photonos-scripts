"""
Configuration constants and kernel version mappings for the kernelpatches solution.
"""

from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Dict, List, Optional
import os


class KernelBranch(str, Enum):
    """Photon OS branch names."""
    PHOTON_4 = "4.0"
    PHOTON_5 = "5.0"
    COMMON = "common"


@dataclass
class KernelMapping:
    """Mapping between kernel version and Photon OS configuration."""
    version: str
    branch: KernelBranch
    spec_dir: str
    spec_files: List[str]
    
    @property
    def major_version(self) -> int:
        """Get major kernel version number."""
        return int(self.version.split(".")[0])
    
    @property
    def kernel_org_url(self) -> str:
        """Get kernel.org URL for this kernel series."""
        return f"https://cdn.kernel.org/pub/linux/kernel/v{self.major_version}.x/"


# Supported kernel configurations
KERNEL_MAPPINGS: Dict[str, KernelMapping] = {
    "5.10": KernelMapping(
        version="5.10",
        branch=KernelBranch.PHOTON_4,
        spec_dir="SPECS/linux",
        spec_files=["linux.spec", "linux-esx.spec", "linux-rt.spec"],
    ),
    "6.1": KernelMapping(
        version="6.1",
        branch=KernelBranch.PHOTON_5,
        spec_dir="SPECS/linux",
        spec_files=["linux.spec", "linux-esx.spec", "linux-rt.spec"],
    ),
    "6.12": KernelMapping(
        version="6.12",
        branch=KernelBranch.COMMON,
        spec_dir="SPECS/linux/v6.12",
        spec_files=["linux.spec", "linux-esx.spec"],
    ),
}

SUPPORTED_KERNELS = list(KERNEL_MAPPINGS.keys())


@dataclass
class KernelConfig:
    """Global configuration for kernel backport operations."""
    
    # Directories
    base_dir: Path = field(default_factory=lambda: Path("/root/photonos-scripts"))
    log_dir: Path = field(default_factory=lambda: Path("/var/log/kernel-backport"))
    report_dir: Path = field(default_factory=lambda: Path("/var/log/kernel-backport/reports"))
    gap_report_dir: Path = field(default_factory=lambda: Path("/var/log/kernel-backport/gaps"))
    cache_dir: Path = field(default_factory=lambda: Path("/var/cache/kernel-backport"))
    
    # Repository
    repo_url: str = "https://github.com/vmware/photon.git"
    
    # Network settings
    network_timeout: int = 30
    network_retries: int = 3
    
    # NVD API configuration
    nvd_api_base: str = "https://services.nvd.nist.gov/rest/json/cves/2.0"
    nvd_feed_base: str = "https://nvd.nist.gov/feeds/json/cve/2.0"
    kernel_org_cna: str = "416baaa9-dc9f-4396-8d5f-8c081fb06d67"
    
    # GitHub API
    github_api_url: str = "https://api.github.com"
    github_graphql_url: str = "https://api.github.com/graphql"
    
    # CVE announce feed
    cve_announce_feed: str = "https://lore.kernel.org/linux-cve-announce/new.atom"
    
    # Patch numbering ranges in spec files
    cve_patch_min: int = 100
    cve_patch_max: int = 9999
    
    # Broadcom artifactory for source packages
    photon_sources_url: str = "https://packages.broadcom.com/artifactory/photon/photon_sources/1.0/"
    
    # Build settings
    build_timeout: int = 3600  # 1 hour
    
    # Stable kernel branches for gap detection
    stable_branches: List[str] = field(
        default_factory=lambda: ["5.10", "5.15", "6.1", "6.6", "6.11", "6.12"]
    )
    
    def __post_init__(self):
        """Ensure directories exist."""
        for dir_path in [self.log_dir, self.report_dir, self.gap_report_dir, self.cache_dir]:
            dir_path.mkdir(parents=True, exist_ok=True)
    
    @classmethod
    def from_env(cls) -> "KernelConfig":
        """Create configuration from environment variables."""
        return cls(
            base_dir=Path(os.getenv("KERNEL_BACKPORT_BASE_DIR", "/root/photonos-scripts")),
            log_dir=Path(os.getenv("KERNEL_BACKPORT_LOG_DIR", "/var/log/kernel-backport")),
            network_timeout=int(os.getenv("KERNEL_BACKPORT_TIMEOUT", "30")),
            network_retries=int(os.getenv("KERNEL_BACKPORT_RETRIES", "3")),
        )
    
    def get_kernel_mapping(self, kernel_version: str) -> Optional[KernelMapping]:
        """Get kernel mapping for a given version."""
        return KERNEL_MAPPINGS.get(kernel_version)
    
    def get_repo_dir(self, kernel_version: str) -> Optional[Path]:
        """Get repository directory for a kernel version."""
        mapping = self.get_kernel_mapping(kernel_version)
        if mapping:
            return self.base_dir / "kernelpatches" / mapping.branch.value
        return None
    
    def get_spec_dir(self, kernel_version: str) -> Optional[Path]:
        """Get spec directory path for a kernel version."""
        mapping = self.get_kernel_mapping(kernel_version)
        repo_dir = self.get_repo_dir(kernel_version)
        if mapping and repo_dir:
            return repo_dir / mapping.spec_dir
        return None


# Default global configuration instance
DEFAULT_CONFIG = KernelConfig()


def get_branch_for_kernel(kernel_version: str) -> Optional[str]:
    """Get Photon branch name for a kernel version."""
    mapping = KERNEL_MAPPINGS.get(kernel_version)
    return mapping.branch.value if mapping else None


def get_spec_files_for_kernel(kernel_version: str) -> List[str]:
    """Get spec files for a kernel version."""
    mapping = KERNEL_MAPPINGS.get(kernel_version)
    return mapping.spec_files if mapping else []


def get_kernel_org_url(kernel_version: str) -> Optional[str]:
    """Get kernel.org URL for a kernel version."""
    mapping = KERNEL_MAPPINGS.get(kernel_version)
    return mapping.kernel_org_url if mapping else None


def validate_kernel_version(kernel_version: str) -> bool:
    """Check if a kernel version is supported."""
    return kernel_version in SUPPORTED_KERNELS
