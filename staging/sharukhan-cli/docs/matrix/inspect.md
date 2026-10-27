# Running the matrix: doctor, plan, status, findings, report

[← sharukhan overview](../../README.md)

**Who this is for:** Someone about to run the permutation matrix: checking the host and seeing what would run before anything is built.

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

---

[← sharukhan overview](../../README.md)
