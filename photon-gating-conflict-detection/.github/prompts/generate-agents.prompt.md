---
agent: gating-orchestrator
---

# Generate/Update Gating Agent Definitions

## Mission

Bootstrap or update the gating agent ecosystem by ensuring all agent definitions in `.github/agents/` are consistent with the current build tree structure.

## Available Agents

| # | Agent | File | Role |
|---|-------|------|------|
| 1 | gating-orchestrator | `gating-orchestrator.agent.md` | Entry point, delegates to others |
| 2 | gating-detector | `gating-detector.agent.md` | Read-only conflict detection |
| 3 | gating-remediation | `gating-remediation.agent.md` | Applies fixes |
| 4 | fips-validator | `fips-validator.agent.md` | Deep FIPS canister validation |
| 5 | artifactory-probe | `artifactory-probe.agent.md` | Snapshot URL availability checks |
| 6 | build-config-fixer | `build-config-fixer.agent.md` | Executes file edits |

## Available Prompts

| # | Prompt | File | Purpose |
|---|--------|------|---------|
| 1 | detect-conflicts | `detect-conflicts.prompt.md` | Full detection workflow |
| 2 | apply-remediation | `apply-remediation.prompt.md` | Remediation workflow |
| 3 | adr | `adr.prompt.md` | Architecture Decision Record creation |
| 4 | inventory | `inventory.prompt.md` | Phase 0 build tree inventory |
| 5 | modernize-gating | `modernize-gating.prompt.md` | Deep phased assessment |
| 6 | traceability | `traceability.prompt.md` | Full traceability matrix |
| 7 | generate-agents | `generate-agents.prompt.md` | This file |

## Supporting Files

| File | Purpose |
|------|---------|
| `gating-findings-schema.json` | JSON Schema for findings output |
| `quality-rubric.md` | Pass/fail criteria for all agent outputs |
| `workflows/gating-conflict-detection.yml` | GitHub Actions CI pipeline |

## Validation

After generating/updating, verify:

- [ ] All 6 agent files exist in `.github/agents/`
- [ ] All 7 prompt files exist in `.github/prompts/`
- [ ] Schema file is valid JSON Schema
- [ ] Workflow file is valid GitHub Actions YAML
- [ ] Agent handoff references are consistent (no broken links)
- [ ] Stopping rules are defined for every agent
