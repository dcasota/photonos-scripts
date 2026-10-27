# ADR-0009 — Keeping the fork's PRs current as a resumable state machine

Status: accepted, implemented
Date: 2026-10-23 (state machine), amended through 2026-10-25
Commits: 8edee187, db9b9c05, e66ff6de, cbff11e4, 7e5c44d4, 78b01b02, c8163943, 7c999ea7, 8438d93c
Docs: [docs/automation/sync.md](../../docs/automation/sync.md)

## Context

The fork carries about 70 PRs against `5.0` and `common`. Every move of those
bases meant the same recipe by hand: analyze every PR against the new base,
rebase the ones that need it, verify the specs, regenerate the variant
patches, build, run the fast loop and the gate, push the PRs with their
descriptions carried over, and only then touch the upstream PRs. A recipe of
hours to days, interrupted by WSL restarts, builds that fail at hour three and
decisions only a person can take, must survive interruption and must never
publish what was not gated.

## Options considered

1. **A script per step, run by hand** (the state before). Every interruption
   lost track of what was done; nothing stopped a push of an ungated head.
2. **A CI pipeline on GitHub.** The builds and VMs live on this workstation;
   the gate cannot run in hosted CI, and a pipeline that only orchestrates a
   local runner still needs the local state.
3. **A resumable state machine in `memory.db`.** Each run is a row, each stage
   a row with state, evidence and a detail line, each PR a row with its lease
   (the head ANALYZE saw), its candidate and its state; stages are
   idempotent, and the inputs are re-checked before every stage.

## Decision

Option 3. The stages are ANALYZE, REBASE, VERIFY, PREPARE, FASTLOOP, GATE,
PUBLISH, STAGEVM, UPSTREAM, DONE. One run at a time. A stage left `running`
by a process that is gone becomes `interrupted` and runs again. A refused
rebase or a failed check stops the run as `needs-decision` - the input of the
escalation (ADR-0010) - and `sync decide` records the answer. Nothing reaches
GitHub before PUBLISH, which pushes with `--force-with-lease` against the
heads ANALYZE saw and edits a description only when the PR's own change is
unchanged or a reviewed description was recorded. `sync auto` (a 30-minute
timer) starts a run only when the fork's base moved and stayed quiet, no job
uses the builder, and every PR head in the gate repository equals GitHub's.
`run` fails when a row failed or an ISO group was refused, because GATE
judges by its exit code.

## Consequences

- A sync can be paused, aborted between stages and resumed after a restart.
- The gate repository's branches are the candidates during a run; PREPARE
  records their previous values and an abort restores them.
- Every decision and every published head is in `memory.db` and the run's
  evidence directory.
- A change held only in the gate repository holds the timer (event
  `sync-held`) until it is published.
