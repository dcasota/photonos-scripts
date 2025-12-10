# photonos-docs-lecturer.py User Manual

## Overview

`photonos-docs-lecturer.py` is a comprehensive documentation analysis and remediation tool for Photon OS documentation. It crawls documentation served by an Nginx webserver, identifies various issues (grammar, spelling, markdown artifacts, broken links/images, formatting problems, heading hierarchy violations), generates CSV reports, and optionally applies automated fixes via git push and GitHub pull requests.

### Project Goal

This tool was developed to address [GitHub Issue #22](https://github.com/dcasota/photonos-scripts/issues/22):

> Develop a command-line Python tool that crawls a Photon OS-hosted Nginx webserver serving documentation pages, identifies issues (grammar/spelling errors, Markdown rendering artifacts, orphan/broken links, orphan/broken images, unaligned multiple images), generates a CSV report, and optionally applies fixes via git push and GitHub pull request.

The goal is to automate documentation quality assurance for the Photon OS project, enabling systematic detection and remediation of common documentation issues across all documentation versions.

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
- LLM support: google-generativeai (for Gemini-based fixes when `--llm gemini` is specified)

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
| `install-tools` | Install Java and required Python packages (requires admin/sudo) |
| `version` | Display tool version |

### Basic Examples

```bash
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

# Full workflow with LLM-assisted fixes (xAI/Grok)
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
  --llm xai --XAI_API_KEY your_api_key
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
| `--test` | - | Run unit tests instead of analysis |

---

## Selective Fix Application (--fix parameter)

Version 1.5 introduces the `--fix` parameter for selective fix application. By default, all fixes are applied when using `--gh-pr`. Use `--list-fixes` to see all available fixes.

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
| 1 | broken-emails | Fix broken email addresses (domain split with whitespace) | No |
| 2 | vmware-spelling | Fix VMware spelling (vmware -> VMware) | No |
| 3 | deprecated-urls | Fix deprecated URLs (VMware, VDDK, OVFTOOL, AWS, bosh-stemcell) | No |
| 4 | backtick-spacing | Fix missing spaces around backticks, remove backticks from URLs | No |
| 5 | backtick-errors | Fix backtick errors (spaces inside backticks) | No |
| 6 | heading-hierarchy | Fix heading hierarchy violations (skipped levels) | No |
| 7 | header-spacing | Fix markdown headers missing space (####Title -> #### Title) | No |
| 8 | html-comments | Fix HTML comments (remove <!-- --> markers, keep content) | No |
| 9 | grammar | Fix grammar and spelling issues | Yes |
| 10 | markdown-artifacts | Fix unrendered markdown artifacts | Yes |
| 11 | indentation | Fix indentation issues | Yes |
| 12 | malformed-codeblocks | Fix malformed code blocks (mismatched backticks, unclosed inline code) | No |
| 13 | numbered-lists | Fix numbered list sequence errors (duplicate/skipped numbers) | No |

### Examples

```bash
# Apply only VMware spelling and deprecated URL fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 2,3

# Apply all automatic fixes (1-8, 12), skip LLM fixes
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 1-8,12

# Apply grammar fixes only (requires LLM)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix 9 \
  --llm gemini --GEMINI_API_KEY your_key
```

---

## Selective Feature Application (--feature parameter)

Version 1.7 introduces the `--feature` parameter for optional feature enhancements. Features are **opt-in** and not applied by default. Use `--list-features` to see all available features.

Features are separated from fixes because they may modify code block formatting in ways that change the documentation style (e.g., removing shell prompts).

### Syntax

```bash
--feature SPEC
```

Where SPEC can be:
- Single ID: `--feature 1`
- Multiple IDs: `--feature 1,2`
- Range: `--feature 1-2`
- All: `--feature all`

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

# Apply all features (requires LLM for mixed-cmd-output)
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --feature all \
  --llm xai --XAI_API_KEY your_key

# Apply fixes and features together
python3 photonos-docs-lecturer.py run \
  --website https://127.0.0.1/docs-v5 \
  --local-webserver /var/www/photon-site \
  --gh-pr --fix all --feature all \
  --llm gemini --GEMINI_API_KEY your_key
```

---

## Issue Categories

The tool detects and reports issues in the following categories:

### 1. `grammar` - Grammar and Spelling Issues

**Detection:** Uses LanguageTool (Java-based) to check text for grammar and spelling errors. Code blocks and inline code are automatically excluded from grammar checking.

**What it finds:**
- Spelling mistakes
- Grammar errors (subject-verb agreement, tense issues, etc.)
- Punctuation errors
- Style issues

**How it's fixed:**
- **Without LLM:** Reports suggestions from LanguageTool in the CSV
- **With LLM:** Uses Gemini/xAI to intelligently apply grammar corrections

---

### 2. `markdown` - Markdown Rendering Artifacts

**Detection:** Regex patterns identify unrendered markdown syntax in HTML output.

**What it finds:**
- Unrendered headers (`## Header` appearing as text)
- Unrendered bullet points (`* item` appearing as text)
- Unrendered links (`[text](url)` appearing as text)
- Unrendered code blocks and inline code
- Unrendered bold/italic (`**bold**`, `_italic_`)
- Headers missing space after `#` (e.g., `####Title` instead of `#### Title`)
- Unclosed fenced code blocks (``` without closing ```)
- Unclosed inline code backticks

**How it's fixed:**
- **Deterministic:** Headers missing space are auto-corrected
- **With LLM:** Complex markdown issues are fixed via AI

---

### 3. `heading_hierarchy` - Heading Level Violations

**Detection:** Analyzes markdown heading structure for proper hierarchy.

**What it finds:**
- Skipped heading levels (e.g., H1 -> H3 without H2)
- Wrong first heading level (should start with appropriate level based on context)
- Inconsistent heading progression

**How it's fixed:**
- **Deterministic:** Automatically adjusts heading levels to fix hierarchy

---

### 4. `orphan_link` / `orphan_url` - Broken/Orphan Links

**Detection:** HEAD requests to verify each internal link returns HTTP 2xx/3xx.

**What it finds:**
- Links returning 404 (Not Found)
- Links returning 5xx (Server Error)
- Links timing out

**How it's fixed:**
- Reported for manual review (links require human decision to update or remove)

---

### 5. `orphan_image` / `orphan_picture` - Broken/Orphan Images

**Detection:** HEAD requests to verify each image source URL is accessible.

**What it finds:**
- Images returning 404
- Missing image files
- Incorrect image paths

**How it's fixed:**
- Reported for manual review

---

### 6. `image_alignment` / `unaligned_images` - Unaligned Multiple Images

**Detection:** Checks if pages with multiple images have proper CSS alignment classes.

**What it finds:**
- Multiple images without alignment CSS classes
- Images not wrapped in container elements
- Missing responsive image classes

**Alignment classes checked:** `align-center`, `align-left`, `align-right`, `centered`, `img-responsive`, `text-center`, `mx-auto`, `d-block`

**How it's fixed:**
- Reported with suggestion to add CSS classes or container divs

---

### 7. `formatting` - Formatting Issues (Backtick Spacing)

**Detection:** Regex patterns for missing spaces around inline code backticks.

**What it finds:**
- Missing space after backtick: `` `command`text`` -> should be `` `command` text``
- URLs incorrectly wrapped in backticks: `` `https://example.com` `` -> should be `https://example.com`

**How it's fixed:**
- **Deterministic:** Automatically adds missing spaces
- **Deterministic:** Removes backticks from standalone URLs (URLs should not be in inline code)

---

### 8. `backtick_errors` - Backtick Errors

**Detection:** Regex patterns for malformed backtick usage.

**What it finds:**
- Space after opening backtick: `` ` code` `` -> should be `` `code` ``
- Space before closing backtick: `` `code ` `` -> should be `` `code` ``
- Spaces on both sides: `` ` code ` `` -> should be `` `code` ``
- Unclosed fenced code blocks
- Unclosed inline code backticks

**How it's fixed:**
- **Deterministic:** Automatically fixes space issues in backticks

---

### 9. `indentation` - List Indentation Issues

**Detection:** Analyzes HTML structure of ordered/unordered lists for improper nesting.

**What it finds:**
- Inconsistent list item indentation
- Code blocks inside list items not properly indented
- Nested content misaligned under parent list items

**How it's fixed:**
- **With LLM:** Uses AI to fix indentation in markdown source

---

### 10. `deprecated_url` - Deprecated URLs

**Detection:** Regex matches deprecated URLs that need updating.

**Deprecated URLs detected:**
| Old URL | New URL |
|---------|---------|
| `packages.vmware.com/*` | `packages.broadcom.com/` |
| `my.vmware.com/.../VDDK670...` | `developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7` |
| `developercenter.vmware.com/web/sdk/60/vddk` | `developer.broadcom.com/sdks/vmware-virtual-disk-development-kit-vddk/6.7` |
| `my.vmware.com/.../OVFTOOL410...` | `developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest` |
| `docs.aws.amazon.com/.../set-up-ec2-cli-linux.html` | `docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html` |
| `github.com/cloudfoundry/bosh/blob/develop/bosh-stemcell/README.md` | `github.com/cloudfoundry/bosh/blob/main/README.md` |

**How it's fixed:**
- **Deterministic:** Automatically replaces deprecated URLs

---

### 11. `spelling` - VMware Spelling Errors

**Detection:** Regex matches incorrect capitalizations of "VMware".

**What it finds:**
- `vmware` (all lowercase)
- `Vmware` (only first letter capitalized)
- `VMWare` (incorrect second capital)
- `VMWARE` (all caps)

**Excludes:** URLs, domain names, file paths, email addresses, code blocks

**How it's fixed:**
- **Deterministic:** Replaces with correct spelling `VMware`

---

### 12. `broken_email` - Broken Email Addresses

**Detection:** Regex matches email addresses where the domain is split with whitespace/newlines.

**What it finds:**
- `linux-packages@vmware.                        com` -> should be `linux-packages@vmware.com`

**How it's fixed:**
- **Deterministic:** Automatically removes whitespace to fix email

---

### 13. `html_comment` - HTML Comments

**Detection:** Regex matches HTML comment markers `<!-- ... -->`.

**What it finds:**
- HTML comments that should be uncommented/visible
- Commented-out content that should be restored

**How it's fixed:**
- **Deterministic:** Removes comment markers, keeps inner content

---

### 14. `orphan_page` - Inaccessible Pages

**Detection:** Pages in sitemap that return HTTP 4xx/5xx or timeout.

**What it finds:**
- Pages returning 404
- Server errors (5xx)
- Connection timeouts

**How it's fixed:**
- Reported for manual review (remove from sitemap or fix page)

---

### 15. `malformed_code_block` - Malformed Code Blocks

**Detection:** Regex patterns identify incorrectly formatted code blocks in markdown source.

**What it finds:**
- Single backtick + content + triple backticks: `` `command``` `` (should be fenced block)
- Consecutive inline code lines that should be fenced (including with blank lines between them):
  ```
  `command1`
  `command2`
  ```
  Should be:
  ```bash
  command1
  command2
  ```
- Stray backticks inside fenced code blocks (e.g., trailing backtick on a line)
- Unclosed inline backticks at end of sentences: `` `$HOME/path. `` -> `` `$HOME/path`. ``

**How it's fixed:**
- **Deterministic:** Automatically converts to proper fenced code blocks and removes stray backticks
- **Deterministic:** Closes unclosed inline backticks that end with sentence punctuation

---

### 16. `numbered_list` - Numbered List Sequence Errors

**Detection:** Analyzes numbered list sequences for duplicate or skipped numbers.

**What it finds:**
- Duplicate numbers (e.g., 1, 2, 3, 3, 5)
- Skipped numbers in sequence (e.g., 1, 2, 4)
- Out of order numbers

**How it's fixed:**
- **Deterministic:** Automatically renumbers list items to correct sequence

---

## Feature Categories

Features are optional enhancements that may modify code block formatting in ways that change the documentation style. They are **opt-in** via the `--feature` parameter and are not applied by default.

### 1. `shell_prompt` - Shell Prompts in Code Blocks

**Detection:** Regex patterns for common shell prompt prefixes that shouldn't be in copyable code.

**What it finds:**
- `$ command` (user prompt)
- `> command` (alternative prompt)
- `% command` (csh/tcsh prompt)
- `~ command` (home directory prompt)
- `user@host$ command` (full prompt)
- `root@host# command` (root full prompt)
- `❯ command` (fancy prompts like starship, powerline)
- `➜ command` (Oh My Zsh robbyrussell theme)

**How it's fixed:**
- **Deterministic:** Removes prompt prefixes, adds language hints (```console)

---

### 2. `mixed_command_output` - Mixed Command and Output

**Detection:** Heuristics identify code blocks containing both commands and their output.

**What it finds:**
- Code blocks where a command is followed by its output
- Makes copy-paste difficult for users

**How it's fixed:**
- **With LLM:** Separates into two code blocks (command + output)

---

## Output Files

Each run generates timestamped output files:

| File | Description |
|------|-------------|
| `report-<datetime>.csv` | CSV report with all detected issues |
| `report-<datetime>.log` | Detailed log of the analysis process |

### CSV Format

```csv
Page URL,Issue Category,Issue Location Description,Fix Suggestion
https://example.com/docs/page1/,grammar,"...the packages is installed...",The verb 'is' doesn't seem to agree. Suggestions: are
https://example.com/docs/page2/,orphan_link,"Link text: 'Old Guide', URL: ...",Remove or update link (status: 404)
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

**Legend:**
- **Deterministic Fix:** Applied automatically using regex/rules (fixes 1-8, 12-13)
- **LLM Fix:** Applied using AI (fixes 9-11, requires `--llm` and API key)
- **Manual Review:** Reported in CSV for human decision

---

## Feature Application Summary

Features are opt-in enhancements applied via `--feature` parameter:

| Feature | Deterministic Fix | LLM Fix |
|---------|:-----------------:|:-------:|
| `shell_prompt` | Yes | - |
| `mixed_command_output` | - | Yes |

**Legend:**
- **Deterministic Fix:** Applied automatically using regex/rules (feature 1)
- **LLM Fix:** Applied using AI (feature 2, requires `--llm` and API key)

---

## LLM Providers

The tool supports two LLM providers for advanced fixes:

### Google Gemini

```bash
--llm gemini --GEMINI_API_KEY your_api_key
```

Uses the `gemini-2.5-flash` model for cost-efficient, high-quality fixes.

### xAI (Grok)

```bash
--llm xai --XAI_API_KEY your_api_key
```

Uses the `grok-3-mini` model (OpenAI-compatible API).

### URL and Path Protection

When using LLM-assisted fixes, URLs and paths are automatically protected using placeholders before being sent to the LLM. This prevents the LLM from accidentally modifying them. Original content is restored after the LLM response is received.

**Protected content includes:**
- Markdown links: `[text](url)` - the URL part is protected
- Standalone URLs: `https://example.com/path`
- Relative documentation paths: `troubleshooting-guide/solutions-to-common-problems/page`
- Paths starting with `./` or `../`: `../administration-guide/security-policy/settings`
- File paths with `.md` extension: `path/to/file.md`

---

## Post-Analysis: Generating Issue Rankings

After running the tool, use these commands to generate a summary ranking:

```bash
REPORT="report-2025-12-01T10-30-00.csv"

# Count by category
tail -n +2 "$REPORT" | cut -d',' -f2 | sort | uniq -c | sort -rn

# Generate formatted ranking
total=$(tail -n +2 "$REPORT" | wc -l)
echo "=============================================="
echo "  Issue Report - Categories"
echo "  Total Issues: $total"
echo "=============================================="
tail -n +2 "$REPORT" | cut -d',' -f2 | sort | uniq -c | sort -rn | while read count category; do
  pct=$(echo "scale=1; $count * 100 / $total" | bc)
  printf "  %-25s %5d  (%5.1f%%)\n" "$category" $count $pct
done
```

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
|     - Test HEAD request to --website                        |
|     - Initialize logging                                    |
|     - Parse --fix specification (if provided)               |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  2. Generate Sitemap                                        |
|     - Try sitemap.xml first                                 |
|     - Fallback: BFS crawl (depth=5, respect robots.txt)     |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  3. Initialize Grammar Checker                              |
|     - Load LanguageTool (requires Java >= 17)               |
|     - Configure for specified language                      |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  4. Analyze Each Page (parallel if --parallel > 1)          |
|     - Grammar/spelling (LanguageTool)                       |
|     - Markdown artifacts (regex)                            |
|     - Heading hierarchy violations                          |
|     - Orphan links/images (HEAD checks)                     |
|     - Formatting issues (backtick spacing)                  |
|     - Backtick errors (spaces inside)                       |
|     - Shell prompts in code blocks                          |
|     - Mixed command/output detection                        |
|     - Deprecated URLs                                       |
|     - VMware spelling                                       |
|     - Broken email addresses                                |
|     - HTML comments                                         |
|     - Malformed code blocks                                 |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  5. Write Issues to CSV Report                              |
+-------------------------------------------------------------+
                              |
                   +----------+----------+
                   |                     |
            [analyze]              [run --gh-pr]
                   |                     |
                   v                     v
+---------------------+   +---------------------------------+
|  Done: Report Only  |   |  6. Apply Fixes (based on --fix)|
+---------------------+   |     - Deterministic fixes (1-9) |
                          |     - LLM-based fixes (10-13)   |
                          +---------------------------------+
                                         |
                                         v
                          +---------------------------------+
                          |  7. Git Commit & Push           |
                          |     - Incremental per-fix mode  |
                          |     - Commit modified files     |
                          |     - Push to --ghrepo-branch   |
                          +---------------------------------+
                                         |
                                         v
                          +---------------------------------+
                          |  8. Create GitHub PR            |
                          |     - PR to --ref-ghrepo        |
                          |     - Include fix summary       |
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

### SSL Certificate Errors

The tool uses `verify=False` by default for self-signed certificates. If you still encounter issues:
```bash
# Export certificate from your server
openssl s_client -connect localhost:443 </dev/null 2>/dev/null | \
  openssl x509 -outform PEM > server.crt
```

### LLM Fixes Not Applied

Ensure you provide the correct API key:
```bash
# For Gemini
python3 photonos-docs-lecturer.py run \
  --llm gemini \
  --GEMINI_API_KEY your_api_key_here \
  ...

# For xAI
python3 photonos-docs-lecturer.py run \
  --llm xai \
  --XAI_API_KEY your_api_key_here \
  ...
```

### xAI API 404 Error

If you see `404 Client Error: Not Found for url: https://api.x.ai/v1/chat/completions`, ensure:
1. Your API key is valid and has access to the xAI API
2. The tool is using a valid model name (default: `grok-3-mini`)

### No Local File Found for URL

The tool maps URLs to local markdown files. Ensure:
1. `--local-webserver` points to the Hugo content root
2. Directory structure matches: `{local-webserver}/content/{language}/...`

### Selective Fixes Not Working

Use `--list-fixes` to see available fix IDs:
```bash
python3 photonos-docs-lecturer.py run --list-fixes
```

---

## Version History

### Version 1.8 (Current)
- Added Fix Type 13: Numbered list sequence errors
  - Detects duplicate numbers (e.g., 1, 2, 3, 3, 5)
  - Detects skipped numbers in sequence
  - Automatically renumbers list items to correct sequence
- Enhanced malformed code block detection and fixing:
  - Now handles blank lines between consecutive inline commands
  - Fixes unclosed inline backticks at end of sentences (e.g., `` `$HOME/path. `` -> `` `$HOME/path`. ``)
- Enhanced backtick spacing fix:
  - Removes backticks from standalone URLs (URLs should not be in inline code)
- Added relative path protection for LLM fixes:
  - Protects paths like `troubleshooting-guide/solutions-to-common-problems/page`
  - Protects paths starting with `./` or `../`
  - Prevents LLM from modifying documentation links
- Increased xAI max_tokens from 2000 to 131072 to prevent LLM truncating long documents
- 13 enumerated fix types (9 automatic, 4 LLM-assisted)

### Version 1.7
- Separated fixes and features into two categories:
  - **Fixes** (`--fix`): Bug fixes and error corrections (applied by default)
  - **Features** (`--feature`): Optional enhancements that modify code style (opt-in)
- Moved shell-prompts and mixed-cmd-output from fixes to features
- Added `--feature` parameter for selective feature application
- Added `--list-features` option to display all available features
- Renumbered fix IDs to maintain sequential numbering:
  - Fix IDs 1-12 (was 1-14, minus shell-prompts and mixed-cmd-output)
  - Feature IDs 1-2 (shell-prompts, mixed-cmd-output)

### Version 1.6
- Added Fix Type 14: malformed code blocks detection and fixing
  - Detects single backtick + triple backtick patterns (`` `cmd``` ``)
  - Detects consecutive inline code lines that should be fenced blocks
  - Detects and removes stray backticks inside fenced code blocks
- 14 enumerated fix types (10 automatic, 4 LLM-assisted)
- Improved detection of code block formatting issues

### Version 1.5
- Added `--fix` parameter for selective fix application
- 13 enumerated fix types (9 automatic, 4 LLM-assisted)
- Added `--list-fixes` option to display all available fixes
- Added broken email detection and fixing
- Added HTML comment detection and fixing
- Added heading hierarchy violation detection and fixing
- Added header spacing detection and fixing
- Improved backtick error detection (spaces inside backticks)
- Added xAI (Grok) LLM provider support
- URL protection for LLM-assisted fixes (prevents URL modification)
- Incremental PR workflow support

### Version 1.3
- Initial documented version
- Grammar/spelling detection with LanguageTool
- Markdown artifact detection
- Orphan link/image detection
- VMware spelling detection
- Deprecated URL detection
- Shell prompt detection
- Gemini LLM support

---

## Version

Current version: **1.8**

Check version:
```bash
python3 photonos-docs-lecturer.py version
```
