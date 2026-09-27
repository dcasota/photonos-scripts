# ADR-0004 — Profiles live in sharukhan-cli and are cross-checked against the branch

Status: accepted, implemented
Date: 2026-09-27
Feature: [FRD-001](../features/kernel-wrapper.md)

## Context

What cannot be computed from a release string - which rebased patches to enable, why a kernel
parameter goes, the installer patches, pre-build extras, the pinned digest - must live somewhere.
Candidates: `sharukhan-cli/profiles/`, beside the wrappers in `staging/`, or on the kernel branch
(`SPECS/linux/EXPERIMENTAL-<release>.md` already records tarball, sha512 and tag commit).

## Decision

`sharukhan-cli/profiles/kernel/<release>.json`, one per release, strict JSON (schema 1,
`deny_unknown_fields`), next to `kernel-org-signers.json`. The file name must equal the profile's
release.

The branch manifest is not the source but a second witness: `derive` reads it from
`origin/experimental/linux-<release>` in a photon clone (`--repo` or `SHARUKHAN_PHOTON_REPO`) and
requires agreement on tarball URL, sha512, tag commit, Kernel and RPM Version/Release, and that each
patch file the profile names exists on the branch exactly once. Skipping the check needs
`--no-branch` and is printed as "NOT verified".

## Why

- The profile is reviewed with the tool that consumes it, and the golden test pins both.
- The branch is in another repository that the tool must not write to, and its manifest is prose
  for people; making it machine input would couple two repositories' formats in one direction.
- Two witnesses that must agree catch the drift either one alone would not.

## Consequences

A new release needs a profile here and a manifest on its branch; `profile-new` produces the first
and the branch check proves the second.
