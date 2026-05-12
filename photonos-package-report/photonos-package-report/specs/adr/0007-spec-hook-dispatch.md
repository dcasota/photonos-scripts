# ADR-0007: Per-spec override blocks → dispatch table of hand-written hooks

**Status**: Accepted
**Date**: 2026-05-12

## Context

The PS script contains ~200 distinct `if ($currentTask.spec -ilike 'X.spec') { ... }` (and `elseif`) blocks scattered throughout `CheckURLHealth` and adjacent functions. Each block encodes package-specific knowledge (e.g. `mozjs60.spec` requires `esr` suffix in the URL; `psmisc.spec` resets `$Source0`; `amdvlk.spec` has a non-standard version transform).

These cannot be machine-translated because the inner statements perform arbitrary side effects on `$Source0`, `$NameLatest`, `$UpdateURL`, etc.

## Decision

A two-part mechanism:

1. **`tools/extract-spec-hooks.sh`** — bash+awk extractor that scans `photonos-package-report.ps1`, identifies every `-ilike 'X.spec'` block (and its surrounding context — `elseif` chains, `else` arms), and emits two things:
   - A C dispatch table (`pr_spec_dispatch.h`) keyed on lower-cased spec basename, mapping to `hook_<name>(pr_task_t *, pr_state_t *)`.
   - A check that each entry in the dispatch table corresponds to a hand-written `hook_<name>` function under `src/check_urlhealth/hooks/`. Build fails if a hook is missing.
2. **`src/check_urlhealth/hooks/<name>.c`** — one C file per spec hook. The PS block source is included verbatim as a comment block at the top of the file; the C translation follows. Reviewers see PS-source and C side-by-side.

## Rationale

- Mechanical translation of arbitrary PS bodies is unsafe (different semantics around `$_`, `$Matches`, pipeline implicit returns).
- Manual one-time translation is acceptable because the count (~200) is bounded and the bodies are usually small (3-20 lines).
- The build-time drift check catches new PS-side hooks at the next CMake re-config, surfacing them as immediate build failures rather than silent skips.

## Consequences

- ~200 small C files in `src/check_urlhealth/hooks/`. Each file has a one-line dispatch entry and a focused function.
- A directory CLAUDE.md notes the convention: "the PS source is the spec; do not modify the C without first updating the PS comment block".
- Phase 3 task 035 produces the extractor; phase 4 task 040 fills in the ~200 hooks (with parity tests per-hook).

## Considered alternatives

- **Embed PS bodies as Lua/Tcl/scripting strings interpreted at C runtime**: pulls in a scripting engine; fights ADR-0001's "minimal abstraction" property.
- **Generate hook bodies via awk/sed mechanical translation**: too fragile for arbitrary PS pipelines, even with strict input shape.
