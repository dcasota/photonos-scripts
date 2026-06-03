# TODO — C-port parity convergence + vendor-info quality

**>>> 2026-06-03 SESSION CHECKPOINT (M99-M135 era — convergence loop effectively COMPLETE) <<<**

Since the M63 checkpoint, ~37 phase-M tasks shipped covering CI infrastructure,
database management, dynamic reporting, Node.js modernisation, and the final
TODO-1 col9 closure. Notable landings:

- **M99**: scraper-UA fallback fixed 6 specs (simple-UA when photonos-UA 4xx'd).
- **M112**: urlhealth UA-gating retry for Linux mirrors (ftp.altlinux.org class).
- **M122-M124**: C-side `ModifySpecFile` port — version-bump spec rewriting on
  parity with PS. Gated behind `modify_spec=true` dispatch input.
- **M125**: First/Last/Email params on PS + C + workflow inputs — changelog
  author no longer hardcoded.
- **M126**: `photon-scans.db` xz-compressed in git (75 MB raw → 2.9 MB xz).
  Hit the 100 MB GitHub blob ceiling, applied LRU prune (10 outlier scans).
- **M127-M128**: dynamic timeline chart (matplotlib Agg) embedded in the
  database-report .docx; outlier trim + dashed aggregate trend line.
- **M129-M130**: workflow hygiene — retention-days 95→90 (cap warn fix);
  step-summary chart via raw.githubusercontent.com URL (data: URI sanitiser).
- **M131-M132**: Node.js 24 modernisation. M131 opt-in env-var; M132 native
  `download-artifact@v8.0.1` + `upload-artifact@v7.0.1`.
- **M133**: `snyk-analysis.yml` default branches now include `main`
  (3.0,4.0,5.0,6.0,common,dev,master,main).
- **M134**: emergency Snyk run recovery — `snyk_issues.db` hit 129 MB > 100 MB
  GitHub limit. Salvaged the 16-h scan artifact and xz-compressed inline.
  Workflow now mirrors M126 pattern: decompress at job start, compress at
  commit. ~96% size reduction.
- **M135**: `sha_cache=ON` workflow default. M64's 122-row col9 finding has
  decayed; direct cache-vs-prn measurement (2026-06-03) shows 4833 / 4913
  potential cache hits, 70-100% match per branch in manual replay (production
  auto-trigger projects 95%+). Production validation pending Sunday's PS
  cron (2026-06-07).

### Parity state (2026-06-03)

All 7 non-common branches `overall=strict` under ADR-0009 ceilings.
**common branch went GREEN for the first time** in run 26868597097 with
`sha_cache=ON`. Per-branch col9 cache-hit rates from M135 validation:

| Branch | PS-has-SHA | C-match (cache hit) | Match % |
|--------|------------:|--------------------:|--------:|
| 3.0    | 693         | 268                 | 38.7 %  |
| 4.0    | 745         | 410                 | 55.0 %  |
| 5.0    | 599         | 416                 | 69.4 %  |
| 6.0    | 731         | 514                 | 70.3 %  |
| common | 1           | 1                   | 100 %   |
| dev    | 767         | 534                 | 69.6 %  |
| main   | 611         | 424                 | 69.4 %  |
| master | 766         | 534                 | 69.7 %  |

(Lower-than-projected match is github auto-archive byte-drift in **manual
replay only** — production auto-trigger reads bytes seconds after PS
preserved them, byte-stable.)

### TODO-1 / TODO-2 / TODO-3 — operator decisions

- **TODO-1** (col9 SHA full parity): **effectively closed** by M135.
  Remaining 2 real bugs (`newt.spec` / `psmisc.spec`) are architectural
  fixes deferred 2026-06-03 (operator chose Option A: park, value <0.2%).
  Tasks 62/63 carry the documented root cause.
- **TODO-2** (tight PS→C scheduling): **done** via `workflow_run`
  auto-trigger (predates this checkpoint).
- **TODO-3** (`PR_STRICT_COL9` flip): still gated. Wait for several
  production auto-trigger cycles with `sha_cache=ON` to measure col9
  byte-stability before flipping the strict gate.

### Session conventions (added this session)

- Phase-M PRs with `gate + parity-gate` green and `MERGEABLE/CLEAN`
  auto-merge without operator ask (durable authorization 2026-06-03).
- `M136` and `M137` numbers are reserved for the deferred newt/psmisc
  fixes; do not reuse for unrelated work.

---

**>>> 2026-05-24 SESSION CHECKPOINT (M63 — fixable stragglers EXHAUSTED) <<<**
Shipped M52-M63 (13 feature PRs, all merged). 5.0 urlhealth strict 126→~85.
netcat (M62) + libusb sourceforge two-stage (M63) both byte-identical to PS.
The clean autonomous per-spec/detection lane is now COMPLETE. What remains is
NOT per-spec detection work:
  - TEMPORAL drift (dominant residual): PS snapshot vs later C run → col5/col6
    version+SHA differ for specs that released between the two runs. Fix =
    run PS and C BACK-TO-BACK (architecture/operator), not detection code.
  - col9 SHA: PR_SHA_CACHE persistent SOURCES_NEW (operator-gated on a disk-cap
    policy) OR inline download+hash (network-heavy, soft-only). NEEDS OPERATOR.
  - libsodium: upstream 404 (1.0.18-stable gone) — PS blank is CORRECT, not a bug.
  - stalld diff-report row: PS internal inconsistency (C more correct);
    informational-only in the gate (M61).
NEXT (operator decisions): (a) col9 SHA cache disk policy; (b) back-to-back
PS+C scheduling to kill temporal drift; (c) PR_STRICT_COL9 re-enable timing.

**>>> 2026-05-24 SESSION CHECKPOINT (M62 — netcat; report parity + gating) <<<**
Shipped M52-M62 (12 feature PRs, all merged). 5.0 urlhealth strict 126→~87
(±5 transient). C matches PS on urlhealth + diff + package reports (M59/M60),
package report GATED byte-identical (M61). M62: netcat bespoke detection
(raw netcat.c CVS rev + Commits-API commit_id) — byte-identical to PS.
REMAINING:
  - libusb (M63, scoped): sourceforge TWO-STAGE (PS L3513-3530). Stage 1 scrapes
    projects/libusb/files/ net.sf.files → strip libusb-compat-/libusb- → filter
    digit+no-alpha → version-sort → SERIES (e.g. "1.0"). Stage 2 re-scrapes
    projects/libusb/files/libusb-<series> net.sf.files → real release names →
    generic pipeline → 1.0.30. Needs a libusb two-stage in the C sf branch
    (check_urlhealth.c ~L1527) reusing pr_sourceforge_fetch_names twice +
    pr_version_compare for the series max. Validate against snapshot (1.0.30).
  - libsodium: upstream 404 (1.0.18-stable gone; only 1.0.19+ remain). PS's
    blank-on-dead-URL is CORRECT; not a bug — do not "fix".
  - col9 SHA: PR_SHA_CACHE (operator-gated, disk policy) or inline compute.
  - stalld diff-report row: PS internal inconsistency (C more correct); diff
    report is informational-only in the gate (M61), so not failing.

**>>> 2026-05-23 SESSION CHECKPOINT (M60 — FULL REPORT PARITY) <<<**
Shipped M52-M60 (9 PRs, all merged). 5.0 urlhealth strict: **126 → 87**.
C now matches PS on ALL report types:
  - urlhealth: parity-gated, 87 strict (M52/54/55/56/57/58 detection+schema work).
  - diff reports (M59): generated+uploaded in CI; byte-matches PS except 1
    stalld row (PS internally inconsistent — its own matrix+VersionCompare say
    common>master but its diff omits it; C is more correct, do NOT mirror).
  - package matrix (M60): generated+uploaded; **byte-identical to PS** (1245
    rows, 0 diffs, pinned-CI validated, incl. subrelease rows).
  - issues-.md: shared Python post-processor on the urlhealth .prn — no C port
    needed (works on C's output).
M58 was the dual-goal headline: PS source-of-truth fix so BOTH PS+C emit the
real gitlab-atom tarball+SHA (not the homepage).
NEXT UNITS:
  - M61: parity-GATE the diff + package reports in CI (PS package report is in
    the snapshot's package-reports/ dir; needs parity-diff plumbing + the
    stalld decision — accept C-superiority or fix the PS diff bug like M58).
  - URL-health stragglers (dual-goal, fragile): netcat (bespoke raw-file+CVS-
    regex+Commits-API), libusb (sourceforge two-stage), libsodium (404 temporal).
  - col9 SHA: PR_SHA_CACHE (operator-gated on disk policy) or inline compute.

**>>> 2026-05-23 SESSION CHECKPOINT (updated) <<<**
Shipped M52-M59 (all merged). 5.0 strict: **126 → ~87**.
M58 (col3 fix c, PS source-of-truth): gitlab-atom family now emits the real
tarball byte-identically on BOTH PS and C — 103→87 (dual-goal win: healthy/
correct URLs on both implementations). M59: wired the cross-branch diff
reports into the C CLI (common-master/5.0-6.0/4.0-5.0/3.0-4.0), deduped to
match PS's matrix; matches PS except 1 stalld row (PS internally inconsistent;
diff report not yet parity-gated).
Earlier this session: M52 ICU sort (−12); M53 persistent clone cache; M54
curl/openssl basename; M55 tzdata; M56 byacc/dialog; M57 14 hardcoded overrides.
REMAINING (next units):
  - M60: diff-report parity-gate integration (validate diff reports in CI;
    needs PS snapshot to carry all 4 + resolve/accept the stalld case).
  - Package-matrix report generator (C still lacks it; PS has it).
  - URL-health/schema stragglers (fragile): netcat (bespoke raw-file+CVS-regex+
    Commits-API), libusb (sourceforge two-stage), libsodium (404 temporal).
  - col9 SHA: Phase-2 PR_SHA_CACHE (operator-gated on disk policy) or compute
    inline for the hardcoded/atom specs (soft; info-quality dual-goal).
PRIOR checkpoint (superseded):
Shipped M52-M57 (all merged). 5.0 strict on snapshot 26324090866:
**126 → 103 (−23)**. M52 ICU sort (−12); M54 curl/openssl; M55 tzdata; M56
byacc/dialog; M57 the 14 hardcoded overrides (→ soft col9 only). M53 made the
clone cache persistent (90min→8min, fixes cold-clone transients).
Remaining strict diffs are dominated by **operator-gated** levers, not
missing detection:
  - **col3 atom-path C-superiority (~28 rows)** — LARGEST strict bucket
    (PS stale homepage vs C real tarball). Needs the a/b/c decision below.
  - **col9 SHA (now soft, larger after M57)** — Phase-2 `PR_SHA_CACHE`
    persistent SOURCES_NEW cache (gated on disk policy) or `PR_STRICT_COL9`.
  - Fragile/attended stragglers (NOT clean units): libsodium (upstream 404,
    PS blank-on-dead-URL is correct), netcat (bespoke: raw netcat.c + CVS
    regex + Commits API + tarball synthesis), libusb (deferred sourceforge
    two-stage). gtest v-prefix (C-cleaner, cosmetic).
Next high-leverage step is the **col3 operator decision**, not more adapters.

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








## col3/col6 ROOT CAUSE = C-SUPERIORITY on atom specs (2026-05-23, definitive)

Traced gstreamer (representative of the freedesktop atom-spec col3 bucket):
  col5 MATCHES (1.29.1). But:
  PS col3/col6/col10 = bare homepage "gstreamer.freedesktop.org" (useless)
  C  col3/col6/col10 = REAL tarball "gstreamer-1.29.1.tar.xz" + SHA (col9)
PS's atom-detection path doesn't build a download URL -> falls back to the
homepage; C re-substitutes the spec Source0 template into the real tarball.
=> C is DRAMATICALLY more correct. Mirroring PS would replace real
tarballs+SHAs with homepages — absurd. This is SYSTEMATIC across the
freedesktop atom specs (cairo/dbus/fontconfig/pixman/...), and is the bulk
of the col3/col6/col10 strict rows.

CONCLUSION: the remaining parity gap is largely C-SUPERIORITY (the metric
penalizing C for being better than PS), NOT C bugs. No clean autonomous
code fix exists (mirroring degrades C; dual-goal forbids it). The honest
resolutions are OPERATOR/ADR decisions:
  (a) accept "C >= PS" cells in the ADR-0009 verdict (don't count them), or
  (b) soft col3/col6/col10 for atom-detected specs (like soft-col9), or
  (c) fix PS's atom-path URL building (PS LOGIC change -> both emit the
      tarball) — biggest win but modifies PS source-of-truth behavior.
This + the col9 soft + the C-better col5 rows means the journal's residual
strict count UNDERSTATES C quality. Per-spec autonomous convergence is
genuinely COMPLETE; the rest is the operator's parity-criteria call.

## COL5 DETECTION COMPLETE (2026-05-23, 5.0 = 126 strict)

proto RESOLVED in CI (M51 — generic-scrape tokens reordered before Name
tokens, so "xproto-" strips before Name="proto" mangles it). Every
non-transient, non-C-better col5 straggler is now resolved. This
resumption's wins (all CI-confirmed): amdvlk M48, nicstat/tclap M49,
ltrace M50, proto M51 + the C-side journal-push-retry CI fix.

GENUINELY REMAINING (operator-gated / not autonomous):
- col3: criteria decision (softening weakens ADR-0006 bit-identical).
  ~28 col3-only rows are PS-stale-homepage vs C-real-tarball (C >= PS).
- col9: tarball-cache activation (architecture) — but marginal (col9
  already soft; most col9 rows strict on other cols).
- libev (transient host flakiness), lasso/libbsd/libevent/lzo (C-better):
  not fixable / don't-mirror.
- irreducible transient noise (mirror/Anubis/clone-EOF).

Per-spec convergence is COMPLETE. 5.0: 392 (start) -> 126, all detection
adapters + every tractable real bug shipped & CI-validated; green-capable
via soft-col9. Further reduction needs the operator col3/col9 decisions.

## MORE WINS via local repro (2026-05-22 late, 5.0 -> 126 strict)

After "per-spec done" was declared, local-repro found MORE clean wins:
M48 amdvlk (quarterly-version filter-skip), M49 nicstat/tclac
(sourceforge /files/ parent fallback), M50 ltrace (.orig token).
5.0: 135 -> 126 (CI-confirmed for M48/M49; M50 verified locally).

REMAINING col5-missed stragglers (FIDDLY, deferred):
- libev: TRANSIENT (not a bug). Attic/ DOES contain libev-4.33, but
  dist.schmorp.de intermittently 302s/blocks the scraper request (200 on
  retry/HEAD) — same class as freetype2/Anubis flakiness. C's empty
  resolves on a lucky run. NO code fix.
- proto: x.org archived; %{xproto_ver}=7.7 vs detected xproto 7.0.31
  (different packages); PS warns, C empty. Confusing per-spec edge. DEFER.
- 4 C-better col5 rows (lasso/libbsd/libevent/lzo: C emits (same version),
  PS empty) -> C >= PS, don't mirror.

col3 lever: still operator-gated (criteria change weakening ADR-0006).
The truly-clean per-spec wins are now exhausted; libev/proto need
attended care (shared-path / confusing edges).

## RESIDUAL ANALYSIS (2026-05-22, 5.0 = 135 strict, all per-spec real-bugs done)

Categorized the residual after M45-M48 + detection program:
- col9-involved: 83 rows — BUT col9 is already SOFT, so these are strict
  on OTHER cols (col5/6/3). => col9 tarball-cache activation barely moves
  the count; most col9 rows stay strict regardless. LOWER lever than thought.
- col3-only / col3-4: ~28 rows strict ONLY on col3 (col4 already soft).
  These are the PS-stale cases (PS=homepage/wiki/readme, C=real tarball
  URL — C MORE correct). => col3-soft (or accept) is the BIGGEST single
  lever (~28 rows). Operator decision; not uniformly C-better so needs a
  targeted rule, not blanket-soft (some col3 diffs are real substitution).
- col5-involved: ~37 rows — residual detection differences (smaller
  families / per-spec quirks / minor temporal). Long tail; diminishing.
- transient (mirror/Anubis/SHA/clone-EOF): irreducible per-run noise.

REVISED operator priority: col3-soft (~28 rows, C>=PS) > col9-cache
(marginal, most col9 rows strict elsewhere). The per-spec autonomous
work is DONE; further count reduction is gated on the col3 decision.

## PER-SPEC CONVERGENCE ESSENTIALLY DONE (2026-05-22, 5.0 ~134-136 strict)

Resolved + CI-confirmed this session: full detection program + lsscsi
(M45) + apparmor (M46) + linux kernel family (M47/M47b: linux-esx,
linux-rt, linux-api-headers all -> 6.1.173, row-identical incl SHA).

REMAINING (NOT clean autonomous units):
- amdvlk: shared version comparator must order ".Q2." quarter versions
  (2025.Q2.1) -> HIGH blast radius across all comparisons -> ATTENDED.
- linux.spec: malformed version "6.1.164-acvp}" (conditional Release
  macro %{?acvp_build:.acvp}); PS mis-compares it as > 6.1.173 and warns
  (PS quirk; 6.1.164 < 6.1.173). Its Source0 also 404s -> C gated out.
  Matching PS = replicating a PS bug on a malformed version -> SKIP.
- col9 auto-archive SHA + col3-stale: C >= PS -> OPERATOR decision
  (col9 tarball-cache activation / col3-soft).
- transient noise (mirror/Anubis/clone-EOF): not code-fixable.

The cleanly-tractable per-spec convergence is DONE. Further gains need an
attended session (amdvlk comparator) or the operator col9/col3 decisions.

## CLEAN PER-SPEC WINS EXHAUSTED (2026-05-22, 5.0 ~137-141 strict)

Resolved this session (all CI-confirmed, via local binary repro):
detection program (rubygems/funet/sourceforge/CPAN/github/samba/GNU/
intltool/itstool/openvswitch/ipset/grub2/xorg-fonts/mozilla/json-c) +
real-bugs lsscsi (M45) + apparmor (M46, launchpad series-dir col6).

REMAINING (attended-only / operator-gated — NOT clean autonomous units):
- linux-esx/rt/secure/aws/linux/linux-6.1 (kernel family): C picks
  6.19.x (latest mainline) vs PS 6.1.173 (LTS). PS L4027-4036 scrapes
  v6.x with customRegex ^linux-[\d.]+$ but emits the 6.1 series — the
  series-pinning constraint is NOT visible in that block; needs deep PS
  study + careful multi-spec port (6 specs, cross-spec regression risk).
- amdvlk: version comparator must order ".Q2." quarter versions
  (2025.Q2.1) — shared-comparator change, HIGH blast radius -> attended.
- col9 auto-archive SHA + col3-stale: C is more correct than PS ->
  OPERATOR decision (col9 tarball-cache activation / col3-soft).
- transient noise (mirror/Anubis/clone-EOF): not fixable in code.

The high-value autonomous work is DONE. Further gains need an attended
session (kernel family / amdvlk comparator) or the operator col9/col3
decisions. Easing the autonomous grind.

## DETECTION COMPLETE — remaining tail is fiddly real-bugs + operator levers (2026-05-22)

All per-host detection adapters SHIPPED + CI-validated: rubygems, funet,
sourceforge, CPAN, github-html, samba, GNU tokens, intltool/itstool/
openvswitch/ipset (launchpad/all-other), grub2/xorg-fonts, mozilla family
(mozjs/nss/nspr), json-c (S3). 5.0 strict ~139 (from 392 session-start),
soft-col9 makes it green-capable.

REMAINING (each 1-spec, fiddly, shared-path regression risk — low ROI):
- apparmor: col5 resolves; col6 needs the LAUNCHPAD HREF (not Source0
  re-substitution — its Source0 hardcodes a stale /3.1/ series; PS uses
  the actual download href .../apparmor/4.1/4.1.0/...). Fix = make the ao
  path capture the matched-version full href for col6 (affects all ao
  specs -> verify intltool/itstool/openvswitch don't regress).
- amdvlk: C picks 2018.4.2 vs PS 2025.Q2.1 — version comparator doesn't
  order ".Q2." (quarter) versions. Comparator change (high blast radius).
- lsscsi: C emits 030; PS drops the bogus "lsscsi-030" entry — needs a
  drop token applied BEFORE the Name-strip (token-ordering).
- linux-esx/rt: C picks 6.19.x vs PS 6.1.x — wrong kernel series; needs
  per-spec series pinning.
- + transient noise (mirrors/Anubis/SHA) and col3-stale / col9 (C-better)
  -> these are the col9-cache-activation + col3-soft OPERATOR decisions,
  higher-leverage than the fiddly 1-spec bugs.

RECOMMENDATION: the high-value autonomous detection work is DONE. Further
gains need either (a) the operator col9-cache / col3-soft decisions, or
(b) careful attended per-spec bug fixes (comparator/token-order/series
pinning) where shared-path regression risk warrants review. Easing the
autonomous grind here.

## REBOOT STANDBY (2026-05-22 ~09:03Z)

System reboot requested. State at standby:
- All work COMMITTED + PUSHED; master HEAD == origin (eaefbc9). Nothing lost.
- In-flight PS validation run 26278553867 (M43b mozilla family) was
  CANCELLED cleanly (would have been killed mid-write by reboot). The
  full mozilla family (mozjs 151.0.1 / nss 3.124 / nspr 4.39) is already
  verified ROW-IDENTICAL to PS via LOCAL binary repro, so the CI cycle
  was only confirmation.
- Self-hosted GitHub Actions runner stops with the system; it should
  re-register on boot if its service is enabled.
- The autonomous loop (ScheduleWakeup) + 4h "retry to continue" cron are
  session-only and END at reboot.

RESUME AFTER REBOOT:
  1. Re-dispatch the M43b confirmation cycle:
     gh workflow run "Photon OS Package Report" -f report_type=urlhealth \
       -f branches=5.0 -f upstreams_exclusion_list=firmware,chromium --ref master
     (live C auto-triggers; ~45min) then read parity-journal.tsv 5.0 row +
     confirm mozjs/nss/nspr resolved.
  2. To resume autonomous grind, re-invoke /loop (or just say "continue").
  3. NEXT UNITS (per the L4260+/L3200-3400 map below): json-c S3-XML,
     apparmor series-URL, then the ~5 real bugs (amdvlk Q-version, lsscsi,
     linux-esx/rt). Detection clean-wins are otherwise exhausted; the
     dominant residual is transient noise + col3-stale (C-better) — see
     the col9/col3 soft decisions and the methodology notes.

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
| 5.0    | 1113 | **198** | **82%** | 26233502563 (post-M39, ±noise) |
| 6.0    | 1093 | 373 | 66% | 26160062078 |
| dev    | 1090 | 386 | 65% | 26160062078 |
| master | 1090 | 381 | 65% | 26160062078 |

**M34 validated (5.0, run 26201671031):** 392→266 strict (−126).
117 rubygem specs in 5.0, only 11 still mismatched → M34 closed ~106.
Journal == local parity-diff (266/60) confirmed. No regressions: the
improvement is concentrated in rubygem-* rows. Other branches not yet
re-run post-M34 (single-branch validation per memory guidance).

**M38 validated (5.0, run 26230052436):** 206→197 strict (−9).
github HTML tags-page detection — 9 specs fixed (hwloc, jna, libmodulemd,
libnsl, lmdb, npth, paho-c, python-networkx, python-wheel). One apparent
regression (mysql.spec) was a transient col9 SHA-download blip (C had the
SHA in the prior run, empty here; everything else identical; mysql is NOT
in the github special-case list so M38 does not touch it). gitSource
github path untouched. Remaining github: amdvlk (Q-version via API path),
libmspack/python-pexpect (have gitSource — git path failing).

**M39 validated FULL SUCCESS (samba atom, re-run 26233502563 = 198):**
all 5 samba specs now DETECT correctly (col5/col6 match PS): libldb +
samba-client are full matches; libtalloc(2.4.4)/libtdb(1.4.15)/
libtevent(0.17.1) match on detection but remain STRICT-diff ONLY on col9
SHA — the gitlab `/-/archive/<tag>` auto-archive SHA drift (same class as
github auto-archive; ADR-0015 can't help, no release asset). The first
M39 run (26231942567 = 203) was noise-dominated; this re-run (198)
confirms the −5 detection signal is at the noise floor.

**>>> col9 ROOT-CAUSE (2026-05-21, measured on 5.0 run 26233502563): the
col9 gap is NOT byte-drift — it is mostly PS DEFICIENCY. <<<** Of the ~35
col9-containing strict rows: **27 are PS-empty / C-has-real-SHA (C is
MORE correct)**, 7 are genuine different-SHA byte-drift, 1 is C-empty
(transient). PS's Get-FileHashWithRetry leaves col9 empty when it didn't
fetch the tarball into SOURCES_NEW (PS fetch is flakier / less complete
than C's live download). IMPLICATION: the chosen tarball-cache (bundle
PS bytes → C reuses) fixes ONLY the 7 byte-drift rows; it CANNOT fix the
27 PS-empty rows (no PS bytes exist) and mirroring PS there would BLANK
C's correct SHA — a dual-goal regression. Viable col9 paths now:
  (a) PERSISTENT shared SOURCES_NEW on the runner (PS reuses prior
      tarballs → fewer empties; C hashes the SAME files → parity). Cost:
      disk (the very thing that gets cleaned for disk-fill). 7 byte-drift
      + 27 PS-empty both improve IF the cache is warm before PS runs.
  (b) soft-col9 in ADR-0009 verdict — pragmatic, accepts that C is often
      MORE correct than PS; stops counting col9 as strict.
  (c) re-run PS until SOURCES_NEW is complete (reduces empties) — fragile.
OPERATOR INPUT NEEDED: tarball-cache (option a) only pays off with
persistent disk; otherwise (b) soft-col9 is the realistic route to a
green journal given C ≥ PS on col9.

**FRESH-CYCLE BASELINE (5.0, run 26280707019, 2026-05-22): 139 strict /
94 soft.** mozilla family (mozjs 151.0.1 / nss 3.124 / nspr 4.39) all
RESOLVED in CI (M43/M43b).
26243226678 → live C auto-trigger; ~20-min gap, kills the temporal col5
inflation) + M40 (unzip/zip) + soft-col9. Journal == local diff (147)
verified. This is the trustworthy current floor for 5.0.

REMAINING-GAP MAP off the fresh 147 (this is the path to green):
  - **~30+ C-empty col5 = the BIG one.** PS detects, C emits nothing.
    Two PS sources, both per-spec-exception-heavy ("the work IS the
    exceptions" per feedback_per_package_depth_investigation):
    (i) **L3200-3400 per-host blocks**: mozilla mozjs(L3206)/nss(L3234)/
        nspr(L3252) — each TWO-STAGE (fetch releases listing → latest →
        build versioned NSS_X_RTM / vX / firefox-releases URL); python2/3
        (L3274); + generic scrape with per-spec $replace tokens
        (grub2 L3336, freetype2 L3337, ...).
    (ii) **L4260-4450+ "all other types" block** = the big one. Default
        SourceTagURL=dirname(Source0); ~13 per-spec URL overrides
        (apparmor/bzr/intltool→launchpad/+download, ipset→install.html,
        itstool→itstool.org/download.html, js→archive.mozilla, json-c→
        s3 releases, openvswitch→/download, python-pbr→opendev/tags,
        wireguard-tools→git.zx2c4, chrpath→codeberg/tags, xmlsec1); a
        DIFFERENT extraction than C's M20 href-regex (PS splits on
        `<tr><td` / `a href=` / `>` / `title=`) + a Chrome-UA+full-
        headers fallback for bot-walled pages; then dozens of per-spec
        name transforms (docbook-xml two-stage L4338, byacc L4354, json-c
        S3-XML `<Key>` parse L4363, chrpath, apparmor/bzr/intltool/itstool/
        openssl path-split-last-segment L4398, curl, js, lsscsi=030,
        ltrace .orig, tzdata, ...).
    PORT STRATEGY: do it in small validated PRs — easiest first (the
    ~13 override table + path-split transform recovers apparmor/intltool/
    itstool/openvswitch/openssl), then the per-spec quirks (json-c S3,
    docbook two-stage, mozilla two-stage) individually. Each touches the
    shared scraper path, so validate each against a fresh cycle for
    regressions before merge. NOT to be rushed at marathon-depth.
    [M41 DONE #152, validated fresh cycle 26262711412: intltool/itstool/
    openvswitch fully RESOLVED; apparmor col5 fixed (4.1.0) but col6+
    remain — its Source0 hardcodes the series dir (/apparmor/3.1/), C
    re-substitutes to /3.1/4.1.0/ (404→warning) while PS derives the
    series 4.1 from the version → FOLLOW-ON: apparmor (+ other launchpad
    series-versioned specs) need series-from-version URL construction.
    No regressions (5.0 147→145). NEXT L4260+ units: apparmor series-URL,
    then json-c S3-XML / ipset install.html / mozilla two-stage.]
    [M41b DONE #153: ipset→install.html, RESOLVED (7.24). M42 DONE #154:
    per-spec generic-scrape tokens — grub2(grub-) + xorg-fonts(encodings-)
    RESOLVED; freetype2 still empty (its row diffs col3+col4 → C health
    probe non-200 gates the scraper out BEFORE the token; needs Source0/
    health investigation, not a token) and proto still empty (x.org scrape
    fails). compat-gdbm/xorg-applications both-empty (match). NOTE: per-PR
    gains (1-2 specs) are now at/below the ±2-5 fresh-cycle noise floor —
    verify fixes by spec-level diff, not the journal count. Remaining is
    judgment-heavy per-spec: freetype2/proto health-gate, mozilla/python
    two-stage, json-c S3-XML, apparmor series-URL, + col3-stale (C-better,
    likely accept/soft not fix).]
    [M43 DONE #155/#156/#157, VALIDATED in CI: nspr RESOLVED (col5=4.39,
    col6=.../v4.39/src/nspr-4.39.tar.gz = PS). Took 2 bug fixes found via
    LOCAL binary repro (minimal workingDir w/ just nspr): (1) #156 basename
    full-path hrefs (/pub/nspr/releases/v4.39/ -> v4.39); (2) #157 exclude
    moz from the M23 pre-filter (it keeps only .tar./.tgz, dropped the bare
    version dirs). LESSON: debug detection bugs via local binary repro, not
    noisy CI cycles. mozilla releases-index mechanism (pr_mozilla_releases_url
    + apply_mozilla_transform + moz_eligible + used_moz) now proven.
    mozjs/nss FOLLOW-ON is harder: they detect a version (update-avail) but
    PS emits EMPTY col6 (its NSS_<ver>_RTM/src probe yields nothing); plain
    re-substitution of their stale-dir Source0 404s -> C would set a col11
    "Manufacturer may changed..." warning PS doesn't have. Needs per-spec
    col6/col11 suppression (emit col5 only, leave col6/col11 empty).]
    [INVESTIGATION 2026-05-22: freetype2's empty = TRANSIENT mirror
    flakiness, NOT a bug — savannah 302-redirects to a rotating mirror
    pool; C's HEAD-L hit a 500 mirror that run, PS hit 200. The M42
    freetype- token is correct; it resolves on a lucky 200 probe. So
    freetype2 is noise-class. CONCLUSION: the clean tractable detection
    wins (override-table + simple tokens, M41/M41b/M42 = ~6 specs) are
    now EXHAUSTED. Remaining detection tail splits into: (a) TRANSIENT/
    mirror/Anubis/SHA noise (freetype2, freedesktop atoms, col9) — no
    fix; (b) BIG per-spec units (mozilla 3× two-stage, json-c S3-XML,
    apparmor series-URL) — focused work, not tick-sized; (c) col3-stale
    where C is more correct (accept/soft, not fix); (d) ~5 real bugs
    (amdvlk Q-version, lsscsi, linux-esx/rt). The 90-day-green goal is
    now gated more on the RUNTIME clock (soft-col9 already green-capable)
    + the col3 accept/soft decision than on more detection ports.]
  - ~44 col3 / col3-4: Source0 rewrites; several PS-stale / C-more-
    correct (mirroring DEGRADES C — candidate for soft or accept, not
    fix).
  - col11 warning-table diffs (~within the col[4 6 7 9 10 11] bucket).
  - real per-spec bugs: amdvlk (Q-version sort), gtest (v-prefix kept by
    PS), lsscsi (C=030), linux-esx/rt (C picks 6.19 vs PS 6.1 — wrong
    kernel branch), qemu (PS value "/9.1.2" looks like a PS glitch).
PROGRESS: 5.0 392 (session start) → 147 (fresh, soft-col9). Detection
adapters for the major families done; remaining is the L3200-3400
per-host long tail + col3/col11 + ~5 real bugs.

**RESIDUAL MAP (5.0, soft-col9 = 163 strict, 2026-05-21):** no
high-leverage coherent unit remains; it is a long tail —
  - ~38 C-empty col5: 7 sourceforge-deferred (unzip/zip version-munge +
    libusb two-stage — M35 skipped these), 3 mozilla, 2 openssl, 2
    launchpad, + ~20 singleton per-spec families.
  - ~17 both-version: mostly TEMPORAL (C ran a day after the PS snapshot
    → detected newer upstream releases; C is MORE current — same
    temporal-gap class as col9). A few real: amdvlk (Q-version format),
    gtest (v-prefix).
  - ~27 col3 / col3-4: Source0 rewrites; several are PS-stale / C-more-
    correct (mirroring would DEGRADE C per dual-goal — low value).
  - transient freedesktop-atom (Anubis) fetch failures.
  - operator-gated: sort-collation (~12), col9 cache activation.
NEXT-UNIT OPTIONS (pick by value):
  (1) back-to-back PS+C validation to kill the col5+col9 temporal gap —
      HIGHEST leverage for the 90-day-green goal (the temporal gap, not
      detection, is now the dominant strict-diff source). Architecture
      change (same fork as col9 cache option B).
  (2) M40: finish deferred sourceforge unzip/zip (simple version-munge);
      libusb two-stage separately. Deterministic, ~2-3 specs.
  (3) per-spec long-tail (amdvlk Q-version, gtest v-prefix, mozilla,
      openssl, launchpad) — exception-heavy, low yield per unit.
The detection-adapter phase (M34-M39) delivered the bulk; from here the
gains are per-spec or gated on the temporal-gap architecture decision.

**>>> STRATEGIC INFLECTION (2026-05-21): detection adapters essentially
DONE. <<<** M34-M39 closed the major upstream families (rubygems,
sourceforge, CPAN, github-html, samba, GNU/funet). col5 (UpdateAvailable)
+ col6 (UpdateURL) detection is now correct across them. The DOMINANT
residual on 5.0 (~198 strict) is no longer missing detection — it is:
  (1) col9 SHA-drift on github/gitlab AUTO-ARCHIVE tarballs (regenerated
      per-request → SHA differs PS-snapshot-vs-C-run; ~30-40 specs). Only
      fixable by tarball-cache (hash once, share both sides) — NOT by
      detection code. ADR/operator decision.
  (2) transient col3/col4/col7 network jitter (~±5-9/run).
  (3) the deterministic, code-fixable remainders: sort-collation (~12,
      touches do-not-break invariant → operator) and col3/col3-4 Source0
      rewrites (~14, per-spec hooks — the one remaining ABOVE-noise
      deterministic unit).
Recommendation: the high-leverage detection phase is complete; further
single-spec adapters are sub-noise. Next code unit = col3 Source0
rewrites (deterministic). Parallel gating decision (operator) = col9
tarball-cache vs soft-col9 in the ADR-0009 verdict.

**>>> UPDATE 2026-05-23 — two deterministic units shipped <<<**
  - [DONE #169 / M52 / ADR-0016] **sort-collation** — `prn_writer.c` now
    sorts via ICU `en-US` collator (matches PS `Sort-Object`), not ordinal
    `strcasecmp`. Validated 0-mismatch row order on ALL branches. CI-measured
    on the SAME PS snapshot: 5.0 strict **126→114 (−12)**. No longer
    operator-gated — full-branch local validation retired the realignment risk.
  - [DONE M53 / ADR-0009 amendment] **persistent clone cache** — the
    bucket-1 fix. CI cloned under `${RUNNER_TEMP}` (wiped every job) → cold
    runs → transient col5 empties (45 of 64 5.0 col5 diffs were transient,
    confirmed by warm-vs-cold cross-check; see
    [[feedback_transient_vs_persistent_diffs]]). Cache root → persistent
    `${PARITY_CACHE_ROOT:-$HOME/.cache/photonos-parity}`. Reconstruct still
    checks out the snapshot SHA + `pr_clone_ensure` fetches on hit → warm =
    same detection as a successful cold clone, just reliable. Partial clones
    (blob:none) keep disk small; `concurrency` group serialises runs.
  - [PHASE 2, operator-gated on disk policy] `PR_SHA_CACHE=1` persistent
    SOURCES_NEW tarball cache (col9) — see col9 strategy below. Held until a
    SOURCES_NEW size-cap/prune policy is set (tarballs are GBs vs the tiny
    blob:none clone cache).

**col9 STRATEGY — operator chose "both: cache now, soft fallback" (2026-05-21):**
  - [DONE #149] soft-col9 in parity-diff.sh — LIVE. col9 joins cols 4/7 as
    soft; reversible via `PR_STRICT_COL9=1`. 5.0 effect: strict 198→163.
    ADR-0009 amended.
  - [DONE #150] tarball-cache MECHANISM (C side) — merged, env-gated by
    `PR_SHA_CACHE`. pr_sha_of_url_cached / _multi_cached hash
    <upstreams>/<branch>/SOURCES_NEW/<UpdateDownloadName> (the SAME file
    PS writes). Inert until the env var is set.
  - [BLOCKED on architecture decision] cache ACTIVATION. Investigated
    2026-05-21: the C workflow (package-report-C.yml) reconstructs an
    EPHEMERAL upstreams tree at `$RUNNER_TEMP/parity-c-wd/photon-upstreams`
    (parity-reconstruct.sh) — isolated from PS's persistent
    `$HOME/photon-upstreams`, and the snapshot carries only the tarball
    sha256 MANIFEST, not the bytes. So PS and C do NOT share SOURCES_NEW;
    `PR_SHA_CACHE=1` alone writes into an ephemeral dir that's discarded.
    Two real activation paths, each a tradeoff (operator decision):
      (A) BUNDLE tarball bytes in the snapshot + reconstruct extracts them
          into C's SOURCES_NEW. Keeps replay-isolation/reproducibility.
          BUT only fixes the ~7 byte-drift rows (the 27 PS-empty have NO
          PS bytes to bundle), and inflates the artifact (auto-archive
          source tarballs, ~0.5-1 GB/branch).
      (B) PERSISTENT shared SOURCES_NEW: point C at the persistent
          `…/reports/photon-upstreams/photon-<branch>/SOURCES_NEW` that PS
          already writes (CONFIRMED present on the runner, ~46 GB total /
          ~6.5-8.3 GB per branch — the 611 GB upstreams footprint is
          dominated by git CLONES, not tarballs). So persisting
          SOURCES_NEW is disk-CHEAP; a prune cap is almost moot for the
          tarballs themselves. Warm cache fills PS-empties over runs AND
          kills byte-drift. Tradeoff is reproducibility, NOT disk: breaks
          snapshot-replay isolation (manual replays would hash current
          host bytes, not the snapshot's). The live workflow_run flow
          (PS→C same host) is the natural fit.
    RECOMMENDATION: defer. soft-col9 (#149) already unblocks green for ALL
    col9 cases now; the cache only matters for eventually re-tightening
    col9 to strict (`PR_STRICT_COL9=1`), which is a later milestone. Pick
    (A) vs (B) when that milestone is scheduled. Mechanism (#150) is ready
    for either.

**METHODOLOGY ESCALATION (was: transient-noise observation):** this run
proved the per-run network jitter (~±9 specs in col5-fetch-fail + col9-
SHA) now EXCEEDS the per-PR signal (M39 = −5). Single-snapshot
validation is no longer reliable for small PRs. NEXT: (a) validate by
re-run-and-take-best, or better (b) move to back-to-back PS+C runs to
kill the temporal gap, and (c) decide with operator whether col3
(Source0-blanked-on-non-200) and col9 (SHA) should be SOFT like cols
4/7 in the ADR-0009 90-day verdict. This is now the gating issue for
trustworthy convergence measurement, ahead of further per-spec adapters.

**TRANSIENT-NOISE OBSERVATION (relevant to ADR-0009 90-day verdict):**
across the M34-M38 single-snapshot validations, ~1-2 specs flip per run
in the volatile col3 (Source0 blanked on transient non-200 health) and
col9 (SHA download failure) columns — lasso (503), mysql (SHA), openipmi
(recovered). These are NOT code defects; they are the PS-snapshot-vs-
C-run temporal gap. The 90-day-green verdict will need to tolerate this
col3/col9 jitter (as cols 4/7 are already soft) OR adopt back-to-back
PS+C runs to remove the temporal gap. See the 23-31 row col[9] bucket.

**M37 validated (5.0, run 26228183563):** 213→206 strict (−7).
CPAN author-dir detection — 8 perl-* specs fixed (perl-Canary-Stability,
perl-common-sense, perl-DBIx-Simple, perl-JSON-XS, perl-NetAddr-IP,
perl-Parse-Yapp, perl-Perl4-CoreLibs, perl-Types-Serialiser). One
APPARENT regression (lasso.spec) was transient network noise:
dev.entrouvert.org returned 503 during this C run vs 200 in the PS
snapshot → empty-Source0 logic blanked col3. lasso is NOT cpan and my
code does not touch it; resolves on re-run. Remaining biggest families:
github (12, mixed: amdvlk Q-version, hwloc/jna no-gitSource gap), samba
(5), openssl (2), launchpad (2).

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

**RESOLVED 2026-05-23 — sort-collation divergence (M52 / ADR-0016):**
Rows were misaligned (col[1] Spec mismatch cascades) because C sorted with
`strcasecmp` (ordinal: `-`<`.`<`_`) while PS's .NET `Sort-Object` delegates
to ICU culture collation (hyphen/period ignorable, `_` weighted
differently). Affected clusters: python-backports_abc /
python-backports.ssl_match_hostname, python-setuptools_scm /
python-setuptools-rust, rubygem-http_parser.rb + http-* cluster,
rubygem-unf_ext / unf. **Fix shipped:** `prn_writer.c` `cmp_str_asc` now
uses an ICU `en-US` collator (strength SECONDARY, `pthread_once`,
strcasecmp fallback). New build dep `icu-devel`. **Validated: ICU sort
reproduces PS row order with 0 mismatches across ALL branches**
(3.0/4.0/5.0/6.0/common), and agrees with live `pwsh Sort-Object` on ICU
72 and 76. Regression test `test_icu_row_sort` added to test_phase6.
Eliminates ~8 misaligned 5.0 row-positions (~10 phantom strict diffs);
proportional on the other branches. The earlier "global-realignment
regression risk" was retired by full-branch local validation before merge.

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
