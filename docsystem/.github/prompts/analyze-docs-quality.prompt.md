---
mode: agent
description: Run full documentation quality analysis using the docs-lecturer tool
tools: [filesystem, playwright]
---

# Analyze Documentation Quality

## Prerequisites

- Photon OS documentation site running at `http://127.0.0.1/photon/docs/`
- Python dependencies installed: requests, beautifulsoup4, language-tool-python, tqdm

## Workflow

1. Run the docs-lecturer crawler with all detections enabled:
   ```bash
   python3 tools/photonos-docs-lecturer/photonos-docs-lecturer.py \
     --url http://127.0.0.1/photon/docs/ \
     --depth unlimited \
     --output-csv reports/docs-audit.csv \
     --detect-all
   ```

2. Review the CSV report for issues by severity:
   - **Critical**: Broken links, orphan pages
   - **High**: Heading hierarchy violations, markdown artifacts
   - **Medium**: Grammar/spelling, Flesch score < 80
   - **Low**: Missing alt text, style inconsistencies

3. Generate summary statistics:
   - Total pages crawled
   - Issues by type and severity
   - Overall grammar compliance rate
   - Pages below Flesch readability threshold

## Quality Targets

- [ ] Grammar compliance: >95%
- [ ] Broken links: 0
- [ ] Flesch readability: >80 on all pages
- [ ] Heading hierarchy violations: 0
- [ ] Orphan pages: 0
