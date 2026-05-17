# PRN incomplete-entry analysis

Per-branch breakdowns of `photonos-urlhealth-<branch>_<ts>.prn` rows that are NOT marked `complete` by the upstream PS scan, with root-cause categorisation and per-host buckets.

Source data: PS-side parity snapshot from run `25991871716` (2026-05-17, master at `0e30de2`).

| Branch / scope | Doc |
|---|---|
| photon-4.0 (default SPECS) | [`photon-4.0.md`](photon-4.0.md) |
| photon-5.0 (default SPECS, ex- SPECS/91) | [`photon-5.0-normal.md`](photon-5.0-normal.md) |
| photon-5.0 SPECS/91 (vendor-pinned subrelease) | [`photon-5.0-SPECS-91.md`](photon-5.0-SPECS-91.md) |
| photon-5.0 SPECS/90 (newly-added flavor; absent in this snapshot's pinned SHA) | [`photon-5.0-SPECS-90.md`](photon-5.0-SPECS-90.md) |

## Common taxonomy

All non-pinned, non-archived rows fall into one of:

| Category | Definition |
|---|---|
| `no_update_url` | UpdateAvailable detected (tags found) but UpdateURL re-substitution yielded empty |
| `warn_packaging_format` | Candidate UpdateURL HEAD-probed non-200; warning "Manufacturer may changed version packaging format" emitted |
| `no_sha` | UpdateURL accepted HEAD but body download / SHA-512 failed |
| `no_update_available` | Tag detection ran but returned 0 entries, or Source0 had no host to query |
| `info_vmware_internal` | Source0 points at `packages.broadcom.com/photon/photon_sources/...` — by-design, not a failure |
| `warn_unmaintained` | Lookup table marks upstream as abandoned — diagnostic only |
| `warn_cannot_correlate_tags` | Tag list returned values, none matched the version pattern |
| `warn_source0_invalid` | Source0 is a bare filename like `%{name}-%{version}.tar.gz` with no URL |
| `warn_duplicate_of` | Spec marked as duplicate of another |
| `vendor_pinned_subrelease_91` | SPECS/91 short-circuit, by design (not a failure) |
| `archived` | ArchivationDate set; out of scope |

## Cross-branch leverage table

Same five Source0Lookup fixes that account for ~75% of incompletes across both 4.0 and 5.0 normal:

| Fix | 4.0 wins | 5.0 normal wins |
|---|---|---|
| GitHub `archive/refs/tags` template | ~30 | ~48 |
| RubyGems update template | 18 | 46 |
| CPAN MetaCPAN release pattern | 9 | 22 |
| X.Org `pub/individual/lib/` template | ~30 | ~30 |
| SourceForge `/projects/<p>/files/<a>` rewrite | ~28 | ~35 |

Source0Lookup is shared across all photon branches; one fix lands a substring of these gains everywhere.
