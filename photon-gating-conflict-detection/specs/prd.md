# Product Requirements Document (PRD)

## Photon OS Gating Conflict Detection

**Version**: 1.0
**Last Updated**: 2026-03-06
**Status**: Technical Review Complete

---

## 1. Purpose

The Photon OS build system uses `build_if` conditional gating to select between old and new package specs based on `photon_subrelease`, and snapshot pinning to lock the remote repository to a known-good package set. These two mechanisms interact destructively: every commit that introduces or modifies `build_if` gating creates an inconsistency window for all snapshots captured before that commit.

This project delivers an automated detection pipeline that scans the Photon OS build tree for conflicts between gating and snapshot state, classifies findings by severity, and provides actionable remediation.

**Target Users**: Photon OS build engineers, release managers, and CI maintainers.

**Motivation**: Commit [6b7bc7c](https://github.com/vmware/photon/commit/6b7bc7c77f66165a3413464f5b0495e510691a57) (libcap v2.66 -> v2.77 split with `build_if` gating) caused unresolvable `Solv general runtime error` failures across 86+ packages in the 5.0 branch build.

---

## 2. Scope

### In Scope

- Detect all six known conflict constellations (C1-C6) across release branches
- Scan `build_if` gates in all `.spec` files across `common/`, `4.0/`, `5.0/`, `6.0/`
- Validate snapshot URL availability on Broadcom Artifactory
- Detect remote repo version conflicts when snapshot is bypassed (C3+ upgrade pattern)
- Produce dual-format output: machine-readable JSON + human-readable Markdown
- Provide severity classification (BLOCKING, CRITICAL, HIGH, WARNING)
- Include actionable remediation for every finding
- Run as GitHub Actions CI workflow and as standalone CLI tool

### Out of Scope

- Automatically applying fixes to `build-config.json` (remediation is advisory only)
- Building or testing ISO images
- Modifying `.spec` files
- LLM or AI inference (pipeline is fully deterministic Python)

---

## 3. Goals and Success Criteria

### Goals

1. **Prevention**: Catch gating-snapshot conflicts before they reach builds
2. **Visibility**: Provide full blast-radius traceability for every finding
3. **Actionability**: Every finding includes a concrete remediation suggestion
4. **Automation**: Run unattended in CI with pass/fail exit codes

### Success Criteria

- [SC-1] Agent detects the libcap split conflict (commit 6b7bc7c) as C1 CRITICAL
- [SC-2] Agent detects the systemd/Linux-PAM/dbus upgrade conflict as C3 CRITICAL
- [SC-3] Zero false negatives on gated spec pairs with subpackage differences
- [SC-4] Findings JSON validates against `gating-findings-schema.json`
- [SC-5] CI job fails on BLOCKING/CRITICAL, passes on WARNING-only
- [SC-6] Full scan of 3 branches + common completes in under 60 seconds

---

## 4. Requirements

### [REQ-1] Constellation C1 -- Package Split/Merge Detection

The agent must detect when a gated spec pair has different subpackage sets, and at least one consumer depends on subpackages that only exist in the inactive spec.

**Related**: FRD-C1, ADR-0001

### [REQ-2] Constellation C2 -- Version Bump with New Dependencies

The agent must detect when a gated spec pair's new version adds Requires or BuildRequires on packages produced by other inactive gated specs.

**Related**: FRD-C2

### [REQ-3] Constellation C3 -- Subrelease Threshold Boundary Mismatch

The agent must detect when a branch uses a snapshot whose number matches the gating threshold, and when snapshot bypass (photon-mainline) causes `tdnf upgrade` to pull newer versions from the remote repo.

**Related**: FRD-C3, ADR-0002

### [REQ-4] Constellation C4 -- Cross-Branch Contamination via common/

The agent must detect when two branches share common/ specs with different subreleases, activating different spec sets from the same gating threshold.

**Related**: FRD-C4

### [REQ-5] Constellation C5 -- FIPS Canister Version Coupling

The agent must detect kernel specs with FIPS canister BuildRequires and verify version alignment.

**Related**: FRD-C5

### [REQ-6] Constellation C6 -- Snapshot URL Availability

The agent must validate that the snapshot URL for each branch returns HTTP 200, and probe nearby snapshot numbers on failure.

**Related**: FRD-C6

### [REQ-7] Build Tree Inventory (Phase 0)

Before detection, the agent must produce a complete inventory of all branches, their `build-config.json` parameters, all gated specs, and relocated spec directories.

**Related**: FRD-inventory

### [REQ-8] Dual-Format Output

Every detection run must produce both `findings.json` (machine-readable, schema-validated) and `findings.md` (human-readable with severity icons and remediation).

**Related**: quality-rubric.md

### [REQ-9] Severity Classification and CI Integration

Findings must be classified as BLOCKING, CRITICAL, HIGH, or WARNING. CI job must exit non-zero on BLOCKING or CRITICAL findings.

**Related**: FRD-C1 through FRD-C6

### [REQ-10] Blast-Radius Traceability

Every finding must include the chain: spec -> subpackages -> consuming specs -> branches -> affected packages. C3+ findings must identify all ungated consumer packages.

**Related**: traceability.prompt.md

---

## 5. Traceability Matrix

| Requirement | Feature (FRD) | ADR | Task | Agent | Prompt |
|-------------|---------------|-----|------|-------|--------|
| REQ-1 | FRD-C1 | ADR-0001 | 001, 005 | gating-detector | detect-conflicts |
| REQ-2 | FRD-C2 | -- | 001, 005 | gating-detector | detect-conflicts |
| REQ-3 | FRD-C3 | ADR-0002 | 001, 005 | gating-detector | detect-conflicts |
| REQ-4 | FRD-C4 | -- | 001, 005 | gating-detector | detect-conflicts |
| REQ-5 | FRD-C5 | -- | 001, 005 | fips-validator | detect-conflicts |
| REQ-6 | FRD-C6 | -- | 001, 005 | artifactory-probe | detect-conflicts |
| REQ-7 | FRD-inventory | -- | 001 | gating-detector | inventory |
| REQ-8 | -- | ADR-0003 | 002 | gating-orchestrator | -- |
| REQ-9 | -- | -- | 003 | gating-orchestrator | -- |
| REQ-10 | -- | -- | 005 | gating-detector | traceability |

---

## 6. Assumptions and Constraints

### Assumptions

- Branch checkouts (`4.0/`, `5.0/`, `6.0/`, `common/`) are available locally or via CI checkout
- `build-config.json` in each branch contains `photon-subrelease` and optionally `photon-mainline`
- Broadcom Artifactory (`packages.broadcom.com`) is reachable for C6 URL validation
- `.spec` files use `%global build_if %{photon_subrelease} <= N` or `>= N` syntax

### Constraints

- **No LLM/AI dependency**: Pipeline must be fully deterministic Python 3.11
- **Read-only**: Agent never modifies spec files or build configs (detection only)
- **Dependencies**: Only `requests` and `jsonschema` (both in PyPI)
- **Performance**: Full scan must complete in under 60 seconds for CI viability
- **Compatibility**: Must run on GitHub Actions `ubuntu-latest` runner

---

**Document Version**: 1.0
**Status**: Ready for Implementation
