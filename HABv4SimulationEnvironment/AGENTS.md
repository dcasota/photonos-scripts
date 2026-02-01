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
