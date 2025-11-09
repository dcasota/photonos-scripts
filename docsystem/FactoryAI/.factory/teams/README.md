# Simplified Three-Team Documentation System

This directory contains a simplified reorganization of the Docs Lecturer Swarm into three focused teams.

## Why This Reorganization?

The original swarm had 15+ interconnected droids with complex dependencies. This simplified structure provides:
- **Clear separation of concerns**
- **Easier maintenance and updates**
- **Better team coordination**
- **Simplified execution flow**

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
- `blogger.md` - Blog content generation
- `chatbot.md` - Knowledge base population

**Orchestrator**: `orchestrator.md`

## Master Orchestrator

**File**: `MASTER-ORCHESTRATOR.md`

Coordinates all three teams in sequence:
1. Maintenance (quality foundation)
2. Sandbox (modernization)
3. Translator (globalization)

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
   translate → blog → chatbot → PR
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
factory run @docs-translator-blogger
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
- ✅ Blog posts: ≥5
- ✅ Knowledge base: Complete

## Auto-Level Configuration

Configure in `auto-config.json`:

- **HIGH**: Full automation, auto-merge PRs
- **MEDIUM**: Auto-fixes, manual PR merge
- **LOW**: Manual approval at checkpoints

## Migration from Original Structure

Original complex droids have been:
1. **Simplified**: Removed redundant complexity
2. **Reorganized**: Grouped by team function
3. **Streamlined**: Clear responsibilities per droid
4. **Documented**: Each team has README and orchestrator

## Key Improvements

✅ **Reduced Complexity**: From 15+ droids to 11 focused droids
✅ **Clear Workflow**: Linear team progression
✅ **Better Separation**: Each team has clear domain
✅ **Easier Debugging**: Isolated team failures
✅ **Maintainable**: Simple to update individual teams
✅ **Scalable**: Easy to add new droids to existing teams

## Target Repository

- **Repository**: https://github.com/dcasota/photon
- **Branch**: photon-hugo
- **All teams create PRs to this repository**

## Original Goals Coverage

This simplified structure covers all 10 original swarm goals:

**Maintenance Team**: Goals 1, 2, 3, 6, 7
**Sandbox Team**: Goals 4, 5
**Translator Team**: Goals 8, 9, 10

## Support

For questions or issues:
1. Check individual team README files
2. Review orchestrator documentation
3. Check logs in respective team directories
4. Consult master-log.json for full audit trail
