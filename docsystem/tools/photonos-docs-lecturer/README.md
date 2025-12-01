# photonos-docs-lecturer.py User Manual

## Overview

`photonos-docs-lecturer.py` is a comprehensive documentation analysis and remediation tool for Photon OS documentation. It crawls documentation served by an Nginx webserver, identifies various issues (grammar, spelling, markdown artifacts, broken links/images, formatting problems), generates CSV reports, and optionally applies automated fixes via git push and GitHub pull requests.

### Project Goal

This tool was developed to address [GitHub Issue #22](https://github.com/dcasota/photonos-scripts/issues/22):

> Develop a command-line Python tool that crawls a Photon OS-hosted Nginx webserver serving documentation pages, identifies issues (grammar/spelling errors, Markdown rendering artifacts, orphan/broken links, orphan/broken images, unaligned multiple images), generates a CSV report, and optionally applies fixes via git push and GitHub pull request.

The goal is to automate documentation quality assurance for the Photon OS project, enabling systematic detection and remediation of common documentation issues across all documentation versions.

---

## Installation

### Prerequisites

- Python 3.8+
- Java (required for grammar checking via LanguageTool)

### Install Dependencies

```bash
# Install required tools (Java and Python packages)
sudo python3 photonos-docs-lecturer.py install-tools
```

This installs:
- Java runtime (openjdk)
- Python packages: requests, beautifulsoup4, language-tool-python, tqdm, Pillow
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
| `install-tools` | Install Java and required Python packages |
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
| `--XAI_API_KEY` | - | API key for xAI |
| `--ref-website` | - | Reference website for comparison |

---

## Issue Categories

The tool detects and reports issues in the following categories:

### 1. `grammar` - Grammar and Spelling Issues

**Detection:** Uses LanguageTool (Java-based) to check text for grammar and spelling errors.

**What it finds:**
- Spelling mistakes
- Grammar errors (subject-verb agreement, tense issues, etc.)
- Punctuation errors
- Style issues

**How it's fixed:**
- **Without LLM:** Reports suggestions from LanguageTool in the CSV
- **With LLM:** Uses Gemini/xAI to intelligently apply grammar corrections

**Example Report Entry:**
```
Category: grammar
Location: "...the packages is installed..."
Fix: [AGREEMENT_SENT_START] The verb 'is' doesn't seem to agree. Suggestions: are
```

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

**How it's fixed:**
- **Deterministic:** Headers missing space are auto-corrected
- **With LLM:** Complex markdown issues are fixed via AI

**Example Report Entry:**
```
Category: markdown
Location: Markdown header missing space: '####Configuration'
Fix: Add space after '####': '#### Configuration'
```

---

### 3. `orphan_url` - Broken/Orphan Links

**Detection:** HEAD requests to verify each internal link returns HTTP 2xx/3xx.

**What it finds:**
- Links returning 404 (Not Found)
- Links returning 5xx (Server Error)
- Links timing out

**How it's fixed:**
- Reported for manual review (links require human decision to update or remove)

**Example Report Entry:**
```
Category: orphan_url
Location: Link text: 'Installation Guide', URL: https://example.com/old-page
Fix: Remove or update link (status: 404)
```

---

### 4. `orphan_picture` - Broken/Orphan Images

**Detection:** HEAD requests to verify each image source URL is accessible.

**What it finds:**
- Images returning 404
- Missing image files
- Incorrect image paths

**How it's fixed:**
- Reported for manual review

**Example Report Entry:**
```
Category: orphan_picture
Location: Alt text: 'Architecture Diagram', URL: https://example.com/images/arch.png
Fix: Remove or fix image path (status: 404)
```

---

### 5. `unaligned_images` - Unaligned Multiple Images

**Detection:** Checks if pages with multiple images have proper CSS alignment classes.

**What it finds:**
- Multiple images without alignment CSS classes
- Images not wrapped in container elements
- Missing responsive image classes

**Alignment classes checked:** `align-center`, `align-left`, `align-right`, `centered`, `img-responsive`, `text-center`, `mx-auto`, `d-block`

**How it's fixed:**
- Reported with suggestion to add CSS classes or container divs

**Example Report Entry:**
```
Category: unaligned_images
Location: 3 unaligned images: /images/step1.png, /images/step2.png, /images/step3.png
Fix: Add CSS alignment classes or wrap images in container div
```

---

### 6. `formatting` - Formatting Issues

**Detection:** Regex patterns for missing spaces around inline code backticks.

**What it finds:**
- Missing space before backtick: `Clone\`the project\`` â†’ should be `Clone \`the project\``
- Missing space after backtick: `\`command\`text` â†’ should be `\`command\` text`

**How it's fixed:**
- **Deterministic:** Automatically adds missing spaces

**Example Report Entry:**
```
Category: formatting
Location: Missing space before backtick: ...Run`docker ps`...
Fix: Add space before backtick: 'Run `docker ps`' instead of 'Run`docker ps`'
```

---

### 7. `indentation` - List Indentation Issues

**Detection:** Analyzes HTML structure of ordered/unordered lists for improper nesting.

**What it finds:**
- Inconsistent list item indentation
- Code blocks inside list items not properly indented
- Nested content misaligned under parent list items

**How it's fixed:**
- **With LLM:** Uses AI to fix indentation in markdown source

**Example Report Entry:**
```
Category: indentation
Location: Code block in list item 3 may have indentation issues: sudo tdnf install...
Fix: Ensure code block is properly indented (4 spaces or 1 tab) under the list item
```

---

### 8. `shell_prompt` - Shell Prompts in Code Blocks

**Detection:** Regex patterns for common shell prompt prefixes that shouldn't be in copyable code.

**What it finds:**
- `$ command` (user prompt)
- `# command` (root prompt in specific contexts)
- `> command` (alternative prompt)
- `% command` (csh/tcsh prompt)
- `user@host$ command` (full prompt)
- `root@host# command` (root full prompt)

**How it's fixed:**
- **Deterministic:** Removes prompt prefixes, adds language hints (```console)

**Example Report Entry:**
```
Category: shell_prompt
Location: Shell prompt in code block: '$ sudo tdnf install nginx'
Fix: Remove shell prompt prefix '$' - command should be: 'sudo tdnf install nginx'
```

---

### 9. `mixed_command_output` - Mixed Command and Output

**Detection:** Heuristics identify code blocks containing both commands and their output.

**What it finds:**
- Code blocks where a command is followed by its output
- Makes copy-paste difficult for users

**Common patterns detected:**
```
sudo cat /etc/config.toml    â† Command
[Section]                     â† Output starts here
Key="value"
```

**How it's fixed:**
- **With LLM:** Separates into two code blocks (command + output)

**Example Report Entry:**
```
Category: mixed_command_output
Location: Mixed command and output in code block. Command: 'cat /etc/os-release', Output starts: 'NAME="VMware Photon OS"'
Fix: Separate into two code blocks: one for the command (copyable) and one for the output (display only)
```

---

### 10. `deprecated_url` - Deprecated VMware URLs

**Detection:** Regex matches `packages.vmware.com` URLs that should use Broadcom infrastructure.

**What it finds:**
- `https://packages.vmware.com/*` URLs
- These should be updated to `https://packages-prod.broadcom.com/`

**How it's fixed:**
- **Deterministic:** Automatically replaces deprecated URLs

**Example Report Entry:**
```
Category: deprecated_url
Location: Deprecated VMware URL: https://packages.vmware.com/photon/3.0/
Fix: Replace with https://packages-prod.broadcom.com/
```

---

### 11. `spelling` - VMware Spelling Errors

**Detection:** Regex matches incorrect capitalizations of "VMware".

**What it finds:**
- `vmware` (all lowercase)
- `Vmware` (only first letter capitalized)
- `VMWare` (incorrect second capital)
- `VMWARE` (all caps)

**Excludes:** URLs, domain names, code blocks

**How it's fixed:**
- **Deterministic:** Replaces with correct spelling `VMware`

**Example Report Entry:**
```
Category: spelling
Location: Incorrect VMware spelling: 'vmware' in ...Photon OS is developed by vmware...
Fix: Change 'vmware' to 'VMware'
```

---

### 12. `orphan_page` - Inaccessible Pages

**Detection:** Pages in sitemap that return HTTP 4xx/5xx or timeout.

**What it finds:**
- Pages returning 404
- Server errors (5xx)
- Connection timeouts

**How it's fixed:**
- Reported for manual review (remove from sitemap or fix page)

**Example Report Entry:**
```
Category: orphan_page
Location: HTTP 404 - Page not accessible
Fix: Remove from sitemap or fix page availability
```

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
https://example.com/docs/page2/,orphan_url,"Link text: 'Old Guide', URL: ...",Remove or update link (status: 404)
```

---

## Fix Application Summary

| Category | Deterministic Fix | LLM Fix | Manual Review |
|----------|:-----------------:|:-------:|:-------------:|
| `grammar` | - | Yes | Fallback |
| `markdown` | Partial | Yes | - |
| `orphan_url` | - | - | Yes |
| `orphan_picture` | - | - | Yes |
| `unaligned_images` | - | - | Yes |
| `formatting` | Yes | - | - |
| `indentation` | - | Yes | Fallback |
| `shell_prompt` | Yes | - | - |
| `mixed_command_output` | - | Yes | Fallback |
| `deprecated_url` | Yes | - | - |
| `spelling` | Yes | - | - |
| `orphan_page` | - | - | Yes |

**Legend:**
- **Deterministic Fix:** Applied automatically using regex/rules
- **LLM Fix:** Applied using AI (requires `--llm` and API key)
- **Manual Review:** Reported in CSV for human decision

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

### Example Output

```
==============================================
  Issue Report - Categories
  Total Issues: 1399
==============================================

  Rank | Category                              | Count | Percentage
  -----+---------------------------------------+-------+-----------
  1    | double_slash (malformed // in paths)  |  1301 |  92.9%
       | - from printview pages                |   997 |  71.2%
       | - from other pages                    |   304 |  21.7%
  2    | missing_image (broken image refs)     |    60 |   4.2%
  3    | other (md_file_link, wrong paths)     |    38 |   2.7%

==============================================
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
|  3. Analyze Each Page (parallel if --parallel > 1)         |
|     - Grammar/spelling (LanguageTool)                       |
|     - Markdown artifacts (regex)                            |
|     - Orphan links/images (HEAD checks)                     |
|     - Formatting issues                                     |
|     - Shell prompts in code blocks                          |
|     - Deprecated URLs                                       |
|     - VMware spelling                                       |
+-------------------------------------------------------------+
                              |
                              v
+-------------------------------------------------------------+
|  4. Write Issues to CSV Report                              |
+-------------------------------------------------------------+
                              |
                   +----------+----------+
                   |                     |
            [analyze]              [run --gh-pr]
                   |                     |
                   v                     v
+---------------------+   +---------------------------------+
|  Done: Report Only  |   |  5. Apply Fixes                 |
+---------------------+   |     - Deterministic fixes       |
                          |     - LLM-based fixes (if key)  |
                          +---------------------------------+
                                         |
                                         v
                          +---------------------------------+
                          |  6. Git Commit & Push           |
                          |     - Commit modified files     |
                          |     - Push to --ghrepo-branch   |
                          +---------------------------------+
                                         |
                                         v
                          +---------------------------------+
                          |  7. Create GitHub PR            |
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

**Solution:** Install Java runtime:
```bash
sudo tdnf install openjdk11
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
python3 photonos-docs-lecturer.py run \
  --llm gemini \
  --GEMINI_API_KEY your_api_key_here \
  ...
```

### No Local File Found for URL

The tool maps URLs to local markdown files. Ensure:
1. `--local-webserver` points to the Hugo content root
2. Directory structure matches: `{local-webserver}/content/{language}/...`

---

## Version

Current version: **1.3**

Check version:
```bash
python3 photonos-docs-lecturer.py version
```
