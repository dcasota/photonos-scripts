"""Tests for common module."""

import pytest
from pathlib import Path
from unittest.mock import patch, MagicMock

from scripts.common import (
    calculate_sha512,
    extract_cve_ids,
    extract_commit_sha,
    version_less_than,
    expand_targets_to_specs,
    format_duration,
)
from scripts.models import Patch, PatchTarget


class TestVersionComparison:
    """Tests for version comparison."""
    
    def test_version_less_than_patch(self):
        """Test patch version comparison."""
        assert version_less_than("6.1.100", "6.1.159") is True
        assert version_less_than("6.1.159", "6.1.100") is False
    
    def test_version_less_than_minor(self):
        """Test minor version comparison."""
        assert version_less_than("6.1.100", "6.2.0") is True
        assert version_less_than("6.2.0", "6.1.100") is False
    
    def test_version_less_than_major(self):
        """Test major version comparison."""
        assert version_less_than("5.10.200", "6.1.0") is True
        assert version_less_than("6.1.0", "5.10.200") is False
    
    def test_version_equal(self):
        """Test equal versions."""
        assert version_less_than("6.1.100", "6.1.100") is False


class TestCVEExtraction:
    """Tests for CVE ID extraction."""
    
    def test_extract_single_cve(self):
        """Test extracting single CVE."""
        text = "This fixes CVE-2024-12345"
        cves = extract_cve_ids(text)
        assert "CVE-2024-12345" in cves
    
    def test_extract_multiple_cves(self):
        """Test extracting multiple CVEs."""
        text = "Fixes CVE-2024-12345 and CVE-2023-5678"
        cves = extract_cve_ids(text)
        assert len(cves) == 2
        assert "CVE-2024-12345" in cves
        assert "CVE-2023-5678" in cves
    
    def test_extract_no_duplicates(self):
        """Test no duplicate CVEs."""
        text = "CVE-2024-12345 CVE-2024-12345 CVE-2024-12345"
        cves = extract_cve_ids(text)
        assert len(cves) == 1
    
    def test_extract_case_insensitive(self):
        """Test case insensitive extraction."""
        text = "cve-2024-12345 CVE-2024-5678"
        cves = extract_cve_ids(text)
        assert len(cves) == 2


class TestCommitExtraction:
    """Tests for commit SHA extraction."""
    
    def test_extract_github_commit(self):
        """Test extracting from GitHub URL."""
        url = "https://github.com/torvalds/linux/commit/" + "a" * 40
        sha = extract_commit_sha(url)
        assert sha == "a" * 40
    
    def test_extract_kernel_org_stable(self):
        """Test extracting from kernel.org stable URL."""
        url = "https://git.kernel.org/stable/c/" + "b" * 40
        sha = extract_commit_sha(url)
        assert sha == "b" * 40
    
    def test_extract_kernel_org_id(self):
        """Test extracting from kernel.org id parameter."""
        url = "https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git/commit/?id=" + "c" * 40
        sha = extract_commit_sha(url)
        assert sha == "c" * 40
    
    def test_extract_no_commit(self):
        """Test URL without commit."""
        url = "https://example.com/page"
        sha = extract_commit_sha(url)
        assert sha is None


class TestTargetExpansion:
    """Tests for target expansion."""
    
    def test_expand_all(self):
        """Test expanding ALL target."""
        specs = ["linux.spec", "linux-esx.spec", "linux-rt.spec"]
        result = expand_targets_to_specs(PatchTarget.ALL, specs)
        assert result == specs
    
    def test_expand_none(self):
        """Test expanding NONE target."""
        specs = ["linux.spec", "linux-esx.spec"]
        result = expand_targets_to_specs(PatchTarget.NONE, specs)
        assert result == []
    
    def test_expand_base(self):
        """Test expanding BASE target."""
        specs = ["linux.spec", "linux-esx.spec", "linux-rt.spec"]
        result = expand_targets_to_specs(PatchTarget.BASE, specs)
        assert result == ["linux.spec"]
    
    def test_expand_esx(self):
        """Test expanding ESX target."""
        specs = ["linux.spec", "linux-esx.spec"]
        result = expand_targets_to_specs(PatchTarget.ESX, specs)
        assert result == ["linux-esx.spec"]
    
    def test_expand_missing_spec(self):
        """Test expanding when spec not available."""
        specs = ["linux.spec"]  # No RT spec
        result = expand_targets_to_specs(PatchTarget.RT, specs)
        assert result == []


class TestSHA512:
    """Tests for SHA512 calculation."""
    
    def test_calculate_sha512(self, tmp_path):
        """Test SHA512 calculation."""
        test_file = tmp_path / "test.txt"
        test_file.write_text("Hello, World!")
        
        sha = calculate_sha512(test_file)
        
        assert len(sha) == 128
        assert all(c in "0123456789abcdef" for c in sha)
    
    def test_sha512_consistency(self, tmp_path):
        """Test SHA512 produces consistent results."""
        test_file = tmp_path / "test.txt"
        test_file.write_bytes(b"Test content")
        
        sha1 = calculate_sha512(test_file)
        sha2 = calculate_sha512(test_file)
        
        assert sha1 == sha2


class TestFormatDuration:
    """Tests for duration formatting."""
    
    def test_seconds(self):
        """Test seconds format."""
        assert format_duration(30) == "30s"
        assert format_duration(59) == "59s"
    
    def test_minutes(self):
        """Test minutes format."""
        assert format_duration(60) == "1m 0s"
        assert format_duration(125) == "2m 5s"
    
    def test_hours(self):
        """Test hours format."""
        assert format_duration(3600) == "1h 0m"
        assert format_duration(3725) == "1h 2m"
