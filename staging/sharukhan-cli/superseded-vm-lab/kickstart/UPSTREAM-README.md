# `iso-phase6-kickstart-template.cfg` — README

This sibling file documents `iso-phase6-kickstart-template.cfg` without using
underscore-prefixed keys inside the JSON itself (memory
`trap_kickstart_underscore_keys` — Photon installer's `_check_install_config()`
rejects any `_*` key and aborts the install).

## Placeholders

| Token | Substituted by phase 6 from… | Notes |
|---|---|---|
| `{{ HOSTNAME }}` | env `SPAGAT_HOSTNAME` (default `spagat-librarian`) | Hostname of the installed appliance. |
| `{{ ROOT_PASSWORD_HASH }}` | env `SPAGAT_ROOT_PASSWORD_HASH` (default `*` = locked) | Crypted hash. Default locks root; operator can override at build time. |
| `{{ SPAGAT_OPERATOR_AUTHORIZED_KEY }}` | env `SPAGAT_OPERATOR_AUTHORIZED_KEY` (default empty) | Verbatim SSH pubkey line written to `operator`'s `authorized_keys`. Empty = no coordinator key. Character-set validated by phase 6 (single quote, double quote, backslash, newline rejected). |
| `{{ TEST_SSH_PUBKEY }}` | env `IPHASE6_TEST_SSH_PUBKEY` (default empty) | Task #706 test-preseed path. Second SSH pubkey APPENDED to `authorized_keys` after `SPAGAT_OPERATOR_AUTHORIZED_KEY`. `make iso-test` sets it from `$(TEST_SSH_PUBKEY)`. Same charset validator as above. |
| `{{ WIZARD_PRESEED_TOML_B64 }}` | env `IPHASE6_WIZARD_PRESEED_TOML_B64` (default empty) | Task #706 test-preseed path. Standard-alphabet, no-line-wrap base64 of an `spagat_appliance_config::ApplianceConfig` TOML. Postinstall decodes to `/etc/spagat/appliance-config.toml` (0640, root:spagat per BUG-N65; was root:operator per feedback #837, superset via `m operator spagat`). Rust wrapper validates the raw TOML (`IPHASE6_WIZARD_PRESEED_TOML`) parses + carries `[operator]` table BEFORE base64-encoding — see `iso_phase6::preseed`. |
| `{{ WIZARD_COMPLETE_MARKER }}` | env `IPHASE6_WIZARD_COMPLETE_MARKER` (default empty) | Literal `"1"` or empty. When `"1"`, postinstall touches `/var/spagat/state/wizard-complete` as an operator-visible breadcrumb. NOTE: this marker file is NOT consulted by the ADR-0060 onboarding gate; the ACTUAL wizard-skip mechanism is a non-sentinel `[operator]` identity in the preseed above (see `spagat_appliance_config::first_boot_pending`). |
| `{{ INSTALL_STATIC_IP }}` | env `IPHASE6_INSTALL_STATIC_IP` (default `192.168.225.140/24`) | CIDR baked into the first-boot systemd-networkd `10-eth0-static.network` unit's `Address=` line. Gateway + DNS are still hardcoded to `192.168.225.2` — separate follow-up. |
| `{{ INSTALL_DISK }}` | env `SPAGAT_INSTALL_DISK` (default `/dev/sda`) | Target install disk. |
| `{{ LINUX_FLAVOR }}` | static `linux-mok` | The HABv4 MOK kernel variant phase 5 built. |
| `{{ PAYLOAD_SHA256 }}` | computed sha256 of `overlay.tar.zst` | Installer refuses install if on-disk payload sha mismatches. |
| `{{ SERVICES_ENABLE_JSON }}` | JSON array, walked from `OUTPUT_ROOTFS_DIR/etc/systemd/system/*.{service,timer,target}` | All units the installer should `systemctl enable` in the target rootfs. |
| `{{ SERVICES_TARGETS_JSON }}` | JSON object, walked from `OUTPUT_ROOTFS_DIR/etc/systemd/system/*.target.wants/` and `multi-user.target.wants/`, `timers.target.wants/` | Target → unit symlinks the installer should create. |

## How substitution works

Phase 6 does literal token replacement of `{{ TOKEN }}` strings (with leading +
trailing whitespace tolerated). It does NOT use a templating engine; the
template stays valid-shape JSON after substitution because:

- String tokens (`HOSTNAME`, `ROOT_PASSWORD_HASH`, `INSTALL_DISK`,
  `LINUX_FLAVOR`, `PAYLOAD_SHA256`) sit inside `"..."` already in the template.
- Composite tokens (`SERVICES_ENABLE_JSON`, `SERVICES_TARGETS_JSON`) are bare
  JSON values that phase 6 substitutes with valid JSON arrays/objects.

After substitution phase 6 runs `python3 -c 'import json,sys; json.load(open(sys.argv[1]))'`
on the result to fail-fast on any malformed substitution.

## What the installer does with it

The Photon installer (HABv4-patched, plus our M21.6.f1 monkey-patch from §7 of
spec 040, revised at M21.6.f1.f3) consumes this file at install-time:

1. `spagat_kickstart.py` (appended to the installer's initrd at
   `/usr/lib/python3.X/site-packages/photon_installer/installer_patches/`) is
   imported at startup via a hook line appended to
   `photon_installer/__init__.py`. It mutates the class-level
   `Installer.known_keys` set to allow the three `spagat_*` keys past
   `_check_install_config()`. (M21.6.f1.f3 simplified from wrapping the check
   method — the upstream class is `Installer`, not `InstallerConfig`, and
   `known_keys` is a public class attribute purpose-built for whitelisting.)
2. The standard installer install phase runs: partitions, package install,
   kernel install (`linux-mok`), grub install.
3. The post-install phase runs our `_spagat_post`: sha-verifies + extracts
   `spagat/overlay.tar.zst` into `/mnt/photon-root`, `systemctl enable`s every
   unit in `spagat_services_enable`, creates the symlinks in
   `spagat_services_targets`.
4. Reboot → MOK Quickstart UI (HABv4) → first boot → multi-user.target → kanban
   on tty1.

### Build-time receipt: `/.spagat-installer-patch-applied`

Phase 6 drops a stamp file at the initrd root containing:

```
patch_version: M21.6.f1.f3
applied_at: <ISO8601 UTC>
installer_module: /usr/lib/python3.X/site-packages/photon_installer/installer.py
installer_init:   /usr/lib/python3.X/site-packages/photon_installer/__init__.py
patches_dir:      /usr/lib/python3.X/site-packages/photon_installer/installer_patches
spagat_keys: spagat_overlay,spagat_services_enable,spagat_services_targets
```

The phase 6 fixture smoke step 16 unpacks the patched initrd and asserts this
file exists. Bastion-side smoke should do the same after the next install
campaign. Absence means the monkey-patch was not applied and the install will
crash at `_check_install_config()` — the M21.6.f1.f2 → f3 regression.

## `postinstall` — coreutils swap (MVP.B.f7, #518)

The `postinstall` shell block runs in the target rootfs chroot after all
packages have been installed but before reboot. Alongside the
`/etc/issue.spagat` marker, it force-swaps `coreutils-minimal` with the full
`coreutils` RPM shipped on the ISO.

**Why:** Photon 5's `minimal` package group resolves to `coreutils-minimal`,
which ships only `/usr/sbin/chroot`. The explicit `coreutils` entry in the
`packages` list is treated as a no-op by tdnf because `coreutils-minimal`
declares `Provides: coreutils` and there is no upgrade signal on a plain
`install` request. Without the swap, `/usr/bin/install` is absent from the
installed rootfs and every spagat-*.service unit with an
`ExecStartPre=/usr/bin/install -d …` line dies at first boot with:

```
Failed at step NAMESPACE spawning /usr/bin/install: No such file or directory
```

**Why not %post-level:** the linux-mok RPM `%post` runs inside the installer's
RPM transaction — the RPM DB is locked, so `tdnf install` / `rpm -Uvh` from
inside the `%post` is unsupported. `postinstall` runs after the transaction
completes and has a clean DB.

**Why rpm-direct, not tdnf:** the target rootfs's `/etc/yum.repos.d/` points
at online Photon repos. The appliance is designed for air-gapped install, so
`tdnf install coreutils` would fail without network. The ISO exposes every
package RPM at `/mnt/media/RPMS/x86_64/` throughout install, so `rpm -Uvh`
against the on-media RPM works offline.

The `[0-9]` glob + `grep -Ev 'minimal|lang|selinux'` filter deliberately
picks the un-suffixed `coreutils-<version>.ph5.x86_64.rpm` (not the -lang
or -selinux siblings, and never the -minimal we are replacing). Version
number is not hardcoded — same shape survives a coreutils bump.

## What does NOT belong here

- Comments inside the JSON itself (Photon installer rejects standard JSON
  comments; the template is pure JSON with NO `_*` underscore-prefixed keys —
  any doc / comment text lives here in this sibling README file).
- Operator secrets in plaintext (use the `crypted: true` hash form).
- Container image digests (those live in the overlay tarball's
  `var/cache/spagat-images/*.tar`).


## Disk sizing & /tmp placement (BUG-N135, task #948)

The appliance VM disk **must be <= 50 GB total**. For the VMware smoke VM that
is a 50 GB thin VMDK -- the descriptor's extent line reads
`RW 104857600 SECTORS ...` (104857600 x 512 B = 50 GiB). The kickstart
partition plan sizes `/boot/efi` (512 MiB) and `/boot` (1024 MiB) fixed and
gives **all remaining space to `/`** (`"size": 0`), so it adapts to any disk
<= 50 GB with no hardcoded root size.

**/tmp is disk-backed, not tmpfs.** Photon 5 mounts a RAM-backed `tmpfs` on
`/tmp` by default (~50% of RAM, ~2 GB on the 4 GB smoke VM). Anything that
writes growing or persistent data there fills RAM and is wiped on reboot,
which surfaced as recurring **"No space left on device"**. Two layers fix it:

1. **Real fix** -- `spagat-console` (the C UI) now writes its SQLite kanban DB
   to `/var/lib/spagat/console-state` and its subagent/CLI scratch files to
   `/var/tmp/spagat` (both disk-backed, created by `tmpfiles.d/spagat.conf`).
   `spagat-console.service` pins `SPAGAT_DB` + `TMPDIR` at those paths and
   lists them in `ReadWritePaths`. The C fallback in `get_db_path()` no longer
   points at `/tmp`.
2. **Backstop** -- the `postinstall` step above masks `tmp.mount`
   (`ln -sf /dev/null /etc/systemd/system/tmp.mount`), so even a stray `/tmp`
   writer lands on the root disk instead of RAM.

`systemd-tmpfiles` still age-cleans `/tmp` and `/var/tmp/spagat` (1d), so
neither grows without bound.
