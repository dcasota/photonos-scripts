# Finding: three harness races produced false results in a full matrix run

**Date**: 2026-09-13
**Status**: Resolved by amendment (runner, vm, verify, media, guest)
**Affects**: finding #29's mitigation as implemented; how `run` prepares a
row's VM; how `verify` decides a guest is unreachable

## What the harness assumed

1. An ISO younger than `--settle` should be **refused**, "so the operator sees
   the reason instead of an unexplained pause".
2. `create --recreate` leaves a row with a fresh disk: the stash moves the old
   one aside.
3. The install's "leased under its own hostname" signal means sshd is ready, so
   one ssh attempt with a 10 s connect timeout decides reachability.

## What measurement showed

A re-run of all 26 automated rows against the restacked kernel PRs:

| Row | What happened | Why it was not a product result |
|---|---|---|
| `c01` | Group `full/2.8/equivalent` REFUSED: ISO "written 48s ago" | The campaign's last build flowed straight into `run`. The row was never attempted, and `report --all` kept showing its 2026-09-12 result as a pass. |
| `c03` | Passed, "installed" 18 s after power-on | Its VM had been left powered on. `fs::rename` of the `.vmdk` VMware held open failed, `stash_contents` discarded the error, and `create` logged "disk already present, keeping it". The harvested manifest shows `install_time 2026-09-13 01:02:07`, 13 hours before the ISO under test existed. Kernel and canister NEVRs matched, so no version check could tell. |
| `k16` | FAIL, `guest.ssh`: "Connection timed out" | Probed once, 12 s after its lease. Seven other STIG rows answered 15-20 s after theirs. Rerun on a fresh disk: 39 checks, 0 fail, 30 s after lease. |

## Consequence of leaving it uncorrected

Two of the three failure modes are silent: a skipped row reads as passing, and
a row can pass on an installation that never came from the media under test.
The third turns boot-timing jitter on the heaviest rows into false FAILs.

## Resolution

- **Settle.** Finding #29's own mitigation is a settle delay. `media::settled`
  returns a typed `Unsettled`; the runner waits out `Young` — logging the
  measured age and remaining seconds, bounded by `--settle` — and re-checks.
  `Growing` and `Unreadable` are still refused.
- **Disk.** `run_row` tears the row's VM down (stop our own VM, stash its disk
  chain) before `create`. Stash failures are logged by name in both `create`
  and `teardown`, and `create --recreate` refuses when a disk survives.
- **ssh.** `verify` retries every 5 s for up to 120 s while
  `guest::transport_not_ready` holds (timeout, refused, no route, reset). An
  sshd that answered and refused — `Permission denied`, `Unable to negotiate` —
  is never retried: that text is `s02`'s evidence.

Recorded in `memory.db` as findings 61-63.
