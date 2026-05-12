# Tasks — phase-ordered

Tasks are dependency-numbered. Each is small enough for a single commit. Each commit follows the template in `../../CLAUDE.md`.

Legend:
- **FRD** — the FRD this task implements (`../features/FRD-NNN-*.md`)
- **ADR** — the ADR(s) that justify the approach
- **PS-L** — line range in `../../../photonos-package-report.ps1`
- **Parity** — strict / soft / n/a (what the parity harness asserts)

---

## Phase 0 — SDD scaffold

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 000 | Create directory tree (`.claude/agents/`, `specs/{adr,features,tasks}`, `include/`, `src/`, `tools/`, `data/`, `tests/`) | — | — | — | n/a |
| 001 | Write `CLAUDE.md` | — | — | — | n/a |
| 002 | Write `specs/prd.md` (Status: Reviewed) | — | — | — | n/a |
| 003 | Write 11 ADRs (Status: Accepted) | — | ADR-0001…0011 | — | n/a |
| 004 | Write 16 FRD skeletons (Status: Accepted) | FRD-001…016 | various | — | n/a |
| 005 | Write `specs/tasks/README.md` (this file) | — | — | — | n/a |
| 006 | Write `README.md` and `ARCHITECTURE.md` | — | — | — | n/a |
| 007 | Write 7 Claude Code subagent files under `.claude/agents/` | — | ADR-0011 | — | n/a |
| 008 | Add commit-msg git hook under `tools/git-hooks/commit-msg` | — | — | — | n/a |
| 009 | First commit + push branch `sdd/phase-0-scaffold`; open PR | — | — | — | n/a |

**Exit gate**: spec-lint job (FRD ↔ ADR cross-references) passes; PR merged to master.

---

## Phase 1 — Foundation

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 010 | `CMakeLists.txt` scaffold; `tdnf` deps documented | FRD-016 | 0001,0002,0003,0008 | — | n/a |
| 011 | `include/pr_types.h` — `pr_task_t` (22 fields, lower-case canonical) | FRD-002 | 0001 | 247-372 | n/a |
| 012 | `src/params.c` — param parsing (incl. `-UpstreamsExclusionList`) | FRD-001 | 0001 | 83-102 | strict |
| 013 | `src/convert.c` (Convert-ToBoolean), `src/diskspace.c` (Test-DiskSpace) | FRD-001 | 0001 | 111-156 | strict |
| 014 | `src/git_with_timeout.c` (posix_spawn + alarm) | FRD-012 | 0001 | 163-225 | strict |
| 015 | Unit tests for tasks 011-014 | FRD-016 | 0001 | — | strict |

**Exit gate**: `photonos-package-report --help` parses identical to `pwsh -? photonos-package-report.ps1`.

---

## Phase 2 — Spec ingestion

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 020 | `src/spec_value.c` (Get-SpecValue) | FRD-002 | 0001 | 234-245 | strict |
| 021 | `src/parse_directory.c` (ParseDirectory; `scandir` + `alphasort`) | FRD-002 | 0001,0006 | 247-380 | strict |
| 022 | Fixture set: 10 representative SPECs from photon-5.0/SPECS | FRD-016 | — | — | n/a |
| 023 | Parity test: PS `$Packages` JSON dump vs C JSON dump = byte-identical | FRD-016 | 0006 | — | strict |

**Exit gate**: `photonos-package-report --dump-tasks <branch>` matches PS `$Packages | ConvertTo-Json` byte-for-byte on the fixture set.

---

## Phase 3 — Embedded data

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 030 | `tools/extract-source0-lookup.sh` (bash+awk) | FRD-003 | 0005 | 509-1369 | n/a |
| 031 | `tools/escape-c-string.sh` (POSIX shell) | FRD-003 | 0005 | — | n/a |
| 032 | CMake `add_custom_command` to regenerate `source0_lookup_data.h` | FRD-003 | 0005 | — | n/a |
| 033 | `src/source0_lookup.c` — CSV parser → `pr_source0_lookup_t[850]` | FRD-003 | 0001,0005 | 1367-1369 | strict |
| 034 | Roundtrip parity test (PS `ConvertFrom-Csv` dump vs C dump) | FRD-016 | 0006 | — | strict |
| 035 | `tools/extract-spec-hooks.sh` (bash+awk) | FRD-005 | 0007 | scattered | n/a |
| 036 | `tools/spec-hooks-drift-check.sh` + CMake hook | FRD-005 | 0007 | — | n/a |
| 037 | Skeleton `src/check_urlhealth/hooks/<spec>.c` for every detected PS hook (~200 files, each with PS body as comment + TODO marker) | FRD-005 | 0007 | scattered | n/a |

**Exit gate**: Source0LookupData roundtrip parity = strict-green; spec-hooks drift check passes (every PS hook has a C file, every C file has a PS hook).

---

## Phase 4 — Substitution core

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 040 | `src/check_urlhealth/macro_subst.c` — port L 2161-2199 in source order | FRD-004 | 0003,0006 | 2161-2199 | **strict** |
| 041 | `src/check_urlhealth/convert_version.c` (Convert-ToVersion) | FRD-010 | 0001 | 1889-1906 | strict |
| 042 | `src/check_urlhealth/parse_version.c`, `compare_versions.c` | FRD-010 | 0001 | 1745-1888 | strict |
| 043 | `src/clean_version.c`, `src/version_compare.c` (Versioncompare, Clean-VersionNames) | FRD-010 | 0001 | 381-449 | strict |
| 044 | `src/check_urlhealth/int_like.c`, `highest_jdk.c` | FRD-010 | 0001 | 1638-1744 | strict |
| 045 | Hand-write the ~200 `hook_*.c` translations | FRD-005 | 0007 | scattered | strict |
| 046 | 1100-SPEC dry-run gate: PS-vs-C diff of "modified Source0" for every SPEC in photon-5.0 = strict-green | FRD-016 | 0006 | — | **strict** |

**Exit gate**: substitution-only parity is strict-green across all photon-5.0 SPECs. *This is the gate that catches regressions like the `%{version}` failure of 2026-05-11.*

---

## Phase 5 — Network & lookups

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 050 | `src/http_client.c` — libcurl wrapper (HEAD/GET, redirects, per-host UA + Referer) | FRD-006 | 0002 | n/a | strict on URL, soft on status |
| 051 | `src/urlhealth.c` — port L 1458-1518 verbatim | FRD-006 | 0002 | 1458-1518 | soft (status), strict (string) |
| 052 | `src/koji_lookup.c` — port L 1520-1572 | FRD-009 | 0002 | 1520-1572 | soft (status), strict (string) |
| 053 | `src/check_urlhealth/github_tags.c` — GitHub tag detection sub-section | FRD-007 | 0002 | within 1574-4920 | strict (name) |
| 054 | `src/check_urlhealth/gitlab_tags.c` — GitLab tag detection sub-section | FRD-008 | 0002 | within 1574-4920 | strict (name) |
| 055 | Parity gate: `$NameLatest`, `$UpdateDownloadName`, `$UpdateURL` string outputs identical to PS for fixture set | FRD-016 | 0006 | — | strict |

**Exit gate**: phase-5 fixture run matches PS strings byte-for-byte (HTTP statuses are soft-diffed).

---

## Phase 6 — CheckURLHealth main path

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 060 | `src/check_urlhealth/check_urlhealth.c` — translates L 1574-4920 section-by-section | FRD-011 | 0001,0007 | 1574-4920 | strict |
| 061 | `src/check_urlhealth/output_row.c` — `.prn` row assembly matching L 4918 | FRD-014 | 0006 | 4918 | strict |
| 062 | Phase-6 gate: 1100-SPEC fixture run; all 12 columns strict-identical except cols 4 and 7 | FRD-016 | 0006 | — | strict |

**Exit gate**: full single-threaded fixture-set parity green.

---

## Phase 7 — Cluster + parallelisation

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 070 | `src/git_photon.c` (GitPhoton) | FRD-012 | 0001 | 451-506 | strict |
| 071 | `src/generate_urlhealth_reports.c` (top-level orchestrator) | FRD-015 | 0004 | 4935-end | strict |
| 072 | `src/parallel.c` — 20-thread pool; `scandir`+`alphasort` ordering; single writer thread; flock-protected appends | FRD-013 | 0004,0010 | 4995-5097 | strict |
| 073 | End-to-end parity gate: single-branch (5.0) full run; cached HTTP; strict-green | FRD-016 | 0006 | — | strict |

**Exit gate**: end-to-end branch-5.0 parity strict-green.

---

## Phase 8 — Side-by-side CI

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 080 | Modify `.github/workflows/package-report.yml`: run PS, then C, then diff | FRD-016 | 0009 | n/a | n/a |
| 081 | `tools/parity-diff.sh` finalised; writes step-summary verdict | FRD-016 | 0006,0009 | n/a | n/a |
| 082 | `tools/parity-journal.tsv` append; `tools/parity-gate.sh` 30/60/90-day timeline logic | FRD-016 | 0009 | n/a | n/a |
| 083 | First three runs all soft-green; commit to start the clock | FRD-016 | 0009 | n/a | soft |

**Exit gate**: the 90-day clock starts ticking.

---

## Phase 9 — Retirement

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| 090 | After 90 consecutive strict-green days: PR to move `photonos-package-report.ps1` → `staging/legacy/` and rewire workflow to C-only | — | 0009 | n/a | strict |
| 091 | All specs flipped to `Status: Implemented` | — | — | n/a | n/a |
| 092 | Update root README to point new contributors at the C app | — | — | n/a | n/a |

**Exit gate**: PS script archived; C app is the sole producer of `.prn`.

---

## Risk register (cross-phase)

| Risk | Phase | Mitigation |
|---|---|---|
| `%{version}` regression of 2026-05-11 — parallel-runspace state leak — recurs in C | 4, 7 | FRD-013 mandates per-thread state isolation; FRD-016 gates Phase 4 strictly |
| PS-side hook changes during the port window | 3, 4 | `spec-hook-extractor` drift check at every CMake configure |
| HTTP-status flapping | 5, 6 | Cols 4, 7 are soft-diffed |
| Sort-order divergence (locale) | 7 | `setlocale(LC_ALL, "C")` at startup |
| `flock` advisory-only semantics | 7 | Single writer thread is the primary guard; flock is the cross-process backup |
| Embedded CSV growing | 3 | `extract-source0-lookup.sh` re-runs on PS mtime change; parity test catches drift |
| 200 hand-written hooks: human error | 4 | Each hook has a PS-source comment + per-hook unit test against a captured PS trace |
| Parity journal corruption | 8 | Journal is append-only TSV; `parity-gate.sh` validates structure on every run |

---

## How a typical task PR looks

1. Read the relevant FRD + ADRs.
2. Implement the change in one or a few small commits.
3. Each commit message uses the template in `../../CLAUDE.md`.
4. Run `tools/parity-diff.sh` locally (once the harness exists).
5. Open PR; CI runs spec-lint + (after Phase 8) parity-gate.
6. Merge after review; update the FRD's Status if the task closes it.
