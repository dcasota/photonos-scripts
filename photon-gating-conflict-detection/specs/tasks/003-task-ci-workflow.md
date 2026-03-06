# Task 003: GitHub Actions Workflow Integration

**Dependencies**: Task 002
**Complexity**: Medium
**Status**: Complete

---

## Description

Create the GitHub Actions workflow that runs the detection pipeline on PRs, daily schedule, and manual dispatch.

## Requirements

- Trigger on PRs to `common`, `4.0`, `5.0`, `6.0` touching `SPECS/**` or `build-config.json`
- Trigger on daily schedule (cron `0 6 * * *`)
- Trigger on `workflow_dispatch` with configurable branches and URL checking
- Check out CI tooling and Photon OS branches into separate directories
- Run Phase 0 (inventory) and Phase 1 (detection)
- Validate findings against JSON schema
- Run quality rubric checks
- Fail job on BLOCKING/CRITICAL findings
- Upload findings as artifacts

## Acceptance Criteria

- [ ] Workflow YAML passes `actionlint` validation
- [ ] All checkout paths are correct (ci/ for tooling, workspace/ for branches)
- [ ] Schema and rubric validation steps execute inline Python
- [ ] Findings artifacts uploaded even on failure

## Implementation

File: `.github/workflows/gating-conflict-detection.yml`
