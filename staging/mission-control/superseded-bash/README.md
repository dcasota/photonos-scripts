# Superseded bash

The ten `bin/*.sh` drivers and the two `lib/*.sh` libraries that were mission
control until 2026-09-01. Archived rather than deleted, because two things here
still have no Rust equivalent and one of them is running right now.

Everything they did is in `../../sharukhan-cli`. `sharukhan` is meant to be the
only script.

## What replaced what

| bash | sharukhan | where the reasoning went |
| --- | --- | --- |
| `bin/mc-run.sh` | `run` | `src/runner.rs` (gates, job row), `src/phases.rs` (the sequence) |
| `bin/mc-build-iso.sh` | `build-iso --allow-build` | `src/build.rs` |
| `bin/mc-make-variant-patches.sh` | `variant-patches` | `src/build.rs` |
| `bin/mc-gen-kickstart.sh` | `kickstart` | `src/kickstart.rs` |
| `bin/mc-create-vm.sh` | `create-vm` | `src/vm.rs`, `src/vmx.rs`, `src/winpath.rs`, `src/b64.rs` |
| `bin/mc-install.sh` | `install` | `src/install.rs` |
| `bin/mc-verify.sh` | `verify` | `src/verify.rs` |
| `bin/mc-teardown.sh` | `teardown` | `src/vm.rs` |
| `bin/mc-preflight.sh` | `doctor` | `src/main.rs` |
| `bin/mc-operator-card.sh` | `card` | `src/card.rs` |
| `lib/common.sh` | — | `src/identity.rs`, `src/winpath.rs`, `src/evidence.rs`, `src/serial.rs`, `src/config.rs` |
| `lib/oracle.sh` | — | `src/oracle.rs` |

The evidence format did not change: `results/<id>/checks-<stamp>.jsonl`, same
field names in the same order, same `checks-latest.jsonl` and `logs-latest`
pointers. The 21 rows of existing evidence still read.

## `bin` and `lib` are symlinks, and that is deliberate

`/root/photon-mc/canister-c01.sh` has been running since 2026-09-01 16:09Z. It
calls `$MC/bin/mc-build-iso.sh` (in flight now) and, when that finishes, will
call `$MC/bin/mc-run.sh --only c01` **by path**. Moving those files out from
under a 12-hour build would have broken the one row in the matrix that
exercises a locally built FIPS canister.

So `mission-control/bin` and `mission-control/lib` are now symlinks into this
directory, and `superseded-bash/config` points back at `../config` so
`mc_find_config` still resolves. Renaming a file does not disturb a running
bash - the open fd follows the inode - and the paths still resolve for the
invocation that has not happened yet.

Once the c01 chain has finished, remove them:

    rm mission-control/bin mission-control/lib

Nothing in `sharukhan` reads either path.

## What is NOT replaced

1. **`mc_report_to_file`.** `mc-run.sh` wrote `results/reports/report-<stamp>.txt`
   and pointed `report-latest.txt` at it, so two runs could be diffed. `sharukhan
   report` prints to stdout and writes nothing. Redirect it yourself until that
   is fixed; a report that overwrites its predecessor cannot be diffed against
   it, which is the main thing anyone wants from two runs.
2. **`config/mission-control.env` still carries a literal root password.**
   `sharukhan` does not read that file - `MC_GUEST_PASSWORD` is required and has
   no default, and every command that installs or configures a guest refuses
   without it. But the literal is still checked in, and it is still what the
   bash here would use. Delete it from the env file once nothing sources it.
3. **Per-directory disk thresholds.** `mc-preflight.sh` asserted 25 GiB free on
   each of the VM store, the ISO cache and the results directory. `doctor`
   checks `/` and the VM store against the sizes in `src/disk.rs` and only
   checks that the other two are creatable.

## Behaviour that changed on purpose

* **The SELinux oracle was wrong and is fixed.** `lib/oracle.sh` asserted
  `Enforcing` whenever STIG was requested. `selinux-policy` ships **permissive
  by design** at subrelease >= 92 (disabled at 91, enforcing at <= 90), so that
  expectation produced four false failures - k11/k12/k15/k16 - that were
  briefly reported as a Photon compliance defect. `src/oracle.rs` derives the
  expectation from the guest's own `/etc/selinux/config`, falling back to the
  subrelease tri-state, and records both. See COMPILE-CONSTELLATIONS.md 15.1.
* **`sshpass` is gone.** The kickstart already injects `public_key`, so
  authentication is key-only and the guest password never reaches a command
  line. `ssh` itself still runs as an external binary, deliberately: the s02
  finding was OpenSSH's own error text, and a different SSH implementation
  could mask exactly that class of defect.
* **`verify` asks vmrun with a Windows path.** `mc-verify.sh` passed
  `$DIR/$VM.vmx` - a WSL path - to `vmrun getGuestIPAddress`. vmrun.exe cannot
  open it, so it answered nothing, which is indistinguishable from a guest that
  has not booted. Every other call site converted the path; this one did not.
* **An ISO build is now a flag, not a refusal.** `run` used to print the
  `mc-build-iso.sh` command instead of building. It still refuses by default -
  a build takes hours and shares `$PHOTON_TREE/stage` - but `--allow-build`
  makes it a decision the operator can make.

## External tools still exec'd

`vmrun.exe`, `vmware-vdiskmanager.exe`, `ssh`, `ssh-keygen`, `git`, `xorriso`,
and `sh runPh5_normal.sh` (which is the Photon build system). These are Windows
binaries or the system under test.

Absorbed and no longer required: `python3`, `base64`, `jq`, `sshpass`,
`sha256sum`, `patch`, `tar`.

## Safe to delete

Once the c01 chain has finished, `report` writes a file, and the password
literal is out of `config/mission-control.env`. Nothing in the Rust references
this directory: the evidence is in `/root/photon-mc/results/`, the findings are
in `memory.db`.
