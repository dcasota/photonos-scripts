# Task 002 — `--package-lifecycle`: install, test and remove every package of a row's media

Feature: [FRD-002](../features/package-lifecycle.md) · Decision: [ADR-0008](../adr/0008-package-lifecycle.md)
Status: done (2026-09-28)

| # | Step | Acceptance | Status |
|---|---|---|---|
| 1 | Bounded, multiplexed ssh with stdin and exit codes (`guest::run_bounded`, `run_command_bounded`) | `guest::tests::*` (deadline kill, stdin, capture limit, ControlPath only when multiplexed) | done |
| 2 | Shell quoting proven against a real shell; package/unit name grammar; guest-side `timeout` wrapper; scripted fake guest (`remote.rs`) | PL-24, PL-26 | done |
| 3 | Parsers for tdnf JSON, rpm -qa/-ql/-V, systemctl show/list JSON, journal cursor and JSON, ss, cgroup, /proc exes, ldconfig -p, from captured k09 output (`parse.rs`) | `parse::tests::*` | done |
| 4 | Classification from installed files (`classify.rs`) | PL-4 | done |
| 5 | Strict, fingerprinted, embedded policy with reasons (`policy.rs`, `schema/package-lifecycle-policy.json`) | PL-28 | done |
| 6 | Unit plan, start/stability/stop judgements, cycle with cursor-bounded journal, dead-man switch, observe-only for preinstalled units, ssh listener derivation (`units.rs`) | PL-11..PL-16 | done |
| 7 | Sandboxed version probes, denylist, reviewed overrides (`probe.rs`) | PL-17 | done |
| 8 | Records, writer, resume filter (`record.rs`) | PL-25, PL-27 | done |
| 9 | Media: VMX check, volume id, connect/disconnect (`media.rs`) | PL-1 | done |
| 10 | Orchestration: controls, baseline per machine-id, fresh and preinstalled flows, removal with fallback, residue, budget, abort (`mod.rs`) | PL-2..PL-10, PL-18..PL-23; `tests.rs` | done |
| 11 | CLI: `--package-lifecycle`, `--packages`, `--pkg-limit`, `--pkg-budget`, `--pkg-resume`, `--pkg-policy`, `--pkg-force-unverified` on `verify` and `run`; usage errors otherwise | `sharukhan --help`; live runs | done |
| 12 | Memory database: `package_lifecycle`, `v_package_lifecycle`, `is_control` for `pkg.control.*`; `schema/memory.sql` mirrors the DDL | `ingest::tests::*` | done |
| 13 | Gates: tests, clippy clean for new/changed code, rustfmt on touched hunks, coverage ≥ 80 % of new code | see below | done |
| 14 | Live proof on a real guest | see below | done |

## Found by the live runs and fixed before completion

- tdnf's JSON omits the epoch rpm reports (nginx `1:1.30.4-2.ph5`): identities are now
  name-version-release.arch on both sides; baseline files written before are read epoch-free.
  The harness had failed closed on it (it stopped the run rather than removing anything).
- `rpm -qa` prints gpg-pubkey pseudo-packages without an architecture; the harvest cross-check
  now renders them the same way, and a mismatch names the differing entries.
- A bus-activated service that exits when idle (systemd-timedated) was reported as "stopped by the
  package": the baseline of units that must stay up is now the ENABLED active units plus the
  protected ones; a unit stopped through a declared `Conflicts=` of a unit under test (iptables by
  nftables) is restarted and recorded as information, an undeclared stop still fails.
- `DynamicUser=` uids are unknown to Photon's files-only NSS, which made crontab refuse to run; the
  probe sandbox uses the `nobody` account with every other restriction unchanged.
- 7-Zip has no version switch; the reviewed `cli.version_query` entry uses its `i` command, verified
  in the sandbox first.
- `systemctl show` refuses a template name, so openssh-socket's `sshd@.service` was marked
  unreadable: template/alias/unit-type decisions are now made before any property is read
  (`units::plan_static`).

## Gates (2026-09-28)

| gate | measured |
|---|---|
| `cargo test` | 496 passed, 0 failed, 1 ignored (pre-existing) - 109 of them in `pkglife` |
| `cargo clippy --all-targets` | 0 warnings in `src/pkglife/`, `src/guest.rs`, `src/ingest.rs` and the changed hunks of `main.rs`, `verify.rs`, `runner.rs`, `phases.rs` (pre-existing warnings elsewhere untouched) |
| `rustfmt --edition 2021` | clean for every new file and every changed hunk; pre-existing drift in `build.rs`, `kickstart.rs`, `media.rs`, `runner.rs`, `verify.rs` and `main.rs`'s module order left alone |
| coverage (cargo-llvm-cov, rustup 1.97) | `src/pkglife/` 85.9 % of lines (classify 98, parse 98, policy 99, probe 97, record 96, remote 93, units 87, media 83, mod 75 - the untested remainder of `mod.rs` is the host-side `run`/`attach_media`/`detach_media`, proven live) |

## Live runs (k09, full ISO `PHOTON_20260927`, 1934 RPMs, 2026-09-28)

| run | selection | result |
|---|---|---|
| 1 | 14 packages | stopped at the baseline cross-check: gpg-pubkey rendering (fixed); nothing installed |
| 2 | 14 packages | 2 pass, 7 fail, 1 skip, 4 not reached: stopped closed on nginx's epoch (fixed); findings timedated/conflicts, DynamicUser, 7-Zip (fixed) |
| 3 | 14 packages | 7 pass, 6 fail, 1 skip; baseline restored (218); media detached. Fails: jq (prints `jq-` without version - a real defect), no-version tools run-parts, memcached-tool, strace-log-merge, rpm2cpio/rpm2archive/gendiff/rpmsort, and sshd@.service (fixed) |
| 4 | openssh-socket, tree | 2 pass (sshd.socket skipped as protected, sshd@.service as template) |
| 5 | + libyaml, `--pkg-resume` | 2 carried over, 1 tested, 3 pass; baseline restored |

`sharukhan ingest` then reported 33 package lifecycle records; `v_package_lifecycle` holds them and
the three `pkg.control.*` rows carry `is_control=1`. The VM was torn down with `sharukhan teardown
--id k09`.

Not proven live: the `run --package-lifecycle` path (a reinstall) - a foreign build started on the
host before the last run, and the harness rule is not to start VMs then. Its wiring is the same
`verify::run` call with the options passed through, and `run --dry-run` prints the phase.
