# Docsystem Tasks

Task tracker for the photonos-scripts docsystem engineering effort.

## Status Overview

| Task | Title | Phase | Status | Dependencies |
|------|-------|-------|--------|--------------|
| 001 | Project Packaging | 1 - Core Infrastructure | 🔲 Pending | — |
| 002 | SQLite Schema Formalize | 1 - Core Infrastructure | 🔲 Pending | 001 |
| 003 | Import Pipeline | 2 - Existing Tool Formalization | 🔲 Pending | 002 |
| 004 | Summarizer Pipeline | 2 - Existing Tool Formalization | 🔲 Pending | 002 |
| 005 | Docs Lecturer Refactor | 2 - Existing Tool Formalization | 🔲 Pending | 001 |
| 006 | vCenter Release Scraper | 3 - New Capabilities | 🔲 Pending | 001 |
| 007 | Swarm Validation | 3 - New Capabilities | 🔲 Pending | 003, 004, 005 |
| 008 | CI Workflow | 3 - New Capabilities | 🔲 Pending | 001, 005 |

## Phases

### Phase 1 — Core Infrastructure
Foundation tasks that all other work depends on.
- **001** Project Packaging — pyproject.toml, dependency pinning, test scaffold
- **002** SQLite Schema Formalize — schema versioning, migration, validation

### Phase 2 — Existing Tool Formalization
Harden and refactor the tools that already exist.
- **003** Import Pipeline — logging, error handling, progress reporting for importer.py
- **004** Summarizer Pipeline — retry logic, modes, Hugo validation for summarizer.py
- **005** Docs Lecturer Refactor — package restructure, entry-point plugins, unit tests

### Phase 3 — New Capabilities
Net-new features and integration work.
- **006** vCenter Release Scraper — Broadcom KB scraping, coverage gap report
- **007** Swarm Validation — end-to-end Factory AI swarm testing
- **008** CI Workflow — GitHub Actions for lint, typecheck, test, blog-gen

## Conventions
- Files follow the SDD task format from `photon-gating-conflict-detection`.
- Each task has: Title, Status, Phase, Dependencies, PRD refs, Description, Acceptance Criteria, Implementation Notes.
- Status values: Pending → In Progress → Done.
