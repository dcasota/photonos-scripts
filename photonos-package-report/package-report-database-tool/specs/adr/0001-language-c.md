# ADR-0001: Implementation Language — C

**Status**: Accepted
**Date**: 2026-03-22

## Context

The existing `photonos-package-report.ps1` is a 5,300-line PowerShell script. A full migration to C was estimated at ~3.8M tokens and ~70 hours (see `SPEC_Migration_to_C.md`). Rather than migrate the entire script, this tool is a focused companion that handles database storage and report generation only.

## Decision

Implement in **C99** with POSIX extensions.

## Rationale

- Photon OS is a minimal Linux distro where C is the native toolchain
- SQLite3 C API is the most direct and efficient binding
- No runtime dependencies (no Python, Node, or PowerShell required)
- Matches the long-term migration trajectory in SPEC_Migration_to_C.md
- Compiler hardening flags provide strong security guarantees

## Consequences

- Manual memory management (mitigated by consistent patterns and valgrind testing)
- Verbose code for string handling (mitigated by security.c utility functions)
- .docx generation requires manual XML construction (mitigated by chart_xml.c module)
