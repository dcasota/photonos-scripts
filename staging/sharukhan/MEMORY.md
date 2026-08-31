# MEMORY.md

**Generated. Do not edit.** This file is a rendering of the sharukhan memory
database; the database is the system of record. Editing here changes nothing and
will be overwritten on the next render.

- Source database: `/root/photon-mc/memory.db`
- Rendered at: 2026-08-31T14:21:54Z
- Regenerate with: `python3 tools/gen-memory-md.py /root/photon-mc/memory.db MEMORY.md`

| Table | Rows |
|---|---|
| `run` | 0 |
| `permutation` | 0 |
| `check_result` | 0 |
| `artifact` | 0 |
| `finding` | 27 |

## Permutation results

_No permutation has completed yet._

## Findings

### Blocker

#### `installer-console-dispatch` — POI runs the installer only on the single active console

*hypervisor · verified* · source: `generate_initrd.py create_installer_script`

**Observed.** bootphotoninstaller reads /sys/devices/virtual/tty/console/active and runs the installer only if it equals tty0 (then on /dev/tty1) or if tty() equals /dev/$ACTIVE_CONSOLE. With console=tty0 console=ttyS0 the value is 'ttyS0 tty0', matching neither branch, so it falls through to exec /bin/bash.

**Consequence.** The installer never starts and the VM sits at a root shell; with no serial console at all the same state is completely invisible.

**Mitigation.** Remaster grub.cfg with console=ttyS0,115200n8 ONLY for autonomous runs. Verified: the installer then starts on serial. Interactive runs keep the stock ISO so the operator drives tty0.

#### `iso-must-be-windows-visible` — VMware cannot read an ISO on a WSL-only path

*hypervisor · verified* · source: `mc-create-vm.sh`

**Observed.** ISO at /root/photon-mc/... became VMX value \root\photon-mc\...; vmrun reported only 'Error: The operation was canceled'.

**Consequence.** The VM never powers on and the error names nothing.

**Mitigation.** Keep MC_ISO_CACHE under /mnt/<drive>/; refuse a non-/mnt ISO with an explicit diagnosis.

#### `no-serial-console-on-iso` — The Photon ISO does not route the kernel to serial

*hypervisor · verified* · source: `mc-k01 first run`

**Observed.** The ISO's /boot/grub2/grub.cfg menuentry is 'linux /isolinux/vmlinuz root=/dev/ram0 loglevel=3 photon.media=UUID=$photondisk' with no console=ttyS0. Serial log stayed 0 bytes for 15+ minutes while the VM ran.

**Consequence.** Install progress and completion are unobservable; the boot-source transition oracle can never fire.

**Mitigation.** Remaster grub.cfg to console=ttyS0,115200n8 only. Verified: 61KB of kernel output and the installer now runs on serial.

#### `vmrun-nogui-unsupported` — vmrun headless start fails on this host while gui start works

*hypervisor · verified* · source: `mc-k01 bisect`

**Observed.** 'vmrun -T ws start <vmx> nogui' returns 'Error: Unknown error' and creates no vmware.log at all. The identical VMX - including one VMware itself had rewritten after a successful power-on - starts immediately with 'gui', producing a 202 KB vmware.log and serial output.

**Consequence.** Every autonomous permutation fails to launch, and the logless error invites misdiagnosis: the VMX was blamed first, then pinned PCI slot numbers, before bisecting against a known-good VMX proved the file was never the problem.

**Mitigation.** Use gui for autonomous starts too. Headless needs VMware Workstation Server / shared-VM support, which is not enabled here.

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

#### `packagelist-file-name` — packages_minimal.json is not on the installer media

*build · verified* · source: `mc-k01 serial log`

**Observed.** The kickstart named packages_minimal.json; the installer aborted with FileNotFoundError: '/installer/packages_minimal.json'. The initrd ships only /installer/packages.json, containing linux-esx, less, sudo, linux, initramfs, lvm2, minimal.

**Consequence.** Every kickstart-driven install fails before partitioning.

**Mitigation.** Use packagelist_file=packages.json, or omit it and pass an explicit packages list.

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

#### `results-overwritten-per-run` — Re-running a permutation destroys the previous run's evidence

*defect · verified* · source: `user request; confirmed in mc-verify.sh`

**Observed.** mc-verify.sh truncates $MC_RESULTS_DIR/<perm>/checks.jsonl on every invocation, and harvested guest logs use fixed filenames. k01 was run five times; only the last run's checks survived.

**Consequence.** Evidence for a regression is lost exactly when a comparison between runs is what would explain it.

**Mitigation.** Every artifact is UTC-stamped: checks-<stamp>.jsonl, logs-<stamp>/, report-<stamp>.txt, each with a -latest pointer. One stamp per run, exported so all children share it. Verified: two consecutive report runs produced two files.

#### `installed-system-serial-silent` — Remastering the ISO does not make the INSTALLED system serial-visible

*hypervisor · verified* · source: `mc-k01 run 4`

**Observed.** After the installer rebooted, the serial log froze at 119354 bytes and never grew. root=PARTUUID= never appeared, so the boot-source completion oracle could not fire, even though the install had succeeded (partitioning done, chroot populated, postinstall run, 'reboot: machine restart').

**Consequence.** A successful install is scored as a timeout. The harness would report failure for working software - the worst possible error for a test oracle.

**Mitigation.** Two changes: the kickstart postinstall now adds console=ttyS0,115200n8 to the target's grub, and the installer waits on EITHER the boot-source transition OR a guest IP from VMware Tools.

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

#### `vmrun-needs-a-session` — vmrun start silently does nothing from a fully detached process

*hypervisor · verified* · source: `k01 clean run`

**Observed.** 'setsid vmrun -T ws start <vmx> gui' produces no output, no VM and no vmware.log. The same command from a shell with a controlling terminal starts the VM immediately. nohup alone is fine; setsid is what breaks it.

**Consequence.** A background matrix run appears to be waiting on an install that was never started, and times out with nothing to show.

**Mitigation.** Launch background work with nohup, never setsid.

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

#### `builds-serial-installs-parallel` — Only ISO builds must serialise; installs are independent

*build · verified* · source: `PRD review after host measurement`

**Observed.** ISO builds share and mutate $PHOTON_TREE/stage (65 GiB) via git checkout, patch apply and the stale-RPM purge, so two concurrent builds corrupt each other. VM installs share nothing: each permutation owns its VM directory, disk, MAC, UUID and results directory.

**Consequence.** PRD section 7 claimed sequential execution was correctness rather than an unimplemented optimisation. That is true for builds and false for installs, and it would have prevented a legitimate 3x speedup.

**Mitigation.** Amend PRD section 7: builds serialise, installs fan out under admission control. Recorded as specs/findings and corrected by PR.

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

#### `foreign-pci-slot-pins` — Pinned PCI slot numbers do not transfer between hosts

*hypervisor · verified* · source: `VMX diff against the rewritten file`

**Observed.** The template pinned sata0.pciSlotNumber=35 and ethernet0.pciSlotNumber=160, inherited from a template captured elsewhere. VMware rewrote them to 18 and 17 on the one power-on that succeeded, and had already refused vmxnet3 with 'failed to reserve slot for vmxnet3 PCIe device'.

**Consequence.** A foreign slot layout can make power-on fail in ways that name nothing.

**Mitigation.** Pin no pciSlotNumber at all and let VMware assign. Pin only uuid.bios; uuid.location is VMware's own.

#### `vmrun-crlf` — vmrun output is CRLF and breaks naive line matching

*portability · verified* · source: `mc-preflight.sh`

**Observed.** vmrun -T ws list lines end \r\n; grep -c '\.vmx$' returned 0 against 2 running VMs.

**Consequence.** VM-running checks report false negatives, so a teardown could act on a live VM.

**Mitigation.** tr -d '\r' on every vmrun parse.

#### `per-vm-resource-cost` — A running VM costs memSize on disk plus its growing thin disk

*tooling · verified* · source: `mc-k01 vm directory`

**Observed.** Measured on mc-k01: the .vmem file is exactly 4294967296 bytes (= memSize 4096 MiB) and exists only while the VM runs; the thin .vmdk grew 4 MiB -> 914 MiB during install. Peak per concurrent VM is therefore about memSize + installed footprint.

**Consequence.** A concurrency limit derived from CPU count alone over-commits RAM and disk on smaller hosts.

**Mitigation.** Admission control takes min(cpu_slots, ram_slots, disk_slots), recomputed per dispatch, not a fixed startup value.

