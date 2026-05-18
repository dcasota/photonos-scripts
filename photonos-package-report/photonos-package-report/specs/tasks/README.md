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

## Phase M — Maintainer ops mirrors

Small user-facing PS features that land after the linear 0-9 stream
get mirrored here. Numbered M01…Mnn, independent of the numeric
phase task ids. Each task lands in a single PR alongside an FRD
amendment (or new FRD if scope warrants).

| Task | Subject | FRD | ADR | PS-L | Parity |
|---|---|---|---|---|---|
| M01 | Mirror PS PR #84: extend `-UpstreamsExclusionList` to skip clone creation in C (`pr_should_skip_clone` + guard at `check_urlhealth.c:107-115`) | FRD-012 | 0001,0006 | 2369-2392, 3659-3679, 4014-4034 | strict |
| M02 | Multi-branch dispatcher in `main.c` so the 7 `-GeneratePh*URLHealthReport` flags actually drive iteration (was silently dropped, causing parity-journal strict-fails) | FRD-015 | 0001 | 5040-5215 | strict |
| M03 | `generate_urlhealth_main` prefixes `photon-` when constructing the on-disk SPECS path + clone_root (matches PS L 461, L 5304). Without this, M02's bare-tag branches hit `parse_directory: SPECS path not a directory`. | FRD-015 | 0001 | 461, 5304 | strict |
| M04 | `do_clone` switches to `--no-checkout --filter=blob:none` partial clone (10-100× speedup for big repos: llvm-project, dotnet/runtime, elasticsearch). Mask `github_token` / `gitlab_freedesktop_org_token` in main.c param echo, drop `-github_token` CLI arg in workflow (was leaking to ps(1) on the runner). | FRD-012 | 0001,0006 | n/a | strict |
| M05 | C-side `.prn` upload as workflow artifact in `package-report-C.yml`. Today the runner cleans `_temp/` at job end and the C-side `.prn` is lost, blocking post-hoc strict-diff investigation. Acceptance: `gh run download <id> -n c-side-prn-<id>` returns 7 files. **Implemented** in workflow YAML; smoke-test pending next workflow_dispatch. | FRD-017 | 0006 | n/a | n/a |
| M06 | Diff-analysis baseline. Run C binary against snapshot SHAs locally, run `diff_analyzer.py` per branch, ship 7 markdown files under `docs/prn-analysis/diff-c-vs-ps-photon-<branch>.md`. Buckets specs by column-set signature with sample values. | FRD-017 | 0006 | n/a | n/a |
| M07 | Per-bucket convergence loop (parent task; spawns Mxx subtasks). Iterates the priority list in [`TODO.md`](../../../../TODO.md) §3. Each bucket = one PR following the 9-step recipe (read bucket → trace to source → fix direction per CLAUDE.md invariant 2 → spec → implement → smoke test → PR → parity-gate → merge). | FRD-011, FRD-014 | 0006 | varies | strict |
| M08 | `%{version}` substitution cut: mirror PS L 2111-2119 to strip the trailing `-release` from `task->Version` before substitution (with dot-suffix preservation for Photon dist tags). Fixes the dominant ~550-spec-per-branch diff signature `Source0_modified,UpdateAvailable,UpdateURL,SHAName,UpdateDownloadName`. Smoke: 946 of 1034 photon-4.0 specs now have matching col-3 vs ~2 before. | FRD-011 | 0006 | 2111-2119 | strict |
| M09 | ftp.gnu.org → ftp.funet.fi mirror rewrite post-substitution (PS L 2343-2346). Affects ~50 specs/branch using GNU FTP. Confirmed byte-exact match for autoconf-archive. | FRD-011 | 0001,0006 | 2343-2346 | strict |
| M10 | UpdateAvailable comparison branches: emit `(same version)` when latest==spec, emit warning when latest<spec (PS L 2538-2553). Also fix the compare to use `state.version` (cut form) instead of `task->Version` (X-Y form) — otherwise tomcat9-style packages with Release suffix never match "same". Buckets affected: `UpdateAvailable` (62 specs/4.0) and `UpdateAvailable,warning` (25 specs/4.0). | FRD-011 | 0001,0006 | 2538-2553 | strict |
| M11 | UpdateDownloadName post-processing (PS L 4770 + L 4782-4783): leading `v` strip (when 2nd char is not `-`), and `<task.Name>-` prefix when the extension-stripped basename has no alpha char. Targets bucket `UpdateDownloadName` (113 specs/4.0, sample XML-Parser: PS=`XML-Parser-2.58.tar.gz`, C=`2.58.tar.gz`). Per-spec exceptions (inih, open-vm-tools, samba-client, httpd-mod_jk) remain in `src/hooks/*.c`; Release_/Rel_/v- branches not yet ported. | FRD-014 | 0001,0006 | 4755-4793 | strict |
| M12 | Gate UpdateURL / HealthUpdateURL / UpdateDownloadName / SHA computation on rc==1 (newer version detected). PS L 2538-2553: when `(same version)` or warning fires, those columns stay empty; C was populating them unconditionally. Targets bucket `UpdateURL,SHAName,UpdateDownloadName` (33 specs/4.0, sample apr-util — PS has all empty when UpdateAvailable=`(same version)`, C had them filled). | FRD-011 | 0001,0006 | 2538-2553 | strict |
| M13 | Per-spec warning table (PS L 4442-4519, ~70 entries across 6 categories): "repo isn't maintained", "Cannot detect correlating tags" (gated on empty UpdateAvailable), "duplicate of python-pam.spec", "Info: VMware internal URL", "Source0 seems invalid", "static version number". New module `src/spec_warnings.c` + header. Wired in check_urlhealth after the rc/UpdateAvailable branches. Affects ~50 specs/4.0 across multiple buckets (warning-only, warning combinations). | FRD-014 | 0001,0006 | 4442-4519 | strict |
| M14 | `.prn` row sort: switch from `strcmp` (case-sensitive ASCII; capitals first) to `strcasecmp` (case-insensitive) to mirror PS L 5476 `Sort-Object Spec, SubRelease -Unique`. PS-side row order was lowercase-first (`abseil-cpp`, `acl`, ...); C-side was uppercase-first (`GConf`, `ImageMagick`, ...). The row-position mismatch made `parity-diff.sh` (which compares line-by-line at the same row index) flag nearly every row as strict even when content was identical. Validated: strict_rows dropped 13-25% per branch (e.g. 4.0: 1032 → 841). | FRD-014 | 0006 | 5476 | strict |
| M15 | Blank `state.Source0` when `UpdateAvailable==""` AND `urlhealth!=200` (PS L 4527). Signals "tried and couldn't verify upstream; don't expose a dead URL". Affects bucket `Source0_modified` only (17 specs/4.0, sample PyPAM where PS has empty col-3 and C has the full pangalactic.org URL). | FRD-011 | 0001,0006 | 4527 | strict |
| M16 | Apply `Source0Lookup.replaceStrings` to tag names before version comparison (PS L 2151). C parsed the column but never used it. For clang/llvm with `replaceStrings="llvmorg-"`, tag `llvmorg-22.1.5` is normalised to `22.1.5` so the compare finds the actual latest. Affects bucket `UpdateAvailable,UpdateURL,UpdateDownloadName,warning` (21 specs/4.0, sample clang: PS=22.1.5, C was llvmorg-9.0.1-rc3). | FRD-011 | 0001,0006 | 2151, 2516-2517 | strict |
| M17 | Vendor-pinned subrelease short-circuit (PS L 2104-2106). When `task.SubRelease` non-empty (SPECS/<digits>/<spec>/<spec>.spec), C now bypasses the full pipeline and emits the fixed-shape pinned row: `<Spec>,<Source0 original>,,pinned,,,,<Name>,,,vendor-pinned (subrelease N),` — mirroring PS byte-for-byte. Implements ADR-0012 Option A decision (status quo / sentinel encoding) and ADR-0013 Option A documentation update (case-variant convention in runbook §1). | FRD-002, FRD-014 | 0006, 0012, 0013 | 2104-2106 | strict |
| M18 | HEAD-fail manufacturer-changed warning emission (PS L 4727-4733). When the HEAD probe of the constructed UpdateURL returns non-200, emit `Warning: Manufacturer may changed version packaging format.` AND clear UpdateURL + HealthUpdateURL. C variant is single-attempt (PS retries 3 alternate URL constructions; the multi-attempt retry chain is a separate future task). Targets bucket `UpdateURL,UpdateDownloadName,warning` (~18 specs/4.0). | FRD-011 | 0001,0006 | 4727-4733 | strict |
| M19 | Augment per-name strip list (PS L 2507-2516): `<Name>.`, `<Name>-`, `<Name>_`, `<Name>`, `ver`, `release_`, `release/`, `release-`, `release`, `-final`. Applied after Source0Lookup.replaceStrings and before `pr_get_latest_name`. Strips e.g. `expat-2.7.0` → `2.7.0`, `release-1.5` → `1.5`. Helps any spec whose tags carry the spec Name as prefix (mostly github tag style). | FRD-011 | 0001,0006 | 2507-2516 | strict |
| M20 | **HTTP listing scraper for non-git specs** (FRD-018). New `src/scraper.c` + `include/pr_scraper.h`. When the spec has no `gitSource` AND the original urlhealth=200, GET dirname(Source0), PCRE2-extract `<a href="...">` values, run the same name-filter pipeline as git tags, pick latest. Implements PS L 4258-4283 (`Invoke-WebRequest .Links.href`). Targets the dominant 504-spec bucket `UpdateAvailable,UpdateURL,SHAName,UpdateDownloadName` (GConf-style ftp.gnome.org listings, archive.apache.org, downloads.sourceforge.net, etc.). Both parity-impact AND vendor-info-impact: empty cells gain real upstream values. Validated: strict_rows dropped 26-69 per branch, soft_rows climbed (cell content fixed; only volatile cols differ). | FRD-018 | 0001,0002,0006 | 4258-4283 | strict |
| M21 | Post-strip name filters (PS L 2522-2524): `-replace "v",""`, keep has-digit, drop names with alpha-after-`[pP]\d+`-strip. Applied to both git-tag and scraper paths after `apply_name_replace_augmentations`. Filters scraper noise like `?C=S;O=A` Apache sort-query hrefs, `LATEST-IS-X` gnome symlink hrefs, navigation `..` paths. amdvlk.spec is the documented exception in PS — not yet covered (separate hook). | FRD-011 | 0001,0006 | 2522-2524 | strict |
| M22 | **Clean-VersionNames** port (PS L 441-451). New `apply_clean_version_names` helper in `src/check_urlhealth.c`. Three anchored case-insensitive leading-prefix strips (`rel/`, `v`, `r`) followed by literal `_`→`.` replace, then PCRE2-based drop of pre-release candidates (`candidate\|-alpha\|-beta\|.beta\|rc.[0-4]\|rc[1-4]\|-preview.\|-dev.\|-pre1\|.pre1`). Wired into both the git-tag pipeline and the M20 scraper pipeline between `apply_name_replace_augmentations` (M19) and `apply_name_post_filters` (M21). PS calls the function at 10 sites (L 2518, 3106, 3317, 3502, 3562, 3842, 3919, 4154, 4388) before passing the name list onward. Targets specs whose tag streams include `rc.N` / `-alpha` / `-beta` / `-preview.` / `-dev.` candidates that previously won the latest-version compare and produced wrong UpdateAvailable rows. | FRD-011 | 0001,0006 | 441-451 | strict |
| M23 | **Scraper pre-filter** port (PS L 4321-4341). New `apply_scraper_pre_filters` helper in `src/check_urlhealth.c`. Drops hrefs containing `</a` or `.tgz.asc`, two-pass keep filter (`.tar.` if present else `.tgz`), strips archive extensions (`-src.tar.gz`, `.tar.gz`, `.tar.bz2`, `.tar.xz`, `.tar.lz`, `.tgz`) — all BEFORE the M19/M22/M21 name-strip chain on the scraper path only. Targets the dominant ~189-spec `cols[5 6 7 9 10]` residual bucket per branch on 5.0 post-M21-wired: candidates like `autogen-5.18.16.tar.xz` were being dropped by M21's no-alpha-after-`[pP]N` rule because the `tar/xz` suffix counted as alpha residue. C's old post-`pr_get_latest_name` extension strip is now defensive dead code; redundant but harmless. | FRD-018 | 0001,0006 | 4321-4341 | strict |
| M24 | **download_name_post** Release/Rel_/v- prefix swaps (PS L 4786-4793). Extends the existing M11 post-processor in `src/check_urlhealth.c` with two new branches: (a) when the basename starts with `Release` or `Rel_` (case-insensitive), replace `Release_`/`Release-`/`Rel_` with `<task.Name>-` then `_`→`.`; (b) when it starts with `v-` (case-insensitive), replace with `<task.Name>-`. Targets the col[10]-only bucket (8 specs on 5.0, e.g. chrpath.spec — PS=`chrpath-0.18.tar.gz` vs C=`release-0.18.tar.gz`) and the tail of cols[5 6 7 10] / cols[5 6 7 9 10] specs where col 10 is the residual diff after M23 fixes the rest. New helpers: `starts_with_icase` and `replace_leading_icase`. M11 explicitly left these branches "not yet ported"; this closes that follow-on. | FRD-014 | 0001,0006 | 4786-4793 | strict |
| M25 | **Per-spec download-name rules** (PS L 4772-4779). Inline the 4 PS if-branches into `download_name_post`: inih.spec (`^r`→`libinih-` anchored), open-vm-tools.spec (prepend `open-vm-tools-`), samba-client.spec (`samba-samba-`→`samba-` global), httpd-mod_jk.spec (`JK_`→``, `_`→`.`, prepend `tomcat-connectors-`). New parameter `task_spec` on `download_name_post`; both call sites updated. Sample: inih.spec PS=`libinih-62.tar.gz` vs C=`r62.tar.gz`. PS handles these inline (not via hooks), so C placement is also inline rather than via the dormant `src/hooks/inih.c` stub. | FRD-014 | 0001,0006,0007 | 4772-4779 | strict |
| M26 | **Source0Lookup.ignoreStrings filter** (PS L 2152 + 2505 + scraper mirror at L 4376). New `apply_ignore_strings()` helper using `fnmatch(FNM_CASEFOLD)`. C parsed `row->ignoreStrings` into the Source0LookupData struct (Phase 3a) but never applied it. Wired into both pipelines between `apply_replace_strings` (M16) and `apply_name_replace_augmentations` (M19). Sample: checkpolicy.spec (row L 568 has ignoreStrings = `2008*,2009*,...,2020*`) — without this filter C picked the date-format tag `20200710`; with it, the date tags drop and C picks `3.10`. Affects specs sharing a multi-format git repo (SELinuxProject mixes checkpolicy-N.N + date-format tags). | FRD-011 | 0001,0006 | 2152, 2505, 4376 | strict |
| M27 | **Per-spec strip-token table** (PS L 2839 switch). New module `src/per_spec_strip.c` + `include/pr_per_spec.h`. Ports ~76 simple `$replace +=` entries from the PS GitHub-tag-list switch (aide, at-spi2-core, bcc, bpftrace, calico-*, chrpath, cloud-init, colm, dracut, frr, glib, glslang, gnome-common, gobject-introspection, gtk3, inih, jsoncpp, krb5, libevent, libsolv, ModemManager, mysql, pandoc, ragel, redis, vulkan-*, ...). Each entry is a static `const char *const tokens[]` NULL-terminated list. Lookup is case-insensitive (PS `switch` default). Wired between `apply_ignore_strings` (M26) and `apply_name_replace_augmentations` (M19). Complex switch entries with custom `$Names = ...` filters (apache-tomcat, automake, docker-20.10, glib, glslang Name-filters, go, httpd, salt3) are deferred to per-spec hooks. | FRD-011 | 0001,0006,0007 | 2839-3060 | strict |

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
