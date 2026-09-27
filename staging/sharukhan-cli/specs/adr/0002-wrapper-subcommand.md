# ADR-0002 — `sharukhan wrapper`: its own command group, scoped to kernel wrappers

Status: accepted, implemented
Date: 2026-09-27
Feature: [FRD-001](../features/kernel-wrapper.md)

## Context

The research note asked whether wrapper derivation belongs under `build` or is a command of its own,
and whether it should also derive `runPh7-2-7.sh` from `runPh5_normal.sh`.

`build` runs the build cascade and takes the permutation-matrix option set (`--release`, `--img`,
`--canister`, ...). Deriving a wrapper builds nothing: it reads a base script and a profile, may talk
to kernel.org and git, and writes one file. Its options (`--profile`, `--repo`, `--trust`,
`--tarball`, `--check`) share nothing with `build`'s.

## Decision

A command group `sharukhan wrapper <derive|check|kernel|verify|profile-new>`, dispatched in `main`
before the matrix option parser, with its own parser and `--help`. Unknown commands and options exit
64, failures exit 1.

- `derive` / `check`: the derivation and the CI drift gate.
- `kernel`: what a release selector resolves to on kernel.org, with the identity it derives.
- `verify`: source verification, independently of derivation, so a pin can be established or
  re-established without writing anything.
- `profile-new`: the only way a new release enters, so the first profile for it already carries a
  verified pin.

Scope is kernel wrappers derived from a slot-marked base. `runPh7-2-7.sh` from `runPh5_normal.sh` is
out of scope: that relationship is a generate-and-rewrite at run time inside the wrapper.

## Alternatives

- `build --derive-wrapper`: mixes two option sets; `build`'s safety gates (`--allow-build`) mean
  nothing here.
- One command with flags for each step: `verify` needs no base, `kernel` needs no profile; one
  command would carry options that are meaningless in most invocations.

## Consequences

The group has room for further wrapper kinds, but each would need its own base contract (ADR-0003).
