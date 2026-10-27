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

## Contents

- [Status: one CLI, the bash harness archived](#status-one-cli-the-bash-harness-archived)
- [Build](#build)
- [Installing the host services: `sharukhan service`](#installing-the-host-services-sharukhan-service)
  - [What gets installed](#what-gets-installed)
  - [Install or update](#install-or-update)
  - [Check: `service status`](#check-service-status)
  - [Remove: `service remove`](#remove-service-remove)
  - [Commands run by hand use the same settings](#commands-run-by-hand-use-the-same-settings)
  - [When the timed sync is needed, and when not](#when-the-timed-sync-is-needed-and-when-not)
- [Typical session](#typical-session)
  - [A gate run by hand](#a-gate-run-by-hand)
  - [A day with the automation](#a-day-with-the-automation)
- [Running the permutation matrix: commands](#running-the-permutation-matrix-commands)
  - [`doctor` — check the environment before anything is built or run](#doctor--check-the-environment-before-anything-is-built-or-run)
  - [`plan` — what would run, and what has to be built first](#plan--what-would-run-and-what-has-to-be-built-first)
  - [`status` — VMs, disk, and how much parallelism that allows](#status--vms-disk-and-how-much-parallelism-that-allows)
  - [`findings` — what previous runs established](#findings--what-previous-runs-established)
  - [`report` — results of the last run of each permutation](#report--results-of-the-last-run-of-each-permutation)
  - [`run` — drive permutations end to end, sequentially](#run--drive-permutations-end-to-end-sequentially)
  - [`stop` — end a job and its process tree](#stop--end-a-job-and-its-process-tree)
  - [`watch` — what is running, and follow it](#watch--what-is-running-and-follow-it)
  - [The state the job table exists to survive](#the-state-the-job-table-exists-to-survive)
  - [One phase at a time](#one-phase-at-a-time)
- [Package lifecycle: install, test and remove every package of a row](#package-lifecycle-install-test-and-remove-every-package-of-a-row)
- [Build mode: sharukhan builds the ISO itself](#build-mode-sharukhan-builds-the-iso-itself)
  - [Two trees, and why that matters](#two-trees-and-why-that-matters)
  - [The common tree must hold only the build's own edits](#the-common-tree-must-hold-only-the-builds-own-edits)
  - [Test-only changes are compiled in](#test-only-changes-are-compiled-in)
  - [The canister question, in the order it is asked](#the-canister-question-in-the-order-it-is-asked)
  - [One build, not two](#one-build-not-two)
  - [The embedded patch pins Release numbers, and 5.0 moves](#the-embedded-patch-pins-release-numbers-and-50-moves)
  - [`--compose-only`](#--compose-only)
  - [The installer that composes the media is the variant's: `composer`](#the-installer-that-composes-the-media-is-the-variants-composer)
  - [How a medium boots: `iso-boot`](#how-a-medium-boots-iso-boot)
- [Remaster mode: an Azure variant of an ISO that already exists](#remaster-mode-an-azure-variant-of-an-iso-that-already-exists)
  - [Why remaster rather than build](#why-remaster-rather-than-build)
  - [The dependency closure is computed, not listed](#the-dependency-closure-is-computed-not-listed)
  - [The toolchain comes off the input ISO](#the-toolchain-comes-off-the-input-iso)
  - [The accelerator is gated on byte identity](#the-accelerator-is-gated-on-byte-identity)
  - [What verify reads back off the finished ISO](#what-verify-reads-back-off-the-finished-iso)
  - [The replacement set is derived](#the-replacement-set-is-derived)
  - [A config change must change the NEVR](#a-config-change-must-change-the-nevr)
- [Kernel wrappers: `sharukhan wrapper`](#kernel-wrappers-sharukhan-wrapper)
  - [A FIPS canister series for a profile kernel](#a-fips-canister-series-for-a-profile-kernel)
- [Kernel-profile builds and runs: `--kernel`](#kernel-profile-builds-and-runs---kernel)
  - [Linux 7.3-rc4 (2026-09-29)](#linux-73-rc4-2026-09-29)
- [Real-world example: a full ISO with kernel 7.3, the latest installer and the equivalent canister](#real-world-example-a-full-iso-with-kernel-73-the-latest-installer-and-the-equivalent-canister)
  - [The goal and the result](#the-goal-and-the-result)
  - [Step 1: which 7.3, verified](#step-1-which-73-verified)
  - [Step 2: the release branch on today's 5.0](#step-2-the-release-branch-on-todays-50)
  - [Step 3: the profile and the derived wrapper](#step-3-the-profile-and-the-derived-wrapper)
  - [Step 4: prove every patch before building](#step-4-prove-every-patch-before-building)
  - [Step 5: variant patches with every PR](#step-5-variant-patches-with-every-pr)
  - [Step 6: build the ISO](#step-6-build-the-iso)
  - [Step 7: install and verify](#step-7-install-and-verify)
  - [Culprits and how each was solved](#culprits-and-how-each-was-solved)
  - [Timings](#timings)
- [Keeping the fork's PRs current: `sharukhan sync`](#keeping-the-forks-prs-current-sharukhan-sync)
  - [The stages](#the-stages)
  - [Starting, following and resuming a run](#starting-following-and-resuming-a-run)
  - [When a PR needs a decision](#when-a-pr-needs-a-decision)
  - [Descriptions](#descriptions)
  - [Upstream PRs: shared branches, staged first](#upstream-prs-shared-branches-staged-first)
  - [The timer: `sync auto`](#the-timer-sync-auto)
  - [Other sync commands](#other-sync-commands)
- [The escalation: `sharukhan escalate` and `sharukhan mcp`](#the-escalation-sharukhan-escalate-and-sharukhan-mcp)
  - [Before the first escalation: `escalate preflight`](#before-the-first-escalation-escalate-preflight)
  - [One escalation, the queue, the ledger](#one-escalation-the-queue-the-ledger)
  - [Taking a verified proposal](#taking-a-verified-proposal)
  - [Budgets and price weights](#budgets-and-price-weights)
  - [How the model is confined](#how-the-model-is-confined)
  - [The MCP server: `sharukhan mcp`](#the-mcp-server-sharukhan-mcp)
- [The upstream watcher and its events](#the-upstream-watcher-and-its-events)
- [Data files the automation reads](#data-files-the-automation-reads)
  - [`config/variants.conf`: installer variants and the common branches](#configvariantsconf-installer-variants-and-the-common-branches)
  - [`config/check-prs.tsv`: which PR a check proves](#configcheck-prstsv-which-pr-a-check-proves)
  - [`memory.db` and `MEMORY.md`](#memorydb-and-memorymd)
  - [The embedded canister-equivalent patch](#the-embedded-canister-equivalent-patch)
- [`helper-scripts/` — the run wrappers](#helper-scripts--the-run-wrappers)
  - [The two-pass protocol](#the-two-pass-protocol)
  - [They need `MC_GUEST_PASSWORD` in the environment](#they-need-mc_guest_password-in-the-environment)
  - [Paths are absolute and host-specific](#paths-are-absolute-and-host-specific)
- [Configuration](#configuration)
  - [Paths, the VM and the network](#paths-the-vm-and-the-network)
  - [The settings file and the secret files](#the-settings-file-and-the-secret-files)
  - [Settings of the build, the fork and the sync](#settings-of-the-build-the-fork-and-the-sync)
- [The network axis](#the-network-axis)
  - [What this host cannot test, and why](#what-this-host-cannot-test-and-why)
  - [n05 fails for the environment's reason, not POI's](#n05-fails-for-the-environments-reason-not-pois)
  - [n03 needs a second NIC, and that now works](#n03-needs-a-second-nic-and-that-now-works)
  - [When an install is finished, and how that is known](#when-an-install-is-finished-and-how-that-is-known)
- [Troubleshooting](#troubleshooting)
  - [Every ISO group is refused at once](#every-iso-group-is-refused-at-once)
  - [The disk fills during a build](#the-disk-fills-during-a-build)
  - [`stop` and containers](#stop-and-containers)
  - [A manual gate after a stopped or failed build](#a-manual-gate-after-a-stopped-or-failed-build)
  - [Following a job](#following-a-job)
- [Things learned the hard way](#things-learned-the-hard-way)

## Status: one CLI, the bash harness archived

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

## Installing the host services: `sharukhan service`

The watcher, the timed sync and the builder's shared mount run as systemd
units. `sharukhan service` writes them from templates compiled into the
binary, so they are versioned with the code instead of being edited by hand.

### What gets installed

| Path | What it is |
|---|---|
| `/usr/local/libexec/sharukhan/sharukhan` | the binary the units and every job run (installed atomically) |
| `/etc/sharukhan/sharukhan.env` | the services' settings, `KEY="value"` lines; nothing secret |
| `/etc/sharukhan/secrets/anthropic-api-key` | the escalation's API key, mode 0600 (only with `--escalation-key-from-env`) |
| `/etc/sharukhan/secrets/guest-password` | the guest root password, mode 0600 (only with `--guest-password-from-env`) |
| `/etc/systemd/system/sharukhan-watch.service` | the upstream watcher (`sharukhan watch --interval <s>`) |
| `/etc/systemd/system/sharukhan-sync.service` + `.timer` | `sharukhan sync auto` on a timer (only with `--sync`) |
| `/etc/systemd/system/photon-mc-gate-shared.service` + `/usr/local/sbin/photon-mc-gate-shared` | the shared bind mount the builder container needs (only with `MC_BUILDER=container`) |

The settings file names the secret files (`MC_ANTHROPIC_KEY_FILE`,
`MC_GUEST_PASSWORD_FILE`); the values themselves are never written to a unit,
the settings file, an argv or the output.

### Install or update

Run it in the host mount namespace, from a shell that has the settings you
want the services to carry:

```bash
. /root/photon-mc/gate/env-isolated.sh            # the gate settings
export HOME=/root MC_NOTIFY=file:/root/photon-mc/events.log
nsenter --target 1 --mount -- \
  sharukhan service install --sync --guest-password-from-env --escalation-key-from-env
```

* Every setting sharukhan knows that is set in the environment goes into the
  settings file; settings already in the file and not in the environment are
  kept. `--unset KEY` removes one.
* `--escalation-key-from-env` takes `ANTHROPIC_API_KEY`, checks its shape and
  that the API accepts it, then writes the key file.
* `--guest-password-from-env` takes `MC_GUEST_PASSWORD`. `--sync` refuses
  without a guest password file: a sync reaches GATE, which installs VMs.
* `--watch-interval S`, `--sync-every SPAN` (e.g. `30min`, `1h`) and
  `--sync-quiet S` set the service options.
* It refuses while a sync run, a job or an escalation is running: those
  processes run the installed binary.
* Running it again changes only what differs and says what.

```bash
sharukhan service install --dry-run                 # what would change
sharukhan service install --root /tmp/svc-review    # render into a directory, systemd untouched
```

### Check: `service status`

```bash
sharukhan service status
```

It renders what `install` would write from the settings file on disk and
compares: every file is `current`, `missing` or `differs` (with the lines),
each secret file is checked for owner and mode, and the installed binary is
compared with the one running. It exits non-zero on drift; `sharukhan doctor`
reports the same as its "service files" item.

### Remove: `service remove`

```bash
sharukhan service remove --sync          # only the sync service and timer
sharukhan service remove                 # every unit and the settings file
sharukhan service remove --key --guest-password   # ...and those secret files
```

A secret file goes only when named. The binary stays.

### Commands run by hand use the same settings

`/root/photon-mc/gate/env-isolated.sh` loads `/etc/sharukhan/sharukhan.env`
(after `env.sh`, which only provides the guest password for bash scripts that
check `MC_GUEST_PASSWORD` themselves), so a gate run by hand and a sync started
by systemd see the same paths. Change a setting with `service install`, not by
editing a script.

### When the timed sync is needed, and when not

* **Needed** when the fork's PRs should follow the fork's release and `common`
  branches without anyone starting it: the timer checks every
  `SHARUKHAN_SYNC_EVERY` and starts a run once a base moved and stayed quiet
  for `SHARUKHAN_SYNC_QUIET` seconds.
* **Not needed** while you drive a sync by hand (only one run exists at a
  time), and it waits by itself while a gate or build job is running.
* **The watcher** only reads and records; it should always run.

## Typical session

### A gate run by hand

```
sharukhan doctor                     # is the machine fit to run anything
sharukhan plan --only k01,k02        # what will run, is the ISO cached
sharukhan status                     # room to run it, and how many at once
sharukhan run --dry-run --only k01,k02   # every gate, for real, executing nothing
nohup sharukhan run --only k01,k02 &     # prints a job id
sharukhan watch --job 1              # follow it (the run log, until the job ends)
sharukhan stop --job 1               # if it has to end early
sharukhan report --only k01,k02      # what happened, against the documented verdict
sharukhan findings                   # what previous runs established
```

### A day with the automation

```
sharukhan service status             # services, settings and secret files as installed
sharukhan events --new               # what moved upstream, what waits for a person
sharukhan sync status                # the last runs and their stages
sharukhan escalate ledger            # what the escalation did and cost
sharukhan sync approve-upstream 7    # after reading UPSTREAM.table
```

## Running the permutation matrix: commands

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
sharukhan db render /root/photon-mc/memory.db MEMORY.md
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

`--dry-run --allow-build` reports the builds a real run would start and starts
none of them: a missing ISO is listed as `would build <key> <path>`, and its
rows as `[build ISO] -> kickstart -> ...`. Until 2026-09-26 it asked
`build::resolve` instead of `build::plan`, and `resolve` knows nothing of dry
runs - it created the cache directory, purged the cached photon-os-installer
RPMs from `stage/RPMS` and started `runPh5_normal.sh`. `resolve` now takes its
decision through `plan` as well, and refuses a missing variant patch before the
purge rather than after it.

The serialisation gate recognises a build by what contends for the shared
common tree, stage and fixed-name sandbox containers - `python3 build.py`,
whatever wrapper runs it - plus the `runPh*` wrapper family, not by a list of
wrapper names. It used to know only `runPh5_normal`, and a build started beside
`runPh7-3-RC4`. `build` and `build-iso` check it too, and `run` checks again
before each ISO it builds, because a run can take many hours:

```
sharukhan: foreign work is in flight: pid 3618556 /bin/sh /tmp/runPh7-3-RC4.5vU5M2.sh /root common experimental/linux-7.3-rc4 ...; pid 3641864 python3 build.py -c build-config.json -t image. ...
```

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

### `watch` — what is running, and follow it

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

## Package lifecycle: install, test and remove every package of a row

`--package-lifecycle` on `verify` or `run` goes past the vanilla install. After the read-only oracle
and harvest, for every package the row's own ISO offers, it installs the package, tests it by what
it ships, removes it, and proves the guest is back at its baseline. Design:
[ADR-0008](specs/adr/0008-package-lifecycle.md), contract:
[FRD-002](specs/features/package-lifecycle.md).

```
sharukhan verify --id k09 --package-lifecycle                      # every package on the media
sharukhan verify --id k09 --package-lifecycle --packages chrony,nginx,jq
sharukhan verify --id k09 --package-lifecycle --pkg-limit 50 --pkg-budget 3600
sharukhan verify --id k09 --package-lifecycle --pkg-resume         # continue on the same guest
sharukhan run --only k09 --package-lifecycle --keep
```

| option | meaning |
|---|---|
| `--packages a,b` | only these; each must exist on the media |
| `--pkg-limit n` | the first n candidates by name |
| `--pkg-budget sec` | wall-clock bound (default 14400); later packages are recorded as `not-reached` |
| `--pkg-resume` | keep the final verdicts of the last lifecycle file for this row, if they came from the same guest (machine-id) and the same policy (sha256) |
| `--pkg-policy file` | test a policy change; default is the embedded `schema/package-lifecycle-policy.json` |
| `--pkg-force-unverified` | run although verify recorded failures (refused by default: verdicts on a guest that is not known-good are unattributable) |

**Judging a change.** `sharukhan pkg-compare --base <pkglife-*.jsonl> --new <pkglife-*.jsonl> [--json]`
sets two runs of the same row side by side, package by package (name and arch). Media without
any change already carry failures, so a gate is judged against a baseline, not against zero. The
comparison fails on a regression (pass or skip turned fail), a new failure (a package only the new
media carries, failing), a missing package, or an incomplete one (not reached on either side).
Failures present in both runs are reported as unchanged; their reasons are shown when they differ.

**Every package, even when one takes the guest down.** `sharukhan pkg-lifecycle --id <row>
[--iso <path>] [--pkg-budget s] [--pkg-segments n]` runs the lifecycle on a freshly installed guest
(create-vm --recreate, install, verify --package-lifecycle, teardown) and, when a package leaves the
guest unreachable or away from its baseline, continues with the packages not reached on another
fresh install - at most `n` segments (default 10), each of which must reach a package the last one
did not. A package whose test failed is followed by a reachability probe: if the guest no longer
answers, the run stops there; that package keeps its fail with a `guest-state` step, while a
package that only read from an already lost guest is not reached and is retried. The segments'
records are appended to one `results/<row>/pkglife-segmented-<stamp>.jsonl`, where the last record
of a package is its verdict. `--iso` defaults to the row's cached ISO; `verify --iso` accepts the
same override, so a frozen baseline ISO can be tested on the row it belongs to.

**What is broken at all.** `sharukhan pkg-report --runs <label>=<pkglife-*.jsonl>,... [--out f.md]`
writes every failing package of one or more runs as Markdown: per ISO the packages failing per kind
of check (cli, ldcache, journal-window, unit, files-gone ...), each failing step, unit and CLI with
its detail, the packages a guest was lost with, and across the ISOs the packages that fail on one
ISO but pass on another that carries them. A package an ISO does not carry is not counted against it.

**Where packages come from.** The row's own ISO, reconnected with `vmrun connectNamedDevice
sata0:1` and mounted read-only in the guest; tdnf reads it through `--repofrompath` with every
other repository disabled, and the guest's repo files are never edited. Before anything installs,
the VMX must name this row's ISO, the medium must carry its volume id, and tdnf's listing must equal
the ISO's `/RPMS` file for file (`pkg.repo_is_media`). The media RPMs are unsigned, so
`--nogpgcheck` is used and recorded (`pkg.gpgcheck`).

**What is tested**, decided from the files a package installs:

| class | test |
|---|---|
| every package | `rpm -V` right after install: a missing file or a size/digest/link change of a non-%config, non-%ghost file outside `/var /run /proc /sys /dev /tmp` fails |
| daemon (unit files) | per unit: enable, bounded `systemctl start`, must stay up 5 s (same MainPID, no restart), stop, disable; the unit's journal between a cursor taken before enable and the end must hold no `err` or worse. Condition-skipped units are "skipped (condition)" with systemd's sentence. Templates, aliases and mount/target/swap-like units are not started, with the reason |
| cli (`/usr/bin` `/usr/sbin` `/bin` `/sbin`) | the file first: a dangling link fails, a file only owner or group may run is skipped (mode named), a script whose `#!` interpreter is not installed fails without running. Then `--version`, `-V`, `-v`, `version`, `-version` until one exits 0 printing a version with a clean stderr - never a bare invocation, always inside a systemd sandbox (unprivileged `nobody` with a private tmpfs `/tmp` as `$HOME`, no network, no devices, read-only root, no capabilities, refused syscalls fail with EPERM, runtime limit). No version: a defect signature (loader, missing interpreter/module/class/command, sanitizer build, crash by signal) **fails**; a probe the tool accepted but answered without a version **fails**; the tool's own option parser, an echo of the probe as an operand, a refusal to run unprivileged or a silent exit 0 make it a **skip** ("no version query") with the line that shows it; a reviewed `cli.preconditions` entry (tool + its exact words) skips what the bench cannot provide |
| library (`lib*.so.*`) | every ELF object a packaged library path resolves to (`readlink -f`: `/usr/lib64` is a link to `lib`) is the target of an `ldconfig -p` entry - no guess at soname spellings |
| after removal | package set equals the baseline, packaged files gone (%config may stay, recorded), unit files unloaded, no process runs a removed file, no new failed unit (one a `units.requires_config` entry declares is said with its reason, not failed), every enabled baseline unit active again. New entries below `/var/lib`, `/var/cache` and `/var/spool` that no installed package owns (a database the removal kept on purpose) are moved to `/var/tmp/sharukhan-residue/<package>/` and listed, so the next package starts from the baseline state: MySQL refuses MariaDB's leftover `/var/lib/mysql` |

A transaction that would remove or replace an installed package is never run (skip, with the
list). Boot-affecting packages (files under `/boot/`, `/lib/modules/`) are skipped with the reason.
Preinstalled packages are tested in place and **never removed**; their units are observed, never
started or stopped.

**Guest safety.** The unit owning the port-22 listener is derived and protected, with a reviewed list
(journald, dbus, networkd, vmtoolsd...); a unit whose `Conflicts=` names one is not started. Firewalls
and network providers (ordered `Before=` a network target, or listed) start only under a dead-man
switch: a transient timer that stops the unit is armed first, and only a NEW ssh connection
succeeding afterwards disarms it. If the package set cannot be returned to the baseline, the run
stops and records the rest as not reached. A later run on the same guest removes what an
interrupted one left behind.

**Controls first.** An err line logged on purpose must be found by the journal query; a transient
unit that exits 3 must be judged failed with its line found; the sandbox must be unprivileged,
offline and read-only, `rpm --version` must pass and GNU `false --version` (exit 1) must fail. A
failed control disables what it protects (`pkg.control.*`, `is_control=1` in the database).

**Evidence.** `pkg.*` rows (one `pkg.life.<name>` per package) in the run's `checks-<stamp>.jsonl`;
the full per-package record - every step with measured detail, every probe attempt, the journal
lines - in `results/<perm>/pkglife-<stamp>.jsonl`; `ingest` loads it into `package_lifecycle` and
`v_package_lifecycle`:

```
$ sqlite3 memory.db "SELECT package, classes, verdict, reason FROM v_package_lifecycle WHERE stamp='20260927T222143Z'"
7zip|cli|pass|
chrony|daemon,cli|pass|
cronie|daemon,cli|fail|cli /usr/bin/run-parts
jq|cli,library|fail|cli /usr/bin/jq
linux-drivers-sound|data|skip|boot-affecting: installs 25 under /boot/ /lib/modules/ /usr/lib/modules/ - ...
nftables|daemon,cli|pass|
...
```

`jq` there is a real defect the check found: `jq --version` prints `jq-` with no version - a
probe the tool accepted but answered without a version stays a failure. A tool without any version
query (`faillock`: `Unknown option: --version`) is a skip that quotes the tool's own words; a
reviewed `cli.version_query` (an alternative query that must still print a version - 7-Zip's `i`,
GNU `false --version` with its documented status 1) or `cli.preconditions` entry covers the rest.
Units: a reviewed `units.expected_errors` entry (unit or identifier + exact words) explains an
err line that is not the package's fault on this bench; the lines of a unit whose failure a
`units.requires_config` entry declares are that skip's evidence, not a second failure. A unit whose
start failed is a skip only with a reviewed `units.preconditions` entry and its evidence: the exact
words of its own journal, a kernel option the running kernel's own `/boot/config-$(uname -r)` leaves
unset (`CONFIG_IPMI_HANDLER` on linux-esx), or a device path that does not exist
(`/sys/class/infiniband`) - each with a negative control, and never for a unit that started. A probe's
own crash or OOM kill is the CLI's verdict, so systemd-coredump and kernel OOM lines about the
harness's units leave the journal window.

**Cost.** Measured on k09 (full ISO): 0.3-20 s per package (chrony 19 s: two units, each with its 5 s
stability window; nftables 12 s under the dead-man switch; a CLI-only package 2-3 s). The full media is ~1930 packages - hours, which is what `--pkg-budget` and
`--pkg-resume` are for.

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

### The common tree must hold only the build's own edits

Every Photon build on the host shares the common tree, and the driver restores
only the files it patches there. So `build`, `build-iso` and a `run` that would
build all refuse while that tree carries an edit the harness did not make, and
name each file with its modification time:

```
sharukhan: /root/common carries edits the build did not make, and every ISO built now would carry them too:
   M common/data/packages_appliance.json  (modified 2026-09-24 14:03:45)
```

On 2026-09-26 such an edit - an installer initrd list without stig-hardening -
went into every gate ISO, and every STIG row stalled in the installer. Stash
the edits in that checkout, or name them in `MC_COMMON_EDITS_ALLOWED` if they
are meant to ship - or give the build its own trees: with `MC_BUILD_ROOT` and
`PHOTON_TREE` pointing at an empty directory, `resolve` clones `common` and the
release branch from `MC_PHOTON_REMOTE` before it records the build inputs.

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
4 to 8, and the patch needed retargeting three times. As of 2026-09-29
(6.12.111, after 5.0 took both kernels to Release 2 for the aarch64 RELR
config) the chain is:

```
                  linux   linux-esx
pristine 5.0        2         2
variant patch       3         3      PR#24/#29 share one entry, #36 keeps it in its includes
embedded patch      4         4      +1 each
```

**Regenerate it, never hand-edit it.** `sharukhan canister-equivalent --out
src/embedded/canister-equivalent.patch` (`--repo <photon clone>`, default
`$PHOTON_TREE`, so it need not touch a tree another build is using; `--check`
compares a regeneration with the patch this binary embeds)
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

### The installer that composes the media is the variant's: `composer`

`make image` does not compose an ISO with the photon-os-installer RPM the build
just produced. `poi.py` runs a docker image (`photon-build-param.poi-image`),
and the installer inside that image decides what goes on the media; the RPM
under test only lands in the ISO's initrd. On this host `photon/installer:latest`
held photon-os-installer **2.4** on a Python 3.14 base, so every ISO had been
composed by 2.4. On 2026-09-29, in a fresh build root, both minimal gate groups
failed all ten attempts on `Error(1011) : No matching packages` for `ntp`. 2.4's
STIG set still names it; the variants' 0006 patch removes it. Earlier minimal
runs had passed only because a shared stage still held an `ntp` RPM from a full
build.

Upstream's Dockerfile is no way out: it runs `tdnf update` against the live
repos, and that day photon-updates had `librepo-1.14.5-7` requiring
`libxml2.so.2` next to a `libxml2-2.15.4` that no longer provides it. So
`build-iso` (and `sharukhan composer --poi <v>` on its own) builds the composer
offline, with `--network=none`:

1. the variant's installer spec directory, taken from `HEAD` with the variant
   patch applied,
2. every archive its `config.yaml` declares, each checked against its sha512,
3. the spec's own `%prep` (`rpmbuild -bp`),
4. the two commands `%py3_build`/`%py3_install` run, executed by the base
   image's own Python, on top of the base image pinned by ID
   (`MC_POI_BASE_IMAGE`, default `photon/installer:latest`), with the base's
   installer RPM removed.

Before the image is used, sharukhan proves it:

- every file of `photon_installer` in the image is byte-identical to the
  prepped tree, with nothing missing or left over;
- the rpmdb no longer lists the replaced installer;
- both console scripts resolve.

The tag, `sharukhan/photon-os-installer:<version>-<hash>`, is a content hash
over the base ID and the prepped tree, so an unchanged variant reuses its image.
The shared `photon/installer:latest` is never retagged. The legacy driver
receives the tag as `MC_POI_IMAGE` and writes and re-reads `poi-image` itself.
The cascade does the same in `preflight`, building the composer from the
already-injected tree when no tag was passed.

### How a medium boots: `iso-boot`

photon-os-installer 2.9 (upstream `b7c9039`) replaced syslinux. BIOS boots a
GRUB El Torito image, `/isolinux/eltorito.img`, which reads `/boot/grub2/grub.cfg`,
the same file UEFI GRUB reads. `isolinux.bin`, `isolinux.cfg` and `menu.cfg` are
gone. POI 2.8 media still boot `/isolinux/isolinux.bin`. The installer that
composes the medium decides which, so a tool that hardcodes one breaks on the
other: the HABv4 ISO creator stopped a 7.3-rc4 run with `Cannot find in ISO
image: -boot_image ... bin_path='/isolinux/isolinux.bin'`.

`sharukhan iso-boot --iso <path> [--json]` reads the layout from the El Torito
catalogue and reports:

- the catalogue, the BIOS image and the EFI image, each checked to be on the
  medium;
- the BIOS loader, identified from the image's own bytes: `ISOLINUX` for
  syslinux, and GRUB `cdboot.img`'s two messages for `grub-eltorito`;
- whether a hybrid MBR/GPT system area is present;
- the mkisofs boot options that reproduce the layout from an extracted tree,
  with the EFI load size left to xorriso, because a re-signed `efiboot.img`
  changes size.

The media oracle records the same layout (`media.boot_layout`) and fails a
catalogue that names a missing file (`media.boot_images`). `remaster` needs none
of this: it replays the input's boot catalogue (`-boot_image any replay`).

## Remaster mode: an Azure variant of an ISO that already exists

An Azure guest needs Hyper-V support **built into** the kernel rather than as
modules:

```
CONFIG_HYPERV=y  CONFIG_HYPERV_STORAGE=y  CONFIG_HYPERV_NET=y  CONFIG_HYPERV_UTILS=y
CONFIG_HYPERV_BALLOON=y  CONFIG_HYPERV_VSOCKETS=y  CONFIG_PCI_HYPERV=y
```

The installer's initrd is a fixed rootfs, not a dracut image, so `=m` leaves the
installer kernel depending on udev autoloading from a module tree it may not
reach. `=y` removes that dependency.

```
sharukhan remaster --in photon-5.0-c6db6a0d6.aarch64.iso \
                   --out photon-5.0-c6db6a0d6.aarch64.azure.iso \
                   --arch aarch64 --hyperv \
                   --photon-tree /path/to/photon@<the commit that built --in> \
                   --sources /path/to/SOURCES --builddir /path/to/scratch
```

`--hyperv` also exists on `build` and `build-iso`, where it joins the cascade as
`inject:kernel-config[...]` + `inject:release-bump[...]`.

### Why remaster rather than build

A full aarch64 ISO on an x86_64 host is hundreds of packages under qemu-user at
roughly a tenth of native speed — days. An Azure variant changes exactly one
thing, so `remaster` rebuilds the kernel spec alone and swaps the results into
the medium: bootstrap → gen-config → build-kernel → initrd → repo → iso →
verify, each resumable, because `build-kernel` takes hours.

### The dependency closure is computed, not listed

A tristate cannot be `y` unless every symbol it depends on is `y`. Writing
`CONFIG_HYPERV_UTILS=y` into a config where `CONFIG_CONNECTOR=m` does not fail —
`olddefconfig` silently demotes it back to `m`, and the only visible consequence
is a kernel that cannot find VMBus devices. So the fragment carries the seven
symbols that were **asked for**, and the enabling symbols are computed from the
config at hand and reported:

```
dependency closure raised 3 symbol(s):
  CONFIG_CONNECTOR: m -> y (else CONFIG_HYPERV_UTILS cannot be y)
  CONFIG_SCSI_FC_ATTRS: m -> y (else CONFIG_HYPERV_STORAGE cannot be y)
  CONFIG_VSOCKETS: m -> y (else CONFIG_HYPERV_VSOCKETS cannot be y)
```

The edges come from the kernel's Kconfig, but nothing trusts them: after
`olddefconfig`, every symbol is asserted `=y` by name. If an edge is wrong or
the kernel moved, the build stops and says which symbol. `PCI_MSI_IRQ_DOMAIN`
gated `PCI_HYPERV` in 6.1 and does not exist in 6.12 — which is exactly why the
table is re-checked per kernel rather than copied forward.

**`config_x86_64_acvp` is never touched**, and `--hyperv` is refused for the
`acvp` and `kat` canister modes: those are FIPS certification artefacts.

### The toolchain comes off the input ISO

The kernel is compiled by the toolchain generation that produced the rest of the
media — read from the input, never named in code. A kernel built against a
different glibc or binutils ships modules whose vermagic disagrees with the
userland around them, and that fails at boot rather than at build time.

### The accelerator is gated on byte identity

Under emulation the kernel compiles ~10× slower than native. An x86_64-hosted
cross `cc1`, built from the *same* gcc source, removes most of that — but "same
version" is not evidence: gcc's configure silently disables SHF_MERGE,
SHF_LINK_ORDER, CFI directives and LEB128 support when it cannot find a target
assembler, and the resulting compiler emits different code while reporting the
same version.

So real kernel translation units the media's own compiler already built are
recompiled with the native one and compared **byte for byte**. Any difference,
any failed compile, or fewer than five samples refuses the swap. Only
`-nostdinc` compiles are routed to it; `as` and `ld` are never swapped, because
Photon patches gas's DWARF output. `--no-accel` declines it outright.

### What verify reads back off the finished ISO

Five independent assertions, because each can pass while another fails:

1. the kernel RPM **on the media** carries the symbols in `/boot/config-<uname>`
2. `isolinux/vmlinuz` is byte-identical to that RPM's `/boot/vmlinuz-<uname>`
3. the installer kernel's **own embedded ikconfig** carries them — the only
   evidence about the binary rather than about a file beside it
4. the initrd carries exactly one module tree, at the new uname, with no `hv_*`
   modules left
5. the repo metadata lists the new NEVR and not the old one

### The replacement set is derived

Every package on the media whose `SOURCERPM` is the kernel SRPM — which on 5.0
includes **`bpftool`**, whose name gives no hint and which carries
`Requires: linux-tools = V-R`. Leaving it behind breaks the repo. It is read
from `primary.xml`, never hardcoded.

### A config change must change the NEVR

`Release: N` becomes `N+1.azure`, so `6.12.109-4.azure.ph5` sorts above the
stock `3.ph5` and below a future official `4.ph5` — a later official build still
upgrades it. Without a distinguishable NEVR, rpm considers the Hyper-V kernel
identical to the stock one.

## Kernel wrappers: `sharukhan wrapper`

`staging/runPh7-2-7.sh` builds Photon OS 5.0 with Linux 7.2.7. A wrapper for any other
kernel.org release is **derived** from it, not written by hand:

```sh
sharukhan wrapper kernel mainline                 # what kernel.org has; the identity it derives
sharukhan wrapper profile-new --kernel 7.3-rc5 --from 7.3-rc4   # verified pin, review list
sharukhan wrapper derive --profile 7.3-rc5 --repo /root/5.0     # writes staging/runPh7-3-RC5.sh
sharukhan wrapper check --repo /root/5.0          # every committed wrapper is up to date
sharukhan wrapper verify 7.3-rc4 --profile 7.3-rc4              # re-prove a pin
```

Run from `staging/sharukhan-cli` (profiles default to `./profiles/kernel`), or set
`SHARUKHAN_WRAPPER_PROFILES`, `SHARUKHAN_WRAPPERS`, `SHARUKHAN_PHOTON_REPO` and
`SHARUKHAN_KERNEL_CACHE`.

How it is built, in short (the full contract is [FRD-001](specs/features/kernel-wrapper.md)):

- **The base marks its own kernel-specific regions.** `runPh7-2-7.sh` declares
  `# @sharukhan-wrapper kernel=7.2.7 userland=5.0 native-series=6.12` and ten
  `# @sharukhan-slot <name> begin|end` pairs. Each slot is re-rendered for the target; the rest is
  carried over and renamed by identity. The markers are comments, so the base still runs as is.
- **Everything else is computed from the release string**: tag, ISO marker, script and branch
  names, tarball and signature URLs, `Source0`, RPM `Version`/`Release` (an RC is `X.Y.0` /
  `0.rcN.1`), `%define kernel_src`, `EXTRAVERSION` handling.
- **What cannot be computed lives in a reviewed profile** (`profiles/kernel/<release>.json`): the
  patch enablers, dropped kernel parameters, installer patches, pre-build extras, the derived
  wrapper's version, and the pin with how it was verified.
- **Nothing is trusted on arrival.** A pin is established by `verify`: cdn tarballs by their
  `.tar.sign`, git.kernel.org snapshots (release candidates) by the signed tag plus byte-identity
  with `git archive` of the tagged commit. Only the fingerprints in
  `profiles/kernel/kernel-org-signers.json` (from kernel.org/signature.html) are accepted, in a
  keyring private to the run. `derive` also reads `EXPERIMENTAL-<release>.md` in the kernel spec
  directory of `origin/experimental/linux-<release>` and requires it to agree with the profile.
- **The kernel spec directory is read from the tree, never assumed.** 5.0 keeps its kernel per
  subrelease (`SPECS/90/linux`, `SPECS/91/linux`, `SPECS/92/linux`); the directory is the one
  whose `linux.spec` `build_if` accepts the tree's `photon-subrelease`. The pin script works on
  `$KDIR`: a build exports the directory sharukhan resolved (`specresolve::kernel_dir`), a run by
  hand resolves it with the same rule (`pin_kernel_dir`), and a test keeps the two in agreement.
- **Every derivation proves itself** before it writes: no target name already in the base, no base
  name in a rendered slot, every rename applied, no base name left anywhere, `sh -n` clean, every
  Python heredoc parses. The write is atomic; `--check` compares byte for byte instead.
- **A base bump stops derivation** until each profile is reviewed against it
  (`base.wrapper_version`), because a fix in the base flows into every derived wrapper.

`runPh7-3-RC4.sh` is the first derived wrapper; the golden test keeps it byte-identical to what the
committed base and `profiles/kernel/7.3-rc4.json` derive (wrapper v11, base v15).

### A FIPS canister series for a profile kernel

A profile may carry a `fips` section: where the release branch keeps a ported
canister series (`SPECS/linux/fips-<series>/manifest.json`) and its LKCM series.
The manifest - written by the port's export and proven by a `%prep` replay -
says which file every `PatchN`/`SourceN` line names, which 6.12 patches the
kernel does not need, the `%autopatch` ranges and the per-flavour additions.

The derived wrapper renders a manifest-driven spec editor
(`src/wrapper/assets/fips_spec_edit.py`, compiled in) into the `kernel-fips`
slot and runs it **only for a canister build** (`CANISTER_MODE` `build`,
`equivalent-a`, `equivalent-b`); `none` leaves the kernel FIPS-off. The editor:

- rewrites the Patch/Source lines, drops what the kernel does not need and
  restores the commented-out `%autopatch` ranges in place;
- makes both canister pins overridable in the two-macro shape Photon's
  SpecParser can read (`canister_equivalent` + `fips_canister_override`,
  `canister_stamp_real` + `fips_certified_override`), defaulting to the tree's
  own `linux` NEVR - there is no certified canister of the series to claim;
- moves `Name:` before the first canister conditional (see below);
- after the config merge, enables `CRYPTO_SELFTESTS`, re-applies Photon's
  `CRYPTO_FIPS*`/`CRYPTO_JITTERENTROPY*` settings and fails `%prep` if any does
  not hold.

`derive`'s branch check also reads the manifest and requires every file it
names on the branch exactly once under `SPECS/linux` (rpm sees it flattened).

## Kernel-profile builds and runs: `--kernel`

```sh
sharukhan variant-patches --kernel 7.3-rc4        # variants on experimental/linux-7.3-rc4
sharukhan build-iso --kernel 7.3-rc4 --iso-type full --poi latest --canister equivalent --allow-build
sharukhan run --kernel 7.3-rc4 --only k13,k14,k15,k16
sharukhan verify --kernel 7.3-rc4 --id k15
```

- **Own trees.** A kernel build runs in `$MC_WORK/kbuild/<release>` with its
  own ISO cache (`$MC_ISO_CACHE/k<release>`) and variant patches, and never
  touches `/root/5.0`, `/root/common` or `/root/experimental/*`. The release
  branch is verified before anything is purged (tarball manifest, patch files,
  FIPS manifest).
- **The cascade, in every mode.** The derived wrapper's pin script is one
  injection (`inject:kernel-pins[<release>]`), sourced exactly as the wrapper
  sources it; the 6.12 canister-equivalent patch is left out (the profile brings
  its own series); the canister NEVR comes from the profile.
- **Photon's spec checker is honoured, not skipped.** The pins leave the 5.0
  kernel's own patches unreferenced; `build.py` checks modified specs whenever
  `make` has no TTY, which the wrapper's own runs never met. After the pins the
  checker runs per kernel spec and over both, exactly what it lists is pruned
  from the working tree (a `PatchN` only from the spec whose own run lists it,
  a `SourceN` only when unreferenced), and it must then pass.
- **Kernel variants.** PR branches that touch a kernel spec directory
  (`SPECS/linux` or `SPECS/<n>/linux`) are left out (the profile owns the
  kernel) - a PR stacked on such a branch too, because its range carries the
  parent's kernel files; a conflicting commit is skipped only when the kernel
  branch already carries it (same subject, identical non-spec files).
- **Runs.** Under `--kernel` every row takes the canister axis `equivalent`,
  `verify` expects the profile's NEVR, records `meta.kernel`, and
  `guest.kernel_release` requires `uname -r` to be that kernel; the media gate
  adds the installer Release bumps the profile's pins make.

### Linux 7.3-rc4 (2026-09-29)

`photon-5.0-899f55a42.x86_64.iso` - full, photon-os-installer 2.9-4, canister
equivalent, `linux`/`linux-esx` 7.3.0-0.rc4.1 relinked in phase B against
`linux-fips-canister-7.3.0-0.rc4.1`. `run --kernel 7.3-rc4` over k13-k16: 0
failing checks; every guest runs `7.3.0-0.rc4.1.ph5-esx`; the STIG rows k15/k16
boot with `fips=1`, "FIPS canister verification passed", canister version 7.3
based on 7.3.0-0.rc4.1.ph5. **Not CMVP validated** - no canister of the 7.3
series is published; the port's per-patch decisions are in
`SPECS/linux/fips-7.3/README.md` on the release branch.

## Real-world example: a full ISO with kernel 7.3, the latest installer and the equivalent canister

This chapter is a record of one real run (2026-10-25 to 2026-10-27), from the
request to the verified ISO, with every command and every problem met on the
way. Host-specific paths are shown as they were on that host; no value here is
secret.

### The goal and the result

**Goal:** one full ISO with Linux 7.3, the latest photon-os-installer variant,
the canister built from that kernel (`--canister equivalent`), and every fork
PR applied.

**Result:**

| | |
|---|---|
| ISO | `C:\Users\dcaso\Downloads\Ph-Builds\full-poilatest-equivalent__photon-5.0-cb2b916647.x86_64.iso` |
| Kernel on the media | `linux` / `linux-esx` `7.3.0-1.ph5` (guest `uname -r`: `7.3.0-1.ph5-esx`) |
| Installer | `photon-os-installer-2.9-1.ph5` - the same as the regular latest-variant ISO |
| Canister | `linux-fips-canister-7.3.0-1.ph5`, built from this kernel in phase A, relinked into both flavours in phase B - **not CMVP validated** |
| PRs | every branch of `[variant latest]` and `[common]` except the kernel stack (see step 5) |
| Rows | k13 (full, latest, ext4): 44 checks, 0 fail; k15 (full, latest, STIG, `fips=1`): 46 checks, 0 fail, canister 7.3 based on `7.3.0-1.ph5` |

### Step 1: which 7.3, verified

```sh
sharukhan wrapper kernel 7.3          # identity: Version 7.3.0, Release 1, tarball, branch name
sharukhan wrapper kernel stable       # kernel.org: 7.3 is mainline and latest_stable, no 7.3.x yet
sharukhan wrapper verify 7.3          # downloads linux-7.3.tar.xz and checks its .tar.sign
```

`verify` accepted the tarball only with the signature of a reviewed kernel.org
signer (`647F28654894E3BD457199BE38DBBDC86092693E`, Greg Kroah-Hartman) and
printed its sha512; that sha512 is what every later step compares against.

### Step 2: the release branch on today's 5.0

A kernel build takes its variants as `origin/<kernel branch>..origin/<PR>`, so
the kernel branch must sit on the same 5.0 the PRs are rebased on; the rc4
branch was 100 commits behind. `experimental/linux-7.3` was therefore built in
the **local gate repository only** (never pushed), on 5.0 `727909c4b8`:

```sh
git -C /root/photon-mc/gate/photon.git worktree add --detach /root/photon-mc/gate/work/k73-branch 727909c4b8
# kernel files of experimental/linux-7.3-rc4: SPECS/linux/... -> SPECS/92/linux/...
#   secure/0001-gcc-rap-plugin-with-kcfi-7.3.patch, vmw/*-7.3.patch, fips-7.3/ (43 files)
# SPECS/92/linux/config.yaml: the linux-7.3.tar.xz entry (url, sha512, commit c03c1a14,
#   license-review hashes computed from the 7.3 tarball); version quoted: '7.3'
# SPECS/92/linux/kernel_cve_patches.inc: empty (6.12-stable backports do not apply to 7.3)
# SPECS/92/linux/EXPERIMENTAL-7.3.md: the rows the branch check verifies
git -C /root/photon-mc/gate/work/k73-branch branch experimental/linux-7.3
```

Only the kernel moves to the branch. The rc4 branch also carried userland fixes
(cloud-init, dbus, sudo, two installer patches); the PRs bring cloud-init, and
the others are not PRs, so they are not part of this ISO.

### Step 3: the profile and the derived wrapper

```sh
sharukhan wrapper profile-new --kernel 7.3 --from 7.3-rc4    # verifies the source again, lists what to review
# review profiles/kernel/7.3.json: comments, the FIPS manifest (relative to the kernel
# directory: fips-7.3/manifest.json), no installer patches, no userland pre-build
git clone -q --no-checkout -b experimental/linux-7.3 /root/photon-mc/gate/photon.git /root/photon-mc/gate/work/k73-repo
sharukhan wrapper derive --profile 7.3 --repo /root/photon-mc/gate/work/k73-repo
sharukhan wrapper check --repo /root/photon-mc/gate/work/k73-repo   # both profiles, each in its own layout
```

`derive` wrote `runPh7-3.sh` and its branch check passed: kernel spec directory
`SPECS/92/linux` (subrelease 92), tarball and sha512, `Version: 7.3.0`,
`Release: 1`, the three patch files, and the FIPS manifest (55 files present
once, 40 patches in range, 13 dropped).

### Step 4: prove every patch before building

The pin script was run on a scratch checkout of the branch in a container with
nothing else mounted, then `rpmbuild -bp` replayed `%prep` of the pinned specs
with each canister phase's macros (`canister_build 1`, `canister_stamp_real 1`,
`fips_certified_override 7.3.0-1.ph5` for phase A):

```sh
# pins: KDIR resolved by the script itself -> SPECS/92/linux; FIPS series enabled
docker run --rm --network none -v <scratch tree>:<scratch tree> -w <scratch tree> \
  -e CANISTER_MODE=equivalent-a ... sharukhan/photon-builder:<tag> sh -c 'set -eu; . /pins.sh'
# %prep replay: every patch at --fuzz=0 on pristine linux-7.3
rpmbuild -bp --nodeps -D "_sourcedir /src" -D "photon_subrelease 92" -D "dist .ph5" \
  -D "canister_build 1" -D "canister_stamp_real 1" -D "fips_certified_override 7.3.0-1.ph5" linux.spec
```

Result after one port (see the culprits): 44 patch runs, 0 failed hunks, 0
rejects. Phase B's `%prep` cannot run standalone - it unpacks the canister phase
A installs - and was proven by the build itself.

### Step 5: variant patches with every PR

```sh
sharukhan variant-patches --kernel 7.3
```

Both variants assembled on `experimental/linux-7.3` and apply to it. One branch
was left out, `fix/linux-esx-depmod-ghost`: the tip of the kernel PR stack
(#24, #29, #36, #54), whose range changes 638 files, all in kernel spec
directories. Those PRs rework the 6.12 kernel spec; under a 7.3 profile they do
not apply, and nothing outside the kernel is lost with them.

### Step 6: build the ISO

```sh
sharukhan build-iso --kernel 7.3 --iso-type full --poi latest --canister equivalent --allow-build
```

run detached in the host mount namespace with a log. The build runs in its own
root (`$MC_WORK/kbuild/7.3`): phase A builds `linux` with the canister
(`linux-fips-canister-7.3.0-1.ph5`), phase B relinks both flavours against it
and builds the full image. The ISO went to the ISO store (`MC_ISO_STORE`) and is
linked from `$MC_ISO_CACHE/k7.3/full-poilatest-equivalent/`.

### Step 7: install and verify

```sh
sharukhan run --kernel 7.3 --only k13,k15 --allow-build
```

`--kernel` makes every row expect the profile's NEVR: `meta.kernel 7.3
(7.3.0-1.ph5)`, `guest.kernel_release 7.3.0-1.ph5-esx` (PASS on both rows), and
on the STIG row k15 `guest.fips_canister 1`, `guest.canister_version 7.3`,
`guest.canister_based_on 7.3.0-1.ph5` (PASS). 0 failing checks.

### Culprits and how each was solved

| # | Symptom | Root cause | Fix |
|---|---|---|---|
| 1 | The kernel-profile tooling could not build against today's 5.0 | 5.0 keeps its kernel per subrelease (`SPECS/92/linux`); the base wrapper, the branch check, the profile and `spec_canister_pin` assumed `SPECS/linux` | the kernel directory is read from the tree everywhere; base wrapper v15 (`5088b218`) |
| 2 | "All PRs" would have dragged 100 upstream commits into every variant | the rc4 branch sat on a 5.0 from 2026-09-19 | `experimental/linux-7.3` on today's 5.0 (local gate repo, step 2) |
| 3 | rc4's `config.yaml` license-review hashes did not belong to its tarball | copied from the 6.12 entry | the 7.3 hashes computed from `linux-7.3.tar.xz` |
| 4 | `version: 7.3` in `config.yaml` read as the float `7.3` | YAML typing | quoted `'7.3'`, confirmed with `yaml.safe_load` in the builder |
| 5 | `1000-FIPS-canister-creation-7.3.patch`: 1 of 23 hunks FAILED at `--fuzz=0` | 7.3 moved `assoclen -= orig_len_this_step;` in `gcm_process_assoc()`; the hunk's context still expected it after the `need_resched()` block | the same change on 7.3's context, proven by the `%prep` replay (branch commit `cb2b916647`) |
| 6 | Phase A stopped after 1 h 48 min: `failed to build contain_unpriv`, `linux/errno.h: No such file or directory` | build.py compiles `contain_unpriv` in a fresh build root; the builder image had gcc and glibc-devel but no `linux-api-headers` (the gate's root still had a binary compiled on the host in September) | `linux-api-headers` in the image, and every new image must compile a C program that includes `<errno.h>` (`fe532e0a`); the old image fails that proof, the new one differs by that package only |
| 7 | `could not obtain rpcbind-1.3.1.tar.bz2 / pgbouncer-1.26.0.tar.gz from any source` | both upstreams are gone and not on Photon's mirror; the fetcher never looked at the verified copies in the configured build root | a missing archive is restored from the local caches first, only when its sha512 is the declared one (`1204fe90`) |
| 8 | Phase B needed 6 `make` attempts: `linux` failed once, `linux-esx` three times, `kafka` once; attempt 6 passed | the one failure whose log was read while the build ran: `cc1: internal compiler error: Bus error` compiling `fs/jbd2/recovery.o` (linux-esx, 2026-10-26 17:20Z). The kernel log shows no OOM kill, no SIGBUS record and no I/O error on the build disk, only order-7 page allocation failures in the Hyper-V vmbus driver (fragmented memory); the same sources built cleanly on the next attempts - environmental, not reproducible | the retries carried the build; the logs of the other failures were overwritten by the next attempt, so the cascade now keeps every failed attempt's package logs under `<build-log dir>/failed-attempts/` (`a04b4a6d`) |
| 9 | `Debug symbols found in following rpms: subversion-1.14.5-2.ph5` (non-fatal) | open: the base wrapper's `pin_svn_nodebug` (`%exclude /usr/lib/debug` after every `%files`) is the only difference to the gate's subversion RPM, which has no debug paths; not yet proven | recorded as finding 124 (`wrapper-svn-nodebug-ships-debug-files`) |

### Timings

All times UTC.

| Step | When | Took |
|---|---|---|
| Tooling port, branch, profile, `%prep` proof | 2026-10-25 20:34 - 21:06 | 32 min |
| `variant-patches --kernel 7.3` | 21:06 | about 1 min |
| First build to the `contain_unpriv` stop (fetching 2 030 sources into the fresh root) | 21:07 - 22:55 | 1 h 48 min |
| Idle until the stop was picked up, then the builder fix and a new image | 22:55 - 04:11 | 5 h 16 min |
| Phase A (fresh toolchain bootstrap, then `linux` with the canister) | 2026-10-26 04:11 - 10:19 | 6 h 08 min |
| Phase B (6 `make` attempts: 147, 165, 209, 27, 267 and 125 min) | 10:20 - 2026-10-27 03:28 | 17 h 08 min |
| Rows k13 and k15 | 2026-10-27 07:47 - 08:03 | 16 min |

## Keeping the fork's PRs current: `sharukhan sync`

When the fork's release branch (`MC_RELEASE`, default `5.0`) or its `common`
branch moves, every open PR of the fork (`MC_FORK`, default `dcasota/photon`)
has to be rebased, checked, built, gated and published again. `sharukhan sync`
does that as a resumable state machine recorded in `memory.db`.

### The stages

```
ANALYZE -> REBASE -> VERIFY -> PREPARE -> FASTLOOP -> GATE -> PUBLISH -> STAGEVM -> UPSTREAM -> DONE
```

| Stage | What it does |
|---|---|
| `ANALYZE` | lists the fork's open PRs, checks each local head equals GitHub's, and decides per PR: keep, or rebase (a PR stacked on a rebased one is rebased too) |
| `REBASE` | moves each PR onto its new base, parents first; a refused rebase stops the run as `needs-decision` |
| `VERIFY` | `rpmspec -P` per subrelease and arch, `check_spec`, and the one-changelog-entry rule against the new base |
| `PREPARE` | points the gate repository at the candidates, resets the build trees and regenerates the variant patches |
| `FASTLOOP` | builds the minimal ISO of the default variant and installs `MC_FASTLOOP_ROWS` (default `k03 c03`) |
| `GATE` | `sharukhan run --all --allow-build`: every ISO, every unattended row |
| `PUBLISH` | pushes with `--force-with-lease`, carries each description, checks GitHub shows both |
| `STAGEVM` | for PRs held for the upstream stage: the staged code is the gated code, then `MC_STAGED_ROWS` (default `k11`) is installed from it |
| `UPSTREAM` | waits for `sync approve-upstream`, then moves the shared branches and updates both descriptions in place |
| `DONE` | records the synced bases |

Rules that hold throughout:

* One run at a time.
* Before every stage the inputs are checked again: if a base head or a PR head
  moved, the run stops as `superseded`.
* A stage left `running` by a process that is gone is `interrupted` and runs
  again on resume; every stage is idempotent.
* `abort` takes effect between stages, never inside PUBLISH.
* Nothing reaches GitHub before PUBLISH. Candidates live in the gate
  repository as `sync/<run>/<branch>`.

### Starting, following and resuming a run

```bash
sharukhan sync start                    # a run against the fork's current bases
sharukhan sync start --until GATE       # stop before GATE (paused)
sharukhan sync status                   # the last five runs and their stages
sharukhan sync resume 7                 # continue run 7 from where it stopped
sharukhan sync abort 7                  # between stages; restores the gate refs
```

`start` also takes `--fork <owner/repo>`, `--repo <gate repository>` and
`--against <repository>` (new bases from another repository, for a preview).
Stage logs go to `$MC_RESULTS_DIR/sync/<run>/`.

`MC_PUBLISH_DCASOTA` decides PUBLISH:

| Value | PUBLISH |
|---|---|
| `auto` (default) | pushes when every description passes the lint |
| `approve` | always waits for `sharukhan sync approve <run>` |
| `preview` | the run ends before PREPARE: candidates only, nothing built or published |

### When a PR needs a decision

A refused rebase or failed checks stop the run as `needs-decision`. The
escalation (below) may propose a fix; either way the answer is recorded with
`decide`:

```bash
sharukhan sync decide 7 23 candidate refs/heads/resolve/23
sharukhan sync decide 7 92 candidate refs/heads/resolve/92 --base 5.0   # and move the PR's base
sharukhan sync resume 7
```

The candidate must sit on the new position of the base the PR will have.
Resuming keeps every PR already rebased or resolved.

### Descriptions

PUBLISH carries each PR's description to its new head (moved paths, Release
numbers) and lints it: Problem / Change / Testing sections, Dependencies when
stacked, no stale paths or versions. A change whose content changed needs a
description reviewed for it:

```bash
sharukhan sync lint                              # every open PR's description now
sharukhan sync lint 23 36                        # only these
sharukhan sync body --set 7 23 reviewed-23.md    # a reviewed description for run 7
sharukhan sync body --set 7 23 proposed          # the escalation's, once its proposal is decided
sharukhan sync body --set-upstream 7 36 up-36.md # the upstream PR's description
sharukhan sync body --restore 7 23               # put back the text from before run 7
```

The previous text of every edited description is kept as
`PUBLISH/<n>.orig` (and `<n>.upstream.orig`).

### Upstream PRs: shared branches, staged first

An upstream PR (`MC_UPSTREAM`, default `vmware/photon`) opened from a fork
branch shares that branch with the fork's own PR. GitHub cannot give a PR
another head, and the maintainers keep their conversation on the PR they have,
so sharukhan never closes, re-opens or comments on an upstream PR, and it
never opens one:

1. **PUBLISH** pushes such a branch, and every PR stacked on it, to
   `staging/<branch>` on the fork, a branch no PR uses.
2. **STAGEVM** checks `staging/<branch>` is the gated candidate and the
   upstream PR's head has not moved, then installs `MC_STAGED_ROWS` from it.
3. **UPSTREAM** prepares both descriptions and checks the head merges cleanly
   onto the upstream PR's base. The upstream description may not name the
   fork's owner, nor a PR number that is not an upstream PR of the fork and
   not already in its text. It waits for a person whatever
   `MC_PUBLISH_DCASOTA` says:

```bash
cat $MC_RESULTS_DIR/sync/7/UPSTREAM.table       # what will move, both descriptions' verdicts
sharukhan sync approve-upstream 7
```

After approval it moves the shared branch with a lease, checks both PRs show
the new head, edits both descriptions in place, checks GitHub's merge verdict
and deletes `staging/<branch>`. For these PRs the fork PR shows the new code
at the same moment as the upstream PR.

### The timer: `sync auto`

```bash
sharukhan sync auto                  # what the timer runs
sharukhan sync auto --quiet 3600     # quiet period override (default SHARUKHAN_SYNC_QUIET, else 7200 s)
```

It starts a run only when the watcher recorded a move of the fork's bases
that has been quiet long enough, no run is active and no gate or build job is
running. A run that waits for a decision is handed to the escalation queue on
every tick. Notifications go to `MC_NOTIFY`.

### Other sync commands

```bash
sharukhan sync reset-trees            # build trees back to the gate repository's branches, as PREPARE does
sharukhan sync baseline 5.0 <sha>     # record the synced base of a root
sharukhan sync analyze --repo <git dir> --fork <owner/repo> --base 5.0=<old>..<new>
sharukhan sync verify  --repo <git dir> --base <rev> --common <common tree> <ref>...
```

`reset-trees` refuses edits no variant patch or fixup explains, and refuses
while a run or job uses the trees: use it before a gate run by hand.

## The escalation: `sharukhan escalate` and `sharukhan mcp`

A PR the sync could not rebase, or whose checks failed, can be handed to
Claude. The model gets only sharukhan's own tools, works under token budgets,
and nothing it says is believed: sharukhan reruns its own checks on whatever
it proposes, and a proposal becomes a candidate only through `sync decide`.

### Before the first escalation: `escalate preflight`

```bash
sharukhan escalate preflight
```

It checks the API key without spending a token (set, shaped like an
Anthropic key, accepted by `GET /v1/models`) and prints the budgets and the
price weights. The key comes from `MC_ANTHROPIC_KEY_FILE` (a root-owned 0600
file, written by `service install --escalation-key-from-env`) or else from
`ANTHROPIC_API_KEY`. It is passed to `curl` on stdin and to `claude` in its
environment only; it is never printed, logged or stored elsewhere.

### One escalation, the queue, the ledger

```bash
sharukhan escalate --run 7 --pr 23     # one attempt for PR #23 of run 7
sharukhan escalate queue --run 7       # every refused or failed PR of run 7, parents first
sharukhan escalate ledger              # the last 30 attempts: tokens, turns, cost, outcome
```

The queue skips a PR waiting on an undecided parent, one with a verified
proposal and one out of attempts. A run or day budget, a rate limit or a
missing key stops the queue; `sync auto` admits it again on its next tick. A
parked PR is one notification, not one per tick. `MC_ESCALATE=off` leaves a
stopped run to a person.

Outcomes in the ledger: `verified` (sharukhan's own verify passes the
proposal), `proposed` (it does not), `no-proposal`, `budget`, `parked`,
`failed`, `interrupted` (its process died; counts as an attempt) and `void`
(invalidated by a sharukhan defect; not an attempt).

### Taking a verified proposal

```bash
sharukhan escalate ledger | head -3
sharukhan sync decide 7 23 candidate refs/heads/sync/7/proposal/<branch>
sharukhan sync body --set 7 23 proposed     # the description it proposed, if it passes the lint
sharukhan sync resume 7
```

### Budgets and price weights

Tokens are counted by price relative to uncached input: input and output 1,
cache read 0.1, cache write 1.25 (5-minute cache) or 2.0 (1-hour cache).

| Setting | Default | Meaning |
|---|---|---|
| `MC_ESC_TOKENS_PER_ESCALATION` | `150000` | weighted tokens of one attempt; the stream is stopped when exceeded |
| `MC_ESC_TOKENS_PER_RUN` | `500000` | weighted tokens of all attempts of one sync run |
| `MC_ESC_TOKENS_PER_DAY` | `1000000` | weighted tokens per day |
| `MC_ESC_ATTEMPTS` | `2` | failed attempts per PR and run before it is parked for a person |
| `MC_ESC_MAX_TURNS` | `25` | turns per attempt |
| `MC_ESC_MODEL` / `MC_ESC_FALLBACK_MODEL` | `opus` / `sonnet` | models |
| `MC_ESC_WEIGHT_CACHE_READ` | `0.1` | price weight |
| `MC_ESC_WEIGHT_CACHE_WRITE_5M` / `_1H` | `1.25` / `2.0` | price weights |
| `MC_ESCALATE` | `auto` | `auto` or `off`; anything else is an error |

### How the model is confined

* `claude --bare -p --tools ""`: no built-in tool (no shell, files, web or
  sub-agents); the only tools are `mcp__sharukhan__*`.
* A private empty working directory and `HOME`, an environment of `PATH`,
  `HOME`, the key and `DISABLE_AUTOUPDATER` only.
* The MCP server is started under `env -i` with only the settings its own work
  needs, so it never sees the key.
* `verify` runs the spec tools in read-only, capability-free containers without
  network; only a directory the caller names is writable.

### The MCP server: `sharukhan mcp`

```bash
sharukhan mcp --run 7 --pr 23                       # escalation profile (default)
sharukhan mcp --run 7 --pr 23 --profile readonly    # read tools only
```

A stdio JSON-RPC server bound to one sync run and PR. Its tools:

| Tool | Profile | What it returns or does |
|---|---|---|
| `subject` | both | the run, the PR, the stage that stopped, its refusal, the revisions |
| `pr_diff` | both | the PR's own change, paginated |
| `upstream_diff` | both | what upstream changed in one path between the old and the new base |
| `file_at` / `list_files` | both | a file, or a directory listing, at a named revision |
| `log_excerpt` | both | lines of a stage log of this run |
| `rules` / `findings` | both | the project's rules; recorded findings |
| `propose_patch` | escalation | commits a diff on the proposal ref `refs/heads/sync/<run>/proposal/<branch>`; nothing is pushed |
| `verify` | escalation | sharukhan's checks on the proposal |
| `propose_description` | escalation | writes `PUBLISH/<n>.proposed`, linted |

Results are redacted (keys and tokens) and paginated.

## The upstream watcher and its events

```bash
sharukhan watch                  # poll every 900 s (default), record events, notify
sharukhan watch --interval 600   # at least 60
sharukhan watch --once           # one cycle
sharukhan events                 # the last 50 events
sharukhan events --new           # the open ones
sharukhan events ack 412         # handled
sharukhan events ignore 413
```

Branch heads come from `git ls-remote`; a move becomes one typed event in
`memory.db` (`upstream-moved`, `reference-ahead`, `pr-head-moved`,
`sync-needs-decision`, `escalation-proposed`, ...). `MC_NOTIFY` lists the
channels, comma-separated: `file:<path>` (default
`/root/photon-mc/events.log`), `ntfy:https://...`,
`gh-issue:<owner>/<repo>#<n>`. Nothing leaves the host unless a remote channel
is configured.

## Data files the automation reads

### `config/variants.conf`: installer variants and the common branches

```
[variant 2.8]          # the first variant is the default
fix/some-branch
[variant latest]
fix/some-branch
[common]
fix/check-spec-subrelease-aware
[excluded]
fix/experiment  # why it is in no variant (the reason is required)
```

`sharukhan variants` compares it with the fork's open PRs: every listed branch
must be an open PR head and every open PR on the release or `common` branch
must be covered: listed, excluded with a reason, or the parent of a listed
branch (a listed child carries its parent's commits).
`SHARUKHAN_VARIANTS` overrides the path.

### `config/check-prs.tsv`: which PR a check proves

One line per oracle check id followed by one or more PR labels, separated by
whitespace (`guest.selinux PR#31`, or `media.x PR#85 PR#86`; labels are
`PR#<n>` or `POI#<n>`). A `check_result` carries those labels, so a failure
reads as "PR#22 regressed". Comments are whole lines starting with `#`. `sharukhan doctor`
warns when a label names a PR that is no longer open. `SHARUKHAN_CHECK_PRS`
overrides the path.

### `memory.db` and `MEMORY.md`

```bash
sharukhan ingest                         # fold results/ into memory.db (idempotent)
sharukhan db render MEMORY.md            # the database as Markdown
sharukhan db render /path/memory.db out.md
```

The database is the system of record; `MEMORY.md` is a generated view.

### The embedded canister-equivalent patch

```bash
sharukhan canister-equivalent --check        # is the embedded patch current?
sharukhan canister-equivalent --out new.patch
```

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

## Configuration

### Paths, the VM and the network

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
| `MC_GUEST_PASSWORD` | **required, no default** — the root password of every VM the harness installs (or `MC_GUEST_PASSWORD_FILE`, below) |
| `SERIAL_LOG_PREFIX` | `serial0` |
| `MC_INSTALL_TIMEOUT_SEC` | `2400` |
| `MC_BOOT_TIMEOUT_SEC` | no effect: nothing reads it, a warning says so (installs use `MC_INSTALL_TIMEOUT_SEC`) |
| `MC_SSH_TIMEOUT_SEC` | no effect, as above |
| `MC_SAMPLE_SEC` | no effect, as above |
| `MC_START_TIMEOUT` | `240` |

```
SHARUKHAN_DB=/tmp/other.db sharukhan findings
```

### The settings file and the secret files

The services read `/etc/sharukhan/sharukhan.env` (written by
`sharukhan service install`); `env-isolated.sh` loads the same file for
commands run by hand. It holds `KEY="value"` lines and nothing secret. A
secret is a file named by a setting, owned by the reading user, mode 0600, in
a directory nobody else can write:

| Setting | Points to | Read by |
|---|---|---|
| `MC_GUEST_PASSWORD_FILE` | the guest root password | everything that installs or configures a guest, when `MC_GUEST_PASSWORD` is not set |
| `MC_ANTHROPIC_KEY_FILE` | the Anthropic API key | the escalation, before `ANTHROPIC_API_KEY` |

A test (`every_variable_the_code_reads_is_classified`) fails when the code
reads an environment variable that is neither a service setting, a secret
pointer, a secret nor named as something else, so a new setting cannot be
left out of the services by accident.

### Settings of the build, the fork and the sync

| Variable | Default | Meaning |
| --- | --- | --- |
| `MC_FORK` | `dcasota/photon` | the fork whose PRs are gated and synced |
| `MC_UPSTREAM` | `vmware/photon` | the upstream repository of the fork |
| `MC_FORK_INSTALLER` / `MC_UPSTREAM_INSTALLER` | `dcasota/photon-os-installer` / `vmware/photon-os-installer` | the same for the installer |
| `MC_INSTALLER_BRANCH` | `master` | the installer branch |
| `MC_GATE_REPO` | `/root/photon-mc/gate/photon.git` | the gate repository (bare) |
| `MC_AUTHOR` | the gate repository's git `user.name` and `user.email` | `Name <mail>` of rebased commits and changelog entries; with neither, a sync refuses |
| `MC_BUILDER` | `host` | `host` or `container`: where make and the spec tools run |
| `MC_BUILDER_SHARED_ROOT` | `/root/photon-mc/gate` | the shared bind mount of the builder container |
| `MC_BUILDER_DIR` | `/root/photon-mc/gate/builder` | the builder image's context |
| `MC_ISO_STORE` | none | where finished ISOs are moved; the cache keeps a link |
| `SHARUKHAN_VARIANTS` | `$SHARUKHAN_ROOT/config/variants.conf` | installer variants and common branches |
| `SHARUKHAN_CHECK_PRS` | `$SHARUKHAN_ROOT/config/check-prs.tsv` | check to PR attribution |
| `MC_FASTLOOP_ROWS` | `k03 c03` | rows of a sync's FASTLOOP (minimal ISOs of the default variant) |
| `MC_STAGED_ROWS` | `k11` | rows of a sync's STAGEVM |
| `MC_PUBLISH_DCASOTA` | `auto` | `auto`, `approve` or `preview` (see the sync chapter) |
| `MC_NOTIFY` | `file:/root/photon-mc/events.log` | notification channels |
| `SHARUKHAN_SYNC_QUIET` | `7200` | seconds a base must be quiet before `sync auto` starts a run |
| `SHARUKHAN_SYNC_EVERY` | `30min` | the sync timer's interval (service option) |
| `SHARUKHAN_WATCH_INTERVAL` | `900` | the watcher's interval in seconds (service option) |

The escalation's settings are in its own chapter.


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

## Troubleshooting

### Every ISO group is refused at once

Read the first `REFUSED` line; the others repeat it.

* **`... is missing or has no 'file' binary`** while `docker run --rm
  <composer image> sh -c 'command -v file'` works on the host: Docker's
  default bridge may be gone. `ip link show docker0` fails and the Docker
  journal shows `Failed to add veth... to bridge via netlink: Device does not
  exist`. Containers on `--network none` still work, which is why spec checks
  pass. Restarting Docker (`systemctl restart docker`) recreates `docker0`;
  containers with a restart policy come back by themselves.
* **`build-config.json has no photon-dist-tag`**: a tree sharukhan reads has
  no dist tag. The dist tag, the kernel directory and the branch are read
  from the tree, never assumed.

### The disk fills during a build

A full build needs tens of gigabytes; `run` checks the disk before it starts
a VM, but not other writers on the same disk. Stop the job before the disk is
full, find the writer, then restart:

```bash
df -h /
sharukhan stop --job 90
```

### `stop` and containers

In container mode a build runs inside `docker run`. Every container a job
starts carries the label `sharukhan.job=<id>`, and `sharukhan stop --job <id>`
stops those containers after the processes, saying which, if any, survived:

```bash
docker ps --filter label=sharukhan.job=90
```

### A manual gate after a stopped or failed build

```bash
sharukhan sync reset-trees                 # refuses edits no patch explains
sharukhan variant-patches
sharukhan run --all --allow-build
```

### Following a job

`sharukhan watch --job <id>` prints the job's state and follows its run log
until it ends (`--once` prints once). Without `--job`, `sharukhan watch` is
the upstream watcher (see its chapter).

```bash
sharukhan watch --job 90 --once      # state and the latest log lines
sharukhan watch --job 90             # follow until the job ends
sharukhan status                     # every job, and whether its process is alive
```

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
- **"Clean" is not clean at fuzz 0.** `patch` defaults to fuzz 2, rpm's
  `%autopatch` uses `--fuzz=0`. Five 6.12 FIPS patches applied "clean" to
  7.3-rc4 by default and failed at fuzz 0; every patch is judged on its exact
  parent at `--fuzz=0`, and a series is proven by replaying `%prep`.
- **A renamed Kconfig switch drops dependents silently.** 7.x replaced
  `CRYPTO_MANAGER_DISABLE_TESTS` (tests on unless set) with `CRYPTO_SELFTESTS`
  (off unless set), and `CRYPTO_FIPS` depends on it: `olddefconfig` dropped FIPS
  and its jitterentropy settings from Photon's config without an error.
- **Photon's SpecParser reads per-package macros by `Name:`.** A
  `%if 0%{?canister_build}` read before the `Name:` line sees no
  pkg-build-options macros, so the dependency graph demanded the canister in
  the very phase that builds it, while `rpmbuild` itself was right.
- **A harness must not lean on ambient state.** The cascade wrote the canister
  macros but never pointed `build-config.json` at them; `/root/common` still
  named the file from earlier runs, a fresh clone did not, and phase A built a
  canister consumer after seven hours.
- **`make pkgs=a,b` never creates the base sandbox.** After a purge removes
  `sandboxBase` every package fails with "special device overlay does not
  exist". The pre-build now builds each package by its own target.
- **A file walk must not follow a sandbox's mounts.** A failed package's sandbox
  keeps `/proc` mounted; a walk that followed it went through the whole host,
  `/mnt/c` included, and a build sat for half an hour in 9p reads between two
  attempts. Walks stay on their filesystem and skip `stage/photonroot`.
- **A changelog can move to a file the target lacks.** `branch-check` compared
  a spec with the same path only, so a collision in a changelog include passed
  (vmware/photon#1680). A path absent on a side is now compared with every
  changelog of the same package directory there.
- **A cache that fails open is worse than none.** The canister struct-layout
  plugin returned success with an empty database whenever its cache file was
  locked, so under `make -j` layouts could go unchecked. Found while porting the
  canister to 7.3; the 6.12 series carries the same code.
