# Four-Team Documentation System

This directory contains the organized Docs Lecturer Swarm with four specialized teams for comprehensive Photon OS documentation processing.

## System Overview

This four-team structure provides:
- **Clear separation of concerns**
- **Specialized team responsibilities**
- **Easier maintenance and updates**
- **Better team coordination**
- **Scalable architecture**

## Team Structure

### 🛠️ Team 1: Docs Maintenance
**Directory**: `docs-maintenance/`
**Focus**: Content quality, grammar, links, orphaned pages, security

**Members**:
- `crawler.md` - Site discovery and link validation
- `auditor.md` - Quality assessment
- `editor.md` - Automated fixes
- `pr-bot.md` - PR management
- `logger.md` - Progress tracking
- `security.md` - Security compliance

**Orchestrator**: `orchestrator.md`

### 🧪 Team 2: Docs Sandbox
**Directory**: `docs-sandbox/`
**Focus**: Code block modernization and interactive runtime

**Members**:
- `converter.md` - Convert code blocks to sandboxes
- `tester.md` - Test sandbox functionality

**Orchestrator**: `orchestrator.md`

### 🌐 Team 3: Docs Translator
**Directory**: `docs-translator/`
**Focus**: Multi-language support and content integration

**Members**:
- `translator.md` - Multi-language translation
- `chatbot.md` - Knowledge base population

**Orchestrator**: `orchestrator.md`

### 📝 Team 4: Docs Blogger
**Directory**: `docs-blogger/`
**Focus**: Automated blog generation from repository analysis

**Members**:
- `blogger.md` - Monthly blog generation from git history
- `pr-bot.md` - Pull request management for blog content

**Orchestrator**: `orchestrator.md`

## Master Orchestrator

**File**: `MASTER-ORCHESTRATOR.md`

Coordinates all four teams in sequence:
1. Maintenance (quality foundation)
2. Sandbox (modernization)
3. Translator (globalization)
4. Blogger (publication)

## Execution Flow

```
MASTER ORCHESTRATOR
        ↓
   [Setup & Validation]
        ↓
TEAM 1: Docs Maintenance
   crawl → audit → edit → PR
        ↓
   [Quality Gates Check]
        ↓
TEAM 2: Docs Sandbox
   convert → test → PR
        ↓
   [Quality Gates Check]
        ↓
TEAM 3: Docs Translator
   translate → chatbot → PR
        ↓
   [Quality Gates Check]
        ↓
TEAM 4: Docs Blogger
   blogger → pr-bot → publication
        ↓
   [Final Validation]
        ↓
     COMPLETE
```

## Quick Start

### Run All Teams (Recommended)
```bash
factory run @DocsSwarmMasterOrchestrator
```

### Run Individual Teams
```bash
# Maintenance only
factory run @docs-maintenance-orchestrator

# Sandbox only
factory run @docs-sandbox-orchestrator

# Translator only
factory run @docs-translator-orchestrator

# Blogger only
factory run @docs-blogger-orchestrator
```

### Run Individual Droids
```bash
# Within maintenance team
factory run @docs-maintenance-crawler
factory run @docs-maintenance-auditor
factory run @docs-maintenance-editor

# Within sandbox team
factory run @docs-sandbox-converter
factory run @docs-sandbox-tester

# Within translator team
factory run @docs-translator-translator
factory run @docs-translator-chatbot

# Within blogger team
factory run @docs-blogger-blogger
factory run @docs-blogger-pr-bot
```

## Quality Gates

### Team 1 (Maintenance) Gates
- ✅ Critical issues: 0
- ✅ Grammar: >95%
- ✅ Markdown: 100%
- ✅ Accessibility: WCAG AA
- ✅ Orphaned pages: 0

### Team 2 (Sandbox) Gates
- ✅ Conversion: 100% eligible blocks
- ✅ Functionality: All sandboxes working
- ✅ Security: Isolated execution

### Team 3 (Translator) Gates
- ✅ Translation: 100% coverage
- ✅ Knowledge base: Complete

### Team 4 (Blogger) Gates
- ✅ Blog posts: Monthly coverage complete
- ✅ Technical accuracy: All references verified
- ✅ Hugo integration: Build successful

## Auto-Level Configuration

Configure in `auto-config.json`:

- **HIGH**: Full automation, auto-merge PRs
- **MEDIUM**: Auto-fixes, manual PR merge
- **LOW**: Manual approval at checkpoints

## Key Features

✅ **Organized Structure**: 4 teams with clear responsibilities
✅ **12 Focused Droids**: Specialized for specific tasks
✅ **Clear Workflow**: Linear team progression
✅ **Better Separation**: Each team has clear domain
✅ **Easier Debugging**: Isolated team failures
✅ **Maintainable**: Simple to update individual teams
✅ **Scalable**: Easy to add new droids or teams

## Target Repository

- **Repository**: https://github.com/dcasota/photon
- **Branch**: photon-hugo
- **All teams create PRs to this repository**

## Goals Coverage

This four-team structure covers all 10 swarm goals:

**Maintenance Team**: Goals 1, 2, 3, 6
**Sandbox Team**: Goals 4, 5, 7
**Translator Team**: Goals 8, 10
**Blogger Team**: Goal 9

## Support

For questions or issues:
1. Check individual team README files
2. Review orchestrator documentation
3. Check logs in respective team directories
4. Consult master-log.json for full audit trail
