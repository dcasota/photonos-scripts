# ADR-0001 — `run`, `stop`, `watch`

Status: accepted, implemented
Date: 2026-09-01
Supersedes: the "Non-goals for this stage" paragraph of `specs/prd.md`

## Context

Eight ad-hoc bash drivers were written in one day to get the matrix through:

| driver | what it drove |
| --- | --- |
| `retest-stig.sh` | rebuild minimal/2.8, re-run k03 k04 |
| `rebuild-and-verify.sh` | rebuild minimal/2.8, re-run k01–k04 s01 s02 |
| `build-latest.sh` | build minimal/latest, run k05–k08 |
| `latest-rows.sh` | re-gate the minimal/latest media, run k05–k08 |
| `drive-matrix.sh` | reclaim k01 k02, run k03 k04 s01 s02 |
| `full-rows.sh` | build full/2.8 → k09–k12, build full/latest → k13–k16 |
| `finish-matrix.sh` | reuse both full ISOs → k09–k12, k05–k08, then build full/latest → k13–k16 |
| `k05-k08-after.sh` | wait for `full-rows.sh`'s completion marker, then k05–k08 |

They are eight copies of one program. Counting them:

| primitive | drivers carrying it |
| --- | --- |
| `gb()` / `avail_gb()` — `df -BG \| awk NR==2` | 8 of 8 |
| timestamped log file + `log()` prefix helper | 8 of 8 |
| sequential `for perm in …; do mc-run.sh --only "$perm"; done` | 8 of 8 |
| wait-for-idle `while pgrep -f 'mc-run\|mc-build-iso\|runPh5_normal'` | 7 of 8 |
| per-row disk gate (`C: < 20G → REFUSING; break`) | 7 of 8 |
| ISO media gate via `xorriso -osirrox on -indev … /RPMS` | 7 of 8 |
| pre-build disk gate (`/ < 25G → REFUSING`) | 6 of 8 |
| verdict scrape `grep -E "^  $perm: " "$LOG" \| tail -1` | 6 of 8 |
| `expected_poi()` — NEVR derived from the variant patch | 4 of 8 |
| NEVR **hardcoded** (`*2.9-2*`, `*2.1-10*`, `*2.8-6*`) | 3 of 8 |
| completion-marker chaining rather than idle polling | 1 of 8 |
| teardown-to-reclaim-space | 1 of 8 |

The last three rows are the interesting ones. The primitive that mattered most
was present in one driver out of eight, and the primitive that was got *wrong*
was present in three. `latest-rows.sh` exists solely because `build-latest.sh`
hardcoded `2.9-2` and the spec had moved to `2.9-3`, so a correct ISO would have
been rejected — and the file could not be edited in place because bash re-reads
a running script mid-execution. Copy-paste orchestration is how a fix reaches
four of eight call sites.

## Decision

Three commands. The dividing line is: **`run` decides and serialises, `watch`
observes, `stop` ends things — and none of the three builds anything.**

### What goes where

**`run`** — everything the drivers did *around* `mc-run.sh`:

- selection and refusal (`--only` / `--all`, unknown ids are an error, `mode=ui`
  rows are refused because they need a human, `c02` is refused because it needs
  aarch64 hardware)
- serialisation: refuse to start when another `sharukhan run` job is live, or
  when an `mc-run.sh` / `mc-build-iso.sh` / `runPh5_normal.sh` is in flight
- disk admission before the first row and again before every subsequent row
- ISO settle check before the first VM of a group
- ISO media gate, once per ISO group, with the expected NEVR **derived** from
  that variant's patch
- sequential per-row invocation of `mc-run.sh --only <id>`, verdict scraped from
  its output
- a `job` row so the work is findable after this process is gone

**`watch`** — read-only. Job state, liveness of the recorded pid, a live tail of
the job log, which matrix VMs are up, and free space. It is the replacement for
`tail -F` on four log files at once, and for `pgrep` loops.

**`stop`** — end a job the way a driver was ended, but correctly: signal the
recorded pid *and its descendants*, confirm they are gone, mark the job row.
It reports which matrix VMs are still powered on and does not touch them.

### What deliberately stays in bash

| stays in bash | why |
| --- | --- |
| `mc-build-iso.sh` (and `runPh5_normal.sh` under it) | an ISO build is a chroot toolchain run that takes 40 minutes to 11 hours, resets `SPECS` with git, purges stale RPMs from a shared stage, and stages a per-variant script directory. It is a build system. Reimplementing it in Rust buys nothing and risks the one artefact everything else is judged against. |
| `mc-gen-kickstart.sh`, `mc-create-vm.sh` | VMX generation is python3 string templating against a template file; kickstart generation is JSON assembly. Both are already deterministic and already tested by the ISO gate downstream. |
| `mc-install.sh` | it already contains `start_vm_verified`, the single most valuable line of the harness. Moving it would mean re-earning finding #30 in a second language. |
| `mc-verify.sh` / `lib/oracle.sh` | the oracle is ~40 SSH assertions against a guest. It is the thing under test's specification, and it changes more often than the orchestrator. |
| `mc-teardown.sh` | stash-not-delete semantics with UEFI NVRAM handling. `stop` calls nothing here; it *reports* what is still up and leaves the decision to the operator. |

`run` therefore refuses rather than builds: if the ISO a selected row needs is
not in the cache, the row is refused with the exact `mc-build-iso.sh` command
that would produce it. `mc-run.sh` would have built it silently, turning a
"2 minute" invocation into an 11-hour one with no warning. That is a deliberate
behaviour change and it is the only one.

## Commands and flags

```
run     --only <ids> | --all      which permutations (required, no default)
        --dry-run                 run every gate for real, execute nothing
        --keep                    passed through to mc-run.sh (skip teardown)
        --settle <sec>            minimum ISO age before the first VM (default 300)
        --wait-idle <sec>         wait this long for foreign work to finish (default 0)
        --log <path>              run log (default $MC_RUN_LOG_DIR/run-<stamp>.log)

stop    --job <id>                one job
        --all                     every job in state 'running'
        --dry-run                 say what would be signalled, signal nothing

watch   --job <id>                follow one job until it leaves 'running'
        --once                    one snapshot, no loop
        --interval <sec>          poll interval (default 15)
```

`--job <id>` is a **job table row id**. It is not `--jobs <n>`, the pre-existing
`status` flag for proposed VM parallelism. The names are unfortunately close;
`--jobs` was already documented and renaming it would break a published
interface, so both are kept and the difference is documented here and in the
README.

## Module layout

Existing modules are untouched. `config.rs` gains two fields.

```
src/main.rs      arg parsing + the five pre-existing commands (unchanged bodies)
src/config.rs    + mc_bin, run_log_dir
src/matrix.rs    unchanged
src/memory.rs    unchanged (read-only findings)
src/disk.rs      unchanged
src/vmware.rs    unchanged
src/report.rs    unchanged
src/proc.rs      NEW  process lookup that cannot match itself
src/job.rs       NEW  the job table, read/write
src/media.rs     NEW  expected NEVR, actual NEVR, the gate, the settle check
src/runner.rs    NEW  cmd_run / cmd_stop / cmd_watch
```

The five existing commands stay in `main.rs`. Moving them into `src/cmd/` would
be a pure refactor whose only possible outcome is a change to output nobody
asked for.

### Signatures

```rust
// proc.rs — lesson 2
pub struct Proc { pub pid: i32, pub cmdline: String }
pub fn matching(needles: &[&str]) -> Vec<Proc>;
pub fn descendants(root: i32) -> Vec<Proc>;
pub fn alive(pid: i32) -> bool;
pub fn looks_like_sharukhan(pid: i32) -> bool;
pub fn signal(pid: i32, sig: i32) -> bool;

// job.rs
pub struct Job { pub id: i64, pub kind: String, pub label: String,
                 pub pid: Option<i64>, pub state: String,
                 pub log_path: String, pub started_at: String,
                 pub finished_at: String }
pub fn open_rw(path: &Path) -> Result<Connection, String>;
pub fn start(c: &Connection, kind: &str, label: &str, pid: i32, log: &str) -> Result<i64, String>;
pub fn finish(c: &Connection, id: i64, state: &str) -> Result<(), String>;
pub fn get(c: &Connection, id: i64) -> Result<Option<Job>, String>;
pub fn list(c: &Connection, running_only: bool) -> Result<Vec<Job>, String>;

// media.rs — lessons 3 and 6
pub struct Gate { pub expected: String, pub actual: String, pub ok: bool }
pub fn expected_installer(variant_patch: &Path, photon_tree: &Path) -> Result<String, String>;
pub fn installer_on_media(iso: &Path) -> Result<String, String>;
pub fn gate(iso: &Path, variant_patch: &Path, photon_tree: &Path) -> Result<Gate, String>;
pub fn settled(iso: &Path, min_age_secs: u64) -> Result<u64, String>;

// runner.rs
pub struct RunOpts { pub only: Option<String>, pub all: bool, pub dry_run: bool,
                     pub keep: bool, pub settle: u64, pub wait_idle: u64,
                     pub log: Option<String> }
pub fn cmd_run(cfg: &Config, o: &RunOpts) -> Result<(), String>;
pub fn cmd_stop(cfg: &Config, job: Option<i64>, all: bool, dry: bool) -> Result<(), String>;
pub fn cmd_watch(cfg: &Config, job: Option<i64>, once: bool, interval: u64) -> Result<(), String>;
```

## How each hard-won lesson is encoded

1. **`vmrun`'s exit code is not evidence in either direction.** `run` never
   starts a VM — `mc-install.sh` does, and it already polls the inventory. What
   `run`, `stop` and `watch` do with `vmrun` is *ask*, never *conclude*:
   `vmware::running()` is the sole authority for whether a VM is up, and no
   command in this crate branches on a `vmrun` exit code.

2. **`pgrep -f` / `pkill -f` self-match.** `proc::matching` scans `/proc/*/cmdline`
   directly and excludes, in this order: our own pid; every ancestor up the
   `PPid` chain; and any process whose `argv[0]` basename equals ours. The bash
   form matched the `pgrep` inside the very `$(...)` that ran it, which is how a
   waiter looped forever and a `pkill` killed its own shell. A Rust process
   scanning `/proc` has no subshell to match, but a *second* `sharukhan` would
   still match a needle appearing in its own argv, so the argv[0] exclusion is
   not theoretical.

3. **Never trust an ISO without checking its contents.** `media::gate` runs
   `xorriso -osirrox on -indev <iso> -find /RPMS -name 'photon-os-installer-*.rpm'`
   and compares against `media::expected_installer`, which isolates the
   `SPECS/photon-os-installer/photon-os-installer.spec` hunk of
   `variant-patches/poi-<poi>.patch` before reading `+Version:`/`+Release:` —
   the patch touches ~28 specs, so an unisolated grep picks up whichever spec
   sorts last. Where the variant patch does not set `Version:` (poi-2.8 only
   bumps `Release:`), the version comes from `git show origin/5.0:` on the
   pristine tree, never from the working tree, which is whatever the last build
   left patched. **No NEVR is written down anywhere in this crate.** The gate is
   run once per ISO group and its result is refused or accepted for the whole
   group.

4. **Check disk before starting, not during.** `disk::admit(&VM_RUN, …)` is
   called before the first row and again before every subsequent row; a refusal
   stops the remaining rows rather than skipping one. This is exactly the
   drivers' `if [ "$(gb /mnt/c)" -lt 20 ]; then … break; fi`, which is why it is
   `break` and not `continue`: one row short of space means the next is too.

5. **Serialise properly.** Two gates, in order. First the `job` table: if any row
   is `state='running'` with a live pid that still looks like a `sharukhan`,
   `run` refuses and names the job id. That is a completion marker in a database,
   not an idle poll — the successor is chained to the predecessor's *record*, so
   two `run`s cannot both observe "idle" and both proceed. Second, foreign work:
   `proc::matching` for `mc-run.sh`, `mc-build-iso.sh`, `runPh5_normal.sh`, which
   catches a bash driver someone started by hand. `--wait-idle <sec>` bounds the
   wait; the default is 0, i.e. refuse immediately, because a CLI that blocks
   forever is the failure mode being fixed.

6. **Do not start a VM in the same breath as an ISO build finishing.**
   `media::settled` refuses while the ISO's mtime is younger than `--settle`
   seconds (default 300; finding #29 observed the same image unopenable at 0s and
   instant at 8 minutes) and additionally requires the size to be identical
   across two reads a second apart. Refuses — does not sleep — so the operator
   sees why.

7. **Evidence observed in one phase is authoritative.** The media gate is
   evaluated once per ISO group and recorded in the run log; per-row processing
   never re-derives it. The per-row verdict is scraped once from `mc-run.sh`'s
   own summary line and never recomputed. And `run` treats `mc-run.sh`'s exit
   code as informational: `mc-run.sh` ends with `mc_report_to_file`, so its rc
   reflects the last `tee`, not the verdict. The scraped summary is the evidence.

## Deliberately excluded

- **Building ISOs.** See above. `run` refuses a row whose ISO is absent and
  prints the `mc-build-iso.sh` line that would create it.
- **Parallel rows.** Every driver ran rows sequentially and said why: ISO builds
  share `$PHOTON_TREE/stage`, and C: cannot hold several installed VMs. `status`
  already computes a parallel limit; `run` does not use it. Implementing
  parallelism I have never observed working would be inventing orchestration.
- **Daemonising.** `run` is a foreground process. The drivers were backgrounded
  with `nohup … &` and so is this: `nohup sharukhan run --all &`. Writing a
  double-fork daemon with no dependencies, no logging framework and no way to
  test the failure paths here is how a job leaks. The `job` row makes the
  foreground process findable, which is all daemonising would have bought.
- **Stopping VMs.** `stop` signals processes only. A VM outlives its driver;
  killing it is `mc-teardown.sh`'s job, which has stash-not-delete and NVRAM
  semantics that must not be duplicated. More importantly this host runs
  `runner-2`, a production VM, and `spagat-smoke`. A `stop` that powered off VMs
  would eventually power off one of those. It prints what is up and stops there.
- **Reclaiming disk.** `drive-matrix.sh`'s double `mc-teardown.sh --purge` is
  destructive and appeared once. `run` refuses on low disk instead of freeing it;
  deleting to make room is a decision an operator should make.
- **Writing `run` / `permutation` / `check_result` rows.** Those tables are empty
  and `mc-verify.sh` writes the JSONL that `report` already reads. Writing a
  second, divergent copy of the results into SQLite from the orchestrator would
  create two sources of truth for the same verdict. Only `job` is written.
- **Operator prompting for `mode=ui` rows.** `mc-operator-card.sh` already emits
  the card. `run` refuses those rows and names the command.
- **`--all` meaning "everything".** `--all` selects the matrix and then refuses
  the `ui` and aarch64 rows individually, reporting each refusal. It never
  silently narrows.

## Limits, honestly

- `run` shells out to `mc-run.sh`. If `mission-control` moves or its flags
  change, `run` breaks. `MC_BIN` exists so the path is at least configurable.
- The pid recorded in `job` can be recycled by the kernel. `stop` guards by
  checking that the live pid's `argv[0]` is still a `sharukhan` before
  signalling, which is a strong guard but not a proof. A start-time comparison
  would be a proof; it needs a column the fixed schema does not have.
- `stop` kills the process tree it can see in `/proc` at the moment it looks. A
  child spawned in the microsecond after the scan survives. It re-scans after the
  grace period and reports anything still alive rather than claiming success.
- The settle check is a heuristic. Finding #29 recorded a failure at 0s and a
  success at ~8 minutes; there is no measurement in between, so 300s is a guess
  bounded by two observations, not a threshold anyone has derived.
- `run --dry-run` reads real ISOs and real disks, so its verdicts are real. It
  cannot tell you whether `mc-run.sh` would then succeed.
- Nothing here has been exercised against a full 16-row matrix run. It has been
  exercised against `--dry-run` on real media, and against a real background job
  for `watch` and `stop`. The README shows only that.
