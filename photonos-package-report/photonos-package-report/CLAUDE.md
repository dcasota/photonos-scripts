# photonos-package-report (C port) — Project Context

This sub-project is a 1:1 C migration of the parent
`photonos-package-report/photonos-package-report.ps1` script (5,522 lines).

## Invariants (all Claude Code sessions inherit these)

1. **Bit-identical output to the PowerShell script is non-negotiable.** Performance is secondary. Never introduce an "improvement" that changes a `.prn` byte unless an ADR explicitly accepts it.
2. **`../photonos-package-report.ps1` is the upstream source-of-truth.** Never modify it from this sub-project. Bugfixes flow PS → spec → C, not the other way around.
3. **No reordering of mutations on `$Source0`** when porting. The substitution sequence at PS lines 2161-2199 must be translated in source order, line for line.
4. **Photon-only.** Build and run on Photon 5/6 with `tdnf`. No portability hooks for Debian/RHEL/etc.
5. **No Python in the build pipeline.** Generators are POSIX shell + awk only.
6. **No Factory.ai droids.** Agents run exclusively as Claude Code subagents declared in `.claude/agents/*.md` (see ADR-0011).

## SDD lifecycle

```
PM agent → Dev Lead → Architect → Developer → Code
```

Every code change traces back through `specs/tasks/README.md` → FRD → ADR → PRD. Status of each spec moves Draft → Reviewed → Accepted → Implemented.

## Commit message template (enforced via tools/git-hooks/commit-msg)

```
phase-<N> task <NNN>: <imperative subject>

FRD: FRD-<NNN>
ADR: ADR-<NNNN>[, ADR-<NNNN>...]
PS-source: photonos-package-report.ps1 L <start>-<end>
Parity: <strict|soft|n/a>
```

## Build & test (once Phase 1 lands)

```bash
cmake -B build -S .
cmake --build build
ctest --test-dir build
tools/parity-diff.sh build/photonos-package-report ../photonos-package-report.ps1
```

## Phase tracker (always include in status replies)

| Phase | Title | Status |
|-------|-------|--------|
| 0 | SDD scaffold | in progress |
| 1 | Foundation (params, types, diskspace, git-timeout) | pending |
| 2 | Spec ingestion (Get-AllSpecs port) | pending |
| 3 | Embedded data (Source0LookupData + spec-hook dispatch) | pending |
| 4 | Substitution core (%{url}/%{name}/%{version}/...) | pending |
| 5 | Network & lookups (urlhealth, GitHub/GitLab tags, Koji) | pending |
| 6 | CheckURLHealth main path + .prn assembly | pending |
| 7 | Cluster orchestrator + parallel runspace mirror | pending |
| 8 | CI side-by-side parity gate | pending |
| 9 | Retirement (PS → staging/legacy/, C-only) | pending |
