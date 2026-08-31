# MEMORY.md

**Generated. Do not edit.** This file is a rendering of the sharukhan memory
database; the database is the system of record. Editing here changes nothing and
will be overwritten on the next render.

- Source database: `/root/photon-mc/memory.db`
- Rendered at: 2026-08-31T13:31:35Z
- Regenerate with: `python3 tools/gen-memory-md.py /root/photon-mc/memory.db MEMORY.md`

| Table | Rows |
|---|---|
| `run` | 0 |
| `permutation` | 0 |
| `check_result` | 0 |
| `artifact` | 0 |
| `finding` | 18 |

> **1 unresolved blocker finding(s).** See the Blocker section.

## Permutation results

_No permutation has completed yet._

## Findings

### Blocker

#### `iso-must-be-windows-visible` — VMware cannot read an ISO on a WSL-only path

*hypervisor · verified* · source: `mc-create-vm.sh`

**Observed.** ISO at /root/photon-mc/... became VMX value \root\photon-mc\...; vmrun reported only 'Error: The operation was canceled'.

**Consequence.** The VM never powers on and the error names nothing.

**Mitigation.** Keep MC_ISO_CACHE under /mnt/<drive>/; refuse a non-/mnt ISO with an explicit diagnosis.

#### `no-serial-console-on-iso` — The Photon ISO does not route the kernel to serial

*hypervisor · **UNRESOLVED*** · source: `mc-k01 first run`

**Observed.** The ISO's /boot/grub2/grub.cfg menuentry is 'linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=UUID=$photondisk' with no console=ttyS0. Serial log stayed 0 bytes for 15+ minutes while the VM ran.

**Consequence.** Install progress and completion are unobservable; the boot-source transition oracle can never fire.

**Mitigation.** Open: remaster grub.cfg to add console=ttyS0,115200, or detect completion via getGuestIPAddress on the installed system.

#### `vmxnet3-pci-slot` — vmxnet3 cannot reserve a PCI slot in this VMX layout

*hypervisor · verified* · source: `vmware.log mc-k01`

**Observed.** vmware.log: 'Vmxnet3 PCI: failed to reserve slot for vmxnet3 PCIe device' then "Module 'DevicePowerOn' power on failed." vmrun surfaced only 'Error: The operation was canceled'.

**Consequence.** The VM cannot power on at all.

**Mitigation.** Use e1000, as vm-lab documented. A hand-made VM on this host runs vmxnet3 but has a different PCI slot layout, so it was not evidence.

#### `toybox-grep-no-dash-a` — toybox grep has no -a and returns zero matches on NUL-bearing logs

*portability · verified* · source: `mission-control lib/common.sh`

**Observed.** In a non-interactive shell /usr/bin/grep is toybox 0.8.9; its usage line has no -a. `grep -ac PATTERN nul-log` returned 0 where the pattern was present. Interactively the same name resolves to ugrep 7.8.4, which supports -a and -P.

**Consequence.** Every serial-log assertion silently passes while measuring nothing. A green run would prove nothing.

**Mitigation.** Strip NULs before matching; never depend on a grep flag. Verified: mc_grep_count returns 1 on a NUL-prefixed log.

### High

#### `stale-poi-rpm-shadowing` — A stale installer RPM in the stage tree ships on the ISO

*build · verified* · source: `mc-build-iso.sh`

**Observed.** tdnf selects the highest release it can see, so an older photon-os-installer left in stage/RPMS wins.

**Consequence.** A run reports a verdict for installer code nobody ships.

**Mitigation.** Purge photon-os-installer-*.rpm before each build and record the NEVR that actually shipped. Verified: media carries photon-os-installer-2.8-5.

#### `two-divergent-patch-copies` — Two copies of downstream-fixes.patch had diverged

*build · verified* · source: `mc-build-iso runs 1-2`

**Observed.** /root/photonos-patches/...patch had 27 files; staging/photonos-patches/...patch had 8. The build script resolves the patch relative to itself, so it used whichever sat beside the invoked copy.

**Consequence.** The build silently omits fixes and fails with 'patch does not apply' against a spec, which reads like a rebase problem.

**Mitigation.** PHOTON_SCRIPTS points at the live pair; preflight asserts the build resolves the same file it validated.

#### `hashed-perm-index-collides` — A cksum-based permutation index collides and can enter the DHCP range

*defect · verified* · source: `mission-control lib/common.sh`

**Observed.** Over the 34-row matrix, cksum%200 produced 32 distinct indices: k04/k16 and k09/s02 collided. Max index 200 maps to .240, inside VMnet8 DHCP (.128-.254).

**Consequence.** Two permutations share a MAC, UUID and IP; addresses can collide with real leases.

**Mitigation.** Index is the row ordinal in permutations.tsv. Verified 34/34 distinct, addresses .41-.74.

#### `printf-drops-last-item` — printf '%s' without a newline makes read drop the last item

*defect · verified* · source: `mc-run.sh select_rows`

**Observed.** --only k01,k03 selected only k01; --only k01,k03,k09 omitted the full/2.8 ISO.

**Consequence.** A run silently covers fewer permutations than reported.

**Mitigation.** printf '%s\n'. Verified all three ids now selected.

#### `no-vmware-tools-during-install` — VMware Tools is not running during the install phase

*hypervisor · verified* · source: `vmware.log mc-k01`

**Observed.** getGuestIPAddress returned 'The VMware Tools are not running'; captureScreen returned 'Anonymous guest operations are not allowed'. vmware.log shows Tools heartbeat 1 => 0.

**Consequence.** No guest-side liveness or IP discovery during install.

**Mitigation.** Do not rely on Tools before first boot of the installed system. vmtoolsd one-shot --cmd still works for guestinfo reads.

#### `uefi-ignores-bootorder` — UEFI ignores bios.bootOrder; NVRAM decides the boot source

*hypervisor · verified* · source: `vm-lab README`

**Observed.** Documented in vm-lab and carried forward: a surviving ESP plus NVRAM makes the firmware boot the previous image.

**Consequence.** An install appears to silently do nothing while the old image boots.

**Mitigation.** Stash .nvram before install and at teardown; stash the whole chain by glob, not a fixed list.

#### `gnu-only-sed-grep` — sed \U and grep -P are GNU extensions absent on this host

*portability · verified* · source: `mc-build-iso.sh, mc-create-vm.sh`

**Observed.** grep -oP failed with "Unknown option 'P'"; sed 's|...|\U\1:|' emitted a literal 'Uc:' instead of uppercasing.

**Consequence.** Path conversion and version parsing silently produce wrong values rather than erroring.

**Mitigation.** Use tr and awk. mc_win_path uses tr; version parsing uses awk.

#### `editing-a-running-script` — Editing a shell script while it runs corrupts execution

*tooling · verified* · source: `mc-build-iso run 1`

**Observed.** mc-build-iso.sh was edited mid-run; bash re-read the file at the next command boundary and died with 'syntax error near unexpected token (' at line 68, after the child build had already succeeded.

**Consequence.** The wrapper's post-processing was skipped while the expensive work completed, leaving a half-finished artifact.

**Mitigation.** Never edit a script that is executing. sharukhan is a compiled binary, which removes the class.

#### `rust-install-broke-ssh` — Installing rust upgraded openssl and broke openssh

*tooling · verified* · source: `host toolchain`

**Observed.** tdnf install rust pulled openssl 3.5.7 and removed 3.0.18; ssh then failed with 'OpenSSL version mismatch. Built against 30000120, you have 30500070'.

**Consequence.** Guest verification silently becomes impossible, and a version-skewed ssh presents exactly like an unreachable host.

**Mitigation.** Upgraded openssh-clients to 10.4p1. Prerequisite checks must report version and provenance, not a boolean.

### Medium

#### `canister-hardcoded-in-verify` — Cached ISO lookup hardcoded the prebuilt canister mode

*defect · verified* · source: `mc-verify.sh`

**Observed.** mc-verify.sh built the cache path as ${ISO_TYPE}-poi${POI}-prebuilt.

**Consequence.** An ISO built with canister build/acvp/kat would be verified against a different artifact.

**Mitigation.** Derive from MC_CANISTER.

#### `static-ip-never-applied` — The static-address scheme was computed but never applied

*defect · verified* · source: `inventory of mission-control`

**Observed.** mc_ip_for is computed and logged, but --ip is never passed to the kickstart generator, so every kickstart emits network.type=dhcp.

**Consequence.** The documented 'static below the DHCP floor' property was never in effect; verification depends on IP discovery instead.

**Mitigation.** Either wire it through or remove it; the half-state is worse than either.

#### `subshell-counter-loss` — Counters incremented inside a piped while-read are discarded

*defect · verified* · source: `mc-run.sh`

**Observed.** mc-run.sh piped into `while read`, so total/failed stayed 0 in the parent.

**Consequence.** The run summary always reported zero attempted.

**Mitigation.** Feed the loop with a here-string. Verified: now reports '1 permutation(s) attempted, 1 with failing checks'.

#### `drvfs-symlink-not-followable` — A WSL symlink on drvfs is not reliably followable from Windows

*hypervisor · verified* · source: `mc-create-vm.sh`

**Observed.** photon.iso is a symlink; also observed a self-referential link created because locale collation sorted 'photon.iso' before 'photon-minimal-...iso'.

**Consequence.** The VMX references a link Windows may not resolve.

**Mitigation.** readlink -f the ISO and write the concrete filename into the VMX.

#### `vmrun-crlf` — vmrun output is CRLF and breaks naive line matching

*portability · verified* · source: `mc-preflight.sh`

**Observed.** vmrun -T ws list lines end \r\n; grep -c '\.vmx$' returned 0 against 2 running VMs.

**Consequence.** VM-running checks report false negatives, so a teardown could act on a live VM.

**Mitigation.** tr -d '\r' on every vmrun parse.

