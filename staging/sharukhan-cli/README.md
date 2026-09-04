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
| `MC_NET_PREFIX` | `192.168.225` |
| `MC_NET_CIDR` | `24` |
| `MC_NET_V6_PREFIX` | `fd00:225` (a ULA — see the network axis below) |
| `MC_NET_VLAN_PREFIX` | `192.168.100` |

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

### n03 needs a second NIC, and that is unproven here

An IPv6-only guest is unreachable from this harness (blocker 3), so `n03`'s VMX
carries a second NIC on the same NAT segment doing plain DHCPv4, purely so ssh
has a path in. **No VM on this host has ever had two NICs.** If `n03` refuses to
power on, treat it as unrunnable here on the `c02` precedent — `install.rs`
says exactly that in the failure text — rather than as a POI defect.

### When an install is finished, and how that is known

The hardest question this harness asks is *has the install completed*. There
are four signals, and no single one of them is reliable on this host:

| | signal | fires for | why it is not enough alone |
|---|---|---|---|
| a | `root=PARTUUID=` in the serial log | rows whose installed system has a serial console | the installed cmdline carries no `console=ttyS0`, so the log stays 0 bytes and this **never fires here** |
| b | `vmrun getGuestIPAddress` | any row with open-vm-tools | latency is wild: 11 minutes on one c03 run, longer than the whole 2400s timeout on the next |
| c | the host's DHCP lease file | DHCP rows | a statically addressed guest takes no lease |
| d | SSH on the row's reserved address | static rows | a DHCP row never configures that address |

Together (c) and (d) cover every runnable row; (b) remains the only signal for
`v6-static-untag`, whose static address is IPv6 while the reserved address is
IPv4.

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
  zero seconds eight minutes later. `run` refuses a too-fresh ISO rather than
  starting a VM that will fail for a reason nobody will connect to the build.
- **Serialise on a record, not on an idle poll.** Two drivers polling the same
  idle condition both wake when it clears and both start work. `run` chains on a
  `job` row it owns, and only then checks for foreign processes.
- **A background job outlives the shell that started it.** The `job` table is
  what makes it findable afterwards, and what makes a crashed driver
  distinguishable from a running one.
