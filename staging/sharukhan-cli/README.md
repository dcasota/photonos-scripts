# sharukhan

A single standalone CLI for verifying Photon OS ISOs and the PRs that go into
them, across the permutation matrix in `ISO-PERMUTATION-MATRIX.md`.

The matrix spans six axes — minimal/full ISO, installer 2.8 or latest, FIPS
crypto canister, with/without STIG, ext4/btrfs, and kickstart or the interactive
UI. Three of those are decided when the ISO is built (`iso_type`, `poi`,
`canister`); the rest are injected per VM. That is why 36 permutations need only
a handful of ISOs rather than one each.

Every command reports what it actually observed. Where a fact cannot be
established it says so rather than guessing — a harness that confidently
reports a wrong answer is worse than one that reports nothing.

## Status

Implemented and working: `doctor`, `plan`, `status`, `findings`, `report`,
`run`, `stop`, `watch`.

`run` orchestrates; it does not build. ISO builds, kickstart and VMX generation,
the install itself and the guest oracle all remain in the `mission-control` bash
harness, which `run` shells out to. The reasoning, and the full list of what was
deliberately left out, is in [`specs/adr-0001-run-stop-watch.md`](specs/adr-0001-run-stop-watch.md).

This README documents only what runs today. Every block below is captured
output, not an illustration.

## Build

```
cargo build --release
./target/release/sharukhan --help
```

One dependency (`rusqlite`, bundled SQLite). No network access at runtime.

## Commands

### `doctor` — check the environment before anything is built or run

Run this first. It is cheap and it catches the things that otherwise waste an
hour: a missing `vmrun`, an empty ISO cache, a build stage with no headroom.

```
$ sharukhan doctor
environment
  [ok  ] photon tree            /root/5.0
  [ok  ] matrix                 /root/photonos-scripts/staging/mission-control/config/permutations.tsv
  [ok  ] vmrun                  /mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe
capacity
  [ok  ] / (build stage)        167G free (88% used), needs 25G
  [ok  ] VM store               112G free (98% used), needs 20G
inputs
  [ok  ] variant patches        /root/photon-mc/variant-patches
  [ok  ] iso cache              full-poi2.8-prebuilt, full-poilatest-prebuilt, minimal-poi2.8-prebuilt, minimal-poilatest-prebuilt
memory
  [ok  ] database               31 finding(s)

all checks passed
```

Exit code is non-zero when any check fails, so it drops straight into a script:

```
sharukhan doctor || exit 1
```

### `plan` — what would run, and what has to be built first

```
$ sharukhan plan --only k01,k03,p01
ISOs required (1):
  minimal/2.8/prebuilt       cached

permutations: 3 (2 autonomous, 1 need an operator)
  ID    ISO      POI     STIG  FS     MODE  VARIANT    CANISTER       DOC
  k01   minimal  2.8     no    ext4   ks    none       prebuilt       works
  k03   minimal  2.8     yes   ext4   ks    stigpkgs   prebuilt       fails
  p01   minimal  2.8     no    ext4   ui    -          prebuilt       works
```

The ISO key is `iso_type/poi/canister` — all three are build-time axes, so a row
needing a different canister cannot silently reuse the prebuilt ISO.

`cached` vs `must be built` is the difference between a two-minute run and an
hour, so check it before starting a batch:

```
$ sharukhan plan --only k09,k13
ISOs required (2):
  full/2.8/prebuilt          cached
  full/latest/prebuilt       cached
```

The whole matrix at once:

```
$ sharukhan plan
```

`DOC` is what the matrix recorded before the PRs were applied. A row marked
`fails` that now passes is a fix; a row marked `works` that now fails is a
regression. That comparison is the point of the exercise.

Unknown ids are refused rather than skipped, because asking for a row that does
not exist should never look like a clean run:

```
$ sharukhan plan --only k01,k99
sharukhan: unknown permutation id(s): k99
```

### `status` — VMs, disk, and how much parallelism that allows

```
$ sharukhan status
running VMs
  C:\spagat-iso-build\vm\runner-2\runner-2.vmx
  C:\photon-mc\vm\mc-s02\mc-s02.vmx

disk
  /          48G free (97% used)
  VM store   116G free (97% used)

matrix VMs up: s02

parallel VMs allowed: 3
  3 (cpus=14 -> 3)
  an ISO build would be admitted
```

The default parallel count is `cpus / 4`, floored at 1 — 14 CPUs gives 3. It is
then capped by what the VM store can actually hold, because parallelism that
fills the disk is worse than none:

```
$ sharukhan status --jobs 8
parallel VMs allowed: 5
  5 (requested 8, but /mnt/c/photon-mc/vm only has room for 5)
```

`matrix VMs up` distinguishes harness VMs from anything else on the host, so a
production VM sharing the hypervisor is never mistaken for a test one.

### `findings` — what previous runs established

Findings live in SQLite so they survive the session that produced them.

```
$ sharukhan findings | head -4
31 finding(s)

  #1   blocker    -          toybox-grep-no-dash-a
  #2   high       -          gnu-only-sed-grep
```

Filter by severity:

```
$ sharukhan findings --severity blocker
```

The column names are discovered from the schema rather than assumed, so a
database written by an older or newer version still reports something useful
instead of failing outright.

### `report` — results of the last run of each permutation

```
$ sharukhan report --only k01,k02,k03,k04,s01,s02
  ID    ISO      POI     STIG  FS     DOC        RESULT   EVIDENCE                     FAILED CHECKS
  k01   minimal  2.8     no    ext4   works      13 pass  checks-20260831T190338Z.jsonl 
  k02   minimal  2.8     no    btrfs  untested   13 pass  checks-20260831T190527Z.jsonl 
  k03   minimal  2.8     yes   ext4   fails      15 pass  checks-20260831T190822Z.jsonl 
  k04   minimal  2.8     yes   btrfs  fails      15 pass  checks-20260831T191422Z.jsonl 
  s01   minimal  2.8     no    ext4   fails      13 pass  checks-20260831T191846Z.jsonl 
  s02   minimal  2.8     no    ext4   fails      1 FAIL   checks-20260831T192717Z.jsonl guest.ssh

6 of 6 permutation(s) have results; 1 with failing checks
```

Read that against `DOC`: k03 and k04 were recorded as `fails` and now pass —
those are the STIG SELinux-relabel ordering fix. s02 fails `guest.ssh`, which is
the FIPS defect where sshd offers algorithms the FIPS crypto then refuses.

All 18 autonomous rows have now been run across the four ISOs. Six rows moved from
a documented `fails` to a clean pass, seven previously `untested` predictions were
confirmed, and one genuine defect remains (s02). Four rows first reported as
failures turned out to be a wrong expectation in the oracle rather than a defect:
on subrelease 92 `selinux-policy` ships permissive by design, so asserting
`Enforcing` was incorrect. That is the failure mode this tool exists to avoid, and
it still got through — the guard against it is that every verdict names the
evidence file it came from, so the claim can be re-checked rather than believed.

`EVIDENCE` names the exact result file each verdict came from. Result files are
timestamped and never overwritten, so a re-run cannot quietly replace the
evidence of the previous one.

Rows with no results say so rather than being omitted:

```
$ sharukhan report --only k09,k10
  k09   full     2.8     no    ext4   untested   not run  -                            -
  k10   full     2.8     no    btrfs  untested   not run  -                            -
```

### `run` — drive permutations through mission-control, sequentially

`run` is the gate in front of `mc-run.sh`, not a replacement for it. It decides
what may proceed, serialises against anything already in flight, proves the
media, and records a job so the work is findable after the shell that started it
is gone. Rows run one at a time, because ISO builds share `$PHOTON_TREE/stage`
and the VM store cannot hold two installs.

`--dry-run` runs every gate for real — real `df`, real `xorriso`, real process
scan — and executes nothing:

```
$ sharukhan run --dry-run --only k03,k04,s02
selection: 3 row(s)
  3 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 186G free, VM store 108G free

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 59748s ago

would run 3 row(s), sequentially:
  k03   minimal/2.8/prebuilt     /root/photonos-scripts/staging/mission-control/bin/mc-run.sh --only k03
  k04   minimal/2.8/prebuilt     /root/photonos-scripts/staging/mission-control/bin/mc-run.sh --only k04
  s02   minimal/2.8/prebuilt     /root/photonos-scripts/staging/mission-control/bin/mc-run.sh --only s02

dry run: no job recorded, nothing executed
```

The expected installer NEVR in that `media` line is **derived**, never written
down: the `photon-os-installer.spec` hunk of `variant-patches/poi-2.8.patch` is
isolated (the patch touches ~28 specs, so an unisolated grep reads the wrong
one) and its `+Release:` read; `Version:` comes from `git show origin/5.0:` when
the variant does not set it. A driver that hardcoded `2.9-2` rejected a good ISO
once the spec moved to `2.9-3`, and could not be edited in place because bash
re-reads a running script.

`--all` selects the matrix and then refuses, individually and out loud, every row
this host cannot drive:

```
$ sharukhan run --dry-run --all
selection: 36 row(s)
  refused p01   mode=ui needs a human at the console: /root/photonos-scripts/staging/mission-control/bin/mc-operator-card.sh --id p01
  [p02 through p16 refused identically - 15 lines elided]
  refused c02   canister=fips0-aarch64 needs aarch64, this host is x86_64
  19 row(s) can run autonomously

[serialisation and disk sections elided - identical to the block above]

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 59760s ago
  ok      minimal/latest/prebuilt  media has photon-os-installer-2.9-3.ph5.x86_64.rpm (expected photon-os-installer-2.9-3*), written 53021s ago
  ok      full/2.8/prebuilt        media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 11288s ago
  ok      full/latest/prebuilt     media has photon-os-installer-2.9-3.ph5.x86_64.rpm (expected photon-os-installer-2.9-3*), written 7773s ago
  REFUSED full/2.8/build           no ISO at /mnt/c/photon-mc/iso-cache/full-poi2.8-build/photon.iso - build it with `/root/photonos-scripts/staging/mission-control/bin/mc-build-iso.sh --iso-type full --poi 2.8 --canister build` (hours, not minutes)
```

`run` refuses a missing ISO rather than building one. `mc-run.sh` would have
built it silently, turning a two-minute invocation into an eleven-hour one.

**A refused gate refuses the whole group.** Pointing at a variant patch that
asks for `2.8-7` while the media carries `2.8-6`:

```
$ MC_VARIANT_PATCH_DIR=/root/sharukhan-demo/variant-patches sharukhan run --dry-run --only k03,k04
selection: 2 row(s)
  2 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 186G free, VM store 108G free

media
  REFUSED minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-7*), written 60508s ago
sharukhan: every ISO group was refused; nothing would be run
```

**An ISO that is still settling is refused too**, because VMware cannot open one
that is (finding #29: the same 3.9G image was unopenable the second it landed and
instant eight minutes later). Forcing the check with an absurd `--settle` shows
the refusal:

```
$ sharukhan run --dry-run --only k13 --settle 99999
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 186G free, VM store 108G free

media
  REFUSED full/latest/prebuilt     /mnt/c/photon-mc/iso-cache/full-poilatest-prebuilt/photon.iso was written 7788s ago; VMware cannot reliably open an ISO that is still settling (finding #29). Wait 92211s or pass --settle 0 if you know the file is quiet.
```

It refuses rather than sleeping, so the reason is visible instead of being an
unexplained pause.

Foreign work already in flight is refused too. `--wait-idle <sec>` bounds how
long it will wait first; the default is 0, because a CLI that blocks forever is
the failure being fixed:

```
$ sharukhan run --only k03 --dry-run --wait-idle 20
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  wait    1 process(es) in flight, waited 0s of 20s
  wait    1 process(es) in flight, waited 15s of 20s
sharukhan: foreign work is in flight: pid 3360289 bash /root/sharukhan-demo/bin/mc-build-iso.sh. ISO builds share $PHOTON_TREE/stage and the VM store cannot hold two installs, so this would corrupt both. Wait, or pass --wait-idle <sec>
```

A real run is a foreground process; background it the way the bash drivers were
backgrounded. It prints the job id and the two commands that act on it.

> **The captures from here to the end of `watch` were produced against a stub
> `mc-run.sh`** — it prints the summary line `mc_result_summary` emits and then
> sleeps — with `MC_BIN=/root/sharukhan-demo/bin` and
> `MC_RUN_LOG_DIR=/root/sharukhan-demo/run-logs`. Nothing is edited; the stub
> paths are visible in the output below. Gating, serialisation, job recording,
> verdict scraping, process-tree teardown and log following are all real. What
> is stubbed is the install underneath: a real 16-row pass takes hours and a
> VMware host, and has **not** been run through this code. The ADR says the same.

```
$ nohup sharukhan run --only k03,k04 &
selection: 2 row(s)
  2 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 186G free, VM store 108G free

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-6.ph5.x86_64.rpm (expected photon-os-installer-2.8-6*), written 60400s ago

job 2 (pid 3360126) -> /root/sharukhan-demo/run-logs/run-20260901T115000Z.log
  sharukhan watch --job 2
  sharukhan stop  --job 2
  running k03 (minimal/2.8/prebuilt)
  k03: 13 checks, 13 pass, 0 fail
  running k04 (minimal/2.8/prebuilt)
  k04: 13 checks, 13 pass, 0 fail

job 2 done: 2 of 2 admissible row(s) attempted
evidence: /root/sharukhan-demo/run-logs/run-20260901T115000Z.log
results:  sharukhan report --only k03,k04
```

`k03: 13 checks, 13 pass, 0 fail` is scraped from `mc-run.sh`'s own summary
line. `mc-run.sh` ends with `mc_report_to_file`, so its exit code reflects the
last `tee` rather than the verdict — the scraped line is the evidence, and the
exit code is reported only when there is no line to scrape.

While a job is live, a second `run` is refused by name. This is the
serialisation that mattered: two drivers polling the same idle condition both
woke when it cleared and started an ISO build and a VM install at once.

```
$ sharukhan run --only k05 --dry-run
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
sharukhan: job 1 (run k03,k04) is still running as pid 3360082; refusing to start a second one. Watch it with `sharukhan watch --job 1` or end it with `sharukhan stop --job 1`
```

### `stop` — end a job and its process tree

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
reports what is up and leaves `mc-teardown.sh` to the operator.

### `watch` — what is running, and follow it

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

### The state the job table exists to survive

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

## Typical session

```
sharukhan doctor                     # is the machine fit to run anything
sharukhan plan --only k01,k02        # what will run, is the ISO cached
sharukhan status                     # room to run it, and how many at once
sharukhan run --dry-run --only k01,k02   # every gate, for real, executing nothing
nohup sharukhan run --only k01,k02 &     # prints a job id
sharukhan watch --job 1              # follow it
sharukhan stop --job 1               # if it has to end early
sharukhan report --only k01,k02      # what happened, against the documented verdict
sharukhan findings                   # what previous runs established
```

## Configuration

Every path has a default and an environment override. Nothing is tied to one
machine.

| Variable | Default |
| --- | --- |
| `PHOTON_TREE` | `/root/5.0` |
| `SHARUKHAN_MATRIX` | `<mission-control>/config/permutations.tsv` |
| `MC_RESULTS_DIR` | `/root/photon-mc/results` |
| `SHARUKHAN_DB` | `/root/photon-mc/memory.db` |
| `MC_ISO_CACHE` | `/mnt/c/photon-mc/iso-cache` |
| `MC_VARIANT_PATCH_DIR` | `/root/photon-mc/variant-patches` |
| `MC_VM_ROOT_WSL` | `/mnt/c/photon-mc/vm` |
| `VMRUN` | `/mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe` |
| `MC_BIN` | `<mission-control>/bin` |
| `MC_RUN_LOG_DIR` | `/root/photon-mc/run-logs` |

```
SHARUKHAN_DB=/tmp/other.db sharukhan findings
```

## Things learned the hard way

These are encoded in the code, with the reasoning in comments, because each one
cost real time:

- **`permutations.tsv` is whitespace-aligned, not tab-separated.** Splitting on
  `\t` yields zero rows and looks like an empty matrix rather than an error.
- **`vmrun` output is CRLF-terminated.** It is a Windows binary; not stripping
  `\r` makes every comparison fail while the output looks correct.
- **`vmrun` exits 0 even when the VM did not start.** A stale modal dialog in
  the Workstation UI silently swallows the power-on request, so a start has to
  be confirmed against the inventory, not trusted from the exit code.
- **Disk is checked before work starts, not during.** Running out part-way
  leaves a half-written VM and a verdict that means nothing.
- **Evidence observed in one phase is authoritative.** A later phase that fails
  to reproduce it must not overturn it — that produced false failures on every
  row until it was fixed. The media gate is evaluated once per ISO group and
  recorded; per-row processing never re-derives it.
- **`vmrun` exits non-zero when the VM is merely slow.** Attaching a 3.9G ISO
  trips its internal timeout while VMware powers the VM up anyway. Together with
  the line above: the exit code is not evidence in *either* direction, so no
  command here branches on one. The inventory is the sole authority.
- **`pgrep -f` matches the process doing the checking.** The pattern is on the
  checker's own command line. That made a bash waiter wait for itself and made a
  `pkill -f` kill the shell that issued it, twice. `proc::matching` scans
  `/proc` directly, excludes this process, every ancestor, and any other
  `sharukhan` — and matches only `argv[0]`/`argv[1]`, the interpreter and the
  script, never the whole command line. Matching anywhere reports every shell
  that merely *mentions* `mc-run.sh` as running it; that was observed here while
  building this, when the shell that had just written a file of that name was
  counted as a build in flight.
- **Never trust an ISO without reading it.** The expected installer NEVR is
  derived from the variant patch's own `photon-os-installer.spec` hunk, never
  hardcoded. A hardcoded `2.9-2` rejected a good ISO after the spec moved to
  `2.9-3`, and the script could not be fixed in place because bash re-reads a
  running script mid-execution.
- **An ISO that has just been written cannot be opened.** Finding #29: the same
  3.9G image failed every power-on the second it landed on NTFS and opened in
  zero seconds eight minutes later. `run` refuses a too-fresh ISO rather than
  starting a VM that will fail for a reason nobody will connect to the build.
- **Serialise on a record, not on an idle poll.** Two drivers polling the same
  idle condition both wake when it clears and both start work. `run` chains on a
  `job` row it owns, and only then checks for foreign processes.
- **A background job outlives the shell that started it.** The `job` table is
  what makes it findable afterwards, and what makes a crashed driver
  distinguishable from a running one.
