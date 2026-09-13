# sharukhan

A single standalone CLI for verifying Photon OS ISOs and the PRs that go into
them, across the permutation matrix in `ISO-PERMUTATION-MATRIX.md`.

The matrix spans six axes — minimal/full ISO, installer 2.8 or latest, FIPS
crypto canister, with/without STIG, ext4/btrfs, and kickstart or the interactive
UI. Three of those are decided when the ISO is built (`iso_type`, `poi`,
`canister`); the rest are injected per VM. That is why 43 permutations need only
a handful of ISOs rather than one each.

Every command reports what it actually observed. Where a fact cannot be
established it says so rather than guessing — a harness that confidently
reports a wrong answer is worse than one that reports nothing.

## Status

`sharukhan` is now the only script. The `mission-control` bash harness has been
absorbed: `run` no longer shells out to `mc-run.sh` - it resolves the ISO,
generates the kickstart, creates the VM, installs, verifies and tears down in
this process, and every one of those steps is also a subcommand of its own
(`kickstart`, `create-vm`, `install`, `verify`, `teardown`, `build-iso`,
`variant-patches`, `card`, `doctor`).

The bash is archived, not deleted, at
[`../mission-control/superseded-bash/`](../mission-control/superseded-bash/README.md),
whose README says what replaced each script, what is NOT replaced, and which
behaviour deliberately changed (the SELinux oracle, `sshpass`, the WSL path
handed to `vmrun` in `mc-verify.sh`).

Two things to know before reading further:

* **`MC_GUEST_PASSWORD` is required and has no default.** It is the root
  password of every VM the harness installs. Anything that installs or
  configures a guest refuses without it.
* **Building an ISO is a policy flag.** `run` and `build-iso` still refuse by
  default - a build takes hours and shares `$PHOTON_TREE/stage` - but
  `--allow-build` makes it the operator's decision rather than a missing
  capability.

Everything below this line is captured output from BEFORE the absorption. The
gates, the job record and the evidence format are unchanged, but the command
lines quoted in the `run` / `stop` / `watch` sections still name
`mission-control/bin/*.sh` where today they name a `sharukhan` subcommand. It is
left as captured rather than rewritten, because the alternative is output nobody
ran.

## Build

```
cargo build --release
./target/release/sharukhan --help
```

Three dependencies (`rusqlite` with bundled SQLite, `serde`, `serde_json`).
No network access at runtime. `cargo test` runs the unit tests, which include the
check that `photon-matrix.vmx.template` and the VMX renderer have not diverged.

## Commands

### `doctor` — check the environment before anything is built or run

Run this first. It is cheap and it catches the things that otherwise waste an
hour: a missing `vmrun`, an empty ISO cache, a build stage with no headroom.

```
$ sharukhan doctor
environment
  [ok  ] photon tree            /root/5.0
  [ok  ] matrix                 /root/photonos-scripts/staging/mission-control/config/permutations.tsv
  [ok  ] MC_GUEST_PASSWORD      set in the environment
vmware tooling
  [ok  ] vmrun.exe              executable
  [ok  ] vmware-vdiskmanager.exe executable
  [ok  ] VMs already running    2 (this harness only ever touches its own)
capacity
  [ok  ] / (build stage)        84G free (94% used), needs 25G
  [ok  ] VM store               122G free (97% used), needs 20G
  [ok  ] iso-cache              /mnt/c/photon-mc/iso-cache
  [ok  ] results                /root/photon-mc/results
iso build tree
  [ok  ] photon tree HEAD       /root/5.0 (eb1cabdd4)
  [ok  ] poi-2.8 applies        35 files, against pristine origin/5.0
  [ok  ] poi-latest applies     35 files, against pristine origin/5.0
  [ok  ] canister-equivalent applies layers on poi-2.8.patch, kernel 6.12.109-4.ph5
external tools
  [ok  ] xorriso                /usr/bin/xorriso
  [ok  ] ssh                    /usr/bin/ssh
  [ok  ] ssh-keygen             /usr/bin/ssh-keygen
  [ok  ] git                    /usr/bin/git
inputs
  [ok  ] variant patches        /root/photon-mc/variant-patches
  [ok  ] iso cache              full-poi2.8-equivalent, full-poi2.8-prebuilt, full-poilatest-prebuilt, minimal-poi2.8-equivalent, minimal-poi2.8-prebuilt, minimal-poilatest-prebuilt
  [ok  ] lab keypair            /root/.ssh/photon-mc-rsa
memory
  [ok  ] database               64 finding(s)

all checks passed
```

The `iso build tree` checks test each variant patch against pristine
`origin/<release>` through a temporary index, so a tree that a build has left
patched does not read as a stale patch (finding #64).

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
  ID    ISO      POI     STIG  FS     MODE  VARIANT    CANISTER     NET                DOC
  k01   minimal  2.8     no    ext4   ks    none       prebuilt     -                  works
  k03   minimal  2.8     yes   ext4   ks    stigpkgs   prebuilt     -                  fails
  p01   minimal  2.8     no    ext4   ui    -          prebuilt     -                  works
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
64 finding(s)

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

`MEMORY.md` is a generated view of the same database and must never be edited
by hand. Until the planned `sharukhan db render` (Task 013) lands, regenerate it
with

```
python3 tools/gen-memory-md.py /root/photon-mc/memory.db MEMORY.md
```

### `report` — results of the last run of each permutation

```
$ sharukhan report --only k03,k04,s02,n05
  ID    ISO      POI     STIG  FS     DOC        RESULT   EVIDENCE                     FAILED CHECKS
  k03   minimal  2.8     yes   ext4   fails      19 pass  checks-20260913T134716Z.jsonl 
  k04   minimal  2.8     yes   btrfs  fails      19 pass  checks-20260913T135001Z.jsonl 
  s02   minimal  2.8     no    ext4   fails      17 pass  checks-20260913T135326Z.jsonl 
  n05   minimal  2.8     no    ext4   untested   1 FAIL   checks-20260913T140244Z.jsonl guest.ssh

4 of 4 permutation(s) have results; 1 with failing checks

written: /root/photon-mc/results/reports/report-20260913T201940Z.txt
```

Read that against `DOC`. k03, k04 and s02 were recorded as `fails` and now pass:
the STIG SELinux-relabel ordering fix, and photon-os-installer 2.8-7, which
restricts sshd to FIPS-approved algorithms so s02 is reachable under FIPS
crypto. n05 fails `guest.ssh` for an environmental reason, not a defect - see
*n05 fails for the environment's reason* below.

On 2026-09-13 every automated row ran against six ISOs built from the current
PRs: 25 of 26 pass, and n05 fails as documented. Earlier, four rows first
reported as failures turned out to be a wrong expectation in the oracle rather
than a defect: on subrelease 92 `selinux-policy` ships permissive by design, so
asserting `Enforcing` was incorrect. That is the failure mode this tool exists
to avoid, and it still got through - the guard against it is that every verdict
names the evidence file it came from, so the claim can be re-checked rather
than believed.

`EVIDENCE` names the exact result file each verdict came from. Result files are
timestamped and never overwritten, so a re-run cannot quietly replace the
evidence of the previous one.

Rows with no results say so rather than being omitted:

```
$ sharukhan report --only k09,k10
  k09   full     2.8     no    ext4   untested   not run  -                            -
  k10   full     2.8     no    btrfs  untested   not run  -                            -
```

### `run` — drive permutations end to end, sequentially

`run` decides what may proceed, serialises against anything already in flight,
proves the media, and records a job so the work is findable after the shell that
started it is gone. Then it drives each row in this process: it tears down
whatever an earlier run left of that row's VM, and runs
`kickstart -> create-vm -> install -> verify -> teardown --purge`. Rows run one
at a time, because ISO builds share `$PHOTON_TREE/stage` and the VM store cannot
hold two installs.

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
  ok      / 84G free, VM store 122G free

media
  ok      minimal/2.8/prebuilt     media has photon-os-installer-2.8-7.ph5.x86_64.rpm (expected photon-os-installer-2.8-7*), written 38135s ago

would run 3 row(s), sequentially:
  k03   minimal/2.8/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge
  k04   minimal/2.8/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge
  s02   minimal/2.8/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge

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

That capture predates 2026-09-02: c01 was `canister=build` then, so the refused
key reads `full/2.8/build`. It is `full/2.8/equivalent` now — `build` creates a
canister that no row installs, because `canister_build=1` forces
`canister_usage=0` and the kernel every row boots is `linux-esx`, which hardcodes
`canister_build 0`. See ISO-PERMUTATION-MATRIX.md §2b. The refusal behaviour
shown is unchanged.

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

**An ISO that is still settling is waited for, not refused.** VMware cannot open
an ISO written moments ago (finding #29: the same 3.9G image was unopenable the
second it landed and instant eight minutes later), so `run` waits until the ISO
is `--settle` seconds old (default 300). The wait is announced with the ISO's
measured age and the seconds left, so it is never a silent pause. It used to
refuse instead, and on 2026-09-13 that skipped a whole group when a campaign's
last build flowed straight into its run, while the report went on showing that
row's result from the day before (finding #61). An ISO that is still *growing*,
or cannot be read, is still refused.

A dry run changes nothing and does not block: it reports the wait a real run
would make and carries on. Forcing the check with an absurd `--settle`:

```
$ sharukhan run --dry-run --only k13 --settle 99999
selection: 1 row(s)
  1 row(s) can run autonomously

serialisation
  ok      no sharukhan job is running
  ok      no mc-run / mc-build-iso / runPh5 in flight

disk
  ok      / 84G free, VM store 122G free

media
  would wait full/latest/prebuilt  /mnt/c/photon-mc/iso-cache/full-poilatest-prebuilt/photon.iso was written 36225s ago; --settle 99999 needs 63774s more (finding #29)
  ok      full/latest/prebuilt     media has photon-os-installer-2.9-4.ph5.x86_64.rpm (expected photon-os-installer-2.9-4*), written 36225s ago

would run 1 row(s), sequentially:
  k13   full/latest/prebuilt     kickstart -> create-vm -> install -> verify -> teardown --purge

dry run: no job recorded, nothing executed
```

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
>
> **These captures also predate `run` absorbing `mc-run.sh` (2026-09-01).** A row
> no longer runs as a child `mc-run.sh`: it runs in this process as
> `kickstart -> create-vm -> install -> verify -> teardown --purge`, and the hint
> for a powered-on matrix VM now reads ``use `sharukhan teardown --id <id>` ``.
> They are kept for what they show about gating and job handling, not as a
> current transcript.

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
reports what is up and leaves `sharukhan teardown --id <id>` to the operator.

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

### One phase at a time

Every step `run` takes is also a command of its own, for one row:

| command | what it does |
| --- | --- |
| `kickstart --id <perm>` | prints the kickstart JSON the row would get |
| `create-vm --id <perm> [--iso <path>] [--kickstart <file>] [--recreate]` | thin boot disk, VMX and kickstart injection. `--recreate` stashes the VM directory's *contents* - never the directory, which VMware holds open - and refuses if a disk survives the stash (finding #62) |
| `install --id <perm> [--mode auto\|interactive] [--no-wait] [--timeout <sec>]` | powers on and waits for the guest to boot off disk; see *When an install is finished* |
| `verify --id <perm> [--ip <addr>]` | runs the oracle and harvests logs. Waits up to 120 s for sshd while nothing answers, and never retries an sshd that answered and refused (finding #63) |
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

## Build mode: sharukhan builds the ISO itself

`sharukhan build` runs the whole build cascade natively. It replaces five shell
scripts that were the same build with different accretions:

| was | now |
|---|---|
| `runPh4.sh` | `sharukhan build --release 4.0` |
| `runPh5_normal.sh` | `sharukhan build` |
| `runPh5_pinned90.sh` | `sharukhan build --subrelease 90` |
| `runPh5_pinned91.sh` | `sharukhan build --subrelease 91` |
| `runPh6.sh` | `sharukhan build --release 6.0` |

Their fixups had drifted - `run-in-chroot`'s fd-255 fix was in two of the five,
`createrepo_c` repair in two, `rpm 6.x` removal in three - and none of that was
a decision about the release: fd 255 breaks a 4.0 build exactly as it breaks a
5.0 one. So a phase here never asks *which release is this*, it asks *is the
thing I fix present in this tree*, and says so when it is not:

```
$ sharukhan build --dry-run
   1. resolve          9. inject:fixup[release]:openjdk-wsl2-build-flag
   2. sync            10. inject:fixup[release]:python3-pgo-test-generators
   3. reset-specs     11. inject:fixup[release]:sssd-serial-make-install
   4. inject:patch[release]:poi-2.8.patch
   5. inject:embedded[release]:canister-equivalent
   6. inject:embedded[common]:sans-snapshot-local-canister
   7. inject:pkg-build-options[equivalent-b]      13. sources
   8. inject:fixup[release]:spec-blank-lines      14. preflight
  12. inject:fixup[common]:run-in-chroot-fd-255   15. purge / 16. make / 17. post

  [skip] sssd-serial-make-install: already correct in this tree
```

`--dry-run` touches nothing. The scripts had no equivalent: the only way to
learn their order was to run one for hours.

### Two trees, and why that matters

Photon keeps per-release SPECS on `5.0`/`4.0`/`6.0` and shared build tooling on
`common`, and those branch lines never meet - `common` has no `SPECS/`, the
release branches have no `support/package-builder/`. The variant-patch
mechanism diffs `origin/<release>..branch` and applies to `SPECS`, so it can
**never** carry a change to the package builder. That is why the cascade
distinguishes `Tree::Release` from `Tree::Common` and can patch both.

### Test-only changes are compiled in

`canister_equivalent` and the sans-snapshot package-builder fix have no
destination in vmware/photon - upstream has no reason to carry a switch whose
only consumer is this harness - so they live in `src/embedded/`, are compiled
into the binary with `include_str!`, and are applied **on top of** the variant
patch. `VARIANTS` therefore carries only work genuinely bound upstream, and
nothing test-only can leak into a PR.

The practical effect: a fresh clone of this repository can build an
equivalent-canister ISO with no other repository checked out at any particular
revision.

### The canister question, in the order it is asked

| state | plan | validated? |
|---|---|---|
| Broadcom publishes one at this kernel level | link it | **yes**, CMVP |
| not published, but already built locally | link that, no phase A | no |
| neither | build it (phase A), then relink both flavours (phase B) | no |

Only the third costs the extra ~90 minutes. `sharukhan canister` reports the
same decision the build will take - it asks the same question, so the two
cannot disagree.

Two further answers are possible. If the published repository cannot be reached
the answer is `unknown`, not `equivalent`: "build one locally" and "we could not
look" are different claims. On aarch64 it is `absent` by design, because both
kernel specs set `fips 0` there. The published lookup reads the repository URL
from `SPECS/photon-repos/photon-updates.repo`.

### One build, not two

`build-iso` resolves a matrix tuple to an ISO; `build` runs the cascade
directly. They used to be two implementations of the same build, and they
drifted - the visible half being the phase-B purge, which the cascade taught
about per-flavour NEVRs while the legacy path kept a rule keyed only on the
canister's. Anything through `build-iso`, or `run --allow-build`, could still
ship a `linux-esx` that never linked the canister, on the flavour these rows
boot.

Sharing the predicate would not have fixed it:

- **Ordering.** The cascade purges AFTER the injections, against patched specs.
  At the equivalent point in the script path the tree is still pristine, where
  both flavours read `Release: 1`, so a per-flavour purge there matches nothing.
- **The embedded patch.** `fix/canister-equivalent-mode` is test-only, compiled
  into `src/embedded/` and applied as an injection, so only the cascade applies
  it - while `resolve` called `equivalent_kernel_nevr`, which *reads* it, to
  pick the NEVR. The legacy path expected `linux` at Release 4, would have
  built Release 3, and purged on a NEVR its own build could not produce.

So `equivalent` runs the cascade. `prebuilt` still runs `runPh5_normal.sh`: it
applies no embedded patch and needs no inter-phase purge, so it has nothing to
drift on. The delete rule lives once in `build::doomed_before_phase_b`, and the
spec assembly once in `buildmode::spec_for`.

### The embedded patch pins Release numbers, and 5.0 moves

`src/embedded/canister-equivalent.patch` bumps the kernel Release on top of the
variant patch, so it carries the pre-bump number as diff context. Every time
5.0 bumps a kernel Release, that context stops matching and the patch fails to
apply — the build dies at the inject stage.

This is not rare: in five days in September 5.0 took `linux` from Release 1 to
4 to 8, and the patch needed retargeting three times. As of 2026-09-13
(6.12.109) the chain is:

```
                  linux   linux-esx
pristine 5.0        1         1
variant patch       3         2      PR#24 bumps both, PR#29 bumps linux
embedded patch      4         3      +1 each
```

**Regenerate it, never hand-edit it.** `tools/regen-canister-equivalent.py`
applies the variant patch to a pristine worktree, makes the embedded edits,
derives the kernel version, runs the spec checker over the result and writes the
patch; `--check` only reports whether the committed patch is current. The patch
is compiled in, so rebuild the binary afterwards. `sharukhan doctor` reports
`canister-equivalent applies` on every run, so a moved kernel is caught before a
build rather than seconds into one. Hand-editing hunk offsets is how an earlier
attempt produced an orphan changelog entry and a descending-order violation that
`rpmspec` rejected.

### `--compose-only`

Rebuilding an image must not cost a kernel rebuild. The kernels in the stage
are already linked against the canister and verified, and `purge` would delete
them for the sake of a recompose. `--compose-only` keeps them - but the skip is
earned, not asserted: every `linux*` RPM must be shown to POSTDATE the canister
(phase A builds the canister as a subpackage of the kernel, so a phase-A kernel
shares its BUILDTIME), and the build is refused on any path that cannot be
proven.

It is not a uniform saving. A minimal recompose took **9m38s** against ~2h45m;
a full one took **154m**, because the full package set is 264 packages against
the minimal's 141 and most of the difference had never been built. What is
saved is the kernel rebuild, not the package set.

## `helper-scripts/` — the run wrappers

Five scripts that drive `sharukhan` through a specific multi-hour sequence.
They are **not** part of the harness: nothing in `src/` calls them, and every
one of them shells out to the built binary. They are kept because each records
*why* a particular run was shaped the way it was, and that reasoning is not
recoverable from the CLI.

| script | what it drives |
|---|---|
| `rebuild-both.sh` | Rebuilds **both** minimal ISOs (2.8 and latest) and runs every unattended row they serve. Both variants, because the isoBuilder change rides POI patch 0008, which is carried by the 2.8 *and* the latest installer branch — testing one would leave the other unproven with the same change in it. |
| `activate-coverage-plan.sh` | Pass 2 of the two-pass protocol: throw the local state away, take everything back from the fork, rebuild, run every unattended row. Waits for `rebuild-both.sh` and refuses if that run never reached `=== done ===`. |
| `pass2.sh` | Pass 2, second attempt. Its header is the most useful thing in this directory — it dissects how the first attempt reported *"pass 2 complete"* having run zero rows, from three compounding faults. |
| `full-rows.sh` | The full-ISO half of the matrix plus the canister row, after the variant patch moved under all of them. |
| `canister-equivalent.sh` | First real exercise of the equivalent-canister path, on minimal/2.8 rather than full — the mechanism is identical either way and a minimal ISO costs ~30 minutes against hours. Asserts four things rather than assuming them: phase A produced the canister, the purge kept it and removed the canister-*creating* kernel, phase B rebuilt **both** flavours against it, and the ISO carries a `linux-esx` built after the canister. |

### The two-pass protocol

`activate-coverage-plan.sh` and `pass2.sh` exist for a distinction worth
stating plainly:

```
pass 1   change it locally, test it locally, push it to the fork PR
pass 2   THROW THE LOCAL STATE AWAY, take everything back from the fork,
         rebuild, and run every unattended row
```

Pass 1 proves the change is right. Pass 2 proves *the change that is published*
is the one that was proven — a different claim, and the one that matters before
opening a PR against `vmware/photon`. A local working tree can make a test pass
for reasons the fork does not carry.

### They need `MC_GUEST_PASSWORD` in the environment

Each script opens with

```bash
: "${MC_GUEST_PASSWORD:?not set ...}"
```

and exits immediately if it is unset. It is the root password of every VM the
harness creates, so it has no default and is deliberately **not** stored in
this repository — these scripts previously carried it as a literal, which is
exactly what a public repository must not hold. Export it before running.

### Paths are absolute and host-specific

They hardcode `/root/photonos-scripts/...`, `/root/photon-mc/...` and
`/root/5.0`. They are a record of how this host was driven, not a portable
tool. Read them before running one anywhere else.

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
| `POI_TREE` | `/root/photon-os-installer` |
| `PHOTON_SCRIPTS` | `/root` |
| `SHARUKHAN_ROOT` | `/root/photonos-scripts/staging/mission-control` |
| `SHARUKHAN_MATRIX` | `$SHARUKHAN_ROOT/config/permutations.tsv` |
| `SHARUKHAN_DB` | `/root/photon-mc/memory.db` |
| `MC_RESULTS_DIR` | `/root/photon-mc/results` |
| `MC_BUILD_LOG_DIR` | `/root/photon-mc/build-logs` |
| `MC_RUN_LOG_DIR` | `/root/photon-mc/run-logs` |
| `MC_WORK` | `/root/photon-mc/work` |
| `MC_VARIANT_PATCH_DIR` | `/root/photon-mc/variant-patches` |
| `MC_ISO_CACHE` | `/mnt/c/photon-mc/iso-cache` |
| `MC_VM_ROOT_WSL` | `/mnt/c/photon-mc/vm` |
| `MC_DHCP_LEASES` | `/mnt/c/ProgramData/VMware/vmnetdhcp.leases` |
| `VMRUN` | `/mnt/c/Program Files/VMware/VMware Workstation/vmrun.exe` |
| `VDISKMANAGER` | `/mnt/c/Program Files/VMware/VMware Workstation/vmware-vdiskmanager.exe` |
| `MC_BUILD_ROOT` | `/root` |
| `MC_BUILD_COMMON` | `common` |
| `MC_RELEASE` | `5.0` |
| `MC_PHOTON_REMOTE` | `https://github.com/dcasota/photon.git` |
| `GUEST_VCPUS` | `2` |
| `GUEST_MEM_MB` | `4096` |
| `BOOT_DISK_SIZE` | `32GB` |
| `BOOT_DISK_ADAPTER` | `lsilogic` |
| `BOOT_DISK_TYPE` | `0` |
| `MC_NET_PREFIX` | `192.168.225` |
| `MC_NET_GATEWAY` | `<MC_NET_PREFIX>.2` |
| `MC_NET_DNS` | `<MC_NET_PREFIX>.2` |
| `MC_NET_CIDR` | `24` |
| `MC_NET_V6_PREFIX` | `fd00:225` (a ULA — see the network axis below) |
| `MC_NET_VLAN_PREFIX` | `192.168.100` |
| `MC_IP_BASE` | `40` |
| `MC_NIC_DEV` | `e1000` |
| `SSH_KEY_DIR` | `$HOME/.ssh` |
| `SSH_KEY_NAME` | `photon-mc-rsa` |
| `SSH_USER` | `root` |
| `MC_GUEST_PASSWORD` | **required, no default** — the root password of every VM the harness installs |
| `SERIAL_LOG_PREFIX` | `serial0` |
| `MC_INSTALL_TIMEOUT_SEC` | `2400` |
| `MC_BOOT_TIMEOUT_SEC` | `600` |
| `MC_SSH_TIMEOUT_SEC` | `300` |
| `MC_SAMPLE_SEC` | `25` |
| `MC_START_TIMEOUT` | `240` |

```
SHARUKHAN_DB=/tmp/other.db sharukhan findings
```

## The network axis

`permutations.tsv` carries an eleventh column, `net`, holding all three network
dimensions in one token:

```
net = <family>-<assignment>-<vlan>
      family      v4 | v6 | dual
      assignment  dhcp | static
      vlan        untag | vlanNNN     (NNN in 1..4094)
```

An absent column, or `-`, means `v4-dhcp-untag` — which is exactly what every
row did before the axis existed, so the column documents the status quo rather
than changing it. `kickstart::tests::the_default_net_token_reproduces_the_legacy_dhcp_kickstart_byte_for_byte`
is the guard for that.

**It is an install-time axis and costs no ISO builds.** The network config
reaches the guest through `guestinfo.kickstart.data` and is applied by POI's
`_setup_network()` against an already-installed root; it never touches the
media, the package set or the installer. `Permutation::iso_key()` deliberately
excludes it, and a test asserts that.

**An unknown token fails `matrix::load`, naming the row.** This is not
fastidiousness: `installer.py` validates only the *top-level* keys of a
kickstart, so a misspelt key inside `network` is silently ignored by POI and
produces a guest with no address and no error message anywhere. The harness is
the only place that typo can ever be caught.

Which POI schema a row exercises follows from its token, and the split is not
arbitrary — `Legacy` is exactly the set the curses configurator can produce:

| token | schema | what it exercises |
| --- | --- | --- |
| `v4-dhcp-untag` | legacy `type: dhcp` | the pre-axis default, all rows outside the n-block |
| `v4-static-untag` | legacy `type: static` | n01 |
| `v4-dhcp-vlanNNN` | legacy `type: vlan` | n05 |
| `v4-static-vlanNNN` | v2 `vlans` | n04 |
| `dual-static-untag` | v2, two families in one `addresses` list | n02 |
| `v6-static-untag` | v2, plus a second NIC | n03 |

All five generated configs were verified by running them through POI's own
`networkmanager.py` offline (`networkmanager.py -D <dir> -f <config>`) and
reading the systemd-networkd files it produced.

### What this host cannot test, and why

These are findings about the host, not about POI, and they are why the block is
five rows rather than twelve.

**IPv6 has three independent blockers, any one sufficient:**

1. `/mnt/c/ProgramData/VMware/vmnetnat.conf` has `natIp6Enable = 0`. The vmnet8
   NAT device emits no router advertisement and offers no IPv6 gateway.
2. **No DHCPv6 server exists on this host in any configuration.**
   `VMnetDHCP.exe` is a VMware port of ISC 2.0 and is IPv4-only;
   `vmnetdhcp.conf` declares only `subnet 192.168.58.0` and
   `subnet 192.168.225.0`. Setting `natIp6Enable = 1` would not create one.
3. **WSL2 runs in NAT networking mode and has no IPv6 stack at all.**
   `.wslconfig` has `networkingMode = Nat`; `/proc/net/if_inet6` holds only
   link-local addresses and `ping -6` answers "Network is unreachable". The
   harness itself cannot reach any guest over IPv6, whatever the hypervisor
   does. Changing this needs `networkingMode = mirrored` and a full WSL
   restart — a global host change.

So DHCPv6 and SLAAC rows are **unrunnable here** and are recorded as such by
`NetSpec::unrunnable_reason` rather than written out and failed. Static IPv6
needs no router, no server and no peer, so it *is* testable: the address is
assigned, DAD completes, and the guest can be asked what it has over an IPv4
path. That is what n02 and n03 do. They could be extended to real IPv6
reachability on a host with an IPv6 router — an ESXi portgroup, or KVM with
`radvd`/`dnsmasq --enable-ra`.

**VLAN has one blocker:**

4. **VMware Workstation 17 has no VLAN backing of any kind.**
   `ethernet0.vlanID` is a vSphere *portgroup* property; `strings` over
   `x64/vmware-vmx.exe`, `vmnetBridge.dll` and `vnetlib.dll` finds no
   VLAN/trunk symbol at all, and the Virtual Network Editor has no VLAN
   concept. Tagging can therefore only happen inside the guest — which is
   exactly what POI's `vlans` config does — and nothing on vmnet8 will answer a
   tagged frame, because the NAT gateway and `VMnetDHCP.exe` are both bound to
   the untagged segment. Bridged mode is no escape: the only uplink is Wi-Fi
   (Intel AX211), and 802.1Q over a bridged wireless adapter does not work.
   There is no wired NIC on this host.

So a VLAN row proves what the installer **configured**, never that tagged
traffic flows, and the oracle asserts accordingly.

### n05 fails for the environment's reason, not POI's

`n05` carries `expect = fails`. That failure is **environmental** — blocker 4
means no switch here will ever answer its tagged DHCP, and no change to Photon
or to the installer would make it pass. This is the opposite of `s02`, which is
a real defect somebody should fix. Do not conflate them.

What n05 *does* prove is that the legacy `type: vlan` conversion ran and wrote
the right files. Its `systemd-networkd-wait-online` failure is asserted
**positively** (`net.wait_online`) and excluded from `guest.failed_units`, so it
is recorded rather than hidden — and so it cannot regress an assertion that has
nothing to do with it.

There is a genuine POI gap underneath: `networkmanager.py` writes only
`[Match]`, `[Network]`, `[NetDev]` and `[VLAN]` sections, so `RequiredForOnline=`
is unreachable from the kickstart schema and an operator who *knows* a link
cannot come up has no way to say so. Written up in
`/root/photon-mc/poi-gap-requiredforonline.md` for filing upstream.

### n03 needs a second NIC, and that now works

An IPv6-only guest is unreachable from this harness (blocker 3), so `n03`'s VMX
carries a second NIC on the same NAT segment doing plain DHCPv4, purely so ssh
has a path in. This was recorded as unproven for a long time — no VM on this
host had ever had two NICs.

**It is proven now.** n03 powers on, installs, and passes 39 checks with 0
failures, with `net.v6_addr fd00:225::4f/64` and DAD complete. The second NIC
also turned out to matter to the install detector, not just to ssh: the guest
takes its DHCPv4 lease on that MANAGEMENT interface, so the lease signal has to
match every MAC the row owns. See *When an install is finished* below — getting
that wrong cost n03 a false `install.booted_from_disk` failure on 2026-09-09.

### When an install is finished, and how that is known

The hardest question this harness asks is *has the install completed*. There
are four signals, and no single one of them is reliable on this host:

| | signal | fires for | why it is not enough alone |
|---|---|---|---|
| a | `root=PARTUUID=` in the serial log | rows whose installed system has a serial console | the installed cmdline carries no `console=ttyS0`, so the log stays 0 bytes and this **never fires here** |
| b | `vmrun getGuestIPAddress` | any row with open-vm-tools | latency is wild: 11 minutes on one c03 run, longer than the whole 2400s timeout on the next |
| c | the host's DHCP lease file, matched on **every NIC the row owns** | any row where some interface takes a lease | a row whose every interface is statically addressed takes none |
| d | SSH on the row's reserved address | static rows | a DHCP row never configures that address |

Together (c) and (d) cover every runnable row.

**(c) must match on every NIC, not just the first.** n03 (`v6-static-untag`)
failed `install.booted_from_disk` on an install that had plainly succeeded: the
guest held `fd00:225::4f/64` with DAD complete and answered 18 checks, and it
had been up since 44 seconds in. Its lease was in the file the whole time,
under the row's own hostname - but carried `00:50:56:3b:00:27` while the lookup
matched `00:50:56:3a:00:27`. That is `mac2` against `mac`: n03 carries a second
NIC and leases on the MANAGEMENT interface, so a filter on the primary MAC
could never match it. Blind by construction, not by timing - waiting longer
would never have helped.

That row is also why (d) cannot cover it: its static address is IPv6 while the
reserved address this harness probes is IPv4, so the SSH probe stays silent.
With (c) matching both NICs, n03 is covered.

**(c) distinguishes the boot source by hostname.** The installer live
environment and the installed system share a MAC, so a lease alone proves
nothing:

```
09:13:54  192.168.225.186  host=photon-installer   <- live installer
09:15:26  192.168.225.192  host=mc-c03             <- installed system
```

Every lookup is bounded below by a timestamp taken before the guest can lease
anything. Leases from PREVIOUS runs of the same row persist under the same MAC
and hostname, so matching on those alone would report an install finished
before the guest powered on - a false pass, and far worse than the false
timeout it replaces.

**(d) checks the SSH banner, not the connection.** The reserved address sits
below the DHCP floor so the pool never hands it out, and the installer live
environment takes a pool lease instead - so nothing answers there until the
installed system has configured its own network. Accepting a bare TCP
handshake as proof of boot is how a detector starts lying again.

The quiet-log line reports all four, because six identical `serial log quiet`
lines over 40 minutes tell a reader nothing about which signal is failing:

```
still waiting: serial size=0, tools ip=none, ssh at 192.168.225.79 silent,
               last lease photon-installer@2026/09/04 16:17:48 192.168.225.155
```

That line is what found (d): every quiet report on the static rows named
`photon-installer` as the last lease, which is the signal saying it cannot see
this row.

## Things learned the hard way

These are encoded in the code, with the reasoning in comments, because each one
cost real time:

- **`permutations.tsv` is whitespace-aligned, not tab-separated.** Splitting on
  `\t` yields zero rows and looks like an empty matrix rather than an error.
- **`vmrun` output is CRLF-terminated.** It is a Windows binary; not stripping
  `\r` makes every comparison fail while the output looks correct.
- **`vmx::placeholders` scans for `@@[A-Z_]+@@`, so a digit ends the token.**
  `@@ETHERNET1@@` substitutes correctly and is then invisible to the contract
  test that keeps the template and the renderer in step. The management NIC's
  placeholder is `@@MGMT_NIC@@` for that reason.
- **New matrix rows must be APPENDED, never inserted.** `identity.rs` derives
  each VM's MAC, UUID and IP from the row *ordinal*, so inserting a row silently
  re-addresses every VM below it.
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
  zero seconds eight minutes later. `run` waits out a too-fresh ISO, announcing
  the wait, rather than starting a VM that will fail for a reason nobody will
  connect to the build. It refused at first, which skipped a whole group of
  rows (finding #61).
- **Serialise on a record, not on an idle poll.** Two drivers polling the same
  idle condition both wake when it clears and both start work. `run` chains on a
  `job` row it owns, and only then checks for foreign processes.
- **A background job outlives the shell that started it.** The `job` table is
  what makes it findable afterwards, and what makes a crashed driver
  distinguishable from a running one.
- **A failed rename is a finding, not a skipped line.** Stashing moved files with
  `rename(...).is_ok()`. When VMware still held a disk open the rename failed
  silently, the disk stayed, and a row "installed" in 18 seconds and passed on an
  installation from the day before (finding #62). Stash failures are logged by
  name, every row tears its VM down first, and `create --recreate` refuses a disk
  that survives.
- **A DHCP lease is not sshd.** The install signal is a lease under the guest's
  own hostname, which comes before sshd listens. One SSH attempt 12 seconds later
  scored a false FAIL on the heaviest row (finding #63). `verify` now retries
  while nothing answers, and never retries an sshd that answered and refused.
- **Check a patch against what a build applies it to.** A build leaves `SPECS`
  patched, so checking a variant patch in the tree reported it stale after every
  build (finding #64). `doctor` reads `origin/<release>` into a temporary index.
- **A temporary name must be unique per call, not per process.** Every thread of
  one process shares a pid, and parallel tests collided on one index file until
  the name carried a counter.
