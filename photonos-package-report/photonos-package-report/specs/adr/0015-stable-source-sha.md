# ADR-0015 — Stable-source SHA for github auto-archives

**Status**: Draft

**Date**: 2026-05-18

**Deciders**: TBD (user gate)

## Context

`SHAValue` col 9 of `.prn` currently carries the SHA computed against
whatever URL the substitution pipeline emits in col 6 (`UpdateURL`).
For ~75 spec rows per branch (the `cols[9]`-only residual bucket
after M21-wired) PS and C disagree on col 9 only, while every other
column matches.

The disagreement is **not** a C-port bug. It is fundamental upstream
volatility:

1. **GitHub auto-archive instability.** When `Source0` looks like
   `https://github.com/<org>/<proj>/archive/refs/tags/<tag>.tar.gz`,
   GitHub regenerates the tarball on demand. Newer git versions on
   the GitHub backend re-pack the tree with different blob ordering;
   the SHA shifts even though the underlying source code is the
   identical commit. PS computed its SHA at one moment; the C run
   computed it later → bytes differ.

2. **No fix possible on the consumer side.** Both PS and C are
   following the link the spec gave them. Neither side is "wrong".
   The data source itself moves.

Two orthogonal directions could mitigate this:

- ADR-0014 (multi-SHA) — record SHAs for *multiple* algorithms so
  consumers have redundant verification surface. Useful but
  doesn't address the auto-archive instability — all three hashes
  shift in lockstep when GitHub re-packs.
- ADR-0015 (this doc) — when a stable alternative source URL exists,
  use it for col-9 computation while keeping col-6 (`UpdateURL`)
  as the user-facing canonical URL.

## What "stable" means

Upstream projects on GitHub typically expose **two** types of
download URL per tag:

- **Auto-archive**: `https://github.com/<org>/<proj>/archive/refs/tags/<tag>.tar.gz`
  — regenerated on demand, SHA unstable.
- **Release asset**: `https://github.com/<org>/<proj>/releases/download/<tag>/<assetname>`
  — uploaded by the maintainer at release time, SHA stable forever
  (or until the asset is deleted, which is rare and visible).

Projects that publish release assets are signalling "this is the
canonical artefact"; those that only publish auto-archives implicitly
accept SHA drift. For Photon's `.prn`, we should prefer the stable
asset when available.

## Options

### A. col-9-only override: probe release assets, fall back to auto-archive

**Behaviour**: when col 6 contains `github.com/.../archive/refs/tags/`,
issue a HEAD against the corresponding release-asset URL pattern
(typically `releases/download/<tag>/<tag>.tar.gz` or
`releases/download/<tag>/<proj>-<tag>.tar.gz`). On 200, switch col 9's
SHA computation to that URL while keeping col 6 unchanged. On non-200,
keep computing SHA against the auto-archive URL (current behaviour).

Pros: minimum schema change; consumer-side `.prn` shape unchanged.
Cons: extra HEAD per github-auto-archive spec (~75/branch); not all
upstreams follow a single asset-naming convention so the URL guesser
will miss some legitimate assets and fall back unnecessarily.

### B. Schema change: add col 13 = `StableSourceURL`, col 14 = `StableSHA`

**Behaviour**: same probe as A, but record the stable URL separately
so consumers can choose which to trust.

Pros: explicit; consumer-visible distinction between "what URL the
spec downloads from" (col 6) and "what URL the SHA matches" (col 13).
Cons: schema change; collides with ADR-0014's col 13/14 if both
proceed. PS + C + parity-diff + journal need coordinated rollout.

### C. Sidecar release-asset cache

**Behaviour**: maintain `tools/release-asset-cache.tsv` keyed on
`<org>/<proj>/<tag>` → `<asset-url>`. Populated by a separate
background job that walks the spec set monthly. Lookup at run time
is offline.

Pros: zero per-run HEAD overhead; offline-friendly.
Cons: cache staleness; new artefact to maintain; another generator
(violates "no python in pipeline" constraint unless written in
shell/awk).

### D. Accept drift; document the bucket as expected

**Behaviour**: classify the col-9-only github-auto-archive bucket as
"volatile, like cols 4/7" and treat as soft-diff in parity-gate.

Pros: zero engineering work.
Cons: weakens the soft/strict line. Cols 4/7 are HTTP status (truly
volatile per probe), col 9 is a hash that changes per
*regeneration* — different time-scale. Soft-diffing it might mask
real bugs where the SHA computation logic itself drifts.

## Decision

**Pending user input.** Agent recommendation: **Option A (col-9
override with auto-archive fallback)**, gated by a per-host
allowlist (initially `github.com` only).

Reasons:

- Surgical. Minimum schema change. Consumer `.prn` shape unaffected.
- Probe overhead is bounded (~75 specs/branch * 1 HEAD each * 7
  branches ≈ 525 probes per workflow run, parallelisable; current
  workflow time is ~2h so probe cost is amortised).
- Falls back cleanly to current behaviour for non-github
  Source0Lookups and for github specs that don't publish release
  assets.
- Doesn't preclude Option B later — if ADR-0014 multi-SHA is also
  accepted, the multi-SHA + stable-source compose naturally (col 9
  remains the single canonical SHA against the stable URL; cols
  13/14 add algorithm redundancy).

Compose-with-ADR-0014: if both are accepted, the stable URL takes
precedence for whichever algorithm column the spec named. The
multi-SHA columns (13/14) carry the redundant hashes against the
SAME stable URL. Consumers get one stable hash plus algorithm
redundancy — both axes addressed.

## Consequences

- New helper: `pr_resolve_stable_source_url(spec, tag, current_url)`
  in `src/sha.c` or a new `src/stable_source.c`. Returns either a
  stable asset URL (string) or NULL (fall back).
- Per-host probe table: starts with `github.com` (release-asset
  guess), can grow to `gitlab.com`, `bitbucket.org`, etc.
- Asset-URL guessing heuristic (github case):
  1. `releases/download/<tag>/<proj>-<tag>.tar.gz`
  2. `releases/download/<tag>/<tag>.tar.gz`
  3. `releases/download/<tag>/<proj>-<tag>.tar.bz2`
  4. (more variants observed across the photon spec set)
  HEAD each in order; first 200 wins.
- FRD-007 (GitHub tag detection) gets a new §3 paragraph documenting
  the stable-source override behaviour.
- ADR-0006 (bit-identical priority) unaffected — col 9 schema stays
  the same; only the URL the SHA is computed against changes.
- Parity gate: PS must also adopt the override for parity to hold.
  This means a coordinated PS-side patch in the same PR (CLAUDE.md
  invariant 2 — PS is upstream-of-C source-of-truth, so PS-side
  patches are valid and expected).

## Implementation order (when accepted)

1. PS-side patch: add `Resolve-StableSourceURL` helper in
   `photonos-package-report.ps1` near the SHA computation site
   (around L 4912-4921). Insert HEAD probe + fallback.
2. C-side: `pr_resolve_stable_source_url` mirror.
3. Both sides call the resolver before SHA computation in the
   `rc==1` branch of CheckURLHealth and in the scraper path.
4. Update FRD-007 with §3 stable-source paragraph.
5. Ship as one PR. Workflow re-dispatch confirms the col-9 bucket
   shrinks.
6. Per-host expansion (gitlab, bitbucket, sourceforge) as follow-up
   PRs.

## Open questions

- HEAD probe failure modes (rate-limit, redirect loop, 403 on
  CDN): need timeout + backoff parity between PS and C.
- Asset-name variability: github has no canonical convention; some
  projects upload `v1.2.3.tar.gz`, others `proj-1.2.3.tar.gz`, others
  `proj-1.2.3-source.tar.gz`. The guesser will need a per-spec
  override path (spec-hook style) for the outliers.
- Caching: should the resolved URL be cached across runs to avoid
  re-probing? Trade-off between freshness (asset deleted/replaced)
  and probe cost.

## Related

- ADR-0006 (bit-identical priority — col 9 strict)
- ADR-0009 (CI parity gate; col-9 currently strict, target stays
  strict under this ADR)
- ADR-0014 (multi-SHA — composes naturally with this ADR)
- FRD-007 (GitHub tag detection)
- The col-9-only bucket (~75 specs/branch in the post-M21-wired
  journal) is the direct target.
