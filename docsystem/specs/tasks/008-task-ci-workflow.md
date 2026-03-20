# Task 008 — CI Workflow

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 3 — New Capabilities |
| **Dependencies** | 001, 005 |
| **PRD Refs** | PRD §14 (CI/CD), §5 (Testing) |

## Description

Create a GitHub Actions workflow for the docsystem project. The workflow
should run lint, type-checking, and unit tests on every push/PR, with an
additional manually-triggered job for blog generation. Support self-hosted
runners following the pattern established in `vCenter-CVE-drift-analyzer`.

## Acceptance Criteria

- [ ] `.github/workflows/docsystem-ci.yml` created
- [ ] `lint` job: runs `ruff check` and/or `flake8` on `src/` and `tests/`
- [ ] `typecheck` job: runs `mypy src/` with strict mode
- [ ] `test` job: runs `pytest tests/ -v --tb=short` with coverage reporting
- [ ] `blog-gen` job: manually triggered via `workflow_dispatch`, runs summarizer export
- [ ] All jobs use `runs-on: self-hosted` with fallback to `ubuntu-latest`
- [ ] Python version matrix: 3.10, 3.11, 3.12
- [ ] Secrets handled via `${{ secrets.XAI_API_KEY }}` for blog-gen job only
- [ ] Workflow badge added to project README

## Implementation Notes

- Reference `vCenter-CVE-drift-analyzer/.github/workflows/` for self-hosted runner config.
- Use `actions/setup-python@v5` and `actions/cache@v4` for pip caching.
- The `blog-gen` job should only run on `workflow_dispatch` to avoid accidental API usage.
- Coverage reports can use `pytest-cov` with `--cov=src/docsystem --cov-report=xml`.
- Consider a `concurrency` group to prevent parallel blog-gen runs.
