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

**FRESH-CYCLE BASELINE (5.0, run 26262711412, 2026-05-22 01:46): 145
strict / 98 soft.** (was 147 pre-M41.) Achieved via: fresh same-hour PS→C cycle (PS
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
