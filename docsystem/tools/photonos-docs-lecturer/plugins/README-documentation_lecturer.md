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
    --fix grammar,spelling \
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
