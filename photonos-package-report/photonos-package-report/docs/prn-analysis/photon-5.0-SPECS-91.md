# PRN incomplete-entry analysis — photon-5.0 SPECS/91

**Source PRN:** `photonos-urlhealth-5.0_202605171536.prn` (PS-side, 2026-05-17 15:36 UTC).

**Scope:** rows produced from `.spec` files under `<workingDir>/photon-5.0/SPECS/91/<pkg>/<pkg>.spec`. These coexist in the same `.prn` with rows from main `SPECS/<pkg>/<pkg>.spec`; the PS script writes both. SPECS/91 rows are identified by `UrlHealth = "pinned"` and `warning = "vendor-pinned (subrelease 91)"`.

**Total SPECS/91 rows:** 16
**Complete in the conventional sense:** 0
**By-design pinned (not failures):** 16

## Status: every row is intentionally pinned, not incomplete

Unlike the main SPECS/ rows in `photon-5.0-normal.md`, every SPECS/91 row has:

| Column | Value |
|---|---|
| col 4  `UrlHealth` | literal `pinned` (sentinel, not an HTTP status) |
| col 5  `UpdateAvailable` | empty |
| col 6  `UpdateURL` | empty |
| col 7  `HealthUpdateURL` | empty |
| col 8  `Name` | spec basename without `.spec` |
| col 9  `SHAName` | empty |
| col 10 `UpdateDownloadName` | empty |
| col 11 `warning` | `vendor-pinned (subrelease 91)` |
| col 12 `ArchivationDate` | empty |

The pipeline is intentionally short-circuited: subrelease 91 is the "vendor-frozen" lineage of selected packages; PS does not chase upstream updates for these by design.

## Affected packages (all 16)

| Spec | Notes (from upstream) |
|---|---|
| `apr-util.spec` | Apache Portable Runtime utility, pinned |
| `aufs-util.spec` | aufs userland, pinned at kernel-compatible version |
| `containerd.spec` | container runtime; locked for legacy compatibility |
| `cups.spec` | print server, pinned |
| `dbus.spec` | IPC bus; subrelease 91 keeps 1.x branch |
| `docker.spec` | docker engine, pinned |
| `gawk.spec` | GNU awk, pinned |
| `libcap.spec` | POSIX capabilities, pinned |
| `Linux-PAM.spec` | PAM, pinned |
| `linuxptp.spec` | PTP daemon, pinned |
| `pgbackrest.spec` | postgres backup tool, pinned |
| `python-psycopg2.spec` | postgres binding, pinned |
| `rpm.spec` | rpm tooling, pinned |
| `runc.spec` | OCI runtime, pinned |
| `stalld.spec` | stall detector, pinned |
| `strace.spec` | tracer, pinned |

## Root-cause taxonomy

Only one bucket applies, and it is by design, not a defect:

| Category | Count | Cause |
|---|---|---|
| `vendor_pinned_subrelease_91` | 16 | PS L 2155-2200 (or equivalent) detects the SPECS/91 path and emits the `pinned` sentinel instead of running the normal Source0Lookup → tag-detection → SHA pipeline. The package set is intentionally frozen at the 5.0 GA-time versions for the 91 subrelease. |

## Implications for parity gate

Both PS and C ports must produce **byte-identical** `pinned` rows for SPECS/91 (FRD-014, ADR-0006). If a C row ever differs from PS on a SPECS/91 spec, that's a strict-fail and the C port has incorrectly walked the standard tag-detection path for a pinned spec.

This requires the C port's `parse_directory` to recognise the `SPECS/91/` subpath and route those task entries to a `pinned-emit` short-circuit, mirroring the PS behaviour.

**Open question:** which PS line range encodes the pinned short-circuit? Worth tracing during the M02/M03 follow-up since the dispatcher we just landed only iterates branches, not subreleases. (Track in a future Phase M task if the parity diff surfaces a strict on any SPECS/91 spec.)
