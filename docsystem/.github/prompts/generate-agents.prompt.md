---
mode: agent
description: Bootstrap or validate the docsystem agent ecosystem
tools: [filesystem]
---

# Generate / Validate Agent Ecosystem

## Agent Inventory

The docsystem uses 5 agents defined in `.github/agents/`:

| Agent | Mode | Responsibility |
|-------|------|----------------|
| docsystem-orchestrator | orchestrator | Routes intent, manages pipeline sequence |
| commit-analyst | read-only | Imports commits from vmware/photon |
| blog-generator | write | Generates Hugo blog posts via xAI API |
| docs-quality-checker | read-only | Crawls and audits documentation |
| release-coverage-tracker | read-only | Tracks vCenter release coverage gaps |

## Validation Checklist

- [ ] All 5 agent files exist in `.github/agents/`
- [ ] Each agent has: name, description, mode, tools in frontmatter
- [ ] Orchestrator decision tree covers all user intents
- [ ] Each specialized agent has stopping rules defined
- [ ] Agent roles do not overlap (strict separation of concerns)
- [ ] Prompts in `.github/prompts/` align with agent capabilities

## Relationship to Factory Droids

The `.factory/` directory contains the 5-team swarm configuration (25 droids) which operates at a higher level. The `.github/agents/` define the SDD-pattern agents for spec-driven development coordination. Both coexist:
- `.github/agents/` → SDD development workflow (spec → implement → test)
- `.factory/teams/` → Runtime documentation processing swarm
