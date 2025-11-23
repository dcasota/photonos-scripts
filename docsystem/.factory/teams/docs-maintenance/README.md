# Docs Maintenance Team

**Purpose**: Content quality, grammar, broken links, orphaned pages, SEO, accessibility, and security compliance.

**📋 DETAILED PLAN**: See [`PLAN-SPECIFICATION.md`](./PLAN-SPECIFICATION.md) for the comprehensive reengineered workflow with quality metrics, validation criteria, and reproducible execution procedures.

## Team Members

### Core Droids
1. **crawler** - Site discovery, link validation, orphaned page detection
2. **auditor** - Content quality assessment, grammar, markdown validation
3. **editor** - Automated content fixes and issue resolution
4. **pr-bot** - Pull request creation and management
5. **logger** - Session tracking and progress logging

## Workflow

```
crawler → auditor → editor → pr-bot
           ↓
        logger (continuous)
        
[Security monitoring by Team 5: Docs Security]
```

## Key Responsibilities

- **Site Discovery**: Crawl production and localhost sites
- **Orphaned Page Detection**: Identify missing/broken pages
- **Quality Assessment**: Grammar, spelling, markdown validation
- **Link Validation**: Test all internal/external links
- **Automated Fixes**: Grammar, markdown, accessibility improvements
- **PR Management**: Create and manage documentation PRs
- **Branding Compliance**: Ensure Broadcom integration alongside VMware branding (logo, community links, footer text)

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

## Branding Requirements (DO NOT REMOVE)

### Required Broadcom Integration
The following Broadcom elements are **mandatory features** (like the console window):

1. **Broadcom Logo in Footer**
   - File: `/var/www/photon-site/static/img/broadcom-logo.png`
   - Must appear alongside VMware logo in footer
   - Configured by `installer-weblinkfixes.sh` (Fix 46)

2. **Broadcom Community Link**
   - Must be in footer community links section
   - URL: `https://community.broadcom.com/`
   - Configured in `config.toml` (Fix 27)

3. **Footer Branding Text**
   - Must read: "A VMware By Broadcom Backed Project"
   - Location: `themes/photon-theme/i18n/en.toml`
   - Configured by `installer-weblinkfixes.sh` (Fix 47)

4. **Package Repository URLs**
   - Console container uses `packages-prod.broadcom.com`
   - Required for Docker-based console feature
   - Location: `installer-consolebackend.sh`

### Console Window Feature
- Terminal icon in main navigation menu
- Full WebSocket + Docker + tmux backend
- Implemented by `installer-consolebackend.sh`
- **Must be preserved** during all maintenance operations

### Reference Implementation
- VMware logo: Points to `https://vmware.github.io`
- Broadcom logo: Points to `https://www.broadcom.com`
- Both logos displayed side-by-side in footer
- Both branding elements coexist without conflicts

## Security Monitoring

This team is monitored by **Team 5: Docs Security** for:
- MITRE ATLAS compliance
- Content security validation
- Link safety verification
- Unauthorized access prevention
- Branding compliance verification
