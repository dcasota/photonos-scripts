# Research: upgrade-path permutations (4.0 GA, 4.0 latest, 5.0/90, 5.0/91 -> 5.0 mainline)

| | |
|---|---|
| Status | **Research input.** Not a PRD, not an ADR, not approved for implementation. |
| Date | 2026-09-11 |
| Scope | Extending the matrix with upgrade paths from four start points to 5.0 mainline (subrelease 92). |
| Method | Read-only investigation. Every file path, function, line number, table and column cited was read. Broadcom media inventory and repo URLs probed by HEAD/index fetch only; no media downloaded. `photon-upgrade` sources read on `5.0`, `SPECS/91/`, and `origin/4.0` via `git show`. |
| Gate | Under `specs/README.md`, implementation is blocked until a PRD merges. This needs an FRD and `specs/adr/0002-upgrade-transitions.md`. |

---

## 0. Not determined by this investigation

Each has a named spike in section 10.

1. Whether the 2021 `4.0-GA` in-tree installer supports a **btrfs** root, a **STIG** menu, or the network-config shapes the `net` axis uses. `installer/isoInstaller.py` and the file list were read; the rest was not.
2. Whether a second CD-ROM device in the VMX is inert during a Photon install on this host (needed for the ISO-as-repo design).
3. Where `photon-subrelease` from `/root/5.0/build-config.json` becomes the rpm macro `%photon_subrelease` that `%global build_if` tests. Not in this checkout. Consequence: the **gate expressions** are confirmed (`>= 92` mainline, `<= 91` for `SPECS/91`, `<= 90`/`== 90` for `SPECS/90`) but it cannot be proven from the repo that a pinned build lands the intended `photon-repos` and therefore the intended `/etc/tdnf/vars/subrelease`. **The oracle must measure it, never assume it.**
4. Whether `--precheck-only` is genuinely non-destructive on the mainline 5.0 script (the `is_precheck_running` guards present on the `4.0` copy are absent from mainline's `verify_version_and_upgrade`). Read, not run.
5. Per-row wall clock for an *upgrade*. `permutation` stores `started_at = finished_at` (both the verify stamp, `src/ingest.rs:186`), so **no duration exists in the database at all**. Install timings below come from `/root/photon-mc/run-logs/*.log` line timestamps.

---

## 1. What the existing capability actually is (corrected)

The premise that `sharukhan build --release/--subrelease` is reachable from the matrix is **false**. Two separate build paths exist and only one knows about release/subrelease.

| | `sharukhan build` (`src/main.rs:742` `cmd_build`) | `sharukhan build-iso` / `run` (`src/build.rs:44` `resolve`) |
|---|---|---|
| axes | `--release 4.0\|5.0\|6.0`, `--subrelease mainline\|90\|91`, `--img`, `--canister`, `--poi` | `IsoRequest { iso_type, poi, canister }` only (`src/build.rs:20`) |
| release | `args.release`, default `"5.0"` (`main.rs:743`) | `cfg.release`, from `MC_RELEASE`, default `"5.0"` (`config.rs:218`) - **never varied** |
| subrelease | parsed at `main.rs:761` -> `Injection::PinSubrelease(n)` | **hardcoded `None`** at `build.rs:257`; absent from the legacy path |
| cache key | none - writes to `--out` | `cfg.iso_dir(iso_type, poi, canister)` = `{iso_type}-poi{poi}-{canister}` (`config.rs:301-303`) |
| driver | `buildexec::execute` (native cascade) | native cascade **only** for `canister == "equivalent"`; otherwise `sh runPh5_normal.sh` (`build.rs:269`) |

Consequences that constrain everything below:

- **`iso_dir` has no release or subrelease component.** A 5.0-subrelease-90 ISO and a 5.0-mainline ISO collide on `minimal-poi2.8-prebuilt`. Same class as finding **#13** `canister-hardcoded-in-verify`: a cache key omitting a build axis makes the harness verify an artefact the row never used.
- **`build::resolve` hardcodes the 5.0 driver** for every non-equivalent build. Passing `release=4.0` would build against `$MC_BUILD_ROOT/4.0` while the variant patch and the stale-RPM purge remain 5.0-shaped.
- **`VARIANTS` (`build.rs:594`) is 5.0-only.** `make_variant_patches` fetches base ref `"5.0"` (`build.rs:704`) and diffs `origin/5.0..branch`. There is **no 4.0 variant patch and no mechanism to make one**, yet `resolve` refuses to build without `poi-{poi}.patch` (`build.rs:112`), and `runner.rs:~160` gates every group on `media::gate(&iso, &patch, ...)` comparing the installer NEVR on the media against the one the patch asks for. A 4.0 or subrelease-pinned ISO fails that gate by construction.
- **`/root/4.0` and `/root/6.0` do not exist.** `buildexec::sync` (`buildexec.rs:77-105`) *would* clone branch `4.0` into `$MC_BUILD_ROOT/4.0` on first use - but only through the `build` path, not `build-iso`.
- **The matrix exercises exactly one release/subrelease today**: 5.0 mainline. `build-config.json` sets `"photon-subrelease": "92"`.

Sibling scripts: `runPh5_normal.sh` (932 lines), `runPh5_pinned90.sh` (691), `runPh5_pinned91.sh` (815), `runPh4.sh` (437). Diffing normal vs pinned90 shows the substantive delta is the subrelease pin plus a base-commit bypass; the script's own header warns *"SPECS/90 is a large (~583-package) ecosystem ... a fully-clean ISO build may need additional subrelease-90 bootstrap fixes discovered iteratively."* **Treat a 90 ISO build as unproven on this host.**

---

## 2. Hard constraints discovered

**C1 - `identity::MAX_INDEX = 80` (`src/identity.rs:20`).** Every VM's MAC, BIOS UUID and IP derive from the row's 1-based ordinal among data rows (`perm_index`, `identity.rs:53`). There are **43** data rows today (`p01-p16 k01-k16 s01 s02 c01 c02 n01-n05 c03 s03`). With `ip_base = 40` (`config.rs:232`) and VMnet8's DHCP floor at `.128`, ordinal 88 collides with a lease; the code refuses at 80. **37 row slots remain, total.** A literal "4 start points x all 43 permutations" = 172 new rows = 215 total, which is **not representable**: `perm_index` returns `WouldReachDhcpRange` and the row cannot be created at all. **This is the single most important number in this plan.**

**C2 - Rows must be APPENDED, never inserted.** Same mechanism; the matrix comments state it twice. Upgrade rows go at the end of `permutations.tsv`, after `s03`.

**C3 - Photon 4.0 GA media cannot be kickstarted over guestinfo.** `git show 4.0-GA:installer/isoInstaller.py` recognises only `ks=`, `repo=`, `photon.media=` from `/proc/cmdline`; `grep guestinfo` -> **zero hits**. guestinfo support first appears in photon-os-installer **v2.7** (`v2.4` -> 0 hits, `v2.7` -> 2 hits at `photon_installer/isoInstaller.py:172,182`). `origin/4.0:SPECS/photon-os-installer/photon-os-installer.spec` is `Version: 2.7`, so **4.0-latest supports guestinfo and 4.0-GA does not**. The entire "install-time axes are free" economy is unavailable on a GA row. `ks=` does accept an `http://` URL (`_load_ks_config`), so the alternatives are an ISO remaster or an operator at the console.

**C4 - `photon-upgrade` does not exist on 4.0 GA.** First appears on the `4.0` branch in `75a535c1f "photon-upgrade: adding package to 4.0"`, long after the 2021-02-24 GA commit `1526e30ba`. `tdnf` on `4.0-GA` is `3.0.0-5`; on `origin/4.0` it is `3.3.12-3`. A 4.0-GA row **cannot** start with `photon-upgrade`; it must first pull it (and whatever `tdnf`/`rpm` that drags in) from the live 4.0 updates repo. That bootstrap is a fact the row must record, not hide - otherwise "4.0 GA -> 5.0" is a claim about a system that was already partly updated.

**C5 - `photon-upgrade` implements no 5.0-subrelease transition.** On mainline/91 the dispatch `case "$TO_VERSION"` (`SPECS/photon-upgrade/photon-upgrade.sh:936-947`) accepts **only `6.0`**; anything else exits `Valid values for --to-ver can only be 6.0`. On `origin/4.0` it accepts **only `5.0`**. With no `--upgrade-os`, `TO_VERSION` stays empty, the `''` arm matches, **no transition file is sourced**, so `deprecated_packages_arr` and `replaced_pkgs_map` are never populated - and `update_os()` (`:795-830`) still calls `find_installed_deprecated_packages` (`:817`) and `find_installed_replaced_packages` against empty arrays. So a 90->92 or 91->92 move is **`tdnf --noautoremove distro-sync --refresh --allowerasing` plus rpmdb hygiene and nothing else**: no subrelease-aware deprecation handling exists. That is itself a defensible finding for the matrix to produce, and it means start points 3 and 4 are **not "photon-upgrade rows" in the same sense as 1 and 2**.

**C6 - `--subrelease` is a 4.0-branch-only flag, and it selects a package list, not a transition.** `origin/4.0`'s getopt string is `assume-yes,help,install-all,precheck-only,repos:,rm-pkgs-pre:,rm-pkgs-post:,subrelease:,to-ver:,skip-update,upgrade-os,retain-deprecated-pkgs:`; mainline's is identical **minus `subrelease:`**. Default is `SUBRELEASE=${SUBRELEASE:-91}`. `ph4-to-ph5-upgrade.sh:1` builds `"$1/ph4-to-ph5-${SUBRELEASE}-deprecated-pkgs.txt"` and aborts `ERETRY_EINVAL` if absent; `:50` branches `replaced_pkgs_map` on `[[ "$SUBRELEASE" -gt 90 ]]`. **Reaching 5.0 mainline (92) requires `--subrelease=92` explicitly** - the default 91 would apply the wrong deprecation list (the 92 list = the 91 list plus `perl-WWW-Curl`, `python3-configobj`, `rpcsvc-proto`, `rpcsvc-proto-devel`). A row that omits it silently tests the wrong transition.

**C7 - locally built RPMs are unsigned.** `rpm -qpi /root/5.0/stage/RPMS/x86_64/7zip-26.01-2.ph5.x86_64.rpm` -> `Signature : (none)`. `SPECS/photon-repos/photon-iso.repo` ships `baseurl=file:///mnt/cdrom/RPMS`, `gpgcheck=1`, `enabled=0`. `photon-upgrade` hardcodes `TDNF='/usr/bin/tdnf --noautoremove'` (`constants.sh`) with **no `--nogpgcheck` passthrough**, so presenting our own build as a repo requires writing a repo file with `gpgcheck=0` in the guest. A deliberate deviation from a production upgrade; assert it as such, do not do it quietly.

**C8 - `photon-upgrade` never reboots non-interactively and never touches the bootloader.** `ask_for_reboot()` with `--assume-yes` prints *"Please reboot the system."* and exits 0. `grep -iE "grub|initrd|dracut|linux-esx|uname -r|vmlinuz"` over mainline `photon-upgrade.sh` + `utils.sh` -> **zero hits**. Kernel and boot entries move only as a side effect of `distro-sync` and the kernel RPM's scriptlets. **The harness owns the reboot and owns proving the boot entry is right.**

**C9 - the installed binary is `/usr/bin/photon-upgrade.sh`, not `photon-upgrade`.** `%install` does `install -m550 %{SOURCE0} %{buildroot}%{_bindir}` with `Source0: photon-upgrade.sh`; no symlink. Also `%{_libdir}` is used in `%install` while the script hardcodes `PHOTON_UPGRADE_UTILS_DIR="/usr/lib/photon-upgrade"` - a latent mismatch on x86_64 where `%_libdir` is normally `/usr/lib64`. **Derive the path by probing the guest; hardcode neither spelling.**

**C10 - no snapshot support in the harness.** `src/vmware.rs` exposes `running/is_running/start/start_verified/stop_hard/guest_ip` and nothing else; `src/vm.rs` has `create/teardown/stash_nvram/detach_cdrom`. An upgrade row that fails mid-`distro-sync` currently has to re-install from scratch to retry. Finding **#30** applies: a `vmrun snapshot` exit code is not evidence; `vmrun listSnapshots` is.

**C11 - `install.rs:365` calls `vm::detach_cdrom` unconditionally** after every install. If the target media is presented as a CD-ROM, this must not remove it.

**C12 - finding #60 needs correcting.** Probed: `https://packages.broadcom.com/artifactory/photon/5.0/photon_updates_5.0_x86_64/x86_64/` -> **200**, as does the short form; `packages.vmware.com` 301-redirects to the short form. The `/artifactory/` prefix is a live alias, not retired; #60 recorded a **transient outage** as a retirement. Its *mitigation* - derive the URL from `SPECS/photon-repos/photon-updates.repo` rather than writing it down twice - remains correct and should stand. Matters here because every upgrade row depends on those URLs resolving.

> Confirmed and acted on when this document was filed: #60 was re-probed (200 on three consecutive tries, repo back in the directory index) and rewritten as `artifactory-canister-url-outage`, severity lowered to medium.

---

## 3. Where each start point's media comes from

All probes returned `200`; sizes are `Content-Length`; sha256 published both as sibling `.sha256` files and as Artifactory `X-Checksum-Sha256` headers.

| dir | build id | x86_64 minimal | x86_64 full |
|---|---|---|---|
| `/photon/4.0/GA/iso/` | `1526e30ba` | `photon-minimal-4.0-1526e30ba.iso` **506 241 024 B** (483 MB) | `photon-4.0-1526e30ba.iso` 4.17 GB |
| `/photon/4.0/Rev1/iso/` | `ca7c9e933` | 469 MB | 4.22 GB |
| `/photon/4.0/Rev2/iso/` | `c001795b8` | 357 MB | **4 401 641 472 B** (4.10 GB) |
| `/photon/5.0/GA/iso/` | `dde71ec57` | 537 MB | 4.31 GB |

Also present: `Beta/`, `RC/`, `OSL/` under 4.0; `Beta/`, `RC/` under 5.0. **No `6.0/` at all** (404). 4.0 x86_64 repos last modified 10-Sep-2026, 5.0 x86_64 11-Sep-2026 - both lines still receiving updates.

**The build id in the ISO filename is the short SHA of the corresponding git tag.** Confirmed against the local checkout:

```
4.0-GA   -> 1526e30babd7b3a6afcdd1a76bb2ce37aa79a1e9  2021-02-24  "Add missing dependency for bison"
4.0-Beta -> d98e681a99d3ba81c30fe9b4c1fae8519e1aa5c2  2020-11-03
5.0-GA   -> dde71ec57136fe9e6dc9396904afed3ed089f964  2023-04-21
```

and `git merge-base --is-ancestor 4.0-GA origin/4.0` -> yes. `Rev1`/`Rev2` are **untagged** respins; there are no `4.0-Update*` or `5.0-Update*` tags. GitHub releases for `vmware/photon` carry **`assets: []`** - tags are source-only, no ISOs.

### Decisions

**"4.0 GA" is authoritative as a downloaded image, not as a build.** The GA claim is *"the media Broadcom released on 2021-02-24"*. The git tag reproduces the *source*, not the media: rebuilding `4.0-GA` today means a 5-year-old `build.py`, a 5-year-old toolchain bootstrap, and `Source0` URLs that have moved - and a rebuilt artefact would differ from the released one in ways nobody can enumerate, destroying the only property the row exists to have. So: **start point 1 = `/photon/4.0/GA/iso/photon-minimal-4.0-1526e30ba.iso`, downloaded once, identity proven by sha256 == the published sibling AND by `1526e30ba` == `git rev-parse --short=9 4.0-GA`.** That double check is the negative control (AC-2): a filename alone is not provenance, and a server-self-attested checksum alone is not either.

Caveat to record: there is **no independently published 2021-era checksum** on these hosts to cross-check. The strongest available claim is "the bytes Broadcom serves under `GA/` today, whose embedded build id matches the `4.0-GA` tag". State that in the evidence; do not upgrade it to "byte-identical to the 2021 original".

**Start point 2, "4.0 latest", has two defensible readings and they are different tests.**
(a) *4.0 GA media, then `tdnf distro-sync` within 4.0 to current* - reachable with no build at all, tests the supported customer path, produces a system whose `photon-upgrade` is the current `1.2-7`.
(b) *An ISO built from `origin/4.0` HEAD* - tests media Broadcom does not publish, costs a multi-hour build plus a 4.0 tree clone plus a 4.0 variant-patch mechanism that does not exist.
**Take (a).** It is the honest meaning of "fully updated 4.0", it is what a real operator has, and it costs zero build hours. Record it as `ph4-latest` with the pre-upgrade oracle capturing the resulting NEVR set, so "latest" is a *measured* state, not a date.

**Start points 3 and 4 must be built locally.** Broadcom publishes no subrelease-specific media: `/photon/5.0/` contains only `Beta/ RC/ GA/`, no `Rev*`/`Update*` (404). `5.0-GA` (`dde71ec57`, 2023) predates the subrelease scheme entirely. So `ph5-90` and `ph5-91` require `sharukhan build --subrelease 90|91 --img minimal-iso` - the one path that already supports it, **not** `build-iso`. These need a release/subrelease-aware cache key before `run` can consume them, and the 90 build is unproven.

---

## 4. Matrix extension

### 4.1 New columns

Append two columns to `permutations.tsv`, both defaulting to `-` so all 43 existing rows are byte-unchanged:

```
#id  iso_type poi stig fs mode ks_variant doc expect canister net   from        to
```

- **`from`** - the start point: `-` (fresh install; every existing row), `ph4-ga`, `ph4-latest`, `ph5-90`, `ph5-91`.
- **`to`** - the upgrade target: `-` (no upgrade), `ph5-92`. Only `ph5-92` is accepted now; the column exists so a future `ph6` row needs no schema change, and so this plan does not smuggle in the 5.0->6.0 transition that mainline `photon-upgrade` actually implements.

`from` and `to` are mutually implied: `from != -` XOR `to != -` is an error. `matrix::load` (`src/matrix.rs:93`) must reject an unknown token **naming the row**, exactly as it does for `net` (`matrix.rs:116-118`) and for the reason given there: POI validates only top-level kickstart keys, so a silently-defaulted axis yields a green run that exercised nothing.

```rust
pub enum StartPoint { Fresh, Ph4Ga, Ph4Latest, Ph5Sub(u32) }   // 90 | 91
pub enum Target     { None, Ph5Mainline }                       // subrelease 92
```

`Permutation` gains `pub from: StartPoint, pub to: Target` and `Permutation::is_upgrade() -> bool`.

### 4.2 Which existing axes are meaningful on an upgrade row

| axis | on an upgrade row | why |
|---|---|---|
| `iso_type` | **property of the START media**, real axis where both forms exist | 4.0 GA publishes minimal (483 MB) and full (4.17 GB); a `ph5-90` build would cost one ISO per value |
| `poi` | **not an axis - must be `-`** | `VARIANTS` is 5.0-only; the 2.8/latest PR variants change a *fresh install*, which an upgrade row does not test after its start install. The start media's installer version is a *measured* fact |
| `canister` | **not a build axis - must be `-`**, but is a post-upgrade *assertion* | `Embedded::CanisterEquivalent` patches the 5.0 tree; nothing to apply it to on a 4.0 or pinned tree. Post-upgrade, "which canister does the new kernel link" is a first-class oracle question |
| `stig` | axis only where the start installer has the menu | UI-only by construction. Unknown for 4.0-GA - spike S1 |
| `fs` | axis where the start installer supports it | ext4 certain; btrfs on 4.0-GA unknown - spike S1 |
| `mode` | `ui` only for `ph4-ga` unless a remaster lands; `ks` for the rest | C3 |
| `ks_variant` | `-` for `ph4-*` | `fips`/`selinux` variants are 5.0-era POI kickstart keys |
| `net` | `-` for `ph4-ga` | the 4.0 in-tree `networkmanager.py` predates the v2 `addresses`/`vlans` schema the `net` axis asserts on. Free for `ph5-90/91`, but per C5 it re-tests `k01`'s network with no upgrade-specific signal |

`iso_key()` must be **split**, because an upgrade row consumes two artefacts:

```rust
pub fn start_key(&self)  -> String;          // what the VM boots and installs from
pub fn target_key(&self) -> Option<String>;  // what the upgrade consumes; None when Fresh
```

For `StartPoint::Fresh`, `start_key()` is verbatim today's `iso_key()` = `{iso_type}/{poi}/{canister}` - so the three existing `matrix.rs` tests (`the_network_axis_never_reaches_the_iso_cache`, `the_equivalent_row_cannot_reuse_the_prebuilt_iso`) keep passing unchanged. For an upgrade row, `start_key()` = `{from}/{iso_type}` and `target_key()` = `Some("ph5-92")`.

`runner::group_rows` (`runner.rs:318`) currently reconstructs the cache dir as `format!("{}-poi{}-{}", ...)` - a **second copy** of `config::iso_dir`'s formatting. Fold it into `Config::media_dir(&Permutation)` and delete the duplicate; that is the two-copies defect class of findings #16 and #38.

### 4.3 `iso_dir` must gain release and subrelease - independently of upgrades

```rust
pub fn iso_dir(&self, k: &MediaKey) -> PathBuf   // {release}-sub{subrelease}-{iso_type}-poi{poi}-{canister}
```

Keep the legacy spelling for `release=5.0, subrelease=mainline, poi in {2.8,latest}` so the six existing cache directories are not orphaned:

```
minimal-poi2.8-prebuilt  full-poi2.8-prebuilt  full-poilatest-prebuilt
minimal-poi2.8-equivalent  minimal-poilatest-prebuilt  full-poi2.8-equivalent
```

New keys get the long form, e.g. `5.0-sub91-minimal-poi-prebuilt`. Renaming the existing six would throw away built media measured in days of rebuild.

Downloaded start media is **not** built media and belongs in a sibling tree, `$MC_ISO_CACHE/../media-cache/ph4-ga/`, with `photon.iso` a symlink and `photon.iso.sha256` + `provenance.txt` (URL, `Content-Length`, published sha256, matching git tag) beside it - the side-car convention `build.rs:305-311` already writes. It must live under `/mnt/c/...`: finding **#5**, a non-`/mnt` ISO becomes the nonsense VMX value `\root\...` and `vmrun` reports only *"The operation was canceled"*.

### 4.4 Id scheme

Existing prefixes: `p` (ui), `k` (ks), `s` (kickstart-only failure class), `c` (canister), `n` (network). **Take `u`** - unused, one letter as the others are. Ids `u01`, `u02`, ... appended after `s03`, never inserted (C2). The start point lives in the `from` column, not the id: encoding four start points in the id would force two-letter prefixes or a renumbering the moment a fifth appears, and `perm_index` is positional anyway.

### 4.5 The arithmetic

Reading "all permutations" literally as "the 43 rows that exist":

```
43 rows x 4 start points = 172 new rows;  43 + 172 = 215 total
```

**Not representable.** `identity::MAX_INDEX = 80`; ordinal 81 returns `IdentityError::WouldReachDhcpRange(81)`, and ordinal 88 would be `192.168.225.128`, inside VMnet8's `range 192.168.225.128 192.168.225.254`. **Budget: 37 rows.**

Nominal after dropping axes that are not axes on an upgrade row:

| start point | iso_type | mode | fs | stig | ks_variant | net | rows |
|---|---|---|---|---|---|---|---|
| `ph4-ga` | 2 | 1 (`ui`; C3) | 1-2 (S1) | 1-2 (S1) | 1 | 1 | **2-8** |
| `ph4-latest` | 2 | 1 (`ks`) | 2 | 2 | 1 | 1 | **8** |
| `ph5-90` | 2 | 2 | 2 | 2 | 4 | 6 | <= 384 nominal |
| `ph5-91` | 2 | 2 | 2 | 2 | 4 | 6 | <= 384 nominal |

The `ph5-9x` cells fan out because every 5.0-era axis is expressible there - and every one costs an install while proving nothing about the upgrade, because per **C5** a 90->92 or 91->92 move is a bare `distro-sync` that reads no subrelease-specific data at all. The matrix's own precedent settles it: *"poi is deliberately NOT crossed with net"* because the code under test is byte-identical across the axis. Same argument, stronger: the upgrade code under test reads **none** of these axes.

**The full cross-product is not affordable and not defensible.** The defensible reduction, 8 rows:

```
#id  iso_type poi stig fs     mode ks_variant doc       expect  canister net from        to
u01  minimal  -   no   ext4   ui   -          untested  pass    -        -   ph4-ga      ph5-92
u02  minimal  -   no   ext4   ks   none       untested  pass    -        -   ph4-latest  ph5-92
u03  minimal  -   no   ext4   ks   none       untested  pass    -        -   ph5-91      ph5-92
u04  minimal  -   no   ext4   ks   none       untested  pass    -        -   ph5-90      ph5-92
u05  full     -   no   ext4   ui   -          untested  pass    -        -   ph4-ga      ph5-92
u06  full     -   no   ext4   ks   none       untested  pass    -        -   ph4-latest  ph5-92
u07  minimal  -   no   btrfs  ks   none       untested  pass    -        -   ph4-latest  ph5-92
u08  minimal  -   yes  ext4   ks   stigpkgs   untested  pass    -        -   ph4-latest  ph5-92
```

Rationale per row - these comments belong **in** the TSV, not in a side document; the file is the executable form of the analysis:

- `u01`-`u04`: one row per start point, all other axes pinned to `k01`'s values. The start point is then the *only* difference between them, and `k01` is the paired control for the post-upgrade state.
- `u05`/`u06`: `full` start media. Not a duplicate - the full 4.0 media carries ~1 900 RPMs against minimal's ~290, so it is where a deprecated package with no replacement actually gets *installed* and therefore where the erase path is exercised at all. On minimal, most of the 225-entry `ph4-to-ph5-92-deprecated-pkgs.txt` matches nothing and the whole deprecation mechanism is vacuous.
- `u07`: btrfs. Genuinely different - `distro-sync` of a full package set on btrfs is where a snapshot/space interaction would show, and `guest.root_fstype` (`oracle.rs:236`) must still read `btrfs` afterwards.
- `u08`: STIG. A hardened start system is where `/tmp` `noexec` (`oracle.rs:305`) and the STIG package set collide with an erase-and-replace upgrade.
- **`ph4-ga` is `ui` only** until a remaster lands (C3), so `u01`/`u05` are operator-assisted - `card` -> `install --mode interactive` -> `upgrade` -> `verify`. Same arrangement the 16 `p` rows already have; a property of 2021 media, not an omission.
- **No `net`, `fips`/`selinux`, or `equivalent` crossing.** Each would multiply installs while re-testing a code path the upgrade does not touch. State it in the TSV with the reason, per the `net`-block precedent.

8 rows brings the matrix to 51 of 80, leaving 29 slots. **If the concurrently planned extensions also want rows, `MAX_INDEX` becomes the shared scarce resource and the plans must agree a budget.** Flag it; do not silently consume it.

---

## 5. Driving an upgrade row end to end

### 5.1 Reuse vs new

| phase | today | upgrade row |
|---|---|---|
| `kickstart` | `phases::kickstart_json` -> `kickstart::render` | reused for `ph4-latest`/`ph5-9x`. **New** for `ph4-ga`: different schema (S1) and no guestinfo channel (C3) |
| `create-vm` | `vm::create` | reused, plus a second CD-ROM for the target media |
| `install` | `install::run` | reused. Completion signals (a) `root=PARTUUID=`, (b) tools IP, (c) DHCP lease under the VM's own hostname, (d) SSH banner at the reserved address (`install.rs:236-290`) are all start-media agnostic. **C11**: `detach_cdrom` must not detach the target CD |
| **`upgrade`** | - | **NEW.** Between `install` and `verify` |
| `verify` | `verify::run` -> `oracle::{media,install,guest,harvest}` | reused, run **twice** |
| `teardown` | `vm::teardown` | reused. `--purge` destroys the disk; an upgrade row wants a checkpoint first |

New module `src/upgrade.rs`; new `phases::cmd_upgrade(cfg, id, dry_run)`; `runner::run_row` (`runner.rs:~355`) gains one conditional step; `main.rs` USAGE gains `upgrade` under PHASES.

### 5.2 Guest-side invocation

Everything over `Guest::run` (`src/guest.rs:74`) - `ssh` as an exec'd external binary, `BatchMode=yes`, key-only, stderr captured. A Rust SSH library would negotiate differently and could mask exactly the class of defect (s02) this harness exists to find. No credential ever reaches an argv; `MC_GUEST_PASSWORD` is needed only for `oracle::harvest`'s scrub (`oracle.rs:857`) and never printed.

Resolve the binary by **probing**, never by spelling (C9):

```
command -v photon-upgrade.sh || command -v photon-upgrade
rpm -q photon-upgrade                       # NEVR, recorded
rpm -ql photon-upgrade                      # where the utils dir actually is
```

Per start point:

```
# ph4-ga, ph4-latest   (transition 4.0 -> 5.0; --subrelease is 4.0-only, C6)
<bin> --upgrade-os --to-ver=5.0 --subrelease=92 --repos=<target-repo> --assume-yes

# ph5-90, ph5-91       (no transition exists, C5 - this is the point of the row)
<bin> --repos=<target-repo> --assume-yes
```

`--assume-yes` is what makes it non-interactive: exactly three `read` prompts exist, all guarded by `[ -z "$ASSUME_YES_OPT" ]` - the deprecated-package `Proceed(y/n)?`, the `Continue (y/n)?` in `verify_version_and_upgrade`, and `Reboot now(y/n)?`. Note `trap '' SIGINT SIGQUIT` at the top of the script: it ignores Ctrl-C, so `sharukhan stop` cannot interrupt it cleanly and must say so.

**`--precheck-only` is the dry-run candidate and is not yet trustworthy** (S4). Until proven, `sharukhan upgrade --dry-run` must **not** invoke the guest tool at all: it prints the resolved argv, the resolved binary path and NEVR, the target repo definition it would write, and the pre-upgrade facts it would capture - and changes nothing.

### 5.3 Presenting the target to the guest

| option | verdict |
|---|---|
| Published Broadcom repo | Zero new machinery, probed working, signed. But it tests **Broadcom's** 5.0, not the tree under test - useless as a PR gate. **Rejected as primary, kept as a comparison control.** |
| **The built target ISO as a second CD-ROM** | `photon-iso.repo` already exists with `baseurl=file:///mnt/cdrom/RPMS`, and the built media carries `/RPMS/repodata` (verified: `xorriso -indev ... -find /RPMS -type d` -> `/RPMS`, `/RPMS/noarch`, `/RPMS/repodata`, `/RPMS/x86_64`). No HTTP server, no host firewall question, no download. Needs `gpgcheck=0` (C7), a VMX second CD-ROM (S2), and C11 fixed. **Chosen.** |
| HTTP repo served from the host over `stage/RPMS` | Needed anyway for `ph4-ga`'s `ks=http://...` if the remaster route is taken, and the only option if S2 fails. **Fallback, not built first.** |

`upgrade.rs` writes in the guest:

```
/etc/yum.repos.d/sharukhan-target.repo
  [sharukhan-target]
  name=sharukhan upgrade target (LOCALLY BUILT, UNSIGNED)
  baseurl=file:///mnt/sharukhan-target/RPMS
  gpgcheck=0
  enabled=0
```

and mounts the second CD there. `enabled=0` with `--repos=sharukhan-target` is what `photon-upgrade` expects: `--repos=r1,r2` builds `--disablerepo=* --enablerepo=r1 ...`. `gpgcheck=0` is recorded as a **failing-by-design provenance check**, the same shape as `meta.canister_origin` marking a locally built canister `(NOT CMVP validated)` (`verify.rs:~95`).

One thing to check before trusting `--repos`: `is_repo_config_valid_for_release()` runs `tdnf --releasever=<target> list available photon-release` and aborts `ERETRY_EINVAL` unless every dist tag matches. Our ISO carries `photon-release-5.0-*.ph5`, so it should pass - verify in S3, because failing it aborts the whole upgrade with a message about repo config that says nothing about the ISO.

### 5.4 The 4.0-GA bootstrap, made explicit

C4 means `u01`/`u05` need, before any upgrade:

```
tdnf -y makecache
tdnf -y install photon-upgrade        # from the live 4.0 updates repo
```

A **separate, named sub-step** (`upgrade.bootstrap`) whose pre- and post- NEVR sets are both captured, so the row's "GA" claim stays honest: the report can say exactly which packages a GA system had to accept before it could be upgraded at all. Silently folding it into the upgrade would make `u01` and `u02` the same test with different labels. For `ph4-latest` the bootstrap is instead the defining step: `tdnf -y distro-sync` within 4.0, then `rpm -qa | sort` **is** the definition of "latest" for that run.

### 5.5 Reboot, and how completion is decided

`photon-upgrade` with `--assume-yes` never reboots (C8). So:

1. Record `uname -r`, `/proc/cmdline`, `rpm -q photon-release`, `/etc/photon-release`, `/etc/tdnf/vars/subrelease`, `rpm -qa | sort` **before** rebooting.
2. Take a checkpoint so a failed first boot does not cost the install.
3. Reboot from inside the guest (`systemctl reboot`), then **immediately stop trusting anything**: finding **#30** (vmrun exit codes are non-evidence in both polarities) and there is no serial console (findings **#8**, **#21**: the installed system's serial log froze at 119 354 bytes and never grew).
4. Wait on **positive, independent guest-side evidence**, reusing `install.rs`'s instruments rather than inventing new ones:
   - the SSH banner at the row's address (`install::ssh_answers`, `install.rs:127` - checks the `SSH-` prefix, not a bare TCP handshake);
   - **and** a monotonic boot discriminator, because the address answered before the reboot too: read `/proc/sys/kernel/random/boot_id` before the reboot and require a **different** value after;
   - **and** for a DHCP row, a *new* lease under the VM's own hostname, using `leases::installed_ip` with `started_at` taken immediately before the reboot (`install.rs:225-227` already establishes exactly this bound).

   `boot_id` changing **and** SSH answering is the completion oracle. Neither alone.
5. Never a bare timeout as a verdict (AC-7). A timeout is `upgrade.reboot = fail` with the measured values printed - the `install.rs:295-320` "still waiting: serial size=..., tools ip=..., ssh ..., last lease ..." pattern.

`MC_UPGRADE_TIMEOUT_SEC` as a new config, defaulting generously (suggest 7 200 - a 4.0->5.0 `distro-sync` replaces essentially the whole OS, and `MC_INSTALL_TIMEOUT_SEC` is already 2 400 for an install that empirically takes 60-150 s on minimal media). Derived, never hardcoded at a call site.

### 5.6 Checkpoint between install and upgrade

An upgrade row's install is the *expensive, uninteresting* half. Add to `src/vmware.rs`:

```rust
pub fn snapshot(vmrun, vmx_win, name) -> i32;
pub fn list_snapshots(vmrun, vmx_win) -> Result<Vec<String>, String>;
pub fn revert(vmrun, vmx_win, name) -> i32;
pub fn has_snapshot(vmrun, vmx_win, name) -> bool;   // the authority
```

`has_snapshot` polls `listSnapshots`; the `i32` return codes are logged and never acted on - finding **#30** applied to a new verb.

Two named checkpoints: `pre-upgrade` (after install + pre-oracle) and `post-upgrade` (after the reboot). The first makes `sharukhan upgrade --id uNN` idempotently re-runnable; the second makes a failed oracle re-runnable without redoing the upgrade.

Cost: a snapshot pins the pre-snapshot blocks, so the VM's footprint roughly doubles. Budget **40 GB** for a snapshotted upgrade row and recompute `disk::admit` against a new `disk::UPGRADE_RUN` need before every upgrade row, exactly as `cmd_run` already re-checks before every row (*"one row short of space means the next one is too"*).

---

## 6. The oracle: what an upgrade must assert that a fresh install need not

### 6.1 Two states, one oracle implementation

`oracle::guest` (`oracle.rs:227`) writes ~39 checks. Run it **twice** - once before the upgrade, once after. Do not write a second copy.

Cheapest mechanism that does not touch the frozen evidence format: add a prefix field to `Checks`.

```rust
pub struct Checks { ..., pub prefix: String }   // "" by default
// in Checks::check(), the emitted check id becomes:
let id = if self.prefix.is_empty() { id.to_string() } else { format!("{}.{id}", self.prefix) };
```

Set `prefix = "pre"` for the pre-upgrade pass, leave it empty for the post pass. Then:

- every existing check id keeps its exact spelling for the post-upgrade state, so **`u02`'s post state is directly comparable to `k01`** - the paired-control discipline the `c01`/`k09` and `n01`-`n05`/`k01` blocks already use;
- the pre-upgrade state appears as `pre.guest.root_fstype`, `pre.guest.selinux`, ... with **no new oracle code at all**;
- `src/evidence.rs`'s record shape (`perm, check, pr, status, expected, actual, detail`, declared frozen at `evidence.rs:12-15`) is unchanged, so `report.rs`, `ingest::parse` (`ingest.rs:49`) and all 21 stored evidence files keep working. **No new field, no format break.**

`oracle::expected_selinux` (`oracle.rs:201`) already branches on subrelease: `<= 90 -> Enforcing`, `91 -> Disabled`, `else -> Permissive`. So the pre/post pair on `u03`/`u04` gets a *free, already-correct* expectation change across the upgrade - `pre.guest.selinux` expects `Disabled` on a 91 start and `guest.selinux` expects `Permissive` after landing on 92. Exactly the kind of assertion an upgrade row exists to make, at zero cost.

### 6.2 New upgrade-specific checks

Version and subrelease facts - none of which any existing check asserts (`grep -n "photon-release\|os-release\|VERSION_ID" src/oracle.rs` -> **zero hits**):

| check | asserts | expectation source |
|---|---|---|
| `upgrade.photon_release` | `rpm -q photon-release` NEVR moved `.ph4 -> .ph5` | `SPECS/photon-repos/photon-repos.spec` `Release:` in the target tree - **read**, not written down |
| `upgrade.os_release` | `/etc/photon-release` + `/etc/os-release` `VERSION_ID` == target | derived from the target tree |
| `upgrade.subrelease_var` | `/etc/tdnf/vars/subrelease` == `92` | `photon-repos.spec:67` writes it; `:80` marks it `%config` **without** `noreplace`, with the comment *"When upgrading to new subrelease, photon-repos must be upgraded as well"* - so if this file still says `91`, `photon-repos` did not upgrade, and that is the assertion |
| `upgrade.dist_tag` | zero installed RPMs carry a pre-target dist tag | `rpm -qa --qf '%{RELEASE}\n' \| grep -c 'ph4'` must be 0 for `u01/u02/u05/u06` |
| `upgrade.no_leftover_subrelease` | for `u03/u04`, no package still at a `SPECS/90` or `SPECS/91` release | diff `pre.` and post `rpm -qa` |

Deprecated packages and replacements:

| check | asserts |
|---|---|
| `upgrade.deprecated_removed` | every name in the **applicable** list that was present in the `pre.` inventory is absent after. List read from the guest at `$(rpm -ql photon-upgrade \| grep deprecated-pkgs)` - for `--subrelease=92` that is `ph4-to-ph5-92-deprecated-pkgs.txt` (225 entries). **Never hardcode the list**; it changed three times in the last month |
| `upgrade.deprecated_negative_control` | a name **not** on the list, present before and expected present after, is still present. AC-2: the removal check is a count over a set read from the guest, and a mis-parsed list would make it vacuously pass |
| `upgrade.replacements_present` | for every `pre.`-installed key of `replaced_pkgs_map` (read from `ph4-to-ph5-upgrade.sh` in the guest), **at least one** of its value list is installed. First-available-wins, e.g. `[dhcp-server]="kea"`, `[openjdk11]="openjdk11 openjdk25 openjdk21 openjdk17"`, `[procmail]="dovecot"` |
| `upgrade.no_orphans` | `rpm -Va --nofiles --nodigest` reports no unsatisfied dependency; `tdnf check` clean |
| `upgrade.rpmdb_sane` | `rpm -qa \| wc -l` > 0 and `rpm --verifydb` clean. `photon-upgrade` calls `rebuilddb` five times and backs the DB up to a `mktemp` dir; a corrupt DB leaves a machine unfixable |
| `upgrade.python3_configobj_absent` | **the specific regression the recent commits are about.** `python3-configobj` must be gone on a `--subrelease=92` upgrade and - per `1d99b66c0` being deliberately *not* applied to `SPECS/91/` - still present on a `--subrelease=91` one. One check, pass-on-92 and pass-on-91 for the opposite reason, attributed to the commit |

Kernel and boot - C8 says nothing in `photon-upgrade` touches these, so these are the highest-risk assertions:

| check | asserts |
|---|---|
| `upgrade.kernel_flavour` | `uname -r` names the flavour the target media ships. The ISO boots `linux-esx`; `SPECS/linux/linux.spec` hardcodes `canister_build 0 / canister_usage 1` for it (finding **#43**) |
| `upgrade.kernel_nevr` | `uname -r` == the NEVR the target tree builds, via `build::kernel_nevr` / `equivalent_kernel_nevr`. `verify.rs:78-88` already derives this correctly and documents why reading the pristine spec is wrong (c03 read `-3` against an actual `-4`). Reuse it |
| `upgrade.boot_entry` | `/boot/loader/entries/` (or `grub.cfg`) has an entry for the running kernel, the default resolves to it, and **no stale 4.0/90/91 entry is default**. Independent of the machine having booted: it may have booted the *old* kernel |
| `upgrade.initrd_present` | an initrd exists for the running kernel and postdates the upgrade |
| `upgrade.cmdline_preserved` | `/proc/cmdline` still carries what the row installed - notably `fips=1` on a FIPS row and the kickstart's `console=ttyS0,115200n8` (`kickstart.rs:400-401`). A `distro-sync` that regenerates grub config can drop both, and losing the console silently re-creates finding **#21** |

Config migration:

| check | asserts |
|---|---|
| `upgrade.rpmsave_rpmnew` | enumerate every `*.rpmsave`/`*.rpmnew` under `/etc`. **Recorded as `Info`, asserted only against an allowlist** - a wholesale "none may exist" would fail on legitimate rpm behaviour; the signal is *which* files |
| `upgrade.sshd_config_intact` | the harness's own `authorized_keys` and sshd settings survived. If not, the guest is unreachable and every later check reads as an upgrade failure when the real fault is config clobbering - the misattribution of finding **#53** and the s02 saga |
| `upgrade.network_config_intact` | `/etc/systemd/network/*` byte-compared with the `pre.` capture (already harvested as `systemd-network.txt`). On an `n`-style row the address must survive; on any row cloud-init must not have rewritten it |
| `upgrade.conf_path_map` | for each `conf_path_map` key present before (mainline has only `[/var/opt/apache-tomcat/conf]`), the target path exists after |
| `upgrade.fstab_intact` | `/etc/fstab` unchanged and `findmnt -no FSTYPE /` still == the row's `fs` |

systemd, FIPS, canister:

| check | asserts |
|---|---|
| `upgrade.failed_units` | `systemctl --failed` count == 0, **compared against the `pre.` count**. Reuse `guest.failed_units` (`oracle.rs:390`) and its `n05`-style exclusion mechanism - a unit already failing before the upgrade is not an upgrade regression |
| `upgrade.units_enabled_preserved` | the enabled/disabled set is a superset-with-reason of `pre.`. Finding **#55** `photon-preset-enables-unmatched-units` is this failure mode arriving through a package change |
| `upgrade.fips_coherent` | if `pre.guest.fips_enabled` was 1, then after: `/proc/sys/crypto/fips_enabled` == 1, `fips=1` still in `/proc/cmdline`, **and** the FIPS self-test ran. Per the c03 commentary, `crypto/fips_integrity.c` prints the canister stamp *only* from the self-test, so a guest without `fips=1` reads `canister_based_on=absent` and proves nothing |
| `upgrade.canister_coherent` | `guest.canister_based_on` after the upgrade names the canister the **target** kernel links, from `oracle::canister_expectation(&"prebuilt", kernel)`. A row whose start media had no canister (4.0) and which lands on a canister-linked 5.0 kernel is the only way to observe that transition |
| `upgrade.no_esx_downgrade` | the flavour did not silently switch (`linux` <-> `linux-esx`) without the boot entry following |

Plus, mandatorily, a **negative control per counting check** (AC-2, `v_control_integrity`): a run in which a control passes is `inconclusive`, not a pass.

### 6.3 Pre-upgrade oracle: what it must assert, not just record

The pre-state is the baseline every post assertion is relative to. It must **fail the row before the upgrade runs** when:

- `pre.upgrade.tool_present` - the resolved binary exists and `rpm -q photon-upgrade` yields a NEVR. Without it there is nothing to test, and running `tdnf distro-sync` by hand instead would be testing a different thing.
- `pre.upgrade.start_identity` - `rpm -q photon-release` and `/etc/photon-release` match the row's `from`. A `ph4-ga` row whose guest reports 5.0 installed the wrong media, and every downstream check would be about the wrong system. This is the media-gate discipline `runner.rs` already applies per ISO group.
- `pre.upgrade.target_repo_visible` - `tdnf --repo=sharukhan-target list available photon-release` returns a `.ph5` NEVR at the expected release. Fail here rather than 40 minutes into a `distro-sync`.
- `pre.upgrade.inventory` - `rpm -qa | sort` captured as `rpm-qa-pre.txt`. Every set-difference check depends on it; if empty the row is `inconclusive`, not `pass`.
- `pre.upgrade.unsigned_target` - records, as a deliberate `Info`-with-caveat, that the target repo has `gpgcheck=0` and the RPMs are unsigned (C7).

---

## 7. Schema and reporting

`src/memory.rs` opens the DB **read-only** (`memory.rs:23`) and reads **only `finding`**, discovering columns via `PRAGMA table_info` (`memory.rs:25`). Writes happen in `src/ingest.rs` (`open_rw`, `:69`) and `src/job.rs`. So adding columns and tables cannot break it. `v_permutation_report` and `v_control_integrity` name their columns explicitly, so added columns do not break them either. `schema/memory.sql` is generated from the live DB and **must** be regenerated in the same PR as any DDL.

`permutation` is already missing two axes that exist in the TSV - `canister` and `net` are never written (`ingest.rs:189-207` inserts `iso_type, poi, stig, fs, mode, ks_variant` only). Fix that in the same change.

```sql
-- existing axes never persisted
ALTER TABLE permutation ADD COLUMN canister TEXT;
ALTER TABLE permutation ADD COLUMN net      TEXT;

-- the upgrade axes
ALTER TABLE permutation ADD COLUMN from_start TEXT;   -- '-' | ph4-ga | ph4-latest | ph5-90 | ph5-91
ALTER TABLE permutation ADD COLUMN to_target  TEXT;   -- '-' | ph5-92

-- durations, absent today: started_at == finished_at for every row
ALTER TABLE permutation ADD COLUMN install_sec INTEGER;
ALTER TABLE permutation ADD COLUMN upgrade_sec INTEGER;

CREATE TABLE IF NOT EXISTS transition (
    id              INTEGER PRIMARY KEY,
    permutation_id  INTEGER NOT NULL REFERENCES permutation(id),
    from_start      TEXT NOT NULL,
    to_target       TEXT NOT NULL,
    tool_nevr       TEXT,                 -- rpm -q photon-upgrade, as MEASURED in the guest
    tool_path       TEXT,                 -- resolved, never assumed (C9)
    argv            TEXT NOT NULL,        -- the exact invocation; no credential can appear here
    target_repo     TEXT NOT NULL,
    target_signed   INTEGER NOT NULL,     -- 0 for a locally built ISO (C7)
    start_media     TEXT,
    start_sha256    TEXT,
    start_build_id  TEXT,                 -- 1526e30ba, cross-checked against the git tag
    bootstrap_pkgs  TEXT,                 -- what a GA system had to accept first (C4)
    result          TEXT,                 -- pass | fail | error | skipped | inconclusive
    reboot_proved   TEXT,                 -- 'boot_id+ssh' | 'timeout' | 'skipped'
    started_at      TEXT NOT NULL,
    finished_at     TEXT,
    UNIQUE (permutation_id)
);
CREATE INDEX IF NOT EXISTS idx_transition_perm ON transition(permutation_id);

CREATE VIEW IF NOT EXISTS v_upgrade_report AS
SELECT p.perm_id, t.from_start, t.to_target, t.tool_nevr, t.target_signed,
       t.reboot_proved, t.result,
       (SELECT COUNT(*) FROM check_result c
          WHERE c.permutation_id = p.id AND c.status='fail'
            AND c.check_id LIKE 'pre.%')                        AS pre_fail,
       (SELECT COUNT(*) FROM check_result c
          WHERE c.permutation_id = p.id AND c.status='fail'
            AND c.check_id NOT LIKE 'pre.%')                    AS post_fail,
       (SELECT GROUP_CONCAT(DISTINCT c.pr) FROM check_result c
          WHERE c.permutation_id = p.id AND c.status='fail' AND c.pr IS NOT NULL)
                                                                AS prs_implicated
FROM permutation p JOIN transition t ON t.permutation_id = p.id;
```

The two-state row needs **no DDL on `check_result`**: the prefix scheme already distinguishes `pre.guest.selinux` from `guest.selinux` inside the existing `check_id` column, so before/after lands with zero change to `evidence.rs`'s frozen record shape.

`pre_fail > 0` and `post_fail > 0` are different diagnoses and must not collapse: the first says the row never got to test an upgrade, the second says the upgrade broke something.

Package-set deltas are large (~1 900 NEVRs on full media) and belong in the evidence tree, not SQLite. `oracle::harvest`'s `FILES` already writes `rpm-qa.txt`; add `rpm-qa-pre.txt` and a computed `rpm-qa-delta.txt`. The database indexes *verdicts*; the files are the evidence (`ingest.rs:4-7`).

`report.rs` gains one branch printing the upgrade columns when `from_start != '-'`; `ingest.rs` gains the `transition` upsert keyed on `permutation_id` so re-ingest replaces rather than duplicates.

---

## 8. Cost and scheduling

### Measured inputs

- `/` (WSL): **65 G free, 96% used**. `/mnt/c`: **94 G free, 98% used**.
- `disk::VM_RUN` = 5 G root / 20 G vmstore; `disk::ISO_BUILD` = 25 G root / 5 G vmstore (`disk.rs:36-37`).
- `disk::max_parallel` with `cpus=14`: `by_cpu = 3`, `by_disk = 4`, `min = 3`. **But `runner::cmd_run` is strictly sequential** - the 3 is what `status` advertises and what finding **#23** says is achievable, not what `run` does. Do not plan an upgrade schedule around parallelism that is not implemented.
- Per-VM peak (finding **#22**): `.vmem` == `memSize` == exactly 4 294 967 296 B while running; thin `.vmdk` grew 4 MiB -> 914 MiB during a minimal install.
- Install wall clock (`run-20260909T145636Z.log`): `k01` 56 s, `k02` 58 s, `k03` 129 s, `k04` 140 s. A **timeout** costs the full `MC_INSTALL_TIMEOUT_SEC = 2 400 s` (`n01`, `n02` both did).
- ISO sizes on disk: full 3.90 GB, minimal ~1.7-2.8 GB per cache dir; `full-poi2.8-equivalent` alone holds 15 GB because four respins accumulated.

### Per-row estimates

| row | new media | install | upgrade | verify | disk peak | wall clock |
|---|---|---|---|---|---|---|
| `u01` ph4-ga minimal, ui | 483 MB download | operator, ~10-20 min | bootstrap + 4.0->5.0 from a ~290-pkg base: **20-45 min** | ~2 min | ~15 G (+snapshot) | **~40-70 min**, operator-gated |
| `u02` ph4-latest minimal, ks | none (reuses u01's media) | ~2 min | 4.0 distro-sync to latest (**~10-25 min**) + 4.0->5.0 (**20-45 min**) | ~2 min | ~15 G | **~40-80 min** |
| `u03` ph5-91 minimal, ks | **one ISO build, hours** | ~2 min | bare distro-sync 91->92: **10-25 min** | ~2 min | ~15 G | **~20-35 min + build** |
| `u04` ph5-90 minimal, ks | **one ISO build, hours, unproven** | ~2 min | 90->92: **15-40 min** | ~2 min | ~15 G | **~25-50 min + build** |
| `u05` ph4-ga full, ui | 4.17 GB download | operator, ~20-30 min | ~1 900 pkgs: **60-120 min** | ~3 min | ~35 G (+snapshot) | **~90-150 min**, operator-gated |
| `u06` ph4-latest full, ks | none | ~5 min | 4.0-latest + 4.0->5.0 on full: **90-180 min** | ~3 min | ~35 G | **~100-190 min** |
| `u07` btrfs | none | ~2 min | as `u02` | ~2 min | ~15 G | as `u02` |
| `u08` stig | none | ~2 min | as `u02` | ~2 min | ~15 G | as `u02` |

Storage added on `/mnt/c` (must be Windows-visible, finding **#5**): 483 MB + 4.17 GB downloads ~ **4.7 GB**, plus two built ISOs ~ **4.6 GB** ~ **9.3 GB**, leaving ~85 G -> still 4 `VM_RUN` slots, or **2 snapshotted upgrade slots** at the 40 G `UPGRADE_RUN` need. `/` at 65 G free is the real risk: `ISO_BUILD` wants 25 G and `$PHOTON_TREE/stage` is 65 GiB per finding **#23**, so the two subrelease builds are the line item that could halt the whole thing.

**Total for the 8-row set: roughly 6-11 hours of VM time, plus 2 ISO builds (each "hours", the 90 one unproven), plus ~4.7 GB of download, plus 2 operator-attended sessions.** A multi-day effort with human gating - and that already reflects the reduction.

**The literal cross-product (172 rows) is unquantifiable and irrelevant, because it cannot be represented at all** (C1). Even ignoring `MAX_INDEX`: at a conservative 45 min per row that is ~130 h of VM time, sequential, on a host whose `/mnt/c` is 98% full, with 8 ISO builds of which 2 are unproven.

### First useful subset

**`u02` alone.** Zero ISO builds (the 4.0 GA minimal ISO is a 483 MB download; the target is the already-cached `minimal-poi2.8-prebuilt`), runs unattended (POI 2.7 supports guestinfo, C3), and exercises the **only** transition `photon-upgrade` actually implements from a 4.0 guest (C5). It produces a real verdict on the four commits that motivated this work.

### Scheduling rules

- Sequential, like everything else.
- Upgrade rows **last** in a mixed run: they hold a VM an order of magnitude longer. `group_rows` (`runner.rs:318`) keeps matrix order, so appending the `u` block gives the right order for free - another reason not to interleave.
- Re-check `disk::admit(&disk::UPGRADE_RUN, ...)` before **every** upgrade row, halting rather than skipping on refusal, per `runner.rs`'s existing `break 'outer`.
- `wait_for_idle`'s `FOREIGN` list (`runner.rs:31`) needs nothing new: an upgrade is guest-side and shares no host resource with a build beyond disk, which `admit` covers.

---

## 9. CLI surface

```
PHASES
    upgrade             run the in-distro upgrade on an installed guest and prove it rebooted

OPTIONS
    --id <perm>         ... (upgrade)
    --to <target>       override the row's target; default is the row's `to` column
    --dry-run           print the resolved invocation and change nothing (upgrade)
    --allow-download    permit fetching published start media; OFF by default
    --keep-snapshot     do not delete the pre-upgrade checkpoint after a pass
    --from-snapshot     revert to the pre-upgrade checkpoint first, then upgrade
```

Refusals, loud and naming the fix (the `build::resolve` refusal at `build.rs:63-73` is the template):

- `upgrade --id k01` -> *"k01 is a fresh-install row (`from` = `-`); there is nothing to upgrade. Upgrade rows are u01-u08."*
- `upgrade` on a row with no `mc-facts.env` recording `installed` -> *"u02 has no completed install (`MC_INSTALL_RESULT` is `<x>`); run `sharukhan install --id u02` first."* Never infer from a booting VM.
- Missing start media without `--allow-download` -> *"no start media at `<path>`; downloading 4.17 GB is never started implicitly. Run `sharukhan media --get ph4-ga --iso-type full --allow-download` when you mean it."* Same policy shape as `--allow-build`.
- Downloaded media whose sha256 != the published sibling, **or** whose embedded build id != `git rev-parse --short=9 4.0-GA` -> refuse with both measured values.
- **`--subrelease` is never exposed on the sharukhan CLI.** It is derived from the row's `to` column (`ph5-92` -> `--subrelease=92`), because letting an operator pass a third, contradictory spelling is how `u02` ends up applying the 91 deprecation list while the report says 92 (C6).
- `MC_GUEST_PASSWORD` required and never printed. The upgrade argv contains no credential and is safe to store in `transition.argv`.

New sub-command `sharukhan media` (list / `--get <start-point>` / verify), so provenance is a first-class, inspectable step and not a side effect of `upgrade`.

---

## 10. Phased delivery

**Phase A - matrix and schema, no new behaviour.** `from`/`to` columns with `-` defaults; `StartPoint`/`Target`; `matrix::load` rejects unknown tokens naming the row; `start_key`/`target_key` split with the three existing `matrix.rs` tests green; `Config::media_dir` folding in `runner::group_rows`'s duplicate; `iso_dir` gains release+subrelease with the legacy spelling preserved; `permutation` gains six columns; `transition` + `v_upgrade_report`; `schema/memory.sql` regenerated; `Checks.prefix`. **No row runs differently.** Provable by `cargo test` plus `plan --all`/`report` producing identical output. *Ships alone.*

**Phase B - provenance.** `sharukhan media --get ph4-ga --iso-type minimal --allow-download`; sha256 against the published sibling **and** build id against the tag; side-cars under `/mnt/c/.../media-cache/`. 483 MB, no VM, no build. *Ships alone.*

**Phase C - spikes, read-mostly, before any upgrade code.**
- **S1** `ph4-ga` installer capability: mount the downloaded GA ISO read-only on the host and read `installer/` - btrfs? STIG menu? which network shapes? Settles the `u01`/`u05` axis cardinalities.
- **S2** second CD-ROM inertness: one throwaway VM, existing `k01` media on the boot device plus the target ISO on a second; confirm the install is unaffected and `detach_cdrom` (C11) leaves the second attached.
- **S3** `--repos` acceptance: on an existing installed guest, write the `gpgcheck=0` target repo and run `tdnf --repo=sharukhan-target list available photon-release` plus `is_repo_config_valid_for_release`'s own probe. Non-destructive.
- **S4** `--precheck-only` non-destructiveness on mainline, against a snapshotted throwaway guest, reverted. Until S4 passes, `--dry-run` does not touch the guest.
- **S5** `%photon_subrelease` / `build_if` evaluation site. Needed only before Phase F.

**Phase D - the `upgrade` phase, on `u02`.** `src/upgrade.rs`, `vmware` snapshot verbs with `listSnapshots` as the authority (#30), the `boot_id` + SSH + fresh-lease reboot oracle, the pre-upgrade gate checks, `Checks.prefix` wired to run `oracle::guest` twice, `transition` upsert in `ingest`. **Delivers the first real verdict.** *Smallest increment producing real signal.*

**Phase E - `u01`, `u05`, `u06`, `u07`, `u08`.** `u01`/`u05` operator-assisted, plus the `ph4-ga` bootstrap sub-step and its NEVR recording. `u06`-`u08` need no new code once Phase D lands. *Each row ships independently.*

**Phase F - `u03`, `u04`.** Needs the release/subrelease cache key actually consumed by `build-iso`/`run`, which today refuses without a `poi-{poi}.patch` and gates on `media::gate` - both must learn that an upgrade row's start media has no PR variant. Then `sharukhan build --subrelease 91 --img minimal-iso`, then `u03`. `u04` last. **Expect `u03`/`u04` to fail informatively** on C5 - there is no subrelease transition to invoke - and that failure is the deliverable.

**Phase G - optional.** `ph4-ga` unattended via ISO remaster (`ks=http://...` + host HTTP server + a 4.0-era kickstart renderer). Removes the operator from `u01`/`u05`. Substantial: a second kickstart schema, an HTTP server in the harness, and an `xorriso` write path where today `xorriso` is only ever *read* from (`media.rs:118`). **Deliberately last.**

---

## 11. Risks and deliberate omissions

**Risks**

1. **`u03`/`u04` may be tautological.** Per C5 a 90/91->92 move reads no subrelease data, so the row may prove only that `tdnf` works. Mitigation: state the expectation up front (`doc=untested`, `expect=pass`) and make `upgrade.subrelease_var` and `upgrade.no_leftover_subrelease` load-bearing - they are the only ones that can distinguish "the subrelease actually moved" from "packages got newer".
2. **The 90 ISO build may not complete.** `runPh5_pinned90.sh`'s own header warns of iteratively discovered bootstrap fixes. `/` has 65 G free against `ISO_BUILD`'s 25 G and a 65 GiB stage. Mitigation: `u04` last; a failure is recorded as a build finding, not an upgrade verdict.
3. **Findings #58 and #59 are live build hazards.** Both are marked DONE at `photonos-scripts 6216e9d`/`767d7dd`, but both are *build*-path, and Phase F is the one phase that builds. Re-read both before starting a subrelease build.
4. **`gpgcheck=0` weakens the verdict.** An upgrade proven against unsigned media does not prove the signed path works. Mitigation: assert it as a caveat (`pre.upgrade.unsigned_target`); add the published-repo variant as a control row later if it matters.
5. **The reboot oracle is new code in the highest-stakes place.** Findings #8, #19, #21, #30 all describe how this has gone wrong before. Mitigation: `boot_id` change **and** SSH banner, both positive, both from inside the guest; `vmrun` return codes logged and never acted on; a timeout is a measured failure with every instrument's reading printed.
6. **Snapshots double VM footprint** on a volume at 98%. Mitigation: a distinct `disk::UPGRADE_RUN` need, re-checked per row, halting rather than skipping.
7. **`u05`/`u06` are the longest rows and the most likely to time out.** Mitigation: a generous `MC_UPGRADE_TIMEOUT_SEC` and the pre-upgrade checkpoint, so a timeout costs the upgrade and not the install.
8. **`MAX_INDEX = 80` is now a shared, contended resource** across this extension and the two planned concurrently. 51 of 80 after this plan. Let the plans agree a budget before anyone appends rows.
9. **`trap '' SIGINT SIGQUIT`** in `photon-upgrade.sh` means `sharukhan stop` cannot cleanly interrupt an in-flight upgrade. Document it; `stop` reports the VM as still powered on, as it already does for orphans.

**Deliberate omissions for v1**

- **5.0 -> 6.0.** The transition mainline `photon-upgrade` actually implements - but `/photon/6.0/` does not exist on Broadcom (404) and there is no `/root/6.0` tree. The `to` column is shaped to accept it later.
- **3.0 -> 4.0.** `PH3RPMTAG` exists in `constants.sh` but no 3.0 transition file does.
- **aarch64.** Same reason `c02` is unrunnable here; 4.0 aarch64 repos are frozen at 30-Oct-2025 anyway.
- **`Rev1`/`Rev2` 4.0 media.** Untagged respins; the double-proof provenance rule cannot be satisfied. If wanted later, the honest identity is "the bytes under `Rev2/` today", nothing stronger.
- **Downgrade / rollback testing.** `photon-upgrade` offers none.
- **`net`, `fips`, `selinux`, `equivalent` crossed with `from`.** Reasons go in the TSV so they are not re-litigated.
- **Automated `ph4-ga` install** (Phase G).
- **Package-set deltas in SQLite.** Files in the evidence tree; the DB indexes verdicts.

---

## 12. New findings to record

All observed, not hypothesised. To be deduplicated against findings already filed on 2026-09-11 before insertion.

| slug | category | severity | evidence |
|---|---|---|---|
| `iso-cache-key-omits-release-and-subrelease` | build | high | `config.rs:301-303` keys on `{iso_type}-poi{poi}-{canister}`; a subrelease-90 and a mainline ISO collide. Same class as #13 |
| `build-iso-cannot-reach-release-or-subrelease` | build | high | `build.rs:20` `IsoRequest` has three fields; `build.rs:257` passes `subrelease: None`; `build.rs:269` execs `runPh5_normal.sh`. Only `sharukhan build` varies them, and the matrix cannot reach it |
| `variant-patch-mechanism-is-5-0-only` | build | high | `build.rs:594` `VARIANTS`, `build.rs:704` base ref `"5.0"`; `resolve` refuses without `poi-{poi}.patch` (`build.rs:112`) and `runner` gates on `media::gate` |
| `ph4-ga-installer-has-no-guestinfo-channel` | hypervisor | blocker | `git show 4.0-GA:installer/isoInstaller.py` reads only `ks=`/`repo=`/`photon.media=`; guestinfo first appears in poi `v2.7` |
| `photon-upgrade-has-no-subrelease-transition` | defect | high | `photon-upgrade.sh:936-947` accepts only `6.0` on mainline / `5.0` on 4.0; the empty-`TO_VERSION` arm sources no transition file, so `update_os` runs `find_installed_deprecated_packages` against an unset array |
| `photon-upgrade-absent-on-4-0-ga` | tooling | high | first added by `75a535c1f` on the `4.0` branch, long after `1526e30ba` (2021-02-24); `tdnf` 3.0.0 vs 3.3.12 |
| `photon-upgrade-default-subrelease-is-91` | defect | medium | `SUBRELEASE=${SUBRELEASE:-91}`; reaching mainline needs `--subrelease=92`, and the 92 list differs from 91 by exactly four packages |
| `photon-upgrade-binary-keeps-sh-suffix` | tooling | low | `%install` puts `Source0` (`photon-upgrade.sh`) in `%{_bindir}` with no symlink; the script hardcodes `/usr/lib/photon-upgrade` while `%install` uses `%{_libdir}` |
| `permutation-table-omits-canister-and-net` | tooling | medium | `ingest.rs:189-207`; `c01` and `k09` are indistinguishable in the DB, and `n01`-`n05` from `k01` |
| `permutation-table-has-no-duration` | tooling | medium | `started_at = finished_at = ?12` (`ingest.rs:196`); no wall clock exists anywhere in the DB |

---

## 13. Files a first implementation touches

`mission-control/config/permutations.tsv` - `src/matrix.rs` - `src/config.rs` - `src/evidence.rs` - `src/oracle.rs` - `src/verify.rs` - `src/install.rs` (C11) - `src/vm.rs` - `src/vmware.rs` - `src/phases.rs` - `src/runner.rs` - `src/ingest.rs` - `src/report.rs` - `src/main.rs` - `schema/memory.sql` - **new** `src/upgrade.rs`, `src/media.rs` (extend) - `README.md`, `specs/prd.md`, `specs/adr/0002-upgrade-transitions.md`.
