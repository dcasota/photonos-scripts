# Changelog

All notable changes to the package-report-database-tool are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Added
- SDD scaffolding: PRD, 4 FRDs, 5 ADRs, 10 task specs
- Factory AI config: 3 droids (c-implementer, security-auditor, test-runner), PostToolUse hook, 2 slash commands
- Task 001: Project scaffold — Makefile, CMakeLists.txt, directory structure
- Task 002: security.h/c — input validation, path sanitization, XML escaping
- Task 003: csv_parser.h/c — CSV parsing with UTF-16LE/UTF-8 auto-detect, 5/12-col schema
- Task 004: db.h/c — SQLite schema, dedup import, SHA-256 integrity, report queries
- Task 005: report.h/c — report data aggregation (included in db.c queries)
- Task 006: chart_xml.h/c — OOXML DrawingML line chart and pie chart generation
- Task 007: docx_writer.h/c — .docx ZIP creation with OOXML document assembly
- Task 008: main.c — CLI entry point with --db, --import, --report arguments
- Task 009: Unit tests and integration test
- README.md — usage guide, build instructions, security overview
- ARCHITECTURE.md — component diagram, data model, query details, .docx generation
- database-report.yml — self-hosted GitHub Actions workflow (build, test, import, report, upload)
- reports/ directory with .gitignore for generated output
- report-<datetime>.docx auto-naming when --report points to a directory
- 3D stacked bar chart (c:bar3DChart) for source category drift over time
- db_query_category_drift() — per-scan per-branch category percentage tracking
- db_query_top_changed() — all-branches top-changed query (replaces 5.0-only)

### Changed
- Section 4: pie chart now shows branch 5.0 only (was all branches)
- Section 4: replaced 3D bar chart with 2D 100%-stacked bar chart for 5.0 branch
- Section 2: top-changed now covers all branches, not just 5.0
- Section 3: least-changed requires presence in all 7 branches
- Section 4: renamed to "Source Category Drift", "No URL" → "(scan issues)"
- Source categories: 10 new domains (pypi, gnome.org, x.org, apache.org, etc.)
- Categories below 3% merged into "Other" via SQL CTE threshold
- Upgraded actions/checkout@v4 → v6, actions/upload-artifact@v4 → v6 (Node.js 24)

### Fixed
- YAML heredoc syntax error in database-report.yml (line 149)
- .docx missing word/settings.xml, webSettings.xml, fontTable.xml (Word refused to open)
- .docx missing <w:tblGrid> elements in tables (OOXML strict compliance)
- Duplicate docPr id="1" on all chart drawings (OOXML requires unique ids)
- "paguire.io" typo → "pagure.org" in category CASE statement
