# Task 001 — Project Packaging

| Field | Value |
|-------|-------|
| **Status** | Pending |
| **Phase** | 1 — Core Infrastructure |
| **Dependencies** | — |
| **PRD Refs** | PRD §2 (Project Structure), §5 (Testing) |

## Description

Bootstrap the docsystem project with modern Python packaging. Add a
`pyproject.toml` at the repository root that defines the `docsystem` package,
pins runtime dependencies, and configures pytest for the new `tests/` directory.
Include a `.gitignore` tailored to docsystem artifacts.

## Acceptance Criteria

- [ ] `pyproject.toml` exists with `[project]` metadata (name, version, description, python-requires ≥ 3.10)
- [ ] Runtime dependencies pinned: `requests`, `beautifulsoup4`, `language-tool-python`, `tqdm`, `Pillow` (optional extra)
- [ ] `[project.optional-dependencies]` section for dev tools: `pytest`, `ruff`, `mypy`
- [ ] `tests/` directory created with `conftest.py` and a trivial smoke test
- [ ] `pytest.ini` or `[tool.pytest.ini_options]` configured in pyproject.toml
- [ ] `.gitignore` covers: `*.pyc`, `__pycache__/`, `.pytest_cache/`, `photon_commits.db`, `*.egg-info/`
- [ ] `pip install -e .` succeeds in a clean venv

## Implementation Notes

- Use `[build-system] requires = ["setuptools>=68"]` with setuptools backend.
- Keep Pillow optional because not all environments need image processing.
- The smoke test can simply assert `import docsystem` succeeds.
- Coordinate with task 002 for any schema-related test fixtures.
