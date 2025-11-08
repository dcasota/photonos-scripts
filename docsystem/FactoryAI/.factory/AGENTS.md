---
name: DocsLecturerSwarm
description: Comprehensive documentation processing swarm for Photon OS with multi-droid coordination
version: 1.0.0
updated: 2025-11-08T23:30:00Z
model: glm-4.6
auto_levels: [low, medium, high]
---

# Docs Lecturer Swarm Configuration

The Docs Lecturer Swarm is a sophisticated multi-droid system for comprehensive documentation processing, crawling, quality assessment, and modernization of Photon OS documentation.

## Core Droids

### 🕷️ DocsLecturerCrawler
- **Purpose**: Recursive website crawling and content extraction
- **Tools**: http_get, http_head, write_file, list_files, view_image
- **Features**: Unlimited depth crawling, sitemap.xml processing, localhost support
- **Auto-level Support**: Low (3 depth/50 pages), Medium (5 depth/200 pages), High (unlimited)

### 🔍 DocsLecturerAuditor
- **Purpose**: Content quality assessment and issue identification
- **Tools**: grammar_check, read_file, write_file
- **Features**: Flesch score analysis, grammar compliance checking, issue categorization
- **Auto-level Support**: Variable thresholds (40/50/60), comprehensive analysis

### 🛡️ DocsLecturerSecurity
- **Purpose**: MITRE ATLAS compliance and security monitoring
- **Tools**: security_scan, threat_analysis
- **Features**: Basic/standard/full security levels, continuous monitoring

### ✏️ DocsLecturerEditor
- **Purpose**: Content editing and issue resolution
- **Tools**: write_file, edit_file, format_markdown
- **Features**: Automated content fixes, quality improvements

### 🤖 DocsLecturerPRBot
- **Purpose**: Pull request creation and management
- **Tools**: git_branch, git_commit, github_create_pr, github_list_prs
- **Features**: Manual/semi-automated/fully-automated PR workflows

### 🗃️ DocsLecturerSandbox
- **Purpose**: Code block conversion to interactive runtime
- **Tools**: sandbox_runtime, code_conversion
- **Features**: Major blocks only (low), all blocks (medium), + interactive (high)

### 📝 DocsLecturerBlogger
- **Purpose**: Blog content generation from processed documentation
- **Tools**: content_generation, markdown_export
- **Features**: Automated blog post creation

### 💬 DocsLecturerChatbot
- **Purpose**: Knowledge base population for interactive assistance
- **Tools**: knowledge_indexing, content_structuring
- **Features**: Complete content indexing for chatbot integration

### 🌐 DocsLecturerTranslator
- **Purpose**: Multi-language content preparation
- **Tools**: content_structuring, translation_prep
- **Features**: Content structured for translation workflows

### 🧪 DocsLecturerTester
- **Purpose**: Regression testing and verification
- **Tools**: test_runner, verification_checks
- **Features**: 100% regression test pass rate requirement

### 📊 DocsLecturerLogger
- **Purpose**: Session logging and progress tracking
- **Tools**: log_export, session_tracking
- **Features**: Re-playable logs with goal completion tracking

## 🎯 Swarm Orchestrator

### DocsLecturerOrchestrator
- **Purpose**: Coordinates entire swarm operation with goal-based processing
- **Tools**: delegate_to_droid, git_branch, git_commit, github_create_pr, github_list_prs, read_file
- **Features**: 
  - Auto-level configuration awareness
  - Structured goal processing (10 goals matrix)
  - Quality gates monitoring (85% min success rate)
  - Progressive enhancement based on auto-level
  - MITRE ATLAS compliance tracking

## 🔄 Operational Modes

### Onboarding Mode
- Goal 1: Complete site discovery (100% sitemap coverage, 0 broken links)
- Goal 2: Content quality assessment (Flesch compliance, >95% grammar pass rate)
- Goal 3: Issue identification and categorization

### Modernizing Mode  
- Goal 4: Code block modernization (100% sandbox conversion)
- Goal 5: Interactive element integration

### Releasemanagement Mode
- Goal 6: PR consolidation and approval workflows
- Goal 7: Automated testing verification

### Integration Phase
- Goal 8: Chatbot knowledge base population
- Goal 9: Blog content generation (5+ posts)
- Goal 10: Multi-language preparation

## 📈 Quality Gates

- Minimum success rate: 85%
- Maximum critical issues: 0
- Maximum high priority issues: 5
- Maximum medium priority issues: 20
- MITRE ATLAS compliance monitoring
