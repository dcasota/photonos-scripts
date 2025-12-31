"""
Spec file parsing and manipulation for kernel packages.
"""

import re
import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from scripts.common import logger
from scripts.models import SpecPatch


class SpecFile:
    """
    Represents and manipulates a kernel RPM spec file.
    
    Handles parsing, modification, and validation of spec files including:
    - Version and release management
    - Patch entry manipulation
    - Changelog updates
    - SHA512 hash management
    """
    
    def __init__(self, path: Path):
        """
        Initialize SpecFile from a file path.
        
        Args:
            path: Path to the spec file
        """
        self.path = Path(path)
        self._content: Optional[str] = None
        self._lines: Optional[List[str]] = None
        
        if not self.path.exists():
            raise FileNotFoundError(f"Spec file not found: {self.path}")
    
    @property
    def content(self) -> str:
        """Get file content, loading if necessary."""
        if self._content is None:
            self._content = self.path.read_text()
        return self._content
    
    @property
    def lines(self) -> List[str]:
        """Get file lines, loading if necessary."""
        if self._lines is None:
            self._lines = self.content.splitlines()
        return self._lines
    
    def reload(self) -> None:
        """Reload file content from disk."""
        self._content = None
        self._lines = None
    
    def save(self) -> None:
        """Save current content to disk."""
        if self._lines is not None:
            self._content = "\n".join(self._lines)
            if not self._content.endswith("\n"):
                self._content += "\n"
        if self._content is not None:
            self.path.write_text(self._content)
    
    def backup(self, backup_dir: Path) -> Path:
        """
        Create a backup of the spec file.
        
        Args:
            backup_dir: Directory to store backup
        
        Returns:
            Path to backup file
        """
        backup_dir.mkdir(parents=True, exist_ok=True)
        backup_path = backup_dir / f"{self.path.name}.backup"
        shutil.copy2(self.path, backup_path)
        return backup_path
    
    # -------------------------------------------------------------------------
    # Property Extraction
    # -------------------------------------------------------------------------
    
    @property
    def name(self) -> str:
        """Get package name from spec file."""
        match = re.search(r"^Name:\s*(.+)$", self.content, re.MULTILINE)
        return match.group(1).strip() if match else ""
    
    @property
    def version(self) -> str:
        """Get Version from spec file."""
        match = re.search(r"^Version:\s*([0-9.]+)", self.content, re.MULTILINE)
        return match.group(1).strip() if match else ""
    
    @property
    def release(self) -> int:
        """Get Release number from spec file."""
        match = re.search(r"^Release:\s*(\d+)", self.content, re.MULTILINE)
        return int(match.group(1)) if match else 0
    
    def get_sha512(self, source_name: str = "linux") -> Optional[str]:
        """
        Get SHA512 hash for a source.
        
        Args:
            source_name: Name identifier in sha512 define
        
        Returns:
            SHA512 hash string or None
        """
        pattern = rf"^%define\s+sha512\s+{re.escape(source_name)}=([0-9a-f]+)"
        match = re.search(pattern, self.content, re.MULTILINE)
        return match.group(1) if match else None
    
    def get_patches(self, min_num: int = 0, max_num: int = 999) -> List[SpecPatch]:
        """
        Get all patches in a number range.
        
        Args:
            min_num: Minimum patch number (inclusive)
            max_num: Maximum patch number (inclusive)
        
        Returns:
            List of SpecPatch objects
        """
        patches = []
        pattern = re.compile(r"^Patch(\d+):\s*(.+)$")
        
        for line in self.lines:
            match = pattern.match(line)
            if match:
                num = int(match.group(1))
                if min_num <= num <= max_num:
                    name = match.group(2).strip()
                    cve_ids = re.findall(r"CVE-\d{4}-\d+", name, re.IGNORECASE)
                    patches.append(SpecPatch(number=num, name=name, cve_ids=cve_ids))
        
        return sorted(patches, key=lambda p: p.number)
    
    def get_cve_patches(self, cve_min: int = 100, cve_max: int = 499) -> List[SpecPatch]:
        """Get patches in the CVE range (100-499 by default)."""
        return self.get_patches(cve_min, cve_max)
    
    def get_next_patch_number(self, min_num: int = 100, max_num: int = 499) -> int:
        """
        Get the next available patch number in a range.
        
        Args:
            min_num: Start of range
            max_num: End of range
        
        Returns:
            Next available number, or -1 if range is full
        """
        patches = self.get_patches(min_num, max_num)
        if not patches:
            return min_num
        
        last_num = max(p.number for p in patches)
        if last_num >= max_num:
            return -1
        return last_num + 1
    
    def has_patch(self, sha_prefix: str) -> bool:
        """Check if a patch with given SHA prefix is already in spec."""
        return sha_prefix.lower() in self.content.lower()
    
    # -------------------------------------------------------------------------
    # Modification Methods
    # -------------------------------------------------------------------------
    
    def set_version(self, new_version: str) -> bool:
        """
        Update the Version field.
        
        Args:
            new_version: New version string
        
        Returns:
            True if updated successfully
        """
        old_version = self.version
        if not old_version:
            logger.error(f"Could not find Version in {self.path.name}")
            return False
        
        pattern = rf"^(Version:\s*){re.escape(old_version)}"
        new_content = re.sub(pattern, rf"\g<1>{new_version}", self.content, flags=re.MULTILINE)
        
        if new_content == self.content:
            logger.warning(f"Version unchanged in {self.path.name}")
            return False
        
        self._content = new_content
        self._lines = None
        logger.info(f"Updated Version: {old_version} -> {new_version} in {self.path.name}")
        return True
    
    def set_release(self, new_release: int) -> bool:
        """
        Update the Release number.
        
        Args:
            new_release: New release number
        
        Returns:
            True if updated successfully
        """
        old_release = self.release
        pattern = rf"^(Release:\s*){old_release}(%.*)"
        new_content = re.sub(pattern, rf"\g<1>{new_release}\g<2>", self.content, flags=re.MULTILINE)
        
        if new_content == self.content:
            logger.warning(f"Release unchanged in {self.path.name}")
            return False
        
        self._content = new_content
        self._lines = None
        logger.info(f"Updated Release: {old_release} -> {new_release} in {self.path.name}")
        return True
    
    def increment_release(self) -> int:
        """
        Increment the Release number by 1.
        
        Returns:
            New release number, or -1 on failure
        """
        current = self.release
        new_release = current + 1
        if self.set_release(new_release):
            return new_release
        return -1
    
    def reset_release(self) -> bool:
        """Reset Release to 1."""
        return self.set_release(1)
    
    def set_sha512(self, source_name: str, new_sha512: str) -> bool:
        """
        Update SHA512 hash for a source.
        
        Args:
            source_name: Name identifier in sha512 define
            new_sha512: New SHA512 hash value
        
        Returns:
            True if updated successfully
        """
        if len(new_sha512) != 128 or not all(c in "0123456789abcdef" for c in new_sha512.lower()):
            logger.error(f"Invalid SHA512 hash format: {new_sha512}")
            return False
        
        old_sha512 = self.get_sha512(source_name)
        if not old_sha512:
            logger.error(f"No existing SHA512 for '{source_name}' in {self.path.name}")
            return False
        
        if old_sha512 == new_sha512:
            logger.info(f"SHA512 unchanged for {source_name}")
            return True
        
        pattern = rf"^(%define\s+sha512\s+{re.escape(source_name)}=)[0-9a-f]+"
        new_content = re.sub(pattern, rf"\g<1>{new_sha512}", self.content, flags=re.MULTILINE)
        
        if new_content == self.content:
            logger.warning(f"SHA512 unchanged in {self.path.name}")
            return False
        
        self._content = new_content
        self._lines = None
        logger.info(f"Updated SHA512 for {source_name} in {self.path.name}")
        return True
    
    def add_patch(self, patch_name: str, patch_number: int) -> bool:
        """
        Add a new patch entry to the spec file.
        
        Args:
            patch_name: Name of the patch file
            patch_number: Patch number to assign
        
        Returns:
            True if added successfully
        """
        lines = self.lines.copy()
        
        # Find the last Patch line
        last_patch_idx = -1
        for i, line in enumerate(lines):
            if re.match(r"^Patch\d+:", line):
                last_patch_idx = i
        
        if last_patch_idx == -1:
            logger.error(f"No existing Patch lines found in {self.path.name}")
            return False
        
        # Insert new Patch definition after last one
        patch_line = f"Patch{patch_number}: {patch_name}"
        lines.insert(last_patch_idx + 1, patch_line)
        
        # Find and update %patch application section
        last_apply_idx = -1
        for i, line in enumerate(lines):
            if re.match(r"^%patch\d+\s+-p1", line):
                last_apply_idx = i
        
        if last_apply_idx > 0:
            apply_line = f"%patch{patch_number} -p1"
            lines.insert(last_apply_idx + 1, apply_line)
        
        self._lines = lines
        self._content = None
        logger.info(f"Added Patch{patch_number}: {patch_name} to {self.path.name}")
        return True
    
    def remove_patch(self, patch_number: int) -> bool:
        """
        Remove a patch entry from the spec file.
        
        Args:
            patch_number: Patch number to remove
        
        Returns:
            True if removed successfully
        """
        lines = self.lines.copy()
        removed = False
        
        # Remove Patch definition line
        patch_pattern = re.compile(rf"^Patch{patch_number}:")
        lines = [l for l in lines if not patch_pattern.match(l)]
        
        # Remove %patch application line
        apply_pattern = re.compile(rf"^%patch{patch_number}\s")
        lines = [l for l in lines if not apply_pattern.match(l)]
        
        if len(lines) < len(self.lines):
            removed = True
            self._lines = lines
            self._content = None
            logger.info(f"Removed Patch{patch_number} from {self.path.name}")
        
        return removed
    
    def add_changelog_entry(
        self,
        version: str,
        release: int,
        message: str,
        author: str = "Kernel Backport Script <kernel-backport@photon.local>",
    ) -> bool:
        """
        Add a changelog entry to the spec file.
        
        Args:
            version: Package version
            release: Package release
            message: Changelog message
            author: Author name and email
        
        Returns:
            True if added successfully
        """
        lines = self.lines.copy()
        
        # Find %changelog line
        changelog_idx = -1
        for i, line in enumerate(lines):
            if line.strip() == "%changelog":
                changelog_idx = i
                break
        
        if changelog_idx == -1:
            logger.error(f"No %changelog section found in {self.path.name}")
            return False
        
        # Format date
        date_str = datetime.now().strftime("%a %b %d %Y")
        
        # Create changelog entry
        entry_lines = [
            f"* {date_str} {author} {version}-{release}",
            f"- {message}",
        ]
        
        # Insert after %changelog
        for i, entry_line in enumerate(entry_lines):
            lines.insert(changelog_idx + 1 + i, entry_line)
        
        self._lines = lines
        self._content = None
        logger.info(f"Added changelog entry to {self.path.name}")
        return True
    
    # -------------------------------------------------------------------------
    # Validation
    # -------------------------------------------------------------------------
    
    def validate(self) -> Tuple[bool, List[str]]:
        """
        Validate spec file syntax.
        
        Returns:
            Tuple of (is_valid, list_of_errors)
        """
        errors = []
        
        # Check required fields
        if not self.name:
            errors.append("Missing Name field")
        if not self.version:
            errors.append("Missing Version field")
        if self.release <= 0:
            errors.append("Invalid Release field")
        
        # Check for %changelog
        if "%changelog" not in self.content:
            errors.append("Missing %changelog section")
        
        # Check patch numbering consistency
        patches = self.get_patches()
        patch_nums = [p.number for p in patches]
        if len(patch_nums) != len(set(patch_nums)):
            errors.append("Duplicate patch numbers found")
        
        return len(errors) == 0, errors
    
    def validate_with_rpmspec(self) -> bool:
        """Validate using rpmspec command."""
        from scripts.common import run_command
        
        returncode, _, stderr = run_command(
            ["rpmspec", "--parse", str(self.path)],
            capture_output=True,
        )
        
        if returncode != 0:
            logger.error(f"rpmspec validation failed: {stderr}")
            return False
        return True
    
    # -------------------------------------------------------------------------
    # Utility Methods
    # -------------------------------------------------------------------------
    
    def extract_all_cve_ids(self) -> List[str]:
        """Extract all CVE IDs referenced in the spec file."""
        pattern = r"CVE-\d{4}-\d{4,}"
        return list(set(re.findall(pattern, self.content, re.IGNORECASE)))
    
    def get_patch_count(self, min_num: int = 0, max_num: int = 999) -> int:
        """Get count of patches in a number range."""
        return len(self.get_patches(min_num, max_num))
    
    def __repr__(self) -> str:
        return f"SpecFile({self.path.name}, version={self.version}, release={self.release})"
