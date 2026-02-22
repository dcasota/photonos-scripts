# Docs Blogger Team

**Purpose**: Automated blog content generation from Photon OS repository commit history and development activities.

## Architecture

The docs-blogger team is integrated into the Factory droid framework using
three primitives: **skills** (reusable capabilities), **droids** (subagents),
and **hooks** (deterministic validation).

### Factory Layout

```
.factory/
  droids/
    docs-blogger-blogger.md       # Blog generation droid
    docs-blogger-orchestrator.md  # Workflow coordination droid
    docs-blogger-pr-bot.md        # PR creation droid
  skills/
    photon-import/
      SKILL.md                    # Skill: commit data import
      importer.py                 # Script: clone repo, populate SQLite DB
    photon-summarize/
      SKILL.md                    # Skill: AI-powered monthly summaries
      summarizer.py               # Script: generate Hugo blog posts via xAI
    db_schema.py                  # Shared DB schema (commits + summaries)
  hooks/
    validate_hugo_frontmatter.py  # PostToolUse hook: front matter validation
  settings.json                   # Hook registration
```

### Workflow Diagram

```
                         ┌──────────────────────────────────┐
                         │        Weekly Cron / Manual       │
                         └──────────────┬───────────────────┘
                                        │
                    ┌───────────────────┐│┌───────────────────┐
                    │                   │││                   │
                    ▼                   │││                   ▼
         ┌──────────────────┐          │││        ┌──────────────────┐
         │   importer.py    │          │││        │  summarizer.py   │
         │  (photon-import) │          │││        │(photon-summarize)│
         └────────┬─────────┘          │││        └────────┬─────────┘
                  │                    │││                  │
      ┌───────────┴───────────┐        │││   ┌─────────────┴──────────────┐
      │ 1. git clone/fetch    │        │││   │ 1. Read commits from DB    │
      │    vmware/photon      │        │││   │ 2. Group by branch + month │
      │ 2. For each branch:   │        │││   │ 3. Skip if commit count    │
      │    checkout + rev-list│        │││   │    matches stored summary  │
      │ 3. Parse each commit  │        │││   │ 4. Batch commits (40/batch)│
      │    (message, diff,    │        │││   │ 5. xAI API per batch       │
      │     metadata)         │        │││   │ 6. Combine sub-summaries   │
      │ 4. INSERT OR IGNORE   │        │││   │ 7. Write Hugo .md files    │
      │    into commits table │        │││   │ 8. Store in summaries table│
      └───────────┬───────────┘        │││   └─────────────┬──────────────┘
                  │                    │││                  │
                  ▼                    │││                  ▼
         ┌───────────────────────────────────────────────────────┐
         │                   photon_commits.db                   │
         │                                                       │
         │  ┌─────────────────────┐  ┌─────────────────────────┐ │
         │  │    commits table    │  │    summaries table       │ │
         │  │                     │  │                          │ │
         │  │ branch              │  │ branch, year, month      │ │
         │  │ commit_hash         │  │ commit_count             │ │
         │  │ message             │  │ model                    │ │
         │  │ commit_datetime     │  │ changelog_md             │ │
         │  │ signed_off_by       │  │ file_path                │ │
         │  │ content (diff)      │  │ generated_at             │ │
         │  │ ...                 │  │                          │ │
         │  └─────────────────────┘  └─────────────────────────┘ │
         └───────────────────────────────────────────────────────┘
                                        │
                                        ▼
         ┌───────────────────────────────────────────────────────┐
         │        content/blog/YYYY/MM/                          │
         │        photon-<branch>-monthly-YYYY-MM.md             │
         │                                                       │
         │  ┌─────────────────────────────────────────────────┐  │
         │  │ Hugo front matter (title, date, tags, ...)      │  │
         │  │ ## TL;DR                                        │  │
         │  │ ## Action Required                              │  │
         │  │ ## Security          (CVEs with NVD links)      │  │
         │  │ ## Added                                        │  │
         │  │ ## Changed           (version upgrades)         │  │
         │  │ ## Fixed                                        │  │
         │  │ ## Removed                                      │  │
         │  │ ## Contributors                                 │  │
         │  └─────────────────────────────────────────────────┘  │
         └───────────────────────────────────────────────────────┘
```

### Summarizer Batching and Combine Strategy

```
189 commits (example: 2022-05)
  │
  ├─ Batch 1: 40 commits ──► xAI API ──► sub-summary 1
  ├─ Batch 2: 40 commits ──► xAI API ──► sub-summary 2
  ├─ Batch 3: 40 commits ──► xAI API ──► sub-summary 3
  ├─ Batch 4: 40 commits ──► xAI API ──► sub-summary 4
  └─ Batch 5: 29 commits ──► xAI API ──► sub-summary 5
                                              │
               ┌──────────────────────────────┘
               │
               ▼  <= 5 sub-summaries: direct final combine
        ┌──────────────┐
        │ _combine_final│──► xAI API ──► full changelog
        └──────────────┘

If > 5 sub-summaries (> 200 commits):

  10 sub-summaries
    ├─ pair 1+2 ──► _combine_intermediate ──► compact bullets
    ├─ pair 3+4 ──► _combine_intermediate ──► compact bullets
    ├─ pair 5+6 ──► _combine_intermediate ──► compact bullets
    ├─ pair 7+8 ──► _combine_intermediate ──► compact bullets
    └─ pair 9+10 ─► _combine_intermediate ──► compact bullets
                                                    │
                     5 intermediate summaries ◄──────┘
                                │
                                ▼
                         _combine_final ──► full changelog
```

### Weekly Run: Skip vs Regenerate Logic

```
For each branch/month:
  ┌─────────────────────────────────┐
  │ Count commits in commits table  │
  │ for this branch/year/month      │
  └────────────────┬────────────────┘
                   │
                   ▼
  ┌─────────────────────────────────┐     ┌─────────────┐
  │ Summary exists in DB for this   │─NO─►│  Generate    │
  │ branch/year/month?              │     │  new summary │
  └────────────────┬────────────────┘     └─────────────┘
                   │ YES
                   ▼
  ┌─────────────────────────────────┐     ┌─────────────┐
  │ Stored commit_count ==          │─NO─►│  Regenerate  │
  │ current commit count?           │     │  (new commits│
  └────────────────┬────────────────┘     │   detected)  │
                   │ YES                  └─────────────┘
                   ▼
             ┌──────────┐
             │   Skip   │
             └──────────┘
```

## Scenarios

### Scenario 1: Empty Database (First Run)

- **importer.py**: Clones vmware/photon from scratch. Checks out each of
  the 6 branches, runs `git rev-list` to enumerate all commits since
  2021-01-01, parses each commit via `git show`, and inserts into the
  `commits` table. Typically imports ~16,000+ commits across all branches.
- **summarizer.py**: No summaries exist in the `summaries` table. Every
  branch/month combination is generated. For 6 branches x ~60 months each,
  this produces ~350 summaries requiring ~350+ xAI API calls (plus combine
  calls for high-commit months). Runtime: many hours.

### Scenario 2: Existing Database (Weekly Re-run, Mid-month)

- **importer.py**: The repo clone already exists. Runs `git fetch --all`,
  checks out each branch, and imports only new commits not yet in the DB
  (uses `INSERT OR IGNORE` on the unique `(branch, commit_hash)` index).
  Typically imports only a handful of new commits.
- **summarizer.py**: For each branch/month, compares the current commit
  count from the `commits` table against the stored `commit_count` in the
  `summaries` table. Completed past months are skipped (commit count
  unchanged). The **current month** is regenerated because new commits
  were imported, so the stored count no longer matches. Only 1-6 API
  generation cycles run (one per branch for the current month).

### Scenario 3: Up-to-date Database (No New Commits)

- **importer.py**: Fetches from remote, finds zero new commits. No DB
  writes occur.
- **summarizer.py**: Every branch/month has a summary whose `commit_count`
  matches the current commit count. All months are skipped. Runtime:
  under 10 seconds with zero API calls.

## Team Members

### Core Droids

1. **docs-blogger-blogger** - Invokes both skills, validates output
2. **docs-blogger-pr-bot** - Pull request creation via git/gh CLI
3. **docs-blogger-orchestrator** - Delegates to blogger and pr-bot, enforces quality gates

### Skills

1. **photon-import** (`/photon-import`) - Clone/update vmware/photon repo, import commits into SQLite
2. **photon-summarize** (`/photon-summarize`) - Generate Hugo blog posts from commit DB via xAI/Grok API

## Workflow

```
orchestrator
  → delegates to blogger droid
      → invokes photon-import skill (ensure fresh DB)
      → invokes photon-summarize skill (generate posts)
      → validates output
  → delegates to pr-bot droid (production mode)
      → creates PR against dcasota/photon photon-hugo branch
```

## Key Responsibilities

- **Repository Analysis**: Clone and analyze vmware/photon across all branches
- **Monthly Summaries**: Generate comprehensive monthly development summaries
- **Branch Coverage**: All active branches (3.0, 4.0, 5.0, 6.0, common, master)
- **Incremental Updates**: Only regenerate months where commit count changed
- **Technical Analysis**: Deep dive into commits, security updates, user impact
- **Content Generation**: Hugo-compatible blog posts with proper front matter
- **Production Deployment**: Pull requests for photon-hugo branch

## Branch Coverage

All 6 branches, monthly summaries from 2021 to present:
- **3.0**, **4.0**, **5.0**, **6.0**, **common**, **master**

## Quality Requirements

- **Technical Accuracy**: All commit hashes and CVE IDs verifiable
- **Comprehensive Coverage**: Every meaningful change documented
- **User Focus**: Changes explained from user perspective
- **Actionable Content**: Clear recommendations provided
- **Hugo Integration**: Proper front matter (`title`, `date`, `author`, `tags`, `categories`, `summary`)
- **Deterministic Validation**: PostToolUse hook enforces front matter completeness
- **Changelog Sections**: TL;DR, Action Required, Security, Added, Changed, Fixed, Removed, Contributors

## Execution Modes

### Live Testing Mode
- Default mode; validates content locally
- No PRs created

### Production Mode
- Targets dcasota/photon repository (photon-hugo branch)
- Creates pull requests for integration

## Standalone Usage

The Python scripts remain fully usable outside Factory:

```bash
# Import commits (first run or update)
python3 importer.py --db-path photon_commits.db --repo-dir photon

# Import commits with more specifications
python3 importer.py --db-path photon_commits.db --repo-dir photon \
  --branches 3.0 4.0 5.0 6.0 common master --since-date 2021-01-01

# Check DB status
python3 importer.py --db-path photon_commits.db --check

# Generate summaries (skip months already up-to-date)
XAI_API_KEY=your-key python3 summarizer.py --db-path photon_commits.db --output-dir content/blog --debug

# Force regenerate a specific month
XAI_API_KEY=your-key python3 summarizer.py \
  --db-path photon_commits.db --branches 5.0 --months 2022-05 --force --debug

# Export all DB summaries to disk without API calls
python3 summarizer.py --db-path photon_commits.db --export

# Check DB/disk sync status
python3 summarizer.py --db-path photon_commits.db --sync-check
```

### Summarizer CLI Flags

| Flag | Default | Description |
|------|---------|-------------|
| `--db-path` | `photon_commits.db` | Path to SQLite database |
| `--output-dir` | `content/blog` | Output directory for blog posts |
| `--branches` | all 6 | Branches to summarize |
| `--since-year` | 2021 | Start year |
| `--months` | all | Specific month range `YYYY-MM:YYYY-MM` |
| `--model` | `grok-4-0709` | xAI model identifier |
| `--force` | off | Regenerate even if summary is current |
| `--debug` | off | Verbose debug logging with timestamps |
| `--api-timeout` | 7200 | Timeout per API call in seconds |
| `--combine-max-tokens` | 16384 | Max tokens for the combine step |
| `--check` | off | Report summaries status (no API calls) |
| `--export` | off | Export DB summaries to files (no API calls) |
| `--sync-check` | off | Compare DB vs disk content |

## Factory Usage

```
factory run @docs-blogger-orchestrator
factory run @docs-blogger-blogger
factory run @docs-blogger-pr-bot
```

Or invoke skills directly:
```
/photon-import
/photon-summarize
```

## Success Criteria

- **100% Branch Coverage**: All 6 branches documented
- **100% Month Coverage**: No missing months from 2021-present
- **Verified Accuracy**: All technical references verifiable
- **User Comprehension**: Technical complexity explained clearly
- **Production Integration**: Seamless Hugo deployment
