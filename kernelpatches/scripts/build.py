"""
RPM build functions for kernel packages.
"""

import os
import subprocess
import time
from datetime import datetime
from pathlib import Path
from typing import List, Optional, Tuple

import requests

from scripts.common import (
    calculate_sha512,
    download_file,
    logger,
    run_command,
)
from scripts.config import (
    DEFAULT_CONFIG,
    KERNEL_MAPPINGS,
    KernelConfig,
    get_kernel_org_url,
)
from scripts.models import BuildResult, KernelVersion
from scripts.spec_file import SpecFile


class BuildError(Exception):
    """Exception raised for build failures."""
    pass


class KernelBuilder:
    """Build kernel RPMs from spec files."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
    
    def verify_build_deps(self) -> Tuple[bool, List[str]]:
        """
        Verify build dependencies are available.
        
        Returns:
            Tuple of (all_present, missing_deps)
        """
        deps = {
            "rpmbuild": "rpm-build package",
            "rpm": "rpm package",
            "make": "make package",
            "gcc": "gcc package",
        }
        
        missing = []
        for cmd, package in deps.items():
            returncode, _, _ = run_command(["which", cmd])
            if returncode != 0:
                missing.append(f"{cmd} ({package})")
        
        if missing:
            logger.error(f"Missing build dependencies: {', '.join(missing)}")
            return False, missing
        
        logger.debug("Build dependencies verified")
        return True, []
    
    def build_rpm(
        self,
        spec_path: Path,
        build_log: Path,
        canister: int = 0,
        acvp: int = 0,
        topdir: Optional[Path] = None,
    ) -> BuildResult:
        """
        Build kernel RPM from spec file.
        
        Args:
            spec_path: Path to spec file
            build_log: Path for build log
            canister: canister_build value (0 or 1)
            acvp: acvp_build value (0 or 1)
            topdir: RPM build top directory
        
        Returns:
            BuildResult with build outcome
        """
        if not spec_path.exists():
            return BuildResult(
                spec_file=str(spec_path),
                success=False,
                version="",
                release="",
                error_message=f"Spec file not found: {spec_path}",
            )
        
        spec = SpecFile(spec_path)
        version = spec.version
        release = str(spec.release)
        
        logger.info(f"Building {spec_path.name} (canister={canister}, acvp={acvp})")
        logger.info(f"  Version: {version}-{release}")
        logger.info(f"  Log: {build_log}")
        
        # Build command
        cmd = [
            "rpmbuild", "-bb",
            "--define", f"canister_build {canister}",
            "--define", f"acvp_build {acvp}",
        ]
        
        if topdir:
            cmd.extend(["--define", f"_topdir {topdir}"])
        
        cmd.append(str(spec_path))
        
        # Run build
        start_time = time.time()
        
        build_log.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            with open(build_log, "w") as log_file:
                process = subprocess.run(
                    cmd,
                    stdout=log_file,
                    stderr=subprocess.STDOUT,
                    timeout=self.config.build_timeout,
                )
            
            duration = int(time.time() - start_time)
            
            if process.returncode == 0:
                logger.info(f"  Build successful in {duration}s")
                return BuildResult(
                    spec_file=str(spec_path),
                    success=True,
                    version=version,
                    release=release,
                    duration_seconds=duration,
                    log_file=str(build_log),
                    canister_build=canister,
                    acvp_build=acvp,
                )
            else:
                # Read last 20 lines of log for error
                log_tail = ""
                try:
                    with open(build_log) as f:
                        lines = f.readlines()
                        log_tail = "".join(lines[-20:])
                except Exception:
                    pass
                
                logger.error(f"  Build failed (exit code: {process.returncode}) after {duration}s")
                
                return BuildResult(
                    spec_file=str(spec_path),
                    success=False,
                    version=version,
                    release=release,
                    duration_seconds=duration,
                    log_file=str(build_log),
                    error_message=f"Build failed with exit code {process.returncode}",
                    canister_build=canister,
                    acvp_build=acvp,
                )
                
        except subprocess.TimeoutExpired:
            duration = int(time.time() - start_time)
            logger.error(f"  Build timed out after {self.config.build_timeout}s")
            
            return BuildResult(
                spec_file=str(spec_path),
                success=False,
                version=version,
                release=release,
                duration_seconds=duration,
                log_file=str(build_log),
                error_message=f"Build timed out after {self.config.build_timeout}s",
                canister_build=canister,
                acvp_build=acvp,
            )
        except Exception as e:
            return BuildResult(
                spec_file=str(spec_path),
                success=False,
                version=version,
                release=release,
                error_message=str(e),
                canister_build=canister,
                acvp_build=acvp,
            )
    
    def build_all_specs(
        self,
        kernel_version: str,
        repo_dir: Path,
        output_dir: Path,
        canister: int = 0,
        acvp: int = 0,
    ) -> List[BuildResult]:
        """
        Build all kernel specs for a version.
        
        Args:
            kernel_version: Kernel version
            repo_dir: Repository directory
            output_dir: Output directory for logs
            canister: canister_build value
            acvp: acvp_build value
        
        Returns:
            List of BuildResult for each spec
        """
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            raise ValueError(f"Invalid kernel version: {kernel_version}")
        
        spec_dir = repo_dir / mapping.spec_dir
        results = []
        
        logger.info(f"Building kernel specs for {kernel_version}")
        
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            if not spec_path.exists():
                logger.warning(f"Spec file not found: {spec_path}")
                continue
            
            build_log = output_dir / f"build_{spec_name.replace('.spec', '')}.log"
            result = self.build_rpm(spec_path, build_log, canister, acvp)
            results.append(result)
        
        success_count = sum(1 for r in results if r.success)
        fail_count = len(results) - success_count
        
        logger.info(f"Build Summary: Success={success_count}, Failed={fail_count}")
        
        return results
    
    def build_all_permutations(
        self,
        kernel_version: str,
        repo_dir: Path,
        output_dir: Path,
    ) -> List[BuildResult]:
        """
        Build with all canister/acvp permutations.
        
        Args:
            kernel_version: Kernel version
            repo_dir: Repository directory
            output_dir: Output directory
        
        Returns:
            List of all BuildResults
        """
        permutations = [
            (0, 0),  # Standard
            (1, 0),  # Canister
            (0, 1),  # ACVP
            (1, 1),  # Both
        ]
        
        all_results = []
        
        for canister, acvp in permutations:
            logger.info(f"=== Permutation: canister={canister}, acvp={acvp} ===")
            
            perm_output = output_dir / f"perm_c{canister}_a{acvp}"
            perm_output.mkdir(parents=True, exist_ok=True)
            
            results = self.build_all_specs(
                kernel_version, repo_dir, perm_output, canister, acvp
            )
            all_results.extend(results)
        
        return all_results


class KernelVersionUpdater:
    """Update kernel version in spec files."""
    
    def __init__(self, config: Optional[KernelConfig] = None):
        self.config = config or DEFAULT_CONFIG
    
    def download_tarball(
        self,
        kernel_version: str,
        full_version: str,
        sources_dir: Path,
    ) -> Optional[Path]:
        """
        Download kernel tarball from kernel.org.
        
        Args:
            kernel_version: Kernel series (e.g., "6.1")
            full_version: Full version (e.g., "6.1.160")
            sources_dir: Directory to save tarball
        
        Returns:
            Path to downloaded tarball, or None on failure
        """
        kernel_url = get_kernel_org_url(kernel_version)
        if not kernel_url:
            return None
        
        tarball_name = f"linux-{full_version}.tar.xz"
        tarball_url = f"{kernel_url}{tarball_name}"
        tarball_path = sources_dir / tarball_name
        
        if tarball_path.exists():
            logger.info(f"Tarball already exists: {tarball_path}")
            return tarball_path
        
        logger.info(f"Downloading {tarball_name}...")
        
        if download_file(tarball_url, tarball_path):
            return tarball_path
        return None
    
    def update_version(
        self,
        kernel_version: str,
        new_full_version: str,
        repo_dir: Path,
        sources_dir: Path,
    ) -> bool:
        """
        Update kernel to new version.
        
        Downloads tarball, calculates SHA512, and updates spec files.
        
        Args:
            kernel_version: Kernel series
            new_full_version: New full version
            repo_dir: Repository directory
            sources_dir: Directory for tarballs
        
        Returns:
            True if successful
        """
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            logger.error(f"Invalid kernel version: {kernel_version}")
            return False
        
        spec_dir = repo_dir / mapping.spec_dir
        
        logger.info(f"Updating kernel to {new_full_version}")
        
        # Download tarball
        tarball_path = self.download_tarball(kernel_version, new_full_version, sources_dir)
        if not tarball_path:
            logger.error("Failed to download tarball")
            return False
        
        # Calculate SHA512
        logger.info("Calculating SHA512...")
        new_sha512 = calculate_sha512(tarball_path)
        logger.info(f"SHA512: {new_sha512[:32]}...{new_sha512[-32:]}")
        
        # Update each spec file
        success = True
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            if not spec_path.exists():
                logger.warning(f"Spec file not found: {spec_path}")
                continue
            
            spec = SpecFile(spec_path)
            old_version = spec.version
            
            logger.info(f"Updating {spec_name}...")
            
            # Update version
            if not spec.set_version(new_full_version):
                success = False
                continue
            
            # Update SHA512
            if not spec.set_sha512("linux", new_sha512):
                success = False
                continue
            
            # Reset release to 1
            if not spec.reset_release():
                success = False
                continue
            
            # Add changelog
            if not spec.add_changelog_entry(
                new_full_version, 1,
                f"Update to version {new_full_version}",
            ):
                success = False
                continue
            
            spec.save()
            logger.info(f"  Updated {spec_name}: {old_version} -> {new_full_version}")
        
        return success
    
    def check_and_update(
        self,
        kernel_version: str,
        repo_dir: Path,
        sources_dir: Path,
    ) -> Tuple[bool, Optional[str]]:
        """
        Check for updates and apply if available.
        
        Args:
            kernel_version: Kernel series
            repo_dir: Repository directory
            sources_dir: Directory for tarballs
        
        Returns:
            Tuple of (updated, new_version)
        """
        from scripts.stable_patches import StablePatchManager
        
        manager = StablePatchManager(self.config)
        
        current = manager.get_current_photon_version(kernel_version, repo_dir)
        if not current:
            logger.error("Could not determine current version")
            return False, None
        
        latest = manager.get_latest_stable_version(kernel_version)
        if not latest:
            logger.warning("Could not determine latest version")
            return False, None
        
        logger.info(f"Current: {current}, Latest: {latest}")
        
        from scripts.common import version_less_than
        
        if not version_less_than(current, latest):
            logger.info("Kernel is up to date")
            return False, current
        
        logger.info(f"New version available: {current} -> {latest}")
        
        if self.update_version(kernel_version, latest, repo_dir, sources_dir):
            return True, latest
        
        return False, None


def build_after_patches(
    kernel_version: str,
    repo_dir: Path,
    output_dir: Path,
    patch_count: int,
    config: Optional[KernelConfig] = None,
) -> List[BuildResult]:
    """
    Build RPMs after patch integration.
    
    Increments release and adds changelog entry before building.
    
    Args:
        kernel_version: Kernel version
        repo_dir: Repository directory
        output_dir: Output directory
        patch_count: Number of patches integrated
        config: Optional configuration
    
    Returns:
        List of BuildResults
    """
    mapping = KERNEL_MAPPINGS.get(kernel_version)
    if not mapping:
        raise ValueError(f"Invalid kernel version: {kernel_version}")
    
    spec_dir = repo_dir / mapping.spec_dir
    builder = KernelBuilder(config)
    
    # Verify dependencies
    deps_ok, missing = builder.verify_build_deps()
    if not deps_ok:
        raise BuildError(f"Missing dependencies: {', '.join(missing)}")
    
    changelog_msg = f"Backported {patch_count} CVE patch(es)"
    
    # Update spec files
    for spec_name in mapping.spec_files:
        spec_path = spec_dir / spec_name
        if not spec_path.exists():
            continue
        
        spec = SpecFile(spec_path)
        version = spec.version
        
        # Increment release
        new_release = spec.increment_release()
        if new_release < 0:
            logger.error(f"Failed to increment release for {spec_name}")
            continue
        
        # Add changelog
        spec.add_changelog_entry(version, new_release, changelog_msg)
        spec.save()
    
    # Build all specs
    return builder.build_all_specs(kernel_version, repo_dir, output_dir)
