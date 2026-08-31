# sharukhan — Architecture

`sharukhan` is a single standalone Rust CLI that replaces the shell tooling in `staging/vm-lab` and `staging/mission-control`. It checks its own prerequisites, provisions VMware Workstation VMs, drives Photon OS installs both unattended and operator-assisted, verifies the result, and records every finding in a queryable memory database.

The name is the tool; the job is mission control for the ISO permutation matrix.

## Why one binary

The shell tooling worked but had three structural problems that a matrix runner cannot tolerate, each observed rather than hypothesised:

- **Inputs resolved implicitly.** `runPh5_normal.sh` resolved its patch relative to its own location, so two checkouts silently used different patches; the two copies on the host had drifted 78 lines and 8-vs-27 files apart. The failure surfaced as `patch does not apply` against a spec — indistinguishable from a rebase problem.
- **Checks that could not fail.** `vm-lab/scripts/40-check-staging.sh` never exits non-zero. Fine for an inspection tool, useless as a gate.
- **Portability landmines.** `/usr/bin/grep` is toybox in a non-interactive shell and has no `-a`, returning *zero matches* on a NUL-bearing serial log rather than erroring; interactively the same name is `ugrep`, which behaves differently again. `sed \U` and `grep -P` are GNU-only and absent. A verdict computed by such a pipeline can be silently vacuous.

A compiled binary with typed errors, explicit inputs and real exit codes removes all three by construction.

## Layers

```
                 +-------------------------------------------+
   cli           |  clap surface: doctor / build / run /      |
                 |  status / stop / report / db               |
                 +---------------------+---------------------+
                                       |
   orchestration  +--------------------v---------------------+
                  | permutation planner, scheduler,          |
                  | background job control                    |
                  +--------------------+---------------------+
                                       |
   domain    +----------+----------+---+------+-----------+----------+
             | preflight|  iso     | vm       | install   | verify   |
             | (probes) | (build/  | (vmx,    | (auto via | (oracle, |
             |          |  cache)  |  disk)   | guestinfo;|  harvest)|
             |          |          |          |  or human)|          |
             +----+-----+----+-----+----+-----+-----+-----+-----+----+
                  |          |          |           |           |
   adapters  +----v----------v----------v-----------v-----------v---+
             | process runner (argv only) | fs | ssh | xorriso | git |
             +------------------------+-------------------------+---+
                                      |
   persistence            +-----------v-----------+
                          |  memory database      |
                          |  (findings, runs,     |
                          |   checks, artifacts)  |
                          +-----------------------+
```

Every layer depends only downward. The domain layer never shells out directly; it goes through the process-runner adapter, which takes an argument vector and never a shell string. That single choke point is what makes the security posture testable.

## The axis model

The matrix separates cleanly, and the separation is what makes 34 permutations cost 4 builds:

| Axis | Values | Decided at | Consequence |
|---|---|---|---|
| ISO type | `minimal`, `full` | **build** | separate ISO |
| Installer version | `2.8`, `latest` | **build** | separate ISO |
| STIG hardening | `no`, `yes` | install | free |
| Root filesystem | `ext4`, `btrfs` | install | free |
| Delivery | `kickstart`, `ui` | install | free |

Install-time axes are free because Photon's `isoInstaller` reads `guestinfo.kickstart.data` through `vmtoolsd`, and `vmtoolsd` is present in the installer initrd. A per-permutation kickstart is one VMX line — no ISO remaster, no HTTP server, no boot-menu interaction.

The `ui` value cannot be automated: the STIG menu exists only in the curses configurator, so no kickstart can answer it. Those permutations are operator-assisted by design, not by omission.

## Memory database

Results are not files that happen to be greppable; they are rows. The database is the system of record and `MEMORY.md` is a generated view over it that always refers to it rather than duplicating it — so the two cannot disagree.

Entities: `run`, `permutation`, `check`, `artifact`, `finding`, `job`. A `check` carries the PR it proves, which is what turns a failure into `PR#22 regressed` rather than `something broke`.

## Security posture

The tool orchestrates VMs, handles credentials and executes external binaries. Controls are chosen against NIST SP 800-53 families and MITRE ATT&CK techniques and are recorded in ADRs, not asserted here. The defence-in-depth summary:

- credentials never occupy a process argument (`/proc` is world-readable) and never reach the database or a log
- external commands are argument vectors, never shell strings
- SQL is always parameterised
- destructive operations stash rather than delete, target one named VM, and validate their paths first — the host runs other people's VMs
- prerequisite checks report version *and* provenance, because a version-skewed dependency presents exactly like an unreachable host

## SDD Methodology

This subproject is developed spec-first. Artifacts live in [`specs/`](specs/); the phases, identifier chain, quality gates and branch/commit conventions are defined in [`specs/README.md`](specs/README.md). Implementation is gated behind a merged PRD.

The methodology is reconstructed from the maintainer's `vCenter-CVE-drift-analyzer` and from `sitoader/SDD-book-tracking-app`, adapted to Rust. Neither source contains a constitution file; [`AGENTS.md`](AGENTS.md) was authored by hand and says so.

## Open Initiatives

| Phase | Deliverable | Status |
|---|---|---|
| 0 | `ARCHITECTURE.md`, `specs/README.md`, `AGENTS.md` | Complete (#319) |
| 1 | `specs/prd.md` | In Progress |
| 2 | Dev Lead review on the PRD PR | Pending |
| 3 | `specs/adr/0001`–`000n` | Pending |
| 4 | `specs/features/*.md` | Pending |
| 5 | `specs/tasks/NNN-task-*.md` + index | Pending |
| 6 | `src/`, `tests/` — one PR per task | Pending |
