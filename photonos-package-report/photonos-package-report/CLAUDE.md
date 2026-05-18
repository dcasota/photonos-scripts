# photonos-package-report (C port) — Project Context

This sub-project is a 1:1 C migration of the parent
`photonos-package-report/photonos-package-report.ps1` script (5,522 lines).

## Invariants (all Claude Code sessions inherit these)

1. **Bit-identical output to the PowerShell script is non-negotiable.** Performance is secondary. Never introduce an "improvement" that changes a `.prn` byte unless an ADR explicitly accepts it.
2. **`../photonos-package-report.ps1` is the upstream source-of-truth.** Never modify it from this sub-project. Bugfixes flow PS → spec → C, not the other way around.
3. **No reordering of mutations on `$Source0`** when porting. The substitution sequence at PS lines 2161-2199 must be translated in source order, line for line.
4. **Photon-only.** Build and run on Photon 5/6 with `tdnf`. No portability hooks for Debian/RHEL/etc.
5. **No Python in the build pipeline.** Generators are POSIX shell + awk only.
6. **No Factory.ai droids.** Agents run exclusively as Claude Code subagents declared in `.claude/agents/*.md` (see ADR-0011).

## SDD lifecycle

```
PM agent → Dev Lead → Architect → Developer → Code
```

Every code change traces back through `specs/tasks/README.md` → FRD → ADR → PRD. Status of each spec moves Draft → Reviewed → Accepted → Implemented.

## Commit message template (enforced via tools/git-hooks/commit-msg)

```
phase-<N> task <NNN>: <imperative subject>

FRD: FRD-<NNN>
ADR: ADR-<NNNN>[, ADR-<NNNN>...]
PS-source: photonos-package-report.ps1 L <start>-<end>
Parity: <strict|soft|n/a>
```

## Build & test

```bash
cmake -B build -S .
cmake --build build
ctest --test-dir build
tools/parity-diff.sh build/photonos-package-report ../photonos-package-report.ps1
```

## Phase tracker (always include in status replies)

Numeric phases 0-9 are the linear code-port lane. Phase M is an
ongoing **parallel** track that picks up new sections of the maintainer
runbook as features land in the numeric phases — it is never "done"
while the tool is live.

| Phase | Title | Status |
|-------|-------|--------|
| 0  | SDD scaffold                                          | done (#52)  |
| 1  | Foundation (params, types, diskspace, git-timeout)    | done (#53)  |
| 2  | Spec ingestion (Get-SpecValue + ParseDirectory)       | done (#54)  |
| 3a | Source0LookupData embed (bash+awk + C parser)         | done (#55)  |
| 3b | spec-hook dispatch (extract-spec-hooks + skeletons)   | done (#57)  |
| 4  | Substitution core (%{url}/%{name}/%{version}/...)     | done (#58)  |
| 5  | Network & lookups (urlhealth, GitHub/GitLab tags, Koji) | done (#59) |
| 6  | CheckURLHealth main path + .prn assembly              | done (#60)  |
| 6b | Version-compare (`compare_versions`)                  | done (#61)  |
| 6c | Git-tag detection (GitHub/GitLab API + heuristics)    | done (#62)  |
| 6d | Local clone fetch + per-repo cache                    | done (#63)  |
| 6e | Heap-sort JDK URLs                                    | done (#64)  |
| 6f | SHA helpers + cross-branch diff (col 9 wired)         | done (#65)  |
| 7  | Cluster orchestrator + parallel runspace mirror (`-ThrottleLimit`) | done (#66) |
| 8  | CI side-by-side parity gate                           | done (#67)  |
| 8.5 | Parity convergence loop — per-bucket PS↔C diff fixes (see [TODO.md](../../TODO.md) §3) | in progress |
| 9  | Retirement (PS → staging/legacy/, C-only)             | pending (gated on 90d green journal) |
| M  | Maintainer ops + Phase 8.5 convergence backlog — see `specs/tasks/README.md` for M01-M21 task table and `TODO.md` for the dual-goal program (parity gap + vendor-info quality) | ongoing |

When you land a feature in a numeric phase that changes a workflow the
maintainer cares about (new flag, new override mechanism, new generator),
update the matching section of `docs/maintainer-runbook.md` in the same
PR. The runbook is the operability source-of-truth.

## Active program of work

[`TODO.md`](../../TODO.md) at the repo root tracks the in-flight
program of work — Phase-M backlog, Stage-3 per-bucket convergence
priorities, and the user-checkpoint list (now: ADR-0014 multi-SHA
Draft, on-demand VPN). Update TODO.md whenever a PR lands.

## Goal (dual, user-direction 2026-05-18)

The convergence loop targets TWO goals in parallel:

1. **Shrink the C↔PS `.prn` parity gap** — ADR-0009 90-day-green
   journal verdict is the floor.
2. **Maximize accessible vendor package information** — the cells
   `UpdateAvailable`, `UpdateURL`, `SHAName`, `UpdateDownloadName`
   should reflect upstream truth, not just C-matches-PS.

When goals conflict (PS has a stale URL and C mirrors it), prefer
fixing the Source0Lookup row / Phase-3b hook so BOTH sides improve.

## Session-context cheat-sheet (key findings preserved)

For a fresh session: the convergence loop has shipped M01-M21 in
Phase M, mostly bug-fixes / mirror ports of PS features the C port
lacked. The remaining gap is dominated by **per-package depth
investigation** (per-upstream-family scrapers, per-spec adapter
exceptions). See `feedback_per_package_depth_investigation.md`
memory entry.

**Architectural decisions made:** ADR-0012 (subrelease layout) and
ADR-0013 (Source0Lookup split) both Accepted as Option A (status
quo). ADR-0014 (multi-SHA) Draft, pending user decision.

**Critical mechanics**:

- `parity-diff.sh` compares `.prn` files **line-by-line at the same
  row index** — not joining on Spec. C's `.prn` row sort MUST match
  PS's `Sort-Object Spec, SubRelease` (case-INsensitive). Fixed in
  M14; before that, almost every row mismatched purely from sort
  order. If you ever change the row-output ordering, this is the
  one thing not to break.
- Source0Lookup matching is **case-SENSITIVE** (PS `.IndexOf`).
  Warnings/hooks are **case-INsensitive** (PS `-ilike`). Preserve
  this asymmetry — see `feedback_source0lookup_case_sensitivity.md`.
- `task.Version` is `"Version-Release"` form (PS L 281). `version_cut()`
  in `src/check_urlhealth.c` strips the trailing `-release` (with
  Photon dist-tag preservation) before substitution. This is M08.
- SPECS/91/ + SPECS/90/ subreleases short-circuit via M17's
  `pinned`-sentinel emission. parse_directory already captures
  task.SubRelease.
- HTTP listing scraping for non-git specs lives in `src/scraper.c`
  (M20, FRD-018). Filtered via M21 to drop sort-query hrefs and
  symlink-style names.

**Validation cadence:** every PR followed by a
`gh workflow run "Photon OS Package Report (C-side parity)"
-f snapshot_run_id=25991871716 -f throttle_limit=8` and a 1-2h
wait. Journal lands automatically. Diff baseline refresh via
`tools/diff_analyzer.py <PS-snapshot-dir> <C-artifact-dir>
docs/prn-analysis`.

**Known transient infra issues:**

- WSL2 host occasionally loses TLS connectivity to
  `*.actions.githubusercontent.com` (broker / pipelinesghubeus3)
  while `api.github.com` stays healthy. Symptom: runner offline +
  jobs stuck queued. Recovery: `systemctl restart
  actions.runner.dcasota-photonos-scripts.photon5-local.service`
  after connectivity returns. Seen 2026-05-17 and 2026-05-18.
- Disk-fill from on-demand clones on a non-`/tmp` non-cleaning path.
  Recovery: kill in-flight C binary, `rm -rf <upstreams-dir>`.
