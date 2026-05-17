# FRD-012-gitphoton-clone-fetch: GitPhoton clone/fetch

**Feature ID**: FRD-012-gitphoton-clone-fetch
**Related PRD Requirements**: REQ-12
**Related ADRs**: ADR-0001
**PS source range**: photonos-package-report.ps1 L 451-506
**Status**: Accepted
**Last updated**: 2026-05-12

---

## 1. Overview

Clone or fetch reports/photon-<release>.

This FRD specifies the 1:1 C port of the corresponding section of the PowerShell script. It captures the bit-identical assertions, dependencies, and acceptance tests required for the C implementation to ship.

## 2. Functional requirements

(To be expanded by the dev agent at the start of the phase that implements this FRD; the implementation must be a literal, line-ordered translation of the PS source range above. No reordering, no merging of cases.)

### 2.1 `-UpstreamsExclusionList` clone-skip (Phase M task M01)

Companion to PS PR #84 (PS L 2369-2392, 3659-3679, 4014-4034). The C
port honours the comma-separated `-UpstreamsExclusionList` against the
`repo_name` extracted by `pr_extract_repo_name()` from the
`gitSource` `.git` URL:

* Match is **case-insensitive substring**. Tokens are trimmed of ASCII
  whitespace. Empty tokens are skipped.
* When matched, `check_urlhealth()` MUST NOT call `pr_clone_ensure()`
  for that spec; the downstream `pr_clone_list_tags()` block is also
  bypassed (no `.git` ⇒ nothing to enumerate).
* Default empty list ⇒ zero behavioural diff vs. pre-feature runs.

The tarball half of the PS exclusion (key 2: leaf of
`$UpdateDownloadFile`) has no C counterpart today because the C port
does not download tarballs to `SOURCES_NEW` — only HEAD-probes URLs.
A future feature that adds a real tarball downloader MUST add the
matching guard at that add-site.

## 3. Bit-identical assertions

- All non-volatile bytes of the implementation's outputs must match PS output exactly.
- The HTTP-status columns (col 4, col 7 of `.prn`) are soft-diffed when this feature touches network calls; everything else is strict.
- Mutations on `$Source0` (and equivalents) execute in the same line order as PS.

## 4. Acceptance tests

- Unit: PS-captured trace dumps for the corresponding function are replayed; C output diffs against PS dump = 0.
- Integration: 10 representative SPECs from photon-5.0/SPECS produce identical `.prn` rows under PS and C.
- (For phases that touch network) Side-by-side fixture replay with cached HTTP responses.
- **§2.1 exclusion-list acceptance (Phase M task M01):**
  - Truth-table unit test for `pr_should_skip_clone()` covers
    empty/NULL list, multi-token, whitespace-trim, case-insensitive
    substring, longer-filter-than-name, repeated-comma edge cases
    (see `tests/unit/test_phase6d.c::test_should_skip_clone`).
  - Parity diff under `-UpstreamsExclusionList "firmware,chromium"`
    between PS (PR #84) and C (this FRD §2.1) is strict-green on
    `linux-firmware.spec` and `chromium.spec` rows.

## 5. Dependencies

- Upstream PS source range L 451-506.
- The ADRs listed above.
- Predecessor FRDs (declared in `specs/tasks/README.md`).

## 6. Open questions

None at this Status. Re-open if a task surfaces an ambiguity in the PS source.
