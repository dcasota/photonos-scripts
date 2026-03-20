# ADR-0003: Plugin-Based Documentation Quality Analysis

**Date:** 2026-03-21

**Status:** Accepted

## Context

The `docs-lecturer` tool must detect 12+ distinct categories of documentation quality
issues across a Hugo-based documentation site. Issue types include:

- Grammar and spelling errors
- Broken internal and external links
- Orphan pages (not linked from any navigation)
- Heading hierarchy violations (e.g., jumping from H1 to H3)
- Markdown rendering artifacts (raw HTML, unescaped characters)
- Missing alt text on images
- Inconsistent front matter metadata
- Deprecated API references
- Photon-specific content issues (wrong package names, outdated versions)

Each detection type has fundamentally different logic, different external dependencies,
and different performance characteristics. Some detectors (like broken link checking)
are I/O-bound; others (like grammar checking) require external services. The tool must
also support optional auto-fix for issues where safe automated correction is possible.

## Decision

Implement a **plugin architecture** with approximately 20 Python modules under a
`plugins/` directory. A `PluginManager` class discovers and loads plugins at startup.
Each plugin implements a standard interface:

```python
class BasePlugin:
    name: str           # Human-readable plugin name
    issue_type: str     # Category identifier (e.g., "grammar", "broken_link")
    severity: str       # "error", "warning", or "info"

    def detect(self, file_path: str, content: str) -> list[Issue]
    def fix(self, file_path: str, issue: Issue) -> bool  # optional
```

The `PluginManager`:
1. Scans the `plugins/` directory for Python modules.
2. Imports each module and registers classes that inherit from `BasePlugin`.
3. Runs `detect()` across all registered plugins for each documentation file.
4. Aggregates issues into a unified report with CSV output.
5. Optionally runs `fix()` for plugins that support auto-correction.

Issues are categorized by type and severity. Output is written to CSV for integration
with spreadsheet-based review workflows and CI reporting.

## Alternatives Considered

### Alternative 1: Monolithic Script

Implement all 20 detection routines in a single Python script with functions for
each issue type.

- **Rejected because:** Unmaintainable at 20+ detectors — the script would exceed
  2,000 lines with deeply interleaved concerns. Individual detectors cannot be
  tested in isolation. Adding a new issue type requires modifying the core script,
  increasing regression risk. Dependency management becomes a single large
  requirements file where unrelated packages conflict.

### Alternative 2: External Tools (markdownlint, vale, etc.)

Use existing open-source documentation linters and aggregate their output.

- **Rejected because:** No unified reporting format — each tool has its own output
  schema requiring custom parsers. Cannot integrate Photon OS-specific checks
  (e.g., validating package names against the Photon package repository). External
  tools have opinionated rule sets that don't align with Photon documentation
  conventions. Orchestrating 5+ separate CLI tools adds complexity without
  flexibility.

### Alternative 3: Configuration-Driven Approach

Define detection rules in YAML/JSON configuration files and interpret them with
a generic rule engine.

- **Rejected because:** Insufficient flexibility for complex detection logic.
  Rules like broken link checking, grammar analysis, and image validation require
  imperative code that cannot be expressed as declarative patterns. The
  configuration language would eventually grow into a domain-specific language
  with the same complexity as Python plugins but worse tooling support.

## Consequences

- **Extensibility:** New issue types are added by dropping a new `.py` file into
  `plugins/`. No changes to the core framework are needed.
- **Independent testability:** Each plugin can be unit-tested in isolation with
  fixture files representing known-good and known-bad documentation.
- **Startup overhead:** Plugin discovery and import adds minor startup latency
  (~100ms for 20 plugins). This is negligible for a batch analysis tool.
- **Per-plugin dependencies:** Some plugins require external packages
  (`language-tool-python` for grammar, `Pillow` for image analysis, `requests`
  for link checking). These are optional — plugins gracefully degrade if their
  dependencies are missing, logging a warning instead of crashing.
- **CSV output:** Standardized CSV reporting enables downstream consumption by
  CI systems, spreadsheet tools, and custom dashboards without additional parsing.
