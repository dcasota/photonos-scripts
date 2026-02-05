# AGENTS.md - HABv4 Simulation Environment

## Core Efficiency Rules (Always Follow)
- **Minimize tokens per task**: Use progressive disclosure. Never load full files unless necessary.
- **Summarize first**: Always summarize a file or directory before requesting full content.
- **Model Strategy**: 
  - Routine tasks, analysis, grepping → use fast model (Haiku / GLM-4 / Droid Core)
  - Code generation, patching → Sonnet or equivalent
  - Architecture / complex reasoning → Spec Mode + high-reasoning model
- **Context Management**: Maintain a persistent session summary. Update it after every major step.
- **Verification**: Always run the fastest possible test before declaring success (`diagnose_iso_repodata.sh`, `ls patches/`, build checks).

## Project Context
- This is a VMware Photon OS secure boot + HABv4 simulation environment.
- Key areas: `src/`, `patches/`, `data/`, ISO build scripts, MOK signing, UEFI flows.
- Critical files: `diagnose_iso_repodata.sh`, kernel patches, secure boot chain.

## Memory & Summary
- Project memory and decisions are in `.factory/memories.md`
- Always reference and update the session summary before acting.

**Rule**: If a task touches >2 files or any patch/ISO logic, start in Spec Mode.

## Common Debugging Patterns

### Installer Failures (Error 1525) - Root Cause and Solution
**Root cause (identified v1.9.37)**: Photon OS `installer.py` **hardcodes** `packages.append('grub2-efi-image')` for EFI bootmode (line 361). This is still present in upstream v2.8 (Jan 2026).

**Solution**: Two-repository architecture:
- `RPMS/` → untouched VMware Original packages
- `RPMS_MOK/` → hardlinked copy with conflicting packages replaced by MOK variants
- Installer patches (`packageselector.py`, `installer.py`) redirect MOK options to `RPMS_MOK/`

**Previous approaches that failed** (v1.9.16-v1.9.36):
- Conflicts/Obsoletes directives, Epoch, dynamic meta-package expansion, original package removal
- None addressed the hardcoded `packages.append()` root cause

When debugging new Error 1525 issues:
1. Verify two-repository structure: `ls /mnt/RPMS_MOK/x86_64/grub2-efi-image-mok*.rpm`
2. Verify originals absent from RPMS_MOK: `ls /mnt/RPMS_MOK/x86_64/grub2-efi-image-2*.rpm` (should not exist)
3. Check installer patches applied: grep for `mok_repo_path` in extracted initrd's `installer.py`
4. Inspect package contents: `rpm -qlp <package.rpm> | grep /boot/`

### rpmbuild Issues
- rpmbuild reuses BUILD/ directory - clean it between related builds
- Wildcards in %install can capture unintended files from previous builds
- Use specific file patterns instead of wildcards for kernel files
- Custom kernel injection needs flavor awareness for module selection

### ISO Verification
- Mount ISO and check repodata: `mount -o loop iso /mnt && ls /mnt/RPMS/x86_64/`
- Compare with original: Check if both kernel variants are present
- Verify no file overlap between variants: Use rpm -qlp and comm
