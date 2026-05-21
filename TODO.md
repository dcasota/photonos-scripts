# TODO — C-port parity convergence + vendor-info quality

Living plan for **two parallel goals** toward 90 days green:

1. **Shrink the C↔PS `.prn` parity gap** — close cell-level diffs so
   the ADR-0009 journal verdicts trend green.
2. **Maximize accessible vendor package information** — make
   `UpdateAvailable`, `UpdateURL`, `SHAName`, `UpdateDownloadName`
   actually reflect upstream truth. Stale URLs / empty cells / wrong
   versions are defects regardless of whether PS and C agree on them.

ADR-0009 (90-day green) is the floor, not the ceiling. The journal
verdict says "PS and C agree" — it doesn't say "the report is useful".

When the goals conflict (e.g. PS has a stale URL and C correctly
mirrors it), prefer the fix that scores on **both axes** — typically
that means fixing the Source0Lookup row / Phase-3b hook / upstream
adapter rather than blindly mirroring PS. PS modifications flow under
CLAUDE.md invariant 2 (PS is upstream-of-C source-of-truth), so
PS-side fixes are valid and welcome — they make BOTH sides better
simultaneously.

Git-based, spec-driven, small-patch discipline. AI agent executes
autonomously between checkpoints.

## Methodology

### Spec-driven (SDD)

Adapted from <https://github.com/sitoader/SDD-book-tracking-app> and from
`photonos-package-report/photonos-package-report/CLAUDE.md` invariants.

Every code change traces back through:

```
specs/tasks/README.md  →  FRD  →  ADR  →  specs/prd.md
   (task ID)              (functional)  (architectural)  (product req)
```

Status progression for each spec artefact:
`Draft → Reviewed → Accepted → Implemented`.

When a task lands as a merged PR, its row in `specs/tasks/README.md` is
updated; the relevant FRD's `Status` flips to `Implemented` when its last
task ships. `CLAUDE.md`'s Phase tracker is updated in the same PR.

### Linux-kernel-process discipline

Adapted from <https://github.com/torvalds/linux/blob/master/Documentation/process>.

Adopted (with AI autonomy):

- **One logical change per commit.** No "fix typo + add feature + refactor".
  Phase-M tasks M01–M04 followed this; future PRs must too.
- **Changelog quality.** Every commit subject in imperative mood; body
  answers *why* (not *what* — the diff already shows that). Footer carries
  `FRD:`, `ADR:`, `PS-source:`, `Parity:` lines per `CLAUDE.md` template.
- **Patch series for related changes.** Stacked PRs (e.g. PS edit → C
  mirror → workflow flip) when sequential. Each PR self-contained,
  mergeable, revertible.
- **Don't break userspace.** Translated: don't break the `.prn` contract.
  ADR-0006 (bit-identical) is the userspace-equivalent guarantee. Any
  change that affects a non-volatile `.prn` column must show a parity
  diff before/after.
- **Co-Authored-By on every commit** as the AI's sign-off.
- **Respect the tooling.** `ctest --test-dir build` + `tools/parity-diff.sh`
  + the parity-journal gate are the merge prereqs.

Not adopted (because AI autonomy is granted):

- Mailing-list review cycles. PRs auto-merge once `ctest` is green and
  parity-gate is `pass`/`warn`.
- Maintainer mailing-list etiquette. GitHub PRs replace this.
- Multi-week patch-bombing windows. The agent ships when the change is
  ready.

### Git flow per task

```
master ──┬──► sdd/<phase>-<id>-<topic>  ──► PR  ──► merge ──► master
         │      • single logical change                   │
         │      • spec updated in same PR                 │
         │      • ctest green; parity-gate pass/warn      │
         │                                                ▼
         └──► next task off updated master      task row → "Implemented"
```

Branch naming: `sdd/phase-<N>-task<NNN>-<slug>` for numeric phases,
`sdd/phase-m-m<NN>-<slug>` for Phase M.

---

## Now: disk-recovery aftermath

- [x] Kill zombie C-binary processes (user ran `pkill` via `!`)
- [x] Remove `/tmp/parity-local/`
- [x] Confirm disk back to 609 G free
- [ ] Restart the local C run, this time with `-upstreamsDir` pointing at
      a non-`/tmp` path that survives reboots and has dedicated headroom
      (e.g. `/root/parity-local/`). Set up disk-quota guard if needed.

---

## Stage 1 — Durable diff artefacts (small, immediate)

Goal: every C-side workflow run preserves its `.prn` output so any
strict-fail is investigable post-hoc.

- [ ] **PR-A: upload-artifact for C-side `.prn`.** Add a step to
      `package-report-C.yml` after "Run C binary" that uploads
      `${SCANS}/photonos-urlhealth-*.prn` as artifact
      `c-side-prn-<run_id>` with 30-day retention.
      - Smoke: dispatch the workflow, confirm artifact lands.
      - Acceptance: `gh run download <id> -n c-side-prn-<id>` returns
        7 files.

---

## Stage 2 — Diff analysis baseline

Goal: produce one markdown per branch under
`photonos-package-report/photonos-package-report/docs/prn-analysis/`
that buckets PS↔C diffs by column-set signature with affected packages.

- [ ] Restart local C run against snapshot SHAs (already on runner).
      ~1h ETA at `ThrottleLimit=8`.
- [ ] Once each branch's `.prn` lands, run `diff_analyzer.py` (already
      drafted) → produces:
      - `diff-c-vs-ps-photon-3.0.md`
      - `diff-c-vs-ps-photon-4.0.md`
      - `diff-c-vs-ps-photon-5.0.md` (default subrelease)
      - `diff-c-vs-ps-photon-5.0-SPECS-90.md` (once snapshot includes it)
      - `diff-c-vs-ps-photon-5.0-SPECS-91.md`
      - `diff-c-vs-ps-photon-6.0.md`
      - `diff-c-vs-ps-photon-common.md`
      - `diff-c-vs-ps-photon-dev.md`
      - `diff-c-vs-ps-photon-master.md`
- [ ] Ship as **PR-B** alongside the analyzer script. Auto-regen
      target so future runs refresh.
- [ ] **Decision point:** publish at this stage to confirm the
      diff-signature taxonomy makes sense before generating fix PRs.

---

## Stage 3 — Iterative fix-and-merge loop

For each diff-signature bucket, in descending order of affected-count:

### Per-category PR workflow

1. **Read the bucket.** Open the relevant `diff-c-vs-ps-photon-<b>.md`,
   pick the top bucket. Note: column set + count + sample specs.
2. **Trace the column to source.**
   - PS line range (search `photonos-package-report.ps1` for the column's
     write site)
   - C function (`check_urlhealth.c`, `clone.c`, etc.)
3. **Decide the fix direction.** Per `CLAUDE.md` invariant 2, bugfixes
   flow PS → spec → C. So:
   - If PS is wrong: fix PS, then mirror to C.
   - If C is missing logic that PS already implements: port the PS
     logic to C (no PS change).
   - If both wrong (or category is "C doesn't yet implement"): port.
4. **Write/extend the spec.** Identify the responsible FRD; either
   amend §2 or §4 of an existing FRD, or open a new FRD if the scope
   is a new feature.
5. **Implement.** Single-purpose branch off latest master. Commit
   uses the standard template.
6. **Smoke test locally.**
   - `ctest --test-dir build` (unit)
   - Run C binary against `<wd>/photon-<branch>/SPECS/<spec-from-bucket>`
     for 2-3 sample specs; verify the offending column now matches PS.
   - For PS-side changes: `pwsh -File ../photonos-package-report.ps1
     -workingDir <wd> -GeneratePh<X>URLHealthReport true` against same
     subset; confirm regression-free for unrelated specs.
7. **Open PR, wait for parity-gate.** With Stage 1 PR-A in place, the
   workflow's C `.prn` is now downloadable for post-hoc inspection if
   the verdict regresses unexpectedly.
8. **Merge** if parity-gate is `pass` or `warn` (0-30 day window).
   `fail` blocks; investigate before retry.
9. **Update spec status** (`Implemented` if final task, else leave
   `Accepted`). Already part of the merged PR.

### Status — M01-M34 shipped; harness corrected (2026-05-20)

M01-M21 (Session 1): shared infrastructure — pinned-sentinel, case-
insensitive sort, version-cut, substitution rewrites, warning table,
replaceStrings, post-strip filters, HTTP listing scraper.

M22-M33 (Session 2): Clean-VersionNames, scraper extension pre-strip,
download_name_post Release/Rel_/v-, per-spec download rules,
ignoreStrings filter, per-spec strip-token table (~76 specs),
per-spec drop-substring + global-replace, ADR-0015 stable-source SHA
(M30), ADR-0014 multi-SHA cols 13/14 (M31, env-gated), atom-feed
parser + dispatcher (M32/M33, FRD-019).

M34 (#143): rubygems.org JSON-API adapter — first per-upstream-family
update-detection adapter (vs the HTML scraper). Queries
`api/v1/versions/<gem>.json`, newest non-prerelease, builds the `.gem`
URL + SHA. Closes the dominant rubygem-* slice (~64 specs/branch) of
the cols[5 6 7 9 10] bucket. Validation: run 26185297395 (5.0).

**Trustworthy baseline (journal == local-diff verified):**

| Branch | Initial | Now | % closed | as-of run |
|--------|--------:|----:|---------:|-----------|
| 3.0    |  919 | 551 | 40% | 26160062078 |
| 4.0    | 1034 | 484 | 53% | 26160062078 |
| 5.0    | 1113 | **213** | **81%** | 26226086868 (post-M35) |
| 6.0    | 1093 | 373 | 66% | 26160062078 |
| dev    | 1090 | 386 | 65% | 26160062078 |
| master | 1090 | 381 | 65% | 26160062078 |

**M34 validated (5.0, run 26201671031):** 392→266 strict (−126).
117 rubygem specs in 5.0, only 11 still mismatched → M34 closed ~106.
Journal == local parity-diff (266/60) confirmed. No regressions: the
improvement is concentrated in rubygem-* rows. Other branches not yet
re-run post-M34 (single-branch validation per memory guidance).

**M35 validated (5.0, run 26226086868):** 227→213 strict (−14).
sourceforge adapter — 14 specs fixed (cppunit, docbook-xsl, expect,
hdparm, inotify-tools, libdnet, mingetty, nano, scons, sshpass, tcl,
trousers, watchdog, xmlstarlet), ZERO regressions from the gate
relaxation. Journal == local diff (213/60). Deferred: unzip/zip munge,
libusb two-stage. Remaining biggest families in cols[5 6 7 9 10]:
github (12, mixed causes — amdvlk Q-version quirk, hwloc/jna no-gitSource
detection gap), CPAN (8, clean metacpan-API adapter → M37 next), samba
(5), openssl (2), launchpad (2).

**M36 validated (5.0, run 26212147597):** 266→227 strict (−39).
ftp.gnu.org→FUNET mirror was applied to the probe Source0 (col 3) but
NOT the constructed UpdateURL, so ~40 GNU specs (`cols[6 7 9]`: bash,
coreutils, grep, gawk, glibc, …) got an unreachable col 6 + empty col 9
SHA. Extracted `funet_mirror()`, applied at both UpdateURL build sites.
`cols[6 7 9]` bucket went 40→0; bash/grep/coreutils match PS byte-for-
byte. Journal == local diff (227/60) confirmed.

**NEW FINDING — sort-collation divergence (CHECKPOINT, touches the
"do-not-break" sort invariant):** 12 rows in 5.0 are misaligned (col[1]
Spec mismatch cascades) because C sorts with `strcasecmp` (ordinal:
`-`<`.`<`_`) while PS's .NET `Sort-Object` is culture word-sort
(`_`<`-`<`.`, hyphen treated as ignorable). Affected: python-backports_abc,
python-backports.ssl_match_hostname, python-setuptools_scm,
python-setuptools-rust, rubygem-http_parser.rb + http-* cluster,
rubygem-unf_ext/unf. Fixing requires emulating .NET word-sort
(ignorable-char rules) or linking ICU — both carry global-realignment
regression risk. **Decision needed before touching `prn_writer.c`
cmp_str_asc.** Est. ~12 rows/branch (~70 total).

NOTE: journal rows before run 26160062078 were measured against a
**frozen May 17 PS baseline** (snapshot-selection bug, fixed in PRs
#137-#140). They were internally consistent but distorted on the
col[9]/cols[6 7 9] SHA buckets. Always cross-check anomalous journal
numbers against a local `parity-diff.sh` of the artifacts. See
ITERATIONS-LOG "stale-snapshot saga".

See `specs/tasks/README.md` for the full M01-M33 task table.

### Residual buckets — clean 5.0 baseline (run 26160062078, 392 strict)

Per `feedback_per_package_depth_investigation.md`: the remaining gap
is **per-package investigation** — each spec has its own upstream
naming scheme / download convention / update-detection mechanism.

Trustworthy 5.0 bucket counts (journal == local-diff verified):

- **106 `cols[5 6 7 9 10]`** — per-spec scraper fetch failures; the
  scraper returns no candidate or the wrong one. Needs per-upstream-
  family adapters (gnome.org, sourceforge, launchpad listing layouts).
- **73 `col[5]` only** — `(same version)` not emitted where PS detects
  it; some atom-feed hosts beyond the 27 wired in M33.
- **40 `cols[6 7 9]`** — version-detection differences (C picks a
  different "latest" than PS); per-family release-vs-RC-vs-nightly
  filtering not implemented.
- **23 `col[9]` only** — github auto-archive SHA drift for specs
  WITHOUT a release-asset. ADR-0015 can't help these; only tarball
  caching or back-to-back PS+C runs (no GitHub-regeneration window)
  would close them.
- **20 `cols[5 11]`** — UpdateAvailable + warning combinations.
- **~29 `col[3]` / `cols[3 4]`** — per-spec Source0 rewrites
  (kernel.org cgit, ModemManager dir-vs-file), unported per-spec hooks.

### Next-units priority (dual-axis: parity + vendor-info)

Re-ranked 2026-05-20 against the trustworthy clean baseline.

| Unit | Parity Δ | Info Δ | Effort | Notes |
|---|---|---|---|---|
| **Per-upstream-family adapters** | very-high | very-high | per-family weeks | the 106-spec `cols[5 6 7 9 10]` bucket. Atom-feed (M33) + rubygems (M34) done. Next family scoped: **sourceforge (M35)** — PS L 3459-3568. SourceTagURL = strip {sourceforge.net/, downloads.project/, projects/, prdownloads., downloads., download., gkernel/files/, sourceforge/} from Source0, take split("/")[0], build `sourceforge.net/projects/<n>/files/<n>`; ~10 per-spec URL overrides (docbook-xsl, expect, fakeroot-ng, libpng, nfs-utils, openipmi, procps-ng, tcl, unzip, zip); fetch page, extract `net.sf.files = {...}};` JSON block, pull `"name":` values; per-spec filters (libusb two-stage fetch, tboot 2007-2011 drops); strip tar exts + ignore + replace tokens + Clean-VersionNames + strip v + digit/alpha filters; Get-LatestName. After sourceforge: gnome.org, launchpad. Validate per-family with single-branch 5.0 cycles |
| **`(same version)` emission + remaining atom hosts** | high | medium | 1-2 PRs | the 73-spec `col[5]` bucket — specs where PS emits `(same version)` but C doesn't (scraper found nothing, or atom host beyond the 27 wired) |
| **Per-family version-detection (release vs RC vs nightly)** | medium | high | 1 PR per family | the 40-spec `cols[6 7 9]` bucket — C picks a different "latest" than PS |
| **ADR-0015 release-asset coverage expansion** | medium | high | per-host PRs | extend `pr_resolve_stable_source_url` beyond github (gitlab releases, sourceforge) to shrink the 23-spec `col[9]` auto-archive-drift bucket |
| **Tarball-cache for SHA stability** | medium | n/a | needs ADR | the ultimate fix for col[9] drift: download tarball once, hash both PS+C from the same bytes. Alternative to running PS+C back-to-back |
| **Per-spec Source0 rewrite hooks** | low | medium | 1 PR per ~5 specs | the ~29 `col[3]`/`cols[3 4]` bucket — kernel.org cgit, ModemManager dir-vs-file. PS dispatcher L 3961-3996 lists candidates |
| **Dead-code cleanup**: post-`pr_get_latest_name` ext-strip | n/a | n/a | small PR | M23 made it redundant; safe to remove (clean run confirmed no behavioural diff) |
| ~~ADR-0014 multi-SHA cols 13/14~~ ✅ M31 (#130) | — | — | — | shipped, env-gated (`PR_EMIT_MULTI_SHA`); operator flips on after coordinated PS-snapshot cutover |
| ~~ADR-0015 stable-source SHA~~ ✅ M30 (#129, #137) | — | — | — | shipped live; bounded by release-asset availability |
| ~~Atom-feed scraper (FRD-019)~~ ✅ M32/M33 (#132/#133) | — | — | — | parser + 27-spec dispatcher; bare `PowerShell` UA (#135) |
| ~~Scraper extension pre-strip~~ ✅ M23 · ~~Clean-VersionNames~~ ✅ M22 · ~~download_name_post~~ ✅ M24/M25 · ~~ignoreStrings~~ ✅ M26 · ~~per-spec tables~~ ✅ M27/M28/M29 | — | — | — | all shipped Session 2 |

---

## Stage 4 — Per-release × subrelease coverage   ✅ DECIDED

ADR-0012 → **Accepted Option A (status quo, pinned-sentinel)** on
2026-05-18. PS L 2104-2106 already emits the sentinel row. M17
implements the matching C-side short-circuit. No schema change.

---

## Stage 5 — Source0Lookup split decision   ✅ DECIDED

ADR-0013 → **Accepted Option A (status quo, case-variant rows)** on
2026-05-18. The same conceptual package is listed twice in
Source0LookupData with different filename casings (PS L 2147
`.IndexOf` is case-sensitive). Documented in maintainer-runbook §1.
No schema change. See `feedback_source0lookup_case_sensitivity.md`
memory entry.

---

## Stage 6 — Network gating (e.g. netfilter.org)

Some upstream hosts (`netfilter.org`, geo-restricted release mirrors)
return 5xx or redirect-loops when the runner's egress IP is blocked.
Today the C binary reports those as `no_update_available` /
`url_unhealthy`, which dilutes the signal.

- [ ] **Identify the blocked-host set.** From the PS-side
      `photon-4.0.md` and `photon-5.0-normal.md` analyses: at minimum
      `*.netfilter.org`. Possibly more once the C diff lands.
- [ ] **On-demand VPN.** Decision: provision a VPN egress on the
      self-hosted runner that activates when an in-flight clone or
      probe targets a known-blocked host. Implementation options:
      - WireGuard with policy routing keyed on dest CIDR
      - HTTP/SOCKS5 proxy with `git config http.<base>.proxy`
      - `gh api`-style cached fetcher (cheapest; doesn't help git
        clones for those repos)
- [ ] **Out-of-scope for the AI agent.** Needs host root + ISP
      decisions. Capture as `docs/maintainer-runbook.md` §10 once
      decided, owned by you.

---

## Stage 7 — Phase 9 retirement criterion

ADR-0009 says: 90 days of green parity-journal → PS retires →
`staging/legacy/photonos-package-report.ps1` and C app is the sole
producer.

- [ ] Track the journal day-by-day. The ADR-0009 ladder is already
      live (PR #67); the 30/60/90 windows enforce themselves.
- [ ] When 90 days hit, the user (not the agent) opens the PR that
      moves the .ps1 to `staging/legacy/`. Symbolic event; no AI
      action required.

---

## Checkpoints (where the AI pauses for your input)

Updated 2026-05-18 with status:

1. ~~End of Stage 2 — diff-signature taxonomy~~ ✅ approved; M08-M21 followed.
2. ~~ADR-0012 — single-file vs. split-`.prn`~~ ✅ Option A.
3. ~~ADR-0013 — Source0Lookup CSV restructure~~ ✅ Option A.
4. ~~**ADR-0014** — multi-SHA emission strategy~~ ✅ Option B (new cols 13/14).
5. ~~**ADR-0015** — stable-source SHA for github auto-archives~~ ✅ Option A (col-9 override).
6. ~~**Stage 6** — VPN/proxy provisioning direction~~ ✅ WireGuard with policy routing (operator implementation; runbook §10).
7. ~~**Per-upstream-family scrapers** — atom-feed first~~ ✅ FRD-019
   atom-feed parser + dispatcher shipped (M32/M33). gnome.org /
   sourceforge / launchpad families are the next adapters.
8. **Per-PS-edit guards** — any PS edit touching >3 lookup rows
   or the L 2161-2199 substitution sequence (CLAUDE.md invariant 3)
   still pauses for confirmation.
9. **Harness trust** — journal numbers are only valid if the C run
   diffed against the snapshot from the PS run that triggered it.
   The 2026-05-19/20 stale-snapshot saga (PRs #137-#140) proved a
   green/strict count can silently reflect the wrong input pair.
   When a number looks anomalous, cross-check with a local
   `parity-diff.sh` of the downloaded artifacts before acting.

For everything else: proceed.

---

## Update protocol for this file

This file is the source-of-truth for outstanding work. Each merged PR
ticks off the relevant `[ ]`. The agent may add tasks under any stage;
removing or rewording a stage requires user confirmation. Stage
ordering is descriptive, not prescriptive — Stage 3 PRs interleave
with Stage 1/2 as opportunity allows.

Updated whenever a PR lands; spec/task IDs preserved for traceability.
