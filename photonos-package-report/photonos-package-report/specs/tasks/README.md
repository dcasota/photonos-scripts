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
| M109 | **alternatives.spec: drop CVS-form `r1-X-Y-Z` tags** (FRD-018, diagnosed in seconds via the T1 + `gh api repos/fedora-sysv/chkconfig/tags --paginate` workflow). fedora-sysv/chkconfig carries both proper semver tags (`1.33`, `1.32`, …, paginated beyond the first github-API page) AND CVS-style `r1-3-37-1` tags. Clean-VersionNames strips leading `r`; C's version-compare then reads `1-3-37-1` as numeric `1.3.37.1` → wins over `1.33` → bogus "Source0 version 1.32 higher than detected latest 1-3-37-1" warning. PS's `[version]::TryParse` fails on dashes → string-sort puts `1.33` last. Added `k_drop_alternatives = {"r1-"}` to the M28 per-spec drop-substring table (runs BEFORE Clean-VersionNames, so candidates still carry their `r` prefix and the substring match is exact). `1.33` has no `r1-` → kept. ctest 13/13. | FRD-018 | 0001,0006 | n/a (C tag-filter; PS handles via TryParse) | strict |
| M108 | **qemu-img generic-scrape token** (PS L 4485, mirrors the Q1 PS fix in PR #239). C left qemu-img col5 empty: download.qemu.org scrape yields `qemu-X.Y.Z.tar.xz` hrefs → apply_href_basename + M23 ext-strip → `qemu-X.Y.Z` → Name-strip (Name=qemu-img) doesn't match `qemu-` → post-filter no-alpha rule drops the `qemu` letters → empty. Added `qemu-` to `apply_generic_scrape_tokens` so the prefix is stripped before the no-alpha filter. One-line spec_eq-gated, mirrors PS L4485. ctest 13/13. | FRD-018 | 0001,0006 | 4485 | strict |
| M107 | **Kernel-family series-pin path scan fix** (FRD-011). `linux_kernel_series` used `strstr(clone_root, "photon-")` which finds the FIRST match. With the M53 persistent-cache layout (`.../photon-upstreams/photon-<branch>/clones`), this matches the `photon-upstreams` parent → the substring after it is `upstreams/…` → every branch-prefix check (`3.0`/`4.0`/`common`) fails → fallback `"6.1."` is returned for ALL branches. On 3.0/4.0/common this drops every candidate via the kseries filter (kept=0 in PR_SCRAPE_DEBUG run 26583592871: e.g. 3.0 had 3176 valid 4.x candidates post-filter, all dropped because `kseries="6.1."`). Fix: scan forward to find the LAST `"photon-"`. Restores detection for linux on 3.0, linux-aws/rt/secure on 3.0, linux-secure/esx/api-headers on 4.0, common kernel specs. 5.0/6.0/master/dev/main were coincidentally correct (the wrong fallback happened to be the right default). ctest 13/13. | FRD-011 | 0001,0006,0009 | n/a (impl) | strict |
| M106 | **Exclusion-list minimal-row early-return** (PS L 2376-2392, 3665-3679, 4020-4034). When a spec's Source0Lookup gitSource repo matches `-UpstreamsExclusionList`, PS sometimes emits a minimal row (col2=raw Source0, col3/4 + detection cols empty). Empirically PS does this for `raspberrypi-firmware` + `chromium` only — `aufs-util`/`aufs-linux` still detect (col5=`7.0`) despite matching the exclusion. Added an early-return right after the pinned-subrelease short-circuit, scoped to `spec_eq(rpi-firmware) || spec_eq(chromium)` AND the exclusion-match check, so user-supplied `-UpstreamsExclusionList` toggles still work. aufs-util/aufs-linux fall through unchanged. ctest 13/13. | FRD-012 | 0001,0006 | 2376-2392, 3665-3679, 4020-4034 | strict |
| M104 | **Raise scraper body cap 1MiB→16MiB** (FRD-018, after M105). Confirmed from run-26542403918 logs: `kernel.org/pub/linux/kernel/vN.x/` + `packages.vmware.com/photon_sources/` overflow the 1 MiB `BODY_CAP_BYTES` → scrape fails → empty col5. PS's Invoke-WebRequest has no cap and scrapes the full listing. Bumped `BODY_CAP_BYTES` to 16 MiB (matches `sourceforge.c`). Safe with M105 in place (vmware-internal detection-skip prevents the over-detection a standalone cap raise would expose). Strictly additive — only >1MiB listings (previously failing) are affected. ctest 13/13. | FRD-018 | 0001,0002,0006 | n/a (impl cap) | strict |
| M105 | **Gate update-detection for VMware-internal Source0 specs** (PS L 4490-4508). PS emits the "Info: Source0 contains a VMware internal url address." warning AND skips update-detection (col5/6 empty by design). C only added the warning — it still ran detection, which was masked only because the `packages.vmware.com/photon_sources/` listing overflowed the 1 MiB scrape body cap. To make the body-cap raise (M104) safe and faithful to PS, gate the detection block on `!pr_spec_is_vmware_internal(spec)`. New helper in `spec_warnings.c` reuses the existing static warning table (string-matches the "Info: …VMware internal" prefix); no spec list duplication. Affects: abupdate, ant-contrib, basic, build-essential, ca-certificates, distrib-compat, docker-vsock, fipsify, grub2-theme, initramfs, minimal, photon-iso-config/release/repos/upgrade, rubygem-async-io, shim-signed, stig-hardening (19 specs). ctest 13/13. | FRD-011 | 0001,0006 | 4490-4508 | strict |
| M103 | **mozjs60 mozilla-releases ESR scrape** (PS L 3226-3252). mozjs60 left col5 empty (cat6, all branches): C handled mozjs (M43) but not the mozjs60 ESR variant, so it health-checked the Source0 without scraping the firefox releases index. Added mozjs60.spec to `pr_mozilla_releases_url` (firefox releases URL, same as mozjs) + a mozjs60 case in `apply_mozilla_transform` (keep only `60.`-bearing release dirs, strip `esr`) → pipeline picks 60.9.0 (last 60 ESR) → `(same version)`, matching PS. spec_eq-gated. ctest 13/13. | FRD-018 | 0001,0002,0006 | 3226-3252 | strict |
| M102 | **substitution_unfinished col4 sentinel** (PS L 2627). PS sets col4 UrlHealth to the literal `substitution_unfinished` when the modified Source0 still contains an unresolved macro brace (`${version}` the %{...} pass can't reach, or unmatched `%{...}`), and SKIPS the urlhealth + scrape-detection path (the clone-based gitSource detection still runs, so e.g. nss keeps its clone-detected version). C lacked this entirely — it health-checked the malformed URL (wrong col4, and for `alternatives` a bogus scraped col5 warning). New `subst_unfinished` flag after funet_mirror gates the urlhealth probe, the M96/M97 normalize, and the scrape gate; col4 emitted as a string. A fully-resolved Source0 has no brace so working specs are untouched. Affects dhcp(cat3→cat2), nss, python3-msal, openjdk8_aarch64, alternatives, … ctest 13/13. | FRD-011 | 0001,0006 | 2627 | strict |
| M101 | **wireguard-tools cgit tags-page scrape** (PS L 4376,4493). dirname(Source0) is the cgit `/snapshot/` DOWNLOAD endpoint (not a listing) so the generic path saw nothing (cat6, 5 branches). Added the `/refs/tags` page URL to `pr_all_other_source_tag_url` (ao path) — its snapshot hrefs `.../snapshot/wireguard-tools-<ver>.tar.xz` basename to `wireguard-tools-<ver>.tar.xz`, and a new `wireguard-tools-` token in `apply_generic_scrape_tokens` (PS $replace L4493) strips the prefix → version. spec_eq-gated. ctest 13/13. | FRD-018 | 0001,0002,0006 | 4376,4493 | strict |
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
| M100 | **python2/python3 two-level python.org dir scrape** (PS L 3294-3336). `dirname(Source0)` for python3 is `…/ftp/python/3.7.5/` (the CURRENT release's dir, only 3.7.5) so the generic scraper never saw newer releases → col5 empty (cat6 on all 7 branches). New `python_dir_scrape()` mirrors PS's bespoke handler: scrape the parent index `https://www.python.org/ftp/python/`, basename + keep `2.`/`3.`-prefixed version DIRECTORIES, post-filter (drop pre-release), pick the highest dir, then scrape `…/<latest>/` for the `Python-<ver>.tar.*` names — with PS's do-until drop-and-retry (bounded) when the newest dir has no final tarball. Wired via `python_eligible` (spec_eq python2/python3, gitSource-empty) into the gate + dispatch like the moz/ao index scrapers; the names run the standard pipeline with a new `Python-` token in `apply_generic_scrape_tokens`. Zero blast radius outside python2/python3. ctest 13/13. | FRD-018 | 0001,0002,0006 | 3294-3336 | strict |
| M99 | **Scraper two-stage fetch (simple-UA fallback)** (PS L 4378-4404). `pr_scrape_listing` made a single Chrome-UA GET; PS does a bare `Invoke-RestMethod` (default agent) PRIMARY then a Chrome-UA retry on catch — and `urlhealth.c` already mirrors that two-stage. Refactored the scraper into `fetch_listing_body(url, chrome)` + `extract_hrefs()`; it now tries Chrome FIRST (so every already-detecting spec is byte-identical — returns on attempt 1, never reaches the fallback) then falls back to the simple `photonos-package-report/C` UA when Chrome fails or yields 0 hrefs. Fixes `libev` (cat6 on all 7 branches): `dist.schmorp.de/libev/Attic/` serves its autoindex to the simple agent (the same UA urlhealth used to get 200 on the file) but not to Chrome → C now detects `4.33` like PS. Env-gated `PR_SCRAPE_DEBUG` stderr trace added (no `.prn` impact). ctest 13/13. | FRD-018 | 0001,0002,0006 | 4378-4404 | strict |
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
| M28+M29 | **Per-spec drop-substring + global-replace filters** (PS L 2839 switch — complex arms). Extends `src/per_spec_strip.c` with two more lookup tables. **M28** ports the "drop name containing X" arms (docker-20.10 drop `xdocs-v`; falco drop `agent/`; glib drop `GTK_`/`gobject_` in addition to its M27 strip; glslang drop `untagged-`/`vulkan-` in addition to its M27 strip; go drop `weekly`/`release`; httpd drop `apache`/`mpm-`/`djg`/`dg_`/`wrowe`/`striker`/`PCRE_`/`MOD_SSL_`/`HTTPD_LDAP_`). Match is case-insensitive (PS `select-string -simplematch`). **M29** ports the global character-replacement arms (automake/newt/salt3 `-` → `.`). Both wired after M27 and before M19. apache-tomcat per-output-file filter remains deferred (needs branch-name context). | FRD-011 | 0001,0006,0007 | 2839-3060 | strict |
| M30 | **ADR-0015 impl** — stable-source SHA for github auto-archives (Accepted Option A 2026-05-18). New module `src/stable_source.c` + `include/pr_stable_source.h` exposing `pr_resolve_stable_source_url(spec, latest_tag, current_url)`. For github `archive/refs/tags/<tag>.tar.gz` URLs, probes `releases/download/<tag>/<asset>` variants (`<tag>.tar.gz` then `<proj>-<tag>.tar.{gz,xz,bz2}`, `<proj>-<tag>.tgz`) via libcurl HEAD; first 200 wins. Project name comes from spec basename and the github-repo segment (deduped). Wired into both C SHA call sites in `check_urlhealth.c`. **Coordinated PS-side patch** adds `Resolve-StableSourceURL` near `urlhealth()` (around L 1522) + a side-file download in the SHA block at L 5004-5017 so PS hashes the same stable URL. The auto-archive download still happens for ModifySpecFile/UpdateDownloadFile. col 6 (UpdateURL) is unchanged — col 9 SHA simply points at a stable source where one exists. Targets the col[9]-only residual bucket: 200 specs on 3.0, 140 on 4.0, 24 on 5.0/6.0. | FRD-007 | 0001,0006,0015 | 5004-5017, 1521-1571 | strict |
| M31 | **ADR-0014 impl** — multi-SHA cols 13/14 schema (Accepted Option B 2026-05-18). Schema growth gated by env var `PR_EMIT_MULTI_SHA`. New `pr_sha_of_url_multi(url, &sha256, &sha512)` API in `src/sha.c` — single libcurl GET feeds bytes into two parallel EVP_MD_CTX hashers. `pr_state_t` grows two fields `SHA256Name`, `SHA512Name`. `prn_writer.c` emits 14-col header when env var set; otherwise 12-col header. C row assembly in `check_urlhealth.c` branches between 12- and 14-col on env var. **Coordinated PS-side patch**: SHA block at L 5025+ computes SHA256/SHA512 alongside the spec's preferred algorithm; row assembly at L 5060+ + the three header AppendLine sites at L 5201/5227/5240 branch on `$env:PR_EMIT_MULTI_SHA`. **Rollout**: default off → 12-col output stays byte-identical to cached snapshot. Operator regenerates PS snapshot with `PR_EMIT_MULTI_SHA=1`, then flips env var on the C workflow for the matching cutover. parity-diff.sh + diff_analyzer.py already loop max(npf,ncf) so handle both schemas. ADR-0006 strict-col set amended (cols 13/14 added). | FRD-014 | 0001,0006,0014 | 5004-5067, 5201, 5227, 5240 | strict |
| M32 | **Atom-feed parser** (FRD-019 PR-B). New `src/atom_feed.c` + `include/pr_atom_feed.h` exposing `pr_scrape_atom_feed(url, &names, &n)`. libcurl GET (atom+xml Accept header) + PCRE2 extraction of `<entry>...<title>X</title>` pattern (skipping the feed-level title), with the 5-standard XML entity decode. Not yet wired into the scraper dispatcher — that lands in FRD-019 PR-C (per-spec SourceTagURL override) and PR-D (dispatcher). Targets the ~30+ gitlab.freedesktop.org / gitlab.com `?format=atom` specs. | FRD-019 | 0001,0002,0006 | 3784, 4258-4283 | n/a (parser only) |
| M66 | **Add the `vmware/photon` `main` branch everywhere** (user-direction 2026-05-24). vmware/photon has a distinct `main` branch (SHA 09e9a079) separate from `master`==`dev` (0b37ad6f). Added `main` as the 8th branch across PS + C + both workflows: (1) **C** — `pr_types.h` gains `GeneratePhMainURLHealthReport` + `GeneratePhMaintoPhMasterDiffHigherPackageVersionReport`; `main.c` gains help/defaults/opt-enum/options/switch + urlhealth `branch_dispatch[]` `main` entry + diff `diffs[]` `main`→`master` entry + package `br[]`/`labels[]`/`lists[]` 7→8 (`photon-main`); `package_report.c` + `pr_package_report.h` `lists[7]`→`[8]`, 8th version column, header `…,photon-master,photon-main`. (2) **PS** (source-of-truth) — `$GeneratePhMainURLHealthReport`/`$GeneratePhMaintoPhMasterDiff…` params + Convert-ToBoolean + GenerateUrlHealthReports param/dispatch/checkUrlHealthTasks + `$branchMap` + the package-matrix block (`GitPhoton main`, `$PackagesMain[Main]`, Select-Object `photon-main`, subrelease row, header + row out-file) + a new `main`→`master` diff block. (3) **Workflows** — `package-report.yml` branches default `…,master,main`, `MAIN_UH`/`main)` case + `main_uh`/`diff_mm` outputs + PS args; `package-report-C.yml` snapshot-branch `main)` case + `main` output + C arg. DB tool needs no change (branch derived from filename). Package matrix column order `…,master,main` identical PS↔C (M61 byte-gate). Local smoke: C matrix emits 10 cols incl. `photon-main`; PS parses clean; ctest 13/13. | FRD-015 | 0001,0006,0015 | 83-109,5104-5160,5519-5640 | strict |
| M64 | **col9 shared cache + the three TODOs** (ADR-0009 amendment 2026-05-24). TODO-1: PS workflow preserves `SOURCES_NEW` tarballs to a 50GB-capped shared path; C sets `PR_SHA_CACHE=1`+`PR_SHA_CACHE_BASE`; `col9_cache_path()` reads `<base>/photon-<branch>/SOURCES_NEW/<name>` → C reuses PS's exact bytes → col9 matches on auto-archives (collapses the soft col9, biggest on 3.0/4.0). TODO-2: already met by the `workflow_run` auto-trigger + warm M53 cache. TODO-3: `strict_col9` dispatch input → `PR_STRICT_COL9` (off by default; flip after TODO-1 validates). | FRD-007 | 0009 | n/a (CI infra) | n/a |
| M63 | **libusb sourceforge two-stage** (PS L 3513-3530; un-defers M40). The libusb files page lists series dirs (`libusb-1.0`), not releases. New `libusb_latest_series()` picks the highest series (strip `libusb-compat-`/`libusb-`, keep digit+no-alpha, version-sort) from the stage-1 `net.sf.files` scrape, then the sf branch re-scrapes `files/libusb-<series>` for the real release names → generic pipeline → 1.0.30. `sourceforge_deferred()` now returns 0 (libusb handled). Validated locally byte-identical to PS (col5 1.0.30, col6 real tarball); nicstat/other sf specs unchanged. | FRD-006 | 0001,0002 | 3513-3530 | strict |
| M62 | **netcat bespoke detection** (PS L 2540-2556 + L 4705-4711). netcat's vendored Source0 (packages.broadcom.com nc-<commit_id>) has no upstream listing. New `src/netcat.c` + `include/pr_netcat.h`: GET openbsd's `usr.bin/nc/netcat.c`, regex the CVS revision (`$OpenBSD: netcat.c,v <maj>.<min>`) → col5; GET the GitHub Commits API (`?path=usr.bin/nc`, Bearer-auth via $GITHUB_TOKEN) → first 7 of latest sha → col10 `nc-<sha7>.tar.xz`; col6 = self-built literal, col7=200. Wired into `check_urlhealth.c` gated by `allow_network` + spec_eq(netcat). Validated locally: **byte-identical to PS** (col5 1.238, col6, col10 nc-c2d3847). | FRD-006 | 0001,0002 | 2540-2556,4705-4711 | strict |
| M60 | **Package version-matrix report** (PS L 5556-5585). New `src/package_report.c` + `include/pr_package_report.h` exposing `pr_write_package_report(lists[7], labels[7], path)` — emits `photonos-package-report_<ts>.prn`: one row per spec with its Version-Release in each of the 7 branches (3.0/4.0/5.0/6.0/common/dev/master), deduped to the first non-subrelease occurrence (PS `IndexOf`+`-Unique`), plus appended subrelease rows (numeric branches only). ICU-collated `Spec,SubRelease` sort (ADR-0016). Wired into `main.c` gated by `GeneratePhPackageReport`; C workflow flips it true + uploads the report. C previously lacked this report entirely. Validated locally: **byte-identical to the PS snapshot matrix** (1245 rows, 0 diffs, incl. subrelease rows). | FRD-015 | 0001,0006,0016 | 5556-5585 | strict |
| M59 | **Diff-report CLI wiring** (PS L 5587-5660). Wired the existing `pr_write_diff_report` generator (PS L5440-5500 port) into `main.c`: a dispatch block that, for each enabled `GeneratePh*toPh*DiffHigherPackageVersionReport` flag, parses the two branch SPECS trees and emits `photonos-diff-report-<a>-<b>_<ts>.prn` (the 4 PS pairs: common-master, 5.0-6.0, 4.0-5.0, 3.0-4.0) listing specs where branch `<a>` has a higher version than `<b>` (subreleases skipped). Runs alongside urlhealth (PS report_type=all order). Validated locally against the M58 PS snapshot: clean rows byte-identical (linux-esx/linux-rt `6.1.83-4,6.1.83-3`); residual local diffs were cache drift (pinned-SHA CI validation is authoritative). | FRD-015 | 0001,0006 | 5587-5660 | strict |
| M57 | **Hardcoded UpdateURL/UpdateAvailable overrides** (PS L 2264-2363). Ported PS's 14 maintainer-pinned overrides for specs where dynamic detection is impossible/broken (archived projects, broken download pages, pythonhosted blob URLs): cdrkit, iptraf, json-spirit, libassuan, libtiff, mpc, python-daemon, python-enum, python-enum34, python-Js2Py, python-ruamel-yaml, runit, sendmail, vsftpd. A function-local static table sets col5 (UpdateAvailable), col6 (UpdateURL), col7 (HealthUpdateURL=200), col10 (UpdateDownloadName via the existing `download_name_post`, so the leading-`v` strip etc. match PS — incl. vsftpd→`sftpd`), and cdrkit's col12 ArchivationDate. Applied after detection; the spec-warning table then supplies cdrkit's col11. col9 (SHA) left empty (soft). All `spec_eq`-gated → zero blast radius. Validated: all 14 match PS on every strict column; only col9 (soft) differs. | FRD-011 | 0001,0006 | 2264-2363 | strict |
| M56 | **byacc/dialog `.tgz` keep-marker fix** (PS L 4374). The invisible-island.net `/current/` listings include a versionless `<name>.tar.gz` "latest" alongside the versioned `<name>-<date>.tgz` files. `apply_scraper_pre_filters` Step 3 keeps `.tar.` when ANY name has it, so that lone `.tar.gz` dropped every versioned `.tgz` → empty col5. PS forces `.tgz` for byacc and dialog regardless; ported as a `force_tgz` flag (spec_eq byacc/dialog) so the marker stays `.tgz`. Validated: byacc `2.0.20260126`, dialog `1.3-20260107` now match PS; tzdata/curl/openssl + controls unchanged. | FRD-011 | 0001,0006 | 4374 | strict |
| M55 | **tzdata per-spec detection handler** (PS L 4406-4460). tzdata regressed to empty col5: its versions end in a letter (`2026b`), so the M21 no-alpha filter dropped every candidate, and the generic latest-name sort can't order the `YYYY<letter>` scheme. Ported PS's three tzdata special-cases: `apply_tzdata_filter()` (keep `tzdata-*`, drop `.asc`/`.sign`/`.tar.Z`, strip `beta`) before the Name-strip; **skip** `apply_name_post_filters` for tzdata (PS L 4439 `notlike tzdata`, same skip-pattern as M48 amdvlk); and `tzdata_latest()` — the bespoke max-by-(year, trailing-letter) sort (PS L 4449-4460). All hooks `spec_eq`-gated to tzdata (zero blast radius). Validated locally: tzdata `2026b` + URL match PS byte-for-byte; curl/openssl + 9 controls unchanged. | FRD-011 | 0001,0006 | 4406-4460 | strict |
| M54 | **Generic-scraper href basename reduction** (PS L 4331-4341). The generic HTML listing path kept each `<a href>` verbatim. When a listing serves root-relative or absolute hrefs (e.g. `curl.haxx.se` now 301s to `curl.se`, which emits `download/curl-8.20.0.tar.xz`), the residual `download/` prefix survives Name-strip and is dropped by the M21 no-alpha filter → empty col5. PS tolerates the prefix because its version extraction is regex-based. New `apply_href_basename()` reduces each generic-path href to its last path segment (same logic as the nspr/ao paths) before the M23 pre-filters; no-op on bare basenames. Scoped to the generic `else` branch only (jsonc/moz/ao/sf/atom keep their own handling). Validated locally: curl 8.20.0 + openssl 4.0.0 restored to match PS, 11 working generic-scrape controls (acl/apr/bash/binutils/bluez/boost/…) unchanged. | FRD-011 | 0001,0006 | 4331-4341 | strict |
| M53 | **Persistent clone cache** (ADR-0009 amendment 2026-05-23). CI-infra fix for bucket-1 transient col5 empties: the C workflow cloned ~4000 upstreams under `${RUNNER_TEMP}/parity-c-wd`, which the self-hosted runner wipes every job → every run cold, intermittent clone failures → transient `UpdateAvailable` empties (45 of 64 5.0 col5 diffs on the cold run 26324413477 were transient — the prior warm run detected all of them identically to PS). Fix: cache root → persistent `${PARITY_CACHE_ROOT:-$HOME/.cache/photonos-parity}/parity-c-wd`. Branch SPECS clones (`parity-reconstruct.sh`) and upstream tag clones (`pr_clone_ensure`) both already reuse + `git fetch` on cache hit; reconstruct re-checks-out the snapshot's exact SHA each run, so persistence preserves determinism and only removes cold-clone flakiness. Clones are partial (`--no-checkout --filter=blob:none`) so the cache is small. Added workflow `concurrency` group (serialise cache-sharing runs) + per-run `scans/` wipe + cache-size report. **Phase 2 deferred** (operator-gated on disk policy): `PR_SHA_CACHE=1` persistent `SOURCES_NEW` tarball cache. No C-code change. | FRD-007 | 0009 | n/a (CI infra) | n/a |
| M52 | **ICU row-sort collation** (ADR-0016). `prn_writer.c` `cmp_str_asc` switched from `strcasecmp` (ordinal, case-insensitive) to an ICU `en-US` collator at strength `UCOL_SECONDARY` (case-insensitive), opened once via `pthread_once`, with a `strcasecmp` fallback if ICU init fails. Reproduces PowerShell `Sort-Object`'s .NET `CompareInfo` ordering, which on Linux delegates to ICU. `strcasecmp` compared punctuation by byte value (`-`=0x2D, `.`=0x2E, `_`=0x5F) whereas ICU treats `-`/`.` as ignorable punctuation, mis-ordering punctuation families and shifting rows relative to PS (phantom row-index diffs in `parity-diff.sh`). Affected clusters on 5.0: `rubygem-http_parser.rb` vs `rubygem-http-*`, `python-setuptools_scm` vs `-rust`, `python-backports_abc` vs `.ssl_match_hostname`, `rubygem-unf_ext` vs `unf`. New build dep `icu-devel` (CMake `pkg_check_modules(ICU REQUIRED icu-i18n icu-uc)` + CI `tdnf install`). Validated: ICU sort reproduces PS row order with **0 mismatches across all five branches** (3.0/4.0/5.0/6.0/common). | FRD-011 | 0001,0006,0016 | 5476 | strict |
| M33 | **Atom-feed dispatcher** (FRD-019 PR-C + PR-D bundled). New `pr_per_spec_source_tag_url(spec_name)` lookup in `src/per_spec_strip.c` returning the atom-feed URL when the spec has an override (27 entries ported from PS L 3687, 3815-3866: asciidoc3, atk, cairo, dbus, dbus-glib, dbus-python, fontconfig, gstreamer, ipcalc, libslirp, libtiff, libx11, libxinerama, man-db, mesa, mm-common, modemmanager, pixman, pkg-config, polkit, psmisc, pygobject, python-M2Crypto, python-pygobject, shared-mime-info, wayland, wayland-protocols). Dispatcher in `src/check_urlhealth.c`: when the spec has an atom override AND UpdateAvailable is still empty after the git-tag path, calls `pr_scrape_atom_feed` instead of `pr_scrape_listing`. The atom path skips M23's HTML pre-filter. Gate updated to allow this branch for gitSource-bearing specs (PS's fallback semantics). | FRD-019 | 0001,0002,0006 | 3687, 3815-3866 | strict |

---

## Risk register (cross-phase)

| Risk | Phase | Mitigation |
|---|---|---|
| `%{version}` regression of 2026-05-11 — parallel-runspace state leak — recurs in C | 4, 7 | FRD-013 mandates per-thread state isolation; FRD-016 gates Phase 4 strictly |
| PS-side hook changes during the port window | 3, 4 | `spec-hook-extractor` drift check at every CMake configure |
| HTTP-status flapping | 5, 6 | Cols 4, 7 are soft-diffed |
| Sort-order divergence (locale) | 7, M52 | `setlocale(LC_ALL, "C")` at startup handles the C-library axis; the `.prn` *row* sort uses an ICU `en-US` collator (ADR-0016 / M52) to match PowerShell's culture-aware `Sort-Object`. ICU collation is driven by the locale argument, not `LC_ALL`, so the two are independent. |
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
