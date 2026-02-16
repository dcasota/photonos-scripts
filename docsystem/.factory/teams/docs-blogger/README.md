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
  hooks/
    validate_hugo_frontmatter.py  # PostToolUse hook: front matter validation
  settings.json                   # Hook registration
```

### Data Flow

```
importer.py (photon-import skill)
    ↓ populates
photon_commits.db (SQLite)
    ↓ consumed by
summarizer.py (photon-summarize skill)
    ↓ produces
content/blog/YYYY/MM/photon-<branch>-monthly-YYYY-MM.md
    ↓ validated by
validate_hugo_frontmatter.py (PostToolUse hook)
    ↓ committed by
docs-blogger-pr-bot (droid)
```

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
- **Technical Analysis**: Deep dive into commits, PRs, security updates, user impact
- **Content Generation**: Hugo-compatible blog posts with proper front matter
- **Production Deployment**: Pull requests for photon-hugo branch

## Branch Coverage

All 6 branches, monthly summaries from 2021 to present:
- **3.0**, **4.0**, **5.0**, **6.0**, **common**, **master**

## Quality Requirements

- **Technical Accuracy**: All commit hashes and PR numbers verifiable
- **Comprehensive Coverage**: Every meaningful change documented
- **User Focus**: Changes explained from user perspective
- **Actionable Content**: Clear recommendations provided
- **Hugo Integration**: Proper front matter (`title`, `date`, `author`, `tags`, `categories`, `summary`)
- **Deterministic Validation**: PostToolUse hook enforces front matter completeness

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
# Import commits
python3 importer.py --db-path photon_commits.db --repo-dir photon --since-date 2021-01-01

# Check DB status
python3 importer.py --db-path photon_commits.db --check

# Generate summaries
XAI_API_KEY=your-key python3 summarizer.py --db-path photon_commits.db --output-dir content/blog
```

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
