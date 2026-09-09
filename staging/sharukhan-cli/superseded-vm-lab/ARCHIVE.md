# Superseded vm-lab

The shell toolkit that provisioned Photon OS VMs on VMware Workstation before
`sharukhan` existed. Archived rather than deleted, on the same reasoning as
`../../mission-control/superseded-bash/`: the scripts record how this host was
driven, and that provenance is not recoverable from the Rust CLI.

Everything they did is in `sharukhan`. Nothing here is invoked by the CLI, and
none of it is on any execution path.

## Why it was replaced

`ARCHITECTURE.md` names the structural problem this toolkit had, in its own
terms:

> `vm-lab/scripts/40-check-staging.sh` never exits non-zero. Fine for an
> inspection tool, useless as a gate.

A matrix runner cannot use a check that has no failing outcome. That, plus
implicitly resolved inputs and shell-portability landmines, is what one binary
was meant to fix.

## Layout

| Path | What it was |
|---|---|
| `scripts/00-preflight.sh` … `90-teardown.ps1` | The numbered lifecycle: preflight, create, key, install, check, verify, ssh, teardown. Two are PowerShell, because VM creation and teardown ran on the Windows side. |
| `kickstart/photon-appliance.ks.template.json` | The kickstart template, with `EXPECTED-SHA256` and `check-drift.sh` guarding it against upstream drift. |
| `config/vm-lab.env`, `config/spagat-smoke.vmx.template` | Environment and the VMX template. |
| `PROVENANCE.md`, `README.md` | The originals, unmodified. |

## Reading it

The scripts assume paths and a host that no longer apply. Treat this directory
as a record, not as something to run.
