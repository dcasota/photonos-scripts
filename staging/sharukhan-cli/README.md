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

## Quick start

On a host with VMware Workstation, docker and a logged-in `gh` (details in
[Getting started](docs/getting-started.md)):

```bash
cargo build --release                       # the binary is target/release/sharukhan
read -rs MC_GUEST_PASSWORD; export MC_GUEST_PASSWORD   # the lab VMs' root password, typed, never echoed
nsenter --target 1 --mount -- \
  ./target/release/sharukhan service install --guest-password-from-env
set -a; . /etc/sharukhan/sharukhan.env; set +a   # the services' settings, for commands run by hand
S=/usr/local/libexec/sharukhan/sharukhan          # the installed binary (not on PATH)
$S doctor                                         # is the host fit to build and run anything
$S plan --only k03                                # what would run, and which ISO it needs
$S run --only k03 --allow-build                   # build the ISO if needed, install, verify
```

## Documentation

**Start here**

- [Getting started](docs/getting-started.md) - build sharukhan, install the host services, a normal day
- [Configuration](docs/configuration.md) - every setting, the settings file, secret files, the directory layout
- [Troubleshooting](docs/troubleshooting.md) - refused ISO groups, a full disk, stopped jobs

**Running the permutation matrix**

- [doctor, plan, status, findings, report](docs/matrix/inspect.md) - check the host, see what would run
- [run](docs/matrix/running.md) - drive permutations end to end
- [jobs, stop, watch](docs/matrix/jobs.md) - follow and end a job
- [Package lifecycle](docs/matrix/package-lifecycle.md) - install, test and remove every package of a row
- [The network axis](docs/matrix/network-axis.md) - the n01-n05 rows and what this host cannot test

**Building ISOs**

- [Build mode](docs/builds/build-mode.md) - how sharukhan builds an ISO, and why one cascade
- [Remaster mode](docs/builds/remaster-azure.md) - an Azure variant of an existing ISO
- [Kernel wrappers](docs/builds/kernel-wrappers.md) - a build wrapper for a kernel.org kernel
- [Kernel-profile builds](docs/builds/kernel-profiles.md) - `--kernel`
- [Example: a kernel.org kernel to a tested ISO](docs/examples/kernel-iso.md) - from scratch, with `examples/kernel-iso.sh`

**Keeping the fork's PRs current**

- [sync](docs/automation/sync.md) - the state machine, decisions, descriptions, the upstream stage
- [The escalation](docs/automation/escalation.md) - budgets, confinement, the MCP server
- [The watcher and its events](docs/automation/watcher-events.md) - `events.log` and notifications
- [Data files](docs/automation/data-files.md) - `variants.conf`, `check-prs.tsv`, `memory.db`

**Background**

- [Things learned the hard way](docs/lessons-learned.md) - the failures that shaped sharukhan
- [Architecture](ARCHITECTURE.md) - why one binary, modules, the memory database
- [Specifications](specs/README.md) - PRD, ADRs, features, findings
- [Archive](archive/README.md) - superseded tooling kept for provenance

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

## Moved sections

This README used to hold all of the documentation. Each of its former
sections now lives in the file named below; the anchors are kept here so
links into the old README still lead to the right page.

| Former section | Now in |
|---|---|
| <a name="build"></a>Build | [docs/getting-started.md](docs/getting-started.md#build) |
| <a name="installing-the-host-services-sharukhan-service"></a>Installing the host services: `sharukhan service` | [docs/getting-started.md](docs/getting-started.md#installing-the-host-services-sharukhan-service) |
| <a name="what-gets-installed"></a>&nbsp;&nbsp;&nbsp;&nbsp;What gets installed | [docs/getting-started.md](docs/getting-started.md#what-gets-installed) |
| <a name="install-or-update"></a>&nbsp;&nbsp;&nbsp;&nbsp;Install or update | [docs/getting-started.md](docs/getting-started.md#install-or-update) |
| <a name="check-service-status"></a>&nbsp;&nbsp;&nbsp;&nbsp;Check: `service status` | [docs/getting-started.md](docs/getting-started.md#check-service-status) |
| <a name="remove-service-remove"></a>&nbsp;&nbsp;&nbsp;&nbsp;Remove: `service remove` | [docs/getting-started.md](docs/getting-started.md#remove-service-remove) |
| <a name="commands-run-by-hand-use-the-same-settings"></a>&nbsp;&nbsp;&nbsp;&nbsp;Commands run by hand use the same settings | [docs/getting-started.md](docs/getting-started.md#commands-run-by-hand-use-the-same-settings) |
| <a name="when-the-timed-sync-is-needed-and-when-not"></a>&nbsp;&nbsp;&nbsp;&nbsp;When the timed sync is needed, and when not | [docs/getting-started.md](docs/getting-started.md#when-the-timed-sync-is-needed-and-when-not) |
| <a name="typical-session"></a>Typical session | [docs/getting-started.md](docs/getting-started.md#typical-session) |
| <a name="a-gate-run-by-hand"></a>&nbsp;&nbsp;&nbsp;&nbsp;A gate run by hand | [docs/getting-started.md](docs/getting-started.md#a-gate-run-by-hand) |
| <a name="a-day-with-the-automation"></a>&nbsp;&nbsp;&nbsp;&nbsp;A day with the automation | [docs/getting-started.md](docs/getting-started.md#a-day-with-the-automation) |
| <a name="running-the-permutation-matrix-commands"></a>Running the permutation matrix: commands | [docs/matrix/inspect.md](docs/matrix/inspect.md#running-the-permutation-matrix-commands) |
| <a name="doctor--check-the-environment-before-anything-is-built-or-run"></a>&nbsp;&nbsp;&nbsp;&nbsp;`doctor` — check the environment before anything is built or run | [docs/matrix/inspect.md](docs/matrix/inspect.md#doctor--check-the-environment-before-anything-is-built-or-run) |
| <a name="plan--what-would-run-and-what-has-to-be-built-first"></a>&nbsp;&nbsp;&nbsp;&nbsp;`plan` — what would run, and what has to be built first | [docs/matrix/inspect.md](docs/matrix/inspect.md#plan--what-would-run-and-what-has-to-be-built-first) |
| <a name="status--vms-disk-and-how-much-parallelism-that-allows"></a>&nbsp;&nbsp;&nbsp;&nbsp;`status` — VMs, disk, and how much parallelism that allows | [docs/matrix/inspect.md](docs/matrix/inspect.md#status--vms-disk-and-how-much-parallelism-that-allows) |
| <a name="findings--what-previous-runs-established"></a>&nbsp;&nbsp;&nbsp;&nbsp;`findings` — what previous runs established | [docs/matrix/inspect.md](docs/matrix/inspect.md#findings--what-previous-runs-established) |
| <a name="report--results-of-the-last-run-of-each-permutation"></a>&nbsp;&nbsp;&nbsp;&nbsp;`report` — results of the last run of each permutation | [docs/matrix/inspect.md](docs/matrix/inspect.md#report--results-of-the-last-run-of-each-permutation) |
| <a name="run--drive-permutations-end-to-end-sequentially"></a>&nbsp;&nbsp;&nbsp;&nbsp;`run` — drive permutations end to end, sequentially | [docs/matrix/running.md](docs/matrix/running.md#run--drive-permutations-end-to-end-sequentially) |
| <a name="stop--end-a-job-and-its-process-tree"></a>&nbsp;&nbsp;&nbsp;&nbsp;`stop` — end a job and its process tree | [docs/matrix/jobs.md](docs/matrix/jobs.md#stop--end-a-job-and-its-process-tree) |
| <a name="watch--what-is-running-and-follow-it"></a>&nbsp;&nbsp;&nbsp;&nbsp;`watch` — what is running, and follow it | [docs/matrix/jobs.md](docs/matrix/jobs.md#watch--what-is-running-and-follow-it) |
| <a name="the-state-the-job-table-exists-to-survive"></a>&nbsp;&nbsp;&nbsp;&nbsp;The state the job table exists to survive | [docs/matrix/jobs.md](docs/matrix/jobs.md#the-state-the-job-table-exists-to-survive) |
| <a name="one-phase-at-a-time"></a>&nbsp;&nbsp;&nbsp;&nbsp;One phase at a time | [docs/matrix/jobs.md](docs/matrix/jobs.md#one-phase-at-a-time) |
| <a name="package-lifecycle-install-test-and-remove-every-package-of-a-row"></a>Package lifecycle: install, test and remove every package of a row | [docs/matrix/package-lifecycle.md](docs/matrix/package-lifecycle.md#package-lifecycle-install-test-and-remove-every-package-of-a-row) |
| <a name="build-mode-sharukhan-builds-the-iso-itself"></a>Build mode: sharukhan builds the ISO itself | [docs/builds/build-mode.md](docs/builds/build-mode.md#build-mode-sharukhan-builds-the-iso-itself) |
| <a name="two-trees-and-why-that-matters"></a>&nbsp;&nbsp;&nbsp;&nbsp;Two trees, and why that matters | [docs/builds/build-mode.md](docs/builds/build-mode.md#two-trees-and-why-that-matters) |
| <a name="the-common-tree-must-hold-only-the-builds-own-edits"></a>&nbsp;&nbsp;&nbsp;&nbsp;The common tree must hold only the build's own edits | [docs/builds/build-mode.md](docs/builds/build-mode.md#the-common-tree-must-hold-only-the-builds-own-edits) |
| <a name="test-only-changes-are-compiled-in"></a>&nbsp;&nbsp;&nbsp;&nbsp;Test-only changes are compiled in | [docs/builds/build-mode.md](docs/builds/build-mode.md#test-only-changes-are-compiled-in) |
| <a name="the-canister-question-in-the-order-it-is-asked"></a>&nbsp;&nbsp;&nbsp;&nbsp;The canister question, in the order it is asked | [docs/builds/build-mode.md](docs/builds/build-mode.md#the-canister-question-in-the-order-it-is-asked) |
| <a name="one-build-not-two"></a>&nbsp;&nbsp;&nbsp;&nbsp;One build, not two | [docs/builds/build-mode.md](docs/builds/build-mode.md#one-build-not-two) |
| <a name="the-embedded-patch-pins-release-numbers-and-50-moves"></a>&nbsp;&nbsp;&nbsp;&nbsp;The embedded patch pins Release numbers, and 5.0 moves | [docs/builds/build-mode.md](docs/builds/build-mode.md#the-embedded-patch-pins-release-numbers-and-50-moves) |
| <a name="--compose-only"></a>&nbsp;&nbsp;&nbsp;&nbsp;`--compose-only` | [docs/builds/build-mode.md](docs/builds/build-mode.md#--compose-only) |
| <a name="the-installer-that-composes-the-media-is-the-variants-composer"></a>&nbsp;&nbsp;&nbsp;&nbsp;The installer that composes the media is the variant's: `composer` | [docs/builds/build-mode.md](docs/builds/build-mode.md#the-installer-that-composes-the-media-is-the-variants-composer) |
| <a name="how-a-medium-boots-iso-boot"></a>&nbsp;&nbsp;&nbsp;&nbsp;How a medium boots: `iso-boot` | [docs/builds/build-mode.md](docs/builds/build-mode.md#how-a-medium-boots-iso-boot) |
| <a name="remaster-mode-an-azure-variant-of-an-iso-that-already-exists"></a>Remaster mode: an Azure variant of an ISO that already exists | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#remaster-mode-an-azure-variant-of-an-iso-that-already-exists) |
| <a name="why-remaster-rather-than-build"></a>&nbsp;&nbsp;&nbsp;&nbsp;Why remaster rather than build | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#why-remaster-rather-than-build) |
| <a name="the-dependency-closure-is-computed-not-listed"></a>&nbsp;&nbsp;&nbsp;&nbsp;The dependency closure is computed, not listed | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#the-dependency-closure-is-computed-not-listed) |
| <a name="the-toolchain-comes-off-the-input-iso"></a>&nbsp;&nbsp;&nbsp;&nbsp;The toolchain comes off the input ISO | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#the-toolchain-comes-off-the-input-iso) |
| <a name="the-accelerator-is-gated-on-byte-identity"></a>&nbsp;&nbsp;&nbsp;&nbsp;The accelerator is gated on byte identity | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#the-accelerator-is-gated-on-byte-identity) |
| <a name="what-verify-reads-back-off-the-finished-iso"></a>&nbsp;&nbsp;&nbsp;&nbsp;What verify reads back off the finished ISO | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#what-verify-reads-back-off-the-finished-iso) |
| <a name="the-replacement-set-is-derived"></a>&nbsp;&nbsp;&nbsp;&nbsp;The replacement set is derived | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#the-replacement-set-is-derived) |
| <a name="a-config-change-must-change-the-nevr"></a>&nbsp;&nbsp;&nbsp;&nbsp;A config change must change the NEVR | [docs/builds/remaster-azure.md](docs/builds/remaster-azure.md#a-config-change-must-change-the-nevr) |
| <a name="kernel-wrappers-sharukhan-wrapper"></a>Kernel wrappers: `sharukhan wrapper` | [docs/builds/kernel-wrappers.md](docs/builds/kernel-wrappers.md#kernel-wrappers-sharukhan-wrapper) |
| <a name="a-fips-canister-series-for-a-profile-kernel"></a>&nbsp;&nbsp;&nbsp;&nbsp;A FIPS canister series for a profile kernel | [docs/builds/kernel-wrappers.md](docs/builds/kernel-wrappers.md#a-fips-canister-series-for-a-profile-kernel) |
| <a name="kernel-profile-builds-and-runs---kernel"></a>Kernel-profile builds and runs: `--kernel` | [docs/builds/kernel-profiles.md](docs/builds/kernel-profiles.md#kernel-profile-builds-and-runs---kernel) |
| <a name="linux-73-rc4-2026-09-29"></a>&nbsp;&nbsp;&nbsp;&nbsp;Linux 7.3-rc4 (2026-09-29) | [docs/builds/kernel-profiles.md](docs/builds/kernel-profiles.md#linux-73-rc4-2026-09-29) |
| <a name="real-world-example-a-full-iso-with-kernel-73-the-latest-installer-and-the-equivalent-canister"></a>Real-world example: a full ISO with kernel 7.3, the latest installer and the equivalent canister | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#real-world-example-a-full-iso-with-kernel-73-the-latest-installer-and-the-equivalent-canister) |
| <a name="step-1-from-scratch---a-host-that-can-run-sharukhan"></a>&nbsp;&nbsp;&nbsp;&nbsp;Step 1: from scratch - a host that can run sharukhan | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#step-1-from-scratch---a-host-that-can-run-sharukhan) |
| <a name="the-directory-layout"></a>&nbsp;&nbsp;&nbsp;&nbsp;The directory layout | [docs/configuration.md](docs/configuration.md#the-directory-layout) |
| <a name="why-a-kernel-branch-and-how-it-is-named"></a>&nbsp;&nbsp;&nbsp;&nbsp;Why a kernel branch, and how it is named | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#why-a-kernel-branch-and-how-it-is-named) |
| <a name="the-script-and-its-variables"></a>&nbsp;&nbsp;&nbsp;&nbsp;The script and its variables | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#the-script-and-its-variables) |
| <a name="the-script-function-by-function"></a>&nbsp;&nbsp;&nbsp;&nbsp;The script, function by function | [docs/examples/kernel-iso-helpers.md](docs/examples/kernel-iso-helpers.md#the-script-function-by-function) |
| <a name="the-2026-10-run-result"></a>&nbsp;&nbsp;&nbsp;&nbsp;The 2026-10 run: result | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#the-2026-10-run-result) |
| <a name="culprits-and-how-each-was-solved"></a>&nbsp;&nbsp;&nbsp;&nbsp;Culprits and how each was solved | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#culprits-and-how-each-was-solved) |
| <a name="timings"></a>&nbsp;&nbsp;&nbsp;&nbsp;Timings | [docs/examples/kernel-iso.md](docs/examples/kernel-iso.md#timings) |
| <a name="keeping-the-forks-prs-current-sharukhan-sync"></a>Keeping the fork's PRs current: `sharukhan sync` | [docs/automation/sync.md](docs/automation/sync.md#keeping-the-forks-prs-current-sharukhan-sync) |
| <a name="the-stages"></a>&nbsp;&nbsp;&nbsp;&nbsp;The stages | [docs/automation/sync.md](docs/automation/sync.md#the-stages) |
| <a name="starting-following-and-resuming-a-run"></a>&nbsp;&nbsp;&nbsp;&nbsp;Starting, following and resuming a run | [docs/automation/sync.md](docs/automation/sync.md#starting-following-and-resuming-a-run) |
| <a name="when-a-pr-needs-a-decision"></a>&nbsp;&nbsp;&nbsp;&nbsp;When a PR needs a decision | [docs/automation/sync.md](docs/automation/sync.md#when-a-pr-needs-a-decision) |
| <a name="descriptions"></a>&nbsp;&nbsp;&nbsp;&nbsp;Descriptions | [docs/automation/sync.md](docs/automation/sync.md#descriptions) |
| <a name="upstream-prs-shared-branches-staged-first"></a>&nbsp;&nbsp;&nbsp;&nbsp;Upstream PRs: shared branches, staged first | [docs/automation/sync.md](docs/automation/sync.md#upstream-prs-shared-branches-staged-first) |
| <a name="the-timer-sync-auto"></a>&nbsp;&nbsp;&nbsp;&nbsp;The timer: `sync auto` | [docs/automation/sync.md](docs/automation/sync.md#the-timer-sync-auto) |
| <a name="other-sync-commands"></a>&nbsp;&nbsp;&nbsp;&nbsp;Other sync commands | [docs/automation/sync.md](docs/automation/sync.md#other-sync-commands) |
| <a name="the-escalation-sharukhan-escalate-and-sharukhan-mcp"></a>The escalation: `sharukhan escalate` and `sharukhan mcp` | [docs/automation/escalation.md](docs/automation/escalation.md#the-escalation-sharukhan-escalate-and-sharukhan-mcp) |
| <a name="before-the-first-escalation-escalate-preflight"></a>&nbsp;&nbsp;&nbsp;&nbsp;Before the first escalation: `escalate preflight` | [docs/automation/escalation.md](docs/automation/escalation.md#before-the-first-escalation-escalate-preflight) |
| <a name="one-escalation-the-queue-the-ledger"></a>&nbsp;&nbsp;&nbsp;&nbsp;One escalation, the queue, the ledger | [docs/automation/escalation.md](docs/automation/escalation.md#one-escalation-the-queue-the-ledger) |
| <a name="taking-a-verified-proposal"></a>&nbsp;&nbsp;&nbsp;&nbsp;Taking a verified proposal | [docs/automation/escalation.md](docs/automation/escalation.md#taking-a-verified-proposal) |
| <a name="budgets-and-price-weights"></a>&nbsp;&nbsp;&nbsp;&nbsp;Budgets and price weights | [docs/automation/escalation.md](docs/automation/escalation.md#budgets-and-price-weights) |
| <a name="how-the-model-is-confined"></a>&nbsp;&nbsp;&nbsp;&nbsp;How the model is confined | [docs/automation/escalation.md](docs/automation/escalation.md#how-the-model-is-confined) |
| <a name="the-mcp-server-sharukhan-mcp"></a>&nbsp;&nbsp;&nbsp;&nbsp;The MCP server: `sharukhan mcp` | [docs/automation/escalation.md](docs/automation/escalation.md#the-mcp-server-sharukhan-mcp) |
| <a name="the-upstream-watcher-and-its-events"></a>The upstream watcher and its events | [docs/automation/watcher-events.md](docs/automation/watcher-events.md#the-upstream-watcher-and-its-events) |
| <a name="data-files-the-automation-reads"></a>Data files the automation reads | [docs/automation/data-files.md](docs/automation/data-files.md#data-files-the-automation-reads) |
| <a name="configvariantsconf-installer-variants-and-the-common-branches"></a>&nbsp;&nbsp;&nbsp;&nbsp;`config/variants.conf`: installer variants and the common branches | [docs/automation/data-files.md](docs/automation/data-files.md#configvariantsconf-installer-variants-and-the-common-branches) |
| <a name="configcheck-prstsv-which-pr-a-check-proves"></a>&nbsp;&nbsp;&nbsp;&nbsp;`config/check-prs.tsv`: which PR a check proves | [docs/automation/data-files.md](docs/automation/data-files.md#configcheck-prstsv-which-pr-a-check-proves) |
| <a name="memorydb-and-memorymd"></a>&nbsp;&nbsp;&nbsp;&nbsp;`memory.db` and `MEMORY.md` | [docs/automation/data-files.md](docs/automation/data-files.md#memorydb-and-memorymd) |
| <a name="the-embedded-canister-equivalent-patch"></a>&nbsp;&nbsp;&nbsp;&nbsp;The embedded canister-equivalent patch | [docs/automation/data-files.md](docs/automation/data-files.md#the-embedded-canister-equivalent-patch) |
| <a name="helper-scripts--the-run-wrappers"></a>`helper-scripts/` — the run wrappers | [archive/helper-scripts/README.md](archive/helper-scripts/README.md#helper-scripts--the-run-wrappers) |
| <a name="the-two-pass-protocol"></a>&nbsp;&nbsp;&nbsp;&nbsp;The two-pass protocol | [archive/helper-scripts/README.md](archive/helper-scripts/README.md#the-two-pass-protocol) |
| <a name="they-need-mc_guest_password-in-the-environment"></a>&nbsp;&nbsp;&nbsp;&nbsp;They need `MC_GUEST_PASSWORD` in the environment | [archive/helper-scripts/README.md](archive/helper-scripts/README.md#they-need-mc_guest_password-in-the-environment) |
| <a name="paths-are-absolute-and-host-specific"></a>&nbsp;&nbsp;&nbsp;&nbsp;Paths are absolute and host-specific | [archive/helper-scripts/README.md](archive/helper-scripts/README.md#paths-are-absolute-and-host-specific) |
| <a name="configuration"></a>Configuration | [docs/configuration.md](docs/configuration.md#configuration) |
| <a name="paths-the-vm-and-the-network"></a>&nbsp;&nbsp;&nbsp;&nbsp;Paths, the VM and the network | [docs/configuration.md](docs/configuration.md#paths-the-vm-and-the-network) |
| <a name="the-settings-file-and-the-secret-files"></a>&nbsp;&nbsp;&nbsp;&nbsp;The settings file and the secret files | [docs/configuration.md](docs/configuration.md#the-settings-file-and-the-secret-files) |
| <a name="settings-of-the-build-the-fork-and-the-sync"></a>&nbsp;&nbsp;&nbsp;&nbsp;Settings of the build, the fork and the sync | [docs/configuration.md](docs/configuration.md#settings-of-the-build-the-fork-and-the-sync) |
| <a name="the-network-axis"></a>The network axis | [docs/matrix/network-axis.md](docs/matrix/network-axis.md#the-network-axis) |
| <a name="what-this-host-cannot-test-and-why"></a>&nbsp;&nbsp;&nbsp;&nbsp;What this host cannot test, and why | [docs/matrix/network-axis.md](docs/matrix/network-axis.md#what-this-host-cannot-test-and-why) |
| <a name="n05-fails-for-the-environments-reason-not-pois"></a>&nbsp;&nbsp;&nbsp;&nbsp;n05 fails for the environment's reason, not POI's | [docs/matrix/network-axis.md](docs/matrix/network-axis.md#n05-fails-for-the-environments-reason-not-pois) |
| <a name="n03-needs-a-second-nic-and-that-now-works"></a>&nbsp;&nbsp;&nbsp;&nbsp;n03 needs a second NIC, and that now works | [docs/matrix/network-axis.md](docs/matrix/network-axis.md#n03-needs-a-second-nic-and-that-now-works) |
| <a name="when-an-install-is-finished-and-how-that-is-known"></a>&nbsp;&nbsp;&nbsp;&nbsp;When an install is finished, and how that is known | [docs/matrix/network-axis.md](docs/matrix/network-axis.md#when-an-install-is-finished-and-how-that-is-known) |
| <a name="troubleshooting"></a>Troubleshooting | [docs/troubleshooting.md](docs/troubleshooting.md#troubleshooting) |
| <a name="every-iso-group-is-refused-at-once"></a>&nbsp;&nbsp;&nbsp;&nbsp;Every ISO group is refused at once | [docs/troubleshooting.md](docs/troubleshooting.md#every-iso-group-is-refused-at-once) |
| <a name="the-disk-fills-during-a-build"></a>&nbsp;&nbsp;&nbsp;&nbsp;The disk fills during a build | [docs/troubleshooting.md](docs/troubleshooting.md#the-disk-fills-during-a-build) |
| <a name="stop-and-containers"></a>&nbsp;&nbsp;&nbsp;&nbsp;`stop` and containers | [docs/troubleshooting.md](docs/troubleshooting.md#stop-and-containers) |
| <a name="a-manual-gate-after-a-stopped-or-failed-build"></a>&nbsp;&nbsp;&nbsp;&nbsp;A manual gate after a stopped or failed build | [docs/troubleshooting.md](docs/troubleshooting.md#a-manual-gate-after-a-stopped-or-failed-build) |
| <a name="following-a-job"></a>&nbsp;&nbsp;&nbsp;&nbsp;Following a job | [docs/troubleshooting.md](docs/troubleshooting.md#following-a-job) |
| <a name="things-learned-the-hard-way"></a>Things learned the hard way | [docs/lessons-learned.md](docs/lessons-learned.md#things-learned-the-hard-way) |
