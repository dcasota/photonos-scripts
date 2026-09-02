# mission-control — execute the ISO permutation matrix

> **2026-09-01: the scripts described below have been superseded by
> `sharukhan`.** `bin/` and `lib/` moved to `superseded-bash/` (the two names
> here are now symlinks, for one in-flight build - see
> [`superseded-bash/README.md`](superseded-bash/README.md)). `config/` is still
> live: `permutations.tsv` is read at runtime and
> `photon-matrix.vmx.template` is compiled into the binary. Everything below
> still describes what the harness DOES; the commands are now
> `sharukhan <phase>`.

`ISO-PERMUTATION-MATRIX.md` says of itself: **"No builds were run."** Fourteen
of its sixteen rows are resolution predictions or code reading; only two were
ever installed. This directory is the part that was missing — it builds the
ISOs, stages the VMs, drives the installs, and verifies the result against an
oracle that names the PR behind every failure.

It reuses the mechanics of `../vm-lab` (VMX discipline, thin disks,
stash-never-delete teardown, the serial-log liveness instrument) and drops
everything specific to the SPAGAT-Librarian appliance, which is out of scope.

---

## The one thing that makes this tractable

POI's `isoInstaller` does not only read `ks=` from the kernel command line. It
reads **`guestinfo.kickstart.data`** (base64) and `guestinfo.kickstart.url`
through `vmtoolsd`, and `/usr/bin/vmtoolsd` is present in the installer initrd
(`open-vm-tools` is in `packages_installer_initrd.json`).

So a per-permutation kickstart is **one line in the VMX**. No ISO remaster, no
HTTP server, no typing at a boot menu. That splits the matrix cleanly:

| Layer | Axes | Cost |
|---|---|---|
| **Build time** | ISO type × installer version × canister | one ISO per tuple, cached and reused |
| **Install time** | STIG × filesystem × kickstart-vs-UI × network | free |

41 permutations, 6 ISO keys — of which 4 (`{minimal,full} × {2.8,latest}` on
`prebuilt`) serve 34 rows. The canister is a **build-time** axis, so c01
(`full/2.8/equivalent`) costs its own multi-hour build; c02
(`full/2.8/fips0-aarch64`) needs aarch64 hardware and is never built here.
That asymmetry is why the canister rows are kept to the minimum that can prove
anything — see ISO-PERMUTATION-MATRIX.md §2b.

The **network** axis (`net` column, rows n01–n05) is install-time for the same
reason the others are: the config travels in `guestinfo.kickstart.data` and is
applied by `_setup_network()` against an already-installed root. All five rows
share k01's ISO key, so the block costs five installs and **zero** builds.
`Permutation::iso_key()` excludes it deliberately, and a test asserts that.

It is also not crossed with `poi`, because there would be nothing to find:

```
$ git -C photon-os-installer diff v2.8 master -- photon_installer/networkmanager.py
$
```

`networkmanager.py` is byte-identical across the poi axis, so a `poi=latest`
network row would re-test the same file at the price of a second multi-hour
ISO.

## The network axis, and what this host cannot test

`permutations.tsv` carries a `net` column: `<family>-<assignment>-<vlan>`, with
an absent column meaning `v4-dhcp-untag` — exactly what every pre-existing row
already did. The full grammar, the schema split, and the environment knobs are
in `sharukhan-cli/README.md`.

Seven of the twelve nominal cells are absent, for reasons that belong to **this
host** rather than to POI. Recorded here because they are the hard part to
reconstruct later:

**IPv6 — three independent blockers, any one sufficient:**

1. `vmnetnat.conf` has `natIp6Enable = 0`: the vmnet8 NAT device emits no
   router advertisement and offers no IPv6 gateway.
2. **No DHCPv6 server exists on this host in any configuration.**
   `VMnetDHCP.exe` is a VMware port of ISC 2.0, IPv4-only, and
   `vmnetdhcp.conf` declares only IPv4 subnets. Enabling `natIp6Enable` would
   not create one.
3. **WSL2 runs `networkingMode = Nat` and has no IPv6 stack** — only
   link-local in `/proc/net/if_inet6`, and `ping -6` says "Network is
   unreachable". The harness itself cannot reach a guest over IPv6 whatever
   the hypervisor does.

DHCPv6 and SLAAC rows are therefore recorded as unrunnable rather than run and
failed. **Static** IPv6 needs no router, no server and no peer, so it is
testable and is what n02/n03 do.

**VLAN — one blocker:**

4. **VMware Workstation 17 has no VLAN backing of any kind.**
   `ethernet0.vlanID` is a vSphere portgroup property; `strings` over
   `vmware-vmx.exe`, `vmnetBridge.dll` and `vnetlib.dll` finds no VLAN or
   trunk symbol, and the Virtual Network Editor has no VLAN concept. Tagging
   can only happen inside the guest, and nothing on vmnet8 answers a tagged
   frame. Bridged mode is no escape — the only uplink is Wi-Fi, and 802.1Q
   over a bridged wireless adapter does not work.

A VLAN row therefore proves what the installer **configured**, never that
tagged traffic flows.

### n05 is environmental; s02 is a defect

`n05` (`v4-dhcp-vlan100`) carries `expect = fails`, and that failure is caused
by blocker 4 — no change to Photon or to the installer would make it pass here.
`s02` carries the same verdict for the opposite reason: it is a real defect and
somebody should fix it. **A reader who cannot tell these apart will eventually
fix the wrong one.**

Underneath n05 there is a genuine POI gap: `networkmanager.py` writes only
`[Match]`, `[Network]`, `[NetDev]` and `[VLAN]` sections, so
`RequiredForOnline=` is unreachable from the kickstart schema — an operator who
knows a link cannot come up has no way to say so, and
`systemd-networkd-wait-online` (enabled by preset) fails forever. Written up in
`/root/photon-mc/poi-gap-requiredforonline.md` for filing upstream separately.

## Why both kickstart and UI

Not thoroughness — they exercise different code, and each has a failure mode
the other cannot reach.

- The **STIG menu is UI-only.** `stigenable.py` is reached solely from the
  curses configurator, so a kickstart can never "answer yes"; it has to list
  `KS_STIG_PACKAGES` by hand. That is what `variant=stigpkgs` does.
- The **`security:` key is kickstart-only** on POI 2.8. Rows `s01`/`s02` cover
  it, and `s02` (`security: {fips: …}`) is reachable *exclusively* from a
  kickstart on either installer version.
- The **network axis is UI-unreachable.** `netconfig.py` offers only DHCP,
  DHCP-with-hostname, manual static and VLAN, and its `validate_ipaddr` hard-
  requires four dotted decimal octets — the installer UI cannot accept an IPv6
  address at all. So `net` varies only on `mode=ks` rows, and the two legacy
  tokens (`v4-static-untag`, `v4-dhcp-vlanNNN`) are precisely the shapes a UI
  install would have written.
- The **same failure looks different** on the two paths. In UI mode a missing
  package reduces to `InstallerError("Installer failed")` on screen with the
  real cause only in `/var/log/installer`; in kickstart mode the tdnf error
  surfaces directly. An oracle calibrated on one path misreads the other.

---

## Layout

```
mission-control/
├── config/
│   ├── mission-control.env        every value overridable: ${VAR:=default}
│   ├── permutations.tsv           the matrix as data, with doc vs expected verdict
│   └── photon-matrix.vmx.template 10 placeholders, incl. per-permutation UUID
├── lib/
│   ├── common.sh                  config locator, structured results, identity
│   └── oracle.sh                  the assertions - each names the PR it proves
└── bin/
    ├── mc-preflight.sh            can this host do the job?
    ├── mc-build-iso.sh            build-axis tuple -> cached ISO
    ├── mc-gen-kickstart.sh        permutation -> kickstart JSON
    ├── mc-create-vm.sh            thin disk + VMX + guestinfo injection
    ├── mc-install.sh              autonomous or operator-driven install
    ├── mc-verify.sh               run the oracle, harvest the logs
    ├── mc-teardown.sh             stash the whole chain, keep the evidence
    └── mc-run.sh                  drive it all, report at the end
```

## Use

```bash
export MC_DIR=$PWD                 # or run from this directory
./bin/mc-preflight.sh              # measured host readiness
./bin/mc-run.sh --all --plan       # what would run, builds nothing
./bin/mc-run.sh --only k01,k03     # two autonomous permutations
./bin/mc-run.sh --only p03         # interactive: prompts, then waits
./bin/mc-run.sh --report           # re-print from stored results
```

Runs are **sequential**: every ISO build shares `$PHOTON_TREE/stage`, and C:
has ~138 GB free, so VMs are torn down after verification rather than kept.

## How a PR regression shows up

Every assertion carries the PR it proves, so the report names the culprit:

```
ID     ISO      POI     STIG  FS     MODE  DOC       RESULT    PRs implicated
p03    minimal  2.8     yes   ext4   ui    fails     FAIL(2)   POI#11
```

`DOC` is the verdict the matrix recorded *before* the PRs. A row whose result
reproduces `DOC`'s `fails` is a regression, and the PRs column says which one.
The oracle can currently implicate **PR#9, PR#21, PR#22, PR#24, POI#9, POI#10,
POI#11**.

Results land in `$MC_RESULTS_DIR/<perm>/`: `checks.jsonl` (one JSON object per
assertion), `kickstart.json`, and `logs/` with dmesg, `journalctl -b`,
`journalctl -p err`, failed units, `rpm -qa`, `/proc/cmdline`, mounts,
`/var/log/{installer,ansible-stig,messages}`, the mkinitrd log and the POI
manifest.

The matrix supplies a *dependency-resolution* oracle only — `Error(1011)`,
media RPM presence, NEVRs. It gives no dmesg/journalctl/`/var/log` criteria at
all, so that layer is new here.

---

## Things that will bite

**`Error(1032)` is not a success signal.** It is the `--assumeno` dry-run
abort. A real install never emits it. Only `Error(1011)` means "a package the
installer asked for is not on the media".

**Never match a single package name.** `list(set(packages))` in `installer.py`
randomises which of the six missing names tdnf reports first. The matrix
reproduced `rsyslog` where the user saw `libselinux-utils`; both were right.
Match on `Error(1011)` and set membership.

**`grep -a` does not work here.** In a non-interactive shell `/usr/bin/grep` is
toybox, which has no `-a` and returns *zero matches* on a NUL-bearing serial
log rather than erroring. `mc_grep_count` strips NULs first. Interactively
`grep` is `ugrep`, which behaves differently again — so anything that works at
your prompt may still be wrong inside a script.

**`sed \U` and `grep -P` are GNU extensions** and are absent here for the same
reason. `mc_win_path` uses `tr`.

**UEFI ignores `bios.bootOrder`.** The NVRAM decides. Both install and teardown
stash `.nvram`, or the firmware's removable-media fallback finds the old ESP
and boots the *previous* image — which looks exactly like an install that
silently did nothing.

**Purge stale installer RPMs before every build.** tdnf takes the highest
release it can see, so a months-old `photon-os-installer` left in
`stage/RPMS/` silently wins and ships on the ISO. `mc-build-iso.sh` deletes
them and records the NEVR that actually shipped. A run that exercises a stale
installer is worse than no run: it reports a verdict for code nobody ships.

**Identity is positional, not hashed.** A `cksum`-based index collided on this
very matrix (`k04`/`k16` and `k09`/`s02` shared a MAC, UUID and IP) and could
reach `.240`, inside VMnet8's DHCP range. The ordinal in `permutations.tsv` is
unique by construction and keeps addresses at `.41–.74`.

**Do not blanket-stop VMs.** This host runs other VMs, including live CI
runners. Every operation targets `mc-<perm>` by name.

**Keep VMs off OneDrive.** The hand-made test VM lived under
`OneDrive/Dokumente/Virtual Machines` and disappeared mid-session. Mission
control uses `C:\photon-mc\vm`.
