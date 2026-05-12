# ADR-0001: Language choice — C

**Status**: Accepted
**Date**: 2026-05-12

## Context

The migration from PowerShell needs a compiled, statically-typed target that produces a single binary deployable on Photon. Candidates: C, C++, Rust, Go.

## Decision

**C (C11)**.

## Rationale

- Sibling C tools in this repo (`upstream-source-code-dependency-scanner`, `tdnf-depgraph`, `photonos-package-report/package-report-database-tool`) already use C, sharing build conventions and CI patterns.
- All required libraries (libcurl, PCRE2, json-c, pthread, libarchive) are mature C ABIs available as Photon RPMs — no toolchain bootstrap needed.
- C's lack of metaprogramming forces the port to remain mechanically faithful to PowerShell's straight-line logic. This *helps* the bit-identical goal: there's no idiomatic abstraction to be tempted by.
- The original script shells out heavily to `git`/`tar` (1,043 + 958 call sites) — C's `posix_spawn` matches PowerShell's `Start-Process` cleanly.

## Consequences

- No generics; per-type duplication accepted (cost paid once at port time).
- Manual memory management; partial mitigation via arena allocation per parallel task.
- No structural pattern matching for `if ($currentTask.spec -ilike 'X.spec')` — handled by ADR-0007's dispatch-table approach.

## Considered alternatives

- **C++**: more comfortable string handling but introduces ABI compatibility headaches with the existing C sibling tools and would dilute the "minimal abstraction" property.
- **Rust**: ideal safety, but the toolchain is not pre-installed on the Photon runner, and `unsafe` would be needed for libcurl/PCRE2 bindings, weakening the safety argument.
- **Go**: GC pauses fight bit-identical timing; cgo overhead for libcurl/PCRE2 unfriendly.
