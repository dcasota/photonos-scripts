# Getting started

[← sharukhan overview](../README.md)

**Who this is for:** Someone installing sharukhan on a host for the first time, and anyone who wants the shape of a normal day with it.

**Contents**

- [Build](#build)
- [Installing the host services: `sharukhan service`](#installing-the-host-services-sharukhan-service)
- [Typical session](#typical-session)

## Build

```
cargo build --release
./target/release/sharukhan --help
```

Three dependencies (`rusqlite` with bundled SQLite, `serde`, `serde_json`).
No network access at runtime. `cargo test` runs the unit tests, which include the
check that `photon-matrix.vmx.template` and the VMX renderer have not diverged.

## Installing the host services: `sharukhan service`

The watcher, the timed sync and the builder's shared mount run as systemd
units. `sharukhan service` writes them from templates compiled into the
binary, so they are versioned with the code instead of being edited by hand.

### What gets installed

| Path | What it is |
|---|---|
| `/usr/local/libexec/sharukhan/sharukhan` | the binary the units and every job run (installed atomically) |
| `/etc/sharukhan/sharukhan.env` | the services' settings, `KEY="value"` lines; nothing secret |
| `/etc/sharukhan/secrets/anthropic-api-key` | the escalation's API key, mode 0600 (only with `--escalation-key-from-env`) |
| `/etc/sharukhan/secrets/guest-password` | the guest root password, mode 0600 (only with `--guest-password-from-env`) |
| `/etc/systemd/system/sharukhan-watch.service` | the upstream watcher (`sharukhan watch --interval <s>`) |
| `/etc/systemd/system/sharukhan-sync.service` + `.timer` | `sharukhan sync auto` on a timer (only with `--sync`) |
| `/etc/systemd/system/photon-mc-gate-shared.service` + `/usr/local/sbin/photon-mc-gate-shared` | the shared bind mount the builder container needs (only with `MC_BUILDER=container`) |

The settings file names the secret files (`MC_ANTHROPIC_KEY_FILE`,
`MC_GUEST_PASSWORD_FILE`); the values themselves are never written to a unit,
the settings file, an argv or the output.

### Install or update

Run it in the host mount namespace, from a shell that has the settings you
want the services to carry:

```bash
. /root/photon-mc/gate/env-isolated.sh            # the gate settings
export HOME=/root MC_NOTIFY=file:/root/photon-mc/events.log
nsenter --target 1 --mount -- \
  sharukhan service install --sync --guest-password-from-env --escalation-key-from-env
```

* Every setting sharukhan knows that is set in the environment goes into the
  settings file; settings already in the file and not in the environment are
  kept. `--unset KEY` removes one.
* `--escalation-key-from-env` takes `ANTHROPIC_API_KEY`, checks its shape and
  that the API accepts it, then writes the key file.
* `--guest-password-from-env` takes `MC_GUEST_PASSWORD`. `--sync` refuses
  without a guest password file: a sync reaches GATE, which installs VMs.
* `--watch-interval S`, `--sync-every SPAN` (e.g. `30min`, `1h`) and
  `--sync-quiet S` set the service options.
* It refuses while a sync run, a job or an escalation is running: those
  processes run the installed binary.
* Running it again changes only what differs and says what.

```bash
sharukhan service install --dry-run                 # what would change
sharukhan service install --root /tmp/svc-review    # render into a directory, systemd untouched
```

### Check: `service status`

```bash
sharukhan service status
```

It renders what `install` would write from the settings file on disk and
compares: every file is `current`, `missing` or `differs` (with the lines),
each secret file is checked for owner and mode, and the installed binary is
compared with the one running. It exits non-zero on drift; `sharukhan doctor`
reports the same as its "service files" item.

### Remove: `service remove`

```bash
sharukhan service remove --sync          # only the sync service and timer
sharukhan service remove                 # every unit and the settings file
sharukhan service remove --key --guest-password   # ...and those secret files
```

A secret file goes only when named. The binary stays.

### Commands run by hand use the same settings

`/root/photon-mc/gate/env-isolated.sh` loads `/etc/sharukhan/sharukhan.env`
(after `env.sh`, which only provides the guest password for bash scripts that
check `MC_GUEST_PASSWORD` themselves), so a gate run by hand and a sync started
by systemd see the same paths. Change a setting with `service install`, not by
editing a script.

### When the timed sync is needed, and when not

* **Needed** when the fork's PRs should follow the fork's release and `common`
  branches without anyone starting it: the timer checks every
  `SHARUKHAN_SYNC_EVERY` and starts a run once a base moved and stayed quiet
  for `SHARUKHAN_SYNC_QUIET` seconds.
* **Not needed** while you drive a sync by hand (only one run exists at a
  time), and it waits by itself while a gate or build job is running.
* **The watcher** only reads and records; it should always run.

## Typical session

### A gate run by hand

```
sharukhan doctor                     # is the machine fit to run anything
sharukhan plan --only k01,k02        # what will run, is the ISO cached
sharukhan status                     # room to run it, and how many at once
sharukhan run --dry-run --only k01,k02   # every gate, for real, executing nothing
nohup sharukhan run --only k01,k02 &     # prints a job id
sharukhan watch --job 1              # follow it (the run log, until the job ends)
sharukhan stop --job 1               # if it has to end early
sharukhan report --only k01,k02      # what happened, against the documented verdict
sharukhan findings                   # what previous runs established
```

### A day with the automation

```
sharukhan service status             # services, settings and secret files as installed
sharukhan events --new               # what moved upstream, what waits for a person
sharukhan sync status                # the last runs and their stages
sharukhan escalate ledger            # what the escalation did and cost
sharukhan sync approve-upstream 7    # after reading UPSTREAM.table
```

---

[← sharukhan overview](../README.md)
