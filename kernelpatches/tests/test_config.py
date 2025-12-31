"""Tests for config module."""

import pytest
from pathlib import Path

from scripts.config import (
    KernelConfig,
    KernelMapping,
    KernelBranch,
    KERNEL_MAPPINGS,
    SUPPORTED_KERNELS,
    get_branch_for_kernel,
    get_spec_files_for_kernel,
    get_kernel_org_url,
    validate_kernel_version,
)


class TestKernelMapping:
    """Tests for KernelMapping class."""
    
    def test_kernel_510_mapping(self):
        """Test kernel 5.10 mapping."""
        mapping = KERNEL_MAPPINGS["5.10"]
        assert mapping.version == "5.10"
        assert mapping.branch == KernelBranch.PHOTON_4
        assert mapping.spec_dir == "SPECS/linux"
        assert "linux.spec" in mapping.spec_files
        assert "linux-esx.spec" in mapping.spec_files
        assert "linux-rt.spec" in mapping.spec_files
    
    def test_kernel_61_mapping(self):
        """Test kernel 6.1 mapping."""
        mapping = KERNEL_MAPPINGS["6.1"]
        assert mapping.version == "6.1"
        assert mapping.branch == KernelBranch.PHOTON_5
        assert mapping.spec_dir == "SPECS/linux"
    
    def test_kernel_612_mapping(self):
        """Test kernel 6.12 mapping."""
        mapping = KERNEL_MAPPINGS["6.12"]
        assert mapping.version == "6.12"
        assert mapping.branch == KernelBranch.COMMON
        assert mapping.spec_dir == "SPECS/linux/v6.12"
        assert "linux-rt.spec" not in mapping.spec_files
    
    def test_major_version(self):
        """Test major_version property."""
        mapping = KERNEL_MAPPINGS["5.10"]
        assert mapping.major_version == 5
        
        mapping = KERNEL_MAPPINGS["6.1"]
        assert mapping.major_version == 6
    
    def test_kernel_org_url(self):
        """Test kernel_org_url property."""
        mapping = KERNEL_MAPPINGS["5.10"]
        assert "v5.x" in mapping.kernel_org_url
        
        mapping = KERNEL_MAPPINGS["6.1"]
        assert "v6.x" in mapping.kernel_org_url


class TestKernelConfig:
    """Tests for KernelConfig class."""
    
    def test_default_config(self):
        """Test default configuration."""
        config = KernelConfig()
        assert config.network_timeout == 30
        assert config.network_retries == 3
        assert config.cve_patch_min == 100
        assert config.cve_patch_max == 499
    
    def test_get_kernel_mapping(self):
        """Test get_kernel_mapping method."""
        config = KernelConfig()
        
        mapping = config.get_kernel_mapping("6.1")
        assert mapping is not None
        assert mapping.version == "6.1"
        
        mapping = config.get_kernel_mapping("invalid")
        assert mapping is None
    
    def test_from_env(self, monkeypatch):
        """Test configuration from environment."""
        monkeypatch.setenv("KERNEL_BACKPORT_TIMEOUT", "60")
        monkeypatch.setenv("KERNEL_BACKPORT_RETRIES", "5")
        
        config = KernelConfig.from_env()
        assert config.network_timeout == 60
        assert config.network_retries == 5


class TestHelperFunctions:
    """Tests for helper functions."""
    
    def test_supported_kernels(self):
        """Test supported kernels list."""
        assert "5.10" in SUPPORTED_KERNELS
        assert "6.1" in SUPPORTED_KERNELS
        assert "6.12" in SUPPORTED_KERNELS
    
    def test_get_branch_for_kernel(self):
        """Test get_branch_for_kernel function."""
        assert get_branch_for_kernel("5.10") == "4.0"
        assert get_branch_for_kernel("6.1") == "5.0"
        assert get_branch_for_kernel("6.12") == "common"
        assert get_branch_for_kernel("invalid") is None
    
    def test_get_spec_files_for_kernel(self):
        """Test get_spec_files_for_kernel function."""
        specs = get_spec_files_for_kernel("5.10")
        assert "linux.spec" in specs
        assert "linux-esx.spec" in specs
        
        specs = get_spec_files_for_kernel("invalid")
        assert specs == []
    
    def test_get_kernel_org_url(self):
        """Test get_kernel_org_url function."""
        url = get_kernel_org_url("5.10")
        assert url is not None
        assert "cdn.kernel.org" in url
        assert "v5.x" in url
        
        url = get_kernel_org_url("invalid")
        assert url is None
    
    def test_validate_kernel_version(self):
        """Test validate_kernel_version function."""
        assert validate_kernel_version("5.10") is True
        assert validate_kernel_version("6.1") is True
        assert validate_kernel_version("6.12") is True
        assert validate_kernel_version("invalid") is False
        assert validate_kernel_version("5.11") is False
