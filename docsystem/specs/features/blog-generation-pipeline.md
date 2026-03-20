# Feature Requirement Document (FRD): Blog Generation Pipeline

**Feature ID**: FRD-002
**Feature Name**: Blog Generation Pipeline
**Related PRD Requirements**: REQ-2, REQ-9
**Status**: Draft
**Last Updated**: 2026-03-21

---

## 1. Feature Overview

### Purpose

Generate AI-powered monthly changelog blog posts from imported commit data using the xAI/Grok API, producing Hugo-compatible markdown files with Keep-a-Changelog structure.

### Value Proposition

Automates the labor-intensive process of writing monthly release summaries, ensuring consistent formatting and comprehensive coverage across all 6 Photon OS branches.

### Success Criteria

- Blog posts generated for every branch/month combination with non-zero commits
- All posts pass Hugo frontmatter validation
- Resumability ensures no duplicate API calls for already-generated summaries
- Exported files match database-stored content exactly

---

## 2. Functional Requirements

### 2.1 xAI/Grok API Summarization

**Description**: For each branch/month with commits, send commit data to the xAI/Grok API for summarization into a structured changelog.

**Acceptance Criteria**:
- Commits grouped by branch and calendar month (YYYY-MM)
- API request includes all commit messages and metadata for the group
- API failures are retried up to 3 times with exponential backoff

### 2.2 Hugo-Compatible Markdown Output

**Description**: Each generated blog post is a markdown file with Hugo frontmatter.

**Frontmatter Fields**:
- `title`: e.g., "Photon OS 5.0 Changelog — March 2026"
- `date`: ISO-8601 date (first day of the month)
- `author`: "Photon OS Documentation Team"
- `tags`: branch name, "changelog", relevant package names
- `categories`: ["changelog", branch name]
- `summary`: One-line TL;DR from AI summary

**Acceptance Criteria**:
- Frontmatter is valid YAML between `---` delimiters
- File naming convention: `content/blog/YYYY-MM-<branch>-changelog.md`

### 2.3 Keep-a-Changelog Sections

**Description**: Blog post body follows Keep-a-Changelog structure with docsystem-specific sections.

**Required Sections** (in order):
1. **TL;DR** — One-paragraph executive summary
2. **Action Required** — Breaking changes or manual steps needed
3. **Security** — CVE fixes and security-related changes
4. **Added** — New packages, features, or capabilities
5. **Changed** — Updated packages, configuration changes
6. **Fixed** — Bug fixes and corrections
7. **Removed** — Deprecated or removed packages
8. **Contributors** — List of Signed-off-by contributors

**Acceptance Criteria**:
- Empty sections are omitted (not rendered with "None")
- Section order is preserved as specified above

### 2.4 Summaries Table (Resumability)

**Description**: Store generated summaries in a `summaries` SQLite table to enable resumability and drift detection.

**Schema**:

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `branch` | TEXT | Yes | Branch name |
| `year` | INTEGER | Yes | Calendar year |
| `month` | INTEGER | Yes | Calendar month (1-12) |
| `commit_count` | INTEGER | Yes | Number of commits summarized |
| `model` | TEXT | Yes | xAI model identifier used |
| `file_path` | TEXT | Yes | Relative path to generated markdown file |
| `changelog_md` | TEXT | Yes | Full markdown content of the blog post |
| `generated_at` | TEXT | Yes | ISO-8601 generation timestamp |

**Acceptance Criteria**:
- Composite primary key on (branch, year, month)
- Existing entry skipped on re-run unless `--force` flag is set

### 2.5 Export Mode

**Description**: `--export` flag restores blog post files from the database to the filesystem.

**Acceptance Criteria**:
- Reads `file_path` and `changelog_md` from summaries table
- Writes files to the correct Hugo content directory
- Reports count of files restored

### 2.6 Sync Check

**Description**: `--sync-check` flag detects drift between database-stored content and filesystem files.

**Acceptance Criteria**:
- Compares `changelog_md` in DB with file on disk
- Reports: files missing from disk, files differing from DB, files on disk not in DB

### 2.7 PostToolUse Hook Validation

**Description**: A PostToolUse hook validates Hugo frontmatter on every generated or exported blog post.

**Acceptance Criteria**:
- Validates presence of all required frontmatter fields (title, date, author, tags, categories, summary)
- Validates date is valid ISO-8601
- Rejects files with missing or malformed frontmatter
- Hook runs automatically after file write operations

---

## 3. Edge Cases

- **Zero commits in a month**: No blog post generated; skip silently
- **API rate limiting**: Respect xAI rate limits; back off and retry
- **Model output too short**: Log warning if summary is under 100 characters
- **Conflicting re-generation**: `--force` overwrites existing DB entry and file

---

## 4. Dependencies

### Depends On
- Commit Import Pipeline (FRD-001)
- xAI/Grok API access

### Depended On By
- Swarm Orchestration (FRD-004) — Blogger team uses this pipeline
