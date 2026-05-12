# ADR-0004: Parallelism — fixed-size pthread pool mirroring `ForEach-Object -Parallel`

**Status**: Accepted
**Date**: 2026-05-12

## Context

PS L 5201 sets `$throttleLimit = 20`. `ForEach-Object -Parallel` then dispatches each `currentTask` to one of up to 20 isolated runspaces. Inside a runspace, only `$using:X`-captured variables flow in from outer scope; everything else is local.

## Decision

**pthread pool of exactly 20 workers**, fed by a single-producer SPSC queue of `pr_task_t *`.

## Rationale

- Bit-identical parity is the primary goal (ADR-0006). A different worker count would change ordering of network calls (DNS, TLS handshakes, response interleaving), which propagates into URL-health detection.
- Each worker holds its own `CURL *` handle, `pcre2_match_data *`, and scratch buffers — equivalent to the runspace isolation of `$using:`.
- A single writer thread drains a result queue and serialises `.prn` row writes; per-worker `.prn` row buffers feed into it. `flock` is reserved for cross-process safety (ADR-0010) but unused inside this binary's writer.

## Consequences

- Task ordering at the producer is deterministic (`scandir` + `alphasort`, matching PS `Get-ChildItem`).
- Per-worker state lives in a `pr_worker_ctx_t`; tasks never share writable state.
- A barrier sync at end-of-branch flushes the result queue before the next branch starts (matches PS behaviour at L 5043 where `$results` is fully collected, sorted, then written).

## Consequences for future change

If a runtime parameter ever needs to override the worker count, it requires a new ADR and an explicit parity-test sweep. Default stays at 20 in v1.

## Considered alternatives

- **libcurl multi-handle for HTTP-only parallelism + serial CPU work**: would diverge from PS runspace model and complicate ordering reproduction.
- **OpenMP**: pulls in toolchain dep without semantic gain.
