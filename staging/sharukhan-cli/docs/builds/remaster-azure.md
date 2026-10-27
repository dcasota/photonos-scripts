# Remaster mode

[← sharukhan overview](../../README.md)

**Who this is for:** Someone making an Azure variant of an ISO that already exists.

## Remaster mode: an Azure variant of an ISO that already exists

An Azure guest needs Hyper-V support **built into** the kernel rather than as
modules:

```
CONFIG_HYPERV=y  CONFIG_HYPERV_STORAGE=y  CONFIG_HYPERV_NET=y  CONFIG_HYPERV_UTILS=y
CONFIG_HYPERV_BALLOON=y  CONFIG_HYPERV_VSOCKETS=y  CONFIG_PCI_HYPERV=y
```

The installer's initrd is a fixed rootfs, not a dracut image, so `=m` leaves the
installer kernel depending on udev autoloading from a module tree it may not
reach. `=y` removes that dependency.

```
sharukhan remaster --in photon-5.0-c6db6a0d6.aarch64.iso \
                   --out photon-5.0-c6db6a0d6.aarch64.azure.iso \
                   --arch aarch64 --hyperv \
                   --photon-tree /path/to/photon@<the commit that built --in> \
                   --sources /path/to/SOURCES --builddir /path/to/scratch
```

`--hyperv` also exists on `build` and `build-iso`, where it joins the cascade as
`inject:kernel-config[...]` + `inject:release-bump[...]`.

### Why remaster rather than build

A full aarch64 ISO on an x86_64 host is hundreds of packages under qemu-user at
roughly a tenth of native speed — days. An Azure variant changes exactly one
thing, so `remaster` rebuilds the kernel spec alone and swaps the results into
the medium: bootstrap → gen-config → build-kernel → initrd → repo → iso →
verify, each resumable, because `build-kernel` takes hours.

### The dependency closure is computed, not listed

A tristate cannot be `y` unless every symbol it depends on is `y`. Writing
`CONFIG_HYPERV_UTILS=y` into a config where `CONFIG_CONNECTOR=m` does not fail —
`olddefconfig` silently demotes it back to `m`, and the only visible consequence
is a kernel that cannot find VMBus devices. So the fragment carries the seven
symbols that were **asked for**, and the enabling symbols are computed from the
config at hand and reported:

```
dependency closure raised 3 symbol(s):
  CONFIG_CONNECTOR: m -> y (else CONFIG_HYPERV_UTILS cannot be y)
  CONFIG_SCSI_FC_ATTRS: m -> y (else CONFIG_HYPERV_STORAGE cannot be y)
  CONFIG_VSOCKETS: m -> y (else CONFIG_HYPERV_VSOCKETS cannot be y)
```

The edges come from the kernel's Kconfig, but nothing trusts them: after
`olddefconfig`, every symbol is asserted `=y` by name. If an edge is wrong or
the kernel moved, the build stops and says which symbol. `PCI_MSI_IRQ_DOMAIN`
gated `PCI_HYPERV` in 6.1 and does not exist in 6.12 — which is exactly why the
table is re-checked per kernel rather than copied forward.

**`config_x86_64_acvp` is never touched**, and `--hyperv` is refused for the
`acvp` and `kat` canister modes: those are FIPS certification artefacts.

### The toolchain comes off the input ISO

The kernel is compiled by the toolchain generation that produced the rest of the
media — read from the input, never named in code. A kernel built against a
different glibc or binutils ships modules whose vermagic disagrees with the
userland around them, and that fails at boot rather than at build time.

### The accelerator is gated on byte identity

Under emulation the kernel compiles ~10× slower than native. An x86_64-hosted
cross `cc1`, built from the *same* gcc source, removes most of that — but "same
version" is not evidence: gcc's configure silently disables SHF_MERGE,
SHF_LINK_ORDER, CFI directives and LEB128 support when it cannot find a target
assembler, and the resulting compiler emits different code while reporting the
same version.

So real kernel translation units the media's own compiler already built are
recompiled with the native one and compared **byte for byte**. Any difference,
any failed compile, or fewer than five samples refuses the swap. Only
`-nostdinc` compiles are routed to it; `as` and `ld` are never swapped, because
Photon patches gas's DWARF output. `--no-accel` declines it outright.

### What verify reads back off the finished ISO

Five independent assertions, because each can pass while another fails:

1. the kernel RPM **on the media** carries the symbols in `/boot/config-<uname>`
2. `isolinux/vmlinuz` is byte-identical to that RPM's `/boot/vmlinuz-<uname>`
3. the installer kernel's **own embedded ikconfig** carries them — the only
   evidence about the binary rather than about a file beside it
4. the initrd carries exactly one module tree, at the new uname, with no `hv_*`
   modules left
5. the repo metadata lists the new NEVR and not the old one

### The replacement set is derived

Every package on the media whose `SOURCERPM` is the kernel SRPM — which on 5.0
includes **`bpftool`**, whose name gives no hint and which carries
`Requires: linux-tools = V-R`. Leaving it behind breaks the repo. It is read
from `primary.xml`, never hardcoded.

### A config change must change the NEVR

`Release: N` becomes `N+1.azure`, so `6.12.109-4.azure.ph5` sorts above the
stock `3.ph5` and below a future official `4.ph5` — a later official build still
upgrades it. Without a distinguishable NEVR, rpm considers the Hyper-V kernel
identical to the stock one.

---

[← sharukhan overview](../../README.md)
