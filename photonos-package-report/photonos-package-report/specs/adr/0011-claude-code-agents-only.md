# ADR-0011: Agents run exclusively as Claude Code subagents — no Factory.ai droids, no other runtimes

**Status**: Accepted
**Date**: 2026-05-12

## Context

The SDD methodology used by the sibling `vCenter-CVE-drift-analyzer` project relies on multiple agent runtimes — Factory.ai droids defined under `.factory/droids/` and GitHub-published agent prompts under `.github/agents/`. For this project, the maintainer mandates a single agent runtime: **Claude Code**.

## Decision

All SDD-role agents (pm, devlead, architect, dev) and task-specific worker agents (source0-lookup-embedder, spec-hook-extractor, parity-harness) are defined as **Claude Code project-level subagents** under `.claude/agents/<name>.md`.

No `.factory/droids/` directory. No `.github/agents/` directory. No alternative agent-runtime files (Aider, OpenDevin, etc.).

## Rationale

- Single source of truth for agent prompts simplifies session bootstrapping.
- Claude Code's subagent invocation (via the `Agent` tool with `subagent_type:` matching a filename under `.claude/agents/`) is reproducible across sessions and machines.
- The maintainer interacts with the project exclusively via Claude Code; Factory.ai-side prompts would drift untested.

## File format

Claude Code subagent definition:

```markdown
---
name: <agent-name>
description: <one-sentence purpose; this is what Claude reads to decide when to invoke the agent>
tools: <comma-separated allowlist of tool names>
---

<system prompt, free-form markdown>
```

`tools:` is the **explicit allowlist**: each agent gets the minimum tools needed (pm reads/writes specs only; dev gets Bash too; etc.).

## Consequences

- Every agent has a corresponding `.claude/agents/<name>.md` file committed to this sub-project.
- A future audit or contributor can recreate the SDD pipeline by reading these seven files plus this ADR.
- Agent definitions are version-controlled and reviewable like any other artefact.
- The CLAUDE.md at the project root declares this invariant so future Claude Code sessions inherit it.

## Considered alternatives

- **Mixed runtimes** (Factory.ai + Claude Code): rejected. Prompt drift across runtimes is the most common SDD failure mode.
- **No agents, human-driven SDD**: works but loses the methodology's reproducibility guarantee.
