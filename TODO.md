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

### Status — shared-infrastructure phase complete (M01-M21)

M01-M21 covered shared infrastructure: pinned-sentinel emission,
case-insensitive sort, version-cut, substitution rewrites, warning
table, replaceStrings application, post-strip filters, HTTP listing
scraper. Cumulative parity gap closed by ~30% (varies per branch).

See `specs/tasks/README.md` for the full M01-M21 task table.

### Residual buckets after M21 (the per-package depth territory)

Per `feedback_per_package_depth_investigation.md` memory entry: the
remaining gap is **per-package investigation** — each spec in these
buckets has its own upstream naming scheme / download convention /
update-detection mechanism.

Categories (approximate counts per 4.0 after M21 era):

- ~280 `UpdateAvailable,UpdateURL,SHAName,UpdateDownloadName,warning`
  GConf-style: scraper returns candidate name(s) but PS's downstream
  filtering / regex differs per upstream family.
- ~190 `UpdateAvailable,UpdateURL,SHAName,UpdateDownloadName`
  ImageMagick-style: C scraper picks a wrong "latest" because the
  per-family filter (release vs RC vs nightly) isn't implemented.
- ~75 `SHAName` only — github auto-archive instability. Defer or
  resolve via ADR-0014 (multi-SHA / stable-source SHA).
- ~70 `UpdateAvailable` only — non-git "(same version)" path not
  emitting when scraper finds the current version.
- ~65 `UpdateAvailable,warning` — autogen-style: PS detected
  "(same version)", C scraper picks up a sort-query-string href.
  Some covered by M21; remainder is per-spec edge cases.
- ~18 `Source0_modified` only — per-spec URL rewrite differences
  (ModemManager directory vs file URLs etc.).

### Next-units priority (dual-axis: parity + vendor-info)

| Unit | Parity Δ | Info Δ | Effort | Notes |
|---|---|---|---|---|
| **Per-upstream-family FRDs** | high | very-high | per-family weeks | gnome.org filter, sourceforge filter, launchpad filter — each refines what the scraper does for a specific listing layout |
| **ADR-0014 multi-SHA** Accepted + impl | medium | high | 1-2 PRs | drafted; awaiting decision |
| **M22+ Source0Lookup row repairs** | low | high | 1 PR per spec | one PR per dead-URL spec (bluez-tools→github, etc.) |
| **`(same version)` for non-git path** | medium | low | 1 PR | when scraper finds latest == current spec version |
| **`Clean-VersionNames` port** | medium | medium | 1 PR | additional post-filter from PS that's not yet ported |
| **ADR-0015 stable-source SHA** for github auto-archives | medium | high | needs ADR | switch col-9 source from auto-archive to release-asset where available |

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
4. **ADR-0014** — multi-SHA emission strategy. Draft pending user decision.
5. **Stage 6** — VPN/proxy provisioning decision (operator-only).
6. **Per-PS-edit guards** — any PS edit touching >3 lookup rows
   or the L 2161-2199 substitution sequence (CLAUDE.md invariant 3)
   still pauses for confirmation.

For everything else: proceed.

---

## Update protocol for this file

This file is the source-of-truth for outstanding work. Each merged PR
ticks off the relevant `[ ]`. The agent may add tasks under any stage;
removing or rewording a stage requires user confirmation. Stage
ordering is descriptive, not prescriptive — Stage 3 PRs interleave
with Stage 1/2 as opportunity allows.

Updated whenever a PR lands; spec/task IDs preserved for traceability.
