# photonos-package-report (C port)

A 1:1 C migration of [`../photonos-package-report.ps1`](../photonos-package-report.ps1) (5,522-line PowerShell). Driven by the Spec-Driven Development (SDD) methodology, runs on Photon 5/6.

## Status

Phase 0 — SDD scaffold in progress. See [specs/tasks/README.md](specs/tasks/README.md) for the full phase tracker.

## Quick links

- [PRD](specs/prd.md) — what we're building and why
- [ARCHITECTURE.md](ARCHITECTURE.md) — data flow, PS-to-C function mapping, threading model
- [ADRs](specs/adr/) — 11 architecture decisions
- [FRDs](specs/features/) — 16 feature requirement documents
- [CLAUDE.md](CLAUDE.md) — invariants, commit-msg template, phase tracker

## How this project is built

This is an SDD project: PRD → ADRs → FRDs → tasks → code. No code is written before its FRD is `Status: Accepted`. Every commit references an FRD and at least one ADR.

Agents run exclusively as Claude Code subagents under [`.claude/agents/`](.claude/agents/) (no Factory.ai droids — see [ADR-0011](specs/adr/0011-claude-code-agents-only.md)).

## Building (once Phase 1 lands)

```bash
sudo tdnf install -y cmake gcc libcurl-devel pcre2-devel json-c-devel libarchive-devel
cmake -B build -S .
cmake --build build
ctest --test-dir build
```

## License

Same as the parent repository (see `../../LICENSE`).
