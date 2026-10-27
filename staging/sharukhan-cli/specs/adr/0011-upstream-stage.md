# ADR-0011 — Upstream PRs move after the staged VM and a person's approval

Status: accepted, implemented
Date: 2026-10-25
Commits: 7fed500c
Docs: [docs/automation/sync.md](../../docs/automation/sync.md#upstream-prs-shared-branches-staged-first)

## Context

Fifteen upstream PRs are opened from fork branches: an upstream PR and the
fork's PR share one head branch. Pushing the fork's branch therefore changed
the upstream PR's code at once, before the staged-VM verification and without
approval. GitHub cannot give an existing PR another head branch, and the
upstream maintainers keep their review conversation on the PRs they have.

## Options considered

1. **Replace the upstream PRs** by new ones from separate `vmware/<branch>`
   heads. Clean separation, but closes and reopens fifteen PRs and loses the
   maintainers' threads (rejected by the user, 2026-10-25).
2. **Hold back only the descriptions**: the code moves with the fork push,
   only the upstream text waits for approval. Breaks the order "staged VM
   first, upstream last" for the code.
3. **Stage the code on a branch no PR uses.** PUBLISH pushes a paired branch,
   and every PR stacked on it, to `staging/<branch>` on the fork; STAGEVM
   checks the staged code is the gated code and installs the staged-VM rows
   from it; UPSTREAM waits for approval, then moves the shared branch - both
   PRs change at that moment - and edits both descriptions in place.

## Decision

Option 3. UPSTREAM always waits for `sync approve-upstream`, whatever
`MC_PUBLISH_DCASOTA` says. Before anything is pushed it checks each upstream
description (the lint, plus a cross-org rule: no fork owner name, no PR
number that is neither an upstream PR of the fork nor already in the text)
and that the head merges cleanly onto the upstream PR's base. sharukhan never
opens, closes or comments on an upstream PR; a fork PR without an upstream
counterpart is published on the fork only (user policy, 2026-10-25: no new
upstream PRs until the maintainers have acted on the existing ones).

## Consequences

- For paired PRs the fork's PR shows a change at the same moment as the
  upstream PR, not earlier; the code is on the fork beforehand in
  `staging/<branch>`.
- The upstream maintainers see their PRs updated in place, never a new
  thread or PR.
- An aborted run leaves its `staging/<branch>` pushes on the fork and says so.
