"""
Stable kernel patch downloading and integration.
"""

import asyncio
import json
import lzma
import shutil
import subprocess
from dataclasses import dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import aiohttp
import requests
from git import Repo
from rich.progress import Progress

from scripts.common import (
    console,
    download_file,
    logger,
    run_command,
    safe_remove_dir,
    version_less_than,
)
from scripts.config import (
    DEFAULT_CONFIG,
    KERNEL_MAPPINGS,
    KernelConfig,
    get_kernel_org_url,
)
from scripts.models import KernelVersion, StablePatchInfo
from scripts.spec_file import SpecFile


@dataclass
class CheckpointState:
    """Checkpoint state for resumable operations."""
    kernel_version: str
    spec_file: str
    canister: int
    acvp: int
    patch_index: int
    patch_count: int
    timestamp: float = field(default_factory=lambda: datetime.now().timestamp())
    
    def save(self, checkpoint_dir: Path) -> None:
        """Save checkpoint to file."""
        checkpoint_dir.mkdir(parents=True, exist_ok=True)
        checkpoint_file = checkpoint_dir / "checkpoint.json"
        
        with open(checkpoint_file, "w") as f:
            json.dump({
                "kernel_version": self.kernel_version,
                "spec_file": self.spec_file,
                "canister": self.canister,
                "acvp": self.acvp,
                "patch_index": self.patch_index,
                "patch_count": self.patch_count,
                "timestamp": self.timestamp,
            }, f)
        
        logger.debug(f"Checkpoint saved: {self.spec_file} c={self.canister} a={self.acvp} patch={self.patch_index}/{self.patch_count}")
    
    @classmethod
    def load(cls, checkpoint_dir: Path) -> Optional["CheckpointState"]:
        """Load checkpoint from file."""
        checkpoint_file = checkpoint_dir / "checkpoint.json"
        
        if not checkpoint_file.exists():
            return None
        
        try:
            with open(checkpoint_file) as f:
                data = json.load(f)
            return cls(**data)
        except Exception as e:
            logger.warning(f"Failed to load checkpoint: {e}")
            return None
    
    @classmethod
    def clear(cls, checkpoint_dir: Path) -> None:
        """Clear checkpoint file."""
        checkpoint_file = checkpoint_dir / "checkpoint.json"
        if checkpoint_file.exists():
            checkpoint_file.unlink()
            logger.debug("Checkpoint cleared")


class StablePatchManager:
    """Manage stable kernel patch operations."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
        self.marker_dir = self.config.cache_dir / "stable_markers"
        self.marker_dir.mkdir(parents=True, exist_ok=True)
    
    def get_current_photon_version(self, kernel_version: str, repo_dir: Path) -> Optional[str]:
        """Get current Photon kernel version from spec file."""
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            return None
        
        spec_path = repo_dir / mapping.spec_dir / "linux.spec"
        if not spec_path.exists():
            return None
        
        spec = SpecFile(spec_path)
        return spec.version
    
    def get_latest_stable_version(self, kernel_version: str) -> Optional[str]:
        """Get latest stable version from kernel.org."""
        kernel_url = get_kernel_org_url(kernel_version)
        if not kernel_url:
            return None
        
        logger.debug(f"Checking latest stable version for {kernel_version}")
        
        try:
            response = requests.get(kernel_url, timeout=30)
            response.raise_for_status()
            listing = response.text
        except Exception as e:
            logger.error(f"Failed to fetch kernel.org listing: {e}")
            return None
        
        # Find latest patch version
        import re
        pattern = rf"patch-{re.escape(kernel_version)}\.(\d+)\.xz"
        matches = re.findall(pattern, listing)
        
        if not matches:
            return None
        
        latest_patch = max(int(m) for m in matches)
        return f"{kernel_version}.{latest_patch}"
    
    def get_last_integrated_version(self, kernel_version: str) -> Optional[str]:
        """Get last integrated stable version from marker file."""
        marker_file = self.marker_dir / f".stable_{kernel_version}_last_version"
        
        if marker_file.exists():
            return marker_file.read_text().strip()
        return None
    
    def update_marker(self, kernel_version: str, version: str) -> None:
        """Update the stable version marker."""
        marker_file = self.marker_dir / f".stable_{kernel_version}_last_version"
        marker_file.write_text(version)
    
    def check_stable_status(
        self,
        kernel_version: str,
        repo_dir: Path,
    ) -> Tuple[str, Optional[str], Optional[str]]:
        """
        Check if Photon kernel is behind stable.
        
        Returns:
            Tuple of (status, current_version, latest_version)
            status: "UPDATE_NEEDED", "UP_TO_DATE", or "ERROR"
        """
        current = self.get_current_photon_version(kernel_version, repo_dir)
        if not current:
            return "ERROR", None, None
        
        latest = self.get_latest_stable_version(kernel_version)
        if not latest:
            return "ERROR", current, None
        
        if version_less_than(current, latest):
            return "UPDATE_NEEDED", current, latest
        else:
            return "UP_TO_DATE", current, latest
    
    def get_versions_behind(self, current: str, latest: str) -> int:
        """Calculate how many versions behind."""
        current_kv = KernelVersion.parse(current)
        latest_kv = KernelVersion.parse(latest)
        return latest_kv.patch - current_kv.patch
    
    async def download_patches(
        self,
        kernel_version: str,
        output_dir: Path,
        start_subver: int = 1,
        end_subver: Optional[int] = None,
    ) -> List[StablePatchInfo]:
        """
        Download stable patches from kernel.org.
        
        Args:
            kernel_version: Kernel series (e.g., "6.1")
            output_dir: Output directory for patches
            start_subver: Starting subversion number
            end_subver: Ending subversion number (optional)
        
        Returns:
            List of StablePatchInfo for downloaded patches
        """
        kernel_url = get_kernel_org_url(kernel_version)
        if not kernel_url:
            return []
        
        patch_dir = output_dir / "stable_patches"
        patch_dir.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Downloading stable patches for kernel {kernel_version}")
        
        patches = []
        patch_num = start_subver
        
        async with aiohttp.ClientSession() as session:
            while True:
                if end_subver and patch_num > end_subver:
                    break
                
                version = f"{kernel_version}.{patch_num}"
                xz_filename = f"patch-{version}.xz"
                xz_url = f"{kernel_url}{xz_filename}"
                xz_path = patch_dir / xz_filename
                patch_path = patch_dir / f"patch-{version}"
                
                try:
                    async with session.get(xz_url, timeout=aiohttp.ClientTimeout(total=60)) as response:
                        if response.status != 200:
                            if patch_num == start_subver:
                                logger.warning(f"No patches found starting from {version}")
                            else:
                                logger.info(f"No more patches after {kernel_version}.{patch_num - 1}")
                            break
                        
                        xz_data = await response.read()
                except Exception as e:
                    logger.warning(f"Failed to download {xz_filename}: {e}")
                    break
                
                # Save and decompress
                xz_path.write_bytes(xz_data)
                
                try:
                    with lzma.open(xz_path) as f:
                        patch_data = f.read()
                    patch_path.write_bytes(patch_data)
                    
                    patches.append(StablePatchInfo(
                        version=version,
                        patch_file=str(patch_path),
                        downloaded=True,
                    ))
                    
                    logger.debug(f"Downloaded: {xz_filename}")
                    
                except Exception as e:
                    logger.warning(f"Failed to decompress {xz_filename}: {e}")
                
                patch_num += 1
        
        logger.info(f"Downloaded {len(patches)} stable patches")
        return patches
    
    def download_patches_sync(
        self,
        kernel_version: str,
        output_dir: Path,
        start_subver: int = 1,
        end_subver: Optional[int] = None,
    ) -> List[StablePatchInfo]:
        """Synchronous wrapper for download_patches."""
        return asyncio.run(self.download_patches(kernel_version, output_dir, start_subver, end_subver))


class StableIntegrator:
    """Integrate stable patches into spec files."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
    
    def check_spec2git_available(self, photon_dir: Path) -> Optional[Path]:
        """Check if spec2git tool is available."""
        spec2git_path = photon_dir / "tools" / "scripts" / "spec2git" / "spec2git.py"
        
        if spec2git_path.exists():
            return spec2git_path
        return None
    
    def integrate_simple(
        self,
        kernel_version: str,
        repo_dir: Path,
        patch_files: List[Path],
    ) -> int:
        """
        Simple patch integration without spec2git.
        
        Args:
            kernel_version: Kernel version
            repo_dir: Photon repository directory
            patch_files: List of patch file paths
        
        Returns:
            Number of patches integrated
        """
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            raise ValueError(f"Unsupported kernel version: {kernel_version}")
        
        spec_dir = repo_dir / mapping.spec_dir
        spec_files = mapping.spec_files
        
        logger.info(f"Simple integration for {len(patch_files)} patches")
        
        integrated = 0
        
        for spec_name in spec_files:
            spec_path = spec_dir / spec_name
            if not spec_path.exists():
                continue
            
            spec = SpecFile(spec_path)
            
            for patch_path in patch_files:
                patch_name = patch_path.name
                
                # Skip if already in spec
                if spec.has_patch(patch_name):
                    logger.debug(f"Skipping {patch_name} - already in {spec_name}")
                    continue
                
                # Copy patch to spec directory
                dest_path = spec_dir / patch_name
                shutil.copy2(patch_path, dest_path)
                
                # Add to spec
                patch_num = spec.get_next_patch_number()
                if patch_num < 0:
                    logger.warning(f"Patch range full for {spec_name}")
                    continue
                
                if spec.add_patch(patch_name, patch_num):
                    integrated += 1
                    logger.debug(f"Added {patch_name} to {spec_name} as Patch{patch_num}")
            
            spec.save()
        
        logger.info(f"Integrated {integrated} patches")
        return integrated
    
    def integrate_with_spec2git(
        self,
        kernel_version: str,
        repo_dir: Path,
        patch_dir: Path,
        spec_file: str,
        canister: int = 0,
        acvp: int = 0,
    ) -> int:
        """
        Integrate patches using spec2git tool.
        
        Args:
            kernel_version: Kernel version
            repo_dir: Photon repository directory
            patch_dir: Directory containing stable patches
            spec_file: Spec file name
            canister: canister_build value (0 or 1)
            acvp: acvp_build value (0 or 1)
        
        Returns:
            Number of patches applied
        """
        spec2git = self.check_spec2git_available(repo_dir)
        if not spec2git:
            logger.warning("spec2git not available, using simple integration")
            patch_files = sorted(patch_dir.glob(f"patch-{kernel_version}.*"))
            patch_files = [p for p in patch_files if not p.suffix == ".xz"]
            return self.integrate_simple(kernel_version, repo_dir, patch_files)
        
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            raise ValueError(f"Unsupported kernel version: {kernel_version}")
        
        spec_dir = repo_dir / mapping.spec_dir
        spec_path = spec_dir / spec_file
        
        if not spec_path.exists():
            raise FileNotFoundError(f"Spec file not found: {spec_path}")
        
        spec_base = spec_file.replace(".spec", "")
        git_dir = repo_dir / f"linux-git-{spec_base}-c{canister}-a{acvp}-{kernel_version}"
        
        logger.info(f"Integrating patches with spec2git: {spec_file} (canister={canister}, acvp={acvp})")
        
        # Clean up any existing git directory
        safe_remove_dir(git_dir)
        
        # Convert spec to git
        logger.debug("Converting spec to git...")
        returncode, stdout, stderr = run_command(
            [
                "python3", str(spec2git), spec_file,
                "--output-dir", str(git_dir),
                "--define", f"canister_build={canister}",
                "--define", f"acvp_build={acvp}",
                "--force",
            ],
            cwd=spec_dir,
            timeout=600,
        )
        
        if returncode != 0:
            logger.error(f"spec2git conversion failed: {stderr}")
            return 0
        
        # Disable git auto gc
        try:
            repo = Repo(git_dir)
            repo.config_writer().set_value("gc", "auto", "0").release()
        except Exception as e:
            logger.warning(f"Failed to disable git gc: {e}")
        
        # Apply patches
        patch_files = sorted(patch_dir.glob(f"patch-{kernel_version}.*"))
        patch_files = [p for p in patch_files if not p.suffix == ".xz"]
        
        applied = 0
        for patch_path in patch_files:
            try:
                # Check if patch applies
                check_result = run_command(
                    ["git", "apply", "--check", str(patch_path)],
                    cwd=git_dir,
                )
                
                if check_result[0] != 0:
                    logger.warning(f"Patch doesn't apply cleanly: {patch_path.name}")
                    continue
                
                # Apply patch
                apply_result = run_command(
                    ["git", "apply", str(patch_path)],
                    cwd=git_dir,
                )
                
                if apply_result[0] == 0:
                    # Commit
                    run_command(["git", "add", "-A"], cwd=git_dir)
                    run_command(
                        ["git", "commit", "-m", f"Applied stable patch: {patch_path.name}"],
                        cwd=git_dir,
                    )
                    applied += 1
                    logger.debug(f"Applied: {patch_path.name}")
            except Exception as e:
                logger.warning(f"Failed to apply {patch_path.name}: {e}")
        
        # Convert back to spec
        logger.debug("Converting git back to spec...")
        returncode, stdout, stderr = run_command(
            [
                "python3", str(spec2git), spec_file,
                "--git2spec",
                "--git-repo", str(git_dir),
                "--changelog", f"Integrated stable patches for kernel {kernel_version}",
            ],
            cwd=spec_dir,
            timeout=600,
        )
        
        if returncode != 0:
            logger.error(f"git2spec conversion failed: {stderr}")
        
        # Cleanup
        safe_remove_dir(git_dir)
        
        logger.info(f"Applied {applied} patches to {spec_file}")
        return applied
    
    def integrate_stable_update(
        self,
        kernel_version: str,
        repo_dir: Path,
        new_version: str,
    ) -> bool:
        """
        Integrate a stable kernel version update.
        
        Updates Version, resets Release to 1, and adds changelog.
        
        Args:
            kernel_version: Kernel series
            repo_dir: Repository directory
            new_version: New kernel version
        
        Returns:
            True if successful
        """
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            return False
        
        spec_dir = repo_dir / mapping.spec_dir
        
        logger.info(f"Integrating stable update to {new_version}")
        
        success = True
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            if not spec_path.exists():
                continue
            
            spec = SpecFile(spec_path)
            old_version = spec.version
            
            # Update version
            if not spec.set_version(new_version):
                success = False
                continue
            
            # Reset release
            if not spec.reset_release():
                success = False
                continue
            
            # Add changelog
            if not spec.add_changelog_entry(
                new_version, 1,
                f"Update to stable kernel {new_version}",
            ):
                success = False
                continue
            
            spec.save()
            logger.info(f"Updated {spec_name}: {old_version} -> {new_version}")
        
        return success


def find_and_download_stable_patches(
    kernel_version: str,
    output_dir: Path,
    config: Optional[KernelConfig] = None,
) -> List[StablePatchInfo]:
    """
    Find and download stable patches that need to be applied.
    
    Args:
        kernel_version: Kernel series
        output_dir: Output directory
        config: Optional configuration
    
    Returns:
        List of downloaded patch info
    """
    manager = StablePatchManager(config)
    
    logger.info(f"Checking stable patches for kernel {kernel_version}")
    
    latest = manager.get_latest_stable_version(kernel_version)
    last_integrated = manager.get_last_integrated_version(kernel_version)
    
    if not latest:
        logger.warning("Could not determine latest stable version")
        return []
    
    logger.info(f"Latest stable: {latest}")
    logger.info(f"Last integrated: {last_integrated or 'none'}")
    
    # Determine starting subversion
    latest_kv = KernelVersion.parse(latest)
    start_subver = 1
    
    if last_integrated:
        last_kv = KernelVersion.parse(last_integrated)
        start_subver = last_kv.patch + 1
        
        if start_subver > latest_kv.patch:
            logger.info("Already up to date")
            return []
    
    logger.info(f"Will download patches from {kernel_version}.{start_subver} to {latest}")
    
    patches = manager.download_patches_sync(
        kernel_version,
        output_dir,
        start_subver,
        latest_kv.patch,
    )
    
    if patches:
        manager.update_marker(kernel_version, latest)
    
    return patches
