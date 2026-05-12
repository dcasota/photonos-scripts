# ADR-0010: `.prn` write serialisation — single writer thread + `flock` for cross-process

**Status**: Accepted
**Date**: 2026-05-12

## Context

The PS script writes `.prn` rows from parallel runspaces via `[System.IO.File]::AppendAllText`, which is atomic at the call granularity (kernel-level single-syscall append on Linux). Multiple runspaces racing produces interleaved-but-row-intact output. The post-sort step at PS L 5043 then reorders into the final alphabetical layout.

In the C app with pthreads, naive `fputs` from each worker would interleave at arbitrary byte boundaries. We need row-level atomicity.

## Decision

Inside the binary: **single writer thread** consumes a `pr_row_queue_t` (lock-free SPSC ring per worker, drained by the writer in arrival order). The writer flushes one row per `fwrite` + explicit `fflush`. The post-sort step at end-of-branch reorders the file alphabetically before the next branch starts.

Across processes (side-by-side CI runs PS and C in sequence): **`flock(LOCK_EX)`** on the target `.prn` file before any append, released after `fflush`. Matches PS's implicit serialisation.

## Rationale

- The single-writer model trivially preserves row-level atomicity and avoids a per-row mutex contention.
- `flock` is advisory but consistent: every consumer (the PS script, the C binary, the parity harness) calls it; no third-party tool writes to these files.
- `O_APPEND` (`open(..., O_APPEND)`) combined with `flock` gives the same row-level guarantees as PS's `AppendAllText` on Linux.

## Consequences

- One dedicated writer thread per process (in addition to the 20 worker threads from ADR-0004).
- The SPSC ring sizes are bounded; if a worker fills its ring, it blocks — preferred over dropping rows.
- The writer thread is the only owner of the `FILE *` for the `.prn` file; workers never touch it.

## Considered alternatives

- **Per-row mutex**: simpler but adds locking on the hot path. Single-writer pulls locking to the perimeter.
- **`O_APPEND` from multiple workers**: kernel atomicity is per-write-syscall; 4 KB stdio buffering could split rows. Rejected.
- **`mmap`-based shared buffer**: overkill.
