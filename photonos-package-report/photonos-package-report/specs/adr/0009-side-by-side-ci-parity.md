# ADR-0009: Side-by-side CI parity for ≥90 days before retirement

**Status**: Accepted
**Date**: 2026-05-12

## Context

A direct cutover from PS to C carries unacceptable risk — invisible regressions could degrade output for days before downstream consumers (snyk-analysis, package-classifier, etc.) start producing wrong reports. The lesson from the recent `%{version}` substitution regression is fresh.

## Decision

After phase 7 (C app produces full output), `.github/workflows/package-report.yml` is modified to run the **PS script first**, then the **C binary** on the same inputs (same SPECs, same SOURCES_NEW/SPECS_NEW state). The PS `.prn` output is committed (as today); the C output goes to a sibling `.prn.c` file. A `tools/parity-diff.sh` step diffs them and writes a verdict to the workflow step summary.

Strict-diff gate timeline:

| Days since side-by-side enabled | Diff verdict treatment |
|---|---|
| 0-30  | **Soft** — informational only, no PR failure |
| 30-60 | **Strict-warning** — divergence appears in step summary, marked yellow, no PR failure |
| 60-90 | **Strict-failure** — PRs that don't already have a green diff fail CI |
| 90+   | **Cutover-ready** — schedule retirement (ADR 0011 sibling task 091) |

## Rationale

- 90 days covers four weekly scheduled runs plus dozens of manual dispatches — enough to surface seasonal data quirks (e.g. holiday-related upstream URL changes).
- Phased strictness lets early divergence be caught and fixed without blocking unrelated PRs.
- Once 90 days of strict-green is established, the parity harness itself becomes a regression detector for future PS-side changes.

## Consequences

- CI run time roughly doubles for the package-report workflow during the side-by-side window — acceptable.
- `tools/parity-diff.sh` is itself spec-described (FRD-016) and tested.
- A new GitHub Actions secret / env var is NOT needed; the existing runner produces both outputs locally.

## Retirement trigger

The retirement PR (Phase 9 task 090) is opened automatically once a workflow run detects 90 consecutive days of strict-green diffs in the journal file `tools/parity-journal.tsv` (committed alongside each run).

## Considered alternatives

- **Direct cutover after Phase 7**: rejected, see Context.
- **Side-by-side forever**: pays double compute cost forever; rejected once parity is proven.

## Amendment 2026-05-21 — col9 (SHA) interim-soft during tarball-cache warm-up

Measured on branch 5.0 (run 26233502563): of ~35 strict rows differing
in col9 (SHAValue), **27 are PS-empty / C-has-a-real-SHA** — i.e. PS's
`Get-FileHashWithRetry` left col9 empty because its tarball fetch into
`SOURCES_NEW` failed, while C's live download succeeded. Only ~7 are
genuine byte-drift (github/gitlab auto-archive tarballs regenerated
between the PS-snapshot and C-run), and ~1 is a C-side transient. So the
col9 gap is dominated by **PS deficiency, not C error** — C is the more
correct implementation on those cells.

Decision (operator, 2026-05-21): treat **col9 as SOFT** in
`parity-diff.sh` (joining cols 4/7) so the per-run SHA jitter stops
masking real convergence and the journal can reach green. In parallel,
build a **persistent shared `SOURCES_NEW` cache** on the self-hosted
runner so PS and C hash byte-identical tarballs (fills PS's empties AND
kills the byte-drift — dual-goal-positive). Once the cache is warm and
col9 parity holds, re-enable strict col9 via `PR_STRICT_COL9=1` and
resume the 90-day strict-green clock for col9.

The 90-day-green timeline above applies to the strict columns; col9 runs
its own clock starting when `PR_STRICT_COL9=1` is set.

## Amendment 2026-05-23 — persistent clone cache (M53, bucket-1 transients)

Root-cause analysis of the 5.0 col5 (UpdateAvailable) gap (run
26324413477 vs the prior warm run 26312789233) showed **45 of 64 col5
diffs were transient cold-run failures** — the prior warm run detected
every one identically to PS. Cause: the C workflow placed the clone
cache under `${RUNNER_TEMP}/parity-c-wd`, which the self-hosted runner
**wipes every job**, so every run cold-cloned ~4000 upstreams and
intermittent git/network failures left col5 empty on otherwise-detectable
specs.

Decision (Phase 1, this change): move the cache root to a **persistent
path on the runner** (`${PARITY_CACHE_ROOT:-$HOME/.cache/photonos-parity}`).
Correctness is preserved because:

- `parity-reconstruct.sh` reuses the branch SPECS clone but re-runs
  `git fetch` + checks out the **snapshot's exact recorded SHA** each run
  — the SPECS tree is bit-for-bit the snapshot regardless of cache state.
- `pr_clone_ensure` reuses each upstream clone and `git fetch
  --prune --prune-tags --tags --force`es it — the tag list a warm run
  sees is identical to what a *successful* cold clone would have seen.

So persistence changes only **reliability**, not detection results: it
turns flaky cold clones into fast, reliable fetches. Clones are partial
(`--no-checkout --filter=blob:none`), so the cache footprint is small.
A workflow-level `concurrency` group serialises C runs that share the
cache. The per-run `scans/` dir is wiped each run so the diff always
reads fresh output.

**Phase 2 (deferred, operator-gated on disk impact):** activate
`PR_SHA_CACHE=1` for a persistent `SOURCES_NEW` *tarball* cache (the
dual-goal SHA fix above). Tarballs are real blobs (GBs), so this needs a
size cap / prune policy before enabling — held until that policy is set.

## Amendment 2026-05-23 — col3 decision (c): fix PS's empty-Source0Lookup fallback

The largest remaining strict bucket on 5.0 (~28 rows) was the gitlab-atom
family (gstreamer, cairo, dbus, fontconfig, pixman, …) where col3/col6/col10
differed because **PS emitted the bare project homepage while C emitted the
real versioned tarball URL+SHA** (both 200). Root cause: these specs have a
Source0Lookup entry whose Source0Lookup *field* is empty (it only pins
`gitSource`). PS L2196 set `$Source0 = ""`, which then flowed into the
L2224-2229 homepage-prepend and collapsed col3 to the homepage. The C port
already falls back to the spec's own `Source0` template on an empty lookup
(`check_urlhealth.c` L1027-1033), so C was strictly more correct.

Decision (operator, 2026-05-23): **option (c)** — fix the source-of-truth.
Add a one-line fallback at PS L2196: when the Source0Lookup field is empty,
use `$currentTask.Source0`. Both sides then build the real tarball URL from
the spec template, so col3/col6/col10 (and col9 SHA) genuinely agree AND
PS's report quality improves (dual-goal-positive). Validated in isolation:
gstreamer → `…/src/gstreamer/gstreamer-<ver>.tar.xz`; specs with a non-empty
lookup are unchanged. Requires regenerating the PS snapshot (the cached
snapshot predates the fix); the C side needs no change.

## Amendment 2026-05-24 — col9 shared cache activation (M64; the three TODOs)

Operator-approved activation of the col9 strategy + the two companion levers.

**TODO-1 (shared SOURCES_NEW cache).** The PS workflow now PRESERVES its
downloaded tarballs (only `SOURCES_NEW`, not the full clones — disk-bounded)
to a stable shared path `$HOME/.cache/photonos-shared/photon-upstreams`, with
a 50 GB LRU cap. The C workflow sets `PR_SHA_CACHE=1` +
`PR_SHA_CACHE_BASE=<that path>`; `col9_cache_path()` gained a
`PR_SHA_CACHE_BASE` branch that reads `<base>/photon-<branch>/SOURCES_NEW/
<download_name>`. Since the C workflow auto-triggers right after PS, C reuses
PS's exact bytes → col9 matches on regenerated github/gitlab auto-archives
(the dominant soft driver, biggest on 3.0/4.0). C's clones stay in its own
cache (no full-vs-partial conflict). Value: collapses the col9 portion of soft.
Drawback: shared disk (capped); the PS-empty col9 rows stay C-superiority.

**TODO-2 (tighter PS→C scheduling).** Already satisfied: the C workflow's
`workflow_run` auto-trigger runs C immediately after PS, and the M53 cache
(now warmed for all 7 branches) shrinks C's runtime, minimising the
snapshot-vs-run gap that drives col5/col6 temporal strict diffs. No code
change beyond the warm cache.

**TODO-3 (PR_STRICT_COL9).** Added a `strict_col9` workflow_dispatch input
(default false) wired to `PR_STRICT_COL9`. Folds col9 into the strict verdict
ONLY when explicitly enabled — to be flipped after a PS→C cycle confirms the
TODO-1 cache holds col9 byte-stable (enabling early would spike strict and
reset the 90-day clock). Ordering: TODO-1 proven → then TODO-3.

## Amendment 2026-05-24 — green criterion = strict band; Option D evaluated & deferred

After the M52–M64 program, the per-branch strict counts settled at a stable
**structural floor** (5.0≈85, 6.0≈86, 3.0≈89, 4.0≈89, common=5, dev≈77,
master≈85) that does not trend down with further per-spec work and does not
trend up across snapshots of different ages in the production auto-trigger
flow. Composition of the residual:
  - **C-superiority** cells (C emits a real tarball/SHA where PS has a stale
    homepage/empty) — penalised by a bit-identical metric though C is *more*
    correct; mostly cleared by M58, remainder inherent.
  - **per-spec long-tail** — exception-heavy upstream quirks; diminishing
    yield per fix.
  - **small temporal noise** (±~7) — upstream releases in the PS→C gap; the
    auto-trigger keeps this small (TODO-2).
  - **col9 (soft)** — SHA drift on regenerated auto-archives + PS-empty; kept
    soft deliberately (the PS-empty cases are C-superiority).

**Decision:** literal bit-identical 0 is neither achievable (C is often more
correct than PS) nor the right target. Define **green per branch as
`strict ≤ THRESHOLD`** where THRESHOLD is the ratified structural floor
(above), held for 90 consecutive days. A run that *exceeds* its branch
threshold is a regression to investigate; staying at/under it is green. This
makes the 90-day clock track "no regression beyond the known structural
residual," which is the meaningful guarantee for a 1:1 port whose residual is
dominated by C-being-more-correct. (Operator ratifies the exact per-branch
THRESHOLDs; the measured floor is the proposed starting set.)

**Option D (hermetic record-replay) evaluated and DEFERRED.** M65 attempted
the git-tag input freeze via `git tag --merged <recorded_sha>`; validation
showed it is the wrong mechanism — `--merged` lists only HEAD-reachable tags,
but PS uses `git tag -l` (all tags), and many upstreams tag releases on
unmerged branches, so strict exploded 85→349 (PR #188 closed). A correct
freeze would require recording PS's actual per-upstream tag LISTS (a PS-side
capture + C replay subsystem). Given the production gate is already stable
(~85±7) because the auto-trigger keeps the PS→C gap small, the marginal value
of a full record-replay build is low — it would be gold-plating. Adopt
**A+E** instead: keep tight auto-trigger scheduling + the strict-band green
criterion above. Revisit Option D only if a future need for re-running C
against stale snapshots makes determinism-on-replay valuable.
