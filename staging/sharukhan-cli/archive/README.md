# Archive

[← sharukhan overview](../README.md)

**Who this is for:** anyone tracing where sharukhan came from. Nothing in
sharukhan uses, calls or reads anything in this folder; it is kept for
provenance, not for use.

| Folder | From | What it was | Why archived | Replaced by |
|---|---|---|---|---|
| [`superseded-vm-lab/`](superseded-vm-lab/ARCHIVE.md) | 2026-09-10 | The shell and PowerShell toolkit that provisioned Photon OS appliance VMs on VMware Workstation (VMX template, kickstart, install and check scripts). | Its checks could not fail and its inputs resolved implicitly; see its own `ARCHIVE.md` and `PROVENANCE.md`. | `sharukhan create-vm`, `install`, `verify`, `teardown`, `run` |
| [`helper-scripts/`](helper-scripts/README.md) | 2026-09-09 | One-off run wrappers of the September 2026 gate passes (two-pass protocol, full rows, both minimal ISOs, the first equivalent-canister run). | Host-specific absolute paths, inline Python, and one calls a script outside the repository; every one of them is a single `sharukhan` command now. | `sharukhan run`, `sharukhan sync`, [`examples/kernel-iso.sh`](../examples/kernel-iso.sh) |
| [`aarch64-guide/`](aarch64-guide/) | 2026-09-16 | A Word guide and a session-derived setup script for building a Photon OS 5.0 aarch64 ISO by hand. | Not about sharukhan, referenced nowhere, and a `.docx` cannot be read or diffed on GitHub. | - (aarch64 is not a gate in this project) |

Elsewhere: the plan that build mode came from is in
[`specs/archive/build-mode-plan-2026-09.md`](../specs/archive/build-mode-plan-2026-09.md),
the first PRD in [`specs/archive/`](../specs/archive/), and the bash harness
sharukhan absorbed in `../../mission-control/superseded-bash/`.

`MEMORY.md` is no longer kept in the repository: render it from your own
database with `sharukhan db render` (see
[Data files](../docs/automation/data-files.md)).

---

[← sharukhan overview](../README.md)
