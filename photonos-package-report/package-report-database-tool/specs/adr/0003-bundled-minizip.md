# ADR-0003: Bundled Minimal ZIP Writer

**Status**: Accepted
**Date**: 2026-03-22

## Context

.docx files are ZIP archives. We need to create (not read) ZIP files containing XML.

## Decision

Implement a **minimal ZIP writer** (~200 lines) using raw zlib deflate, rather than bundling minizip or adding libzip as a dependency.

## Rationale

- We only need ZIP creation, not extraction
- The ZIP local-file-header + central-directory format is straightforward
- zlib is already installed on Photon OS
- Avoids adding another dependency or vendoring minizip source files
- The .docx files we create contain <10 small XML files — complexity is minimal

## Consequences

- ZIP writer handles only deflate compression (sufficient for OOXML)
- No ZIP64 support needed (files are small)
- Tested by verifying `unzip -l` on generated .docx
