---
name: DocsLecturerSwarm
description: Comprehensive documentation processing swarm for Photon OS with four-team coordination
version: 2.0.0
updated: 2025-11-09T20:15:00Z
model: claude-sonnet-4.5
auto_levels: [low, medium, high]
---

# Docs Lecturer Swarm Configuration

The Docs Lecturer Swarm is a four-team documentation system for comprehensive Photon OS documentation processing, quality assessment, modernization, and publication.

## Four-Team Structure

### 🛠️ Team 1: Docs Maintenance
**Location**: `teams/docs-maintenance/`
**Purpose**: Content quality, grammar, broken links, orphaned pages

**Droids** (5):
- **crawler** - Site discovery and link validation (unlimited depth)
- **auditor** - Quality assessment (Flesch score, grammar compliance)
- **editor** - Automated content fixes and improvements
- **pr-bot** - Pull request creation and management
- **logger** - Session logging and progress tracking

**Orchestrator**: `docs-maintenance/orchestrator.md`

### 🧪 Team 2: Docs Sandbox
**Location**: `teams/docs-sandbox/`
**Purpose**: Code block modernization and interactive runtime

**Droids** (5):
- **crawler** - Site discovery and code block identification
- **converter** - Code block to sandbox conversion
- **tester** - Sandbox functionality testing and verification
- **pr-bot** - Pull request creation and management
- **logger** - Session logging and progress tracking

**Orchestrator**: `docs-sandbox/orchestrator.md`

### 🌐 Team 3: Docs Translator
**Location**: `teams/docs-translator/`
**Purpose**: Multi-language translation (executes LAST after all other teams)

**Droids** (7):
- **translator-german** - German translation (versions 3.0, 4.0, 5.0, 6.0)
- **translator-french** - French translation (versions 3.0, 4.0, 5.0, 6.0)
- **translator-italian** - Italian translation (versions 3.0, 4.0, 5.0, 6.0)
- **translator-bulgarian** - Bulgarian translation (versions 3.0, 4.0, 5.0, 6.0)
- **translator-hindi** - Hindi translation (versions 3.0, 4.0, 5.0, 6.0)
- **translator-chinese** - Simplified Chinese translation (versions 3.0, 4.0, 5.0, 6.0)
- **chatbot** - Multilingual knowledge base population

**Orchestrator**: `docs-translator/orchestrator.md`

### 📝 Team 4: Docs Blogger
**Location**: `teams/docs-blogger/`
**Purpose**: Automated blog generation from repository analysis

**Droids** (3):
- **blogger** - Monthly blog generation from git commit history
- **pr-bot** - Pull request management for blog content
- **orchestrator** - Team coordinator

**Orchestrator**: `docs-blogger/orchestrator.md`

### 🛡️ Team 5: Docs Security
**Location**: `teams/docs-security/`
**Purpose**: Centralized MITRE ATLAS compliance and security monitoring

**Droids** (5):
- **monitor** - Real-time monitoring of all team activities
- **atlas-compliance** - MITRE ATLAS framework compliance validation
- **threat-analyzer** - Security threat detection and analysis
- **audit-logger** - Comprehensive security audit logging
- **orchestrator** - Security team coordinator

**Orchestrator**: `docs-security/orchestrator.md`
**Execution Mode**: Continuous parallel monitoring of all teams

## 🎯 Master Orchestrator

### DocsSwarmMasterOrchestrator
**Location**: `teams/MASTER-ORCHESTRATOR.md`
**Purpose**: Coordinates all four teams with goal-based processing

**Features**: 
  - Auto-level configuration awareness
  - Structured goal processing (10 goals matrix)
  - Quality gates monitoring between teams
  - Sequential team execution (Maintenance → Sandbox → Translator → Blogger)
  - MITRE ATLAS compliance tracking

## 🔄 Execution Flow

### Parallel Security + Sequential Team Processing
```
Master Orchestrator Starts
  ↓
┌─────────────────────────────────┐
│ Team 5: Security (CONTINUOUS)   │ ← Monitors all teams
│ - Real-time monitoring          │
│ - MITRE ATLAS compliance        │
│ - Threat analysis               │
│ - Audit logging                 │
└─────────────────────────────────┘
  ↓ (Parallel monitoring of:)
  ↓
Team 1: Maintenance (Quality Foundation)
  - Site discovery and crawling
  - Quality assessment and auditing
  - Content fixes and editing
  - PR creation
  - Continuous: logging
  ↓ [Quality Gates + Security Check]
  ↓
Team 2: Sandbox (Modernization)
  - Site discovery for code blocks
  - Code block conversion
  - Sandbox testing
  - PR creation
  - Continuous: logging
  ↓ [Quality Gates + Security Check]
  ↓
Team 4: Blogger (Publication)
  - Monthly blog generation
  - PR creation for blog content
  ↓ [Quality Gates + Security Check]
  ↓
Team 3: Translator (Globalization) - EXECUTES LAST
  - 6 parallel language translations (all versions)
  - Multilingual chatbot knowledge base
  - Hugo multilang integration
  - PR creation
  ↓ [Final Validation + Security Certification]
  ↓
Complete
```

## 📊 Goals Coverage by Team

**Team 1 (Maintenance)**: Goals 1, 2, 3, 6
- Goal 1: Site discovery (100% coverage, 0 broken links)
- Goal 2: Quality assessment (>95% grammar pass rate)
- Goal 3: Issue identification and categorization
- Goal 6: PR consolidation and approval

**Team 2 (Sandbox)**: Goals 4, 5, 7
- Goal 4: Code modernization (100% sandbox conversion)
- Goal 5: Interactive element integration
- Goal 7: Automated testing verification

**Team 3 (Translator)**: Goals 8, 10 - EXECUTES LAST
- Goal 8: Chatbot multilingual knowledge base population
- Goal 10: Multi-language translation (6 languages × 4 versions)

**Team 4 (Blogger)**: Goal 9
- Goal 9: Monthly blog generation (6 branches × months since 2021)

**Team 5 (Security)**: Continuous Monitoring - RUNS IN PARALLEL WITH ALL TEAMS
- Monitors all teams for MITRE ATLAS compliance
- Real-time threat detection and analysis
- Comprehensive security audit logging
- Ensures all goals meet security requirements

## 📈 Quality Gates

- Minimum success rate: 95%
- Maximum critical issues: 0
- Maximum high priority issues: 1
- Maximum medium priority issues: 5
- MITRE ATLAS compliance monitoring
