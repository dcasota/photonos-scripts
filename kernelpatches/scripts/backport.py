"""
Main backport workflow orchestration.
"""

import shutil
from datetime import datetime
from pathlib import Path
from typing import Dict, List, Optional, Tuple

from git import Repo

from scripts.common import (
    check_network,
    console,
    create_output_dir,
    determine_patch_targets,
    download_file,
    expand_targets_to_specs,
    logger,
    setup_logging,
)
from scripts.config import (
    DEFAULT_CONFIG,
    KERNEL_MAPPINGS,
    KernelConfig,
    get_branch_for_kernel,
)
from scripts.models import CVESource, Patch, PatchSource, PatchTarget
from scripts.spec_file import SpecFile
from scripts.source_verification import SourceVerifier, PatchVerificationResult


def run_backport_workflow(
    kernel_version: str,
    patch_source: PatchSource = PatchSource.CVE,
    cve_source: CVESource = CVESource.NVD,
    scan_month: Optional[str] = None,
    analyze_cves: bool = False,
    cve_since: Optional[str] = None,
    detect_gaps: bool = False,
    resume: bool = False,
    repo_base: Optional[Path] = None,
    repo_url: str = "https://github.com/vmware/photon.git",
    branch: Optional[str] = None,
    skip_clone: bool = False,
    skip_review: bool = False,
    skip_push: bool = False,
    enable_build: bool = True,
    patch_limit: int = 0,
    dry_run: bool = False,
    config: Optional[KernelConfig] = None,
) -> bool:
    """
    Run the complete backport workflow.
    
    Args:
        kernel_version: Kernel version to process
        patch_source: Source type (cve, stable, stable-full, all)
        cve_source: CVE source when using CVE patches
        scan_month: Month to scan for upstream source
        analyze_cves: Analyze CVE redundancy
        cve_since: Filter CVE analysis by date
        detect_gaps: Enable gap detection
        resume: Resume from checkpoint
        repo_base: Base directory for cloning repos (overrides config default)
        repo_url: Photon repository URL
        branch: Git branch (auto-detected if not specified)
        skip_clone: Skip cloning if repo exists
        skip_review: Skip CVE review
        skip_push: Skip git push
        enable_build: Enable RPM building
        patch_limit: Limit number of patches
        dry_run: Show what would be done
        config: Configuration object
    
    Returns:
        True if successful
    """
    config = config or DEFAULT_CONFIG
    
    # Setup
    mapping = KERNEL_MAPPINGS.get(kernel_version)
    if not mapping:
        raise ValueError(f"Unsupported kernel version: {kernel_version}")
    
    if not branch:
        branch = mapping.branch.value
    
    # Determine repo directory
    if repo_base:
        repo_dir = repo_base / branch
    else:
        repo_dir = config.base_dir / "kernelpatches" / branch
    spec_dir = repo_dir / mapping.spec_dir
    output_dir = create_output_dir("backport")
    skills_file = config.base_dir / "kernelpatches" / "patch_routing.skills"
    
    # Setup logging
    log_file = config.log_dir / f"backport_{kernel_version}_{datetime.now().strftime('%Y%m%d_%H%M%S')}.log"
    setup_logging("kernelpatches", log_file=log_file)
    
    logger.info("=== Unified Kernel Backport Script ===")
    logger.info(f"Kernel version: {kernel_version}")
    logger.info(f"Patch source: {patch_source.value}")
    logger.info(f"Output directory: {output_dir}")
    logger.info(f"Dry run: {dry_run}")
    
    if patch_source in (PatchSource.CVE, PatchSource.ALL):
        logger.info(f"CVE source: {cve_source.value}")
    
    # Network check
    if not check_network():
        logger.error("Network is not available. Aborting.")
        return False
    
    # Step 1: Clone/Update Repository
    logger.info("")
    logger.info("=== Step 1: Clone Photon Repository ===")
    
    from scripts.common import ensure_photon_repo
    
    if skip_clone and repo_dir.exists():
        logger.info(f"Skipping clone, using existing {repo_dir}")
    else:
        if not dry_run:
            # Use centralized clone routine
            cloned_dir = ensure_photon_repo(
                kernel_version,
                config=config,
                repo_url=repo_url,
                repo_base=repo_base,
                force_update=repo_dir.exists(),  # Update if exists
            )
            if not cloned_dir:
                logger.error("Failed to clone/update repository")
                return False
            repo_dir = cloned_dir
            spec_dir = repo_dir / mapping.spec_dir
    
    if not spec_dir.exists() and not dry_run:
        logger.error(f"Spec directory not found: {spec_dir}")
        return False
    
    # Step 2: Check Stable Status
    logger.info("")
    logger.info("=== Step 2: Check Stable Kernel Status ===")
    
    from scripts.stable_patches import StablePatchManager, StableIntegrator
    
    manager = StablePatchManager(config)
    status, current_version, latest_version = manager.check_stable_status(kernel_version, repo_dir)
    
    stable_update_success = False
    
    if status == "UPDATE_NEEDED":
        versions_behind = manager.get_versions_behind(current_version, latest_version)
        logger.warning(f"Kernel {kernel_version} is behind stable!")
        logger.info(f"  Current: {current_version}")
        logger.info(f"  Latest: {latest_version}")
        logger.info(f"  Versions behind: {versions_behind}")
        
        if not dry_run:
            integrator = StableIntegrator(config)
            if integrator.integrate_stable_update(kernel_version, repo_dir, latest_version):
                stable_update_success = True
                current_version = latest_version
                logger.info("Stable update integrated successfully")
    elif status == "UP_TO_DATE":
        logger.info(f"Kernel is up to date: {current_version}")
    else:
        logger.warning("Could not determine stable status")
    
    # Step 3: Process Patches
    cve_total = 0
    stable_total = 0
    
    if patch_source in (PatchSource.CVE, PatchSource.ALL):
        logger.info("")
        logger.info("=== Step 3: Find CVE Patches ===")
        
        from scripts.cve_sources import fetch_cves_sync
        
        if not dry_run:
            cves = fetch_cves_sync(cve_source, kernel_version, output_dir, current_version, config)
            cve_total = len([c for c in cves if c.fix_commits])
            
            logger.info(f"Found {cve_total} CVEs with fix commits")
            
            # Gap detection
            if detect_gaps and cves:
                logger.info("")
                logger.info("=== Step 3a: CVE Gap Detection ===")
                
                from scripts.cve_gap_detection import run_gap_detection
                
                cve_ids = [c.cve_id for c in cves]
                run_gap_detection(
                    kernel_version,
                    current_version or "unknown",
                    cve_ids,
                    config.gap_report_dir,
                    config,
                )
        else:
            logger.info("Dry run - skipping CVE fetch")
    
    if patch_source in (PatchSource.STABLE, PatchSource.STABLE_FULL, PatchSource.ALL):
        logger.info("")
        logger.info("=== Step 3: Find Stable Patches ===")
        
        from scripts.stable_patches import find_and_download_stable_patches
        
        if not dry_run:
            patches = find_and_download_stable_patches(kernel_version, output_dir, config)
            stable_total = len(patches)
        else:
            logger.info("Dry run - skipping stable patch download")
    
    # Step 4: Process and Integrate Patches
    logger.info("")
    logger.info("=== Step 4: Process Patches ===")
    
    # Backup spec files
    for spec_name in mapping.spec_files:
        spec_path = spec_dir / spec_name
        if spec_path.exists():
            backup_path = output_dir / f"{spec_name}.backup"
            if not dry_run:
                shutil.copy2(spec_path, backup_path)
    logger.info(f"Backed up spec files to {output_dir}")
    
    total_patches = cve_total + stable_total
    if total_patches == 0:
        logger.info("No patches found. Nothing to process.")
        return True
    
    logger.info(f"Total patches: {total_patches} (CVE: {cve_total}, Stable: {stable_total})")
    
    # Process CVE patches
    success_count = 0
    failed_count = 0
    skipped_count = 0
    included_in_source_count = 0
    
    if patch_source in (PatchSource.CVE, PatchSource.ALL) and cve_total > 0 and not dry_run:
        logger.info(f"Processing {cve_total} CVE patches...")
        
        from scripts.cve_sources import fetch_cves_sync
        
        cves = fetch_cves_sync(cve_source, kernel_version, output_dir, current_version, config)
        
        # Initialize source verifier for checking patches against stable kernel source
        source_verifier: Optional[SourceVerifier] = None
        source_verification_results: Dict[str, PatchVerificationResult] = {}
        
        if current_version:
            logger.info("")
            logger.info("=== Step 4a: Download and Extract Stable Kernel Source ===")
            logger.info(f"Checking patches against kernel source {current_version}")
            logger.info(f"Source URL: {config.photon_sources_url}linux-{current_version}.tar.xz")
            
            source_verifier = SourceVerifier(config=config)
            source_dir = source_verifier.extract_source(current_version)
            
            if source_dir:
                logger.info(f"Source extracted to: {source_dir}")
                logger.info("Will verify each patch against source before adding to spec files")
            else:
                logger.warning("Could not extract source tarball, skipping source verification")
                source_verifier = None
        
        processed = 0
        for cve in cves:
            if not cve.fix_commits:
                continue
            
            if patch_limit > 0 and processed >= patch_limit:
                break
            
            for sha in cve.fix_commits:
                processed += 1
                logger.info(f"[{processed}] SHA: {sha[:12]} ({cve.cve_id})")
                
                # Download patch
                patch_url = f"https://github.com/torvalds/linux/commit/{sha}.patch"
                patch_file = output_dir / f"{sha[:12]}-backport.patch"
                
                if not download_file(patch_url, patch_file, show_progress=False):
                    logger.warning(f"  FAIL: Could not download patch")
                    failed_count += 1
                    continue
                
                patch_content = patch_file.read_text(errors="ignore")
                
                # Check if patch is already included in stable kernel source
                if source_verifier:
                    verification = source_verifier.check_patch_included(
                        patch_content, sha, cve.cve_id
                    )
                    source_verification_results[sha] = verification
                    
                    if verification.is_included:
                        logger.info(f"  SKIP: Already included in kernel source - {verification.match_reason}")
                        included_in_source_count += 1
                        skipped_count += 1
                        patch_file.unlink()
                        continue
                
                # Determine routing
                patch = Patch(sha=sha, cve_ids=[cve.cve_id])
                target = determine_patch_targets(
                    patch, patch_content,
                    skills_file if skills_file.exists() else None,
                )
                
                if target == PatchTarget.NONE:
                    logger.info(f"  SKIP: Routing is 'none'")
                    skipped_count += 1
                    patch_file.unlink()
                    continue
                
                target_specs = expand_targets_to_specs(target, mapping.spec_files)
                logger.info(f"  Routing: {target.value} -> {target_specs}")
                
                # Check if already integrated in spec files
                already_in = []
                for spec_name in target_specs:
                    spec_path = spec_dir / spec_name
                    if spec_path.exists():
                        spec = SpecFile(spec_path)
                        if spec.has_patch(sha[:12]):
                            already_in.append(spec_name)
                
                if already_in:
                    logger.info(f"  SKIP: Already in spec files {already_in}")
                    skipped_count += 1
                    patch_file.unlink()
                    continue
                
                # Add to specs
                patch_name = f"{sha[:12]}-backport.patch"
                dest_path = spec_dir / patch_name
                shutil.copy2(patch_file, dest_path)
                
                for spec_name in target_specs:
                    spec_path = spec_dir / spec_name
                    if spec_path.exists():
                        spec = SpecFile(spec_path)
                        patch_num = spec.get_next_patch_number(
                            config.cve_patch_min, config.cve_patch_max
                        )
                        if patch_num > 0:
                            spec.add_patch(patch_name, patch_num)
                            spec.save()
                            logger.info(f"    Added Patch{patch_num} to {spec_name}")
                
                success_count += 1
                patch_file.unlink()
        
        # Cleanup source verifier
        if source_verifier:
            source_verifier.cleanup()
        
        logger.info("")
        logger.info(f"CVE Processing Complete:")
        logger.info(f"  Success (added to spec): {success_count}")
        logger.info(f"  Already in source tarball: {included_in_source_count}")
        logger.info(f"  Skipped (other reasons): {skipped_count - included_in_source_count}")
        logger.info(f"  Failed: {failed_count}")
    
    # Process stable patches
    if patch_source in (PatchSource.STABLE_FULL, PatchSource.ALL) and stable_total > 0:
        logger.info(f"Processing {stable_total} stable patches...")
        
        from scripts.stable_patches import StableIntegrator
        
        integrator = StableIntegrator(config)
        patch_dir = output_dir / "stable_patches"
        
        if not dry_run and patch_dir.exists():
            patch_files = sorted(patch_dir.glob(f"patch-{kernel_version}.*"))
            patch_files = [p for p in patch_files if not p.suffix == ".xz"]
            
            if patch_files:
                integrated = integrator.integrate_simple(kernel_version, repo_dir, patch_files)
                logger.info(f"Integrated {integrated} stable patches")
    
    # Step 5: Build
    build_needed = stable_update_success or success_count > 0
    
    if enable_build and build_needed:
        logger.info("")
        logger.info("=== Step 5: Build RPMs ===")
        
        from scripts.build import build_after_patches
        
        if dry_run:
            logger.info("Dry run - skipping build")
        else:
            try:
                results = build_after_patches(
                    kernel_version, repo_dir, output_dir,
                    success_count, config,
                )
                
                build_success = all(r.success for r in results)
                if not build_success:
                    logger.error("One or more builds failed")
                    return False
                    
            except Exception as e:
                logger.error(f"Build failed: {e}")
                return False
    
    # Summary
    logger.info("")
    logger.info("=== ALL DONE ===")
    logger.info(f"Output directory: {output_dir}")
    logger.info(f"Log file: {log_file}")
    
    return True
