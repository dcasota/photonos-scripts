# Research: vanilla-system health analysis and per-package lifecycle cases

| | |
|---|---|
| Status | **Research input.** Not a PRD, not an ADR, not approved for implementation. |
| Date | 2026-09-11 |
| Scope | Two proposed extensions to the permutation matrix: (1) analysing the logs of a vanilla installed guest for defects, (2) per-package install / test / reboot / uninstall cases. |
| Method | Read-only investigation of the harness, the matrix, memory.db, the harvested evidence tree, the builder's package lists, and the built media. Every measurement below was taken, not estimated. |
| Gate | Under `specs/README.md` the SDD workflow blocks implementation until a PRD merges. Both extensions need an FRD and at least one ADR first (baseline location; package-case isolation strategy). |

---

## 0. Ground truth established by this investigation

### The harness

| Fact | Evidence |
|---|---|
| CLI is a hand-rolled parser, **not clap** (`ARCHITECTURE.md` is wrong about this) | `src/main.rs:156 fn parse()`, `USAGE` const at `src/main.rs:42`, dispatch `match args.cmd.as_str()` at `src/main.rs:285` |
| `verify` is 218 lines of orchestration over `oracle.rs` (1229 lines) | `src/verify.rs:22 pub fn run()`, `src/phases.rs:483 cmd_verify` |
| The oracle emits **52 distinct `check_id`s** across 3411 rows; exactly **two** are log-health (`logs.dmesg_no_bug`, `logs.journal_err_lines`) | memory.db `SELECT DISTINCT check_id` |
| Harvest is a fixed 12-entry `const FILES` + 3 `/var/log` reads, all `g.run()` over ssh, scrubbed for the password | `src/oracle.rs:842 pub fn harvest()`, `FILES` at ~`:867` |
| The JSONL record format is **frozen by a test** - 7 fields, exact byte order | `src/evidence.rs:41 struct Record`, test `the_line_format_matches_the_stored_evidence` at `src/evidence.rs:194` asserts the literal line |
| `memory.rs` opens the DB **read-only** and only touches `finding`, with column discovery | `src/memory.rs:243 fn columns`, `SQLITE_OPEN_READ_ONLY` at `:239` |
| The only writer is `ingest.rs` (`open_rw` at `src/ingest.rs:69`) plus `job.rs`. Ingest **DELETEs then re-inserts** `check_result` per permutation | `src/ingest.rs:224` |
| `run` is strictly sequential; there is **no parallel dispatcher**, despite `specs/findings/2026-08-31-parallel-execution.md` proving 3 slots and `disk::max_parallel` computing them | `src/runner.rs:258-280`, `src/disk.rs:67` |
| **No VM snapshot support exists anywhere.** Every `snapshot` hit in `src/*.rs` is the `watch` job-table dump or the sans-snapshot build patch | `src/runner.rs:576` |
| Teardown stashes the whole `["vmdk","vmsn","vmsd","nvram","vmss"]` chain by rename; `--purge` deletes the stashes | `src/vm.rs:237-330`, `CHAIN` at `:267` |
| `install::run` already detaches the CD at `src/install.rs:330` -> `vm::detach_cdrom` flips `sata0:1.startConnected` TRUE->FALSE. **The ISO stays in the VMX**, only unconnected | `src/vm.rs:210` |
| `check_result` has **no severity, no category, no raw-payload column**. `detail` max length 299, mean 42. `is_control` is 0 on all 3411 rows - the negative-control machinery is declared and never populated, so `v_control_integrity` reports 0/0 for all 28 perm_ids | memory.db |
| `artifact` has **0 rows**; designed as path+sha256+note with both `run_id` and `permutation_id` FKs | memory.db |
| `run.finished_at` / `run.exit_code` are never written. `permutation.result` is a **free-text tally** (`"17 pass"`, `"1 fail"`), not the enum its DDL comment claims. 122 runs : 122 permutations | memory.db |
| No phase dimension exists anywhere in the schema | memory.db |

### Measured cost of one row

This invalidates the premise that "a reboot costs minutes".

```
/root/photon-mc/run-logs/run-20260910T160550Z.log   (c03, minimal, ks)
16:05:51 disk created + kickstart injected
16:05:53 VM confirmed running
16:06:43 leased under own hostname  -> install = 50s
16:07:01 37 checks, 18 pass         -> verify  = 18s
16:07:07 teardown --purge complete  -> teardown = 6s
                                        TOTAL   = 77s
```

k01 (`run-20260909T183213Z.log`): install 67s, verify 7s, teardown 4s. n03/n05 (`run-20260909T194914Z.log`): 68s/70s install.

**A complete install->verify->purge cycle is 75-90 seconds.** Guest boot alone is ~2s kernel->hostname-change (`journal-boot.txt`: `20:34:59 photon` -> `20:35:01 mc-k01`), so a reboot-and-reconnect is tens of seconds, not minutes.

### Measured vanilla noise floor

This is what makes extension #1 tractable.

| row | `journal-err.txt` lines | dmesg lines matching error/fail/warn | `systemctl --failed` |
|---|---|---|---|
| k01, k09, n01, s01 | 2 | 3 | 0 units |
| c01 | 3 | 4 | 0 units |
| k11 | 5 | 3 | 0 units |

The universal 2 are `piix4-poweroff 0000:00:07.3: failed to request PM IO registers: -16` and its `probe with driver piix4-poweroff failed with error -16`; dmesg adds `Warning: Processor Platform Limit event detected, but not handled.`

The **deltas are the interesting part**:

- k11 adds `audit: kauditd hold queue overflow`, `systemd-resolved[672]: JENTROPY-ERROR: algif_rng_open():135`, `ERROR: socket(...) failed ...('Address family not supported by protocol')`
- c01 adds `(sd-exec-[338]: /usr/lib/systemd/system-generators/cloud-init-generator failed with exit status 3.`

Today all of this collapses into one `Status::Info` row (`logs.journal_err_lines actual=2`) and *nothing reads it*. Three plausible real defects are sitting in the evidence tree unreported.

> Note added when relaying: the c01 line is the defect fixed by dcasota/photon#32 / vmware/photon#1676. The baseline should classify it as a known defect carrying that PR reference, which makes it the first worked example of the `pr` column being used as designed.

### Journald is persistent

`journal-boot.txt`: `Time spent on flushing to /var/log/journal/76c4dfd215c94d10b6a82662271511c3` and `System Journal (/var/log/journal/...) is 8M, max 2.9G`.

Therefore `journalctl --list-boots` and `journalctl -b -1` work across a reboot. Per-boot analysis and reboot-persistence testing are both possible **without a serial console** - findings #8/#21 block the *installer's* observability, not the installed system's.

### Packages

| Fact | Evidence |
|---|---|
| `/root/5.0/SPECS/` = 1017 package dirs, 1044 mainline specs (+744 in `90/`, 36 in `91/`), 1045 distinct `Name:` | enumeration |
| 118 mainline specs reference `%{_unitdir}`/`/lib/systemd/system` (215 tree-wide) - the only available service/library discriminator, and it is derived, not curated | enumeration |
| `packages_*.json` under `/root/common/common/data/` are **image selections, not a package universe**: `packages_minimal.json` = 7 entries, `packages_developer.json` = 21, `packages_appliance.json` = 68, `packages_installer_initrd.json` = 69. There is **no** `packages_full.json` / `packages_all.json` | enumeration |
| `build_install_options_all.json` = 4 menu entries -> `{title, packagelist_file, visible}`. It is a **menu**, not a list | file |
| `/root/common` is the authoritative common checkout (`/root/5.0/build-config.json` `common-branch-path: ../common`); `/root/5.0/common/data/` is a **stale 16-file copy** missing 5 files and differing in 6 | diff |
| **The installed system is 221 RPMs and identical on minimal and full ISOs** because both use `packagelist_file: packages.json`, and the ISO's `/packages.json` is `["linux","sudo","less","lvm2","linux-esx","minimal","initramfs"]` | `k01/logs-latest/rpm-qa.txt` == `k09/...` == 221 lines; `results/k01/kickstart.json` |
| Therefore **docker, cloud-init, iptables, python3 are already installed** on every row: `docker-29.5.3-2`, `cloud-init-25.1.3-11`, `iptables-1.8.13-3`, `python3-3.14.7-1` | `rpm-qa.txt` |
| The **full ISO is a complete offline repo**: `/RPMS/{x86_64,noarch,repodata}`, 1927 RPMs | `xorriso -find /RPMS -name '*.rpm' \| wc -l` |
| Availability on the full ISO: nginx OK, nodejs OK, openjdk11 OK, openjdk17 OK, open-iscsi OK, haproxy OK, mysql OK, containerd OK, etcd OK, kubernetes OK, rsyslog OK; postgresql NO, redis NO, helm NO, apache-tomcat NO (specs exist, not selected onto the media) | probe |
| `photon-iso.repo` ships `baseurl=file:///mnt/cdrom/RPMS`, **`enabled=0`**. Of 8 shipped repo files only `photon-updates.repo` is `enabled=1`, pointing at `https://packages.broadcom.com/...` | `/root/5.0/SPECS/photon-repos/photon-iso.repo` |
| `/root/5.0/stage/RPMS` is 17 GB / 3831 RPMs and **already carries `repodata/`** | filesystem |

### Disk, at time of writing

`/` 68 G free at 95%; `/mnt/c` (= `MC_VM_ROOT_WSL=/mnt/c/photon-mc/vm`, `src/config.rs:195`) 99 G free at 98%. `disk::VM_RUN` needs 5 G root / 20 G vmstore (`src/disk.rs:35`), so `max_parallel` = min(14/4, 99/20) = **3**. Results tree is 99 M total after 122 runs.

---

## 1. Extension #1 - vanilla-system health analysis

### 1.1 What is missing

`oracle::harvest` (`src/oracle.rs:842`) already collects nine-tenths of the raw material: `dmesg`, `journalctl -b`, `journalctl -p err -b`, `systemctl --failed`, `varlog-messages`, `varlog-installer.log`, `varlog-mkinitrd`, `cloud-init status --long`.

What is absent is **any analysis**: two derived checks, one of which (`logs.journal_err_lines`) is `Status::Info` and therefore structurally incapable of failing. Also absent: `systemd-analyze` output, `journalctl --list-boots`, degraded-state, long-running jobs, and a directory walk of `/var/log`.

So: **extend, do not replace.** `harvest` stays the collector; a new `src/health.rs` becomes the analyser that reads the harvest directory off disk, never re-querying the guest - that is the `verify.rs:1-7` doctrine and the cause of the false k01 FAIL(2).

### 1.2 Unit of analysis: per-boot, keyed per row

A "boot" is the right unit and the DB must carry it, because the two things this extension most needs to distinguish are already boot-scoped in the existing oracle's own comments:

- `guest.failed_units` detail says *"first boot may race the SELinux relabel; second boot must be clean"* (`src/oracle.rs:~370`)
- `guest.avc_denials` detail says *"non-zero on first boot is the documented relabel race"*

Both are today asserted against **boot 0 only**, which is exactly the boot where the expected-noise problem is worst. With persistent journald, harvest can take `journalctl --list-boots` then `journalctl -b <id>` per boot, and health verdicts become per-boot:

- **boot 0** (first boot after install): relabel race, cloud-init first-run, sshd keygen - the noisy boot. Findings recorded at `severity='info'` unless a rule marks them `boot0_also`.
- **boot 1** (a deliberate clean reboot, added to the vanilla flow): the gating boot. A failed unit here is a defect.

This is also precisely the machinery extension #2 needs for reboot-persistence, so build it once here.

### 1.3 The baseline / allowlist model

**Decision: baseline lives in the repo, not in memory.db.**

Rationale in the project's own terms - the baseline is an *input* that determines a verdict, and `memory.rs` opens the DB read-only while `ingest.rs` is derived-index-only; a rule set that changed the meaning of a verdict but lived in a mutable derived store would be unauditable and undiffable. It belongs beside `permutations.tsv` and the variant patches: version-controlled, reviewable in a PR, greppable. memory.db instead records **which baseline version produced which verdict**, so an old result stays attributable (the `specs/prd.md` "attributable months later" goal).

File: **`schema/health-baseline.json`** - JSON rather than TOML to avoid adding a dependency to a crate whose only deps are `rusqlite`/`serde`/`serde_json`.

```json
{
  "version": "1",
  "rules": [
    { "id": "piix4-poweroff-no-pm-io",
      "source": "dmesg|journal",
      "match": "piix4-poweroff 0000:00:07.3: failed to request PM IO registers: -16",
      "kind": "expected",
      "why": "VMware Workstation exposes no PIIX4 power-management IO block; the driver probes and gives up. Present on every row measured (k01 k09 k11 n01 s01 c01), zero functional effect.",
      "scope": { "hypervisor": "vmware-workstation" },
      "max_occurrences": 1 },

    { "id": "processor-platform-limit",
      "source": "dmesg",
      "match": "Warning: Processor Platform Limit event detected, but not handled.",
      "kind": "expected", "why": "...", "max_occurrences": 1 },

    { "id": "selinux-relabel-avc-boot0",
      "source": "journal",
      "match": "avc: *denied",
      "kind": "expected-on-boot0",
      "why": "The documented relabel race; oracle.rs guest.avc_denials already says so in prose.",
      "boots": [0] },

    { "id": "jentropy-algif-rng",
      "source": "journal",
      "match": "JENTROPY-ERROR: algif_rng_open",
      "kind": "defect", "severity": "medium",
      "why": "Observed only on k11 (full/2.8/stig). systemd-resolved cannot open the algif_rng socket; AF not supported by protocol. Unexplained - candidate finding, not baseline noise." },

    { "id": "cloud-init-generator-exit-3",
      "source": "journal|dmesg",
      "match": "/usr/lib/systemd/system-generators/cloud-init-generator failed with exit status 3",
      "kind": "defect", "severity": "medium",
      "pr": "dcasota/photon#32",
      "why": "Observed on c01. Fixed by the cloud-init 26.2-3 generator patch; keep the rule so a regression is named rather than rediscovered." }
  ],
  "gates": [
    { "id": "health.failed_units",     "source": "systemctl",   "expect": 0, "boots": [1] },
    { "id": "health.degraded",         "source": "systemctl",   "expect": "running", "boots": [1] },
    { "id": "health.kernel_taint",     "source": "proc",        "expect": 0 },
    { "id": "health.dmesg_no_bug",     "source": "dmesg",       "patterns": ["] BUG","] WARNING","] Oops","] Call Trace"], "expect": 0 },
    { "id": "health.unmatched_errors", "source": "journal-err", "expect": 0 }
  ]
}
```

The load-bearing rule is `health.unmatched_errors`: **every line in `journal-err.txt` must be claimed by exactly one rule; unclaimed lines must be 0.** That is the inverse of a denylist. It is what stops this becoming an always-red signal *and* stops it becoming vacuous. Measured feasibility: 2 lines to claim on 4 of 6 rows, 5 on the worst. A ~12-rule baseline, not a thousand-rule one.

Two anti-vacuity controls, which the project requires (`AGENTS.md`: "Every check that can be vacuous carries a negative control"; `is_control` is currently 0/3411, so this extension is the chance to populate it):

1. **`health.control_baseline_bites`** (`is_control=1`): a synthetic line known to be in the harvest must be matched by its rule. If the matcher is broken (empty file, wrong path, toybox-grep-class bug per finding #1), this control fails and the whole health verdict is reported *inconclusive*, not pass.
2. **`health.control_unmatched_detects`** (`is_control=1`): a line injected into the analyser's input that no rule claims must be reported as unmatched. Proves the unmatched counter is live.

All matching happens **in Rust over bytes read from the harvest files**, never by shelling to grep in the guest or on the host - finding #1 (`toybox-grep-no-dash-a`, blocker) makes grep-based counting untrustworthy, and the existing test `a_nul_bearing_serial_log_still_reports_its_errors` is the precedent.

### 1.4 What gets recorded, and where

Three layers, each in the place the existing design already intends:

1. **Raw harvest stays on disk**, unchanged, at `results/<perm>/logs-<stamp>/`. Add per-boot files: `journal-b0.txt`, `journal-b0-err.txt`, `journal-b1.txt`, `journal-b1-err.txt`, `boots.txt` (`journalctl --list-boots`), `systemd-analyze.txt` (`systemd-analyze; systemd-analyze blame | head -40; systemd-analyze critical-chain`), `systemctl-state.txt` (`systemctl is-system-running; systemctl list-units --state=failed,not-found --no-pager; systemctl list-jobs`), `varlog-tree.txt` (bounded `ls -la -R /var/log`), `kernel-taint.txt` (`cat /proc/sys/kernel/tainted`). All through the existing `FILES` mechanism with the existing `scrub()`.
2. **Gates land in `check_result` as ordinary rows**, namespace `health.*`, via the existing `Checks::check`/`expect`. No format change, no new writer; `report`/`ingest`/`v_permutation_report` keep working for free.
3. **Individual findings go in a new table** - `check_result.detail` caps at 299 chars and has no severity or category. See section 4.

`logs.journal_err_lines` **stays `Info`** (the raw count, comparable across 90 historical rows) and `health.unmatched_errors` is added as the gate. Converting the existing Info row into a gate would retroactively fail historical comparisons and would be exactly the "check that cannot fail becomes a check that always fails" swap. `logs.dmesg_no_bug` is likewise kept as-is - 90 rows of history - and not duplicated.

### 1.5 Where the code goes

- New `src/health.rs`:
  - `pub struct Baseline { version: String, rules: Vec<Rule>, gates: Vec<Gate> }`, `pub fn load(path:&Path) -> Result<Baseline,String>`
  - `pub struct Classified { matched: Vec<(RuleId, usize)>, unmatched: Vec<String>, defects: Vec<Defect> }`
  - `pub fn analyse(harvest:&Path, baseline:&Baseline, boot:u32) -> Result<Classified,String>`
  - `pub fn assert_into(c:&mut Checks, cl:&Classified, boot:u32)` - emits the `health.*` rows plus the two controls
- `src/oracle.rs`: extend `const FILES` (12 entries at `:867`) with the per-boot and systemd-state captures. `harvest`'s signature unchanged.
- `src/verify.rs`: after `oracle::harvest(...)` at `:199`, call `health::analyse` + `assert_into`. Second pass for boot 1 behind the flag.
- `src/config.rs`: one new field `health_baseline: PathBuf`, `var_or("MC_HEALTH_BASELINE", "<repo>/schema/health-baseline.json")`, following the `var_or` convention at `:195-245`.

### 1.6 Boot 1

New `--reboot` flag on `verify`, **off by default** - it changes the machine `verify` is inspecting, and the project's rule is that `verify` consumes what `install` proved.

Implementation: `g.run("systemctl reboot")` (fire-and-forget; ssh will drop), then poll `install::ssh_answers` - it exists at `src/install.rs:~124` and already checks the **SSH banner**, not the TCP handshake. Reuse it rather than writing a second waiter. Cost: measured guest boot is seconds; budget 90s with a hard timeout, and on timeout record `health.reboot` as `Fail` with the measured wait - never as a skip.

### 1.7 First increment

**Do the unmatched-errors classification against boot 0 only, over the harvests already on disk, with no guest interaction at all.** `health --replay <perm>` reads `results/<perm>/logs-latest/` and prints the classification.

A few hundred lines of Rust. No VM, no build, no `MC_GUEST_PASSWORD`. It immediately answers whether `JENTROPY-ERROR` is a defect, and it lets the baseline be tuned against 122 runs of real evidence before it ever gates anything.

---

## 2. Extension #2 - per-package install/test/reboot/uninstall cases

### 2.1 The three facts that reshape the brief

1. **"Install the package" is often a no-op.** docker, cloud-init, iptables, python3 are already in the 221-package installed set. For those the case is *present -> test -> uninstall -> analyse residue -> reinstall -> re-test*, and the interesting half is the **uninstall**.
2. **A fresh install costs 77-90 s**, measured. Per-case isolation by reinstall is cheap and **snapshots are not needed** - decisive given finding #28 (`recreate-moved-dir-under-vmware`, blocker) and `/mnt/c` at 98% with 99 G free; a `.vmsn` is 4 GB of RAM state each, and `vm::teardown`'s `CHAIN` already includes `vmsn`/`vmsd` precisely because snapshot deltas orphan themselves.
3. **The guest has no working package source out of the box.** Only `photon-updates.repo` is `enabled=1` and points at `packages.broadcom.com`; `photon-iso.repo` (`file:///mnt/cdrom/RPMS`) ships `enabled=0`, and `install.rs:330` disconnects the CD after install.

### 2.2 Where the package list comes from

**Not** `packages_*.json` - 2-69-entry image selections, no `packages_all.json`. **Not** `SPECS/` directly - 1044 specs, 301 of 1555 `%package` lines use `-n` so name derivation is wrong ~19% of the time, and most are libraries with nothing to smoke-test.

The correct source is the **intersection of what the media under test carries and what has a systemd unit**, both derivable with existing code:

- available set: `oracle::media_rpms(iso)` (`src/oracle.rs:37`) - already returns every RPM basename under `/RPMS`; 1927 full, 290 minimal
- installed set: `rpm-qa.txt`, or better the `poi-manifest.json` the harness already collects, which carries `packages` (220 entries) **and `systemd-units` (150 entries, `{unit_file,state,preset}`)** - a ready-made service discriminator with no spec parsing
- service candidates among the not-yet-installed: the 118 mainline specs matching `%{_unitdir}`, intersected with `media_rpms`

That intersection is small and should be curated **once, by hand**, into a data file. Do **not** generate the case list at runtime from SPECS: a generated list silently changes when upstream moves, and a case list that changes between runs makes two runs incomparable - the defect class of findings #33 and #17.

### 2.3 The repo problem, and its answer

| Option | Verdict |
|---|---|
| Enable `photon-updates`, let the guest reach `packages.broadcom.com` | **Wrong even if it works.** Tests Broadcom's published builds, not the media this row built. The harness exists to attribute failures to a PR. Finding #60 also records that those URLs went down for minutes this month. |
| HTTP repo served from WSL2 over `/root/5.0/stage/RPMS` | **Probably impossible here and untested.** WSL2 sits behind its own NAT; the guest reaches the Windows host on VMnet8, not the WSL2 instance. Would need `netsh portproxy` on Windows. |
| **Reconnect the ISO already in the VMX and enable `photon-iso`** | **This one.** `sata0:1` still holds the row's exact ISO (`src/vm.rs:210` only flipped `startConnected`); the ISO carries `/RPMS/repodata`; the guest already ships `photon-iso.repo` with the right `baseurl`; and the repo is then *by construction* the media under test. Zero new artifacts, zero extra disk. |

Mechanics: a `vm::attach_cdrom` mirroring `detach_cdrom`, then in the guest `mkdir -p /mnt/cdrom && mount -o ro /dev/sr0 /mnt/cdrom` and `tdnf --enablerepo=photon-iso --disablerepo=photon-updates ...`.

Two gates before any case runs, both loud refusals:

- `pkg.repo_reachable`: `tdnf --enablerepo=photon-iso repolist --all` must list `photon-iso` **enabled with a non-zero package count**.
- `pkg.repo_is_the_media_under_test` (`is_control=1`): the count from `tdnf repoquery` must equal `oracle::media_rpms(iso).len()` (1927/290). This stops a silently-empty mount making every install "succeed" from `photon-updates` instead.

`gpgcheck=1` in `photon-iso.repo` - if the locally built RPMs are unsigned this needs `--nogpgcheck`, recorded as a `pkg.gpgcheck` info row rather than hidden. **Unverified - see section 8.**

### 2.4 Where test definitions live

**A declarative JSON data file in the repo, executed by Rust, with guest-side steps as command lists.** Not shell shipped to the guest (re-creates finding #10 `editing-a-running-script` and exposes finding #1's toybox grep inside the guest); not Rust-per-package (1000 packages cannot be 1000 `fn`s, and a new package must not need a recompile).

`schema/package-cases.json`:

```json
{ "version": "1",
  "cases": [
    { "id": "nginx",
      "rpm": "nginx",
      "preinstalled": false,
      "requires_media": "full",
      "units": ["nginx.service"],
      "ports": [80],
      "install":   { "packages": ["nginx"] },
      "smoke": [
        { "id": "unit_enabled", "cmd": "systemctl is-enabled nginx", "expect_any": ["enabled","disabled"] },
        { "id": "starts",       "cmd": "systemctl start nginx && systemctl is-active nginx", "expect": "active" },
        { "id": "serves",       "cmd": "curl -sf -o /dev/null -w '%{http_code}' http://127.0.0.1/", "expect": "200" },
        { "id": "listens",      "cmd": "ss -ltnH 'sport = :80' | wc -l", "expect": "1" }
      ],
      "reboot_and_retest": ["starts","serves"],
      "uninstall": { "packages": ["nginx"] },
      "residue_allow": ["/var/log/nginx", "/var/cache/nginx"] },

    { "id": "docker",
      "rpm": "docker",
      "preinstalled": true,
      "requires_media": "minimal",
      "units": ["docker.service","docker.socket"],
      "smoke": [
        { "id": "starts", "cmd": "systemctl start docker && systemctl is-active docker", "expect": "active" },
        { "id": "info",   "cmd": "docker info --format '{{.ServerVersion}}'", "expect_nonempty": true },
        { "id": "runs",   "cmd": "docker run --rm photon:5.0 true; echo $?", "expect": "0", "needs_image": true }
      ],
      "reboot_and_retest": ["starts","info"],
      "uninstall": { "packages": ["docker","docker-engine","docker-cli"] },
      "reinstall_after": true,
      "residue_allow": ["/var/lib/docker"] }
  ]}
```

Notes that matter:

- `docker run` needs an image and the guest has no registry access - mark `needs_image: true` and **skip with a stated reason** rather than fail. Attributing a network-less host to a docker defect is the one thing `oracle::network`'s doc comment says the harness exists not to do.
- `uninstall.packages` must be **explicit**, not derived: the docker spec produces docker, docker-engine, docker-cli, docker-doc, docker-rootless-extras, and `tdnf remove docker` will or will not pull the others depending on Requires direction.
- `preinstalled: true` drives *test -> uninstall -> residue -> reinstall -> retest*; `false` drives *install -> test -> uninstall -> residue*.
- `requires_media` gates the case against the row's `iso_type`; nginx/nodejs/openjdk11/open-iscsi cannot run on a minimal row (290 RPMs) and must be **skipped with the reason**, per `matrix.rs::unrunnable_reason`'s precedent.

### 2.5 Fit to the permutation model: a new phase, not a permutation row

A package case is **not** a permutation row. Permutation identity is the ordinal (`identity.rs` derives MAC/UUID/IP from it; README: *"New matrix rows must be APPENDED, never inserted"*), so 200 package rows would consume 200 slots from a pool of 34 addresses and exhaust it immediately. It is also not a sub-phase of `verify`: `verify` is read-only by doctrine and a package case mutates the guest.

So: **a new phase `pkgtest`, and a new axis on the run, not on the matrix.**

```
pkgtest --id <perm> [--cases <ids>|--all-cases] [--reboot] [--dry-run] [--keep]
```

Ordering inside one row: `create-vm -> install -> verify -> pkgtest -> teardown`. A package failure on a guest whose `verify` failed is **refused, loudly**: "`verify` recorded N failing check(s); a package verdict on a guest that is not known-good is unattributable. Re-run verify, or pass `--force-unverified`."

`run` grows `--pkgtest[=<case ids>]`, off by default, inserting the phase between verify and teardown in `runner::run_row` (`src/runner.rs:~390`).

### 2.6 Scheduling hundreds of cases

| step | cost |
|---|---|
| `tdnf install` from ISO repo | 2-20 s (local file repo, no network) |
| smoke tests (3-6 ssh round trips) | 3-10 s |
| reboot + ssh-banner wait | 30-60 s |
| retest | 3-10 s |
| `tdnf remove` + residue diff | 5-15 s |
| **per case, with reboot** | **~60-120 s** |
| **per case, no reboot** | **~15-45 s** |

Three levers, in this order:

1. **Batch cases into one guest, not one guest per case.** One install (77 s) amortised over N cases. Isolation comes from the *residue check itself* - if it passes, the guest is provably back to baseline and the next case is clean. If it fails, the guest is poisoned: **stop the batch at that case, record why, reinstall.** Isolation becomes earned rather than asserted, and costs nothing in the common case.
2. **Make reboot a per-case property, batched.** Only `reboot_and_retest` cases need one, and *all pending reboot retests share a single reboot*: install+test every case in the batch, reboot once, then run every pending retest. Collapses N reboots into 1. This is the biggest saving, and it is why persistent journald matters - `journalctl -b -1` still holds the pre-reboot evidence for every case in the batch.
3. **Only then, parallelism.** `disk::max_parallel` already says 3 and a finding already proved it correct, but `runner.rs` has no dispatcher. Building one is separate, independently shippable work that triples throughput for both extensions. Do not entangle it with either.

Order of magnitude: 100 cases, batched 25-per-guest with one shared reboot per batch ~ 4 x (77 s install + 25 x 25 s + 60 s reboot + 25 x 8 s retest) ~ **4 x 15 min ~ 1 hour sequential**, ~20 min at 3-way parallelism. The naive one-guest-one-case-one-reboot design is ~4 h.

### 2.7 Failure attribution

Three-way plus an honest fourth, decided **before** the answer is seen (the `oracle::canister_expectation` pattern at `src/oracle.rs:713`), recorded as a column, not inferred by a reader:

| `cause` | Decided by |
|---|---|
| `package` | the case's gate failed **and** pre-flight controls passed **and** `verify` was clean **and** the RPM is present at the expected EVR |
| `harness` | a control failed, or ssh dropped, or the reboot never came back, or the residue baseline could not be taken |
| `host` | a known finding matches: no network for `needs_image`, no VLAN switch, FIPS key refusal (finding #53), aarch64 (finding #45). Recorded **with the finding id** |
| `unattributable` | anything else - explicitly, rather than defaulting to `package` |

`unattributable` existing as a value is the point. A harness that cannot tell whose fault it is must say so; finding #30's lesson generalised.

### 2.8 What uninstall-residue analysis checks

Baseline before the case, diff after the uninstall. Each dimension is a separate `check_result` row so a partial failure names itself:

| check | source | notes |
|---|---|---|
| `pkg.residue_files` | `rpm -ql <pkg>` taken **before** removal, plus the case's declared dirs | Scope it; a full-filesystem diff is permanently red from journald/tmpfiles churn |
| `pkg.residue_units` | `systemctl list-unit-files` before/after | Catches finding #55 (`photon-preset-enables-unmatched-units`, high): Photon 5.0 presets have no catch-all, so a new unit is ENABLED on every install. A leftover *enabled* unit file after removal is a real defect, and this is the first thing able to see it |
| `pkg.residue_users` | `getent passwd; getent group` before/after | RPM `%postun` rarely removes users; policy question, so `info` with the delta unless the case declares otherwise |
| `pkg.residue_config` | `%config` files still on disk | `.rpmsave`/`.rpmnew` expected; other survivors are not |
| `pkg.residue_ports` | `ss -ltunH` before/after | A listener surviving removal is a `%preun` that did not stop the unit |
| `pkg.health_delta` | **reuse `health::analyse` from extension #1** | The strongest signal in the whole extension: run the vanilla health analysis before and after and report *new* unmatched error lines. "nginx's removal broke systemd-resolved" is exactly the class neither extension finds alone |

That last row is why the two must be built in this order: **#1 is #2's oracle.**

---

## 3. CLI surface

Additive only; the hand-rolled parser (`src/main.rs:156`) takes new flags by adding arms to the `while let Some(f) = a.next()` match and new commands to the dispatch at `:285`. No dependency change.

```
INSPECT
    health              classify a harvested log set against the baseline
                        --id <perm> [--stamp <s>|--replay] [--baseline <file>]
                        Reads results/<perm>/logs-<stamp>/ ONLY. Touches no guest,
                        needs no MC_GUEST_PASSWORD, powers on nothing.
    cases               list the package cases, and which rows can run each
                        --iso-type <t> to see what a minimal row must skip

DRIVE / PHASES
    verify   ... [--reboot]          also reboot once and gate on the second boot
    pkgtest  --id <perm>             per-package install/test/reboot/uninstall
             [--cases <ids>] [--all-cases] [--reboot] [--batch <n>]
             [--dry-run] [--keep] [--force-unverified]
    run      ... [--pkgtest[=<ids>]] insert pkgtest between verify and teardown

OPTIONS
    --baseline <file>   health baseline; default schema/health-baseline.json
    --cases <ids>       comma-separated case ids (pkgtest)
    --all-cases         every case admissible for the row (pkgtest)
    --batch <n>         cases per guest before reinstall; default 25
    --reboot            add the gating second boot (verify, pkgtest)
    --force-unverified  run pkgtest on a guest whose verify failed; the reason is
                        recorded on every resulting row
```

Style compliance, checked against existing code:

- **Refusals explicit and loud.** `pkgtest` with neither `--cases` nor `--all-cases` errors with "it will not guess a selection", copying `runner.rs:53`. A minimal row asked for an nginx case prints `refused nginx  requires_media=full; this row's ISO carries 290 RPMs` - the `plan` refusal format at `runner.rs:70`.
- **`--dry-run` changes nothing.** Prints the resolved case list, the batch plan, the repo gate it *would* run; exits without powering on or ssh'ing - mirroring `runner.rs:212`.
- **Evidence over inference.** Every case step records measured stdout, never a bare pass/fail. `health` prints, per rule, the count it matched and the lines it did not claim.
- **No secret in argv.** Case commands go to `Guest::run`, which puts them in the ssh argv - so a case whose `cmd` contains a credential must be rejected at load time, with a test for it (the AC-13 pattern).

---

## 4. Schema changes

`src/memory.rs` is **not** broken: read-only, `finding` only, columns discovered via `PRAGMA table_info` (`src/memory.rs:243`) with a candidate-name fallback. `src/ingest.rs` is unaffected until taught to write the new tables. `schema/memory.sql` must be regenerated from the live DB, as its own header instructs.

```sql
-- ---- 1. health: one row per classified problem ---------------------------
-- check_result has no severity, no category, and detail is capped in practice
-- at 299 chars (measured max over 3411 rows). The verdict stays in
-- check_result as health.*; the EVIDENCE lands here.
CREATE TABLE IF NOT EXISTS health_finding (
    id              INTEGER PRIMARY KEY,
    permutation_id  INTEGER NOT NULL REFERENCES permutation(id),
    boot            INTEGER NOT NULL,        -- 0 = first boot after install, 1 = the gating reboot
    source          TEXT NOT NULL,           -- dmesg | journal | systemctl | varlog | proc
    rule_id         TEXT,                    -- baseline rule that claimed it; NULL = unclaimed
    severity        TEXT NOT NULL,           -- blocker | high | medium | low | info
    category        TEXT NOT NULL,           -- expected | defect | unknown
    unit            TEXT,                    -- systemd unit, when attributable
    occurrences     INTEGER NOT NULL DEFAULT 1,
    sample          TEXT NOT NULL,           -- one representative line, verbatim, redacted at write
    baseline_version TEXT NOT NULL,          -- which baseline produced this verdict
    recorded_at     TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_health_perm ON health_finding(permutation_id, boot);
CREATE INDEX IF NOT EXISTS idx_health_sev  ON health_finding(severity);
CREATE INDEX IF NOT EXISTS idx_health_rule ON health_finding(rule_id);

-- ---- 2. package cases ----------------------------------------------------
CREATE TABLE IF NOT EXISTS package_case (
    id              INTEGER PRIMARY KEY,
    permutation_id  INTEGER NOT NULL REFERENCES permutation(id),
    case_id         TEXT NOT NULL,
    rpm             TEXT NOT NULL,
    evr             TEXT,                    -- what was actually installed; NULL if never installed
    preinstalled    INTEGER NOT NULL DEFAULT 0,
    phase           TEXT NOT NULL,           -- install|smoke|reboot|retest|uninstall|residue|reinstall
    result          TEXT NOT NULL,           -- pass | fail | skip | refused
    cause           TEXT,                    -- package | harness | host | unattributable
    finding_id      INTEGER REFERENCES finding(id),   -- the host constraint, when cause='host'
    reason          TEXT,
    duration_sec    INTEGER,
    batch           INTEGER,                 -- which guest generation ran it
    recorded_at     TEXT NOT NULL,
    UNIQUE (permutation_id, case_id, phase, batch)
);
CREATE INDEX IF NOT EXISTS idx_case_perm   ON package_case(permutation_id);
CREATE INDEX IF NOT EXISTS idx_case_result ON package_case(result);
CREATE INDEX IF NOT EXISTS idx_case_cause  ON package_case(cause);

-- ---- 3. check_result gains a phase and a severity ------------------------
-- Additive with defaults, so all 3411 existing rows stay valid.
ALTER TABLE check_result ADD COLUMN phase    TEXT;   -- media|install|guest|health|pkg; NULL = legacy
ALTER TABLE check_result ADD COLUMN severity TEXT;   -- NULL = legacy, unrated

-- ---- 4. report views -----------------------------------------------------
CREATE VIEW IF NOT EXISTS v_health_report AS
SELECT p.perm_id, h.boot, h.severity, h.category,
       COUNT(*) AS findings, SUM(h.occurrences) AS occurrences,
       GROUP_CONCAT(DISTINCT COALESCE(h.rule_id,'(unclaimed)')) AS rules
FROM permutation p JOIN health_finding h ON h.permutation_id = p.id
GROUP BY p.perm_id, h.boot, h.severity, h.category;

CREATE VIEW IF NOT EXISTS v_package_report AS
SELECT p.perm_id, c.case_id, c.rpm, c.evr,
       SUM(c.result='fail') AS failed_phases,
       GROUP_CONCAT(DISTINCT c.cause) AS causes,
       SUM(COALESCE(c.duration_sec,0)) AS seconds
FROM permutation p JOIN package_case c ON c.permutation_id = p.id
GROUP BY p.perm_id, c.case_id;
```

**Things not to do, and why:**

- Do **not** add fields to the `evidence.rs` JSONL `Record` (`src/evidence.rs:41`). The test at `:194` asserts the literal line, and the format is frozen by the evidence already stored. `phase` and `severity` are derived *at ingest* from the `check_id` prefix - the namespace convention (`meta.`/`media.`/`install.`/`guest.`/`logs.`/`net.`, plus new `health.`/`pkg.`) is already load-bearing, and mapping it to a column is free and lossless.
- Do **not** overload `permutation.result`. It is free text (`"17 pass"`), and parsing it as an enum would be a new defect.
- `ingest.rs:224` DELETEs `check_result` per permutation before re-insert. The two new tables need the **same delete-then-insert discipline** or a re-ingest doubles them. **This is the single most likely bug in the whole plan.**
- `ingest.rs` derives everything from the JSONL files, so these richer rows need a **second evidence file** - `results/<perm>/health-<stamp>.jsonl` and `cases-<stamp>.jsonl`, same versioned/`-latest`-symlink discipline as `Checks::init` (`src/evidence.rs:70`) - and ingest gains a reader for each. Keeping the filesystem as source of truth and the DB as derived index is the design's core invariant (`ingest.rs:3-6`); do not break it by writing these tables directly from the phase.
- `run.finished_at` / `run.exit_code` are never written today. Leave that alone; fixing it is a separate change and conflating it muddies the diff.

---

## 5. Cost and capacity

| Work | Measured / estimated |
|---|---|
| One install->verify->purge row | **77-90 s measured** (3 run logs) |
| `health --replay` over one harvest | < 1 s, no VM |
| `verify --reboot` adds | 30-60 s |
| One package case, no reboot | 15-45 s |
| One package case, own reboot | 60-120 s |
| Batch of 25 cases, one shared reboot, one guest | ~13-16 min |
| 100 cases, sequential, batched | **~1 h** |
| 100 cases at 3-way parallel | **~20 min** |
| An ISO build, for comparison | 2 h 45 m minimal, 154 m full recompose |

Neither extension needs a new ISO.

| Disk item | Cost |
|---|---|
| Extra harvest files per row | current harvest is 334 KB/row (`journal-boot.txt` is 243 KB of it); a second boot roughly doubles it -> **~700 KB/row**. 122 runs x 700 KB ~ 85 MB against a 99 MB tree today. Negligible on `/` |
| New DB tables | thousands of short rows. Negligible |
| Package installs in the guest | inside the 32 GB thin `.vmdk`; `disk::VM_RUN.vmstore_gb = 20` already budgets for it |
| **Snapshots** | **zero, by design** |
| Second ISO copy for a repo | **zero** - the row's own ISO is reconnected |

Nothing raises the per-VM footprint, so `disk::max_parallel` is unchanged and both extensions are compatible with a parallel dispatcher whenever it is built. `disk::admit(&disk::VM_RUN, ...)` must be re-checked before each **batch reinstall**, exactly as `runner.rs:264` does before each row.

---

## 6. Delivery order

1. **`health --replay`** (no VM, no guest, no build). `src/health.rs` + `schema/health-baseline.json` + the `health` command. Classify the harvests already on disk. **Signal on day one:** a ruling on `JENTROPY-ERROR: algif_rng_open` (k11). Zero risk. *Merge alone.*
2. **`health` as a gate inside `verify`.** Extend `FILES`; emit `health.*` plus two `is_control=1` controls; add `health_finding`, the `phase`/`severity` columns, `v_health_report`; teach `ingest` the new JSONL. Re-run one cheap row (k01, 85 s) and confirm green on a known-good guest before trusting it. First time `is_control` is ever non-zero, which fixes `v_control_integrity` reporting 0/0.
3. **`verify --reboot` and boot-1 gating.** Reuses `install::ssh_answers`. Separates the relabel-race boot from the gating boot.
4. **Parallel dispatcher** (optional, independent, valuable to both). `runner::cmd_run` gains an N-slot scheduler bounded by `disk::max_parallel`, re-evaluating `disk::admit` per dispatch (finding #22: a thin disk grows *during* a run). The analysis already exists in `specs/findings/2026-08-31-parallel-execution.md`; there is no ADR yet.
5. **`pkgtest` skeleton: repo gate + one case.** `vm::attach_cdrom`, the `photon-iso` mount, both repo gates including the `is_control=1` media-count control, `schema/package-cases.json` with **nginx only**, `package_case` + `v_package_report`, `--dry-run` proving it changes nothing. Run against one full-ISO row (k09). Purpose: prove the repo mechanism, the riskiest unknown.
6. **Widen the case file; batching; residue analysis; `pkg.health_delta`.** Preinstalled cases (docker, iptables, python3, cloud-init) in test->uninstall->residue->reinstall order, then the full-ISO service set (open-iscsi, haproxy, rsyslog, containerd, etcd, nodejs, openjdk11/17).

Steps 1-3 are extension #1 complete. Steps 5-6 are extension #2. Step 4 belongs to neither and helps both.

---

## 7. Risks, and what to leave out of v1

### Extension #1

- **Baseline drift makes it always-red.** A kernel bump changes dmesg wording and every row goes red at once. Mitigation: add `health.baseline_coverage` reporting rules that matched **zero** times, as `Info`, so a dead rule is noticed before it is needed. A stale allowlist that silently stops matching is the failure mode of every allowlist ever written.
- **Substring matching over-claims.** `piix4-poweroff` is safe; a rule like `failed` is not. Rules must be anchored, full-line-ish, `max_occurrences`-bounded, and the unmatched-detects control must prove the counter still bites.
- **Boot 0 vs boot 1 could paper over a real first-boot defect.** Keeping boot-0 findings at `severity='info'` rather than dropping them is the mitigation - recorded, queryable, diffable, just not gating.
- **Leave out of v1:** parsing `systemd-analyze critical-chain` into a boot-time *regression* verdict. Collect the output; do not gate on timing. Boot timing on a 98%-full NTFS volume shared with Windows is not a controlled measurement, and a flaky timing gate would poison trust in the whole health signal. Also leave out `/var/log` content analysis beyond a bounded directory listing - the interesting content is in journald, and `varlog-messages` measured 0 bytes on every row inspected.

### Extension #2

- **The repo mechanism may not work.** The load-bearing unknown. `vmrun connectNamedDevice` may not exist or may not be honoured here (finding #30: the exit code is not evidence either way; finding #24: `nogui` simply does not work on this host, so vmrun capability cannot be assumed from documentation). Fallback - flip `startConnected` in the VMX and reboot - costs 60 s per guest generation. Prove it against the guest's own `mount` output, never against vmrun's rc.
- **`gpgcheck=1` against locally built RPMs.** If unsigned, every install fails in a way that looks like a package defect. Pre-flight `pkg.gpgcheck` as an `Info` row; make the `--nogpgcheck` decision explicit and recorded.
- **Batching couples cases.** Case 7 poisoning the guest makes 8-25 unattributable. Mitigation: stop at the first residue failure and reinstall; the batch order is fixed by the case file, so a poisoned batch is reproducible. Do **not** silently continue.
- **Residue diffing is intrinsically noisy** - journald rotation, tmpfiles, `/var/lib/rpm` churn, machine-id. Scoping to `rpm -ql <pkg>` plus declared dirs is what keeps it honest.
- **Uninstalling a preinstalled package can brick the guest.** `tdnf remove python3` takes tdnf itself, cloud-init and most of the minimal set. Mitigation: a mandatory `--assumeno`-style dry run first, refusing any case whose removal set intersects a hard-coded protected set (`tdnf`, `rpm`, `systemd`, `photon-release`, `linux-esx`, `filesystem`, `bash`, `openssh`), recording the removal set either way. Getting this wrong means a batch dies at case 3 with the guest unreachable.
- **Leave out of v1:** (a) any package needing network (docker image pulls, `npm install`, kubernetes) - skip with a stated reason, do not fake a registry; (b) multi-package interaction cases; (c) the 90/91 subrelease overlay variants; (d) automatic case generation from SPECS; (e) uninstall-residue for libraries (python3, openjdk) where "residue" has no agreed definition; (f) postgresql/redis/helm/apache-tomcat, which have specs but are **not on the ISO**.

---

## 8. Open questions

1. **Does `vmrun connectNamedDevice sata0:1` work on this host?** Not used anywhere in `src/`. Check: run it on a live guest, then verify **in the guest** with `lsblk`/`mount` - per finding #30, never from vmrun's rc. Fallback is the VMX flip + reboot.
2. **Are the ISO's RPMs signed** with the key at `/etc/pki/rpm-gpg/VMWARE-RPM-GPG-KEY-4096`? Check `rpm -qpi` on a locally built RPM for a Signature line.
3. **Can the guest reach `packages.broadcom.com` at all?** `photon-updates` is the one `enabled=1` repo, so if reachable, `tdnf install` may silently prefer it and test the wrong artifact. This is `pkg.repo_is_the_media_under_test`'s whole reason for existing.
4. **Which of the 118 unit-shipping specs are on each ISO, and which have a testable surface?** 11 of 16 probed names confirmed on the full ISO; the full intersection needs one pass.
5. **Does `docker.service` even start on a `linux-esx` guest with no overlay backing?** docker is preinstalled on all 221-package guests but no existing check touches it. One `systemctl start docker` answers it.
6. **Real reboot-to-ssh-ready latency.** Inferred as seconds from journal timestamps; never measured after a `systemctl reboot`. One measurement sets the `--reboot` timeout honestly instead of guessing 90 s.
7. **Does `/var/log/journal` survive a `--purge` teardown?** It should not - teardown stashes the vmdk chain and `--purge` deletes the stashes, so a purged row starts from a blank disk with no journal. That means **boot-1 analysis must happen inside the same row's lifetime**, before teardown. Believed correct from reading `src/vm.rs:237-330`; not tested.
8. **Process gate.** `specs/` is at Phase 1 with zero ADRs merged and no `specs/features/` or `specs/tasks/`. Under `specs/README.md` and `AGENTS.md`, both extensions are PM/Architect work before Developer work: each needs an FRD and at least one ADR (health baseline location; package-case isolation strategy).
9. **Does `next_step` #12** (`every-modification-has-an-unattended-row`) bind harness-only changes? Neither extension modifies Photon. Worth deciding rather than assuming.
