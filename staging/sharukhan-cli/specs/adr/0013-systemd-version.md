# ADR-0013 — A systemd release as a build parameter

Status: accepted, implemented (2026-11-05)
Feature: [FRD-003](../features/systemd-version.md)

## Context

The matrix tests every permutation with the systemd Photon OS 5.0 packages (257.13 at subrelease
92). Testing another systemd release, e.g. 262.2, needs a port of `SPECS/systemd`: between 257.13 and
262.2 four of Photon's five patches stop applying and four meson options are removed upstream (SysV
support, libidn, libiptc). The open PRs #22, #79 and #87 change `SPECS/systemd` for 257.13.

## Decisions

1. **The port is a reviewed branch, not a derivation.** sharukhan verifies the release, starts
   `experimental/systemd-<release>` with the version bump and the pinned source, and reports every
   patch and meson option that needs work; a person (or an agent) finishes the port; `sharukhan
   systemd check` refuses the build until it passes. A derivation that dropped a Photon patch that no
   longer applied, or a meson option the release removed, would build a systemd nobody reviewed and
   report it as tested. This is the kernel's pattern (`experimental/linux-<release>`).
2. **PRs that change `SPECS/systemd` are left out** of a `--systemd` build's variant patches, and
   named in its log; every other PR is applied. They are written for 257.13; the port owns the spec.
   A PR that changes only `SPECS/90/systemd` (subrelease 90) is applied: the mainline does not build it.
3. **The mainline only.** The port branch must be a mainline tree (subrelease = mainline, currently
   92); a branch that pins a subrelease is refused.
4. **Trust is pinned, as for kernels.** A profile pins the GitHub tarball's sha512 and the tagged
   commit; a release verifies only when its tag carries exactly one good signature by a reviewed
   signer (`profiles/systemd/systemd-signers.json`, keys from keys.openpgp.org by full fingerprint)
   and the tarball is `git archive` of the tagged commit. The first reviewed signer is Luca Boccassi,
   who tags systemd's stable releases; his key from his GitHub account and from keys.openpgp.org is
   the same key. A release signed by anyone else is refused with the fingerprint until a person
   adds the signer.
5. **No release candidates.** Photon's RPM version comparison has no `~`, so an rc could not sort
   below its final.
6. **Not with `--kernel`.** Each builds in a release tree of its own; combining them is a later
   decision.
7. **The kernel's verification code is reused**, not copied: its trust file, keyring, signature
   judgement and tar walk take the project's hosts and key file name as parameters.

## Consequences

A systemd release costs a port per release, as a kernel does; the report of `profile-new` is its work
list. The ISO of a `--systemd` build is evidence for the port branch plus every PR that does not touch
systemd, and says so in its log and input record. `guest.systemd_version` makes a medium that carries
the wrong systemd a failed row, not a passed one.
