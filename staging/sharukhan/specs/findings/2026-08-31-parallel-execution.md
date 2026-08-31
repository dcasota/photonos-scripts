# Finding: installs can run in parallel; only ISO builds must serialise

**Date**: 2026-08-31
**Status**: Resolved by amendment
**Affects**: `specs/prd.md` §7 Constraints, and a new ADR on concurrency

## What the PRD claimed

> **Sequential execution.** Every ISO build shares one staging tree, and the
> Windows volume has limited free space. Parallelism is not a future
> optimisation; it is incorrect.

## What measurement showed

The claim is true of **builds** and false of **installs**, and the PRD collapsed
the two into one constraint.

| Stage | Shares state? | Parallelisable |
|---|---|---|
| ISO build | Yes — `$PHOTON_TREE/stage` (65 GiB) is mutated by `git checkout`, patch application and the stale-RPM purge | **No.** Two concurrent builds corrupt each other. |
| VM install / verify | No — each permutation owns its VM directory, disk, MAC, UUID, IP and results directory | **Yes.** |

Measured on this host (14 CPUs, 23 GiB RAM, C: 131 GiB free):

| Resource | Per concurrent VM | Slots |
|---|---|---|
| CPU | — | `floor(14/4)` = **3** |
| RAM | `memSize` = 4 GiB, as a `.vmem` file present only while running | 17 GiB available ÷ 4 = **4** |
| Disk | `.vmem` 4 GiB + thin `.vmdk` growing toward the installed footprint | 131 GiB ÷ ~16 GiB = **8** |

`.vmem` was measured at exactly 4294967296 bytes on `mc-k01`, matching `memSize`;
the `.vmdk` grew from 4 MiB to 914 MiB during a single install.

**RAM is the binding constraint here, not CPU and not disk.** A limit derived
from CPU count alone would over-commit on a smaller host, so the admission
decision must take the minimum across all three and recompute per dispatch,
because a thin disk grows *during* a run and a check that passed at dispatch
can be false ten minutes later.

## Consequence of leaving it uncorrected

The PRD would have forbidden a legitimate 3x speedup on the install phase — the
dominant cost of a full matrix run — on the strength of a constraint that only
applies to builds.

## Resolution

- `specs/prd.md` §7 amended to separate the two stages.
- New ADR: concurrency and disk-trend admission control, adding `--jobs`
  (default `floor(nproc/4)`), a hard refusal floor below one VM's peak
  requirement, degradation to sequential when capacity is short, and a drain-rate
  projection that stops dispatching *new* work rather than killing running work.
- Builds ignore `--jobs` by construction, and the tool says so once rather than
  appearing to honour it.
