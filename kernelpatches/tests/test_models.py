"""Tests for models module."""

import pytest
from datetime import datetime

from scripts.models import (
    CVE,
    CVEReference,
    CVESource,
    GapAnalysisResult,
    KernelVersion,
    Patch,
    PatchSource,
    PatchTarget,
    Severity,
    SpecPatch,
    CVEMatrixEntry,
)


class TestKernelVersion:
    """Tests for KernelVersion class."""
    
    def test_parse_full_version(self):
        """Test parsing full version string."""
        kv = KernelVersion.parse("6.1.159")
        assert kv.major == 6
        assert kv.minor == 1
        assert kv.patch == 159
    
    def test_parse_short_version(self):
        """Test parsing version without patch."""
        kv = KernelVersion.parse("6.1")
        assert kv.major == 6
        assert kv.minor == 1
        assert kv.patch == 0
    
    def test_str_representation(self):
        """Test string representation."""
        kv = KernelVersion(major=6, minor=1, patch=159)
        assert str(kv) == "6.1.159"
    
    def test_comparison_operators(self):
        """Test comparison operators."""
        v1 = KernelVersion.parse("6.1.100")
        v2 = KernelVersion.parse("6.1.159")
        v3 = KernelVersion.parse("6.1.100")
        v4 = KernelVersion.parse("5.10.200")
        
        assert v1 < v2
        assert v2 > v1
        assert v1 <= v3
        assert v1 >= v3
        assert v1 == v3
        assert v1 != v2
        assert v4 < v1  # 5.x < 6.x
    
    def test_series_property(self):
        """Test series property."""
        kv = KernelVersion.parse("6.1.159")
        assert kv.series == "6.1"
    
    def test_hash(self):
        """Test hash for use in sets/dicts."""
        v1 = KernelVersion.parse("6.1.100")
        v2 = KernelVersion.parse("6.1.100")
        
        assert hash(v1) == hash(v2)
        
        versions = {v1, v2}
        assert len(versions) == 1


class TestSeverity:
    """Tests for Severity enum."""
    
    def test_from_cvss_critical(self):
        """Test CRITICAL severity from CVSS."""
        assert Severity.from_cvss(9.5) == Severity.CRITICAL
        assert Severity.from_cvss(10.0) == Severity.CRITICAL
    
    def test_from_cvss_high(self):
        """Test HIGH severity from CVSS."""
        assert Severity.from_cvss(7.0) == Severity.HIGH
        assert Severity.from_cvss(8.9) == Severity.HIGH
    
    def test_from_cvss_medium(self):
        """Test MEDIUM severity from CVSS."""
        assert Severity.from_cvss(4.0) == Severity.MEDIUM
        assert Severity.from_cvss(6.9) == Severity.MEDIUM
    
    def test_from_cvss_low(self):
        """Test LOW severity from CVSS."""
        assert Severity.from_cvss(0.1) == Severity.LOW
        assert Severity.from_cvss(3.9) == Severity.LOW
    
    def test_from_cvss_unknown(self):
        """Test UNKNOWN severity from CVSS 0."""
        assert Severity.from_cvss(0.0) == Severity.UNKNOWN


class TestCVE:
    """Tests for CVE class."""
    
    def test_valid_cve_id(self):
        """Test valid CVE ID validation."""
        cve = CVE(cve_id="CVE-2024-12345")
        assert cve.cve_id == "CVE-2024-12345"
    
    def test_invalid_cve_id(self):
        """Test invalid CVE ID raises error."""
        with pytest.raises(ValueError):
            CVE(cve_id="INVALID-123")
    
    def test_year_extraction(self):
        """Test year extraction from CVE ID."""
        cve = CVE(cve_id="CVE-2024-12345")
        assert cve.year == 2024
        
        cve = CVE(cve_id="CVE-2023-5678")
        assert cve.year == 2023
    
    def test_commit_urls(self):
        """Test commit URL extraction."""
        cve = CVE(
            cve_id="CVE-2024-12345",
            references=[
                CVEReference(url="https://github.com/torvalds/linux/commit/abc123def456"),
                CVEReference(url="https://example.com/other"),
            ],
        )
        
        commit_urls = cve.commit_urls
        assert len(commit_urls) == 1
        assert "commit" in commit_urls[0]
    
    def test_extract_commit_shas(self):
        """Test commit SHA extraction."""
        sha = "a" * 40
        cve = CVE(
            cve_id="CVE-2024-12345",
            references=[
                CVEReference(url=f"https://github.com/torvalds/linux/commit/{sha}"),
            ],
            fix_commits=[sha],
        )
        
        shas = cve.extract_commit_shas()
        assert sha in shas


class TestPatch:
    """Tests for Patch class."""
    
    def test_short_sha(self):
        """Test short SHA property."""
        sha = "a" * 40
        patch = Patch(sha=sha)
        assert patch.short_sha == "a" * 12
    
    def test_default_filename(self):
        """Test default filename generation."""
        sha = "abc123def456" + "0" * 28
        patch = Patch(sha=sha)
        assert patch.default_filename == "abc123def456-backport.patch"


class TestSpecPatch:
    """Tests for SpecPatch class."""
    
    def test_from_spec_line(self):
        """Test parsing from spec line."""
        line = "Patch100: CVE-2024-12345-fix.patch"
        patch = SpecPatch.from_spec_line(line)
        
        assert patch is not None
        assert patch.number == 100
        assert patch.name == "CVE-2024-12345-fix.patch"
        assert "CVE-2024-12345" in patch.cve_ids
    
    def test_from_spec_line_no_cve(self):
        """Test parsing line without CVE."""
        line = "Patch50: some-fix.patch"
        patch = SpecPatch.from_spec_line(line)
        
        assert patch is not None
        assert patch.number == 50
        assert len(patch.cve_ids) == 0
    
    def test_from_spec_line_invalid(self):
        """Test parsing invalid line."""
        line = "Source0: linux.tar.xz"
        patch = SpecPatch.from_spec_line(line)
        assert patch is None


class TestGapAnalysisResult:
    """Tests for GapAnalysisResult class."""
    
    def test_has_gap_true(self):
        """Test has_gap when gap detected."""
        result = GapAnalysisResult(
            cve_id="CVE-2024-12345",
            status="gap_detected",
            target_kernel="6.1",
            current_version="6.1.159",
        )
        assert result.has_gap is True
    
    def test_has_gap_false(self):
        """Test has_gap when backport available."""
        result = GapAnalysisResult(
            cve_id="CVE-2024-12345",
            status="has_backport",
            target_kernel="6.1",
            current_version="6.1.159",
        )
        assert result.has_gap is False


class TestCVEMatrixEntry:
    """Tests for CVEMatrixEntry class."""
    
    def test_create_from_cve(self):
        """Test creating matrix entry from CVE."""
        cve = CVE(
            cve_id="CVE-2024-12345",
            cvss_score=7.5,
            severity=Severity.HIGH,
            description="Test vulnerability",
        )
        
        status_map = {
            "5.10": "fixed",
            "6.1": "needs_backport",
            "6.12": "pending",
        }
        
        entry = CVEMatrixEntry.create(cve, ["5.10", "6.1", "6.12"], status_map)
        
        assert entry.cve_id == "CVE-2024-12345"
        assert entry.cvss_score == 7.5
        assert entry.kernel_status["5.10"] == "fixed"
        assert entry.kernel_status["6.1"] == "needs_backport"
        assert entry.kernel_status["6.12"] == "pending"
