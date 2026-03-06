---
agent: gating-detector
---

# Phased Gating Assessment (Modernizer-Style)

## Mission

Perform a deep, phased assessment of the gating mechanism health across the entire Photon OS build tree. This is for periodic audits, not quick CI checks.

## Phase 1: Assessment and Discovery

### 1.1 Current State Analysis

- Run full inventory (Phase 0 from `inventory.prompt.md`)
- Count total gated specs per branch
- Identify all unique `build_if` thresholds in use
- Map the timeline: which thresholds were introduced when (via git log)

### 1.2 Gap Analysis

- Compare current subrelease values against available snapshots
- Identify branches where `photon-mainline` is not set but should be
- Find specs with `build_if 0` (permanently disabled) that may be dead code
- Check for orphaned `SPECS/<N>/` directories with no corresponding `SPECS/` counterpart

### 1.3 Risk Assessment

For each branch, classify risk:

| Risk | Condition |
|------|-----------|
| **Critical** | BLOCKING or CRITICAL findings exist |
| **High** | Snapshot predates latest gating commit by >30 days |
| **Medium** | `photon-mainline` not set, relying on snapshot consistency |
| **Low** | `photon-mainline` set, snapshot bypassed, gating self-consistent |

Produce a **risk/value matrix** prioritizing which branches need attention first.

## Phase 2: Strategy Formulation

### 2.1 Remediation Roadmap

Create a phased remediation plan:

1. **Immediate** (today): Fix all BLOCKING/CRITICAL findings
2. **Short-term** (this week): Set `photon-mainline` for all branches with stale snapshots
3. **Medium-term** (this month): Request new snapshots aligned with current gating state
4. **Long-term**: Propose upstream changes to synchronize snapshot publication with gating commits

### 2.2 Architecture Evolution

Assess whether the current `build_if` + snapshot mechanism is sustainable:

- How many gating thresholds can accumulate before maintenance becomes unmanageable?
- Should per-branch gating replace the shared `photon_subrelease` macro?
- Would a "snapshot generation" CI step after each gating commit solve the consistency problem?

## Phase 3: Execution Prep

### 3.1 Task Decomposition

Break the remediation roadmap into tasks with:

- **Clear objective**: what changes
- **Acceptance criteria**: how to verify
- **Dependencies**: what must be done first
- **Rollback procedure**: how to undo

### 3.2 Testing Strategy

- After each remediation, run `gating-detector --verify`
- For high-risk changes (subrelease value changes), run a test build
- Monitor build logs for the first build after remediation

## Output

Produce a comprehensive report in three sections:

1. **Assessment Report** (`assessment.md`) -- current state, gaps, risks
2. **Remediation Roadmap** (`roadmap.md`) -- phased plan with timeline
3. **Task List** (`tasks/`) -- individual task files with acceptance criteria
