"""
Kernelpatches - Automated kernel patch backporting solution for Photon OS.

This package provides tools for:
- CVE patch detection from NVD, GHSA, Atom feeds, and upstream commits
- Stable kernel patch downloading and integration
- CVE gap detection for missing backports
- RPM building with spec file manipulation
- CVE coverage matrix generation
"""

__version__ = "1.0.0"
__author__ = "Photon OS Team"

from scripts.config import KernelConfig, SUPPORTED_KERNELS
from scripts.models import (
    CVE,
    Patch,
    KernelVersion,
    CVESource,
    PatchTarget,
    GapAnalysisResult,
    CVEMatrixEntry,
)

__all__ = [
    "__version__",
    "KernelConfig",
    "SUPPORTED_KERNELS",
    "CVE",
    "Patch",
    "KernelVersion",
    "CVESource",
    "PatchTarget",
    "GapAnalysisResult",
    "CVEMatrixEntry",
]
