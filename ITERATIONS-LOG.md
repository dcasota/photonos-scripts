# Iterations log — Phase M convergence loop

Append-only record of the autonomous-loop iterations. Each entry lists
the PR(s) shipped, the C run that validated them, and the journal-row
delta. For methodology and current backlog, see `TODO.md`. For
decision history, see `specs/adr/*.md`. For per-task spec rows, see
`photonos-package-report/photonos-package-report/specs/tasks/README.md`.

---

## Session 1: 2026-05-17 evening → 2026-05-18 morning

Started with parity gate freshly online (Phase 8 done). Goal initially
framed as parity-only; reframed mid-session (per user) as dual goal —
parity AND vendor-info quality.

### Iteration shape

```
M08 → M09 → M10 → M11 → M12 → M13 → M14 → M15 → M16
                                      │
                                      └─ keystone fix (case-insensitive sort)
                                         unmasked M08-M13 in the journal
```

Plus M17 (ADR-0012/0013 decisions + pinned sentinel), M18/M19 (HEAD-fail
warning + name-replace augmentations), M20 (HTTP listing scraper /
FRD-018), M21 (post-strip filters), ADR-0014 (multi-SHA Draft).

### Per-iteration log

| PR | Task | Key insight |
|---|---|---|
| #100 | **M08** — `%{version}` cut (PS L 2111-2119) | C was using the uncut `Version-Release` form for substitution. |
| #102 | **M09** — `ftp.gnu.org` → `ftp.funet.fi` mirror | PS L 2343-2346. ~50 GNU specs affected. |
| #103 | **M10** — UpdateAvailable compare branches | Emit `(same version)` / warning text; compare against cut form. |
| #104 | **M11** — UpdateDownloadName post-process | v-strip + name-prefix-for-numeric (PS L 4770/4782-4783). |
| #105 | **M12** — Gate URL/SHA/DownloadName on rc==1 only | PS leaves cols empty when "(same version)"; C was filling them. |
| #106 | **M13** — Per-spec warning table (~70 entries) | PS L 4442-4519. New `src/spec_warnings.c`. |
| #107 | **M14** — `.prn` sort case-insensitive (KEYSTONE) | `parity-diff.sh` compares by line index. PS uses case-insensitive sort; C used `strcmp`. After fix, M08-M13's column-level work became visible in the journal. **−191 strict on 4.0 in one PR.** |
| #108 | **M15** — Clear Source0 when no update + bad urlhealth | PS L 4527 mirror. |
| #109 | **M16** — Apply Source0Lookup.replaceStrings to tags | PS L 2151. C parsed but never applied. |
| #110 | **M17** — Pinned-subrelease short-circuit | ADR-0012 Option A implementation. PS L 2104-2106. |
| #112 | **M18+M19** — HEAD-fail warning + name strips | PS L 4727-4733 + 2507-2516. |
| #113 | ADR-0014 multi-SHA Draft | User direction; pending decision. |
| #114 | **M20** — HTTP listing scraper (FRD-018) | New `src/scraper.c`. Targets the dominant non-git update detection gap. **−47 strict / +17 soft on 4.0.** |
| #115 | **M21** — Post-strip filters | PS L 2522-2524. Drops scraper-noise hrefs (`?C=S;O=A`, `LATEST-IS-X`, `..`). |
| #117 | **M21 followup** — wire `apply_name_post_filters` into scraper path | One missing call site in `src/check_urlhealth.c` (M20 scraper branch). Validation run 26044019950: strict_rows dropped **149-290 per branch** (35-57% cumulative reduction from initial). The post-strip filters were only applied on the git-tag path until this commit. |
| #118 | **M22** — Clean-VersionNames pre-release filter | PS L 441-451. Anchored `rel/`/`v`/`r` strips, `_`→`.`, drop `candidate\|-alpha\|-beta\|.beta\|rc.[0-4]\|rc[1-4]\|-preview.\|-dev.\|-pre1\|.pre1`. Wired into both git-tag and scraper pipelines between M19 and M21. |
| #120 | **M23** — Scraper pre-filter (extension strip + `.tar.` keep) | PS L 4321-4341. Without it, scraper-path candidates like `autogen-5.18.16.tar.xz` got dropped by M21's no-alpha-after-`[pP]N` rule because `tar/xz` counts as alpha. Targets the dominant ~189-spec `cols[5 6 7 9 10]` bucket per branch on 5.0 post-M21-wired. |
| #121 | **ADR-0015 Draft** — Stable-source SHA for github auto-archives | Option A: when col 6 is a github `archive/refs/tags/` URL, probe `releases/download/<tag>/<asset>` and compute col-9 SHA against the stable asset. Targets the ~75 col[9]-only specs/branch. Composes with ADR-0014. Status Draft, pending user decision. |
| #122 | **M24** — download_name_post Release/Rel_/v- prefix swaps | PS L 4786-4793. Replaces `Release_`/`Release-`/`Rel_` and `v-` prefixes with `<task.Name>-`. Targets col[10]-only bucket (8 specs on 5.0, e.g. chrpath PS=`chrpath-0.18.tar.gz` vs C=`release-0.18.tar.gz`) and the tail of cols[5 6 7 10]/cols[5 6 7 9 10] post-M23. |
| #123 | **TODO refresh** post-M22/M23/M24 | Strike shipped units; document PS snapshot refresh cadence + dead-code cleanup deferral. |
| #124 | **M25** — Per-spec download-name rules (inih, open-vm-tools, samba-client, httpd-mod_jk) | PS L 4772-4779. inih sample: PS=`libinih-62.tar.gz` vs C=`r62.tar.gz`. Inlined into `download_name_post` since PS handles them as a flat if-chain, not via hooks. |
| #125 | **M26** — Source0Lookup.ignoreStrings filter | PS L 2152 + 2505. C parsed col 7 of Source0LookupData but never applied it. New `apply_ignore_strings()` using `fnmatch(FNM_CASEFOLD)`. checkpolicy.spec sample: PS=`3.10` vs C=`20200710` (date-format tag the filter drops). |
| #126 | **M27** — Per-spec strip-token table | PS L 2839 switch (~76 simple entries ported). New `src/per_spec_strip.c` with static table keyed on spec name (case-insensitive). Custom-filter switch arms deferred to per-spec hooks. |
| #127 | **M28+M29** — Per-spec drop-substring + global-replace filters | PS L 2839 switch — complex arms. M28: docker-20.10/falco/glib/glslang/go/httpd drop blacklists (case-insensitive substring match). M29: automake/newt/salt3 global "-" → "." replace. Same module as M27. |
| #128 | **ADR-0014 + ADR-0015 promoted to Accepted, Stage 6 documented** | User decisions 2026-05-18 evening. ADR-0014 → Option B (cols 13/14 schema). ADR-0015 → Option A (col-9 stable URL override). Stage 6 → WireGuard policy routing (runbook §10). Per-upstream family priority → atom-feed parser. |
| #129 | **M30** — ADR-0015 impl: stable-source SHA for github auto-archives | PS + C coordinated. New `src/stable_source.c` + PS `Resolve-StableSourceURL`. When col 6 is github `archive/refs/tags/`, probe `releases/download/<tag>/<asset>` variants via HEAD; first 200 hashed for col 9. col 6 unchanged. Targets col[9]-only bucket (200 on 3.0, 140 on 4.0, 24 on 5.0/6.0). |
| #130 | **M31** — ADR-0014 impl: cols 13/14 SHA256Name/SHA512Name schema | PS + C + parity-diff + diff_analyzer. New `pr_sha_of_url_multi` (single GET, dual hash). pr_state_t grows two fields. Schema growth gated by env var `PR_EMIT_MULTI_SHA` (default off → 12-col matches cached snapshot). Operator regenerates PS snapshot with env var on for cutover. ADR-0006 strict-col set amended. |
| #131 | **FRD-019 Draft** — atom-feed tag-list scraper | ~30+ specs use `?format=atom` URLs that current HTML href scraper returns 0 candidates for. Multi-PR rollout planned (PR-A this draft, PR-B parser, PR-C URL overrides, PR-D dispatcher wiring, PR-E validation). |
| #132 | **M32** — Atom-feed parser (FRD-019 PR-B) | New `src/atom_feed.c` + `include/pr_atom_feed.h`. PCRE2-based `<entry><title>X</title>` extraction with 5-standard XML entity decode. Not yet wired into the scraper dispatcher — FRD-019 PR-C lands the per-spec URL override + dispatcher wiring. |
| #133 | **M33** — Atom-feed dispatcher (FRD-019 PR-C+D bundled) | 27-entry per-spec URL override table + dispatcher wiring in check_urlhealth.c. Calls `pr_scrape_atom_feed` when override exists; otherwise `pr_scrape_listing`. Gate updated to allow this branch for gitSource-bearing specs (PS L 3815-3866 fallback semantics). |
| #134 | **CLAUDE.md refresh** post-M22-M33 | Session-context cheatsheet rewritten. Phase tracker M01-M21 → M01-M33. |
| #135 | **M32 fix** — bare `PowerShell` UA for atom-feed parser | gitlab.freedesktop.org Anubis anti-bot rejects Chrome-style + verbose PS UAs but allows bare `PowerShell`. Caught locally via curl probe with the new HTTP-allowlist permission grant. Would have made M32 inert for all gitlab.freedesktop.org specs. |
| #137 | **M30 fix** — propagate `Resolve-StableSourceURL` into PS parallel runspaces | The function was undefined inside `ForEach-Object -Parallel` workers → ADR-0015 inert PS-side. Added to the FunctionDefinitions init-script table. |
| #138 | **harness fix** — fresh `snapshot/` dir + per-branch dedup in C workflow | first attempt at the stale-snapshot bug. |
| #139 | **harness fix (ROOT CAUSE)** — select snapshot tarball by exact PS run id | `snapshot-raw/` accumulated tarballs; `ls\|head -1` picked the alphabetically-smallest = oldest run id = May 17 baseline. Every C run since ~May 17 silently diffed against the stale baseline. |
| #140 | **harness fix** — dedup by filename-timestamp + clean PS staging dir | C dedup used `ls -t` (mtime); tar gives equal mtimes → tied to oldest filename. PS `/tmp/new-reports` staging accumulated across runs. |

### The 2026-05-19/20 stale-snapshot saga

For ~3 days the journal numbers were measured against a **frozen May 17
PS baseline**, not the PS run that triggered each C run. Root cause:
the C workflow's `snapshot-raw/` download dir accumulated tarballs and
`ls *.tar.gz | head -1` deterministically picked the oldest run id
(`25991871716`). Three compounding bugs (#137 runspace, #139 tarball
select, #140 mtime-dedup + PS staging) all had to be fixed before a C
run would diff against the correct fresh PS snapshot. Diagnosis was
driven by the new read-only HTTP + pwsh permission grants
(local `parity-diff.sh` reproduction + per-file SHA probes).

Lesson: the journal is only as trustworthy as the snapshot-selection
logic. A green/strict number means nothing if it's diffing the wrong
input pair. Always cross-check journal numbers against a local
`parity-diff.sh` of the artifacts when a result looks anomalous.

### Journal trajectory (strict_rows per branch)

NOTE: rows from `After M14` through `After M22-M33` were all measured
against the **stale May 17 PS baseline** (the snapshot-selection bug
above). They're internally consistent — C genuinely converged toward
the May 17 PS output — but the absolute numbers and especially the
col[9]/cols[6 7 9] buckets were distorted. The `Clean baseline` row is
the first **trustworthy** measurement (journal == local diff on all 7
branches, verified).

```
Run / Branch        3.0  4.0   5.0   6.0  common  dev   master
Initial             919  1034  1113  1093    6   1090   1090
After M14 unmask    795   841   849   832    6    833    834   (vs stale)
After M16           774   822   835   817    6    818    816   (vs stale)
After M20           748   774   766   766    6    767    769   (vs stale)
After M21-wired     599   563   476   476    5    481    482   (vs stale)
After M22-M33       571   518   414   416    6    423    425   (vs stale)
Clean baseline      551   484   392   373    5    386    381   ← run 26160062078
                                                              (journal==local-diff ✓)

Δ from initial    -368  -550  -721  -720    -1   -704   -709
% reduction        40%   53%   65%   66%    --    65%    65%
```

### 5.0 residual buckets — clean baseline (run 26160062078, trustworthy)

| Cols signature  | Count | Cause / next step |
|-----------------|------:|-------------------|
| 5 6 7 9 10      |   106 | per-spec scraper fetch failures (per-upstream-family adapters needed) |
| 5 only          |    73 | `(same version)` not emitted where PS detects it; atom hosts not all wired |
| 6 7 9           |    40 | version-detection differences (C picks different latest than PS) |
| 9 only          |    23 | github auto-archive SHA drift for specs WITHOUT a release-asset (ADR-0015 can't help; bounded by the ~7h PS→C run gap) |
| 5 11            |    20 | UpdateAvailable + warning combinations |
| 4 6 7 9 10 11   |    17 | mixed (volatile col 4 + detection) |
| 3 4             |    15 | per-spec Source0 rewrites (kernel.org cgit etc.), unported |
| 3 only          |    14 | per-spec Source0 rewrites |

Total 5.0: 392 strict / 63 soft.

The col[9]-only (23) + cols[6 7 9] (40) are the temporal-drift +
version-detection territory. ADR-0015 closes the subset of github
auto-archive specs that publish a release-asset; the remainder drift
because the auto-archive is regenerated server-side between the PS run
and the (clone-bound, ~4h-later) C run. Closing these fully needs
either tarball caching (download once, hash both sides from the same
bytes) or running PS+C back-to-back with no GitHub-regeneration window.

### Critical findings (preserved as memory entries)

- **`feedback_source0lookup_case_sensitivity`**: PS `.IndexOf` is
  case-sensitive (Source0Lookup); PS `-ilike` is case-insensitive
  (warnings/hooks). Don't collapse case-variant Source0Lookup rows.
- **`feedback_per_package_depth_investigation`**: Remaining gap is
  per-package adapter work, not bulk-port. Decompose by upstream
  family.
- **`feedback_dual_goal`**: Pure-parity fixes that mirror PS's stale
  data are low value; score on parity-impact + info-impact.

### Architectural decisions made

- ADR-0012 — Subrelease output layout → Option A (status quo, pinned-sentinel).
- ADR-0013 — Source0Lookup per-release scoping → Option A (status quo, case-variant rows).
- ADR-0014 — Multi-SHA emission strategy → **Draft**, pending user decision.

### Open infrastructure issues

- WSL2 host occasionally loses TLS connectivity to
  `*.actions.githubusercontent.com` while `api.github.com` stays
  healthy. Symptom: runner offline, jobs queued. Recovery: VPN
  cycle + `systemctl restart actions.runner.*.service`. Seen
  2026-05-17 and 2026-05-18.
- On-demand C clones can fill disk if pointed at `/tmp`. Use a path
  with quota awareness for local non-CI runs.

### Files / artefacts of interest

- `docs/prn-analysis/diff-c-vs-ps-photon-<branch>.md` — auto-generated
  bucket breakdown per branch. Regenerate via `tools/diff_analyzer.py
  <PS-snapshot-dir> <C-artifact-dir> docs/prn-analysis`.
- `tools/parity-journal.tsv` — append-only verdict log; clock for ADR-0009.
- `c-side-prn-<run_id>` workflow artifact — 30-day retained C-side .prn
  output, downloadable via `gh run download <id> -n c-side-prn-<id>`.

---

## Session (2026-05-23): M52 — ICU row-sort collation (ADR-0016)

Root-caused the residual 5.0 col5 "differences" with the actual artifacts
(PS scan `…230701` vs C run `26324413477`, cross-checked against the prior
warm C run `26312789233`):

- **45 of 64** col5 diffs were **transient cold-run failures** (this run was
  the slow ~1h32m post-reboot cold-clone pass); the previous warm run
  detected every one identically to PS.
- **~10** were **sort-collation misalignment** — identical detections shifted
  to neighbouring rows because C sorted with ordinal `strcasecmp` while PS
  uses ICU culture collation.
- The genuine deterministic remainder is ~8 normalization/presentation rows
  (C cleaner) + 1 consistent C-better row — **zero missing detections**.

### Shipped: M52 / ADR-0016

`prn_writer.c` `cmp_str_asc` → ICU `en-US` collator, strength `SECONDARY`
(case-insensitive), opened once via `pthread_once`, `strcasecmp` fallback.
New build dep `icu-devel` (CMake `pkg_check_modules(ICU REQUIRED icu-i18n
icu-uc)` + CI `tdnf install`). Regression test `test_icu_row_sort`
(test_phase6) guards the four punctuation clusters.

**Validation (pre-merge, local):** ICU sort reproduces PS's `.prn` row order
with **0 mismatches across all five branches** (3.0: 919, 4.0: 1034, 5.0:
1113, 6.0: 1093, common: 6), and matches live `pwsh Sort-Object` on ICU 72
and 76. All 13 ctest targets green. This retired the "global-realignment
regression risk" that had gated the sort change.

---

## Session (2026-05-23, cont.): M53 — persistent clone cache (ADR-0009 amendment)

Bucket-1 fix following the M52 root-cause analysis. The C workflow cloned
~4000 upstreams under `${RUNNER_TEMP}/parity-c-wd`, which the self-hosted
runner wipes every job — so every run was cold and intermittent clone
failures produced transient col5 (UpdateAvailable) empties (45 of 64 5.0
col5 diffs on the cold run were transient; the prior warm run detected all
identically to PS).

### Shipped (CI-infra; no C-code change)

- Cache root → persistent `${PARITY_CACHE_ROOT:-$HOME/.cache/photonos-parity}/parity-c-wd`
  (runner home survives across jobs; only `_work/_temp` is wiped). The
  branch SPECS clones (`parity-reconstruct.sh`) and upstream tag clones
  (`pr_clone_ensure`) both already reuse + `git fetch` on a cache hit, and
  reconstruct re-checks-out the snapshot's exact SHA each run — so
  persistence preserves determinism and removes only cold-clone flakiness.
- Workflow `concurrency` group (serialise cache-sharing runs), per-run
  `scans/` wipe, cache-size + free-disk report step.
- Clones are partial (`--no-checkout --filter=blob:none`) → cache footprint
  is small; disk on the runner is 602G free.

**Phase 2 deferred** (operator-gated on disk policy): `PR_SHA_CACHE=1`
persistent `SOURCES_NEW` tarball cache for col9 (real blobs, GBs — needs a
size-cap/prune policy first).

Expectation: the first run after merge re-clones (cold, slow); subsequent
runs are warm and the transient col5 empties should largely disappear,
narrowing the soft/strict counts toward the warm-run baseline.

---

## Session (2026-05-23, cont.): M54 — generic-scraper href basename + diagnosis correction

**Correction to the M53 hypothesis.** The warm run (26336994311) did NOT
collapse the col5 empties — it scored an identical 116/98 with the same
105 empties. The cache WAS hit (runtime 90min→8min), but these specs use
the HTTP-scrape path, not git clones, so M53 couldn't touch them. My
"45-of-64 transient" characterization was substantially wrong: local repro
showed the empties are deterministic, not cold-run noise.

**Root-caused via local repro:**
- curl: `curl.haxx.se/download/` now 301s to `curl.se`, serving root-relative
  hrefs (`download/curl-8.20.0.tar.xz`). C's generic scraper kept the raw
  href; after Name-strip the `download/` prefix is dropped by M21's no-alpha
  filter → empty. PS detects it (regex extraction tolerates the prefix).
  Fixed by M54 `apply_href_basename` (last-path-segment reduction in the
  generic path). curl 8.20.0 + openssl 4.0.0 restored; 11 controls unchanged.
- The remaining empties are NOT one bug — per-spec quirks (tzdata double-slash
  URL + no name/ver separator; byacc `%{byaccdate}` macro; netcat commit-id
  vendored tarball; libsodium `-stable` suffix; libusb/runit/vsftpd hosts).
  These are the deferred "fiddly stragglers" bucket; each needs its own unit.

Net: the col5 gap is a MIX — the curl/openssl relative-href bug (fixed),
per-spec quirks (deferred), and some genuine transients — not predominantly
transient as previously stated.

---

## Session (2026-05-23, cont.): M55 — tzdata per-spec detection handler

First of the per-spec "fiddly straggler" empties. Diagnosed all 7 locally
(tzdata/byacc/netcat/libsodium/libusb/runit/vsftpd): each a distinct cause,
NOT a shared bug. tzdata + byacc use Source0Lookup rewrites that C already
applies correctly (col3 matches PS); the empties are in the post-scrape
pipeline where PS has per-spec handlers C hadn't ported.

**Shipped M55 (tzdata):** ported PS L4406-4460's three tzdata special-cases —
keep-`tzdata`/drop-`.asc/.sign/.tar.Z` filter + `beta` strip; skip the M21
no-alpha filter (tzdata versions end in a letter, `2026b`); bespoke
max-by-(year, trailing-letter) sort. All `spec_eq`-gated → zero blast radius.
Validated: tzdata `2026b` + URL match PS byte-for-byte; curl/openssl + 9
controls unchanged; 13 ctests green.

**Remaining stragglers (each its own unit):** byacc (verify `/current/`
scrape + L4354-4374 filter), libsodium (col3 substitution empty + 404 gate +
`-stable` strip), netcat (commit-id vendored tarball), libusb/runit/vsftpd.

---

## Session (2026-05-23, cont.): M56 — byacc/dialog .tgz keep-marker fix

Second straggler. byacc col4=200 and the `/current/` scrape returned all the
`byacc-2.0.<date>.tgz` files, yet col5 was empty. Traced via a temporary
debug print: the listing also contains a versionless `byacc.tar.gz` "latest"
symlink, which flipped `apply_scraper_pre_filters` Step 3's `has_tar` flag →
keep-marker became `.tar.` → every versioned `.tgz` was dropped, leaving only
`byacc.tar.gz` → reduced to "" → empty.

PS forces `.tgz` for byacc and dialog at L4374 regardless of `.tar.` presence.
Ported as a `force_tgz` flag (spec_eq byacc/dialog) in apply_scraper_pre_filters.
Fixes BOTH byacc (2.0.20260126) and dialog (1.3-20260107); validated no
regression on tzdata/curl/openssl + controls; 13 ctests green.

Remaining stragglers: libsodium (col3 substitution empty + 404 gate +
`-stable`), netcat (commit-id vendored), libusb, runit, vsftpd. (gtest's
`v1.17.0` vs `1.17.0` is a separate known v-prefix normalization, C-cleaner.)

---

## Session (2026-05-23, cont.): M57 — hardcoded UpdateURL/UpdateAvailable overrides

Biggest single batch. While diagnosing the remaining stragglers (runit/
sendmail/vsftpd), found PS L2264-2363: a block of 14 maintainer-pinned
hardcoded overrides for specs where dynamic detection is impossible (archived
projects, broken download pages, pythonhosted blob URLs). None were ported.

Ported all 14 (cdrkit, iptraf, json-spirit, libassuan, libtiff, mpc,
python-daemon, python-enum, python-enum34, python-Js2Py, python-ruamel-yaml,
runit, sendmail, vsftpd) as a function-local static table setting col5/6/7,
col10 (via download_name_post — reproduces the leading-`v` strip, e.g.
vsftpd→sftpd), and cdrkit's col12 ArchivationDate; the spec-warning table
supplies cdrkit's col11. All spec_eq-gated → zero blast radius. col9 (SHA)
left empty (soft per ADR-0009). Validated: all 14 match PS on every strict
column; 13 ctests green. ~8 of these were on my straggler list.

Straggler tally after M54-M57: curl, openssl, tzdata, byacc, dialog, cdrkit,
mpc, runit, sendmail, vsftpd, python-daemon, python-Js2Py, python-ruamel-yaml
(+ iptraf/json-spirit/libassuan/libtiff/python-enum/enum34) fixed. Remaining:
libsodium (404 temporal + col3-blank-on-dead-URL is correct PS behavior),
netcat (commit-id vendored — needs gitSource override), libusb (deferred
sourceforge two-stage).

---

## Session (2026-05-23, cont.): M58 — col3 (c): fix PS empty-Source0Lookup fallback

Operator chose col3 decision (c) — fix the source-of-truth. The ~28-row
gitlab-atom col3/col6/col10 bucket was C-superiority: PS emitted the bare
homepage, C the real tarball. Root cause: PS L2196 set `$Source0` to the
empty Source0Lookup field for these gitSource-only entries, which the
L2224-2229 homepage-prepend then collapsed to the homepage. C already falls
back to the spec Source0 template (check_urlhealth.c L1027-1033).

Fix: one-line fallback at PS L2196 — empty Source0Lookup → `$currentTask.Source0`.
Validated in isolation (gstreamer → real tarball; non-empty-lookup specs
unchanged) + pwsh parse OK. No C change needed (C already does this).
Requires PS-snapshot regeneration before the journal reflects the alignment.

---

## Session (2026-05-23, cont.): M58 merged + M59 — diff-report wiring

M58 (col3 fix c) validated: PS regen + auto-triggered C run → 5.0 strict
**103 → 87 (−16)**; gstreamer & the gitlab-atom family now emit the real
tarball byte-identically on BOTH PS and C (dual-goal win). Merged.

M59: wired the dormant `pr_write_diff_report` generator into the CLI. A
dispatch block emits the 4 PS diff reports (common-master, 5.0-6.0, 4.0-5.0,
3.0-4.0) when their flags are set. Local validation matched PS on clean rows
(linux-esx/linux-rt 6.1.83-4,6.1.83-3); residual local diffs were cache drift
(the shared parity-c-wd cache had advanced past the M58 snapshot — even
showed linux-esx twice). CI (pinned-SHA reconstruct) is the authoritative
validation. Diff-report parity-gate integration to follow once a clean CI
run confirms.

Dual-goal note (per operator): M58 directly advanced healthy/correct URLs on
both implementations; M59 is feature-completeness. Next: resume URL-health/
schema work (the remaining stragglers + proactive detection hardening).

---

## Session (2026-05-23, cont.): M60 — package version-matrix report

Second report-completeness unit. C previously emitted only urlhealth + (M59)
diff reports; PS also produces the package matrix. Implemented
pr_write_package_report (PS L5556-5585): 7-branch main rows (first
non-subrelease version, deduped) + appended subrelease rows, ICU-collated
Spec,SubRelease sort. Wired into main.c (GeneratePhPackageReport); C workflow
now generates + uploads it.

Validated locally against the M58 PS snapshot matrix: **byte-identical —
1245 rows, 0 body diffs**, including subrelease rows (stalld 91). This also
confirmed M59's dedup fix (the linux-esx "drift" was a duplicate spec in the
tree; dedup picks PS's first occurrence). C now matches PS on urlhealth +
diff + package reports; only the issues-.md remains unported.

---

## Session (2026-05-23, cont.): M61 — parity-gate the package + diff reports

Extended the C-side parity step to validate the M59/M60 reports against the
PS snapshot (both are in the snapshot tarball's prn-snapshot/):
  - package-report: GATED. Deterministic (pinned-SHA spec versions, no
    network) → byte-identical to PS (validated 0 diffs / 1245 rows). Folds
    into the overall verdict.
  - diff reports: INFORMATIONAL (reported, not gated). PS omits stalld in
    common-master despite its own matrix + VersionCompare saying common>master
    (PS internal inconsistency); C is more correct, so not gated.

---

## Session (2026-05-23, cont.): M62 — netcat bespoke detection

First URL-health straggler. netcat is a self-built vendored tarball with no
upstream listing; PS derives the version from the CVS revision in openbsd's
netcat.c and the download-name commit_id from the GitHub Commits API. Ported
as src/netcat.c (two libcurl GETs + version regex + sha extract), wired into
check_urlhealth gated by allow_network + spec_eq(netcat). Validated locally:
byte-identical to PS — col5=1.238, col6=self-built literal, col10=nc-c2d3847
(commit_id matched). Remaining stragglers: libusb (sourceforge two-stage),
libsodium (404 temporal, PS-blank correct).

---

## Session (2026-05-24, cont.): M63 — libusb sourceforge two-stage

Un-defers the M40-deferred libusb. The libusb files page lists series dirs
(libusb-1.0), not releases. Added libusb_latest_series() (strip
libusb-compat-/libusb-, keep digit+no-alpha, version-sort → "1.0"); the sf
branch then re-scrapes files/libusb-<series> for the real release names which
the generic pipeline reduces to 1.0.30. sourceforge_deferred() now returns 0.
Root cause of the initial empty: libusb was still in sourceforge_deferred (so
sf_eligible was false) — un-deferring + the two-stage fixed it. Validated
byte-identical to PS (1.0.30 + real tarball URL); nicstat unchanged.
Remaining: col9 SHA (operator-gated), stalld diff row (informational), and
libsodium (404 — correct PS behavior, not a bug).

---

## All-branch convergence baseline (2026-05-24, post-M63, fresh snapshot)

First full 7-branch run after all M52-M63 fixes (PS run 26350387627 → C run
26351276028, same-day → low temporal drift). Also fully warmed the persistent
clone cache for all 7 branches (future full runs are fast).

| branch | strict | soft |
|--------|-------:|-----:|
| 3.0    | 89     | 421  |
| 4.0    | 89     | 287  |
| 5.0    | 85     | 108  |
| 6.0    | 86     | 110  |
| common | 5      | 0    |
| dev    | 77     | 126  |
| master | 85     | 122  |

Reading: strict ~77-89/branch is the structural residual after the detection/
schema program (5.0 went 392→126→85 across the project). The LARGE soft on the
old branches (3.0=421, 4.0=287) is dominated by col9 SHA diffs (auto-archive
SHA drift + PS-empty col9) — addressable ONLY by the operator-gated shared
SOURCES_NEW cache (PR_SHA_CACHE), not detection code. Remaining strict is a mix
of temporal drift (snapshot vs run gap) + per-spec long-tail; further reduction
needs the operator decisions (col9 cache disk policy; tighter PS→C scheduling;
PR_STRICT_COL9 timing), all scoped in TODO.md.

---

## Session (2026-05-24, cont.): M64 — col9 shared cache + the three operator TODOs

Operator approved implementing all three. TODO-1 (col9 shared cache): the PS
workflow now preserves its SOURCES_NEW tarballs to a 50GB-capped shared path;
col9_cache_path() reads PS's bytes via PR_SHA_CACHE_BASE; C activates
PR_SHA_CACHE=1. So PS+C hash identical bytes → col9 matches on regenerated
auto-archives (the soft driver, biggest on 3.0=421/4.0=287). Only tarballs are
persisted (not PS's full clones) so disk stays bounded. TODO-2: already met by
the workflow_run auto-trigger + warm cache (no code change). TODO-3: strict_col9
dispatch input → PR_STRICT_COL9, OFF by default — flip only after a PS→C cycle
confirms col9 byte-stable (else strict spikes + resets the 90-day clock).
Validation: needs a fresh PS run → auto-triggered C run; col9 soft should drop.

---

## M64 col9-cache validation finding (2026-05-24)

Activated the shared cache and measured col9 directly (C run 26357010174 vs PS
snapshot 26356115730): **122 col9 mismatches remained** — 41 C-has-SHA/PS-empty,
53 PS-has/C-empty (download-name vs preserved-filename gap → cache miss), 28
both-differ. So col9 parity needs more than the shared cache: (a) all col9
computation paths must honour cache-only mode (the stable-source/multi-SHA/
legacy paths still compute on miss), (b) C's UpdateDownloadName must align with
PS's preserved tarball filename, (c) PS-empty mirroring. The cache-only fix
(sha.c) handles the simple path correctly but not these.

DECISION: keep all M64 infra (PS preserve step, col9_cache_path PR_SHA_CACHE_BASE,
sha.c cache-only, strict_col9 switch) but GATE activation behind dispatch inputs
`sha_cache` + `strict_col9`, both DEFAULT OFF. Auto (workflow_run) runs behave
exactly as before (col9 soft, no spurious diffs). TODO-1 "full col9 parity" is
re-scoped as a follow-on (the col9-path + name-alignment work). col9 is soft, so
none of this affects the strict gate or 90-day clock. TODO-2 done; TODO-3 switch
ready (gated on TODO-1 completion).

---

## Session (2026-05-24, cont.): M65 abandoned + green-criterion decision (ADR-0009)

M65 (git-tag --merged pin) FAILED validation: `git tag --merged <sha>` lists
only HEAD-reachable tags vs PS's `git tag -l` (all tags); many upstreams tag
on unmerged branches → strict 85→349. PR #188 closed, not merged.

Data finding: per-branch strict is a STABLE STRUCTURAL FLOOR (5.0≈85,6.0≈86,
3.0≈89,4.0≈89,common=5,dev≈77,master≈85), not trending down with per-spec work
nor up across snapshot ages in the auto-trigger flow → temporal drift is small
in production (±~7). Residual = C-superiority + per-spec long-tail + small
temporal noise + soft col9.

Decision (ADR-0009 amendment): green per branch = `strict ≤ THRESHOLD`
(ratified structural floor), held 90 days — tracks "no regression beyond the
known residual" rather than unachievable literal 0 (C is often more correct
than PS). Option D (hermetic record-replay) evaluated and DEFERRED as
gold-plating: the production gate is already stable; the correct tag-freeze
(record tag lists) is high-effort/low-payoff. Adopt A+E (tight scheduling +
strict band). Convergence program is effectively complete.
