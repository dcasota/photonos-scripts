# FRD-002 — Package lifecycle (`verify|run --package-lifecycle`)

Status: implemented (2026-09-28)
Research: [`research/2026-09-11-guest-health-and-package-lifecycle.md`](../research/2026-09-11-guest-health-and-package-lifecycle.md) §2
Decision: [ADR-0008](../adr/0008-package-lifecycle.md) · Task: [002](../tasks/002-task-package-lifecycle.md)
Code: `src/pkglife/` (`mod`, `remote`, `parse`, `classify`, `policy`, `units`, `probe`, `record`,
`media`, `tests`), `src/guest.rs` (bounded, multiplexed ssh), `src/ingest.rs` (`package_lifecycle`)
Data: `schema/package-lifecycle-policy.json` (embedded), `schema/memory.sql`

## 1. Purpose

For any ISO row, as an option: loop over every package the row's media offers; install it, test it
by what it ships, uninstall it, and prove the guest is back at its baseline. A daemon is enabled,
started, must stay up, is stopped and disabled, and its journal for exactly that window must hold no
error; a CLI must print its version without error; a library must be in the linker cache; every
package must pass `rpm -V`. Preinstalled packages are tested in place and never removed.

## 2. Surface

```
sharukhan verify --id <perm> --package-lifecycle [--packages a,b] [--pkg-limit n]
                 [--pkg-budget sec] [--pkg-resume] [--pkg-policy file] [--pkg-force-unverified]
sharukhan run    --only <ids> --package-lifecycle [same options] [--keep]
```

`--pkg-*`/`--packages` without `--package-lifecycle`, or the option on any other command, is a
usage error (exit 64). `--pkg-limit 0` and `--pkg-budget 0` are refused.

## 3. Requirements

| ID | Requirement | Met by | Proven by |
|---|---|---|---|
| PL-1 | The package source is the row's own ISO; the VMX must name it, the mounted medium must carry its volume id, and tdnf's listing must equal the ISO's RPM files one for one, before anything installs. | `attach_media`, `run_attached` (`pkg.media_attached`, `pkg.repo_is_media`) | live run §5; `media::tests::*` |
| PL-2 | No other repository is consulted; the guest's repo files are not edited; every package to install must come from the media repo. | `Session::tdnf` (`--disablerepo=*`, `--repofrompath`), `fresh` | `tests::a_package_from_another_repository_is_refused` |
| PL-3 | Candidates are derived from the media (newest build per name, sorted); `--packages` names must exist on the media; `--pkg-limit` bounds. | `candidates`, `rpm_newer` | `tests::candidates_*`, `tests::evr_ordering` |
| PL-4 | Classification from the files a package installs: daemon / cli / library / data, possibly several. | `classify::classify` | `classify::tests::*` |
| PL-5 | A transaction that would remove, replace or obsolete an installed package is never run: skip, with the list. | `fresh` (preview `Txn::other_than`) | `tests::a_transaction_touching_installed_packages_is_never_run` |
| PL-6 | Boot-affecting packages (files under `boot_paths`) are skipped with the reason before resolution. | `fresh` | `tests::a_boot_affecting_package_is_skipped_before_resolution` |
| PL-7 | Unresolvable dependencies against the media fail the package with tdnf's words. | `fresh` | `tests::unresolvable_dependencies_are_a_package_failure` |
| PL-8 | The installed set must equal the preview; a baseline package lost to an install stops the run. | `fresh` | `tests::an_install_that_removes_a_baseline_package_stops_the_run` |
| PL-9 | `rpm -V`: missing files and size/digest/link changes of non-%config, non-%ghost files outside runtime trees fail; everything else is recorded; non-file lines fail. | `judge_verify` | `tests::rpm_verify_rule` |
| PL-10 | Libraries: every conventional soname in the linker cache (or at least one object when there is none). | `judge_ldcache` | `tests::linker_cache_rule` |
| PL-11 | Daemons: the plan table (§4.1) decides per unit before anything runs. | `units::plan` | `units::tests::planning_follows_the_documented_table`, `..._protected`, `firewalls_...` |
| PL-12 | Start is bounded and measured; judged by the start table (§4.2); must stay up `stability_secs`; stop leaves inactive with no main process; disable leaves disabled; preset-enabled units are recorded as such. | `units::cycle`, `judge_start`, `judge_stable`, `judge_stop` | `units::tests::start_judgement_*`, `stability_*`, `a_healthy_daemon_cycles_*` |
| PL-13 | The unit's journal between a cursor taken before enable and the end of the cycle holds no priority ≤ err entry; offending lines are reported. | `units::cycle` | `units::tests::a_daemon_that_fails_and_logs_errors_*` |
| PL-14 | Condition-skipped units are "skipped (condition)" with systemd's sentence; configuration-needing failures FAIL with a journal hint unless declared in `units.requires_config` (then skip, evidence kept). | `units::cycle` | `units::tests::a_condition_skipped_*`, `a_declared_requires_config_*` |
| PL-15 | The ssh listener's unit (derived) and `units.protected` are never started, stopped or conflicted. | `ssh_listener_unit`, `plan` | `units::tests::the_ssh_unit_is_derived_*`, `..._protected` |
| PL-16 | Network-affecting units (ordered before a network target, or listed) start only under a dead-man switch, with a NEW ssh connection as the proof; a cut session is waited out and the run stops if the guest does not return. | `units::cycle` | `units::tests::a_firewall_that_cuts_ssh_*`, `a_reachable_firewall_*` |
| PL-17 | CLIs: only version probes, never bare, in the systemd sandbox; the name denylist is never sent to the guest; pass = exit 0, output, version token, clean stderr; every attempt recorded; a hang is named. | `probe::*` | `probe::tests::*` |
| PL-18 | Removal is previewed and may remove only what was added; a failed tdnf removal falls back to `rpm -e` of exactly that set. | `Session::remove` | `tests::a_removal_that_would_take_more_*`, `a_failed_tdnf_removal_falls_back_*` |
| PL-19 | After removal: unit files unloaded, packaged files gone (%config may stay, recorded), no process runs a removed file, no new failed unit (cleared afterwards), baseline-active units active (restarted if needed, else stop). | `Session::residue` | `tests::files_left_behind_*`, `a_process_still_running_*`, `a_new_failed_unit_*`, `a_baseline_unit_the_package_stopped_*` |
| PL-20 | A journal window per package: any err-or-worse entry not from the harness's own units fails. | `journal_window`, `window_errors` | `tests::journal_errors_in_the_window_*` |
| PL-21 | Preinstalled packages: rpm -V, CLI and library tests in place; units observed only against this boot's errors captured before the run; never installed, removed, started or stopped. | `Session::preinstalled`, `units::observe` | `tests::preinstalled_packages_are_tested_in_place_*` |
| PL-22 | Controls: journal, failing-unit, sandbox + good/bad binary; each failure disables what it protects. | `control_*` | `tests::the_*_control_*` |
| PL-23 | Baseline per machine-id; first run cross-checked with the verify harvest; later runs remove leftovers of an interrupted run and refuse a guest that lost packages. | `run_attached` | `tests::the_harvest_comparison_speaks_plain_rpm_qa`; live run |
| PL-24 | Bounded: every guest command has a guest-side `timeout` and a host-side deadline; `--pkg-budget` ends the loop with the rest recorded as not reached. | `remote::guest_bounded`, `guest::run_command_bounded`, `run_attached` | `guest::tests::a_hung_command_is_killed_*`, `remote::tests::*` |
| PL-25 | Resumable: `--pkg-resume` carries only final verdicts from the same machine-id and policy sha256. | `record::carry` | `record::tests::records_round_trip_and_resume_*` |
| PL-26 | Every value reaching the guest is single-quoted (proven against a real shell); package and unit names are validated; no credential in argv; records scrubbed of the guest password. | `remote::sq`, `valid_*`, `scrub_record` | `remote::tests::quoted_arguments_survive_a_real_shell_unchanged`, `tests::the_password_never_reaches_a_record` |
| PL-27 | Evidence: `pkg.*` rows in the checks file; `pkglife-<stamp>.jsonl` per package; ingest into `package_lifecycle` (replace, not append) and `v_package_lifecycle`; `pkg.control.*` flagged `is_control`. | `record::Writer`, `ingest::ingest_lifecycle` | `ingest::tests::*` |
| PL-28 | The policy is strict, reviewed data: unknown fields refused, every rule has a reason, limits bounded, no bare probe; its sha256 is recorded. | `policy::Policy::parse` | `policy::tests::*` |

## 4. Classification tables

### 4.1 Unit plan (before anything runs)

| situation | plan |
|---|---|
| alias (symlink) | skip: tested under its real name |
| template `x@.service` | skip: needs an instance |
| target/mount/automount/swap/slice/scope/device | skip: global side effects |
| LoadState ≠ loaded | FAIL |
| protected (policy) or the ssh listener's unit | skip |
| `units.never_start` | skip, with the reviewed reason |
| RefuseManualStart=yes | skip |
| Conflicts= an active protected unit | skip |
| Before= a network ordering target, or `units.network_affecting` | cycle under dead-man switch |
| otherwise | cycle |

### 4.2 Start judgement

| observed after the bounded `systemctl start` | outcome |
|---|---|
| bound fired | FAIL |
| ConditionResult=no, not active | skip (condition), systemd's sentence as evidence |
| AssertResult=no | FAIL |
| failed / Result≠success | FAIL (or skip if declared `requires_config`) |
| service active/running; active/exited with RemainAfterExit | pass |
| Type=oneshot inactive, Result=success | pass |
| other service inactive | FAIL (does not stay up) |
| socket listening; timer/path waiting | pass |
| anything else | FAIL |

### 4.3 CLI probe

denylisted name → skip (never sent) · reviewed `no_version_query` → skip · file inspected: dangling →
FAIL, not executable by others → skip (mode), `#!` interpreter absent → FAIL (not run) · otherwise
probes in order inside the sandbox; pass on the first `exit status as reviewed (0) ∧ output ∧ version
token ∧ no stderr error marker`. No version: reviewed `cli.preconditions` words with no other defect →
skip; `cli.defect_signatures`, a crash by signal or an exec failure → FAIL; a probe accepted but
answered without a version → FAIL; option parser rejection, operand echo, privilege refusal or a
silent exit 0 → skip ("no version query", the line quoted); else FAIL with every attempt. Controls: a
SIGSEGV must be judged a crash and a script with an absent interpreter must fail.

## 5. Live verification

See Task 002 for the measured run on k09 (full ISO, 2026-09-28).
