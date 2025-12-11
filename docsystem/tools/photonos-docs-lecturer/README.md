# photonos-docs-lecturer.py User Manual

## Overview

`photonos-docs-lecturer.py` is a comprehensive documentation analysis and remediation tool for Photon OS documentation. It crawls documentation served by an Nginx webserver, identifies various issues (grammar, spelling, markdown artifacts, broken links/images, formatting problems, heading hierarchy violations), generates CSV reports, and optionally applies automated fixes via git push and GitHub pull requests.

### Version 3.0 - Plugin Architecture

Version 3.0 introduces a complete refactoring into a **modular plugin architecture**:

- **84% code reduction**: Main file reduced from 8,172 lines to 1,296 lines
- **18 plugin modules**: Each detection/fix category is now a separate plugin
- **Thread-safe logging**: Each plugin logs to `/var/log/photonos-docs-lecturer-<plugin>.log`
- **Individual versioning**: Each plugin has its own version for independent updates
- **Full backward compatibility**: All existing CLI options work unchanged

### Project Goal

This tool was developed to address [GitHub Issue #22](https://github.com/dcasota/photonos-scripts/issues/22):

> Develop a command-line Python tool that crawls a Photon OS-hosted Nginx webserver serving documentation pages, identifies issues (grammar/spelling errors, Markdown rendering artifacts, orphan/broken links, orphan/broken images, unaligned multiple images), generates a CSV report, and optionally applies fixes via git push and GitHub pull request.

---

## Architecture

### Directory Structure

```
photonos-docs-lecturer/
├── photonos-docs-lecturer.py    # Main entry point (1,296 lines)
├── README.md                     # This file
└── plugins/                      # Plugin modules
    ├── __init__.py              # Package initialization
    ├── base.py                  # Base classes (BasePlugin, Issue, FixResult)
    ├── manager.py               # PluginManager for coordination
    ├── integration.py           # Backward compatibility layer
    ├── grammar.py               # Grammar checking (FIX_ID 9)
    ├── markdown.py              # Markdown artifacts (FIX_ID 10, 12)
    ├── heading_hierarchy.py     # Heading hierarchy (FIX_ID 6)
    ├── formatting.py            # Backtick spacing (FIX_ID 4)
    ├── backtick_errors.py       # Spaces inside backticks (FIX_ID 5)
    ├── indentation.py           # Indentation issues (FIX_ID 11)
    ├── deprecated_url.py        # Deprecated URLs (FIX_ID 3)
    ├── spelling.py              # VMware spelling, emails, comments (FIX_ID 1,2,8)
    ├── orphan_page.py           # Orphan page detection
    ├── orphan_link.py           # Orphan link detection
    ├── orphan_image.py          # Orphan image detection
    ├── image_alignment.py       # Image alignment detection
    ├── shell_prompt.py          # Shell prompt removal (FEATURE_ID 1)
    ├── mixed_command_output.py  # Mixed cmd/output (FEATURE_ID 2)
    ├── README-grammar.md        # Plugin documentation
    ├── README-markdown.md
    ├── README-heading_hierarchy.md
    ├── README-formatting.md
    ├── README-backtick_errors.md
    ├── README-indentation.md
    ├── README-deprecated_url.md
    ├── README-spelling.md
    ├── README-orphan_page.md
    ├── README-orphan_link.md
    ├── README-orphan_image.md
    ├── README-image_alignment.md
    ├── README-shell_prompt.md
    └── README-mixed_command_output.md
```

### Plugin System

Each plugin inherits from base classes in `plugins/base.py`:

- **BasePlugin**: Abstract base for all plugins
- **PatternBasedPlugin**: For regex-based detection/fixing
- **LLMAssistedPlugin**: For plugins requiring LLM integration

The **PluginManager** (`plugins/manager.py`) handles:
- Plugin discovery and loading
- Coordination of detection and fixing
- Thread-safe parallel execution
- Statistics collection

---

## Installation

### Prerequisites

- Python 3.8+
- Java >= 17 (required for grammar checking via LanguageTool)

### Install Dependencies

```bash
# Install required tools (Java and Python packages)
sudo python3 photonos-docs-lecturer.py install-tools
```

This installs:
- Java runtime (openjdk21)
- Python packages: requests, beautifulsoup4, lxml, language-tool-python, tqdm, Pillow
- LLM support: google-generativeai (for Gemini-based fixes)

---

## Usage

### Commands

```bash
python3 photonos-docs-lecturer.py <command> [options]
```

| Command | Description |
|---------|-------------|
| `run` | Full workflow: analyze, generate fixes, push changes, create PR |
| `analyze` | Generate report only (no fixes, git operations, or PR) |
| `test` | Run unit tests for the tool |
| `install-tools` | Install Java and required Python packages (requires admin/sudo) |
| `version` | Display tool version |

### Basic Examples

```bash
# Run unit tests
python3 photonos-docs-lecturer.py test

# Analyze documentation (report only)
python3 photonos-docs-lecturer.py analyze \
  --website https://127.0.0.1/docs-v5 \
  --parallel 10

# Full workflow with PR creation
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-repotoken ghp_xxxxxxxxx \
  --gh-username myuser \
  --ghrepo-url https://github.com/myuser/photon.git \
  --ghrepo-branch photon-hugo \
  --ref-ghrepo https://github.com/vmware/photon.git \
  --ref-ghbranch photon-hugo \
  --parallel 10 \
  --gh-pr

# Full workflow with LLM-assisted fixes (Gemini)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-repotoken ghp_xxxxxxxxx \
  --gh-username myuser \
  --ghrepo-url https://github.com/myuser/photon.git \
  --ghrepo-branch photon-hugo \
  --ref-ghrepo https://github.com/vmware/photon.git \
  --ref-ghbranch photon-hugo \
  --parallel 10 \
  --gh-pr \
  --llm gemini --GEMINI_API_KEY your_api_key
```

---

## Parameters

### Required Parameters

| Parameter | Description |
|-----------|-------------|
| `--website` | Base URL of documentation (e.g., `https://127.0.0.1/docs-v5`) |

### Git/PR Parameters (required for `run` with `--gh-pr`)

| Parameter | Description |
|-----------|-------------|
| `--local-webserver` | Local filesystem path to webserver root (e.g., `/var/www/photon-site`) |
| `--gh-repotoken` | GitHub Personal Access Token for authentication |
| `--gh-username` | GitHub username |
| `--ghrepo-url` | Your forked repository URL |
| `--ghrepo-branch` | Branch for commits/PR (default: `photon-hugo`) |
| `--ref-ghrepo` | Original repository to create PR against |
| `--ref-ghbranch` | Base branch for PR (default: `photon-hugo`) |
| `--gh-pr` | Flag to enable PR creation |

### Optional Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `--parallel` | 1 | Number of parallel threads (1-20) |
| `--language` | en | Language code for grammar checking |
| `--llm` | - | LLM provider for advanced fixes (`gemini` or `xai`) |
| `--GEMINI_API_KEY` | - | API key for Google Gemini |
| `--XAI_API_KEY` | - | API key for xAI (Grok) |
| `--ref-website` | - | Reference website for comparison |
| `--fix` | all | Selective fix specification (see below) |
| `--list-fixes` | - | Display all available fix types |
| `--feature` | none | Selective feature specification (see below) |
| `--list-features` | - | Display all available feature types |

---

## Selective Fix Application (--fix parameter)

The `--fix` parameter allows selective fix application. By default, all fixes are applied when using `--gh-pr`. Use `--list-fixes` to see all available fixes.

### Syntax

```bash
--fix SPEC
```

Where SPEC can be:
- Single ID: `--fix 1`
- Multiple IDs: `--fix 1,2,3`
- Range: `--fix 1-5`
- Mixed: `--fix 1,3,5-9`
- All: `--fix all` (default behavior)

### Available Fix Types

| ID | Name | Description | LLM Required |
|----|------|-------------|:------------:|
| 1 | broken-emails | Fix broken email addresses | No |
| 2 | vmware-spelling | Fix VMware spelling (vmware -> VMware) | No |
| 3 | deprecated-urls | Fix deprecated URLs (VMware, VDDK, OVFTOOL, AWS) | No |
| 4 | backtick-spacing | Fix missing spaces around backticks | No |
| 5 | backtick-errors | Fix backtick errors (spaces inside backticks) | No |
| 6 | heading-hierarchy | Fix heading hierarchy violations | No |
| 7 | header-spacing | Fix markdown headers missing space | No |
| 8 | html-comments | Fix HTML comments (remove markers, keep content) | No |
| 9 | grammar | Fix grammar and spelling issues | Yes |
| 10 | markdown-artifacts | Fix unrendered markdown artifacts | Yes |
| 11 | indentation | Fix indentation issues | Yes |
| 12 | malformed-codeblocks | Fix malformed code blocks | No |
| 13 | numbered-lists | Fix numbered list sequence errors | No |

### Examples

```bash
# Apply only VMware spelling and deprecated URL fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 2,3

# Apply all automatic fixes (1-8, 12-13), skip LLM fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 1-8,12,13
```

---

## Selective Feature Application (--feature parameter)

Features are optional enhancements that may modify code block formatting. They are **opt-in** and not applied by default.

### Available Feature Types

| ID | Name | Description | LLM Required |
|----|------|-------------|:------------:|
| 1 | shell-prompts | Remove shell prompts in code blocks ($ # etc.) | No |
| 2 | mixed-cmd-output | Separate mixed command/output in code blocks | Yes |

### Examples

```bash
# Apply shell prompt removal feature
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --feature 1

# Apply all features
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --feature all \
  --llm gemini --GEMINI_API_KEY your_key
```

---

## Plugin Documentation

Each plugin has its own README file in the `plugins/` directory with detailed documentation:

| Plugin | README | Description |
|--------|--------|-------------|
| Grammar | `plugins/README-grammar.md` | Grammar and spelling checking |
| Markdown | `plugins/README-markdown.md` | Markdown artifacts and code blocks |
| Heading Hierarchy | `plugins/README-heading_hierarchy.md` | Heading level validation |
| Formatting | `plugins/README-formatting.md` | Backtick spacing issues |
| Backtick Errors | `plugins/README-backtick_errors.md` | Spaces inside backticks |
| Indentation | `plugins/README-indentation.md` | List indentation issues |
| Deprecated URL | `plugins/README-deprecated_url.md` | URL replacements |
| Spelling | `plugins/README-spelling.md` | VMware spelling, emails, comments |
| Orphan Page | `plugins/README-orphan_page.md` | Inaccessible page detection |
| Orphan Link | `plugins/README-orphan_link.md` | Broken link detection |
| Orphan Image | `plugins/README-orphan_image.md` | Missing image detection |
| Image Alignment | `plugins/README-image_alignment.md` | Image alignment issues |
| Shell Prompt | `plugins/README-shell_prompt.md` | Shell prompt removal |
| Mixed Command Output | `plugins/README-mixed_command_output.md` | Command/output separation |

---

## Output Files

Each run generates timestamped output files:

| File | Description |
|------|-------------|
| `report-<datetime>.csv` | CSV report with all detected issues |
| `report-<datetime>.log` | Detailed log of the analysis process |

### CSV Format

```csv
page_url,category,location,fix
https://example.com/docs/page1/,grammar,"...the packages is installed...",The verb 'is' doesn't seem to agree
https://example.com/docs/page2/,orphan_link,"Link: 'Old Guide'",Remove or update link (status: 404)
```

---

## Fix Application Summary

| Category | Deterministic Fix | LLM Fix | Manual Review |
|----------|:-----------------:|:-------:|:-------------:|
| `broken_email` | Yes | - | - |
| `spelling` (VMware) | Yes | - | - |
| `deprecated_url` | Yes | - | - |
| `formatting` | Yes | - | - |
| `backtick_errors` | Yes | - | - |
| `heading_hierarchy` | Yes | - | - |
| `header_spacing` | Yes | - | - |
| `html_comment` | Yes | - | - |
| `malformed_code_block` | Yes | - | - |
| `numbered_list` | Yes | - | - |
| `grammar` | - | Yes | Fallback |
| `markdown` | Partial | Yes | - |
| `indentation` | - | Yes | Fallback |
| `orphan_link` | - | - | Yes |
| `orphan_image` | - | - | Yes |
| `image_alignment` | - | - | Yes |
| `orphan_page` | - | - | Yes |

---

## LLM Providers

### Google Gemini

```bash
--llm gemini --GEMINI_API_KEY your_api_key
```

Uses the `gemini-2.0-flash` model for cost-efficient, high-quality fixes.

### xAI (Grok)

```bash
--llm xai --XAI_API_KEY your_api_key
```

Uses the `grok-beta` model (OpenAI-compatible API).

---

## Workflow Diagram

```
+-------------------------------------------------------------+
|                    photonos-docs-lecturer.py                |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  1. Parse Arguments & Validate Connectivity                 |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  2. Generate Sitemap (sitemap.xml or crawl)                 |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  3. Initialize Grammar Checker (LanguageTool)               |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  4. Load Plugin System                                      |
|     - PluginManager discovers all plugins                   |
|     - Plugins initialized with config                       |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  5. Analyze Each Page (parallel if --parallel > 1)          |
|     - Plugin system handles all detection                   |
|     - Issues written to CSV                                 |
+-------------------------------------------------------------+
                              |
                   +----------+----------+
                   |                     |
            [analyze]              [run --gh-pr]
                   |                     |
                   v                     v
+---------------------+   +---------------------------------+
|  Done: Report Only  |   |  6. Apply Fixes via Plugins     |
+---------------------+   +---------------------------------+
                                         |
                                         v
                          +---------------------------------+
                          |  7. Git Commit & Push           |
                          +---------------------------------+
                                         |
                                         v
                          +---------------------------------+
                          |  8. Create GitHub PR            |
                          +---------------------------------+
```

---

## Troubleshooting

### Grammar Checker Fails to Initialize

```
[ERROR] Failed to initialize grammar checker
```

**Solution:** Install Java runtime (>= 17):
```bash
sudo tdnf install openjdk21
# or
sudo python3 photonos-docs-lecturer.py install-tools
```

### Plugin Import Errors

Ensure the `plugins/` directory exists and contains all plugin files:
```bash
ls -la plugins/
```

### LLM Fixes Not Applied

Ensure you provide the correct API key:
```bash
--llm gemini --GEMINI_API_KEY your_api_key_here
```

---

## Testing Results (v3.0)

The tool has been tested across all Photon OS documentation versions with consistent results:

| Section | Pages | Issues | Fixes Applied |
|---------|------:|-------:|--------------:|
| **docs-v3/overview** | 5 | 34 | 0 |
| **docs-v3/installation-guide** | 58 | 455 | 1 |
| **docs-v3/administration-guide** | 78 | 1,317 | 26 |
| **docs-v3/user-guide** | 14 | 108 | 2 |
| **docs-v3/command-line-reference** | 5 | 41 | 0 |
| **docs-v3/troubleshooting-guide** | 73 | 1,322 | 19 |
| **docs-v4/overview** | 4 | 9 | 0 |
| **docs-v4/installation-guide** | 49 | 223 | 2 |
| **docs-v4/administration-guide** | 94 | 1,205 | 33 |
| **docs-v4/user-guide** | 12 | 69 | 2 |
| **docs-v4/command-line-reference** | 6 | 45 | 0 |
| **docs-v5/overview** | 4 | 11 | 0 |
| **docs-v5/installation-guide** | 55 | 263 | 3 |
| **docs-v5/administration-guide** | 106 | 1,461 | 36 |
| **docs-v5/user-guide** | 21 | 105 | 3 |
| **docs-v5/command-line-reference** | 7 | 31 | 0 |
| **docs-v5/troubleshooting-guide** | 62 | 746 | 16 |

**Test Methodology:**
- Each section was tested with all fixes enabled (`--fix all`)
- Results were verified for consistency across two consecutive runs
- Parallel processing tested with 10 workers (`--parallel 10`)

---

## Version History

### Version 3.0 (Current)
- **MAJOR: Refactored into plugin architecture**
  - Main file reduced from 8,172 lines to ~1,330 lines (84% reduction)
  - 18 plugin modules for modular detection and fixing
  - Thread-safe logging per plugin to `/var/log/`
  - Individual versioning per plugin
  - PluginManager for coordination
  - Full backward compatibility with existing CLI
- **Bug fixes:**
  - Fixed `robots.txt` SSL verification issue (self-signed certificates)
  - Fixed grammar plugin API compatibility (`rule_id` vs `ruleId`)
- **Improved help:** Better CLI help with examples and metavars
- See `plugins/README-*.md` for per-plugin documentation

### Version 2.x
- See backup files for full version 2.x history
- Key features: URL protection, front matter restoration, LLM response cleaning

### Version 1.x
- Initial development with monolithic architecture
- Grammar/spelling detection with LanguageTool
- Markdown artifact detection
- Orphan link/image detection
- Git/PR workflow support

---

## Version

Current version: **3.0**

Check version:
```bash
python3 photonos-docs-lecturer.py version
```

---

## License

This tool is part of the photonos-scripts project.
