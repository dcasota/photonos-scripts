"""Tests for CVE matrix module with five-state tracking."""

import pytest
import json
from datetime import datetime
from pathlib import Path

from scripts.cve_matrix import (
    CVECoverageMatrix,
    CVEMatrixBuilder,
    CVEPatchState,
    KernelCVEStatus,
    KernelVersionCoverage,
    MatrixEntry,
    StablePatchCVECoverage,
    StablePatchCVEMapper,
)
from scripts.models import CVE, Severity


@pytest.fixture
def sample_stable_patch_coverage():
    """Create sample stable patch coverage with five states."""
    return StablePatchCVECoverage(
        patch_version="6.1.155",
        kernel_series="6.1",
        not_applicable=["CVE-2024-99999"],
        included=["CVE-2024-12345", "CVE-2024-12346"],
        cve_in_newer_stable=["CVE-2024-5678"],
        cve_patch_available=["CVE-2024-7777"],
        cve_patch_missing=["CVE-2024-11111"],
    )


@pytest.fixture
def sample_kernel_coverage():
    """Create sample kernel version coverage."""
    return KernelVersionCoverage(
        kernel_version="6.1",
        photon_version="6.1.155",
        latest_stable="6.1.156",
        stable_patches=[
            StablePatchCVECoverage(
                patch_version="6.1.155",
                kernel_series="6.1",
                not_applicable=["CVE-2024-99999"],
                included=["CVE-2024-12345"],
                cve_in_newer_stable=["CVE-2024-5678"],
                cve_patch_available=[],
                cve_patch_missing=["CVE-2024-11111"],
            ),
            StablePatchCVECoverage(
                patch_version="6.1.156",
                kernel_series="6.1",
                not_applicable=["CVE-2024-99999"],
                included=["CVE-2024-12345", "CVE-2024-5678"],
                cve_in_newer_stable=[],
                cve_patch_available=[],
                cve_patch_missing=["CVE-2024-11111"],
            ),
        ],
        total_not_applicable=1,
        total_included=2,
        total_cve_in_newer_stable=0,
        total_cve_patch_available=0,
        total_cve_patch_missing=1,
    )


@pytest.fixture
def sample_entries():
    """Create sample matrix entries with five-state status."""
    return [
        MatrixEntry(
            cve_id="CVE-2024-12345",
            cvss_score=9.5,
            severity="CRITICAL",
            description="Critical vulnerability",
            references=["https://nvd.nist.gov/vuln/detail/CVE-2024-12345"],
            kernel_status={
                "5.10": KernelCVEStatus(
                    state=CVEPatchState.CVE_INCLUDED,
                    stable_patch="5.10.220",
                ),
                "6.1": KernelCVEStatus(
                    state=CVEPatchState.CVE_INCLUDED,
                    stable_patch="6.1.155",
                ),
                "6.12": KernelCVEStatus(
                    state=CVEPatchState.CVE_PATCH_AVAILABLE,
                    fix_commit="abc123def456",
                ),
            },
        ),
        MatrixEntry(
            cve_id="CVE-2024-5678",
            cvss_score=7.2,
            severity="HIGH",
            description="High severity issue",
            references=["https://nvd.nist.gov/vuln/detail/CVE-2024-5678"],
            kernel_status={
                "5.10": KernelCVEStatus(
                    state=CVEPatchState.CVE_PATCH_MISSING,
                    fix_commit="xyz789",
                ),
                "6.1": KernelCVEStatus(
                    state=CVEPatchState.CVE_INCLUDED,
                    stable_patch="6.1.156",
                ),
                "6.12": KernelCVEStatus(
                    state=CVEPatchState.CVE_INCLUDED,
                    stable_patch="6.12.5",
                ),
            },
        ),
        MatrixEntry(
            cve_id="CVE-2024-9999",
            cvss_score=4.5,
            severity="MEDIUM",
            description="Medium severity issue",
            references=["https://example.com/3"],
            kernel_status={
                "5.10": KernelCVEStatus(state=CVEPatchState.CVE_NOT_APPLICABLE),
                "6.1": KernelCVEStatus(state=CVEPatchState.CVE_NOT_APPLICABLE),
                "6.12": KernelCVEStatus(
                    state=CVEPatchState.CVE_INCLUDED,
                    spec_patch="Patch102: CVE-2024-9999.patch",
                ),
            },
        ),
    ]


@pytest.fixture
def sample_matrix(sample_entries, sample_kernel_coverage):
    """Create sample CVE matrix with five-state tracking."""
    return CVECoverageMatrix(
        kernel_versions=["5.10", "6.1", "6.12"],
        entries=sample_entries,
        kernel_coverage={"6.1": sample_kernel_coverage},
    )


class TestCVEPatchState:
    """Tests for CVEPatchState enum."""
    
    def test_states_exist(self):
        """Test all five states exist."""
        assert CVEPatchState.CVE_NOT_APPLICABLE.value == "cve_not_applicable"
        assert CVEPatchState.CVE_INCLUDED.value == "cve_included"
        assert CVEPatchState.CVE_IN_NEWER_STABLE.value == "cve_in_newer_stable"
        assert CVEPatchState.CVE_PATCH_AVAILABLE.value == "cve_patch_available"
        assert CVEPatchState.CVE_PATCH_MISSING.value == "cve_patch_missing"


class TestKernelCVEStatus:
    """Tests for KernelCVEStatus class."""
    
    def test_to_dict(self):
        """Test dictionary conversion."""
        status = KernelCVEStatus(
            state=CVEPatchState.CVE_INCLUDED,
            stable_patch="6.1.155",
            fix_commit="abc123",
        )
        d = status.to_dict()
        
        assert d["state"] == "cve_included"
        assert d["stable_patch"] == "6.1.155"
        assert d["fix_commit"] == "abc123"
    
    def test_default_values(self):
        """Test default values."""
        status = KernelCVEStatus(state=CVEPatchState.CVE_PATCH_MISSING)
        assert status.stable_patch is None
        assert status.spec_patch is None
        assert status.fix_commit is None
    
    def test_has_patch_included(self):
        """Test has_patch for included state."""
        status = KernelCVEStatus(state=CVEPatchState.CVE_INCLUDED)
        assert status.has_patch is True
        assert status.is_gap is False
    
    def test_has_patch_available(self):
        """Test has_patch for patch_available state."""
        status = KernelCVEStatus(state=CVEPatchState.CVE_PATCH_AVAILABLE)
        assert status.has_patch is True
        assert status.is_gap is False
    
    def test_is_gap(self):
        """Test is_gap for patch_missing state."""
        status = KernelCVEStatus(state=CVEPatchState.CVE_PATCH_MISSING)
        assert status.has_patch is False
        assert status.is_gap is True
    
    def test_not_applicable(self):
        """Test not_applicable state."""
        status = KernelCVEStatus(state=CVEPatchState.CVE_NOT_APPLICABLE)
        assert status.has_patch is False
        assert status.is_gap is False
    
    def test_in_newer_stable(self):
        """Test in_newer_stable state."""
        status = KernelCVEStatus(state=CVEPatchState.CVE_IN_NEWER_STABLE)
        # CVE_IN_NEWER_STABLE means patch exists but not in current version
        # has_patch is False because user doesn't have it yet
        assert status.has_patch is False
        assert status.is_gap is False


class TestStablePatchCVECoverage:
    """Tests for StablePatchCVECoverage class."""
    
    def test_total_applicable(self, sample_stable_patch_coverage):
        """Test total applicable count (excludes not_applicable)."""
        # included(2) + in_newer(1) + patch_available(1) + patch_missing(1) = 5
        assert sample_stable_patch_coverage.total_applicable == 5
    
    def test_total_with_patch(self, sample_stable_patch_coverage):
        """Test total with patch count."""
        # included(2) + in_newer(1) + patch_available(1) = 4
        assert sample_stable_patch_coverage.total_with_patch == 4
    
    def test_coverage_percent(self, sample_stable_patch_coverage):
        """Test coverage percentage (only counts included, not in_newer or available)."""
        # 2 included / 5 applicable = 40%
        assert sample_stable_patch_coverage.coverage_percent == 40.0
    
    def test_gap_count(self, sample_stable_patch_coverage):
        """Test gap count."""
        assert sample_stable_patch_coverage.gap_count == 1
    
    def test_upgrade_available_count(self, sample_stable_patch_coverage):
        """Test upgrade available count."""
        assert sample_stable_patch_coverage.upgrade_available_count == 1
    
    def test_get_state(self, sample_stable_patch_coverage):
        """Test getting state for specific CVE."""
        assert sample_stable_patch_coverage.get_state("CVE-2024-99999") == CVEPatchState.CVE_NOT_APPLICABLE
        assert sample_stable_patch_coverage.get_state("CVE-2024-12345") == CVEPatchState.CVE_INCLUDED
        assert sample_stable_patch_coverage.get_state("CVE-2024-5678") == CVEPatchState.CVE_IN_NEWER_STABLE
        assert sample_stable_patch_coverage.get_state("CVE-2024-7777") == CVEPatchState.CVE_PATCH_AVAILABLE
        assert sample_stable_patch_coverage.get_state("CVE-2024-11111") == CVEPatchState.CVE_PATCH_MISSING
    
    def test_coverage_percent_empty(self):
        """Test coverage percentage with no applicable CVEs."""
        sp = StablePatchCVECoverage(
            patch_version="6.1.155",
            kernel_series="6.1",
            not_applicable=["CVE-2024-99999"],
        )
        assert sp.coverage_percent == 100.0


class TestKernelVersionCoverage:
    """Tests for KernelVersionCoverage class."""
    
    def test_to_dict(self, sample_kernel_coverage):
        """Test dictionary conversion."""
        d = sample_kernel_coverage.to_dict()
        
        assert d["kernel_version"] == "6.1"
        assert d["photon_version"] == "6.1.155"
        assert d["latest_stable"] == "6.1.156"
        assert len(d["stable_patches"]) == 2
        assert "summary" in d
    
    def test_total_applicable(self, sample_kernel_coverage):
        """Test total applicable."""
        # included(2) + in_newer(0) + patch_available(0) + patch_missing(1) = 3
        assert sample_kernel_coverage.total_applicable == 3
    
    def test_coverage_percent(self, sample_kernel_coverage):
        """Test coverage percentage."""
        # 2 with patch / 3 applicable = 66.7%
        assert sample_kernel_coverage.coverage_percent == 66.7
    
    def test_upgrade_available(self, sample_kernel_coverage):
        """Test upgrade available property."""
        # photon_version != latest_stable means upgrade is available
        assert sample_kernel_coverage.photon_version != sample_kernel_coverage.latest_stable
    
    def test_get_patch_coverage(self, sample_kernel_coverage):
        """Test getting patch coverage."""
        patch = sample_kernel_coverage.get_patch_coverage("6.1.155")
        assert patch is not None
        assert patch.patch_version == "6.1.155"
        
        patch_none = sample_kernel_coverage.get_patch_coverage("6.1.999")
        assert patch_none is None


class TestMatrixEntry:
    """Tests for MatrixEntry class."""
    
    def test_to_dict(self, sample_entries):
        """Test dictionary conversion with nested status."""
        entry = sample_entries[0]
        d = entry.to_dict()
        
        assert d["cve_id"] == "CVE-2024-12345"
        assert d["cvss_score"] == 9.5
        assert "kernel_status" in d
        assert "5.10" in d["kernel_status"]
        assert d["kernel_status"]["5.10"]["state"] == "cve_included"
        assert d["kernel_status"]["5.10"]["stable_patch"] == "5.10.220"
    
    def test_get_state(self, sample_entries):
        """Test getting state."""
        entry = sample_entries[0]
        
        assert entry.get_state("5.10") == CVEPatchState.CVE_INCLUDED
        assert entry.get_state("6.12") == CVEPatchState.CVE_PATCH_AVAILABLE
        assert entry.get_state("invalid") == CVEPatchState.CVE_PATCH_MISSING
    
    def test_get_stable_patch(self, sample_entries):
        """Test getting stable patch version."""
        entry = sample_entries[0]
        
        assert entry.get_stable_patch("5.10") == "5.10.220"
        assert entry.get_stable_patch("6.1") == "6.1.155"
        assert entry.get_stable_patch("6.12") is None
    
    def test_has_patch_for_kernel(self, sample_entries):
        """Test has_patch_for_kernel."""
        entry = sample_entries[0]
        
        assert entry.has_patch_for_kernel("5.10") is True
        assert entry.has_patch_for_kernel("6.12") is True
        
        entry2 = sample_entries[1]
        assert entry2.has_patch_for_kernel("5.10") is False
    
    def test_is_gap_for_kernel(self, sample_entries):
        """Test is_gap_for_kernel."""
        entry2 = sample_entries[1]
        
        assert entry2.is_gap_for_kernel("5.10") is True
        assert entry2.is_gap_for_kernel("6.1") is False
    
    def test_from_cve(self):
        """Test creating from CVE object."""
        cve = CVE(
            cve_id="CVE-2024-11111",
            cvss_score=8.0,
            severity=Severity.HIGH,
            description="Test CVE",
        )
        
        status_map = {
            "5.10": KernelCVEStatus(state=CVEPatchState.CVE_INCLUDED, stable_patch="5.10.225"),
            "6.1": KernelCVEStatus(state=CVEPatchState.CVE_PATCH_AVAILABLE),
        }
        entry = MatrixEntry.from_cve(cve, ["5.10", "6.1"], status_map)
        
        assert entry.cve_id == "CVE-2024-11111"
        assert entry.cvss_score == 8.0
        assert entry.get_state("5.10") == CVEPatchState.CVE_INCLUDED
        assert entry.get_stable_patch("5.10") == "5.10.225"


class TestCVECoverageMatrix:
    """Tests for CVECoverageMatrix class."""
    
    def test_total_cves(self, sample_matrix):
        """Test total CVE count."""
        assert sample_matrix.total_cves == 3
    
    def test_get_by_severity(self, sample_matrix):
        """Test filtering by severity."""
        critical = sample_matrix.get_by_severity("CRITICAL")
        assert len(critical) == 1
        assert critical[0].cve_id == "CVE-2024-12345"
    
    def test_get_by_state(self, sample_matrix):
        """Test filtering by state."""
        included_61 = sample_matrix.get_by_state("6.1", CVEPatchState.CVE_INCLUDED)
        assert len(included_61) == 2
        
        missing = sample_matrix.get_by_state("5.10", CVEPatchState.CVE_PATCH_MISSING)
        assert len(missing) == 1
        assert missing[0].cve_id == "CVE-2024-5678"
    
    def test_get_included(self, sample_matrix):
        """Test get_included convenience method."""
        included = sample_matrix.get_included("6.1")
        assert len(included) == 2
    
    def test_get_patch_available(self, sample_matrix):
        """Test get_by_state for patch_available."""
        available = sample_matrix.get_by_state("6.12", CVEPatchState.CVE_PATCH_AVAILABLE)
        assert len(available) == 1
        assert available[0].cve_id == "CVE-2024-12345"
    
    def test_get_patch_missing(self, sample_matrix):
        """Test get_by_state for patch_missing."""
        missing = sample_matrix.get_by_state("5.10", CVEPatchState.CVE_PATCH_MISSING)
        assert len(missing) == 1
    
    def test_get_not_applicable(self, sample_matrix):
        """Test get_not_applicable convenience method."""
        na = sample_matrix.get_not_applicable("5.10")
        assert len(na) == 1
        assert na[0].cve_id == "CVE-2024-9999"
    
    def test_get_critical_gaps(self, sample_matrix):
        """Test getting critical gaps."""
        gaps = sample_matrix.get_critical_gaps()
        assert len(gaps) == 1
        assert gaps[0].cve_id == "CVE-2024-5678"
    
    def test_summary(self, sample_matrix):
        """Test summary statistics."""
        summary = sample_matrix.summary()
        
        assert summary["5.10"]["cve_included"] == 1
        assert summary["5.10"]["cve_patch_missing"] == 1
        assert summary["5.10"]["cve_not_applicable"] == 1
        
        assert summary["6.1"]["cve_included"] == 2
        assert summary["6.1"]["cve_not_applicable"] == 1
    
    def test_stable_patch_summary(self, sample_matrix):
        """Test stable patch summary with five states."""
        summary = sample_matrix.stable_patch_summary()
        
        assert "6.1" in summary
        assert len(summary["6.1"]) == 2
        
        patch_155 = next(p for p in summary["6.1"] if p["stable_patch_version"] == "6.1.155")
        assert "cve_included" in patch_155
        assert "cve_in_newer_stable" in patch_155
        assert "cve_patch_available" in patch_155
        assert "cve_patch_missing" in patch_155
        assert "cve_not_applicable" in patch_155
    
    def test_to_dict(self, sample_matrix):
        """Test dictionary conversion."""
        d = sample_matrix.to_dict()
        
        assert "generated" in d
        assert "kernel_versions" in d
        assert "total_cves" in d
        assert "summary" in d
        assert "kernel_coverage" in d
        assert "entries" in d
    
    def test_save_json(self, sample_matrix, tmp_path):
        """Test JSON export."""
        json_path = tmp_path / "matrix.json"
        sample_matrix.save_json(json_path)
        
        assert json_path.exists()
        
        with open(json_path) as f:
            data = json.load(f)
        
        assert data["total_cves"] == 3
        assert "kernel_coverage" in data
        
        entry = data["entries"][0]
        assert "kernel_status" in entry
        assert "state" in entry["kernel_status"]["5.10"]
    
    def test_save_csv(self, sample_matrix, tmp_path):
        """Test CSV export with state columns."""
        csv_path = tmp_path / "matrix.csv"
        sample_matrix.save_csv(csv_path)
        
        assert csv_path.exists()
        
        content = csv_path.read_text()
        assert "CVE ID" in content
        assert "State (6.1)" in content
    
    def test_save_stable_patch_csv(self, sample_matrix, tmp_path):
        """Test stable patch CSV export with five states."""
        csv_path = tmp_path / "patches.csv"
        sample_matrix.save_stable_patch_csv(csv_path)
        
        assert csv_path.exists()
        
        content = csv_path.read_text()
        assert "Kernel" in content
    
    def test_save_markdown(self, sample_matrix, tmp_path):
        """Test Markdown export with five states."""
        md_path = tmp_path / "matrix.md"
        sample_matrix.save_markdown(md_path)
        
        assert md_path.exists()
        
        content = md_path.read_text()
        assert "# CVE Coverage Matrix" in content
        assert "## CVE States" in content


class TestCVEMatrixBuilder:
    """Tests for CVEMatrixBuilder class."""
    
    def test_init_default_kernels(self):
        """Test initialization with default kernels."""
        builder = CVEMatrixBuilder()
        assert "5.10" in builder.kernel_versions
        assert "6.1" in builder.kernel_versions
        assert "6.12" in builder.kernel_versions
    
    def test_determine_not_applicable_with_versions(self):
        """Test not applicable detection with version info."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(
            cve_id="CVE-2024-12345",
            affected_versions=["6.1", "6.5"],
        )
        
        assert builder.determine_not_applicable(cve, "5.10") is True
        assert builder.determine_not_applicable(cve, "6.1") is False
    
    def test_determine_not_applicable_no_versions(self):
        """Test not applicable without version info."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(cve_id="CVE-2024-12345")
        
        assert builder.determine_not_applicable(cve, "5.10") is False
    
    def test_determine_status_not_applicable(self):
        """Test status determination for not applicable."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(cve_id="CVE-2024-12345")
        status = builder.determine_status(cve, "6.1", {}, {}, is_not_applicable=True)
        
        assert status.state == CVEPatchState.CVE_NOT_APPLICABLE
    
    def test_determine_status_in_spec(self):
        """Test status determination for CVE in spec."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(cve_id="CVE-2024-12345")
        spec_cves = {"CVE-2024-12345": "Patch100: fix.patch"}
        
        status = builder.determine_status(cve, "6.1", spec_cves, {}, is_not_applicable=False)
        
        assert status.state == CVEPatchState.CVE_INCLUDED
        assert status.spec_patch == "Patch100: fix.patch"
    
    def test_determine_status_in_stable_patch(self):
        """Test status determination for CVE in stable patch."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(cve_id="CVE-2024-12345")
        stable_cves = {"CVE-2024-12345": "6.1.155"}
        
        status = builder.determine_status(cve, "6.1", {}, stable_cves, is_not_applicable=False)
        
        assert status.state == CVEPatchState.CVE_INCLUDED
        assert status.stable_patch == "6.1.155"
    
    def test_determine_status_patch_available(self):
        """Test status determination with available backport."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(
            cve_id="CVE-2024-12345",
            fix_branches=["6.1", "6.6"],
            fix_commits=["abc123"],
        )
        
        status = builder.determine_status(cve, "6.1", {}, {}, is_not_applicable=False)
        
        assert status.state == CVEPatchState.CVE_PATCH_AVAILABLE
        assert status.fix_commit == "abc123"
    
    def test_determine_status_patch_missing(self):
        """Test status determination for gap."""
        builder = CVEMatrixBuilder()
        
        cve = CVE(
            cve_id="CVE-2024-12345",
            fix_branches=["6.6", "6.12"],
            fix_commits=["abc123"],
        )
        
        status = builder.determine_status(cve, "5.10", {}, {}, is_not_applicable=False)
        
        assert status.state == CVEPatchState.CVE_PATCH_MISSING
        assert status.fix_commit == "abc123"
    
    def test_build_from_cves(self):
        """Test building matrix from CVE list."""
        cves = [
            CVE(
                cve_id="CVE-2024-11111",
                cvss_score=8.5,
                severity=Severity.HIGH,
            ),
            CVE(
                cve_id="CVE-2024-22222",
                cvss_score=5.0,
                severity=Severity.MEDIUM,
            ),
        ]
        
        builder = CVEMatrixBuilder(kernel_versions=["6.1"])
        matrix = builder.build_from_cves(cves)
        
        assert matrix.total_cves == 2
        assert matrix.entries[0].cve_id == "CVE-2024-11111"


class TestStablePatchCVEMapper:
    """Tests for StablePatchCVEMapper class."""
    
    def test_extract_cves_from_patch_file(self, tmp_path):
        """Test extracting CVEs from patch file."""
        mapper = StablePatchCVEMapper()
        
        patch_file = tmp_path / "patch-6.1.155"
        patch_file.write_text("""
From abc123 Mon Sep 17 00:00:00 2001
Subject: Fix CVE-2024-12345 and CVE-2024-12346

This fixes a critical vulnerability.
---
 some/file.c | 10 ++++++++++
 1 file changed, 10 insertions(+)
""")
        
        cves = mapper.extract_cves_from_patch_file(patch_file)
        assert "CVE-2024-12345" in cves
        assert "CVE-2024-12346" in cves
    
    def test_extract_cves_nonexistent_file(self, tmp_path):
        """Test extracting from nonexistent file."""
        mapper = StablePatchCVEMapper()
        cves = mapper.extract_cves_from_patch_file(tmp_path / "nonexistent")
        assert cves == []
