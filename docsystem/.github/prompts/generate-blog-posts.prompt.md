---
mode: agent
description: Generate monthly Hugo blog posts from Photon OS commit history
tools: [filesystem]
---

# Generate Blog Posts

## Workflow

1. Verify `photon_commits.db` is populated:
   ```bash
   python3 .factory/skills/photon-import/importer.py --db-path photon_commits.db --check
   ```
   If any branch count is 0, run the import first.

2. Generate all missing blog posts:
   ```bash
   XAI_API_KEY="$XAI_API_KEY" python3 .factory/skills/photon-summarize/summarizer.py \
     --db-path photon_commits.db \
     --output-dir content/blog \
     --branches 3.0 4.0 5.0 6.0 common master \
     --since-year 2021
   ```

3. Validate output:
   - JSON manifest shows `errors: []`
   - All generated files have valid Hugo frontmatter
   - No duplicate posts for the same branch/month

4. Check DB-to-file sync:
   ```bash
   python3 .factory/skills/photon-summarize/summarizer.py --db-path photon_commits.db --sync-check
   ```

## Quality Checklist

- [ ] All branches covered (3.0, 4.0, 5.0, 6.0, common, master)
- [ ] Hugo frontmatter includes: title, date, author, tags, categories, summary
- [ ] Keep-a-Changelog sections present (TL;DR, Security, Added, Changed, Fixed)
- [ ] AI disclaimer footer present on all generated posts
- [ ] No API errors in generation output
