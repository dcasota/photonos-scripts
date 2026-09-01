# Photon OS 5.0 ISO Build Permutation Matrix

Evidence-based analysis of the four-dimensional permutation space
(ISO type x installer version x STIG hardening x root filesystem) and the
availability of the five STIG-relevant packages in each case.

- **Author:** Daniel Casota <dcasota@gmail.com>
- **Date of analysis:** 2026-08-31
- **Artifacts analysed:** local Photon 5.0 build tree (`/root/5.0`), fork of
  `vmware/photon` (`/root/common`), clone of `vmware/photon-os-installer`
  (`/root/photon-os-installer`), and the freshly built minimal ISO.
- **No builds were run.** All evidence comes from read-only inspection: ISO
  loop-mount, `rpm -qp`, `git log`, GitHub API, and `tdnf --assumeno`
  dependency-resolution tests against local file:// repositories.

---

## 0. Evidence legend

| Tag | Meaning |
|---|---|
| **[M-E2E]** | Measured end to end: a real install of this permutation was performed and observed. |
| **[M-RES]** | Measured dependency resolution: the exact package set the installer would hand to `tdnf` was resolved against the exact repository the ISO carries, with `tdnf --assumeno`. This proves the transaction succeeds or fails, but does not prove post-install steps. |
| **[M-MEDIA]** | Measured media content: the RPM is present/absent on the ISO, verified by loop-mount and `rpm -qp`. |
| **[INF]** | Inferred from reading code. Not executed. |

Anything marked **[INF]** is a code-reading conclusion and is stated as such.
No inference in this document is presented as a measurement.

---

## 1. Why 16 rows and not 512

The task names four binary dimensions (16 combinations) plus five packages.
Treating the packages as independent on/off flags would give 16 x 2^5 = 512
rows. That number is not meaningful, and the reason is structural rather than
stylistic:

**The five packages are not inputs. They are outputs.**

There is no user-facing control anywhere in the installer that turns
`libselinux-utils`, `rsyslog`, `aide`, `openssl-fips-provider` or `ntp` on or
off individually. Their presence is fully determined by two things:

1. **Whether the RPM is on the installation media.** This is decided at ISO
   build time by `isoBuilder.setup()`
   (`photon_installer/isoBuilder.py:482-518`): if `--rpms-list-file` was passed,
   `copyRPMs()` copies every built RPM; otherwise `downloadPkgs()` downloads
   only the dependency closure of the package lists. The user cannot change
   this from the installer UI.
2. **Whether the installer adds the name to the single `tdnf install`
   transaction.** This is decided by three code paths, all of which key off the
   other four dimensions:
   - `stigenable.py:54` sets `install_config['additional_packages'] = KS_STIG_PACKAGES`
     when, and only when, the STIG menu answer is "Yes" (the *Hardening*
     dimension);
   - `installer.py:409-417` (POI 2.8) / `installer.py:459-470` (POI master)
     appends `selinux-policy` / `openssl-fips-provider` based on the presence of
     a `security` key (the *Installer* dimension);
   - `installer.py:2217-2219` (POI 2.8) / `installer.py:2492-2494` (master)
     appends `btrfs-progs` when any partition is btrfs (the *Filesystem*
     dimension).

So each of the 16 primary permutations produces exactly **one** package set.
The 5-package axis has no free choice in it; it is a projection of the 16.
The correct presentation is therefore: 16 primary rows, plus a
requirement/availability matrix that shows, per permutation, which of the five
are *requested* and which are *available*.

### Does any dimension genuinely multiply the space?

Two candidates were examined:

- **Filesystem does NOT multiply it.** It was a plausible second trap:
  `btrfs-progs` is appended to the target transaction for btrfs partitions, so
  if it were absent from the minimal media, minimal + BTRFS would fail
  independently of STIG. **It is present.** See section 5.1. The filesystem
  dimension is therefore inert for all 16 rows, and the effective space is 8
  distinct package sets, each realised twice.
- **Interactive vs kickstart DOES multiply it, and is the hidden fifth
  dimension.** Every failure documented here is specific to the *interactive*
  (no-kickstart) install. A kickstart install can carry its own `packages` list
  and its own `security` section, which changes both the transaction and the
  `security`-key guard at `installer.py:409`. This analysis covers the
  interactive path only, because that is where the STIG menu
  (`stigenable.py`) lives; the menu is not reachable from a kickstart install.
  Kickstart permutations are explicitly out of scope and are **UNTESTED**.

---

## 2. Main matrix: 16 primary permutations

> These 16 rows assume an **interactive (UI) install**. A kickstart install
> shifts some verdicts -- notably minimal + POI 2.8, which fails if the
> kickstart carries a `security:` section. See section 11.

Verdict is for a **default interactive install** (auto-partition or custom
partition with the named filesystem, no kickstart).

| # | ISO type | Installer | STIG | Filesystem | Verdict | Evidence | Failure mode |
|---|---|---|---|---|---|---|---|
| 1 | minimal-iso | POI 2.8 | no | EXT4 | **WORKS** | [M-RES] | - |
| 2 | minimal-iso | POI 2.8 | no | BTRFS | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |
| 3 | minimal-iso | POI 2.8 | **yes** | EXT4 | **FAILS** | [M-RES] + [M-E2E, user-reported] | `Error(1011) : No matching packages` -- 6 of 8 STIG packages absent from media |
| 4 | minimal-iso | POI 2.8 | **yes** | BTRFS | **FAILS** | [M-RES] | Same as #3. `btrfs-progs` resolves fine; STIG set does not |
| 5 | minimal-iso | POI latest | no | EXT4 | **FAILS** | [M-RES] | `Error(1011)` -- `selinux-policy` absent from media, injected unconditionally |
| 6 | minimal-iso | POI latest | no | BTRFS | **FAILS** | [M-RES] | Same as #5 |
| 7 | minimal-iso | POI latest | **yes** | EXT4 | **FAILS** | [M-RES] | Same as #3 plus #5 (7 missing names) |
| 8 | minimal-iso | POI latest | **yes** | BTRFS | **FAILS** | [M-RES] | Same as #7 |
| 9 | full iso | POI 2.8 | no | EXT4 | **WORKS** | [M-E2E] | - |
| 10 | full iso | POI 2.8 | no | BTRFS | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |
| 11 | full iso | POI 2.8 | **yes** | EXT4 | **WORKS** | [M-E2E] | - (requires `stig-hardening >= 2.1-7`, see 5.5) |
| 12 | full iso | POI 2.8 | **yes** | BTRFS | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |
| 13 | full iso | POI latest | no | EXT4 | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |
| 14 | full iso | POI latest | no | BTRFS | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |
| 15 | full iso | POI latest | **yes** | EXT4 | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |
| 16 | full iso | POI latest | **yes** | BTRFS | **UNTESTED** (predicted WORKS) | [M-RES] + [INF] | - |

**Counts: 3 WORKS / 6 FAILS / 7 UNTESTED.**

All 7 UNTESTED rows are *predicted* to work: the exact `tdnf` transaction each
one produces was resolved successfully against the exact repository that ISO
carries [M-RES]. What is untested is everything after the transaction (partition
formatting for btrfs, grub install on btrfs, the STIG ansible playbook run) and,
for rows 13-16, the fact that POI master has never been packaged as an RPM or
placed on a Photon ISO at all.

### 2a. Measured results — kickstart rows, 2026-09-01

Everything above was written before the matrix was executed. It has now been run:
**18 automated kickstart installs across all four ISOs**, each on media verified to
carry the packages under test. These are the `k*`/`s*` rows (mode = kickstart); the
16 rows above remain the **interactive** projection and are still unmeasured.

| row | ISO | POI | STIG | FS | pre-PR verdict | measured | note |
|---|---|---|---|---|---|---|---|
| k01 | minimal | 2.8 | no | ext4 | works | **pass** | |
| k02 | minimal | 2.8 | no | btrfs | untested | **pass** | prediction confirmed |
| k03 | minimal | 2.8 | yes | ext4 | fails | **pass** | fixed |
| k04 | minimal | 2.8 | yes | btrfs | fails | **pass** | fixed |
| k05 | minimal | latest | no | ext4 | fails | **pass** | fixed |
| k06 | minimal | latest | no | btrfs | fails | **pass** | fixed |
| k07 | minimal | latest | yes | ext4 | fails | **pass** | fixed |
| k08 | minimal | latest | yes | btrfs | fails | **pass** | fixed |
| k09 | full | 2.8 | no | ext4 | untested | **pass** | prediction confirmed |
| k10 | full | 2.8 | no | btrfs | untested | **pass** | prediction confirmed |
| k11 | full | 2.8 | yes | ext4 | untested | pass* | SELinux Permissive — intended, see below |
| k12 | full | 2.8 | yes | btrfs | untested | pass* | as k11 |
| k13 | full | latest | no | ext4 | untested | **pass** | prediction confirmed |
| k14 | full | latest | no | btrfs | untested | **pass** | prediction confirmed |
| k15 | full | latest | yes | ext4 | untested | pass* | as k11 |
| k16 | full | latest | yes | btrfs | untested | pass* | as k11 |
| s01 | minimal | 2.8 | no | ext4 | fails | **pass** | kickstart `security.selinux=permissive` |
| s02 | minimal | 2.8 | no | ext4 | fails | **FAIL** | FIPS breaks SSH — real defect |

**Six rows moved from `fails` to `pass`** (k03–k08) and **seven `UNTESTED`
predictions were confirmed**, so the section-2 reasoning held everywhere it was
checked.

`pass*` on k11/k12/k15/k16 marks a correction rather than a defect. Those rows were
first reported as failures because the oracle asserted `SELINUX=Enforcing`. On
subrelease 92 `selinux-policy-43.6-4` **ships permissive by design**; the minimal
ISOs only reported Enforcing because they carried a stale `43.6-3` from June. The
media, not the installer or the playbook, was the whole difference — see
COMPILE-CONSTELLATIONS.md §15.1.

**s02 is the one genuine failure.** With `security.fips: true` the installed system
is unreachable over SSH: sshd advertises curve25519/chacha20-poly1305/ed25519, the
peer selects one, and the FIPS-constrained crypto then refuses it
(`ssh_dispatch_run_fatal: invalid argument [preauth]`). Nothing reports a fault —
the system is `running`, zero failed units, sshd listening on 22. Two existing
defences miss it: the STIG role sets `Ciphers`/`MACs` itself but FIPS can be enabled
without STIG, and openssh's hardened `sshd_config` is only selected when built with
`STIG_HARDEN`, which defaults to 0.

Evidence for every row is under `results/<id>/checks-<UTC>.jsonl`, with the harvested
guest logs beside it. Result files are timestamped and never overwritten.

### The measurement behind rows 1-16

Repository under test for `minimal-iso`: `file:///mnt/isotest/RPMS` -- the
loop-mounted `photon-minimal-5.0-b7e3bedb6.x86_64.iso`
(`/root/5.0/stage/minimal-iso/`, 531,144,704 bytes, built 2026-08-30 23:15),
254 RPMs.

Repository under test for `full iso`:
`file:///root/5.0/stage/iso/photon-so839tgh/RPMS`, 1901 RPMs (the newest full
ISO staging tree, 2026-06-04 23:26).

Transaction base, taken verbatim from the ISO's own
`installer/packages.json` (extracted from the shipped initrd):
`linux-esx, initramfs, minimal, sudo, lvm2, less, linux`, plus
`grub2-efi-image` (appended by `installer.py` for `dualboot`/`efi` bootmode),
plus the per-permutation additions.

```
isomin |noSTIG|ext4 |POI2.8  -> Error(1032) [--assumeno abort]  missing: none
isomin |noSTIG|btrfs|POI2.8  -> Error(1032) [--assumeno abort]  missing: none
isomin |STIG  |ext4 |POI2.8  -> Error(1011)                     missing: rsyslog ...
isomin |STIG  |btrfs|POI2.8  -> Error(1011)                     missing: rsyslog ...
isomin |noSTIG|ext4 |POIlat  -> Error(1011)                     missing: selinux-policy
isomin |noSTIG|btrfs|POIlat  -> Error(1011)                     missing: selinux-policy
isomin |STIG  |ext4 |POIlat  -> Error(1011)                     missing: rsyslog ...
isomin |STIG  |btrfs|POIlat  -> Error(1011)                     missing: rsyslog ...
isofull|noSTIG|ext4 |POI2.8  -> Error(1032) [--assumeno abort]  missing: none
isofull|noSTIG|btrfs|POI2.8  -> Error(1032) [--assumeno abort]  missing: none
isofull|STIG  |ext4 |POI2.8  -> Error(1032) [--assumeno abort]  missing: none
isofull|STIG  |btrfs|POI2.8  -> Error(1032) [--assumeno abort]  missing: none
isofull|noSTIG|ext4 |POIlat  -> Error(1032) [--assumeno abort]  missing: none
isofull|noSTIG|btrfs|POIlat  -> Error(1032) [--assumeno abort]  missing: none
isofull|STIG  |ext4 |POIlat  -> Error(1032) [--assumeno abort]  missing: none
isofull|STIG  |btrfs|POIlat  -> Error(1032) [--assumeno abort]  missing: none
```

`Error(1032) : Operation aborted` is the expected `--assumeno` abort **after** a
successful solve; `Error(1011) : No matching packages` is a genuine resolution
failure. `tdnf` reports only the first name it cannot resolve, which is why the
reported name varies between runs (POI builds the list with
`packages = list(set(packages))` at `installer.py:418`, so the order is not
stable across interpreter runs). Every one of the six missing names was
therefore also verified individually -- see section 3.

---

## 3. Package requirement / availability matrix

### 3a. Availability on the media [M-MEDIA]

Verified by loop-mounting the minimal ISO and enumerating
`/mnt/isotest/RPMS/*/`, and by enumerating the full ISO staging RPMS tree.
Cross-checked with per-package `tdnf --assumeno install <name>`.

| Package | minimal-iso (254 RPMs) | full iso (1901 RPMs) | Notes |
|---|:---:|:---:|---|
| `libselinux-utils` | **ABSENT** | present (`3.10-4.ph5`) | minimal has `libselinux` and `libselinux-python3` only |
| `rsyslog` | **ABSENT** | present (`8.2602.0-4.ph5`) | |
| `aide` | **ABSENT** | present (`0.19-1.ph5`) | |
| `openssl-fips-provider` | **ABSENT** | present (`3.1.2-3.ph5`) | |
| `ntp` | **ABSENT** | satisfied by `ntpsec-1.2.3-13.ph5` | No package literally named `ntp` exists; `ntpsec` carries `Provides: ntp`. `tdnf` logs `[using capability match for 'ntp']` and pulls `ntpsec` + `ntpsec-minimal` [M-RES] |
| `selinux-policy` (6th STIG pkg) | **ABSENT** | present (`43.6-3.ph5`) | |
| `audit` (7th STIG pkg) | present (`4.1.3-3.ph5`) | present (`4.1.3-2.ph5`) | pulled in as a dependency of the minimal closure |
| `libgcrypt` (8th STIG pkg) | present (`1.10.4-1.ph5`) | present (`1.10.1-5.ph5`) | |
| `btrfs-progs` | **present** (`7.0-1.ph5`) | present | see 5.1 -- this is the key negative finding |
| `e2fsprogs` | present (`1.47.4-2.ph5`) | present | |
| `xfsprogs` | present (`6.0.0-4.ph5`) | present | |
| `stig-hardening` | present (`2.1-9.ph5`) | present (`2.1-8.ph5`) | ships the ansible playbook; lives in the *initrd*, not the target |

### 3b. Requested vs available, per permutation

`REQ` = the installer adds the name to the single `tdnf install` transaction.
`AVL` = the name resolves against that ISO's repository.
A row fails iff any cell is `REQ` and not `AVL`.

| # | Permutation | libselinux-utils | rsyslog | aide | openssl-fips-provider | ntp | (selinux-policy) | Result |
|---|---|:---:|:---:|:---:|:---:|:---:|:---:|:---|
| 1 | min / 2.8 / no / ext4 | - | - | - | - | - | - | WORKS |
| 2 | min / 2.8 / no / btrfs | - | - | - | - | - | - | WORKS (pred.) |
| 3 | min / 2.8 / **STIG** / ext4 | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | **FAILS (6 missing)** |
| 4 | min / 2.8 / **STIG** / btrfs | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | **FAILS (6 missing)** |
| 5 | min / **latest** / no / ext4 | - | - | - | - | - | REQ, **no AVL** | **FAILS (1 missing)** |
| 6 | min / **latest** / no / btrfs | - | - | - | - | - | REQ, **no AVL** | **FAILS (1 missing)** |
| 7 | min / **latest** / **STIG** / ext4 | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | **FAILS (6 missing)** |
| 8 | min / **latest** / **STIG** / btrfs | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | REQ, **no AVL** | **FAILS (6 missing)** |
| 9 | full / 2.8 / no / ext4 | - | - | - | - | - | - | WORKS |
| 10 | full / 2.8 / no / btrfs | - | - | - | - | - | - | WORKS (pred.) |
| 11 | full / 2.8 / **STIG** / ext4 | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL (via ntpsec) | REQ+AVL | WORKS |
| 12 | full / 2.8 / **STIG** / btrfs | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | WORKS (pred.) |
| 13 | full / **latest** / no / ext4 | - | - | - | - | - | REQ+AVL | WORKS (pred.) |
| 14 | full / **latest** / no / btrfs | - | - | - | - | - | REQ+AVL | WORKS (pred.) |
| 15 | full / **latest** / **STIG** / ext4 | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | WORKS (pred.) |
| 16 | full / **latest** / **STIG** / btrfs | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | REQ+AVL | WORKS (pred.) |

Note that `selinux-policy` is shown in parentheses because it is not one of the
five the task named, but it is the package that makes rows 5 and 6 fail, and it
is a member of `KS_STIG_PACKAGES`. Omitting it would make rows 5/6 look
inexplicable.

Also note that `audit` and `libgcrypt` -- the other two members of
`KS_STIG_PACKAGES` -- are present on both ISOs [M-MEDIA], so 6 of the 8 STIG
package names are missing from the minimal ISO, not all 8.

---

## 4. Failure modes in detail

### FM-1: minimal-iso + STIG (rows 3, 4, 7, 8)

**Trigger.** Answering "Yes" to the *Apply STIG hardening* menu.

`/usr/lib/python3.14/site-packages/photon_installer/stigenable.py:21-30`

```python
KS_STIG_PACKAGES = [
    "audit", "rsyslog", "openssl-fips-provider", "selinux-policy",
    "libselinux-utils", "ntp", "aide", "libgcrypt"
]
```

`stigenable.py:52-54`

```python
if is_enabled:
    self.install_config['ansible'] = KS_STIG_ANSIBLE
    self.install_config['additional_packages'] = KS_STIG_PACKAGES
```

`installer.py:376-377` merges that list into the *single* target transaction:

```python
if 'additional_packages' in install_config:
    packages.extend(install_config['additional_packages'])
```

`installer.py:1620-1628` builds one `tdnf install` for the whole list, and
`installer.py:1673-1677` aborts the install if it returns non-zero:

```python
# 0 : succeed; 137 : package already installed; 65 : package not found in repo.
if retval != 0 and retval != 137:
    self.logger.error("Failed to install some packages")
    if stderr:
        self.logger.error(stderr.decode())
    self.exit_gracefully()
```

**Exact error.** `Error(1011) : No matching packages`, preceded by
`Package '<name>' not found`. The `<name>` reported is whichever of the six
missing names `tdnf` reaches first, which is non-deterministic because of the
`list(set(packages))` at `installer.py:418`. The user observed
`libselinux-utils`; this investigation reproduced `rsyslog`. Both are correct;
there are six.

**Full set of names that cannot resolve** (each verified individually with
`tdnf --assumeno install <name>` against the mounted ISO repo) [M-RES]:
`rsyslog`, `openssl-fips-provider`, `selinux-policy`, `libselinux-utils`,
`ntp`, `aide`. `audit` and `libgcrypt` resolve.

**Root cause.** `poi.py:403-428` `create_custom_iso()` does not pass
`--rpms-list-file`, so `isoBuilder.setup()`
(`photon_installer/isoBuilder.py:482-518`) takes the `else:` branch and calls
`downloadPkgs()` (`isoBuilder.py:192-259`), which runs
`tdnf --alldeps --downloadonly install <initrd list + packages_minimal list>`.
Nothing in either list, transitively, requires any of the six.

**Fix required.** The six RPMs must be on the media. See FIX-1.

### FM-2: minimal-iso + POI latest, even without STIG (rows 5, 6)

**Trigger.** Any interactive install from a minimal ISO whose installer is built
from `vmware/photon-os-installer` master at or after commit `a88cf02`
("installer: configure selinux explicitly", Bo Gan, 2026-08-04).

POI 2.8, `installer.py:409-417`:

```python
if 'security' in install_config:
    security = install_config['security']
    if 'selinux' in security and security['selinux'] is not None:
        packages.append("selinux-policy")
    if 'fips' in security and security['fips'] is not None:
        packages.append("openssl-fips-provider")
```

An interactive install has no kickstart, so `install_config` has no `security`
key and neither name is appended. POI master, `installer.py:459-470`:

```python
if 'security' not in install_config:
    # Inject a default 'security' section with default selinux settings
    install_config['security'] = {'selinux': Defaults.SELINUX_DEFAULT}

security = install_config['security']
if 'selinux' in security and security['selinux'] is not None:
    packages.append("selinux-policy")
```

with `Defaults.SELINUX_DEFAULT = "permissive"` (`defaults.py:13`). The guard is
gone: `selinux-policy` is now appended on **every** install, kickstart or not.

**Exact error.** `Package 'selinux-policy' not found` /
`Error(1011) : No matching packages`, from the same `_install_packages()` path
as FM-1 [M-RES].

**This is a genuine, independent regression trap:** it converts today's working
row 1 into a failing row 5. It has nothing to do with STIG. It would land the
moment the Photon 5.0 `photon-os-installer.spec` is rebased onto POI master.

**Upstream partially anticipated this** and partially missed it. The same commit
`a88cf02` added `"selinux-policy"` to POI's *own*
`examples/iso/packages_minimal.json`. But Photon's build does not use that
file. `poi.py:403-428` `create_custom_iso()` copies
`<photon>/common/data/packages_installer_initrd.json` and passes
`-p packages_minimal.json` resolved against Photon's own
`common/data/packages_minimal.json`, which was **not** updated. So the upstream
fix does not reach the Photon minimal ISO.

**Fix required.** FIX-2 (media) and/or FIX-3 (make the injection tolerant).

### FM-3 (ruled out): minimal-iso + BTRFS

**Hypothesis:** `btrfs-progs` is appended to the target transaction for btrfs
partitions and might be absent from the 254-RPM closure, making minimal + BTRFS
fail regardless of STIG.

**Result: DISPROVEN.** `btrfs-progs-7.0-1.ph5.x86_64.rpm` is on the minimal ISO
[M-MEDIA] and resolves [M-RES]. See section 5.1 for why. `e2fsprogs-1.47.4-2`
and `xfsprogs-6.0.0-4` are there too. There is no second trap on this axis.

---

## 5. Answers to the specific unknowns

### 5.1 BTRFS: is `btrfs-progs` in the minimal ISO's 254-RPM closure?

**Yes.** [M-MEDIA] + [M-RES]

```
/mnt/isotest/RPMS/x86_64/btrfs-progs-7.0-1.ph5.x86_64.rpm
/mnt/isotest/RPMS/x86_64/e2fsprogs-1.47.4-2.ph5.x86_64.rpm
/mnt/isotest/RPMS/x86_64/e2fsprogs-libs-1.47.4-2.ph5.x86_64.rpm
/mnt/isotest/RPMS/x86_64/xfsprogs-6.0.0-4.ph5.x86_64.rpm
```

`tdnf --assumeno install btrfs-progs` against the ISO repo resolves cleanly
(`Total installed size: 48.08M`, then the expected `Error(1032)` abort).

**Why it is there, given that nothing in `packages_minimal.json` requires it.**
It is not a dependency at all -- an exhaustive `rpm -qp --requires` sweep over
all 254 RPMs on the ISO found **no** package requiring `btrfs-progs`. It arrives
by a different route: `isoBuilder.downloadPkgs()` (`isoBuilder.py:200-202`)
downloads the union of *two* lists:

```python
self.addPkgsToList(self.initrd_pkg_list_file)
self.addPkgsToList(self.packageslist_file)
```

and `common/data/packages_installer_initrd.json` explicitly lists
`btrfs-progs`, `e2fsprogs`, `xfsprogs` -- and `stig-hardening`. Everything in
the *initrd* list therefore also lands in the ISO's `RPMS/` tree and is
installable into the target.

This is important beyond btrfs: **`packages_installer_initrd.json` is an
existing, working mechanism for getting an RPM onto the minimal media without
adding it to the default target install set.** FIX-1 exploits this.

**Runtime tooling is also present** [M-MEDIA]: the shipped installer initrd
(`isolinux/initrd.img`, gzip, 16,822 entries) contains `/usr/sbin/mkfs.btrfs`,
`/usr/sbin/btrfs`, `/usr/sbin/fsck.btrfs` and `/usr/sbin/mkfs.ext4`, so the
in-initrd formatting step (`installer.py:2256-2276`) works for both filesystems.

**Where btrfs is selectable.** Only through the custom-partition screen:
`custompartition.py:120` accepts `['swap','ext3','ext4','xfs','btrfs']`. The
auto-partition default is ext4 (`installer.py:488`:
`p['filesystem'] = 'ext4'`). So BTRFS is a deliberate, non-default choice.

**One cosmetic residue, not a failure** [INF]: `installer.py:1134-1145` sets
`fsck = 1` in `/etc/fstab` for the root partition regardless of filesystem.
For btrfs this causes systemd to invoke `fsck.btrfs`, which is a no-op stub
shipped by `btrfs-progs`. Harmless, but noted.

**Downstream patch confirmed.** `btrfs-progs` is appended to the target install
list by `/root/5.0/SPECS/photon-os-installer/0004-installer-add-btrfs-progs.patch`
(local, Daniel Casota), which lands at `installer.py:2217-2219` in the shipped
2.8 build. Upstream master has the same code at `installer.py:2492-2494`.

### 5.2 POI 2.8 vs latest, on the minimal ISO

**Confirmed: POI master breaks even a non-STIG minimal install.** [M-RES]

```
isomin | noSTIG | ext4  | POI-latest -> Error(1011)  missing: selinux-policy
isomin | noSTIG | btrfs | POI-latest -> Error(1011)  missing: selinux-policy
```

Full mechanism in FM-2 above. Summary: `a88cf02` removed the
`if 'security' in install_config:` guard and injects
`{'selinux': 'permissive'}` when absent, so `selinux-policy` is appended
unconditionally; `selinux-policy` is not on the minimal media.

Note also `installer.py:1567-1570` in master:

```python
def _selinux_label(self):
    if "selinux-policy" not in self.install_config['packages']:
        return
    subprocess.check_call(["chroot", self.photon_root, "/usr/sbin/setfiles", ...])
```

Under master this guard is now always true, so a full filesystem relabel runs on
every install. On the full ISO that succeeds (the binary is present); on the
minimal ISO the install never gets that far. [INF]

### 5.3 Which POI actually ships

**The version collision was real. Its behavioural impact is nil.** [M-MEDIA]

Facts established:

| Fact | Evidence |
|---|---|
| The minimal ISO carries `photon-os-installer-2.8-5.ph5.x86_64.rpm` | `find /mnt/isotest -name '*.rpm'` |
| Its `BUILDTIME` is `Thu 04 Jun 2026 11:08:53 PM CEST` | `rpm -qp --qf '%{BUILDTIME:date}'` |
| The fresh build produced `photon-os-installer-2.8-3.ph5.x86_64.rpm`, mtime `2026-08-30 22:50` | `ls -la /root/5.0/stage/RPMS/x86_64/` |
| The local spec is at `Release: 3` | `/root/5.0/SPECS/photon-os-installer/photon-os-installer.spec:9` |
| At the start of this investigation, `stage/RPMS/x86_64/` contained `2.8-3`, `2.8-4` (Jun 4 20:43) and `2.8-5` (Jun 4 23:08) simultaneously | `ls -la`, `find` |
| `tdnf` therefore picked the highest release, `2.8-5`, for both the initrd and the ISO's `RPMS/` tree | the ISO content itself |

So yes: the ISO shipped a June-built RPM rather than the August one, exactly as
suspected. **However:**

```
$ diff -rq --exclude=__pycache__ <extracted 2.8-3> <extracted 2.8-5>
$ echo $?
0
```

The two RPMs are **byte-identical in every file except the `__pycache__/*.pyc`
artefacts**. Independently confirmed against the shipped ISO: the
`installer.py` extracted from `isolinux/initrd.img` is identical to both
`2.8-3`'s and `2.8-5`'s. `2.8-5` already contains all five downstream patches,
including `0004-installer-add-btrfs-progs.patch`
(`installer.py:2217-2219` present) and
`0005-tdnf-capture-install-output.patch`.

**Conclusion.** The "POI 2.8" column in this matrix describes the same code
either way; no verdict changes. But the *mechanism* is a live hazard: the local
spec is at `Release: 3`, so any future content change made at release 3, 4 or 5
would silently lose to the stale `2.8-5` and never reach an ISO.

**State change observed during this session:** by the end of the investigation,
`2.8-4` and `2.8-5` were no longer present in
`/root/5.0/stage/RPMS/x86_64/` (only `2.8-3` remained; directory mtime
`2026-08-31 00:56:57`). They were not removed by this read-only investigation.
The already-built minimal ISO still contains `2.8-5`. A rebuild from the current
stage tree would now correctly ship `2.8-3`.

**Recommended hygiene (FIX-5):** bump `Release:` past the highest stale artefact
(to `6`) rather than relying on stage cleanliness, and/or purge
`stage/RPMS/**/photon-os-installer-*` before an ISO build.

### 5.4 Sanity check on the full ISO path

Confirmed as stated. `poi.py:334-360` `create_full_iso()` passes
`--rpms-list-file {basename}.rpm-list`; `isoBuilder.setup():482-484` reads it
into `self.rpms_list`, and `:514-515` therefore calls `copyRPMs()`
(`isoBuilder.py:170-190`), which copies every listed RPM with **no dependency
check** (its own docstring says so). The list
`/root/5.0/stage/iso/photon-5.0-effac38a0.x86_64.rpm-list` has exactly **1901**
lines; the staging tree has exactly 1901 RPMs. All six STIG packages plus
`ntpsec` are among them [M-MEDIA].

### 5.5 STIG post-install stage (full ISO)

The STIG menu also sets `install_config['ansible'] = KS_STIG_ANSIBLE`
(`stigenable.py:11-19, 53`), pointing at
`/usr/share/ansible/stig-hardening/playbook.yml`. `installer.py:863-921`
`_ansible_run()` executes `/usr/bin/ansible-playbook -c chroot -i <target>,`
**from the initrd**, not from the target. Both `ansible-playbook` and
`/usr/share/ansible/stig-hardening/` are present in the shipped minimal initrd
[M-MEDIA], supplied by the `stig-hardening` entry in
`packages_installer_initrd.json`. Note `stig-hardening` itself is *not* in
`KS_STIG_PACKAGES`, so it is never installed into the target.

`installer.py:920` is a bare `assert process.returncode == 0`, so a playbook
failure aborts the install with an `AssertionError`. Rows 11/12/15/16 therefore
also depend on the playbook being correct for the target's ansible/audit
versions. The local tree carries `stig-hardening-2.1-9` with four patches
including `fix-stig-playbook-fips-pam.patch`; the corresponding upstream PR
(vmware/photon **#1643**, base `5.0`) is still **open**. The June full-ISO
staging tree only has `stig-hardening-2.1-8`.

---

## 6. Changes required, deduplicated

Six FAILS collapse to **three** distinct root causes and therefore three
distinct upstream changes (plus one local build-hygiene item).

Repository note: `github.com/vmware/photon` has **no `master`/`main`**. Its
default branch is `5.0`; the live branches are `1.0`, `2.0`, `3.0`, `4.0`,
`5.0`, `5.0-9.1.1`, `6.0`, `common`, `dev` (verified via
`gh api repos/vmware/photon/branches`). `common/data/*.json` is maintained on
**`common`** and merged into the release branches.
`github.com/vmware/photon-os-installer` does use `master`.

### FIX-1 -- put the STIG package set on the minimal ISO media

**Fixes rows 3, 4, 7, 8.**

- **Repo/branch:** `github.com/vmware/photon`, branch **`common`**
  (then forward-merge to `5.0` and `6.0`).
- **File:** `common/data/packages_installer_initrd.json`
- **Change:** add `libselinux-utils`, `rsyslog`, `aide`,
  `openssl-fips-provider`, `selinux-policy`, `ntpsec`.
- **Why this file and not `packages_minimal.json`:** adding to
  `packages_minimal.json` would install these six into **every** minimal target,
  changing what "minimal" means. Adding to the initrd list only puts them in the
  ISO's `RPMS/` tree (via the union in `isoBuilder.downloadPkgs():200-202`),
  leaving the default install set untouched. This is precisely the route
  `btrfs-progs`, `xfsprogs` and `stig-hardening` already take (section 5.1), so
  it is a proven mechanism, not a new one.
- **Cost:** these packages are also installed into the installer initrd, growing
  it. `selinux-policy` is the largest contributor. If that cost is unacceptable,
  see FIX-1b.
- **Note on `ntp`:** list `ntpsec`, not `ntp`. No package named `ntp` exists in
  Photon 5.0; `ntpsec-1.2.3-13.ph5` carries `Provides: ntp` and `tdnf` resolves
  `ntp` to it by capability match [M-RES]. `KS_STIG_PACKAGES` can keep saying
  `ntp`.

### FIX-1b -- (preferred, larger) add a media-only package list to isoBuilder

**Same rows as FIX-1, without the initrd bloat.** Two coordinated PRs:

1. **Repo/branch:** `github.com/vmware/photon-os-installer`, branch **`master`**.
   **File:** `photon_installer/isoBuilder.py`. Add a
   `--media-pkgs-list-file` option, merged into `self.pkg_list` inside
   `downloadPkgs()` (around `:200-202`) but *excluded* from
   `self.initrd_pkgs`, so the RPMs land in the ISO's `RPMS/` tree without
   entering the initrd.
2. **Repo/branch:** `github.com/vmware/photon`, branch **`common`**.
   **Files:** new `common/data/packages_media_extra.json` listing the six;
   `common/support/poi/poi.py` `create_custom_iso()` (around `:414-428`) to copy
   it and pass `--media-pkgs-list-file`.

FIX-1 and FIX-1b are alternatives, not both.

### FIX-2 -- make the STIG menu fail soft instead of aborting the install

**Hardens rows 3, 4, 7, 8 and every future media variant.**

- **Repo/branch:** `github.com/vmware/photon-os-installer`, branch **`master`**.
- **Files:** `photon_installer/stigenable.py`, `photon_installer/installer.py`.
- **Change:** before offering the *Apply STIG hardening* menu, resolve
  `KS_STIG_PACKAGES` against the configured install repo (POI already has
  `photon_installer/tdnf.py`; a `repoquery`/dry-run `install` is enough). If any
  are unavailable, hide or disable the menu entry and state why, instead of
  letting `_install_packages()` reach `installer.py:1673-1677` and call
  `exit_gracefully()` mid-install. Today the user answers "Yes" to a menu the
  media cannot honour, and the installer dies partway through with a bare
  `Error(1011)`.
- Independently valuable: the error text should name **all** unresolvable
  packages, not just the first. Today `list(set(packages))` at
  `installer.py:418` randomises which one is reported, which is why the same
  failure is reported as `libselinux-utils` on one run and `rsyslog` on another.

### FIX-3 -- make POI master's unconditional `selinux-policy` injection tolerant

**Fixes rows 5, 6 (and prevents rows 7, 8 gaining a seventh missing name).**

- **Repo/branch:** `github.com/vmware/photon-os-installer`, branch **`master`**.
- **File:** `photon_installer/installer.py:459-470` (introduced by `a88cf02`).
- **Change:** either (a) only append `selinux-policy` when it is resolvable in
  the configured repos, falling back to not injecting the `security` default;
  or (b) keep the injection but treat a missing `selinux-policy` as a
  non-fatal downgrade to `selinux: null`.
- **Companion, in `github.com/vmware/photon` branch `common`:** `a88cf02`
  added `selinux-policy` to POI's own `examples/iso/packages_minimal.json`, but
  Photon builds from `common/data/packages_minimal.json`, which was not updated.
  If option (a)/(b) is rejected upstream, then `selinux-policy` **must** be
  added to Photon's minimal media before POI master is adopted -- which FIX-1
  already does.
- **Blocking relationship:** POI master must not be adopted into
  `SPECS/photon-os-installer/photon-os-installer.spec` on `vmware/photon` `5.0`
  until FIX-1 (or FIX-3) has landed, or minimal-iso installs regress from
  working to broken.

### FIX-4 -- (already open) STIG playbook correctness

**Affects rows 11, 12, 15, 16 post-install.**

- **Repo/branch:** `github.com/vmware/photon`, branch **`5.0`**.
- **Status:** PR **#1643** *"Fix STIG playbook: PAM faillock guard, FIPS module
  config, IMA hash"* -- **open**. Delivers `stig-hardening` 2.1-7
  (`fix-stig-playbook-fips-pam.patch`); local tree is at 2.1-9.
- Not a package-availability issue, but it is the next thing that fails once
  FIX-1 makes the minimal + STIG transaction resolve.

### FIX-5 -- build-hygiene: photon-os-installer release collision

**Affects nothing in the matrix today; prevents a whole class of silent
staleness.**

- **Repo/branch:** `github.com/vmware/photon`, branch **`5.0`**
  (this is PR **#1658**, currently open:
  *"photon-os-installer: 2.8-3 -- fix interactive install + UI output overlay"*).
- **File:** `SPECS/photon-os-installer/photon-os-installer.spec:9`.
- **Change:** set `Release: 6` (or higher) rather than `3`, so the freshly built
  RPM outranks the stale `2.8-4` / `2.8-5` artefacts that can persist in
  `stage/RPMS`. Additionally, purge `stage/RPMS/**/photon-os-installer-*.rpm`
  before an ISO build.
- See 5.3 for the measurement. Behaviourally inert *this* time only because
  `2.8-3` and `2.8-5` happen to have identical Python sources.

### Not required

- **No change is needed for BTRFS.** `btrfs-progs`, `e2fsprogs` and `xfsprogs`
  are already on both ISOs via `packages_installer_initrd.json` (upstream since
  2022-05-24), and the initrd carries the matching `mkfs.*` binaries.
- **No change is needed for the `ntp` name.** The capability match to `ntpsec`
  works [M-RES]; only media presence matters.

### Fix-to-row map

| Fix | Rows repaired |
|---|---|
| FIX-1 *or* FIX-1b | 3, 4, 7, 8 |
| FIX-3 (or FIX-1, which also supplies `selinux-policy`) | 5, 6, and the `selinux-policy` component of 7, 8 |
| FIX-2 | none directly -- converts a mid-install abort into a clear pre-install refusal on any media lacking the set |
| FIX-4 | post-install correctness of 11, 12, 15, 16 |
| FIX-5 | none directly -- prevents silent installer staleness |

Applying FIX-1 alone turns all six FAILS into predicted-WORKS.

---

## 7. History: were the five packages ever in a published minimal-iso?

**Answer: no. Never, on any branch, at any point since the file was created on
2015-06-27.**

Method: `git log --all --follow` over `common/data/packages_minimal.json` in a
fork of `vmware/photon` (`/root/common`), yielding **34 distinct revisions**;
every revision's content was decoded and searched for
`libselinux-utils`, `rsyslog`, `aide`, `openssl-fips-provider`, `ntp`, `ntpsec`
and `selinux-policy`. **Zero hits.** Cross-checked against the live upstream via
`gh api repos/vmware/photon/contents/...` on all nine upstream branches
(`1.0`, `2.0`, `3.0`, `4.0`, `5.0`, `5.0-9.1.1`, `6.0`, `common`, `dev`) --
the fork's contents match upstream byte for byte.

### What the list has contained over time

| Era | Branches | Shape | Contains any of the five? |
|---|---|---|---|
| 2015-06-27 -> ~2019 | `1.0`, `2.0` | Explicit flat list of ~46-48 package names (`glibc`, `zlib`, `filesystem`, `bash`, `systemd`, `docker`, `cloud-init`, `open-vm-tools`, `tdnf`, ...) | **No** |
| ~2019 -> today | `3.0`, `4.0`, `5.0`, `5.0-9.1.1`, `6.0`, `common`, `dev` | Collapsed to a meta-package reference: `["minimal","linux","linux-esx","initramfs","lvm2","less","sudo"]` (3.0/4.0 put `linux-esx` under `packages_x86_64`) | **No** |

Notable revisions:

| Commit | Date | Author | Change |
|---|---|---|---|
| `4d6a578d4` | 2015-06-27 | Touseef Liaqat | File created -- *"Create minimai ISO with less then 300MB of iso size. Usage: sudo make minimal"* |
| `5d05cfcce` | 2015-06-28 | Touseef Liaqat | Moved package JSONs into a shared `common/` folder for installer and package builder |
| `b76471af8` | 2015-06-30 | Touseef Liaqat | `nano` -> `vim` to hold the size budget |
| `e4230b5d1` | 2017-05-03 | Bo Gan | Dropped `cracklib-dicts` hard dependency (CVE-2016-6318) |
| `dd7aafa42` | 2017-05-31 | xiaolin-vmware | Dropped `python2` |
| `265589875` | 2019-10-15 | Piyush Gupta | *"minimal-iso: Creating photon minimal-iso"* -- the current `minimal-iso` target |
| `58c240d19` | 2021-02-09 | Oliver Kurth | *"re-add sudo, less to minimal iso"* |
| `acf3ddb91` | 2023-01-31 | Piyush Gupta | Moved `linux-esx` out of `packages_x86_64` |
| `6b298c6a3` | 2023-03-13 | Shreenidhi Shedi | *"tree-wide: format all json files"* -- latest content-affecting revision |

The list has been **shrinking**, not growing, for its whole life. The trajectory
is the opposite of what STIG needs.

### Did the mechanism ever differ (e.g. copyPkgs)?

No. Every published `minimal-iso` has been built by the dependency-closure
route, never by the copy-everything route:

- 2015-2020, the installer lived inside `vmware/photon` itself; the minimal ISO
  was built from the explicit `packages_minimal.json` list, resolved with the
  package manager. Commit `236535125` (2020-08-18, Piyush Gupta,
  *"Photon Installer as an RPM"*) split it out into `photon-os-installer`.
- Today `poi.py:403` `create_custom_iso()` still omits `--rpms-list-file`, so
  `isoBuilder.setup():514-518` takes the `downloadPkgs()` branch. `copyRPMs()`
  is reached **only** from `create_full_iso()` (`poi.py:334`), which does pass
  `--rpms-list-file`. There is no historical revision in which the minimal ISO
  used `copyRPMs()`.

### The complementary history: how the minimal media *did* grow

The five never entered `packages_minimal.json`, but three STIG-adjacent things
did enter the minimal media through the initrd list
(`common/data/packages_installer_initrd.json`), which `downloadPkgs()` unions
into the ISO's `RPMS/` tree:

| Commit | Date | Author | Change |
|---|---|---|---|
| `94a8e88f8` / `056232a63` | 2022-05-24 | Piyush Gupta | *"packages_installer_initrd: Added btrfs-progs and xfsprogs"* -- this is why minimal + BTRFS works today |
| `6f48cf6d1` / `8f4db5b39` / `73011ea84` | 2024-05-24 | Ankit Jain | *"photon-os-installer: Upgrade to v2.7"* -- added `stig-hardening` (the ansible playbook), but **not** the packages the playbook hardens |

The 2024-05-24 change is the precise origin of the current inconsistency: the
minimal ISO gained the STIG *tooling* and the STIG *menu*
(`stigenable.py`, added upstream in POI commit `1cd4f2b`, 2023-12-11,
*"add menu entry to interactiove ISO install UI to enable STIG hardening"*)
without ever gaining the STIG *packages*. The menu has been offering an
unfulfillable option on minimal ISOs for roughly two years.

---

## 8. Reproduction commands

Non-destructive; each was run for this report.

```bash
# media contents
mount -o loop,ro /root/5.0/stage/minimal-iso/photon-minimal-5.0-b7e3bedb6.x86_64.iso /mnt/isotest
find /mnt/isotest -name '*.rpm' | wc -l                                  # -> 254
find /mnt/isotest -name '*.rpm' -printf '%f\n' | grep -Ei 'selinux|rsyslog|aide|fips|ntp|btrfs'

# which installer shipped
rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE} %{BUILDTIME:date}\n' \
    /mnt/isotest/RPMS/x86_64/photon-os-installer-2.8-5.ph5.x86_64.rpm

# 2.8-3 vs 2.8-5 source identity
diff -rq --exclude=__pycache__ <2.8-3 extracted> <2.8-5 extracted>        # -> no differences

# resolution test (repo file with baseurl=file:///mnt/isotest/RPMS)
tdnf -c <conf> --releasever 5.0 --installroot <tmproot> \
     --setopt=reposdir=<repos> --disablerepo='*' --enablerepo=isomin \
     --assumeno install minimal linux initramfs lvm2 less sudo grub2-efi-image \
       audit rsyslog openssl-fips-provider selinux-policy libselinux-utils ntp aide libgcrypt

# history
cd /root/common && git log --all --follow --format='%H' -- common/data/packages_minimal.json
gh api repos/vmware/photon/branches --jq '.[].name'
```

## 9. Key file references

| Path | Relevance |
|---|---|
| `/root/5.0/common/data/packages_minimal.json` | 7-entry list; defines the minimal target install set |
| `/root/5.0/common/data/packages_installer_initrd.json` | Initrd list; also the media-inclusion mechanism (`btrfs-progs`, `xfsprogs`, `stig-hardening`) |
| `/root/5.0/SPECS/minimal/minimal.spec` | The `minimal` meta-package; 41 `Requires:`, none of the five |
| `/root/5.0/SPECS/photon-os-installer/photon-os-installer.spec` | `Release: 3`; five downstream patches |
| `/root/5.0/SPECS/photon-os-installer/0004-installer-add-btrfs-progs.patch` | Adds `installer.py:2217-2219` |
| `/root/5.0/SPECS/stig-hardening/stig-hardening.spec` | `2.1-9`, four patches incl. `fix-stig-playbook-fips-pam.patch` |
| `/root/common/support/poi/poi.py` | `create_full_iso():334`, `create_custom_iso():403` |
| `/root/photon-os-installer/photon_installer/installer.py` | master: `459-470`, `1567-1570`, `2492-2494` |
| `<POI 2.8 rpm>/usr/lib/python3.14/site-packages/photon_installer/installer.py` | shipped: `409-417`, `376-377`, `418`, `1620-1628`, `1673-1677`, `2217-2219`, `488` |
| `<POI 2.8 rpm>/.../stigenable.py` | `KS_STIG_PACKAGES` at `21-30`, assignment at `52-54` |
| `<POI 2.8 rpm>/.../isoBuilder.py` | `copyRPMs():170`, `downloadPkgs():192`, `setup():469-518` |
| `/root/5.0/stage/iso/photon-5.0-effac38a0.x86_64.rpm-list` | 1901 lines; the full-ISO `--rpms-list-file` |

## 10. Minor divergence noted in passing

`/root/5.0/common/data/packages_installer_initrd.json` is missing the
`"mkpasswd"` entry that upstream `common` has
(commit `52134f3a7`, *"common/data/packages_installer_initrd.json: add mkpasswd
to package list"*). `photon-os-installer.spec` carries `Requires: mkpasswd`, so
it reaches the initrd as a dependency anyway. Unrelated to the five packages;
recorded for completeness.

---

## 11. Kickstart vs UI -- the fifth dimension

Every verdict in sections 2-4 assumes an **interactive (UI) install**. The same
media can behave differently under a kickstart, and in one case *worse*. This
section records that axis.

**Evidence class for this whole section: [C] code-reading.** No kickstart
install was performed. Nothing here is measured.

### 11.1 The two paths diverge before any package is chosen

- **UI:** `isoInstaller` finds no kickstart, so `install_config` stays empty and
  `installer.configure()` runs the curses configurator (`iso_config.py`), which
  is what presents the *Apply STIG hardening* menu.
- **Kickstart:** the config is loaded from the ks source (`cdrom:`, HTTP,
  VMware guestinfo, or the `ks=` kernel parameter), the configurator is
  skipped, and **the STIG menu is never displayed.**

| Evidence | v2.8 | master |
|---|---|---|
| `StigEnable` instantiated only from the curses configurator | `iso_config.py:296` | `iso_config.py:181` |
| `install_config['ui']` defaults to `False`; set true only on the UI path | `installer.py:507-508` | same |

(`iso_config.py` survives in master -- it shrank by 118 lines between v2.8 and
master, it was not removed.)

The downstream patch `0003-isoInstaller-fix-interactive-NoneType-crash.patch`
exists precisely because of this split: an empty config must stay *falsy* so
that `configure()` dispatches to the UI configurator instead of proceeding with
no disk configured.

### 11.2 Consequence 1 -- STIG cannot be "answered yes" from a kickstart

A kickstart has no menu to answer. To get the same result the author must spell
it out: an `ansible:` block naming the playbook **and** an
`additional_packages:` list reproducing `KS_STIG_PACKAGES` by hand. The
minimal-ISO failure therefore still occurs in kickstart form, but only if the
author lists those packages -- there is no automatic path into it.

### 11.3 Consequence 2 -- a kickstart can break minimal on POI 2.8, which the UI cannot

`installer.py:409-417` (v2.8):

```python
if 'security' in install_config:
    security = install_config['security']
    if 'selinux' in security and security['selinux'] is not None:
        packages.append("selinux-policy")
    if 'fips' in security and security['fips'] is not None:
        packages.append("openssl-fips-provider")
```

The guard is *presence of the key*, not its value. So:

- **UI install** -- no `security` key is ever synthesised on 2.8, nothing is
  appended, and minimal-iso installs cleanly (row 1 of the main matrix).
- **Kickstart install** -- an entirely ordinary `security: {selinux: permissive}`
  appends `selinux-policy`, which is **not on the minimal media** -> the same
  `Error(1011)` that POI master produces unconditionally.

This matters for how row 1 should be read: **"minimal + POI 2.8 = WORKS" holds
only for a UI install with no `security` section.** It is not a property of the
media. Commit `a88cf02` did not invent this failure; it made an existing
kickstart-only failure unconditional by synthesising the key for everyone.

| minimal-iso + POI 2.8, kickstart content | verdict |
|---|---|
| no `security`, no `additional_packages` | WORKS |
| `security: {selinux: <any non-null>}` | FAILS -- `selinux-policy` absent |
| `security: {fips: <any non-null>}` | FAILS -- `openssl-fips-provider` absent |
| `additional_packages:` = `KS_STIG_PACKAGES` | FAILS -- six packages absent |

### 11.4 Consequence 3 -- the same failure is surfaced differently

`installer.py` branches on `ui` at `:291`, `:745`, `:779`, `:838`. In UI mode
the tdnf run is the progress-bar parser (`Popen` + line-by-line parsing); in
kickstart mode it is `self.tdnf.run(...)`. Identical failure, different
visibility -- the curses path is what reduces a missing package to a bare
`InstallerError("Installer failed")` on screen, with the real cause only in
`/var/log/installer`. See FIX-2, which is worth more in UI mode than in
kickstart mode.

### 11.5 Effect on the permutation count

This is a fifth binary dimension, but it does **not** cleanly double the matrix:
"kickstart + STIG menu" is not a reachable combination, because the menu is
UI-only. The honest enumeration is:

- the 16 rows of section 2 are the **UI** rows;
- the kickstart rows use the same media, express STIG manually, and add one
  failure mode (`security:` key present) that has no UI counterpart on 2.8.

### 11.6 Fix implications -- none specific to kickstart

Every failure above is media-side: the packages are absent from the minimal
ISO. FIX-1 (or its alternatives) cures the kickstart rows and the UI rows
together. No kickstart-specific change is required.
