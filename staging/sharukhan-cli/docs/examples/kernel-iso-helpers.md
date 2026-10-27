# kernel-iso.sh: header and helpers

[← sharukhan overview](../../README.md)

**Who this is for:** Readers of `examples/kernel-iso.sh`: its header, variables and helper functions, line by line.

## The script, function by function

### Header and variables

```bash
#!/bin/bash
# kernel-iso.sh - one Photon ISO with another kernel.org kernel, built,
# boot-tested and verified through sharukhan.
#
# The README chapter "Real-world example: a full ISO with kernel 7.3, the
# latest installer and the equivalent canister" explains every function of
# this script line by line. Every value is a variable below or is read from
# sharukhan itself (`sharukhan settings`, `sharukhan wrapper kernel`); the
# script never names a host path, a branch or a row of its own.
#
#   KERNEL=7.3 POI=latest CANISTER=equivalent ISO_TYPE=full examples/kernel-iso.sh
#   examples/kernel-iso.sh --dry-run            print every command, run nothing
#   examples/kernel-iso.sh --step verify_media  run one step
#   examples/kernel-iso.sh --from variant_patches  run from a step to the end
#   examples/kernel-iso.sh --list               the steps, in order
#
# Steps that need a person (porting the kernel's patches to a new release,
# reviewing a new profile) stop with what to do and the command that proves
# it was done; run the script again, or that step with --step, afterwards.
set -euo pipefail

# --- what to build: from the environment, defaults for the documented case ---
KERNEL=${KERNEL:-}                    # kernel.org release: 7.3, 7.3-rc4, 7.2.5 ...
POI=${POI:-latest}                    # installer variant: a [variant <name>] of variants.conf
CANISTER=${CANISTER:-equivalent}      # equivalent (built from this kernel) | prebuilt
ISO_TYPE=${ISO_TYPE:-full}            # full | minimal
ROWS=${ROWS:-}                        # matrix rows to boot-test; empty: derived (see derive_rows)
FROM_PROFILE=${FROM_PROFILE:-}        # write_profile: the profile a new one starts from
DISK_MIN_GB=${DISK_MIN_GB:-40}        # free space a kernel build needs (the 7.3 build used about 30 GB)
WAIT=${WAIT:-1}                       # 1: wait for a detached build or run; 0: return at once
ISO=${ISO:-}                          # verify_media: this file instead of the cache's photon.iso

# --- where sharukhan and its settings are -----------------------------------
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
export SHARUKHAN_CLI_DIR=${SHARUKHAN_CLI_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}
SHARUKHAN=${SHARUKHAN:-$(command -v sharukhan || echo /usr/local/libexec/sharukhan/sharukhan)}
SETTINGS_FILE=${SETTINGS_FILE:-/etc/sharukhan/sharukhan.env}

STEPS=(preflight settings verify_kernel_release prepare_branch write_profile prove_patches
       variant_patches build_iso boot_test verify_media report)
```

- `set -euo pipefail`: a failing command, an unset variable or a failing part
  of a pipeline stops the script. Because of `pipefail`, the script never pipes
  into a reader that stops early (`grep -q`, `head`): the producer would die of
  a closed pipe and fail the pipeline; it reads into a variable or a here-string
  first.
- Every `X=${X:-default}` line takes the value from the environment if set -
  `KERNEL=7.3 POI=2.8 examples/kernel-iso.sh` - and documents its default.
- `SHARUKHAN_CLI_DIR` is exported: sharukhan reads the kernel profiles of the
  checkout the script belongs to.
- `STEPS` is the order of the steps; `--step` and `--from` accept only these.

### `say`, `die`, `human`, `run`

```bash
say() { printf '[kernel-iso] %s\n' "$*"; }
die() { printf '[kernel-iso] REFUSED: %s\n' "$*" >&2; exit 2; }

# A step a person must finish: what to do, and how to prove it was done.
human() {
    local step=$1; shift
    printf '[kernel-iso] STOP at %s - a person must do this:\n' "$step" >&2
    printf '  %s\n' "$@" >&2
    if [ "$DRY" = 1 ]; then
        printf '[kernel-iso] (dry run: a real run stops here)\n' >&2
        return 0
    fi
    printf '[kernel-iso] then: %s --from %s\n' "$0" "$step" >&2
    exit 10
}
```
```bash
die() { printf '[kernel-iso] REFUSED: %s\n' "$*" >&2; exit 2; }

# A step a person must finish: what to do, and how to prove it was done.
human() {
    local step=$1; shift
    printf '[kernel-iso] STOP at %s - a person must do this:\n' "$step" >&2
    printf '  %s\n' "$@" >&2
    if [ "$DRY" = 1 ]; then
        printf '[kernel-iso] (dry run: a real run stops here)\n' >&2
        return 0
    fi
    printf '[kernel-iso] then: %s --from %s\n' "$0" "$step" >&2
    exit 10
}
```
```bash
# A step a person must finish: what to do, and how to prove it was done.
human() {
    local step=$1; shift
    printf '[kernel-iso] STOP at %s - a person must do this:\n' "$step" >&2
    printf '  %s\n' "$@" >&2
    if [ "$DRY" = 1 ]; then
        printf '[kernel-iso] (dry run: a real run stops here)\n' >&2
        return 0
    fi
    printf '[kernel-iso] then: %s --from %s\n' "$0" "$step" >&2
    exit 10
}
```
```bash
# Every command that changes something goes through run(): --dry-run prints it.
run() {
    if [ "$DRY" = 1 ]; then
        printf '+ %s\n' "$*"
    else
        "$@"
    fi
}
```

- `say` prints a progress line; `die` prints a refusal to stderr and exits 2.
- `human` stops at a step a person must finish: it prints the instructions and
  the command that resumes (`--from <step>`), and exits 10. In `--dry-run` it
  prints the stop and continues, so a dry run shows every command.
- `run` is the only way the script changes anything: with `--dry-run` it prints
  the command (`+ ...`) instead of running it. Read-only commands (identity,
  checks) run even in a dry run.

### `detach`

```bash
# Long work runs detached in its own session with a log, so a closed terminal
# does not end it; the exit status is the log's last line.
detach() {
    local name=$1; shift
    local log="$MC_RUN_LOG_DIR/kernel-iso-$KERNEL-$name-$(date -u +%Y%m%dT%H%M%SZ).log"
    if [ "$DRY" = 1 ]; then
        printf '+ setsid nohup %s > %s 2>&1 &\n' "$*" "$log"
        return 0
    fi
    mkdir -p "$MC_RUN_LOG_DIR"
    setsid nohup bash -c '"$@"; echo "=== exit $? $(date -u +%FT%TZ)"' _ "$@" > "$log" 2>&1 < /dev/null &
    say "$name detached (pid $!), log $log"
    if [ "$WAIT" = 1 ]; then
        until grep -q '^=== exit ' "$log"; do sleep 60; done
        local rc
        rc=$(grep '^=== exit ' "$log" | tail -1 | awk '{print $3}')
        say "$name ended with exit $rc"
        [ "$rc" = 0 ] || die "$name failed, see $log"
    else
        say "not waiting (WAIT=0): follow $log, then continue with --step after $name"
    fi
}
```

- The log goes to `$MC_RUN_LOG_DIR/kernel-iso-<kernel>-<step>-<stamp>.log`.
- `setsid nohup bash -c '"$@"; echo "=== exit $?..."'` starts the command in
  its own session, immune to a closed terminal, with stdin from `/dev/null`;
  its last log line is `=== exit <status> <time>`.
- With `WAIT=1` the script polls the log every minute for that line and refuses
  to continue on a non-zero status; with `WAIT=0` it returns and says which
  step comes next.

### `in_host_namespace`, `live_jobs`, `free_gb`

```bash
in_host_namespace() {
    [ "$(readlink /proc/self/ns/mnt)" = "$(readlink /proc/1/ns/mnt)" ]
}
```
```bash
# Jobs whose row says running and whose process is a live sharukhan.
live_jobs() {
    [ -f "$SHARUKHAN_DB" ] || return 0
    sqlite3 -cmd ".timeout 10000" "$SHARUKHAN_DB" \
        "SELECT id || ' ' || coalesce(pid,0) FROM job WHERE state = 'running'" 2>/dev/null |
    while read -r id pid; do
        [ "$pid" -gt 0 ] && [ -r "/proc/$pid/cmdline" ] &&
            grep -qa 'sharukhan' "/proc/$pid/cmdline" && echo "job $id (pid $pid)"
    done
}
```
```bash
free_gb() { df -BG --output=avail "$1" | tail -1 | tr -dc '0-9'; }

# --- derived values ----------------------------------------------------------

# The kernel's identity as sharukhan derives it: branch, wrapper, rpm version.
# Output lines look like "  branch       experimental/linux-7.3"; the key may hold a space.
identity() {
    "$SHARUKHAN" wrapper kernel "$KERNEL" --offline | sed -n "s/^  $1  *//p" | sed -n 1p
}
```

- `in_host_namespace` compares this process's mount namespace with PID 1's: on
  WSL2 the builder's overlay mounts are only visible to dockerd from there.
- `live_jobs` lists jobs whose row in memory.db says `running` **and** whose
  process is alive and is sharukhan - a row left by a crashed run does not
  count, a real run does.
- `free_gb` is the free space of the filesystem holding a path, in GB.

### `identity`, `derive_rows`

```bash
# The kernel's identity as sharukhan derives it: branch, wrapper, rpm version.
# Output lines look like "  branch       experimental/linux-7.3"; the key may hold a space.
identity() {
    "$SHARUKHAN" wrapper kernel "$KERNEL" --offline | sed -n "s/^  $1  *//p" | sed -n 1p
}
```
```bash
# Rows for the boot test: one without and one with STIG, autonomous (kickstart),
# default network, ext4, of the requested ISO type and installer variant.
derive_rows() {
    awk -v t="$ISO_TYPE" -v p="$POI" '
        /^#/ || NF < 10 { next }
        { net = (NF >= 11 ? $11 : "-") }    # an empty net column is the default network
        $2 == t && $3 == p && $6 == "ks" && $5 == "ext4" && net == "-" {
            if ($4 == "no"  && !no)  no = $1
            if ($4 == "yes" && !yes) yes = $1
        }
        END { if (no && yes) print no "," yes; else if (no) print no; else if (yes) print yes }
    ' "$SHARUKHAN_MATRIX"
}
```

- `identity` asks sharukhan for one line of the kernel's identity (offline, no
  network): `branch` (`experimental/linux-7.3`), `wrapper` (`runPh7-3.sh`),
  `rpm Version` (`7.3.0`), `rpm Release` (`1`). The kernel branch is therefore
  never written by hand.
- `derive_rows` reads the matrix (`$SHARUKHAN_MATRIX`): skips comments and short
  lines; an empty last column is the default network; it keeps rows of the
  requested ISO type and variant, kickstart mode, ext4, default network, and
  prints the first without STIG and the first with STIG - one plain install
  and one STIG/FIPS install. For `full`/`latest` these are k13 and k15 in the
  2026-10 matrix.

---

[← sharukhan overview](../../README.md)
