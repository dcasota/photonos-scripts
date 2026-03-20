# .factory/commands/generate-missing-blogs.md

## Generate All Missing Blog Posts

Batch-generate all missing monthly blog posts across every Photon OS
branch using the `photon-summarize` skill. This is a convenience wrapper
that covers the full date range (2021 to present) with resumability.

### Prerequisites

- `photon_commits.db` must exist and be populated (run `photon-import` first)
- `XAI_API_KEY` environment variable must be set

### Usage

```bash
cd $HOME/photonos-scripts/docsystem
export XAI_API_KEY="your-key"
./generate_all_missing.sh
```

### What It Does

1. Invokes `summarizer.py` for each branch with predefined month ranges
2. Tracks completed batches in `/tmp/generate_missing_batches_completed.txt`
3. Logs progress to `/tmp/generate_missing_blog_posts.log`
4. Continues on per-batch failure (no single failure aborts the run)
5. Prints a final summary of all summaries in the database

### Branches and Ranges

| Branch | Date Range |
|--------|------------|
| 3.0 | 2022-06 to 2025-12 |
| 4.0 | 2021-01 to 2023-12, 2024-06 to 2026-01 |
| 5.0 | 2021-01 to 2023-12, 2024-05 to 2026-01 |
| 6.0 | 2021-01 to 2024-12, 2025-04 to 2025-12 |
| common | 2021-01 to 2025-12 |
| master | 2021-01 to 2024-12 |

### Resumability

The script checkpoints each completed batch. If interrupted, re-running
the script skips already-completed batches. To force a full re-run,
delete `/tmp/generate_missing_batches_completed.txt`.

### Related

- Skill: `.factory/skills/photon-summarize/SKILL.md`
- Skill: `.factory/skills/photon-import/SKILL.md`
- Droid: `@docs-blogger-blogger` (AI-driven alternative)

## Run via Droids

@docs-blogger-orchestrator Generate monthly blog summaries
@docs-blogger-blogger Generate monthly blog posts
