# Running the matrix: jobs, stop and watch

[← sharukhan overview](../../README.md)

**Who this is for:** Someone with a job running: stopping it, following it, and what the job table guarantees.

**Contents**

- [`stop` — end a job and its process tree](#stop--end-a-job-and-its-process-tree)
- [`watch` — what is running, and follow it](#watch--what-is-running-and-follow-it)
- [The state the job table exists to survive](#the-state-the-job-table-exists-to-survive)
- [One phase at a time](#one-phase-at-a-time)

## `stop` — end a job and its process tree

> **Containers too.** In container mode (`MC_BUILDER=container`) a build runs
> inside `docker run`, and killing the client leaves the container running.
> Every container a job starts is labelled `sharukhan.job=<id>`; `stop` lists
> those containers and stops them after the processes, and says so if one
> survives `docker stop`.

The job's own pid is not enough: killing it leaves `mc-run.sh` and its children
orphaned and still installing. `stop` walks `/proc` for the whole tree, and
`--dry-run` shows exactly what would be signalled:

```
$ sharukhan stop --job 1 --dry-run
job 1 run k03,k04 (state running, alive)
  pid 3360082 plus 2 descendant(s)
    3360096 bash /root/sharukhan-demo/bin/mc-run.sh --only k03
    3360097 sleep 120
  dry run: nothing signalled

matrix VMs still powered on: k11 - not powered off; use `/root/photonos-scripts/staging/mission-control/bin/mc-teardown.sh --id <id>`
2 other VM(s) on this host, untouched
```

```
$ sharukhan stop --job 1
job 1 run k03,k04 (state running, alive)
  pid 3360082 plus 2 descendant(s)
    3360096 bash /root/sharukhan-demo/bin/mc-run.sh --only k03
    3360097 sleep 120
  stopped after 1s; job 1 closed

matrix VMs still powered on: k11 - not powered off; use `/root/photonos-scripts/staging/mission-control/bin/mc-teardown.sh --id <id>`
2 other VM(s) on this host, untouched
```

The parent is signalled first, so it cannot start another row while its children
are being ended; SIGTERM, then SIGKILL after ten seconds, then a re-scan. If
anything survives it is named — a kill that did not happen is never reported as
one.

**`stop` never powers off a VM.** A VM outlives the driver that started it, and
this host also runs `runner-2` and `spagat-smoke`, which are not ours. `stop`
reports what is up and leaves `sharukhan teardown --id <id>` to the operator.

## `watch` — what is running, and follow it

> `sharukhan watch --job <id>` follows a job. `sharukhan watch` without
> `--job` is the upstream watcher (see "The upstream watcher and its
> events"); list jobs with `sharukhan status`.

With no arguments: every job, whether its process is really there, the matrix
VMs, and free space.

```
$ sharukhan watch
  JOB  KIND     STATE     LIVENESS                   STARTED              LABEL
  1    run      running   alive                      2026-09-01T11:49:43Z k03,k04

matrix VMs up: k11 - not powered off; use `/root/photonos-scripts/staging/mission-control/bin/mc-teardown.sh --id <id>`
2 other VM(s) on this host, untouched
/          186G free (87% used)
VM store   108G free (98% used)
```

With `--job`, it follows the log until the job leaves `running`, and exits
non-zero if the job did not end `done`:

```
$ sharukhan watch --job 2 --interval 4
job 2 run k03,k04 - state running, alive, started 2026-09-01T11:50:00Z
log /root/sharukhan-demo/run-logs/run-20260901T115000Z.log
  [sharukhan 2026-09-01T11:50:00Z] job 2 pid 3360126 selection k03,k04
  [sharukhan 2026-09-01T11:50:00Z] group minimal/2.8/prebuilt admitted: media photon-os-installer-2.8-6.ph5.x86_64.rpm matches photon-os-installer-2.8-6*, ISO 60400s old
  [sharukhan 2026-09-01T11:50:00Z] --- k03 ---
  ################ k03 ################

    k03: 13 checks, 13 pass, 0 fail
  [sharukhan 2026-09-01T11:50:12Z] k03: 13 checks, 13 pass, 0 fail
  [sharukhan 2026-09-01T11:50:12Z] --- k04 ---
  ################ k04 ################

    k04: 13 checks, 13 pass, 0 fail
  [sharukhan 2026-09-01T11:50:24Z] k04: 13 checks, 13 pass, 0 fail
  [sharukhan 2026-09-01T11:50:24Z] job 2 done: 2 row(s) attempted

job 2 finished: done at 2026-09-01T11:50:24Z

matrix VMs up: k11 - not powered off; use `/root/photonos-scripts/staging/mission-control/bin/mc-teardown.sh --id <id>`
2 other VM(s) on this host, untouched
```

`--once` prints a snapshot and the last twenty log lines instead of following.

Note `--job <id>` is a job table row id. It is **not** `--jobs <n>`, `status`'s
proposed parallel VM count. The names are unfortunately close; `--jobs` was
already documented and was not renamed.

## The state the job table exists to survive

A driver killed mid-run leaves a row saying `running` and no process. Nothing in
the bash harness could tell that apart from a healthy run, which is how a waiter
waited forever. Here it is named — job 3 below was SIGKILLed:

```
$ sharukhan watch
  JOB  KIND     STATE     LIVENESS                   STARTED              LABEL
  1    run      stopped   pid 3360082                2026-09-01T11:49:43Z k03,k04
  2    run      done      pid 3360126                2026-09-01T11:50:00Z k03,k04
  3    run      running   pid not alive              2026-09-01T11:50:36Z k03

job(s) 3 claim 'running' but their process is gone - they did not finish cleanly. `sharukhan stop --job <id>` closes the row.

matrix VMs up: k11 - not powered off; use `/root/photonos-scripts/staging/mission-control/bin/mc-teardown.sh --id <id>`
2 other VM(s) on this host, untouched
/          186G free (87% used)
VM store   108G free (98% used)
```

A stale row does not block the next run — but the orphan it left behind does, and
the second gate catches it. Both gates, doing their separate jobs:

```
$ sharukhan run --only k05 --dry-run
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
  note    job 3 claims 'running' but pid not alive - it did not finish cleanly; `sharukhan stop --job 3` will close it
  ok      no sharukhan job is running
sharukhan: foreign work is in flight: pid 3360190 bash /root/sharukhan-demo/bin/mc-run.sh --only k03. ISO builds share $PHOTON_TREE/stage and the VM store cannot hold two installs, so this would corrupt both. Wait, or pass --wait-idle <sec>
```

```
$ sharukhan stop --job 3
job 3 run k03 (state running, pid not alive)
  pid not alive - closed the row, no process to signal

matrix VMs still powered on: k11 - not powered off; use `/root/photonos-scripts/staging/mission-control/bin/mc-teardown.sh --id <id>`
2 other VM(s) on this host, untouched
```

`stop` closed the row but could not kill the orphan: it is no longer a
descendant of the dead pid, so it is not `stop`'s to find. That is a real limit,
stated rather than papered over — the orphan above was cleared by hand.

## One phase at a time

Every step `run` takes is also a command of its own, for one row:

| command | what it does |
| --- | --- |
| `kickstart --id <perm>` | prints the kickstart JSON the row would get |
| `create-vm --id <perm> [--iso <path>] [--kickstart <file>] [--recreate]` | thin boot disk, VMX and kickstart injection. `--recreate` stashes the VM directory's *contents* - never the directory, which VMware holds open - and refuses if a disk survives the stash (finding #62) |
| `install --id <perm> [--mode auto\|interactive] [--no-wait] [--timeout <sec>]` | powers on and waits for the guest to boot off disk; see *When an install is finished* |
| `verify --id <perm> [--ip <addr>] [--package-lifecycle ...]` | runs the oracle and harvests logs. Waits up to 120 s for sshd while nothing answers, and never retries an sshd that answered and refused (finding #63). With `--package-lifecycle`, then installs, tests and removes every package of the row's media - see *Package lifecycle* |
| `teardown --id <perm> [--purge]` | stops only this row's VM, stashes its disk chain and removes VMware locks; `--purge` also deletes older stashes |
| `card --id <perm>` | what an operator must enter for an interactive (`ui`) row |

And the commands that produce what the rows consume:

| command | what it does |
| --- | --- |
| `build-iso --iso-type minimal\|full --poi 2.8\|latest --canister <c> [--allow-build] [--force]` | resolves a build-axis tuple to a cached ISO, building it only with `--allow-build`; see *Build mode* below |
| `build [--release] [--subrelease] [--img] [--out] [--dry-run]` | runs the build cascade directly |
| `variant-patches` | rebuilds the installer variant patches from the PR branches and proves each applies to a pristine release |
| `canister [--rebase-check]` | which canister this kernel can have - the same decision a build takes |
| `mirrors` | whether the SPECS copies of photon-os-installer PR commits still match what the published PR branches produce |
| `ingest` | folds the evidence files under `results/` into the memory database; idempotent, so safe to re-run over the whole tree |

---

[← sharukhan overview](../../README.md)
