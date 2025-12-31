"""
Source tarball verification for CVE patches.

Downloads and extracts the stable kernel source tarball from Broadcom artifactory
to check if CVE patches are already included before adding them to spec files.
"""

import hashlib
import lzma
import re
import shutil
import tarfile
import tempfile
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import requests

from scripts.common import logger
from scripts.config import DEFAULT_CONFIG, KernelConfig


@dataclass
class PatchVerificationResult:
    """Result of checking if a patch is already included in source."""
    sha: str
    cve_id: Optional[str] = None
    is_included: bool = False
    match_reason: str = ""
    checked_files: int = 0
    confidence: float = 0.0


class SourceVerificationError(Exception):
    """Exception raised for source verification errors."""
    pass


class SourceVerifier:
    """
    Verifies if CVE patches are already included in the stable kernel source.
    
    Downloads the kernel source tarball from Broadcom artifactory and extracts
    it to a temporary directory for verification.
    """
    
    # Minimum confidence threshold for considering a patch included
    INCLUSION_THRESHOLD = 0.70
    
    # Maximum lines to check per file for performance
    MAX_LINES_TO_CHECK = 15
    
    # Minimum line length to consider significant
    MIN_SIGNIFICANT_LINE_LENGTH = 8
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
        self._source_dir: Optional[Path] = None
        self._source_version: Optional[str] = None
        self._extracted: bool = False
        self._temp_dir: Optional[Path] = None
        self._cache_dir = self.config.cache_dir / "source_tarballs"
        self._cache_dir.mkdir(parents=True, exist_ok=True)
    
    def _get_tarball_url(self, version: str) -> str:
        """Get the URL for kernel source tarball."""
        base_url = self.config.photon_sources_url
        return f"{base_url}linux-{version}.tar.xz"
    
    def _get_cached_tarball_path(self, version: str) -> Path:
        """Get path for cached tarball."""
        return self._cache_dir / f"linux-{version}.tar.xz"
    
    def _download_with_retry(
        self,
        url: str,
        dest_path: Path,
        max_retries: int = 3,
        timeout: int = 600,
    ) -> bool:
        """
        Download file with retry logic.
        
        Args:
            url: URL to download
            dest_path: Destination path
            max_retries: Maximum retry attempts
            timeout: Download timeout in seconds
        
        Returns:
            True if download succeeded
        """
        dest_path.parent.mkdir(parents=True, exist_ok=True)
        
        for attempt in range(1, max_retries + 1):
            try:
                logger.info(f"Download attempt {attempt}/{max_retries}: {url}")
                
                with requests.get(url, stream=True, timeout=timeout) as response:
                    response.raise_for_status()
                    total_size = int(response.headers.get("content-length", 0))
                    
                    downloaded = 0
                    with open(dest_path, "wb") as f:
                        for chunk in response.iter_content(chunk_size=8192):
                            f.write(chunk)
                            downloaded += len(chunk)
                            
                            if total_size > 0:
                                pct = (downloaded / total_size) * 100
                                if downloaded % (10 * 1024 * 1024) < 8192:
                                    logger.debug(f"  Downloaded {downloaded // (1024*1024)}MB ({pct:.1f}%)")
                
                logger.info(f"Download complete: {dest_path} ({downloaded // (1024*1024)}MB)")
                return True
                
            except requests.exceptions.RequestException as e:
                logger.warning(f"Download attempt {attempt} failed: {e}")
                if dest_path.exists():
                    dest_path.unlink()
                
                if attempt < max_retries:
                    wait_time = 5 * attempt
                    logger.info(f"Retrying in {wait_time} seconds...")
                    time.sleep(wait_time)
        
        logger.error(f"Failed to download after {max_retries} attempts: {url}")
        return False
    
    def download_source(self, version: str, force: bool = False) -> Optional[Path]:
        """
        Download kernel source tarball from Broadcom artifactory.
        
        Args:
            version: Kernel version (e.g., "5.10.247")
            force: Force re-download even if cached
        
        Returns:
            Path to downloaded tarball or None on failure
        """
        tarball_path = self._get_cached_tarball_path(version)
        
        if tarball_path.exists() and not force:
            file_size = tarball_path.stat().st_size
            if file_size > 1024 * 1024:  # At least 1MB
                logger.info(f"Using cached source tarball: {tarball_path} ({file_size // (1024*1024)}MB)")
                return tarball_path
            else:
                logger.warning(f"Cached tarball too small ({file_size} bytes), re-downloading")
                tarball_path.unlink()
        
        url = self._get_tarball_url(version)
        logger.info(f"Downloading kernel source from: {url}")
        
        # Verify URL exists before downloading
        try:
            response = requests.head(url, timeout=30, allow_redirects=True)
            if response.status_code == 404:
                logger.error(f"Source tarball not found at URL: {url}")
                return None
            elif response.status_code >= 400:
                logger.warning(f"HEAD request returned {response.status_code}, attempting download anyway")
        except requests.exceptions.RequestException as e:
            logger.warning(f"HEAD check failed ({e}), attempting download anyway")
        
        if self._download_with_retry(url, tarball_path):
            return tarball_path
        
        return None
    
    def extract_source(self, version: str, force: bool = False) -> Optional[Path]:
        """
        Extract kernel source tarball to temporary directory.
        
        Args:
            version: Kernel version
            force: Force re-extraction
        
        Returns:
            Path to extracted source directory or None on failure
        """
        # Return cached extraction if valid
        if (self._extracted and self._source_version == version and 
            self._source_dir and self._source_dir.exists() and not force):
            return self._source_dir
        
        # Ensure tarball exists
        tarball_path = self._get_cached_tarball_path(version)
        if not tarball_path.exists():
            tarball_path = self.download_source(version)
            if not tarball_path:
                return None
        
        # Clean up previous extraction
        self.cleanup()
        
        # Create temp directory
        self._temp_dir = Path(tempfile.mkdtemp(prefix=f"kernel-source-{version}-"))
        logger.info(f"Extracting source tarball to: {self._temp_dir}")
        
        try:
            # Extract with progress logging
            with lzma.open(tarball_path) as xz_file:
                with tarfile.open(fileobj=xz_file, mode='r:') as tar:
                    members = tar.getmembers()
                    total_members = len(members)
                    logger.info(f"Extracting {total_members} files...")
                    
                    for idx, member in enumerate(members):
                        tar.extract(member, self._temp_dir)
                        if (idx + 1) % 10000 == 0:
                            logger.debug(f"  Extracted {idx + 1}/{total_members} files")
            
            # Find the extracted directory (usually linux-X.Y.Z)
            extracted_dirs = [d for d in self._temp_dir.iterdir() if d.is_dir()]
            if len(extracted_dirs) == 1:
                self._source_dir = extracted_dirs[0]
            else:
                self._source_dir = self._temp_dir
            
            self._source_version = version
            self._extracted = True
            
            logger.info(f"Source extracted successfully: {self._source_dir}")
            return self._source_dir
            
        except lzma.LZMAError as e:
            logger.error(f"Failed to decompress tarball (corrupt file?): {e}")
            # Remove corrupt cached file
            if tarball_path.exists():
                tarball_path.unlink()
            self.cleanup()
            return None
            
        except tarfile.TarError as e:
            logger.error(f"Failed to extract tarball: {e}")
            self.cleanup()
            return None
            
        except Exception as e:
            logger.error(f"Unexpected error during extraction: {e}")
            self.cleanup()
            return None
    
    def cleanup(self) -> None:
        """Clean up temporary extraction directory."""
        if self._temp_dir and self._temp_dir.exists():
            try:
                shutil.rmtree(self._temp_dir, ignore_errors=True)
            except Exception as e:
                logger.warning(f"Failed to cleanup temp directory: {e}")
        
        self._temp_dir = None
        self._source_dir = None
        self._extracted = False
        self._source_version = None
    
    def _normalize_line(self, line: str) -> str:
        """Normalize a line for comparison (collapse whitespace)."""
        return ' '.join(line.split())
    
    def _is_significant_line(self, line: str) -> bool:
        """Check if a line is significant for comparison."""
        stripped = line.strip()
        
        # Skip empty lines
        if not stripped:
            return False
        
        # Skip very short lines
        if len(stripped) < self.MIN_SIGNIFICANT_LINE_LENGTH:
            return False
        
        # Skip comments
        if stripped.startswith('//') or stripped.startswith('/*') or stripped.startswith('*'):
            return False
        
        # Skip simple braces
        if stripped in ('{', '}', '};', '});'):
            return False
        
        # Skip preprocessor directives (usually too generic)
        if stripped.startswith('#include') or stripped.startswith('#define'):
            return False
        
        return True
    
    def _extract_patch_hunks(self, patch_content: str) -> List[Dict[str, Any]]:
        """
        Extract file paths and content changes from a patch.
        
        Returns:
            List of dicts with 'file', 'added_lines', 'removed_lines'
        """
        hunks = []
        current_file = None
        added_lines: List[str] = []
        removed_lines: List[str] = []
        
        for line in patch_content.split('\n'):
            # New file in patch
            if line.startswith('+++ b/'):
                if current_file:
                    hunks.append({
                        'file': current_file,
                        'added_lines': added_lines,
                        'removed_lines': removed_lines,
                    })
                current_file = line[6:].strip()
                added_lines = []
                removed_lines = []
                
            # Added line
            elif line.startswith('+') and not line.startswith('+++'):
                content = line[1:]
                if self._is_significant_line(content):
                    added_lines.append(content.strip())
                    
            # Removed line
            elif line.startswith('-') and not line.startswith('---'):
                content = line[1:]
                if self._is_significant_line(content):
                    removed_lines.append(content.strip())
        
        # Don't forget the last file
        if current_file:
            hunks.append({
                'file': current_file,
                'added_lines': added_lines,
                'removed_lines': removed_lines,
            })
        
        return hunks
    
    def _check_lines_in_file(
        self,
        source_file: Path,
        added_lines: List[str],
        removed_lines: List[str],
    ) -> Tuple[bool, str, float]:
        """
        Check if patch changes are already applied to source file.
        
        Returns:
            Tuple of (is_included, reason, confidence)
        """
        # File doesn't exist
        if not source_file.exists():
            if added_lines and not removed_lines:
                # Patch adds to file that doesn't exist - not included
                return False, "file not found but patch adds content", 0.0
            elif removed_lines and not added_lines:
                # Patch only removes from file - likely already done
                return True, "file not found (removal patch)", 0.9
            else:
                # Mixed patch on missing file - uncertain
                return False, "file not found (mixed patch)", 0.3
        
        # Read file content
        try:
            file_content = source_file.read_text(errors='ignore')
            normalized_content = self._normalize_line(file_content)
        except Exception as e:
            return False, f"could not read file: {e}", 0.0
        
        # Check added lines
        lines_to_check_add = added_lines[:self.MAX_LINES_TO_CHECK]
        added_found = 0
        
        for line in lines_to_check_add:
            normalized_line = self._normalize_line(line)
            if len(normalized_line) >= self.MIN_SIGNIFICANT_LINE_LENGTH:
                if normalized_line in normalized_content:
                    added_found += 1
        
        # Check removed lines
        lines_to_check_rem = removed_lines[:self.MAX_LINES_TO_CHECK]
        removed_found = 0
        
        for line in lines_to_check_rem:
            normalized_line = self._normalize_line(line)
            if len(normalized_line) >= self.MIN_SIGNIFICANT_LINE_LENGTH:
                if normalized_line in normalized_content:
                    removed_found += 1
        
        total_added = len(lines_to_check_add)
        total_removed = len(lines_to_check_rem)
        
        # No significant lines to check
        if total_added == 0 and total_removed == 0:
            return False, "no significant lines to check", 0.0
        
        # Calculate inclusion metrics
        add_ratio = added_found / total_added if total_added > 0 else 1.0
        rem_ratio = removed_found / total_removed if total_removed > 0 else 0.0
        
        # Determine if patch is included
        if total_added > 0 and add_ratio >= self.INCLUSION_THRESHOLD:
            if total_removed > 0 and rem_ratio > 0.5:
                # Added lines present but removed lines still exist
                return False, f"added present but removed lines still exist", add_ratio * 0.5
            confidence = add_ratio
            return True, f"added lines present ({added_found}/{total_added})", confidence
        
        if total_removed > 0 and rem_ratio == 0:
            # All removed lines are already gone
            if total_added == 0:
                return True, "removed lines already absent", 0.85
        
        # Default: not included
        confidence = (add_ratio * 0.7 + (1 - rem_ratio) * 0.3) if total_removed > 0 else add_ratio
        return False, f"added: {added_found}/{total_added}, removed: {removed_found}/{total_removed}", confidence
    
    def check_patch_included(
        self,
        patch_content: str,
        sha: str,
        cve_id: Optional[str] = None,
    ) -> PatchVerificationResult:
        """
        Check if a patch is already included in the extracted source.
        
        Args:
            patch_content: Content of the patch file
            sha: Commit SHA
            cve_id: Optional CVE ID
        
        Returns:
            PatchVerificationResult
        """
        result = PatchVerificationResult(sha=sha, cve_id=cve_id)
        
        if not self._extracted or not self._source_dir:
            result.match_reason = "source not extracted"
            return result
        
        hunks = self._extract_patch_hunks(patch_content)
        if not hunks:
            result.match_reason = "no hunks found in patch"
            return result
        
        files_checked = 0
        files_included = 0
        total_confidence = 0.0
        
        for hunk in hunks:
            file_path = hunk['file']
            source_file = self._source_dir / file_path
            files_checked += 1
            
            included, reason, confidence = self._check_lines_in_file(
                source_file,
                hunk['added_lines'],
                hunk['removed_lines'],
            )
            
            total_confidence += confidence
            
            if included:
                files_included += 1
        
        result.checked_files = files_checked
        
        if files_checked > 0:
            avg_confidence = total_confidence / files_checked
            inclusion_ratio = files_included / files_checked
            result.confidence = avg_confidence
            
            if inclusion_ratio >= self.INCLUSION_THRESHOLD:
                result.is_included = True
                result.match_reason = f"patch included ({files_included}/{files_checked} files, {avg_confidence:.0%} confidence)"
            else:
                result.match_reason = f"patch not included ({files_included}/{files_checked} files, {avg_confidence:.0%} confidence)"
        else:
            result.match_reason = "no files to check"
        
        return result
    
    def verify_patches(
        self,
        patches: List[Tuple[str, str, Optional[str]]],
        version: str,
    ) -> Dict[str, PatchVerificationResult]:
        """
        Verify multiple patches against source tarball.
        
        Args:
            patches: List of (sha, patch_content, cve_id) tuples
            version: Kernel version to check against
        
        Returns:
            Dict mapping SHA to verification result
        """
        if not patches:
            logger.info("No patches to verify")
            return {}
        
        source_dir = self.extract_source(version)
        if not source_dir:
            logger.error(f"Failed to extract source for version {version}")
            return {
                sha: PatchVerificationResult(
                    sha=sha, 
                    cve_id=cve_id, 
                    match_reason="source extraction failed"
                )
                for sha, _, cve_id in patches
            }
        
        results: Dict[str, PatchVerificationResult] = {}
        total = len(patches)
        included_count = 0
        
        logger.info(f"Verifying {total} patches against kernel {version} source")
        
        for idx, (sha, patch_content, cve_id) in enumerate(patches, 1):
            result = self.check_patch_included(patch_content, sha, cve_id)
            results[sha] = result
            
            status = "INCLUDED" if result.is_included else "NOT INCLUDED"
            log_msg = f"  [{idx}/{total}] {sha[:12]} ({cve_id or 'N/A'}): {status}"
            
            if result.is_included:
                included_count += 1
                logger.info(f"{log_msg} - {result.match_reason}")
            else:
                logger.debug(f"{log_msg} - {result.match_reason}")
        
        logger.info(f"Verification complete: {included_count}/{total} patches already included in source")
        
        return results
    
    def __enter__(self) -> 'SourceVerifier':
        return self
    
    def __exit__(self, exc_type, exc_val, exc_tb) -> None:
        self.cleanup()


def check_patches_in_source(
    kernel_version: str,
    patches: List[Tuple[str, str, Optional[str]]],
    config: Optional[KernelConfig] = None,
) -> Dict[str, PatchVerificationResult]:
    """
    Check if patches are already included in kernel source.
    
    This is a convenience function that handles verifier lifecycle.
    
    Args:
        kernel_version: Full kernel version (e.g., "5.10.247")
        patches: List of (sha, patch_content, cve_id) tuples
        config: Optional configuration
    
    Returns:
        Dict mapping SHA to verification result
    """
    cfg = config or DEFAULT_CONFIG
    
    with SourceVerifier(config=cfg) as verifier:
        return verifier.verify_patches(patches, kernel_version)
