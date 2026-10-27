# Package lifecycle

[← sharukhan overview](../../README.md)

**Who this is for:** Someone testing every package of a row: install, test and remove, with the policy behind each verdict.

## Package lifecycle: install, test and remove every package of a row

`--package-lifecycle` on `verify` or `run` goes past the vanilla install. After the read-only oracle
and harvest, for every package the row's own ISO offers, it installs the package, tests it by what
it ships, removes it, and proves the guest is back at its baseline. Design:
[ADR-0008](../../specs/adr/0008-package-lifecycle.md), contract:
[FRD-002](../../specs/features/package-lifecycle.md).

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

---

[← sharukhan overview](../../README.md)
