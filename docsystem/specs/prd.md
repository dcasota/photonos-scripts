# Product Requirements Document (PRD) -- docsystem

**Version**: 1.0
**Date**: 2026-03-21
**Status**: Approved
**Author**: PM Agent (SDD pipeline)

## Overview

The docsystem is a documentation management, quality analysis, and publishing platform for VMware Photon OS. It imports git commit history from vmware/photon, generates AI-powered monthly changelogs as Hugo blog posts, crawls and audits a self-hosted Photon OS documentation site, and coordinates a 5-team Factory AI swarm for continuous documentation maintenance, translation, and security monitoring.

## Context: vCenter Release Coverage

The docsystem operates alongside the vCenter-CVE-drift-analyzer. An important finding is the coverage gap between published vCenter releases and those tracked by the drift analyzer:

```
Year     | vCenter 7.0 | vCenter 8.0 | vCenter 9.0 | Total
---------+-------------+-------------+-------------+------
2023     |      6      |      9      |     --      |  15
2024     |      4      |     10      |     --      |  14
2025     |      3      |      3      |      2      |   8
```

Key observations:
- Broadcom maintains 3 parallel vCenter release trains in 2025 (7.0, 8.0, 9.0)
- Patch velocity dropped from 15/year to 8/year as 7.0 winds down and 9.0 ramps up
- The drift analyzer currently tracks 10 of 24 vCenter 8.0 releases and 2 of 3 vCenter 9.0 releases
- Coverage is limited to releases that have Photon OS security patch tables on the vCenter Photon advisory wiki pages
- Broadcom KB article 326316 is the authoritative source for all vCenter build numbers and release dates

## Requirements

| ID | Requirement | Priority |
|----|-------------|----------|
| REQ-1 | Import git commits from vmware/photon into SQLite for 6 branches (3.0, 4.0, 5.0, 6.0, common, master), from 2021 to present | Critical |
| REQ-2 | Summarize monthly changelogs via xAI/Grok API and publish as Hugo-compatible blog posts with Keep-a-Changelog structure | Critical |
| REQ-3 | Crawl self-hosted Photon OS docs site and detect 12+ issue types via a plugin system (grammar, spelling, broken links, orphan pages, heading hierarchy, markdown artifacts, unaligned images) | Critical |
| REQ-4 | Auto-fix detected documentation issues and create GitHub PRs for changes | High |
| REQ-5 | Factory AI swarm orchestration with 5 teams (Maintenance, Sandbox, Translator, Blogger, Security) and 25 droids for continuous doc processing | High |
| REQ-6 | Multi-language translation pipeline for 6 languages (German, French, Italian, Bulgarian, Hindi, Chinese) across 4 Photon OS versions | Medium |
| REQ-7 | MITRE ATLAS security compliance monitoring across all swarm teams | Medium |
| REQ-8 | vCenter release coverage tracking: correlate Photon advisory wiki pages with Broadcom KB 326316 to identify releases missing from drift analysis | High |
| REQ-9 | Hugo frontmatter validation via PostToolUse hooks for all generated blog content | High |
| REQ-10 | Migration tooling for converting Hugo site to Docusaurus or MkDocs | Low |

## Success Criteria

| ID | Criterion |
|----|-----------|
| SC-1 | All 6 branches imported with commits since 2021-01-01 |
| SC-2 | Blog posts generated for every branch/month with non-zero commits |
| SC-3 | Docs-lecturer detects all 12 issue types with >95% grammar compliance |
| SC-4 | Swarm quality gates pass: 0 critical issues, ≤1 high, ≤5 medium |
| SC-5 | Release coverage report identifies all 40+ vCenter releases from KB 326316 |
| SC-6 | All generated Hugo posts pass frontmatter validation |

## Scope Exclusions

- Direct modification of the vmware/photon repository
- vCenter CVE drift analysis (handled by vCenter-CVE-drift-analyzer)
- ESXi release tracking (vCenter releases only)
- Automated production deployment of Hugo site

## Traceability Matrix

| REQ | Feature (FRD) | ADR | Task | Agent | Prompt |
|-----|---------------|-----|------|-------|--------|
| REQ-1 | commit-import-pipeline | ADR-0001 | 002, 003 | commit-analyst | -- |
| REQ-2 | blog-generation-pipeline | ADR-0002 | 004 | blog-generator | generate-blog-posts |
| REQ-3, REQ-4 | docs-quality-analysis | ADR-0003 | 005 | docs-quality-checker | analyze-docs-quality |
| REQ-5 | swarm-orchestration | -- | 007 | docsystem-orchestrator | -- |
| REQ-6, REQ-7 | translation-and-security | -- | 007 | docsystem-orchestrator | -- |
| REQ-8 | vcenter-release-coverage | ADR-0004 | 006 | release-coverage-tracker | track-release-coverage |
| REQ-9 | blog-generation-pipeline | -- | 004 | blog-generator | generate-blog-posts |
| REQ-10 | -- | -- | -- | -- | -- |
| -- | -- | -- | 001 | -- | -- |
| -- | -- | -- | 008 | -- | generate-agents |
