# Task 006: Global Deduplication

**Complexity**: Low
**Dependencies**: 005
**Status**: Complete
**Requirement**: REQ-6 (Global Deduplication)
**Feature**: FRD-deduplication

---

## Description

Implement global deduplication of patch directives to ensure no duplicate `Requires:`, `Conflicts:`, or `Provides:` entries appear in any patched spec file, even when multiple source edges converge on the same directive.

### Problem

When multiple Go module edges produce the same dependency (e.g., both `github.com/docker/docker` and `github.com/docker/cli` map to `Requires: docker >= 28.0`), the conflict detector would generate duplicate patches without deduplication.

### Solution

The `add_patch_to_set()` function in `conflict_detector.c` performs global deduplication by checking `(szDirective, szValue)` pair equality before adding a new patch to the linked list. Duplicates are freed immediately, and the function returns `0` (not added) vs. `1` (added), enabling accurate issue counting.

## Implementation Details

- **Source file**: `src/conflict_detector.c`, function `add_patch_to_set()` (lines ~140-158)
- **Dedup key**: `(SpecPatch.szDirective, SpecPatch.szValue)` — exact string match
- **Return value**: `1` if patch was added, `0` if duplicate was suppressed
- **Memory**: Duplicate `SpecPatch` is `free()`d immediately to prevent leaks
- **Issue counting**: `dwIssueCount += add_patch_to_set(pSet, pPatch)` — only counts unique additions

### Deduplication Flow

```
add_patch_to_set(pSet, pPatch):
  for each existing patch p in pSet->pAdditions:
    if p.szDirective == pPatch->szDirective AND p.szValue == pPatch->szValue:
      free(pPatch)
      return 0  // duplicate suppressed
  pPatch->pNext = pSet->pAdditions  // prepend to list
  pSet->dwAdditionCount++
  return 1  // unique addition
```

## Acceptance Criteria

- [ ] No duplicate `(directive, value)` pairs in any `SpecPatchSet`
- [ ] `add_patch_to_set()` returns `0` for duplicates, `1` for new additions
- [ ] `dwIssueCount` accurately reflects unique issues only
- [ ] Memory is freed for suppressed duplicate patches (no leaks)
- [ ] Dedup works across all three patch sources: missing deps (phase 1), virtual provides (phase 2), API conflicts (phase 3)
- [ ] Different values for same directive are NOT deduplicated (e.g., `Requires: docker >= 28.0` and `Requires: containerd >= 1.0` are both kept)

## Testing Requirements

- [ ] Scan a package with overlapping module edges → verify single `Requires:` entry
- [ ] Verify `dwAdditionCount` matches actual linked list length
- [ ] Verify `dwIssueCount` in summary matches unique additions
- [ ] Check manifest JSON `additions[]` array has no duplicates per spec
- [ ] Memory leak check: run under valgrind with duplicate-heavy workload
