"""Tests for spec_file module."""

import pytest
from pathlib import Path

from scripts.spec_file import SpecFile


SAMPLE_SPEC = """
Name:           linux
Summary:        Kernel
Version:        6.1.159
Release:        1%{?dist}
License:        GPLv2
Group:          System Environment/Kernel
Vendor:         VMware, Inc.
URL:            https://www.kernel.org/
Source0:        https://www.kernel.org/pub/linux/kernel/v6.x/linux-%{version}.tar.xz
%define sha512 linux=abc123def456abc123def456abc123def456abc123def456abc123def456abc123def456abc123def456abc123def456abc123def456abc123def456abcd

Patch1:         0001-fix.patch
Patch2:         0002-fix.patch
Patch100:       CVE-2024-12345-fix.patch
Patch101:       abc123def456-backport.patch

%description
The Linux kernel.

%prep
%setup -q
%patch1 -p1
%patch2 -p1
%patch100 -p1
%patch101 -p1

%build
make

%changelog
* Mon Jan 01 2024 Maintainer <test@example.com> 6.1.159-1
- Update to version 6.1.159
"""


@pytest.fixture
def spec_file(tmp_path):
    """Create a temporary spec file."""
    spec_path = tmp_path / "linux.spec"
    spec_path.write_text(SAMPLE_SPEC)
    return SpecFile(spec_path)


class TestSpecFileRead:
    """Tests for reading spec files."""
    
    def test_name(self, spec_file):
        """Test name extraction."""
        assert spec_file.name == "linux"
    
    def test_version(self, spec_file):
        """Test version extraction."""
        assert spec_file.version == "6.1.159"
    
    def test_release(self, spec_file):
        """Test release extraction."""
        assert spec_file.release == 1
    
    def test_get_sha512(self, spec_file):
        """Test SHA512 extraction."""
        sha = spec_file.get_sha512("linux")
        assert sha is not None
        assert sha.startswith("abc123")
    
    def test_get_patches(self, spec_file):
        """Test getting all patches."""
        patches = spec_file.get_patches()
        assert len(patches) == 4
        assert patches[0].number == 1
        assert patches[3].number == 101
    
    def test_get_cve_patches(self, spec_file):
        """Test getting CVE patches only."""
        patches = spec_file.get_cve_patches()
        assert len(patches) == 2
        assert all(100 <= p.number <= 499 for p in patches)
    
    def test_get_next_patch_number(self, spec_file):
        """Test getting next available patch number."""
        next_num = spec_file.get_next_patch_number(100, 499)
        assert next_num == 102  # 100 and 101 are taken
    
    def test_has_patch(self, spec_file):
        """Test checking if patch exists."""
        assert spec_file.has_patch("abc123def456") is True
        assert spec_file.has_patch("xyz789") is False
    
    def test_extract_all_cve_ids(self, spec_file):
        """Test extracting all CVE IDs."""
        cves = spec_file.extract_all_cve_ids()
        assert "CVE-2024-12345" in cves


class TestSpecFileWrite:
    """Tests for writing spec files."""
    
    def test_set_version(self, spec_file):
        """Test setting version."""
        assert spec_file.set_version("6.1.160") is True
        spec_file.save()
        spec_file.reload()
        assert spec_file.version == "6.1.160"
    
    def test_set_release(self, spec_file):
        """Test setting release."""
        assert spec_file.set_release(5) is True
        spec_file.save()
        spec_file.reload()
        assert spec_file.release == 5
    
    def test_increment_release(self, spec_file):
        """Test incrementing release."""
        new_release = spec_file.increment_release()
        assert new_release == 2
        spec_file.save()
        spec_file.reload()
        assert spec_file.release == 2
    
    def test_reset_release(self, spec_file):
        """Test resetting release to 1."""
        spec_file.set_release(5)
        spec_file.save()
        
        assert spec_file.reset_release() is True
        spec_file.save()
        spec_file.reload()
        assert spec_file.release == 1
    
    def test_set_sha512(self, spec_file):
        """Test setting SHA512."""
        new_sha = "f" * 128
        assert spec_file.set_sha512("linux", new_sha) is True
        spec_file.save()
        spec_file.reload()
        assert spec_file.get_sha512("linux") == new_sha
    
    def test_set_sha512_invalid(self, spec_file):
        """Test setting invalid SHA512."""
        assert spec_file.set_sha512("linux", "invalid") is False
    
    def test_add_patch(self, spec_file):
        """Test adding a patch."""
        assert spec_file.add_patch("new-fix.patch", 102) is True
        spec_file.save()
        spec_file.reload()
        
        patches = spec_file.get_patches()
        numbers = [p.number for p in patches]
        assert 102 in numbers
    
    def test_remove_patch(self, spec_file):
        """Test removing a patch."""
        assert spec_file.remove_patch(100) is True
        spec_file.save()
        spec_file.reload()
        
        patches = spec_file.get_patches()
        numbers = [p.number for p in patches]
        assert 100 not in numbers
    
    def test_add_changelog_entry(self, spec_file):
        """Test adding changelog entry."""
        assert spec_file.add_changelog_entry(
            "6.1.160", 1,
            "Test changelog entry",
            "Test Author <test@test.com>",
        ) is True
        spec_file.save()
        
        content = spec_file.path.read_text()
        assert "Test changelog entry" in content
        assert "Test Author" in content


class TestSpecFileValidation:
    """Tests for spec file validation."""
    
    def test_validate_valid(self, spec_file):
        """Test validation of valid spec."""
        is_valid, errors = spec_file.validate()
        assert is_valid is True
        assert len(errors) == 0
    
    def test_validate_missing_name(self, tmp_path):
        """Test validation catches missing Name."""
        spec_path = tmp_path / "invalid.spec"
        spec_path.write_text("Version: 1.0\nRelease: 1\n%changelog\n")
        spec = SpecFile(spec_path)
        
        is_valid, errors = spec.validate()
        assert is_valid is False
        assert any("Name" in e for e in errors)
    
    def test_backup(self, spec_file, tmp_path):
        """Test backup creation."""
        backup_dir = tmp_path / "backups"
        backup_path = spec_file.backup(backup_dir)
        
        assert backup_path.exists()
        assert backup_path.read_text() == spec_file.path.read_text()


class TestSpecFileEdgeCases:
    """Tests for edge cases."""
    
    def test_file_not_found(self, tmp_path):
        """Test handling of missing file."""
        with pytest.raises(FileNotFoundError):
            SpecFile(tmp_path / "nonexistent.spec")
    
    def test_get_patch_count(self, spec_file):
        """Test patch count."""
        count = spec_file.get_patch_count()
        assert count == 4
        
        cve_count = spec_file.get_patch_count(100, 499)
        assert cve_count == 2
    
    def test_repr(self, spec_file):
        """Test string representation."""
        repr_str = repr(spec_file)
        assert "linux.spec" in repr_str
        assert "6.1.159" in repr_str
