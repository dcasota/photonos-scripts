# Architecture

This document captures the design of the C port and the canonical mapping between PowerShell functions and C translation units. Every entry below traces back to a PS line range in `../photonos-package-report.ps1`.

---

## Data flow

```
                ┌────────────────────────────────────────┐
                │  CLI: photonos-package-report <args>   │
                │  src/main.c + src/params.c (PS L 83)   │
                └──────────────┬─────────────────────────┘
                               │
              ┌────────────────▼─────────────────────┐
              │  Pre-flight: Test-DiskSpace, mkdirs  │
              │  src/diskspace.c (PS L 133)          │
              └────────────────┬─────────────────────┘
                               │
              ┌────────────────▼──────────────────────┐
              │  GitPhoton: clone/fetch reports/      │
              │  src/git_photon.c (PS L 451)          │
              │  → produces $WorkingDir/photon-<rel>/ │
              └────────────────┬──────────────────────┘
                               │
       ┌───────────────────────▼───────────────────────┐
       │  Per-branch loop                              │
       │  src/generate_urlhealth_reports.c (PS L 4935) │
       └───┬───────────────────────────────────────────┘
           │
           ▼
   ┌──────────────────────────────────┐
   │  ParseDirectory                  │
   │  src/parse_directory.c (PS L 247)│
   │  → pr_task_t[] (scandir+alphasort)
   └─────────────┬────────────────────┘
                 │
                 ▼
   ┌──────────────────────────────────────────────────┐
   │  pthread pool, 20 workers (ADR-0004)             │
   │  src/parallel.c                                  │
   │  feeds CheckURLHealth per pr_task_t              │
   └─────────────┬────────────────────────────────────┘
                 │
       ┌─────────▼──────────────────────────────────┐
       │  CheckURLHealth (PS L 1574-4920)           │
       │  src/check_urlhealth/check_urlhealth.c     │
       │  + ~200 hooks under check_urlhealth/hooks/ │
       │  + macro_subst.c + parse_version.c +       │
       │    compare_versions.c + github_tags.c +    │
       │    gitlab_tags.c + ...                     │
       └─────────┬──────────────────────────────────┘
                 │
                 ▼
       ┌──────────────────────────────────┐
       │  output_row → row queue          │
       │  src/check_urlhealth/output_row.c│
       └─────────┬────────────────────────┘
                 │
                 ▼
       ┌──────────────────────────────────────┐
       │  Single writer thread (ADR-0010)     │
       │  → .prn file (flock-protected)       │
       │  → post-branch alphabetical sort     │
       └──────────────────────────────────────┘
```

## Canonical PS-to-C mapping

| PS function | PS lines | C translation unit | FRD |
|---|---|---|---|
| `Convert-ToBoolean` | 111-122 | `src/convert.c` | FRD-001 |
| `Test-DiskSpace` | 133-156 | `src/diskspace.c` | FRD-001 |
| `Invoke-GitWithTimeout` | 163-225 | `src/git_with_timeout.c` | FRD-012 |
| `Get-SpecValue` | 234-245 | `src/spec_value.c` | FRD-002 |
| `ParseDirectory` (Get-AllSpecs) | 247-380 | `src/parse_directory.c` | FRD-002 |
| `Versioncompare` | 381-437 | `src/version_compare.c` | FRD-010 |
| `Clean-VersionNames` | 439-449 | `src/clean_version.c` | FRD-010 |
| `GitPhoton` | 451-506 | `src/git_photon.c` | FRD-012 |
| `Source0Lookup` (CSV embed) | 508-1369 | `src/source0_lookup.c` + generated `source0_lookup_data.h` | FRD-003 |
| `ModifySpecFile` | 1371-1456 | `src/modify_spec.c` | FRD-011 |
| `urlhealth` | 1458-1518 | `src/urlhealth.c` (uses libcurl wrapper in `src/http_client.c`) | FRD-006 |
| `KojiFedoraProjectLookUp` | 1520-1572 | `src/koji_lookup.c` | FRD-009 |
| `CheckURLHealth` (top-level) | 1574-4920 | `src/check_urlhealth/check_urlhealth.c` + subdir | FRD-011 |
| ↳ `Get-HighestJdkVersion` (nested) | 1638-1735 | `src/check_urlhealth/highest_jdk.c` | FRD-010 |
| ↳ `Test-IntegerLike` (nested) | 1737-1744 | `src/check_urlhealth/int_like.c` | FRD-010 |
| ↳ `Parse-Version` (nested) | 1745-1802 | `src/check_urlhealth/parse_version.c` | FRD-010 |
| ↳ `Compare-VersionStrings` (nested) | 1803-1888 | `src/check_urlhealth/compare_versions.c` | FRD-010 |
| ↳ `Convert-ToVersion` (nested) | 1889-1906 | `src/check_urlhealth/convert_version.c` | FRD-010 |
| ↳ `Get-LatestName` (nested) | 1907-1951 | `src/check_urlhealth/get_latest_name.c` | FRD-007, FRD-008 |
| ↳ `Get-FileHashWithRetry` (nested) | 1952-1999 | `src/check_urlhealth/file_hash.c` | FRD-011 |
| ↳ `Wait-ForFetchCompletion` (nested) | 2000-2056 | `src/check_urlhealth/wait_fetch.c` | FRD-013 |
| Per-spec override `if ($currentTask.spec -ilike 'X.spec')` blocks | scattered | `src/check_urlhealth/hooks/<spec>.c` (~200 files, generated dispatch) | FRD-005 |
| `GenerateUrlHealthReports` | 4935-end | `src/generate_urlhealth_reports.c` | FRD-015 |
| Parallel runspace dispatch | 4995-5097 | `src/parallel.c` (pthread pool) | FRD-013 |
| `.prn` row assembly | 4918 | `src/check_urlhealth/output_row.c` | FRD-014 |

## Threading model (ADR-0004 + ADR-0010)

- 1 main thread: param parsing, pre-flight, branch loop sequencing.
- 1 producer (the main thread): pushes `pr_task_t *` onto a bounded MPMC queue per branch.
- **20 worker threads**: each pulls tasks, runs `CheckURLHealth`, pushes resulting `.prn` rows onto a per-worker SPSC ring.
- 1 writer thread: drains all 20 SPSC rings; serialises `.prn` writes; per-branch end-of-batch sort.

Per-thread state isolation:
- Each worker owns: its `CURL *`, its compiled `pcre2_code *` cache, its scratch buffers, its `pr_task_t`-local mutations.
- No worker reads or writes another worker's state.
- Read-only shared state (parsed `pr_source0_lookup_t[]`, the spec-hook dispatch table, the command-line params) is initialised before workers start.

## Build graph (ADR-0005)

```
photonos-package-report.ps1
         │
         ▼
tools/extract-source0-lookup.sh ──▶ source0_lookup.csv (build dir)
         │
         ▼
tools/escape-c-string.sh  ──▶ source0_lookup_data.h (build dir)
         │
         ▼
src/source0_lookup.c (includes the generated header)

photonos-package-report.ps1
         │
         ▼
tools/extract-spec-hooks.sh ──▶ src/check_urlhealth/pr_spec_dispatch.h
         │
         ▼
src/check_urlhealth/hooks/<spec>.c (one per detected hook)
```

CMake `add_custom_command` re-runs the extractors whenever `../photonos-package-report.ps1` mtime changes.

## Module DAG

```
main → params → diskspace → git_photon → generate_urlhealth_reports
                                                   │
                                                   ▼
                                 parallel ─────▶ check_urlhealth/check_urlhealth
                                                   │  ├─ macro_subst
                                                   │  ├─ urlhealth ──▶ http_client
                                                   │  ├─ github_tags, gitlab_tags
                                                   │  ├─ koji_lookup
                                                   │  ├─ {parse,compare,convert}_version
                                                   │  ├─ highest_jdk, int_like
                                                   │  ├─ hooks/<spec> (~200)
                                                   │  └─ output_row
                                                   ▼
                                           single writer thread → .prn
```

## Parity harness (ADR-0006 + ADR-0009)

```
PS run            C run
  │                 │
  ▼                 ▼
.prn (P)        .prn (C)
  │                 │
  └───────┬─────────┘
          ▼
tools/parity-diff.sh
  ├─ strip volatile cols 4, 7
  ├─ sort both
  ├─ byte-diff
  └─ emit verdict + append to tools/parity-journal.tsv
          │
          ▼
tools/parity-gate.sh (soft / strict-warning / strict-failure based on days-since-clock-start)
```

## What this document is NOT

- Not an API reference (the C code's headers are).
- Not a tutorial (the README + each FRD cover that).
- Not a status tracker (see `specs/tasks/README.md`).
