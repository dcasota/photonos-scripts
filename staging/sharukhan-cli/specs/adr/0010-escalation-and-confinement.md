# ADR-0010 — Escalating a stopped PR to a model, confined and verified

Status: accepted, implemented
Date: 2026-10-24, amended 2026-10-25
Commits: 381c5647, 3f85610d, 6c29eb66, 55ed4c20, 6a757f38, 78b01b02, ecf8dea0
Docs: [docs/automation/escalation.md](../../docs/automation/escalation.md)

## Context

A sync stops for a decision when a rebase conflicts or a check fails (ADR-0009).
Most such conflicts are mechanical - a hunk moved, a Release renumbered - but
each still waited for a person. Handing them to a language model saves that
time only if the model cannot do harm, cannot spend without limit, and its
answer is never trusted.

## Options considered

1. **No automation**: a person resolves every stopped PR. Safe, slow.
2. **A model with a shell in the gate repository.** Fast to build; the model
   could run anything as root on a host that holds credentials and other
   projects' VMs.
3. **A model with only purpose-built tools.** `claude -p` with its built-in
   tools switched off and one MCP server (`sharukhan mcp`) offering read tools
   over the stopped PR, `propose_patch` (writes only the proposal ref),
   `verify` and `propose_description`; budgets in `memory.db`; sharukhan
   re-verifies every proposal itself.

## Decision

Option 3. The model runs as `claude --bare -p --tools ""` with the
sharukhan MCP tools only, in an empty directory with a cleared environment
(PATH, a private HOME, the API key); the MCP server runs under `env -i`
without the key. Budgets are tokens weighted by price (cache reads 0.1,
cache writes 1.25 or 2.0), per escalation, per run and per day, plus two
attempts per PR; the stream is cut when an escalation's budget is exceeded.
A proposal becomes a candidate only through `sync decide`. The spec tools
`verify` runs on proposed specs (rpmspec, check_spec) run in read-only,
capability-free containers without network, so a `%(...)` macro in a
proposed spec cannot write the gate tree (ecf8dea0). `sync auto` hands a
stopped run to the queue on every tick; a budget, a rate limit or a missing
key parks it with one notification.

## Consequences

- Escalation costs are recorded per attempt (`escalation` table) and capped.
- No model output reaches GitHub without a person's `sync decide`.
- Both processes still run as root; the safeguards are the missing built-in
  tools, the read-only containers and the verification, not a restricted user.
