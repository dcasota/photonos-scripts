# sharukhan

A single standalone CLI for verifying Photon OS ISOs and the PRs that go into
them, across the permutation matrix in `ISO-PERMUTATION-MATRIX.md`.

The matrix has 34 rows spanning five axes — minimal/full ISO, installer 2.8 or
latest, with/without STIG, ext4/btrfs, kickstart or the interactive UI. Two of
those axes are decided when the ISO is built; the rest are injected per VM. So
34 permutations need only four ISOs.

Every command reports what it actually observed. Where a fact cannot be
established it says so rather than guessing — a harness that confidently
reports a wrong answer is worse than one that reports nothing.

## Status

Implemented and working: `doctor`, `plan`, `status`, `findings`, `report`.

Not implemented yet: driving installs (`run`), background job control
(`stop`, `watch`). Those still live in the bash harness under
`staging/mission-control`. This README documents only what runs today; nothing
below is aspirational.

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
  [ok  ] / (build stage)        48G free (97% used), needs 25G
  [ok  ] VM store               116G free (97% used), needs 20G
inputs
  [ok  ] variant patches        /root/photon-mc/variant-patches
  [ok  ] iso cache              minimal-poi2.8-prebuilt, minimal-poilatest-prebuilt
memory
  [ok  ] database               28 finding(s)

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
  minimal/2.8      cached

permutations: 3 (2 autonomous, 1 need an operator)
  ID    ISO      POI     STIG  FS     MODE  VARIANT    DOC
  k01   minimal  2.8     no    ext4   ks    none       works
  k03   minimal  2.8     yes   ext4   ks    stigpkgs   fails
  p01   minimal  2.8     no    ext4   ui    -          works
```

`cached` vs `must be built` is the difference between a two-minute run and an
hour, so check it before starting a batch:

```
$ sharukhan plan --only k09,k13
ISOs required (2):
  full/2.8         must be built
  full/latest      must be built
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
28 finding(s)

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

`EVIDENCE` names the exact result file each verdict came from. Result files are
timestamped and never overwritten, so a re-run cannot quietly replace the
evidence of the previous one.

Rows with no results say so rather than being omitted:

```
$ sharukhan report --only k09,k10
  k09   full     2.8     no    ext4   untested   not run  -                            -
  k10   full     2.8     no    btrfs  untested   not run  -                            -
```

## Typical session

```
sharukhan doctor                  # is the machine fit to run anything
sharukhan plan --only k01,k02     # what will run, is the ISO cached
sharukhan status                  # room to run it, and how many at once
#   ... run the permutations ...
sharukhan report --only k01,k02   # what happened, against the documented verdict
sharukhan findings                # what previous runs established
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
  row until it was fixed.
