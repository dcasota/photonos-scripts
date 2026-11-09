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

## Iter 2 (2026-11-09)

| Phase    | Total | Medium | Low |
|----------|-------|--------|-----|
| Before   | 26    | 7      | 19  |
| Iter 2   | 9     | 0      | 9   |
| Accepted | 9     | -      | -   |
| Open     | 0     | -      | -   |

- TarSlip (6) -> HARD-FIX. The iter1 realpath-before-extractall guard was bypassable:
  a symlink member pointing outside the destination, followed by a file written
  through it, passed the check and wrote outside (reproduced). New
  `scripts/safe_io.safe_extract_tar` pre-checks names, link targets and special
  files, then extracts with `filter="data"`. Snyk no longer flags it.
- Ssrf (1) -> HARD-FIX. Kernel series normalised to the KERNEL_MAPPINGS constant;
  the kernel.org-sourced stable version must be digits and dots before it goes in the URL.
- PT (19) -> 10 HARD-FIX, 9 DESIGN-DECISION. Spec names, versions from spec files
  and kernel.org, gap-report names and the repo dir that may be `rmtree`'d are now
  validated and confined. The 9 residual findings are taint from the operator's
  own `--output` directory / CVE list file (see accepted/kernelpatches.json).
  Snyk CLI 1.1304.2 ignores inline `deepcode ignore` comments, so they are not used.

Verification: `pytest` 186 passed, 1 pre-existing failure
(`test_config.py::test_default_config`, `cve_patch_max` 9999 vs 499, unrelated);
new `tests/test_safe_io.py` covers both filter modes; real-tarball extraction of
linux-6.12.113 matched `tar -t` (92471 entries, 62 symlinks).
