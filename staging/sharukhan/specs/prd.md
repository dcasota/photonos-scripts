# 📝 Product Requirements Document (PRD)

## 1. Purpose

`sharukhan` is a single standalone Rust CLI that plans, builds, executes and verifies every permutation of a Photon OS ISO install matrix on VMware Workstation, and records what it found in a queryable memory database.

It replaces two shell toolkits — `staging/vm-lab` (VM provisioning) and `staging/mission-control` (permutation harness) — which between them work but cannot be trusted as a test oracle. Three defects motivate the rewrite, all observed rather than hypothesised:

- **Inputs resolve implicitly.** `runPh5_normal.sh` resolves its patch relative to its own location. The two copies on the host had drifted 78 lines and 8-vs-27 files apart, and the build silently used whichever sat beside the invoked script. The failure surfaced as `patch does not apply` against a spec — indistinguishable from a rebase problem, and it cost two builds and two wrong diagnoses.
- **Checks cannot fail.** `vm-lab/scripts/40-check-staging.sh` never exits non-zero. Correct for an inspection tool; useless as a gate.
- **Verdicts can be silently vacuous.** `/usr/bin/grep` is toybox in a non-interactive shell and has no `-a`, returning *zero matches* on a NUL-bearing serial log rather than erroring; interactively the same name resolves to `ugrep`, which behaves differently again. A pipeline that "passes" may have measured nothing.

The audience is one maintainer testing pull requests against a hypervisor on their own workstation, not a fleet.

## 2. Scope

**In Scope**

- Prerequisite verification with measured, actionable results
- ISO build orchestration and caching, keyed by the build-time axes
- Per-permutation VM provisioning, install (unattended and operator-assisted), verification and teardown
- An assertion oracle that attributes each failure to the pull request it disproves
- Background job execution with status inspection and cancellation
- A memory database as the system of record, with `MEMORY.md` generated from it
- A final report table of what ran and what passed
- Selective execution of named permutations

**Out of Scope**

- Hypervisors other than VMware Workstation on Windows driven from WSL
- Building Photon packages itself — `sharukhan` invokes the existing build scripts, it does not replace them
- Any SPAGAT-Librarian appliance concern (`operator-config.vmdk`, `iso-phase6`, `SPAGAT_*`/`IPHASE6_*`, the credential medium). Explicitly excluded by the maintainer
- Remote/multi-host execution, scheduling daemons, web UI, telemetry
- Replacing `ISO-PERMUTATION-MATRIX.md` as the analytical document; `sharukhan` executes it

## 3. Goals & Success Criteria

| Goal | Measured by |
|---|---|
| A failing permutation names the PR it disproves, not "something broke" | every assertion carries a PR identifier; the report's `PRs implicated` column is populated from failures alone |
| No check can pass vacuously | every presence/count assertion has a negative control that must fail |
| A result is attributable months later | each run records tree HEAD, patch identity and hash, ISO hash, and the installer NEVR that actually shipped |
| Prerequisites distinguish causes | "absent", "present but not executable by this user", and "present but version-skewed" are three distinct outcomes, never one boolean |
| The whole matrix is reachable without merging anything | installer variants are assembled by cherry-picking PR branches into a throwaway tree |
| A long run can be supervised | jobs run in the background, are inspectable while running, and are stoppable |

## 4. High-Level Requirements

- **[REQ-1]** Verify every host prerequisite before any destructive action, reporting a measured value and a distinct outcome per failure cause.
- **[REQ-2]** Resolve a build-axis tuple to an ISO, building only on cache miss, and record what actually shipped on the produced media.
- **[REQ-3]** Provision a VM per permutation with a deterministic, collision-free identity (name, MAC, BIOS UUID, address), from a pinned template in which no placeholder may survive substitution.
- **[REQ-4]** Drive an unattended install by injecting a per-permutation kickstart, without remastering the ISO.
- **[REQ-5]** Drive an operator-assisted install for permutations that cannot be automated, presenting generated instructions that cannot drift from the matrix.
- **[REQ-6]** Detect install completion and install failure from observable evidence, never from elapsed time.
- **[REQ-7]** Assert media, install-phase, guest and harvested-log facts, attributing each assertion to the pull request it proves.
- **[REQ-8]** Harvest guest evidence — dmesg, journal, failed units, package inventory, `/var/log` — into per-permutation storage.
- **[REQ-9]** Tear down by stashing the complete boot chain, never deleting, targeting exactly one named VM.
- **[REQ-10]** Execute the whole matrix or a named subset, sequentially, with a plan mode that builds nothing.
- **[REQ-11]** Run work as a background job that can be listed, inspected and stopped.
- **[REQ-12]** Persist every run, permutation, check, artifact and finding in a memory database, and generate `MEMORY.md` as a view over it rather than a parallel copy.
- **[REQ-13]** Produce a final report table of permutations attempted, their recorded pre-change verdict, their result, and the PRs implicated.
- **[REQ-14]** Assemble installer variants by cherry-picking named PR branches onto a pristine base in a throwaway clone, proving each variant applies before use, and merging nothing.
- **[REQ-15]** Apply defence in depth: no credential in a process argument, in the database, or in a log; external commands invoked as argument vectors; SQL parameterised; destructive operations path-validated and single-target.

## 5. User Stories

```gherkin
As a maintainer, I want to know whether my host can run the matrix at all,
so that I do not discover a missing tool three hours into a build.

As a maintainer, I want a failing permutation to name the pull request it
disproves, so that I can act on the result instead of investigating it.

As a maintainer, I want to test a pull request before merging it,
so that I never merge code that has not been exercised.

As a maintainer, I want to run only the permutations I care about,
so that a targeted question does not cost a full matrix run.

As a maintainer, I want a long run to proceed in the background and remain
inspectable and stoppable, so that I am not held hostage by a terminal.

As a maintainer, I want the interactive permutations to tell me exactly what
to type, so that a hand-driven install still exercises the intended axis.

As a maintainer, I want every finding recorded in one queryable place,
so that a result from last month is still attributable to a tree and a patch.

As a security reviewer, I want credentials never to reach an argument list,
a log or the database, so that a test harness is not a disclosure path.
```

## 6. Acceptance Criteria

| ID | Criterion | Verifier |
|---|---|---|
| **AC-1** | `sharukhan doctor` reports, per prerequisite, a measured value and one of `ok` / `missing` / `not-executable` / `version-skew`, and exits non-zero if any is fatal | Task 002 |
| **AC-2** | Every presence or count assertion has a paired negative control; a run in which a control passes is reported as inconclusive, not as a pass | Task 007 |
| **AC-3** | Assertions carry a PR identifier, and the report's implicated-PR column derives solely from failing assertions | Task 009 |
| **AC-4** | A permutation's VM identity is derived from its ordinal, is unique across the matrix, and never falls inside the hypervisor's DHCP range | Task 004 |
| **AC-5** | VMX generation fails if any placeholder survives substitution | Task 004 |
| **AC-6** | An unattended install is driven with no modification to the ISO | Task 005 |
| **AC-7** | Install completion is decided by the boot-source transition, and install failure by the resolution-error signal; elapsed time is never a verdict | Task 006 |
| **AC-8** | Teardown stashes the whole chain, deletes nothing by default, and touches only the named VM | Task 010 |
| **AC-9** | `sharukhan run --plan` builds nothing and lists the deduplicated ISO set | Task 011 |
| **AC-10** | A background job can be listed, inspected while running, and stopped, leaving no orphaned mounts or VMs | Task 012 |
| **AC-11** | Every run, check, artifact and finding is persisted; `MEMORY.md` is regenerated from the database and contains no fact absent from it | Task 013 |
| **AC-12** | Installer variants are produced without merging, and each is proven to apply to a pristine base before a build consumes it | Task 003 |
| **AC-13** | No credential appears in any process argument, database column or log line; verified by a test that greps a full run's artifacts for the configured secret | Task 014 |
| **AC-14** | Serial-log matching is NUL-safe and does not depend on any grep flag | Task 007 |
| **AC-15** | The report distinguishes a result that reproduces the recorded pre-change verdict from one that does not, since the former is the regression signal | Task 009 |

## 7. Assumptions & Constraints

**Assumptions**

- VMware Workstation is installed on the Windows host and its binaries are executable from WSL.
- The Photon build tree and the build scripts exist; `sharukhan` orchestrates rather than replaces them.
- The guest installer reads `guestinfo.kickstart.data` via `vmtoolsd`, and `vmtoolsd` is present in the installer initrd. This is what makes install-time axes free.

**Constraints**

- **Sequential execution.** Every ISO build shares one staging tree, and the Windows volume has limited free space. Parallelism is not a future optimisation; it is incorrect.
- **The host runs other people's VMs.** No operation may act on a VM it did not create.
- **Sixteen permutations cannot be automated.** The STIG menu exists only in the curses configurator, so no kickstart can answer it.
- **Portability floor.** `/usr/bin/grep` is toybox non-interactively; `grep -P`, `grep -a` and `sed \U` are unavailable. Behaviour must not depend on any of them.
- **UEFI ignores `bios.bootOrder`.** NVRAM decides the boot source, so it must be stashed between installs.
- **Credentials cannot be added after the fact** on an image built without them, so key material is an input to the build, not a post-install fix.

## 8. Defects in the predecessor tooling not to be inherited

Recorded here because they are requirements by implication, discovered while inventorying the shell tooling:

- `mc-run.sh` accumulates its pass/fail counters inside a `while read` fed by a pipe, so the subshell discards them and the final tally is always zero.
- `mc-verify.sh` locates a cached ISO as `…-prebuilt`, silently ignoring the canister mode the ISO was actually built with.
- The static-address scheme is computed and logged but never applied: `--ip` is never passed to the kickstart generator, so every guest takes a DHCP lease. Either wire it through or remove it — the half-state is worse than either.
- Nine configuration variables are declared and never read, and `MC_MAC_PREFIX` contradicts the OUI actually used.
- The serial-growth liveness instrument was lost in translation from `vm-lab`, and the serial log is truncated rather than offset-bounded, discarding prior-boot evidence.

---

**Document Version:** 1.0
**Last Updated:** 2026-08-31
**Status:** Draft — awaiting Dev Lead feasibility review (Phase 2)
