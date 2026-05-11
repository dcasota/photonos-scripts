# kernelpatches self-scan summary

Scan date: 2026-05-11
Branch: snyk-self-scan-20260511

## Counts

| Phase     | Total | Warning | Note |
|-----------|-------|---------|------|
| Baseline  | 29    | 10      | 19   |
| Iter 1    | 26    | 7       | 19   |
| Accepted  | 26    | -       | -    |
| Open      | 0     | -       | -    |

## Per-finding outcomes

- reDOS (1) -> HARD-FIX (re.escape of CLI input in fix_pattern, sink in cve_sources.py)
- unquoted_csv_writer (2) -> HARD-FIX (csv.QUOTE_ALL on both writers in cve_matrix.py)
- TarSlip (6) -> HARD-FIX in the two extractor sites; Snyk still flags the data-flow sinks because it doesn't recognize the realpath-startswith guard pattern, but the runtime check now prevents path escape. Recorded as accepted/false-positive-post-fix in the JSON.
- Ssrf (1) -> FALSE-POSITIVE (kernel.org host pinned; only the version path segment is variable)
- PT (19) -> DESIGN-DECISION (kernelpatches is a CLI tool driven by argparse: --kernel-version, --output-dir, --photon-base, etc.)

## Build verification

`python3 -m py_compile` on each modified script succeeds.
