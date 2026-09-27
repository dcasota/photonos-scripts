# ADR-0005 — Wrapper version numbers come from the profile; a base bump forces review

Status: accepted, implemented
Date: 2026-09-27
Feature: [FRD-001](../features/kernel-wrapper.md)

## Context

Two numbers: the base's own `wrapper vN` (v13) and the derived wrapper's (v8). The Python generator
carried both in anchor text, so every base bump broke it - intentionally, to force a review, but
with an error that did not say so.

## Decision

- The derived wrapper's version is `wrapper_version` in the profile. It is not computed: a version
  number records a reviewed change, and only a person knows when one happened.
- The profile records `base.wrapper_version`, the base version it was reviewed against. `derive`
  reads the base's version from its banner (and requires the header to agree) and refuses a mismatch
  with the instruction: review what changed since vN, update the profile if needed, set
  `base.wrapper_version`, raise `wrapper_version`.
- `profile-new` sets `wrapper_version` 1 and `base.wrapper_version` to the base as it is now.

## Consequences

A base bump fails `wrapper check` for every profile until each is reviewed. That is the intended
cost: a fix in the base flows into every derived wrapper, and someone confirms it should.
