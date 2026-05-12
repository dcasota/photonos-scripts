# ADR-0003: Regex engine — PCRE2

**Status**: Accepted
**Date**: 2026-05-12

## Context

PowerShell uses .NET regex (`System.Text.RegularExpressions.Regex`). The script uses 77 `\d` and 6 `\s` meta-characters but no .NET-only features (no `\A`/`\Z`, no balancing groups, no named backreferences in non-trivial usage). However, the substitution syntax `$N`/`$&` is widely used in `-ireplace` replacements, and these MUST be preserved.

## Decision

**PCRE2** (`libpcre2-8`) via Photon RPM.

## Rationale

- PCRE2 supports `$N`/`$&` substitution syntax identically to .NET (via `PCRE2_SUBSTITUTE_*` flags).
- `PCRE2_CASELESS` matches PS `-ireplace`/`-imatch`.
- `pcre2_substitute` covers replacement with regex back-references in one call — equivalent to `-ireplace`.
- Photon already ships `pcre2-devel`; the package-report-database-tool sibling already links it (precedent).

## Consequences

- Each thread compiles its own `pcre2_code *` instances (PCRE2 match data is not thread-safe across `_match` calls with shared state; compile is, but match state isn't).
- A regex cache (`pr_regex_cache_t` per-thread) memoizes compiled patterns since the same patterns are reused across packages.
- Edge case: PowerShell's regex treats unescaped `{` as literal when not forming a valid quantifier; PCRE2 default does the same with `PCRE2_ALLOW_UNESCAPED_BRACES = 0` (default). No flag flip needed.

## Considered alternatives

- **POSIX regex.h**: lacks `$N` backref in substitution; would require manual post-processing.
- **Oniguruma**: stronger Unicode but irrelevant for the ASCII-only SPEC content; adds a dep.
