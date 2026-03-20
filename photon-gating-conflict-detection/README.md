# Photon OS Gating Conflict Detection

Automated CI pipeline for detecting conflicts between `build_if` subrelease gating and snapshot pinning in [vmware/photon](https://github.com/vmware/photon) builds.

## The Problem

Commit [6b7bc7c](https://github.com/vmware/photon/commit/6b7bc7c77f66165a3413464f5b0495e510691a57) ("libcap: Update to v2.77 and split into subpackages") restructures the libcap package across the `build_if` gating boundary. It upgrades libcap from v2.66 (monolithic) to v2.77 (split into libcap, libcap-libs, libcap-minimal, libcap-devel, libcap-doc), gates the new version at `%{photon_subrelease} >= 92`, and relocates the old v2.66 spec to `SPECS/91/libcap/` with a gate of `<= 91`. In parallel, it bumps `rpm.spec` from 4.18.2-8 to 4.18.2-9, changing `Requires: libcap` to `Requires: libcap-libs` -- but this rpm update is also gated `>= 92`, and the previous rpm 4.18.2-8 is relocated to `SPECS/91/rpm/` with `<= 91`.

The gating logic itself is correct: at subrelease 91, the old monolithic libcap and the old rpm with `Requires: libcap` activate together; at subrelease 92, the split libcap and the updated rpm with `Requires: libcap-libs` activate together. However, **the snapshot pinning mechanism breaks this consistency**. Snapshot 91 was published before this commit existed. When a build uses subrelease 91 with snapshot 91, tdnf's dependency resolver sees packages from both the pre-split and post-split states in the repo metadata -- the snapshot filter disables the new subpackages (`libcap-minimal`, `libcap-libs`) because they were not in the snapshot at capture time, yet they appear in the repo index because the git tree now contains the `>= 92` specs. This state is unresolvable, producing a `Solv general runtime error` that aborts the build.

This is not an isolated incident. **Every commit that introduces or modifies `build_if` gating creates an inconsistency window for all snapshots captured before that commit.** The window affects any combination of release branch (4.0, 5.0, 6.0), architecture (x86_64, aarch64), and ISO flavor (minimal, full, FIPS) that shares the `common/` spec tree. The Photon OS build system has no mechanism to validate that a snapshot's package list remains consistent with the set of specs activated by its corresponding subrelease value after new gating commits land.

## Proposed Solution

A `.github/` structure that implements a multi-agent CI pipeline with strict role separation to automatically detect these conflicts before they reach builds.

### Six Conflict Constellations Detected

| ID | Constellation | Example from 6b7bc7c |
|----|--------------|----------------------|
| C1 | Package split/merge inconsistency | libcap split introduces subpackages absent from snapshot 91 |
| C2 | Version bump with new dependencies | rpm 4.18.2-9 adds `Requires: libcap-libs` not in old spec |
| C3 | Subrelease threshold boundary mismatch | Snapshot 91 captured before gating commit, metadata inconsistent |
| C4 | Cross-branch contamination via common/ | Ph5 and Ph6 share common/ but need different subreleases |
| C5 | FIPS canister version coupling | Kernel spec pins canister version absent from snapshot |
| C6 | Snapshot URL availability | Snapshot number not published on Artifactory (HTTP 404) |

### CI Integration Points

1. **Pre-merge PR gate** on `common/` and release branches -- catches C1, C2, C4 conflicts before they land in the repo.
2. **Post-snapshot publication** (scheduled daily or triggered) -- verifies C3 and C6 by probing Artifactory for snapshot-spec consistency.
3. **Pre-build validation** before `make image` -- catches all six constellations with the exact configuration that will be used for the build.

### Severity Classification

| Severity | Action | Example |
|----------|--------|---------|
| BLOCKING | CI job fails, build cannot start | C6: snapshot 404 |
| CRITICAL | CI job fails, build will fail | C1: package split with stale snapshot |
| HIGH | CI job warns, build may fail | C2: transitive dependency gap |
| WARNING | Logged, informational | C4: overlapping specs (versions match) |

## Specifications (specs/)

Following the [SDD-book-tracking-app](https://github.com/sitoader/SDD-book-tracking-app) pattern:

```
specs/
├── prd.md                                   # Product Requirements Document with REQ-1..REQ-10
├── features/                                # Feature Requirement Documents (one per constellation)
│   ├── c1-package-split-merge.md            # FRD-C1: subpackage diff, consumer detection
│   ├── c2-version-bump-deps.md              # FRD-C2: cross-gating dependency analysis
│   ├── c3-subrelease-boundary.md            # FRD-C3: boundary mismatch + tdnf upgrade conflict
│   ├── c4-cross-branch-contamination.md     # FRD-C4: common/ spec divergence
│   ├── c5-fips-canister.md                  # FRD-C5: kernel-canister version coupling
│   └── c6-snapshot-url.md                   # FRD-C6: Artifactory URL validation
├── adr/                                     # Architecture Decision Records
│   ├── 0001-snapshot-bypass-via-photon-mainline.md
│   ├── 0002-tdnf-upgrade-conflict.md
│   └── 0003-detection-agent-architecture.md
├── tasks/                                   # Numbered implementation tasks with dependencies
│   ├── 001-task-spec-parser-inventory.md
│   ├── 002-task-output-schema.md
│   ├── 003-task-ci-workflow.md
│   ├── 004-task-c1-c2-detectors.md
│   ├── 005-task-c3-detector.md
│   ├── 006-task-c4-c5-c6-detectors.md
│   ├── 007-task-reference-validation.md
│   └── 008-task-adr-documentation.md
└── findings/                                # Timestamped scan results
    ├── 2026-03-06-findings.json             # Machine-readable (97 findings)
    └── 2026-03-06-findings.md               # Human-readable with remediation
```

## CI Structure (.github/)

```
.github/
├── agents/                                  # Agent definitions with strict role separation
│   ├── gating-orchestrator.agent.md         # Entry point, routes workflows to specialists
│   ├── gating-detector.agent.md             # Read-only scanner for all 6 constellations
│   ├── gating-remediation.agent.md          # Proposes/applies fixes (never decides what's broken)
│   ├── fips-validator.agent.md              # Deep C5 FIPS canister version validation
│   ├── artifactory-probe.agent.md           # C6 snapshot URL availability checks
│   └── build-config-fixer.agent.md          # Executes pre-approved build-config.json edits
├── prompts/                                 # Reusable workflow templates
│   ├── detect-conflicts.prompt.md           # Full detection workflow with quality checklist
│   ├── apply-remediation.prompt.md          # Remediation workflow with severity prioritization
│   ├── adr.prompt.md                        # Architecture Decision Record template for gating changes
│   ├── inventory.prompt.md                  # Phase 0: build tree discovery before detection
│   ├── modernize-gating.prompt.md           # Deep phased assessment (assess/strategy/execute)
│   ├── traceability.prompt.md               # Full blast-radius traceability matrix
│   └── generate-agents.prompt.md            # Agent ecosystem bootstrap/validation
├── scripts/                                 # Implementation scripts
│   ├── photon-gating-agent.py               # Python detection engine
│   └── fix-gating-conflict.sh               # Spec-level remediation (swap build_if guards)
├── workflows/
│   └── gating-conflict-detection.yml        # GitHub Actions CI pipeline
├── gating-findings-schema.json              # JSON Schema for machine-readable findings
└── quality-rubric.md                        # Pass/fail criteria for all agent outputs
```

### Spec-Level Remediation Script

When the `photon-mainline` bypass strategy is not suitable, `fix-gating-conflict.sh` provides direct spec-level remediation. It swaps the `build_if` guards between old and new spec files so the new split package becomes active at the current subrelease, then optionally rebuilds the package and updates the local RPM repo metadata. Supports `--dry-run`, `--revert`, configurable `--package` and `--build-root`.

```bash
# Preview what would change
.github/scripts/fix-gating-conflict.sh -p libcap -b ~/5.0 --dry-run

# Apply fix and rebuild
.github/scripts/fix-gating-conflict.sh -p libcap -b ~/5.0 --build
```

### Key Design Decisions

- **Role separation**: The detector never modifies files; the fixer never decides what to change. This follows the analyst/remediation split pattern.
- **Dual-format output**: Every detection run produces both human-readable markdown (`findings.md`) and machine-readable JSON (`findings.json`) validated against `gating-findings-schema.json`.
- **Phase 0 inventory**: Before any detection, a complete build tree inventory (`gating-inventory.json`) establishes ground truth about all gated specs, branch configs, and relocated directories.
- **Traceability**: Every finding includes the full blast-radius chain: spec -> subpackages -> consuming specs -> branches -> snapshots -> architectures -> ISO flavors.
- **ADR enforcement**: Every remediation applied requires an Architecture Decision Record documenting what changed, why, and how to roll back.
- **Quality rubric**: Automated pass/fail validation of agent output quality before it reaches humans or CI decisions.

## How to Introduce in vmware/photon

### Step 1: Add to the `common` branch

The `.github/` directory belongs in the `common` branch of `vmware/photon` because it operates across all release branches. Create a PR adding the entire `.github/` structure from this directory.

### Step 2: Implement the Python agent script

Place `photon-gating-agent.py` in `.github/scripts/`. This script implements the detection logic described in `gating-detector.agent.md`: it parses all `.spec` files for `build_if` directives, extracts package names and dependency lists, resolves snapshot URLs, and produces dual-format output. The core algorithm is outlined in [gatingmechanism.agent.md](../gatingmechanism.agent.md) at the repository root.

### Step 3: Enable the GitHub Actions workflow

The workflow in `.github/workflows/gating-conflict-detection.yml` triggers on:
- PRs to `common`, `4.0`, `5.0`, `6.0` that touch `SPECS/**` or `build-config.json`
- Manual dispatch with configurable branch list and URL checking
- Daily schedule (cron `0 6 * * *`)

It checks out all branches into a `workspace/` directory, runs the inventory and detection phases, validates output against the JSON Schema and quality rubric, and fails the job on BLOCKING/CRITICAL findings.

### Step 4: Validate with the 6b7bc7c commit as a test case

Run the agent against the repo state immediately after commit `6b7bc7c` with snapshot 91 configured. The expected output is:
- **C1 CRITICAL**: libcap split -- `libcap-libs`, `libcap-minimal`, `libcap-doc` are new subpackages not in snapshot 91; `rpm.spec` (gated `>= 92`) depends on `libcap-libs`
- **C3 HIGH**: Snapshot 91 predates the gating commit; snapshot metadata is inconsistent with post-gating spec state

This confirms the agent would have caught the exact conflict that broke the Ph5 build.

### Step 5: Create an ADR

Using the `adr.prompt.md` template, document the introduction of gating conflict detection as ADR-0001, recording the decision rationale, affected branches, and the tradeoff between snapshot reproducibility and build reliability.

## Related

- [gatingmechanism.agent.md](../gatingmechanism.agent.md) -- original conflict detection agent with embedded Python implementation
- [vmware/photon commit 6b7bc7c](https://github.com/vmware/photon/commit/6b7bc7c77f66165a3413464f5b0495e510691a57) -- the libcap package split commit that exposed this class of conflicts
