# ADR-0007 — Version-neutral base first, then retire the Python generator

Status: accepted, implemented
Date: 2026-09-27
Feature: [FRD-001](../features/kernel-wrapper.md)

## Context

Six of the Python generator's replacements existed only because the base hard-coded `7.2.7` in
code that does not need a version: the SpecData compat-wrap marker, the `c++.real727` restore, and
comments. `tools/make-73rc4.py` was kept as a reference for the port.

## Decision

1. Make the base version-neutral there first (user decision, 2026-09-27): the SpecData marker is
   matched by `# --- [0-9][0-9A-Za-z.-]* SpecData compatibility ---`, the restore loops over
   `c++.real[0-9]*` / `g++.real[0-9]*`, comments say "kernel-specific". The stale header line
   `wrapper v4 — always rewires common-branch-path before make` becomes `wrapper v13`, matching the
   banner (the new self-consistency check requires it). Proof: fixture runs of old and new code
   give identical results for every input the old code handled; the new code also heals a wrap
   left by any other release. No rebuild was started, because the changed code runs only on leftovers
   and fixtures exercise it directly.
2. Delete `tools/make-73rc4.py`. The golden test (`cli::tests::golden_*`) now pins the same output
   from the committed base and profile, and `wrapper check` is the drift gate. The script remains in
   git history (its last content is at the parent of the commit that removes it).

## Consequences

`staging/runPh7-3-RC4.sh` is a derived file: edit the base or the profile, then
`sharukhan wrapper derive --profile 7.3-rc4 --repo <photon clone>`.
