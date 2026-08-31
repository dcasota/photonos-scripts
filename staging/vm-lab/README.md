# vm-lab — build a SPAGAT appliance VM on VMware Workstation, end to end

Everything needed to go from *nothing* to *a running, verified, SSH-reachable
Photon OS appliance VM*: the VMX settings, the disk geometry, the kickstart,
the install automation, SSH access, and the checks that tell you whether each
stage actually did what it claims.

Read [The four things that actually bite](#the-four-things-that-actually-bite)
before your first run. Each one has cost days elsewhere in this project.

**Defaults:** 2 vCPU, 4 GB RAM, and a **50 GB thin disk in a single file**.
The disk is `monolithicSparse`, so 50 GB is a ceiling rather than an
allocation — a fresh one is ~6 MB and grows only as the guest writes.

**This directory lives in two places.** It is developed in the
SPAGAT-Librarian appliance repo at `deploy/vm-lab/` and snapshotted into
`photonos-scripts` at `staging/vm-lab/`. `PROVENANCE.md` records which commit
a snapshot came from, and `kickstart/check-drift.sh` behaves correctly in
both (see [The kickstart](#the-kickstart)).

---

## Layout

```
vm-lab/
├── README.md                              ← you are here
├── PROVENANCE.md                          which commit this snapshot came from
├── config/
│   ├── vm-lab.env                         single source of paths, sizes, IP, MAC
│   └── spagat-smoke.vmx.template          VMX with every non-default key explained
├── kickstart/
│   ├── photon-appliance.ks.template.json  byte-exact copy of the build's template
│   ├── EXPECTED-SHA256                    that copy's hash, for the standalone check
│   ├── UPSTREAM-README.md                 the template's own upstream docs
│   └── check-drift.sh                     fails if the copy diverges
└── scripts/
    ├── 00-preflight.sh          can this host do the job?
    ├── 10-create-vm.ps1         VM dir + boot VMDK + VMX from template
    ├── 20-make-ssh-key.sh       keypair + the exports the ISO build needs
    ├── 30-install-from-iso.sh   unattended install
    ├── 40-check-staging.sh      did rootfs / ISO / guest actually get what I think?
    ├── 50-verify-boot.sh        is it alive, and did THIS boot do anything?
    ├── 60-ssh.sh                connect — and explain failures
    └── 90-teardown.ps1          back to a fresh disk (stashes, never deletes)
```

Run the shell scripts from this directory, or export `VM_LAB_DIR=/path/to/vm-lab`
if you invoke them from elsewhere (for example after copying one to `/tmp` to
strip CRLF). They **refuse to run** rather than proceeding without their
config.

**Which shell:** `.sh` runs in WSL (`wsl -d Ph5 -u dcaso`), `.ps1` runs on
Windows. That split is not stylistic — `vmware-vdiskmanager.exe` and the VMX
need Windows paths, while the orchestrator needs Linux paths.

---

## Quick start

```bash
# 0. Can this host do it?
./scripts/00-preflight.sh

# 1. Create the VM (Windows side)
powershell -File scripts/10-create-vm.ps1

# 2. Decide SSH access — BEFORE the ISO is built. See "SSH access".
./scripts/20-make-ssh-key.sh
export SPAGAT_OPERATOR_AUTHORIZED_KEY='ssh-ed25519 AAAA... spagat-vm-lab@host'
export IPHASE6_INSTALL_STATIC_IP='192.168.225.140/24'

# 3. Build the ISO in that SAME shell (the exports must be live)
make iso-test BUILD_MANIFEST=... OUTPUT_ISO=/home/dcaso/work/iso-out-<sha>/appliance.iso

# 4. Prove the key actually landed in the ISO — do not assume
sudo ./scripts/40-check-staging.sh --iso /home/dcaso/work/iso-out-<sha>/appliance.iso

# 5. Install
./scripts/30-install-from-iso.sh --iso /home/dcaso/work/iso-out-<sha>/appliance.iso

# 6. Watch it
./scripts/50-verify-boot.sh

# 7. Get in
./scripts/60-ssh.sh
```

---

## The four things that actually bite

### 1. SSH access is decided at ISO **build** time, not after install

Both key variables default to **empty** in `iso-phase6`:

| variable | default | effect |
|---|---|---|
| `SPAGAT_OPERATOR_AUTHORIZED_KEY` | `""` | `operator`'s `authorized_keys` ships **empty** |
| `IPHASE6_TEST_SSH_PUBKEY` | `""` | no appended second key |
| `SPAGAT_ROOT_PASSWORD_HASH` | `"*"` | root **locked** |

So a build where nobody exported a key produces an appliance with correct
`0600` permissions on an **empty** `authorized_keys`, and no root password.
The only way in is the serial console.

This is the whole of the long-running "the appliance refuses my SSH key"
symptom — not an onboarding gate, not a credential subsystem bug. A previous
session even hardcoded a throwaway public key into the template *with no
matching private key anywhere*, which then mis-diagnosed 24+ access failures.

**There is no post-install fix.** Root is locked, so you cannot log in to add
a key. Export the variable and rebuild.

`scripts/40-check-staging.sh --iso <path>` extracts the kickstart *out of the
finished ISO* and prints the keys it contains, so you verify rather than hope.

### 2. `install-from-iso` only **edits** an existing `.vmx`

The orchestrator has no `createvm` / `vdiskmanager` path. VM creation is a
manual step outside the automated loop — exactly the kind of step that
silently drifts. That is why `10-create-vm.ps1` builds from a pinned template
instead of VMware's "New VM" wizard. Half the BUG-N series traces to one VMX
key being wrong.

The template pins, with the reason in a comment beside each:
`firmware=efi` · `uefi.secureBoot.enabled=FALSE` · `bios.bootOrder=hdd,cdrom` ·
`sata0.present=TRUE` · `scsi0.virtualDev=lsilogic` · `ethernet0.virtualDev=e1000` ·
the MAC **and** the BIOS UUID · `serial0.*` · `tools.syncTime=FALSE` ·
`msg.autoAnswer=TRUE`.

Two that catch people out:

- **CDROM must be on SATA.** The `linux-mok` kernel has no IDE CDROM driver.
  On `ide1:0` the installer boots but userspace `mount /mnt/media` finds no
  `/dev/sr0`, and you get a `LABEL="PHOTON_SB_5.0"` not-found failure that
  looks like a broken ISO.
- **The BIOS UUID must stay next to the MAC.** With
  `ethernet0.addressType="generated"`, VMware *derives* the MAC from the UUID.
  Both now come from `vm-lab.env` (`GUEST_MAC`, `GUEST_UUID_BIOS`) rather than
  being hardcoded in the template, so a second VM can be given its own pair
  instead of silently reusing this one's; `10-create-vm.ps1` warns if their
  last three bytes disagree. Drop the UUID and both regenerate, the
  `192.168.225.140` lease moves, and
  every hardcoded address in the runbooks quietly points at nothing.

### 3. The operator medium on `scsi0:1` is the credential channel — and is never regenerated here

`operator-config.vmdk` + `operator-config-flat.vmdk` (250 MiB
`monolithicFlat`, `lsilogic`) carry the signed credential bundle the appliance
reads at every boot. Verified in `install.rs`: `install-from-iso` strips only
`ide1:0.` `sata0:0.` `sata0:1.` `sata0.` `ethernet0.` `msg.autoAnswer`
`bios.bootOrder` — it **never references `scsi0:1`**, so the medium survives
any number of reinstalls verbatim.

- **Do not** pass `--efuse-vmdk` for it. That flag attaches an install-time
  marker on `sata0:0` which finalize then *detaches*; the operator medium is a
  persistent boot-time disk.
- Nothing in this directory creates or modifies it. `90-teardown.ps1`
  explicitly preserves it and checks its size.
- Without it the appliance boots **keyless** — every credential consumer logs
  `operator-config/credentials absent` and the onboarding wizard stays up.
  That is correct behaviour, not a bug.

### 4. Credentials never travel in the ISO

The medium is the channel. Never bake a credential into an image. If you also
want a root password, `install-from-iso` requires **both**
`--root-password-file` *and* `--operator-medium-dir` — all-or-nothing, so a
half-configured run cannot leak a password into an image. Passing one alone is
a hard error, and the plaintext is hashed in memory (`$6$` SHA-512-crypt);
only the hash is ever written.

Omit both and you get `BUG-N91: no --root-password-file supplied` in the log.
**That line is expected**, not a fault.

---

## The scripts, in order

### `00-preflight.sh`
Proves the host can do the job before anything is created: `vmrun` /
`vmware-vdiskmanager` present **and executable by you**, ≥20 GB free, the VM
not already running, the operator medium's size, whether a keypair exists.

Prints measured values rather than OK/FAIL, because "tool missing" and "tool
present but unreadable by this user" need different fixes and look identical
in a boolean. Running as `spagat-runner` is called out explicitly — `vmrun.exe`
is mode 744 owned by `dcaso`, so that user gets `vmrun IO: Permission denied`.

### `10-create-vm.ps1`
Creates the VM directory, a **50 GB thin single-file** `lsilogic` boot disk
(`monolithicSparse`, `RW 104857600 SPARSE`), and the VMX from the template.

Refuses to overwrite an existing disk or VMX — re-provisioning goes through
`90-teardown.ps1` first. `-RefreshVmxOnly` regenerates just the VMX (backing
up the old one). Fails loudly if any `@@PLACEHOLDER@@` survives substitution.

Because the disk is thin, 50 GB costs nothing up front: a fresh one is ~6 MB
and grows only as the guest writes. The headroom is wanted — a measured
appliance install passes 12 GB. The kickstart declares
`{ "mountpoint": "/", "size": 0 }` — grow to fill — so root takes the
remainder after `/boot/efi` 512 M and `/boot` 1 G.

**Single file is deliberate.** `vmware-vdiskmanager -t 0` keeps the entire
disk in one `.vmdk` whose extent line references itself, so a teardown moves
exactly one file aside. `-t 1` stores the same data split across 2 GB extents
(`…-s001.vmdk`, `…-s002.vmdk`, …) — more files for the same bytes, and the
split form is the one that tends to leave orphaned extents behind.

This script is ASCII-only on purpose. Windows PowerShell 5.1 reads `.ps1` as
ANSI without a BOM, so a single em-dash corrupts a string literal and produces
a cascade of misleading "missing closing brace" errors. `pwsh` 7 parses the
same file happily, so a parse check under 7 does **not** prove it runs under
5.1.

### `20-make-ssh-key.sh`
Generates a disposable ed25519 lab keypair and prints the exact `export`
lines the ISO build needs. Reuses an existing key rather than silently
replacing one. This key is a lab convenience, **not** an operator credential.

### `30-install-from-iso.sh`
Wraps `spagat-vm-orchestrator install-from-iso`.

- Refuses if the VM is running rather than passing `--force` — other VMs on
  the host may be live CI runners.
- **Verifies the ISO against its own `.sha256` sidecar before installing.** A
  short write on a 9p→NTFS copy produces a subtly broken appliance.
- Points `serial0.fileName` at a per-build log so RCA output from different
  images never interleaves, and records the existing log's length so only
  bytes past that offset belong to this run.
- Passes the **Linux** path. `vmx-info` parses `/mnt/c/...` and fails on
  `C:\...`; the orchestrator does the Windows translation itself.

### `40-check-staging.sh` — the one to reach for when something is "weird"
Checks staging at all three places it happens:

| section | question it answers |
|---|---|
| `--rootfs <dir>` | what the ISO was *built from*: build label, binary count, `/opt/spagat/appliance-src`, the `/var/spagat/audit` mode |
| `--iso <path>` | the four hashes agree; **and the kickstart extracted from the ISO — SSH keys, static IP, root-locked state** |
| `--guest` | what the running system did: installer vs installed boot, build identity, the credential-injection chain, port 22 |

Run section 2 **as root** — the sidecars are `0600 root`, and as another user
an unreadable file reads exactly like a hash mismatch. The script says so
rather than reporting a false MISMATCH.

### `50-verify-boot.sh`
The only unambiguous liveness instrument while root is locked is **whether the
serial log grows**. Everything else is inference, and these three readings are
all false signals:

- `vmrun list` **omits GUI-started VMs** — absence is not "off".
- CPU at `0.05` usually means the counter has not moved yet. Measure a delta
  over ~25 s.
- A black screen at t≈130 s is normal; the TUI starts at t≈133 s.

Also: `FAIL spagat-console: container not running` is a **red herring** — it
asserts on a retired container, not the live TUI. Grep for
`Started Spagat-Librarian Kanban TUI on tty1` instead.

### `60-ssh.sh`
Connects, and when it fails says *why* — key present? host reachable? port 22
open? — instead of leaving you with `connection refused`. Uses `BatchMode=yes`
so it never sits at a password prompt; root is locked, so there is no password
to give and an interactive prompt is always a dead end.

### `90-teardown.ps1`
Returns the VM to a fresh-disk state. **Nothing is deleted** — files are
renamed `.stashed-<timestamp>` and recovery is a rename back. Requires
`-Confirm`.

It stashes the *whole* chain (disk, snapshot deltas, `.vmsd`, `.vmsn`, NVRAM,
stale `.lck`), because if any piece survives, UEFI's removable-media fallback
finds the old ESP's `\EFI\BOOT\BOOTX64.EFI` and boots the **previous** image.
`bios.bootOrder` is ignored on EFI VMs, and deleting NVRAM alone does not help
— UEFI re-detects the disk.

Preserved: the operator medium, every serial log, and (unless `-IncludeVmx`)
the VMX with its pinned MAC/UUID.

---

## The kickstart

`kickstart/photon-appliance.ks.template.json` is a **byte-exact copy** of
`src/tools/iso-build/iso-phase6-kickstart-template.cfg`, which is what the
build actually consumes. Run `kickstart/check-drift.sh` to prove they still
match — a convenience copy that silently diverges is worse than no copy,
because you would reason about a kickstart the build never uses.

`check-drift.sh` has two modes and says which one it used:

- **Mode 1** — the canonical file is reachable (inside the SPAGAT repo, or via
  `SPAGAT_REPO=/path/to/SpagatLibrarian-Appliance`): it diffs against the live
  file and detects drift in **either** direction. This is the real check.
- **Mode 2** — standalone (e.g. in `photonos-scripts/staging`): it falls back
  to the hash in `EXPECTED-SHA256`. That still catches an edited local copy but
  **cannot** see upstream moving on. The script states this limitation rather
  than implying it proved more than it did, and exits non-zero if neither the
  canonical file nor the hash is available — "cannot check" must never read as
  "fine".

Placeholders and where each value comes from:

| placeholder | source | default |
|---|---|---|
| `{{ HOSTNAME }}` | `SPAGAT_HOSTNAME` | `spagat-librarian` |
| `{{ ROOT_PASSWORD_HASH }}` | `SPAGAT_ROOT_PASSWORD_HASH` | `*` (**locked**) |
| `{{ INSTALL_DISK }}` | `SPAGAT_INSTALL_DISK` | `/dev/sda` |
| `{{ SPAGAT_OPERATOR_AUTHORIZED_KEY }}` | env | **empty** |
| `{{ TEST_SSH_PUBKEY }}` | `IPHASE6_TEST_SSH_PUBKEY` | **empty** |
| `{{ INSTALL_STATIC_IP }}` | `IPHASE6_INSTALL_STATIC_IP` | `192.168.225.140/24` |
| `{{ WIZARD_PRESEED_TOML_B64 }}` | `IPHASE6_WIZARD_PRESEED_TOML` | empty |
| `{{ PAYLOAD_SHA256 }}` | computed from the overlay | — |

What the postinstall does that matters for this lab: installs and enables
`sshd`, creates `operator` with a `0700 .ssh` and `0600 authorized_keys`,
writes the static-IP `systemd-networkd` unit, enables `logrotate.timer`, and
masks `tmp.mount` so `/tmp` is disk-backed rather than a RAM tmpfs (BUG-N135 —
a 4 GB VM's tmpfs `ENOSPC`'d on temp-heavy writes).

---

## Configuration

Everything lives in `config/vm-lab.env`. Override by exporting before a call:

```bash
VM_NAME=my-lab BOOT_DISK_SIZE=30GB ./scripts/00-preflight.sh
```

Defaults:

| setting | default | notes |
|---|---|---|
| `GUEST_VCPUS` | `2` | the appliance profile was measured at 4 |
| `BOOT_DISK_SIZE` | `50GB` | the standing maximum; thin, so it is a ceiling not an allocation |
| `BOOT_DISK_TYPE` | `0` | `monolithicSparse` — thin, **single file**. Do not use `1` (2 GB split extents) |
| `GUEST_MEM_MB` | `4096` | `/run` is a RAM tmpfs sized from this; 4 GB is the tested floor |

For the full appliance profile:

```bash
GUEST_VCPUS=4 powershell -File scripts/10-create-vm.ps1
```

Other values you might legitimately change: `VM_NAME`, `SSH_KEY_NAME`.

Values you should not change without a specific reason: `GUEST_MAC` and the
BIOS UUID in the VMX template (they hold the IP lease together),
`BOOT_DISK_ADAPTER=lsilogic`, and `OPERATOR_MEDIUM_FLAT_BYTES`.

---

## Troubleshooting

| symptom | almost always |
|---|---|
| `Permission denied (publickey)` | no key was baked into the ISO — §1 |
| `vmrun IO: Permission denied` | running as `spagat-runner`; use `dcaso` |
| installer boots but `mount /mnt/media` fails | CDROM landed on IDE, not SATA |
| the VM boots the *previous* image | a piece of the old disk chain or NVRAM survived — `90-teardown.ps1` |
| `DISKUTIL: sata0:1 capacity=0` | the ISO is on a `\\wsl$\` UNC path; copy it to a local Windows path |
| every credential consumer says "absent" | the operator medium is missing from `scsi0:1` |
| `BUG-N91: no --root-password-file supplied` | expected — root installs locked |
| `FAIL spagat-console: container not running` | red herring — check for the Kanban TUI line instead |
| a `grep` of the serial log finds nothing | the log has NUL bytes; **use `grep -a`** or it silently prints nothing |

---

## Related

- `src/tools/iso-build/iso-phase6-kickstart-template.cfg` — canonical kickstart
- `tools/spagat-rust/crates/spagat-vm-orchestrator/` — the install/verify tool
- `deploy/kickstart-photon-host.cfg` — the *host* kickstart, a different thing
