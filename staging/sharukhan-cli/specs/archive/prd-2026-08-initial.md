# sharukhan - Product Requirements

## Problem

Verifying a Photon OS PR set means installing it across a 34-row permutation
matrix and comparing each outcome against what the matrix documented before the
PRs. Doing that by hand is slow and, worse, unreliable: the failures that cost
the most time were not in Photon at all but in the harness reporting a
confident wrong answer - a VM that never started scored as a timeout, an
install that succeeded scored as a failure, a stale ISO scored as a pass.

## Goal

One standalone CLI that makes the state of the matrix legible and refuses to
report what it has not established.

## Requirements

- **REQ-1** Parse the permutation matrix and resolve which ISOs the selected
  rows require. Build-time axes (ISO type, installer version) select an ISO;
  install-time axes are injected per VM.
- **REQ-2** Check the environment before any expensive work: tooling present,
  disk headroom on both the build stage and the VM store, ISO cache populated,
  variant patches present, memory database readable.
- **REQ-3** Admission control on disk. Refuse to start work that cannot
  complete, rather than discovering it part-way and leaving a half-written VM
  and a meaningless verdict.
- **REQ-4** Parallelism defaults to `cpus / 4` rounded down, floored at 1, and
  is capped by what the VM store can actually hold.
- **REQ-5** Findings and results persist in SQLite so they outlive the session.
- **REQ-6** Report each permutation's outcome against its documented verdict,
  naming the evidence file the verdict came from.
- **REQ-7** Result files are timestamped and never overwritten, so a re-run
  cannot replace the evidence of the previous one.
- **REQ-8** Unknown permutation ids are an error, not a silent no-op.
- **REQ-9** Distinguish harness VMs from anything else on the hypervisor. A
  production VM sharing the host must never be acted on or miscounted.
- **REQ-10** A start is confirmed against the hypervisor inventory, never
  inferred from an exit code.

## Acceptance

- **AC-1** `doctor` exits non-zero when any precondition fails, and names which.
- **AC-2** `plan` distinguishes cached ISOs from ones that must be built, and
  autonomous rows from rows needing an operator.
- **AC-3** `status` reports running VMs, free space, and the resulting parallel
  limit with the reason for it.
- **AC-4** `findings` reads the database written by previous runs and tolerates
  schema drift.
- **AC-5** `report` shows pass/fail per row with the failing check names and the
  evidence file.
- **AC-6** Every documented example reproduces against a live environment.

## Non-goals for this stage

Driving installs, background job control and operator prompting remain in the
bash harness. They are added only when each can be demonstrated end to end;
a command that half-works is worse than one that is absent.
