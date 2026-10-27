# sharukhan — Architecture

`sharukhan` is a single standalone Rust CLI that replaces the shell tooling of vm-lab and mission-control, both archived rather than deleted — vm-lab here under `archive/superseded-vm-lab/`, mission-control under `staging/mission-control/superseded-bash/`. It checks its own prerequisites, provisions VMware Workstation VMs, drives Photon OS installs both unattended and operator-assisted, verifies the result, and records every finding in a queryable memory database.

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
   cli           |  inspect: doctor plan status findings     |
                 |           report                          |
                 |  drive:   run stop watch                  |
                 |  phases:  kickstart create-vm install     |
                 |           verify teardown card            |
                 |  build:   build-iso build variant-patches |
                 |           canister mirrors ingest         |
                 |  planned: db render (Task 013)            |
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

## Modules

| Layer | Modules | Responsibility |
|---|---|---|
| orchestration | `runner` | `run`, `stop`, `watch`: gates, serialisation, one row end to end |
| orchestration | `job` | the `job` table: background work that outlives its shell |
| orchestration | `matrix`, `identity` | the permutation matrix; deterministic per-row MAC, UUID and IP |
| domain: preflight | `disk`, `proc`, `canister` | disk admission; process lookup that cannot match itself; which canister a kernel can have |
| domain: iso | `build`, `buildmode`, `buildexec`, `media`, `specresolve` | resolving a tuple to an ISO and the variant patches; the build cascade and its execution; proving an ISO carries the packages under test; reading a spec as one subrelease sees it (subrelease conditionals decided, includes inlined) |
| domain: iso | `builder`, `specdata`, `specparity` | the pinned builder container that runs Photon's tooling; parsing a SPECS tree as the package builder does, before a build; whether a reworked tree builds what a reference tree builds |
| domain: iso | `poiimage`, `isoboot`, `caneq`, `kernelslot`, `subvault` | the installer image that composes the ISO, built from the variant under test; how an ISO boots, read from the ISO; the embedded canister-equivalent patch; the stage's kernel slot shared by prebuilt and equivalent builds; keeping another subrelease's RPMs out of a pinned build |
| domain: kernel | `wrapper` (`base`, `branch`, `cli`, `derive`, `identity`, `kernelorg`, ...), `kbuild` | kernel wrappers and profiles for kernel.org kernels, verified against kernel.org's signatures; ISO builds and runs with a profile's kernel (`--kernel`) |
| domain: iso | `kconfig` | Kconfig as data: the Hyper-V fragment, the tristate parser, the dependency closure a fragment implies, and the IKCONFIG blob inside a built kernel (with its own gzip/DEFLATE decoder) |
| domain: iso | `remaster` (`buildroot`, `kernel`, `cc1`, `initrd`, `repo`, `iso`, `guard`) | making an Azure variant of an ISO that already exists: a build root bootstrapped from the input's own RPMs, the kernel rebuilt in it, the installer initrd and repo metadata reworked, and the medium rewritten by replaying its boot image |
| domain: vm | `vm`, `vmx`, `kickstart`, `net` | the VM on disk and taking it back; the VMX template; the POI kickstart; the network axis |
| domain: install | `console`, `vnc`, `des` | answering a boot menu that waits for a key: the VM's console through VMware's VNC server, and the single-block DES its authentication needs |
| domain: install | `install`, `leases`, `serial`, `card` | one install; the DHCP lease file and serial log as boot signals; the operator card |
| domain: verify | `verify`, `oracle`, `evidence`, `report` | running the oracle and harvesting logs; the assertions; structured results; per-row report |
| domain: verify | `pkglife` (`remote`, `parse`, `classify`, `policy`, `units`, `probe`, `record`, `media`) | opt-in package lifecycle after verify: the row's ISO as the repository, per-package install / test by content / remove / residue, controls, the reviewed safety policy (ADR-0008) |
| adapters | `guest`, `vmware`, `winpath`, `sha256`, `sha512`, `b64` | ssh into the guest; vmrun; WSL to Windows paths; hashing and encoding without shelling out |
| domain: specs | `branchguard` | guarding a PR branch against a base that has moved: the %changelog version it adds must not be one the target already publishes, the top entry must not predate the one beneath it, and enumerating a commit's paths must not collapse a rename to its destination and leave the source behind |
| persistence | `memory`, `ingest` | the memory database; deriving it from the evidence files |
| automation | `sync`, `syncrun`, `prbody`, `subrel`, `variants` | the fork sync: analysis, rebase and verify (`sync`), the resumable state machine and its stages (`syncrun`, ADR-0009, ADR-0011), PR descriptions carried and linted (`prbody`), subreleases from the tree, the variants file |
| automation | `watch`, `health` | the upstream watcher and its events and notifications; `doctor`'s automation checks |
| automation | `escalate`, `mcp` | the escalation queue, budgets and ledger; the stdio MCP server it works through (ADR-0010) |
| host | `service`, `secret`, `author` | the host services, settings file and secret files (ADR-0012); the configured commit author |
| persistence | `dbrender`, `doccheck` | `db render` (MEMORY.md as a view); the documentation tests (links, anchors, subcommands, profiles) |
| cli | `main`, `phases`, `config` | the command surface; one entry point per phase; typed paths and defaults |

## The axis model

The matrix separates cleanly, and the separation is what makes 43 permutations cost 7 ISOs (6 buildable on an x86_64 host; `fips0-aarch64` needs aarch64 hardware):

| Axis | Values | Decided at | Consequence |
|---|---|---|---|
| ISO type | `minimal`, `full` | **build** | separate ISO |
| Installer version | `2.8`, `latest` | **build** | separate ISO |
| FIPS canister | `prebuilt`, `equivalent`, `fips0-aarch64` | **build** | separate ISO |
| STIG hardening | `no`, `yes` | install | free |
| Root filesystem | `ext4`, `btrfs` | install | free |
| Delivery | `kickstart`, `ui` | install | free |
| Network | `<family>-<assignment>-<vlan>`, e.g. `v4-dhcp-untag` | install | free |

Install-time axes are free because Photon's `isoInstaller` reads `guestinfo.kickstart.data` through `vmtoolsd`, and `vmtoolsd` is present in the installer initrd. A per-permutation kickstart is one VMX line — no ISO remaster, no HTTP server, no boot-menu interaction.

The `ui` value cannot be automated: the STIG menu exists only in the curses configurator, so no kickstart can answer it. Those permutations are operator-assisted by design, not by omission.

## Memory database

Results are not files that happen to be greppable; they are rows. The database is the system of record and `MEMORY.md` is a generated view over it that always refers to it rather than duplicating it — so the two cannot disagree.

Tables of the matrix: `run`, `permutation`, `check_result`, `artifact`, `finding`, `job`, `next_step`, `rule`, `package_lifecycle`, `ingest_file` (which results files are indexed). Tables of the automation: `sync_run`, `sync_stage`, `sync_pr` (ADR-0009), `escalation` (ADR-0010), `event`, `heartbeat`, `upstream_head` (the watcher). `MEMORY.md` is not kept in the repository; `sharukhan db render` makes it. A `check_result` carries the PR it proves, which is what turns a failure into `PR#22 regressed` rather than `something broke`. `run`, `permutation` and `check_result` are derived from the evidence files under `results/` by `sharukhan ingest`, which is idempotent; `finding` and `next_step` are written by hand; `artifact` is declared but not yet written. `MEMORY.md` is rendered from the database by `sharukhan db render` (which replaced the stand-in tools/gen-memory-md.py with identical output); the PRD assigned it to Task 013, together with AC-16's versioned reports.

## Security posture

The tool orchestrates VMs, handles credentials and executes external binaries. Controls are chosen against NIST SP 800-53 families and MITRE ATT&CK techniques and are recorded in ADRs, not asserted here. The defence-in-depth summary:

- credentials never occupy a process argument (`/proc` is world-readable) and never reach the database or a log
- external commands are argument vectors, never shell strings
- SQL is always parameterised
- destructive operations stash rather than delete, target one named VM, and validate their paths first — the host runs other people's VMs
- prerequisite checks report version *and* provenance, because a version-skewed dependency presents exactly like an unreachable host
- secrets live in owner-only files the settings name (`MC_ANTHROPIC_KEY_FILE`, `MC_GUEST_PASSWORD_FILE`), never in a unit or the settings file (ADR-0012)
- a model resolving a stopped PR has no built-in tools, only sharukhan's MCP tools, and the spec tools it triggers run in read-only, capability-free containers; nothing it proposes is published without a person (ADR-0010)

## SDD Methodology

This subproject is developed spec-first. Artifacts live in [`specs/`](specs/); the phases, identifier chain, quality gates and branch/commit conventions are defined in [`specs/README.md`](specs/README.md). Implementation is gated behind a merged PRD.

The methodology is reconstructed from the maintainer's `vCenter-CVE-drift-analyzer` and from `sitoader/SDD-book-tracking-app`, adapted to Rust. Neither source contains a constitution file; [`AGENTS.md`](AGENTS.md) was authored by hand and says so.

## Open Initiatives

| Phase | Deliverable | Status |
|---|---|---|
| 0 | `ARCHITECTURE.md`, `specs/README.md`, `AGENTS.md` | Complete (#319) |
| 1 | `specs/prd.md` | Complete — landed with the SDD layout on 2026-09-10 |
| 2 | Dev Lead review on the PRD PR | Not recorded |
| 3 | `specs/adr/0001`–`0012` | Complete for the decisions taken so far: run/stop/watch, kernel wrappers (0002-0007), package lifecycle (0008), sync (0009), escalation (0010), upstream stage (0011), host services (0012) |
| 4 | `specs/features/*.md` | Kernel wrapper, package lifecycle, Hyper-V/Azure remaster; the sync and the escalation are specified by their ADRs and `docs/automation/` |
| 5 | `specs/tasks/NNN-task-*.md` + index | Tasks 001 (kernel wrapper) and 002 (package lifecycle); the `db` command the PRD planned is implemented (`sharukhan db render`) |
| 6 | `src/`, `tests/` — one PR per task | Ahead of phases 2–5: the CLI predates the SDD layout. 195 unit tests; where the implementation disproved an assumption it is recorded under `specs/findings/` |