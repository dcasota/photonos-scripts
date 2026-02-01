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

### Installer Failures (Error 1525)
When encountering "rpm transaction failed" errors:
1. Check for file conflicts between MOK packages: `comm -12 <(rpm -qlp linux-mok*.rpm | sort) <(rpm -qlp linux-esx-mok*.rpm | sort)`
2. Inspect package contents: `rpm -qlp <package.rpm> | grep /boot/`
3. Look for BUILD directory contamination: Multiple builds accumulating files
4. Check module directory naming: ESX modules should have `-esx` suffix
5. Verify flavor matching: Each kernel variant needs matching modules

### rpmbuild Issues
- rpmbuild reuses BUILD/ directory - clean it between related builds
- Wildcards in %install can capture unintended files from previous builds
- Use specific file patterns instead of wildcards for kernel files
- Custom kernel injection needs flavor awareness for module selection

### ISO Verification
- Mount ISO and check repodata: `mount -o loop iso /mnt && ls /mnt/RPMS/x86_64/`
- Compare with original: Check if both kernel variants are present
- Verify no file overlap between variants: Use rpm -qlp and comm
