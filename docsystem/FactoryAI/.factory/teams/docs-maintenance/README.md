# Docs Maintenance Team

**Purpose**: Content quality, grammar, broken links, orphaned pages, SEO, accessibility, and security compliance.

## Team Members

### Core Droids
1. **crawler** - Site discovery, link validation, orphaned page detection
2. **auditor** - Content quality assessment, grammar, markdown validation
3. **editor** - Automated content fixes and issue resolution
4. **pr-bot** - Pull request creation and management
5. **logger** - Session tracking and progress logging
6. **security** - MITRE ATLAS compliance and security monitoring

## Workflow

```
crawler → auditor → editor → pr-bot
           ↓
        logger (continuous)
        security (continuous)
```

## Key Responsibilities

- **Site Discovery**: Crawl production and localhost sites
- **Orphaned Page Detection**: Identify missing/broken pages
- **Quality Assessment**: Grammar, spelling, markdown validation
- **Link Validation**: Test all internal/external links
- **Automated Fixes**: Grammar, markdown, accessibility improvements
- **PR Management**: Create and manage documentation PRs
- **Security Monitoring**: MITRE ATLAS compliance checking

## Quality Gates

- Critical Issues: 0 (zero tolerance)
- Grammar Compliance: >95%
- Markdown Syntax: 100%
- Accessibility: WCAG AA compliance
- Link Validation: 100% working internal links

## Usage

Trigger the maintenance team orchestrator:
```bash
factory run @docs-maintenance-orchestrator
```

Or individual droids:
```bash
factory run @docs-maintenance-crawler
factory run @docs-maintenance-auditor
factory run @docs-maintenance-editor
```
