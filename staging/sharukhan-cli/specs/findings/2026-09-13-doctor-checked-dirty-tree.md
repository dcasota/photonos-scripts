# Finding: doctor checked the variant patches against the build tree

**Date**: 2026-09-13
**Status**: Resolved by amendment (`cede88d`)
**Affects**: `specs/prd.md` REQ-14 / AC-12 as `doctor` implemented them

## What the harness assumed

`git apply --check`, run in the photon tree, answers the question a build
depends on: does this variant patch apply?

## What measurement showed

It answers a different question: does it apply to *whatever the tree holds
now*. A build leaves `SPECS` patched. After the 2026-09-13 equivalent builds,
40 paths carried the variant patch **and** the embedded canister patch on top
of it, and `doctor` reported:

    [FAIL] poi-2.8 applies        no - regenerate with `sharukhan variant-patches`
    [FAIL] poi-latest applies     no - regenerate with `sharukhan variant-patches`

Both were correct. Read into a temporary index at `origin/5.0`, each applied
cleanly (35 files). The tree was not even "the variant, applied": the patches
did not reverse-apply either, because the embedded layer sits on top.

## Consequence of leaving it uncorrected

After every build the operator is told to regenerate patches that are fine,
which makes a genuinely stale patch indistinguishable from the false alarm -
exactly the case the check exists to catch. A build is unaffected: it resets
`SPECS` to the release before applying.

## Resolution

`build::applies_to_pristine` reads `origin/<release>` into a temporary index
and runs `git apply --cached --check` against it, so the working tree is never
read and no second worktree is checked out. It reports a measured reason: the
file count, git's first error line, or an unreadable base ref.

Its tests build a throwaway repository whose tree is dirty. One asserts that the
old in-tree check fails there while the new check passes; a patch for content
that never existed is the negative control. Running them in parallel exposed a
second defect: the temporary index was keyed by pid and patch name, so threads
of one process shared it (`a.txt: does not exist in index`, one run in three).
It is now unique per call.

Recorded in `memory.db` as finding 64.
