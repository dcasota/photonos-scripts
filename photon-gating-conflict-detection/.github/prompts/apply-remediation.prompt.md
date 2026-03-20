---
agent: gating-remediation
---

# Apply Gating Remediation

## Mission

Given a `findings.json` from `gating-detector`, produce and execute a remediation plan that resolves all BLOCKING and CRITICAL conflicts.

## Step-by-Step Workflow

### 1. Load findings

Read `findings.json` produced by `gating-detector`. Validate that all required fields are present.

### 2. Prioritize by severity

Process in order:
1. **BLOCKING** (C6 snapshot unavailable) -- must fix first, build cannot start
2. **CRITICAL** (C1 package split, C4 cross-branch, C5 FIPS) -- build will fail
3. **HIGH** (C2 new deps, C3 boundary mismatch) -- build may fail
4. **WARNING/INFO** -- log only, no action required

### 3. Select remediation strategy

For each finding, choose the primary strategy:

| Constellation | Primary Fix |
|--------------|-------------|
| C1 | Set `photon-mainline` = `photon-subrelease` |
| C2 | Set `photon-mainline` = `photon-subrelease` |
| C3 | Set `photon-mainline` = `photon-subrelease` |
| C4 | Adjust `photon-subrelease` to correct value |
| C5 | Set `photon-mainline` to skip snapshot if canister in base repo |
| C6 | Set `photon-subrelease` to available snapshot, or set `photon-mainline` |

### 4. Generate remediation plan

Produce `remediation-plan.json` listing all edits:

```json
{
  "edits": [
    {
      "file": "<path>",
      "action": "set_key | insert_after | replace",
      "details": "...",
      "reason": "<constellation>: <explanation>"
    }
  ]
}
```

### 5. Present plan

- In `--interactive` mode: display the plan as a markdown diff and wait for approval
- In `--apply` mode: proceed directly to execution

### 6. Execute remediation

**For build-config edits** (primary strategy): delegate to `build-config-fixer`
agent with the approved `remediation-plan.json`.

**For spec-level fixes** (secondary strategy, when snapshot bypass is not
acceptable): run `fix-gating-conflict.sh` for each affected package:

```bash
.github/scripts/fix-gating-conflict.sh \
  -p <package> -b <build-root> --build
```

The script swaps `build_if` guards, optionally rebuilds the package, and
supports `--dry-run` for preview and `--revert` for rollback.

### 7. Verify

Re-run `gating-detector --verify --branch <affected-branches>` to confirm all BLOCKING/CRITICAL findings are resolved.

### 8. Create ADR

For each remediation applied, create an Architecture Decision Record:

```
adr/NNNN-gating-remediation-<branch>.md
```

Document: what was changed, why, which findings were resolved, and what the rollback procedure is.

## Quality Checklist

- [ ] All BLOCKING findings have a remediation action
- [ ] All CRITICAL findings have a remediation action
- [ ] Remediation plan specifies exact file paths and key names
- [ ] Before/after values are recorded for rollback
- [ ] Verification scan confirms resolution
- [ ] ADR created for each change
