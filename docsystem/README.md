# Photon OS Documentation System (docsystem)

## Overview

The docsystem directory contains comprehensive tools and automation for managing, improving, and publishing Photon OS documentation. It includes installers for documentation platforms, quality assessment tools, migration utilities, and a complete multi-team AI-powered documentation swarm system.

## Quick Start

### Setup Environment

```bash
cd $HOME
tdnf install -y git
git clone https://github.com/dcasota/photonos-scripts
cd $HOME/photonos-scripts/docsystem
find . -type f -name "*.sh" -exec sudo chmod +x {} \;
```

### Basic Installation

```bash
# Install Photon OS documentation site (Hugo-based)
./tools/installer-for-self-hosted-Photon-OS-documentation/installer.sh

# option: Install Ollama with LLM models
./Ollama-installer/Ollama-installer.sh

# option: Install AI coding assistants
./CodingAI-installers/CodingAI-installers.sh

# Configure Factory AI Droid
./Droid-configurator.sh
```

## Directory Structure

```
docsystem/
├── tools/                           # Documentation tools and utilities
│   ├── Ollama-installer/           # LLM server installation
│   ├── CodingAI-installers/        # AI coding assistants
│   ├── installer-for-self-hosted-Photon-OS-documentation/
│   │   └── installer.sh            # Hugo-based documentation site installer
│   ├── Migrate2Docusaurus/         # Docusaurus migration tools
│   ├── Migrate2MkDocs/             # MkDocs migration tools
│   ├── mirror-repository/          # GitHub repository mirroring
│   ├── weblinkchecker/             # Website link validation
│   ├── configuresound/             # Audio stack installation
│   └── photonos-docs-lecturer/     # Documentation quality analysis
│       ├── photonos-docs-lecturer.py  # Main analysis tool
│       └── plugins/                # Modular detection/fix plugins
├── .factory/                        # Factory AI Droid configuration
│   ├── AGENTS.md                   # Swarm configuration
│   ├── teams/                      # Documentation team droids
│   │   ├── docs-maintenance/       # Quality & content fixes
│   │   ├── docs-sandbox/           # Code block modernization
│   │   ├── docs-translator/        # Multi-language translation
│   │   ├── docs-blogger/           # Automated blog generation
│   │   └── docs-security/          # MITRE ATLAS compliance
│   └── README.md                   # Factory system setup
├── Droid-configurator.sh           # Factory AI Droid setup script
└── README.md                       # This file
```

## Tools Overview

### Documentation Site Installers

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **installer.sh** | Hugo-based documentation site | Self-hosted, HTTPS, comprehensive link fixes |
| **Migrate2Docusaurus** | Docusaurus 3.9.2 migration | Version management, modern UI, blog support |
| **Migrate2MkDocs** | MkDocs Material migration | Multi-version, responsive design, search |

### Quality & Analysis Tools

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **photonos-docs-lecturer** | Documentation quality analysis | Grammar/spelling, markdown validation, automated fixes |
| **weblinkchecker** | Link validation | Recursive crawling, broken link detection, redirect analysis |

### LLM & AI Tools

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **Ollama-installer** | Local LLM server | Context-aware models, OpenAI-compatible API |
| **CodingAI-installers** | AI coding assistants | Factory Droid, Copilot, Claude, Gemini, Grok |

### Infrastructure Tools

| Tool | Purpose | Key Features |
|------|---------|--------------|
| **mirror-repository** | GitHub repository mirroring | Full history, LFS support, auto-sync |
| **configuresound** | Audio stack setup | TTS engines, audio codecs, speech synthesis |

## Documentation Lecturer Plugin System

Version 3.0 introduces a modular plugin architecture for documentation analysis:

### Automatic Fix Plugins

| Plugin | FIX_ID | Description | LLM Required |
|--------|--------|-------------|:------------:|
| broken_email | 1 | Fix broken email addresses | No |
| deprecated_url | 2 | Fix deprecated URLs (VMware, AWS, etc.) | No |
| hardcoded_replaces | 3 | Fix known typos and errors | No |
| heading_hierarchy | 4 | Fix heading hierarchy violations | No |
| header_spacing | 5 | Fix markdown headers missing space | No |
| html_comments | 6 | Fix HTML comments | No |
| vmware_spelling | 7 | Fix VMware spelling | No |
| backticks | 8 | Fix backtick issues | Yes |
| grammar | 9 | Fix grammar and spelling | Yes |
| markdown_artifacts | 10 | Fix unrendered markdown | Yes |
| indentation | 11 | Fix indentation issues | Yes |
| numbered_lists | 12 | Fix numbered list sequences | No |

### Detection-Only Plugins

- **orphan_link** - Broken hyperlinks
- **orphan_image** - Missing images
- **orphan_page** - Unreferenced pages
- **image_alignment** - Image positioning issues

### Usage Examples

```bash
# Analyze documentation (report only)
python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5 \
  --parallel 10

# Full workflow with automated fixes and PR
python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-repotoken ghp_xxxxxxxxx \
  --gh-username myuser \
  --ghrepo-url https://github.com/myuser/photon.git \
  --ghrepo-branch photon-hugo \
  --gh-pr \
  --parallel 10

# Selective fixes (non-LLM only)
python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 1-7,12
```

## Factory AI Droid Swarm System

A five-team documentation system for comprehensive Photon OS documentation processing:

### Team Structure

1. **Docs Maintenance** - Content quality, grammar, links, orphaned pages
   - crawler, auditor, editor, pr-bot, logger

2. **Docs Sandbox** - Code block modernization and interactive runtime
   - crawler, converter, tester, pr-bot, logger

3. **Docs Translator** - Multi-language support (6 languages × 4 versions)
   - translator-german, translator-french, translator-italian, translator-bulgarian, translator-hindi, translator-chinese, chatbot

4. **Docs Blogger** - Automated blog generation from git history
   - blogger, pr-bot

5. **Docs Security** - MITRE ATLAS compliance and security monitoring
   - monitor, atlas-compliance, threat-analyzer, audit-logger

### Execution Flow

```
MASTER ORCHESTRATOR
   ↓
Security Team (continuous monitoring) ←─┐
   ↓                                     │
Maintenance Team → Quality Gates ───────┤
   ↓                                     │
Sandbox Team → Quality Gates ────────────┤
   ↓                                     │
Blogger Team → Quality Gates ────────────┤
   ↓                                     │
Translator Team → Final Validation ──────┘
   ↓
COMPLETE
```

### Running the Swarm

```bash
# Full swarm execution
cd $HOME/photonos-scripts/docsystem/.factory
droid /run-docs-lecturer-swarm

# Individual teams
factory run @docs-maintenance-orchestrator
factory run @docs-sandbox-orchestrator
factory run @docs-translator-orchestrator
factory run @docs-blogger-orchestrator
factory run @docs-security-orchestrator
```

## Environment Variables

Required for GitHub integration:

```bash
export GITHUB_TOKEN="ghp_xxxxxxxxxxxxxxxxxxxx"
export GITHUB_USERNAME="your-github-username"
export PHOTON_FORK_REPOSITORY="https://github.com/your-username/photon.git"
```

## Access URLs

After installation:

| Service | URL | Credentials |
|---------|-----|-------------|
| Hugo Documentation | `https://<IP_ADDRESS>/` | None (self-signed cert) |
| Docusaurus Site | `https://<IP_ADDRESS>:8443/` | None (self-signed cert) |
| MkDocs Site | `https://<IP_ADDRESS>:8443/` | None (self-signed cert) |
| Ollama API | `http://localhost:11434` | None |
| n8n Workflow | `http://localhost:5678` | None |

## Log Files

| Component | Log Location |
|-----------|-------------|
| Hugo Site | `/var/log/installer.log` |
| Documentation Lecturer | `report-<datetime>.log` |
| Nginx | `/var/log/nginx/error.log` |
| Factory Droid | `.factory/logs/` |

## Quality Gates

### Maintenance Team
- ✅ Critical issues: 0
- ✅ Grammar: >95%
- ✅ Markdown: 100%
- ✅ Accessibility: WCAG AA
- ✅ Orphaned pages: 0

### Sandbox Team
- ✅ Conversion: 100% eligible blocks
- ✅ Functionality: All sandboxes working
- ✅ Security: Isolated execution

### Translator Team
- ✅ Translation: 100% coverage
- ✅ Knowledge base: Complete

### Blogger Team
- ✅ Blog posts: Monthly coverage complete
- ✅ Technical accuracy: All references verified

### Security Team
- ✅ MITRE ATLAS compliance: 100%
- ✅ Critical security issues: 0
- ✅ Isolation violations: 0

## Support & Documentation

For detailed documentation on each tool, see:

- Hugo Site Installation: `tools/installer-for-self-hosted-Photon-OS-documentation/README.md`
- Documentation Lecturer: `tools/photonos-docs-lecturer/README.md`
- Plugin System: `tools/photonos-docs-lecturer/plugins/README.md`
- Factory Swarm: `.factory/teams/README.md`
- Individual Teams: `.factory/teams/*/README.md`


