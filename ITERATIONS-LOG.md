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
| TBD  | **M27** — Per-spec strip-token table | PS L 2839 switch (~76 simple entries ported). New `src/per_spec_strip.c` with static table keyed on spec name (case-insensitive). Custom-filter switch arms deferred to per-spec hooks. |

### Journal trajectory (strict_rows per branch)

```
Run / Branch        3.0  4.0   5.0   6.0  common  dev   master
Initial             919  1034  1113  1093    6   1090   1090
After M14 unmask    795   841   849   832    6    833    834
After M16           774   822   835   817    6    818    816
After M20           748   774   766   766    6    767    769
After M21-wired     599   563   476   476    5    481    482  ← run 26044019950
                  (-149)(-211)(-290)(-290) (-1) (-286) (-287)
After M22          (pending validation — fresh dispatch against master 610ce20)

Δ from initial    -320  -471  -637  -617    -1   -609   -608
% reduction        35%   46%   57%   56%    --    56%    56%
```

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
