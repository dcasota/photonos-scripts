# Documentation Lecturer Module

**Version:** 1.0.0

## Description

The main orchestration module providing the `DocumentationLecturer` class for
crawling, analyzing, and fixing Photon OS documentation websites.

## Key Class

### DocumentationLecturer

Main class coordinating all documentation analysis:

```python
class DocumentationLecturer:
    def __init__(
        self,
        base_url: str,
        local_webserver: Optional[str] = None,
        github_repo: Optional[str] = None,
        github_branch: str = "master",
        language: str = "en",
        llm_provider: str = "xai",
        llm_api_key: Optional[str] = None
    )
```

## Available Fixes (FIX_TYPES)

| ID | Name | Description | LLM |
|----|------|-------------|-----|
| 1 | broken-emails | Fix broken email addresses (domain split with whitespace) | No |
| 2 | deprecated-urls | Fix deprecated URLs (VMware, VDDK, OVFTOOL, AWS, bosh-stemcell) | No |
| 3 | hardcoded-replaces | Fix known typos and errors (hardcoded replacements) | No |
| 4 | heading-hierarchy | Fix heading hierarchy violations (skipped levels) | No |
| 5 | header-spacing | Fix markdown headers missing space (####Title -> #### Title) | No |
| 6 | html-comments | Fix HTML comments (remove <!-- --> markers, keep content) | No |
| 7 | vmware-spelling | Fix VMware spelling (vmware -> VMware) | No |
| 8 | backticks | Fix all backtick issues (spacing, errors, malformed blocks) | Yes |
| 9 | grammar | Fix grammar and spelling issues | Yes |
| 10 | markdown-artifacts | Fix unrendered markdown artifacts | Yes |
| 11 | indentation | Fix indentation issues | Yes |
| 12 | numbered-lists | Fix numbered list sequence errors (duplicate numbers) | No |
| 13 | relative-paths | Allow relative path modifications (../path, ../../path) | No |

### FIX_ID 13: Relative Paths

When FIX_ID 13 is **NOT enabled** (default), the system will automatically revert any relative path modifications made by external tools (e.g., installer.sh). This ensures that paths like `../images/` are not inadvertently changed to `../../images/`.

To **allow** relative path modifications, explicitly include FIX_ID 13:
```bash
--fix 1,2,3,13  # or --fix all
```

## Available Features (FEATURE_TYPES)

| ID | Name | Description | LLM |
|----|------|-------------|-----|
| 1 | shell-prompts | Remove shell prompts in code blocks ($ # etc.) | No |
| 2 | mixed-cmd-output | Separate mixed command/output in code blocks | Yes |

## Core Features

### Site Crawling

Discovers all documentation pages:

```python
sitemap = lecturer.generate_sitemap()
# Uses sitemap.xml if available, falls back to crawling
# Respects robots.txt
```

### Multi-Plugin Analysis

Runs all registered plugins on each page:

```python
issues = lecturer.analyze_page(url)
# Returns: Dict[str, List[Issue]]
```

### Automatic Fixing

Applies fixes and commits to Git:

```python
lecturer.analyze_and_fix(
    fix_types=['grammar', 'deprecated_url'],
    create_pr=True
)
```

### Report Generation

Creates CSV reports of all issues:

```python
lecturer.generate_report('report.csv')
```

## Detection Patterns

Built-in pattern detection:
- Markdown rendering artifacts
- Missing spaces around backticks
- Malformed code blocks
- Consecutive inline commands
- Plain text commands needing formatting

## Workflow Modes

### Analysis Only

```bash
python3 photonos-docs-lecturer.py https://example.com/docs/
```

### Analysis + Fixes

```bash
python3 photonos-docs-lecturer.py https://example.com/docs/ \
    --fix 1,2,3 \
    --local-webserver /var/www/site
```

### With GitHub Integration

```bash
python3 photonos-docs-lecturer.py https://example.com/docs/ \
    --fix all \
    --github-repo owner/repo \
    --github-branch docs-fixes \
    --create-pr
```

### Selective Fixes with Relative Paths

```bash
# Apply fixes 1-3, allow relative path modifications
python3 photonos-docs-lecturer.py https://example.com/docs/ \
    --fix 1,2,3,13 \
    --local-webserver /var/www/site
```

## Dependencies

External libraries (set via `set_dependencies()`):
- requests
- BeautifulSoup
- language_tool_python
- tqdm (optional)
- PIL (optional)

## Plugin Integration

Uses PluginManager for extensibility:

```python
self.plugin_manager = create_plugin_manager(
    config=plugin_config,
    llm_client=self.llm_client
)
```

## Error Handling

- Network failures: Logged, page skipped
- Plugin failures: Logged, continue with other plugins
- File write failures: Logged, changes not committed

## Changes History

### Version 1.0.0
- Initial release with site crawling and analysis
- Plugin-based architecture for extensibility
- GitHub PR integration
- CSV report generation
- FIX_TYPES 1-13 support
- FEATURE_TYPES 1-2 support
