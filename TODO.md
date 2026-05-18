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

### Initial priority bucket list

(To be filled in from Stage 2 outputs. Skeleton based on prior
4.0/5.0 PS-side analysis that already exists in
`docs/prn-analysis/photon-4.0.md` and `photon-5.0-normal.md`. The
C-side diff buckets may differ — Stage 2 will show.)

- [ ] **Bucket 1 — SHAName (col 9) always empty in C.**
      C port doesn't compute SHA-512 of UpdateURL body.
      Affects: every spec with a populated UpdateURL on the PS side
      (~80% of "complete" PS rows). Highest leverage.
      Touches: new `src/sha512_download.c`, `pr_clone_ensure` companion.
      FRD: extend FRD-014 (.prn row assembly).
- [ ] **Bucket 2 — warning (col 11) always empty in C.**
      C port doesn't emit the warning strings ("Manufacturer may
      changed version packaging format", "Info: VMware internal URL",
      etc.). Affects: ~100 specs per branch.
      Touches: `src/check_urlhealth.c` per-warning emission logic.
      FRD: extend FRD-011 (CheckURLHealth orchestrator).
- [ ] **Bucket 3 — ArchivationDate (col 12) always empty in C.**
      C port reads it from lookup row but may not propagate. Affects:
      every archived spec (~5 per branch). FRD-014.
- [ ] **Bucket 4 — `pinned` short-circuit (SPECS/91, SPECS/90).**
      C port doesn't recognise the subrelease path → walks full
      pipeline → diverges. Affects: 16 specs (91) + ~53 specs (90)
      once snapshot refreshes. New FRD or extension of FRD-002
      (parse_directory).
- [ ] **Bucket 5 — Source0 substitution edge cases.**
      Specific cols 2/3 mismatches indicating substitution gaps
      (GitHub archive-URL, RubyGems, CPAN, X.Org). Each
      sub-bucket = one PR. PS-side already has the logic; gap is in
      C. FRD-004 (substitution core).
- [ ] *(remainder filled by Stage 2 data)*

---

## Stage 4 — Per-release × subrelease coverage

The PS workflow currently outputs **one `.prn` per branch**. SPECS/90
and SPECS/91 rows are folded into the parent branch's `.prn` and
identified via the `vendor-pinned (subrelease N)` warning + `pinned`
sentinel in col 4.

- [ ] **Decision A:** Keep the single-file-per-branch layout, with
      pinned-emit logic recognising SPECS/<N>/. Lowest impact on tooling.
- [ ] **Decision B:** Split `.prn` per subrelease
      (`photonos-urlhealth-5.0-90.prn`, `-91.prn`, default).
      Requires per-subrelease GeneratePhXURLHealthReport flag,
      `.prn` filename change, parity-diff awareness, journal schema
      update. Higher impact.
- [ ] **Required ADR.** Whichever decision is made, capture it in
      `specs/adr/0012-subrelease-output-layout.md`. Reviewed +
      Accepted before any task in this stage starts.

---

## Stage 5 — Source0Lookup split decision

Today: one embedded CSV at PS L 509-1366 (~855 rows) shared across all
branches and subreleases.

Risk: ambiguity when a spec has different upstream conventions per
release. E.g. `dbus` SPECS/91 → pinned, SPECS/main → upstream; same
`Source0Lookup` row applied to both yields a wrong result in one case.

- [ ] **Survey** how many specs would actually need per-release
      divergent Source0Lookup entries. Likely small set — mostly
      vendor-pinned subrelease entries.
- [ ] **Option A:** Add a `subrelease` column to the CSV; PS picks
      the row matching the current SPECS subpath. Backwards-compatible.
- [ ] **Option B:** Split CSV into per-release files at PS-source
      level (`Source0Lookup-3.0`, etc.). Larger churn; needs each
      .ps1 maintainer touching the right file.
- [ ] **Option C:** Status quo. Document the limitation in
      `docs/maintainer-runbook.md` §1. Lowest cost; accepts the few
      cases where per-release differs.
- [ ] **ADR:** `specs/adr/0013-source0lookup-per-release.md`. Reviewed
      + Accepted gates this work.

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

These are non-trivial / non-reversible decisions where the agent
should stop and confirm rather than guess:

1. **End of Stage 2** — diff-signature taxonomy. Confirm the buckets
   before mass-generating fix PRs.
2. **Before Stage 4** — single-file vs. split-`.prn` (ADR-0012).
3. **Before Stage 5** — Source0Lookup CSV restructure (ADR-0013).
4. **Stage 6** — VPN/proxy provisioning decision.
5. **Before any PS-side edit that touches more than 3 lookup rows**,
   or any change to the substitution sequence at PS L 2161-2199
   (CLAUDE.md invariant 3).

For everything else: proceed.

---

## Update protocol for this file

This file is the source-of-truth for outstanding work. Each merged PR
ticks off the relevant `[ ]`. The agent may add tasks under any stage;
removing or rewording a stage requires user confirmation. Stage
ordering is descriptive, not prescriptive — Stage 3 PRs interleave
with Stage 1/2 as opportunity allows.

Updated whenever a PR lands; spec/task IDs preserved for traceability.
