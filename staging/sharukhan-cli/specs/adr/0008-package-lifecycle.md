# ADR-0008 — Package lifecycle: the row's own ISO as the repository, one guest, controls before verdicts

Status: accepted, implemented
Date: 2026-09-28
Feature: [FRD-002](../features/package-lifecycle.md) · Task: [002](../tasks/002-task-package-lifecycle.md)
Research: [`research/2026-09-11-guest-health-and-package-lifecycle.md`](../research/2026-09-11-guest-health-and-package-lifecycle.md) §2

## Context

The operator asked for an opt-in check that, for every package an ISO offers, installs it, tests it
by what it is (a daemon is enabled, started, stopped, disabled, with a clean journal; a CLI prints
its version without error), and uninstalls it - robustly, without hard-coded lists, without breaking
the guest the run depends on. The 2026-09-11 research measured the ground truth this rests on and
left open questions; the ones that decide the design were answered on a live k09 guest (full ISO,
2026-09-27) before any code was written:

| question (research §8) | measured answer |
|---|---|
| does `vmrun connectNamedDevice sata0:1` work here? | yes: rc 0 in 0.5 s, and the guest's `blkid /dev/sr0` then reports `LABEL="PHOTON_20260927" TYPE="iso9660"` - proven in the guest, not from the rc |
| are the media RPMs signed? | no: `rpm -qpi` shows `Signature : (none)` for every probed RPM |
| can tdnf use the medium without touching the guest's repo files? | yes: `--disablerepo=* --repofrompath=sharukhan-media,file:///run/sharukhan-media/RPMS --enablerepo=sharukhan-media` lists 1934 packages, and `-j` gives JSON for listings and for `--assumeno` transaction previews (rc 0, `{"Install":[...]}`; a conflicting one adds `"Remove":[...]`) |
| does the installed guest carry a sandbox tool? | no `setpriv`/`runuser`; but systemd 257 runs a transient unit with `DynamicUser`, `PrivateNetwork`, `ProtectSystem=strict`, ... and `systemd-run --wait --pipe` returns its streams and exit status (measured: uid 64696, only `lo`, `/usr` read-only, a 20 s sleep ended at `RuntimeMaxSec=10`) |
| what does `rpm -Va` say on a vanilla guest? | 210 lines, none a defect: %config edits, %ghost pyc files, `/proc` `/sys` modes, `/var/log/wtmp`, `/run/media/*` |
| do package scriptlets reload systemd? | not always: after `tdnf install chrony`, both its units reported `NeedDaemonReload=yes` |

## Decisions

### 1. Package source: the row's own ISO, reconnected (not a network repo, not a copy)

The VMX still names the ISO on `sata0:1`; install only lets the installer eject it. `vmrun
connectNamedDevice` reconnects it, the guest mounts it read-only (`ro,nodev,nosuid,noexec`) at
`/run/sharukhan-media`, and tdnf reads it through `--repofrompath` with every other repository
disabled - the guest's repo files are never edited. The repository is the media under test by
construction, and that is still verified three ways before anything installs: the VMX path equals the
row's cached ISO; the mounted medium's label equals the ISO's volume id (xorriso on the host); and
tdnf's listing equals the ISO's `/RPMS` file list **file for file** (`pkg.repo_is_media`, a control).
The medium is unmounted and disconnected at the end.

`--nogpgcheck` is required (unsigned local builds) and is recorded as `pkg.gpgcheck` with the reason;
the medium's identity is proven by the checks above instead of by signatures.

Alternatives: *photon-updates / packages.broadcom.com* tests somebody else's build and depends on
the network; *an HTTP repo from WSL2* is not reachable from the guest's NAT; *copying RPMS into the
guest* is 3.7 GB per full row and a second copy that could drift.

### 2. The package universe is derived from the media, never listed

Candidates are the distinct names tdnf lists from that repository (newest build per name), sorted.
`--packages` narrows (every name must exist on the media), `--pkg-limit` bounds, `--pkg-resume`
subtracts. No hand-curated case file: the research proposed one to keep runs comparable, but the
request is "all packages", and comparability comes from recording the media identity (volume id,
file list count) and the policy sha256 with every run instead.

### 3. What a package is follows from what it installs

The RPM header (`rpm -qp`, before install) and the rpm database (after) give each file's path, mode
and flags. Unit files directly in a system unit directory make a daemon; executables or links
directly in `/usr/bin /usr/sbin /bin /sbin` make a CLI; `lib*.so.*` directly in the library
directories make a library; otherwise data. A package may be several. Everything gets `rpm -V`.

### 4. One guest, isolation earned per package, never assumed

All packages run on the row's installed guest, one after another. Isolation is proven, not assumed:
before install, a `--assumeno` preview must contain only `Install` entries, all from the media
(anything that would remove, replace or obsolete a baseline package is a skip with the list);
after install the added set must equal the preview; after removal (previewed too: it may remove
only what was added) the package set must equal the baseline, file lists must be gone, no process
may run a removed file, no new failed unit, every baseline-active unit active again (restarted if a
`Conflicts=` stopped it). When the baseline cannot be restored the run **stops** - every later
verdict would be unattributable - and records the rest as not reached. A tdnf removal that fails
falls back to `rpm -e` of exactly the added set, then `--noscripts`, each attempt recorded.

The baseline is a file per guest (`pkglife-baseline-<machine-id>.txt`), written on the first run and
checked against the verify harvest of the same invocation. A later run on the same guest removes
what an interrupted run left behind (previewed) and refuses a guest that lost baseline packages.
Snapshots were rejected: none exist in the harness, `.vmsn` files are GB each on a nearly full
volume, and a reinstall of a row is 80-90 s when a guest does get poisoned.

### 5. Preinstalled packages are tested in place and never removed

`rpm -V`, CLI probes and library checks run as for any package; their units are **observed only**
(state, and err-priority journal entries of this boot recorded once before the run starts, so later
packages cannot pollute them). Removing or cycling them could take the guest's own sshd, network or
package manager with it.

### 6. Daemons: a documented plan per unit, a measured start, the journal of exactly the window

The plan table and the start-judgement table are in `src/pkglife/units.rs` and FRD-002 §4. The
decisions behind them:

- `systemctl start` blocks until the job completes and is bounded by `timeout` in the guest - the
  wait is measured, not a sleep. A started unit must then stay up for `stability_secs` (same
  MainPID, NRestarts, ActiveState).
- The journal window is taken by **cursor** (`journalctl -n 0 --show-cursor`, then
  `--after-cursor`), never by time, and read as JSON; entries of priority `err` or worse fail, with
  the lines reported. A second, unit-independent window per package catches errors the package
  causes elsewhere; only the harness's own `sharukhan-*` units are excluded from it.
- A condition-skipped unit is **skipped (condition)** with systemd's own sentence as evidence. A
  unit that fails because it needs configuration **fails**, with a heuristic hint quoting the journal
  line; only a reviewed `units.requires_config` entry turns that failure into a skip, and the
  failure evidence is still recorded. Nothing is silently passed.
- Templates, aliases and target/mount/automount/swap/slice/scope/device units are not started, with
  the reason. `RefuseManualStart=yes` is honoured.
- **Safety of the harness's session**: the unit that owns the port-22 listener is derived from its
  cgroup and protected, together with the reviewed `units.protected` list (journald, dbus, networkd,
  vmtoolsd...); a unit whose `Conflicts=` names an active protected unit is not started
  (openssh-socket's `sshd.socket`, `Conflicts=sshd.service`, measured). A unit ordered `Before=`
  `network-pre.target`/`network.target`/`network-online.target` (derived; nftables is, measured) or
  listed in `units.network_affecting` is started under a **dead-man switch**: a transient timer that
  stops it after `deadman_secs` is armed first, a NEW ssh connection (never the multiplexed one,
  which established-state rules keep alive) must succeed after the start, and only then is the timer
  disarmed. If the guest does not answer, the harness waits for the switch and proves the guest came
  back; if it does not, the run stops and says so.

### 7. CLIs: only a version query, only in a sandbox

Never a bare invocation (the policy loader refuses an empty probe); probes `--version`, `-V`, `-v`,
`version`, `-version` in that order, the first success ends the search. Each runs as a transient
systemd service: dynamic unprivileged user, no capabilities, private network (loopback only), no
devices, read-only root, private /tmp as working directory, `NoNewPrivileges`, `RestrictSUIDSGID`,
`@reboot @swap @mount @module @raw-io @clock @cpu-emulation` syscalls refused, tasks/memory/file-size
limits, `RuntimeMaxSec`, stdin at EOF. On top, a reviewed name denylist (`cli.never_execute`:
power-state, partitioning, mkfs, dd/shred, kill-family) is never executed at all, and
`cli.no_version_query` holds reviewed per-binary exceptions. A probe passes on exit 0, non-empty
output containing a version token, and no policy error marker on stderr.

### 8. Controls before verdicts

Each class of verdict has a control that must pass first, and a failed control disables exactly what
it protects: a line logged at err must come back from the journal query (else the run stops); a
transient unit that exits 3 after logging at err must be judged failed and its line found (else the
run stops); the probe sandbox must be unprivileged, offline and read-only, `/usr/bin/rpm` must pass
and GNU `false` (exit 1 even for `--version`) must fail (else CLI probes are skipped with the reason).
The controls are check rows `pkg.control.*`, flagged `is_control=1` at ingest.

### 9. Evidence and the memory database

Summary and control rows go into the verify run's own `checks-<stamp>.jsonl` (`pkg.*`, one
`pkg.life.<name>` per package), so the frozen line format is unchanged. The per-package evidence -
every step with measured detail, unit and CLI results, journal lines - goes to
`pkglife-<stamp>.jsonl` beside it, written as each package finishes, bounded per field and scrubbed
of the guest password. `ingest` loads it into `package_lifecycle` (replace, never append) with the
full record as JSON, and `v_package_lifecycle`.

### 10. Where it hangs: an option on `verify` and `run`

`--package-lifecycle` runs after the read-only oracle and harvest, so everything verify asserts about
the vanilla install is recorded before the first package touches the guest; the phase mutates the
guest and says so. It is refused on a guest whose verify failed (`--pkg-force-unverified` overrides,
recorded) and skipped on a row whose install did not finish. Resumability is `--pkg-resume` on the
same guest (machine-id) and policy (sha256); a bound is `--pkg-budget` (default 4 h).

## Consequences

- A full-ISO row offers ~1930 packages; at the measured per-package cost this is hours, so
  `--pkg-budget`, `--pkg-resume` and `--packages` are part of normal use, not debugging aids.
- The policy file is part of the result: a verdict names its sha256, and resume refuses to carry
  verdicts across a policy change.
- Boot-affecting packages (files under `/boot/`, `/lib/modules/`, `/usr/lib/modules/`) are skipped
  with the reason; testing them needs a reboot-capable design (research extension #1 §1.6) and is
  out of scope here.
- `units.requires_config` and `cli.no_version_query` start empty: entries are added only from
  observed failures, reviewed, with reasons.
