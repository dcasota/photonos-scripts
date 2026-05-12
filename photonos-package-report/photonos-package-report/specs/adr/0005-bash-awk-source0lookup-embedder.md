# ADR-0005: Embed Source0LookupData via bash+awk at build time

**Status**: Accepted
**Date**: 2026-05-12

## Context

PS L 509-1369 holds an inline 850-row CSV (`$Source0LookupData=@'...'@`) consumed by `ConvertFrom-Csv`. This is the master source-of-truth for per-package upstream URL overrides — changes to it in the PS script must propagate to the C port without manual copy-paste.

PRD constraint NFR-3: **no Python in the build pipeline**.

## Decision

A POSIX shell + awk pair (`tools/extract-source0-lookup.sh` and `tools/escape-c-string.sh`) extracts the CSV at CMake configure/build time and emits a generated `source0_lookup_data.h` containing a single `static const char *const pr_source0_lookup_csv = "..."` literal. The C code parses this in-memory string at startup.

## Rationale

- The embedded CSV is the data, not just a sidecar — the binary must work in offline / sandboxed CI environments without re-downloading the PS source.
- bash+awk is universally available on Photon and on any developer machine; no new tooling.
- `xxd -i` was considered but produces a `unsigned char[]` not null-terminated and adds a non-standard tool dep.
- The generator depends on the PS source's mtime — CMake re-runs it automatically if the script changes.

## Consequences

- The generator's correctness is itself a unit test: `tools/parity-tests/source0-csv-roundtrip.sh` compares a PS `$Source0LookupData | ConvertTo-Csv` dump against the C-parsed dump byte-by-byte.
- If a new PS commit adds rows, the next C build picks them up automatically.
- Spec hooks for individual packages (`if ($currentTask.spec -ilike 'X.spec')` blocks scattered throughout) are NOT in the CSV and require ADR-0007.

## Considered alternatives

- **Hand-translate the CSV into a C struct array**: 850 rows of maintenance burden every time PS changes it. Rejected.
- **External `data/source0_lookup.csv` file shipped alongside the binary**: violates the user's requirement that the data live "inside the C tool".
- **Python extractor**: violates NFR-3.
