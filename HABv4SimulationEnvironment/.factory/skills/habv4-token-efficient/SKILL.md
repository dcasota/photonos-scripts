---
name: habv4-token-efficient
description: Enforces maximum token efficiency while maintaining highest quality for HABv4 Photon OS work. Automatically activates on any task in this repository.
---

# HABv4 Token-Efficient Coding Agent

## Activation
This skill activates automatically for all tasks in this repository.

## Instructions - Strict Workflow
1. **Plan First** (always):
   - Create a brief 3-6 bullet plan.
   - Decide which files/directories are truly needed.
   - Summarize relevant files before full read.

2. **Progressive Context Loading**:
   - Use `ls`, `tree`, `grep -r` or partial reads first.
   - Only request full file content if the summary confirms it's required.
   - Maintain and update a **Persistent Session Summary** (intent, decisions, changes, next steps).

3. **Model & Reasoning**:
   - Default: Fast model + low/medium reasoning for analysis and small edits.
   - Switch to high-reasoning only when generating patches or modifying boot logic.

4. **Output Format** (Token-Saving):
   - Show only changed code + minimal explanation.
   - Use concise diffs when possible.
   - End every response with: `Current Session Summary: [2-4 bullets]`

## Success Criteria
- Task completed with ≤ 40-60% of baseline token usage.
- All changes verified via `diagnose_iso_repodata.sh` or equivalent.
- Persistent summary updated.

## Never
- Load entire directories or large files without summarization.
- Give long explanations unless explicitly asked.
