# Upstream Dependency Scanner Quality Rubric

## Purpose

This rubric defines pass/fail criteria for the upstream dependency scanner pipeline output. Every scan run must satisfy all MUST criteria. SHOULD criteria are recommended but non-blocking.

---

## Scanner Output Quality

### MUST (Fail the run if violated)

| # | Criterion | Validation |
|---|-----------|------------|
| S1 | `depfix-manifest-{branch}-{timestamp}.json` is produced for every scanned branch | File exists and is non-empty |
| S2 | Manifest JSON is well-formed and parseable | `json.loads()` succeeds without error |
| S3 | Manifest validates against `depfix-manifest-schema.json` | JSON Schema validation passes |
| S4 | `metadata.branch` matches the `--branch` argument | Exact string match |
| S5 | `metadata.specs_scanned` is > 0 for non-empty SPECS directories | Integer > 0 |
| S6 | Every `patched_specs[].additions[]` entry has non-empty `type`, `value`, `evidence` | All three fields are non-empty strings |
| S7 | Every `patched_specs[].additions[].severity` is one of `critical`, `important`, `informational` | Enum validation |
| S8 | Every `patched_specs[].additions[].source` is one of `go.mod`, `pyproject`, `api-constant`, `tarball`, `spec` | Enum validation |
| S9 | `severity_summary.critical + severity_summary.important + severity_summary.informational` equals total additions count | Sum matches `∑ patched_specs[].additions.length` |
| S10 | No duplicate `(type, value)` pairs within any single `patched_specs[].additions[]` array | Uniqueness check per spec |
| S11a | No weaker `Requires: X >= A` when a stronger `Requires: X >= B` (B > A) exists for the same target | Version-strength consolidation |
| S11b | No weaker `Conflicts: X < A` when a stronger `Conflicts: X < B` (B > A) exists for the same target | Lower-bound consolidation |
| S11c | No `Requires:` entries from SKIP-mapped Go sub-modules (moby/moby/client, moby/moby/api, containerd/containerd/api) | SKIP mapping check |

### SHOULD (Log warning if violated)

| # | Criterion | Notes |
|---|-----------|-------|
| S12 | `specs_patched` matches `patched_specs.length` | Consistency check |
| S13 | `conflicts_detected[]` is present and populated for branches with Docker packages | Empty only if no Docker SDK edges |
| S14 | Manifest file name follows `depfix-manifest-{branch}-{YYYYMMDD_HHMMSS}.json` | Timestamp format validation |
| S15 | All spec paths in manifest are absolute paths | Start with `/` |
| S16 | k8s.io module versions follow v0.X.Y → 1.X convention | `kubernetes >= 1.32` not `kubernetes >= 0.0` |

---

## Patch Generation Quality

### MUST (Fail the run if violated)

| # | Criterion | Validation |
|---|-----------|------------|
| P1 | No duplicate `Requires:` directives in any patched spec file | Parse patched spec, check uniqueness |
| P2 | No duplicate `Conflicts:` directives in any patched spec file | Parse patched spec, check uniqueness |
| P3 | No duplicate `Provides:` directives in any patched spec file | Parse patched spec, check uniqueness |
| P4 | Every patched spec is valid RPM spec syntax | `rpmlint` or `rpmspec -P` succeeds |
| P5 | Every added directive has a corresponding evidence trail in the manifest | `evidence` field is non-empty and describes the source |
| P6 | Patched spec files are placed in `SPECS_DEPFIX/{branch}/{package}/` | Correct directory structure |
| P7 | Changelog entry is appended to every patched spec | `%changelog` section has new entry with date and scanner attribution |
| P8 | Original spec files are never modified | Original paths remain untouched |

### SHOULD (Log warning if violated)

| # | Criterion | Notes |
|---|-----------|-------|
| P9 | Version constraints use `>=` for Requires and `<`/`>` for Conflicts | Consistent constraint style |
| P10 | Evidence field includes the source module path and version | e.g., `"go.mod: github.com/docker/docker v28.5.1"` |
| P11 | Patched specs sorted with Requires before Conflicts before Provides | Consistent ordering |

---

## Security Quality

### MUST (Fail the run if violated)

| # | Criterion | Validation |
|---|-----------|------------|
| SEC1 | Zero calls to `system()`, `popen()` in scanner binary | `nm` or `objdump` check, or `grep -r "system\|popen" src/` |
| SEC2 | No shell injection vectors in external process calls | All `fork()/execlp()` with explicit arg lists |
| SEC3 | All temp files created with `mkstemp()` | `grep -r "mkstemp" src/` confirms; no `mktemp()` or hardcoded paths |
| SEC4 | All temp files cleaned up after use | `ls /tmp/tarball-extract-*` empty after scan |
| SEC5 | Path traversal rejected for `--branch` and `--output-dir` arguments | `strstr(arg, "..")` check in `main.c` |
| SEC6 | Path traversal rejected for package names and spec basenames | Validation in `spec_patcher.c` |
| SEC7 | Integer overflow guards on all `realloc()` operations | `dwNewCap < old` check in `graph.c` |
| SEC8 | All string operations use `snprintf()` with bounded buffers | No `sprintf()`, `strcpy()`, `strcat()` in source |
| SEC9 | No use of deprecated unsafe functions (`gets()`, `scanf()` without width) | Static analysis clean |
| SEC10 | PRN entries with path traversal are rejected | Validation in `prn_parser.c:136` |

### SHOULD (Log warning if violated)

| # | Criterion | Notes |
|---|-----------|-------|
| SEC11 | Build with `-Wall -Wextra -Werror` produces zero warnings | Compiler diagnostics |
| SEC12 | AddressSanitizer run produces zero findings | `-fsanitize=address` |
| SEC13 | Valgrind memcheck produces zero definite leaks | `valgrind --leak-check=full` |

---

## CI Integration Quality

### MUST (Fail the run if violated)

| # | Criterion | Validation |
|---|-----------|------------|
| CI1 | Workflow builds scanner successfully | CMake build exits 0 |
| CI2 | Manifest artifacts uploaded for every scanned branch | Artifacts downloadable post-run |
| CI3 | Missing input directories cause graceful skip, not workflow failure | Exit code 0 with `[Phase Nx] Skipped:` log |
| CI4 | Workflow completes within 120-minute timeout for full 7-branch scan | Wall-clock time < 120 min |

### SHOULD (Log warning if violated)

| # | Criterion | Notes |
|---|-----------|-------|
| CI5 | Per-branch summary statistics in workflow summary | Step summary output |
| CI6 | Patched spec files uploaded as separate artifact | Separate from manifests |
| CI7 | Run duration logged per branch | For performance tracking |
| CI8 | Nightly scheduled run enabled | `schedule` trigger configured |
