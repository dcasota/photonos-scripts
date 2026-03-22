# Package Report Database Tool — Tasks

Task tracker for the package-report-database-tool engineering effort.

## Status Overview

| Task | Title | Phase | Status | Dependencies |
|------|-------|-------|--------|--------------|
| 001 | Project Scaffold | 1 - Scaffold | ✅ Done | — |
| 002 | Security Module | 2 - Core | ✅ Done | 001 |
| 003 | CSV Parser | 2 - Core | ✅ Done | 002 |
| 004 | DB Schema & Import | 2 - Core | ✅ Done | 002, 003 |
| 005 | Report Queries | 3 - Reports | ✅ Done | 004 |
| 006 | Chart XML Generator | 3 - Reports | ✅ Done | 005 |
| 007 | DOCX Writer | 3 - Reports | ✅ Done | 006 |
| 008 | Main CLI | 4 - Integration | ✅ Done | 004, 007 |
| 009 | Tests | 5 - Testing | ✅ Done | 008 |
| 010 | CI Integration | 6 - CI | 🔲 Pending | 009 |

## Phases

### Phase 1 — Scaffold
- **001** Project Scaffold — Makefile, CMakeLists.txt, directory structure

### Phase 2 — Core
- **002** Security Module — security.h/c: input validation, path sanitization, XML escaping
- **003** CSV Parser — csv_parser.h/c: UTF-16LE/UTF-8 auto-detect, 5/12-col schema
- **004** DB Schema & Import — db.h/c: schema creation, dedup check, transactional insert

### Phase 3 — Reports
- **005** Report Queries — report.h/c: timeline, top-changed, least-changed, categories
- **006** Chart XML Generator — chart_xml.h/c: OOXML DrawingML line chart + pie chart
- **007** DOCX Writer — docx_writer.h/c: ZIP creation, OOXML document assembly

### Phase 4 — Integration
- **008** Main CLI — main.c: argument parsing, orchestration

### Phase 5 — Testing
- **009** Tests — unit tests, integration test, run_tests.sh

### Phase 6 — CI
- **010** CI Integration — GitHub Actions workflow for build/test

## Conventions
- Files follow the SDD task format from `docsystem/specs/tasks/`.
- Each task has: Title, Status, Phase, Dependencies, PRD refs, Description, Acceptance Criteria.
