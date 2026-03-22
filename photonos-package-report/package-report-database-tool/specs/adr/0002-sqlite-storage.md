# ADR-0002: SQLite as Storage Engine

**Status**: Accepted
**Date**: 2026-03-22

## Context

178+ .prn scan files exist with no structured database. Trend analysis requires cross-file queries.

## Decision

Use **SQLite3** as the single-file embedded database.

## Rationale

- Zero-configuration: single file, no server process
- Pre-installed on Photon OS (`libsqlite3`)
- Excellent C API with parameterized queries (REQ-10)
- WAL mode supports concurrent reads during report generation
- Single-file portability: the .db file can be copied/shared

## Consequences

- Single-writer limitation (acceptable for batch import)
- No built-in full-text search needed for this use case
