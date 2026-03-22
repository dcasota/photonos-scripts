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
