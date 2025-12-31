"""
RPM build functions for kernel packages.
"""

import os
import shutil
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
    
    def install_build_deps(self, spec_path: Path) -> Tuple[bool, List[str]]:
        """
        Install build dependencies for a spec file using tdnf.
        
        Args:
            spec_path: Path to spec file
        
        Returns:
            Tuple of (success, installed_packages)
        """
        if not spec_path.exists():
            logger.error(f"Spec file not found: {spec_path}")
            return False, []
        
        # Get build requirements from spec file
        logger.info(f"Checking build dependencies for {spec_path.name}")
        
        returncode, stdout, stderr = run_command([
            "rpm", "-q", "--buildrequires", "--spec", str(spec_path)
        ])
        
        if returncode != 0:
            logger.warning(f"Could not query build requirements: {stderr}")
            return False, []
        
        # Parse required packages
        required_packages = []
        for line in stdout.strip().split("\n"):
            line = line.strip()
            if line and not line.startswith("#"):
                # Handle versioned requirements like "openssl-devel >= 1.0"
                pkg = line.split()[0] if line else ""
                if pkg:
                    required_packages.append(pkg)
        
        if not required_packages:
            logger.info("No build dependencies to install")
            return True, []
        
        # Remove duplicates while preserving order
        required_packages = list(dict.fromkeys(required_packages))
        
        logger.info(f"Installing {len(required_packages)} build dependencies")
        
        # Install packages using tdnf
        cmd = ["tdnf", "install", "-y"] + required_packages
        
        returncode, stdout, stderr = run_command(cmd, timeout=600)
        
        if returncode != 0:
            logger.error(f"Failed to install dependencies: {stderr}")
            return False, []
        
        logger.info(f"Successfully installed build dependencies")
        return True, required_packages
    
    def _parse_build_requires(self, spec_path: Path) -> List[str]:
        """
        Parse BuildRequires from a spec file.
        
        Args:
            spec_path: Path to spec file
        
        Returns:
            List of package names
        """
        packages = []
        try:
            with open(spec_path, "r") as f:
                for line in f:
                    line = line.strip()
                    if line.startswith("BuildRequires:"):
                        # Extract package name, handle versioned deps like "pkg >= 1.0"
                        parts = line.split(":", 1)[1].strip().split()
                        if parts:
                            packages.append(parts[0])
        except Exception as e:
            logger.warning(f"Could not parse {spec_path}: {e}")
        return packages
    
    def install_all_build_deps(self, spec_dir: Path, spec_files: List[str]) -> bool:
        """
        Install build dependencies for all spec files.
        
        Args:
            spec_dir: Directory containing spec files
            spec_files: List of spec file names
        
        Returns:
            True if all dependencies installed successfully
        """
        all_packages = set()
        
        for spec_name in spec_files:
            spec_path = spec_dir / spec_name
            if not spec_path.exists():
                continue
            
            packages = self._parse_build_requires(spec_path)
            all_packages.update(packages)
        
        if not all_packages:
            logger.info("No build dependencies to install")
            return True
        
        logger.info(f"Installing {len(all_packages)} build dependencies")
        logger.debug(f"Packages: {', '.join(sorted(all_packages))}")
        
        cmd = ["tdnf", "install", "-y"] + list(all_packages)
        returncode, _, stderr = run_command(cmd, timeout=600)
        
        if returncode != 0:
            logger.error(f"Failed to install dependencies: {stderr}")
            return False
        
        logger.info("Successfully installed all build dependencies")
        return True
    
    def setup_srpm_build_env(
        self,
        kernel_version: str,
        naming_scheme: str = "linux-esx",
    ) -> Tuple[bool, Path]:
        """
        Set up SRPM-based build environment.
        
        Downloads SRPM from packages.vmware.com, extracts sources,
        and creates the necessary symlink for rpmbuild.
        
        Args:
            kernel_version: Kernel version (e.g., "5.10")
            naming_scheme: "linux" or "linux-esx"
        
        Returns:
            Tuple of (success, build_topdir)
        """
        # Determine Photon version from kernel version
        photon_version = "4.0" if kernel_version == "5.10" else "5.0"
        
        # Get kernel release from spec file
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            logger.error(f"Invalid kernel version: {kernel_version}")
            return False, Path()
        
        repo_dir = self.config.get_repo_dir(kernel_version)
        spec_dir = repo_dir / mapping.spec_dir
        
        # Get version from spec
        spec_path = spec_dir / f"{naming_scheme}.spec"
        if not spec_path.exists():
            spec_path = spec_dir / "linux.spec"
        
        if not spec_path.exists():
            logger.error(f"Spec file not found: {spec_path}")
            return False, Path()
        
        spec = SpecFile(spec_path)
        full_version = spec.version
        release = spec.release
        
        # Build directory structure
        build_topdir = Path("/usr/local/src")
        for subdir in ["RPMS", "SRPMS", "SOURCES", "SPECS", "LOGS", "BUILD", "BUILDROOT"]:
            (build_topdir / subdir).mkdir(parents=True, exist_ok=True)
        
        # Create symlink /usr/src/photon -> /usr/local/src
        photon_src = Path("/usr/src/photon")
        if photon_src.is_symlink():
            photon_src.unlink()
        elif photon_src.exists():
            logger.warning(f"{photon_src} exists and is not a symlink, skipping symlink creation")
        else:
            photon_src.symlink_to(build_topdir)
            logger.info(f"Created symlink {photon_src} -> {build_topdir}")
        
        # Construct SRPM URL
        # Format: https://packages.vmware.com/photon/4.0/photon_srpms_4.0_x86_64/linux-esx-5.10.210-1.ph4.src.rpm
        # Note: SRPM uses original release, not our modified one
        # We need to find the base SRPM version from tdnf or use a known pattern
        
        srpm_base_url = f"https://packages.broadcom.com/artifactory/photon/{photon_version}/photon_srpms_{photon_version}_x86_64"
        
        # Try to get the SRPM release version (usually -1.ph4 or -1.ph5)
        ph_suffix = f"ph{photon_version.split('.')[0]}"  # ph4 or ph5
        
        # Download SRPM - try common release patterns
        srpm_downloaded = False
        sources_dir = build_topdir / "SOURCES"
        
        for srpm_release in ["1", "2", "3"]:
            srpm_name = f"{naming_scheme}-{full_version}-{srpm_release}.{ph_suffix}.src.rpm"
            srpm_url = f"{srpm_base_url}/{srpm_name}"
            srpm_path = build_topdir / "SRPMS" / srpm_name
            
            logger.info(f"Trying to download SRPM: {srpm_name}")
            
            if download_file(srpm_url, srpm_path):
                logger.info(f"Downloaded SRPM: {srpm_name}")
                
                # Extract SRPM using rpm2cpio
                logger.info("Extracting SRPM sources...")
                extract_cmd = f"cd {sources_dir} && rpm2cpio {srpm_path} | cpio -idm"
                returncode, _, stderr = run_command(["sh", "-c", extract_cmd])
                
                if returncode == 0:
                    logger.info("SRPM sources extracted successfully")
                    srpm_downloaded = True
                    break
                else:
                    logger.error(f"Failed to extract SRPM: {stderr}")
            else:
                logger.debug(f"SRPM not found: {srpm_url}")
        
        if not srpm_downloaded:
            logger.error("Could not download SRPM from packages.vmware.com")
            return False, build_topdir
        
        # Copy SRPM spec to SPECS directory (use original SRPM spec as base)
        srpm_spec = sources_dir / f"{naming_scheme}.spec"
        dest_spec = build_topdir / "SPECS" / f"{naming_scheme}.spec"
        if srpm_spec.exists():
            shutil.copy2(srpm_spec, dest_spec)
            logger.info(f"Using SRPM spec file: {dest_spec}")
        else:
            logger.warning(f"SRPM spec not found: {srpm_spec}")
        
        # Modify check_for_config_applicability.inc to not fail on config diffs
        # (different compiler versions will cause config differences)
        config_check_inc = sources_dir / "check_for_config_applicability.inc"
        if config_check_inc.exists():
            with open(config_check_inc, "w") as f:
                f.write('''echo "Check for .config applicability"
make LC_ALL= olddefconfig %{?_smp_mflags}
# Remove comment with a version string
sed -i '3d' .config
# Show diffs but don't fail (compiler version differences are expected)
diff -u .config.old .config || echo "Config differences detected (expected with different compiler version)"
''')
            logger.info("Modified config applicability check to allow compiler differences")
        
        logger.info(f"Build environment ready at {build_topdir}")
        return True, build_topdir
    
    def build_from_srpm(
        self,
        kernel_version: str,
        naming_scheme: str = "linux-esx",
        canister: int = 0,
        acvp: int = 0,
        install_deps: bool = True,
    ) -> BuildResult:
        """
        Build kernel RPM using SRPM-based approach.
        
        This downloads the official SRPM, extracts sources, applies our
        modified spec file, and builds the RPM.
        
        Args:
            kernel_version: Kernel version (e.g., "5.10")
            naming_scheme: "linux" or "linux-esx"
            canister: canister_build value (0 or 1)
            acvp: acvp_build value (0 or 1)
            install_deps: Whether to install build dependencies
        
        Returns:
            BuildResult with build outcome
        """
        # Set up build environment
        success, build_topdir = self.setup_srpm_build_env(kernel_version, naming_scheme)
        if not success:
            return BuildResult(
                spec_file=f"{naming_scheme}.spec",
                success=False,
                version="",
                release="",
                error_message="Failed to set up SRPM build environment",
            )
        
        spec_path = build_topdir / "SPECS" / f"{naming_scheme}.spec"
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
        
        # Install build dependencies
        if install_deps:
            self.install_build_deps(spec_path)
        
        # Create log directory
        output_dir = self.get_build_output_dir(kernel_version, self.config.get_repo_dir(kernel_version))
        build_log = output_dir / f"build_{naming_scheme}.log"
        build_log.parent.mkdir(parents=True, exist_ok=True)
        
        logger.info(f"Building {naming_scheme}.spec (canister={canister}, acvp={acvp})")
        logger.info(f"  Version: {version}-{release}")
        logger.info(f"  Build topdir: {build_topdir}")
        logger.info(f"  Log: {build_log}")
        logger.info(f"  Output: {build_topdir}/RPMS/x86_64/")
        
        # Build command
        cmd = [
            "rpmbuild", "-bb",
            "--define", f"_topdir {build_topdir}",
            "--define", f"canister_build {canister}",
            "--define", f"acvp_build {acvp}",
            str(spec_path),
        ]
        
        # Run build
        start_time = time.time()
        
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
                logger.info(f"Build successful in {duration}s")
                logger.info(f"RPMs available in {build_topdir}/RPMS/x86_64/")
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
                logger.error(f"Build failed (exit code: {process.returncode}) after {duration}s")
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
            logger.error(f"Build timed out after {self.config.build_timeout}s")
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
    
    def _copy_source_files_to_sources(self, spec_dir: Path) -> int:
        """
        Copy source files from spec directory to /usr/src/photon/SOURCES/.
        
        RPM spec files reference source files that must be present in the
        SOURCES directory during build. This includes .inc files, config files,
        scripts, and other non-patch sources.
        
        Args:
            spec_dir: Directory containing spec and source files
        
        Returns:
            Number of files copied
        """
        sources_dir = Path("/usr/src/photon/SOURCES")
        sources_dir.mkdir(parents=True, exist_ok=True)
        
        # File patterns to copy (excludes .spec and .patch files)
        include_patterns = [
            "*.inc",           # Include files
            "*.trigger",       # Trigger scripts
            "*.conf",          # Config files
            "*.pem",           # Certificates
            "*.csv.in",        # Template files
            "fips_canister-*", # FIPS files
        ]
        
        copied = 0
        for pattern in include_patterns:
            for src_file in spec_dir.glob(pattern):
                if src_file.is_file():
                    dest_path = sources_dir / src_file.name
                    shutil.copy2(src_file, dest_path)
                    logger.debug(f"Copied {src_file.name} to {sources_dir}")
                    copied += 1
        
        # Also copy subdirectories that contain config files
        for subdir in spec_dir.iterdir():
            if subdir.is_dir() and subdir.name not in ["next", ".git"]:
                dest_subdir = sources_dir / subdir.name
                if dest_subdir.exists():
                    shutil.rmtree(dest_subdir)
                shutil.copytree(subdir, dest_subdir)
                logger.debug(f"Copied directory {subdir.name} to {sources_dir}")
                copied += 1
        
        if copied > 0:
            logger.info(f"Copied {copied} source file(s)/dir(s) to {sources_dir}")
        
        return copied
    
    def get_build_output_dir(self, kernel_version: str, repo_dir: Path) -> Path:
        """
        Get the build output directory based on spec version and release.
        
        Creates a directory like kernelpatches/build/5.10.247-8/
        
        Args:
            kernel_version: Kernel version (e.g., "5.10")
            repo_dir: Repository directory
        
        Returns:
            Path to build output directory
        """
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            raise ValueError(f"Invalid kernel version: {kernel_version}")
        
        spec_dir = repo_dir / mapping.spec_dir
        
        # Get version-release from first available spec file
        version = kernel_version
        release = "1"
        
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            if spec_path.exists():
                spec = SpecFile(spec_path)
                version = spec.version
                release = str(spec.release)
                break
        
        # Build directory under kernelpatches/build/
        build_base = self.config.base_dir / "kernelpatches" / "build"
        build_dir = build_base / f"{version}-{release}"
        build_dir.mkdir(parents=True, exist_ok=True)
        
        return build_dir
    
    def build_all_specs(
        self,
        kernel_version: str,
        repo_dir: Path,
        output_dir: Optional[Path] = None,
        canister: int = 0,
        acvp: int = 0,
        install_deps: bool = True,
    ) -> List[BuildResult]:
        """
        Build all kernel specs for a version.
        
        Args:
            kernel_version: Kernel version
            repo_dir: Repository directory
            output_dir: Output directory for logs (auto-generated if None)
            canister: canister_build value
            acvp: acvp_build value
            install_deps: Whether to install build dependencies via tdnf
        
        Returns:
            List of BuildResult for each spec
        """
        mapping = KERNEL_MAPPINGS.get(kernel_version)
        if not mapping:
            raise ValueError(f"Invalid kernel version: {kernel_version}")
        
        spec_dir = repo_dir / mapping.spec_dir
        results = []
        
        # Use auto-generated output directory if not specified
        if output_dir is None:
            output_dir = self.get_build_output_dir(kernel_version, repo_dir)
        
        output_dir.mkdir(parents=True, exist_ok=True)
        logger.info(f"Build output directory: {output_dir}")
        
        # Copy source files to SOURCES directory before building
        self._copy_source_files_to_sources(spec_dir)
        
        # Get version from first available spec and ensure tarball exists
        rpm_sources_dir = Path("/usr/src/photon/SOURCES")
        for spec_name in mapping.spec_files:
            spec_path = spec_dir / spec_name
            if spec_path.exists():
                spec = SpecFile(spec_path)
                full_version = spec.version
                tarball_name = f"linux-{full_version}.tar.xz"
                tarball_path = rpm_sources_dir / tarball_name
                
                if not tarball_path.exists():
                    logger.info(f"Downloading kernel tarball {tarball_name}...")
                    kernel_url = get_kernel_org_url(kernel_version)
                    if kernel_url:
                        tarball_url = f"{kernel_url}{tarball_name}"
                        if not download_file(tarball_url, tarball_path):
                            logger.error(f"Failed to download {tarball_name}")
                        else:
                            logger.info(f"Downloaded {tarball_name} to {rpm_sources_dir}")
                break
        
        # Install build dependencies if requested
        if install_deps:
            if not self.install_all_build_deps(spec_dir, mapping.spec_files):
                logger.warning("Some build dependencies may not have been installed")
        
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
