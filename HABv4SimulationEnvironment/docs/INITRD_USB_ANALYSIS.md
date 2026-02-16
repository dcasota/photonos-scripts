# Initrd USB Driver Analysis for v1.9.33

## Question: Are USB drivers included in initrd phase?

**Short Answer**: YES, but with important nuances about which kernel is used when.

---

## The Two-Phase Boot Architecture

### Phase 1: ISO Boot (Installer)

**Kernel**: Standard Photon kernel **6.12.60-14.ph5** (VMware original)  
**Initrd**: `/isolinux/initrd.img` (192 MB)  
**USB Drivers**: ✅ **Modules** (loaded from initrd)

```
Boot Flow:
UEFI/BIOS → GRUB → vmlinuz (6.12.60-14.ph5) → initrd.img → systemd → installer
```

**USB Host Controllers in Initrd** (as modules):
```
lib/modules/6.12.60-14.ph5/kernel/drivers/usb/host/xhci-hcd.ko.xz  ← USB 3.0
lib/modules/6.12.60-14.ph5/kernel/drivers/usb/host/ehci-hcd.ko.xz  ← USB 2.0
lib/modules/6.12.60-14.ph5/kernel/drivers/usb/host/ohci-hcd.ko.xz  ← USB 1.1
lib/modules/6.12.60-14.ph5/kernel/drivers/usb/host/uhci-hcd.ko.xz  ← USB 1.1
lib/modules/6.12.60-14.ph5/kernel/drivers/usb/core/usbcore.ko.xz   ← Core
lib/modules/6.12.60-14.ph5/kernel/drivers/usb/storage/usb-storage.ko.xz ← Storage
```

**Status**: ✅ USB works during installation phase using standard kernel's modules

---

### Phase 2: Installed System Boot (Post-Installation)

**Kernel**: Custom built kernel **6.1.159-esx** (from linux-mok RPM)  
**Initrd**: Generated during installation by dracut  
**USB Drivers**: ✅ **Built-in** (compiled into kernel image)

```
Boot Flow:
UEFI → Shim → GRUB (MOK-signed) → vmlinuz-6.1.159-esx (MOK-signed) → Custom initrd
```

**USB Configuration in Custom Kernel** (v1.9.0+):
```bash
CONFIG_USB=y                  ← USB subsystem built-in
CONFIG_USB_XHCI_HCD=y        ← USB 3.0 host controller built-in
CONFIG_USB_EHCI_HCD=y        ← USB 2.0 host controller built-in  
CONFIG_USB_STORAGE=y         ← USB storage built-in
```

**Why Built-in?**  
From v1.9.0 changelog:
> "ESX kernel USB boot was failing due to modules not loading. Installation-time dracut dependencies were problematic. USB drivers must be built-in for reliable USB boot."

**Status**: ✅ USB works on installed system without needing modules

---

## Detailed Analysis

### ISO Boot (Installer Phase)

**Kernel File**: `/isolinux/vmlinuz`
```
$ file /tmp/mnt_iso/isolinux/vmlinuz
Linux kernel x86 boot executable bzImage, version 6.12.60-14.ph5 (root@photon)
```

**Initrd Modules Directory**:
```
$ ls lib/modules/
6.12.60-14.ph5/  ← Only standard kernel modules
```

**USB Modules Present**:
- ✅ USB core: `usbcore.ko.xz`
- ✅ USB storage: `usb-storage.ko.xz`
- ✅ USB 3.0 (xHCI): `xhci-hcd.ko.xz`, `xhci-pci.ko.xz`
- ✅ USB 2.0 (EHCI): `ehci-hcd.ko.xz`, `ehci-pci.ko.xz`
- ✅ USB 1.1 (OHCI): `ohci-hcd.ko.xz`, `ohci-pci.ko.xz`
- ✅ USB 1.1 (UHCI): `uhci-hcd.ko.xz`
- ✅ USB HID: `usbhid.ko.xz`, `hid.ko.xz`
- ✅ USB networking: `usbnet.ko.xz`

**Key Point**: During installation, the ISO uses the **standard Photon kernel** with USB as **modules**. This works fine because:
1. Initrd is built by VMware with all necessary drivers
2. systemd-udevd loads USB modules automatically
3. Installation doesn't need MOK-signed kernel (Secure Boot not enforced during install)

---

### Installed System (Post-Installation)

**Kernel File**: `/boot/vmlinuz-6.1.159-esx` (from linux-mok RPM)
```
$ file /root/hab_keys/vmlinuz-mok
Linux kernel x86 boot executable bzImage, version 6.1.159-esx #1 SMP Mon Feb 2 2026
```

**Kernel Config** (custom build):
```bash
$ grep CONFIG_USB /root/5.0/kernel-build/linux-6.1.159/.config
CONFIG_USB=y                     # USB subsystem: built-in
CONFIG_USB_XHCI_HCD=y           # USB 3.0: built-in
CONFIG_USB_EHCI_HCD=y           # USB 2.0: built-in
CONFIG_USB_STORAGE=y            # USB storage: built-in
CONFIG_USB_ANNOUNCE_NEW_DEVICES=y
...
# These are MODULES (not built-in):
CONFIG_USB_OHCI_HCD=m           # USB 1.1 OHCI: module
CONFIG_USB_UHCI_HCD=m           # USB 1.1 UHCI: module
```

**Critical USB Drivers**:
- ✅ `CONFIG_USB=y` - Core USB support built into kernel
- ✅ `CONFIG_USB_XHCI_HCD=y` - USB 3.0 controller built-in
- ✅ `CONFIG_USB_EHCI_HCD=y` - USB 2.0 controller built-in
- ✅ `CONFIG_USB_STORAGE=y` - USB mass storage built-in

**Why This Matters**:
1. USB 3.0 and 2.0 controllers work **immediately** at kernel boot
2. No dependency on initrd modules or dracut
3. USB boot devices are accessible before rootfs mount
4. Critical for eFuse USB dongle detection in GRUB/kernel

---

## Historical Context (v1.9.0 Changes)

### Before v1.9.0
**Problem**: ESX kernel USB boot failures
- USB drivers were modules in ESX kernel
- Modules needed to be loaded by dracut
- Module loading failed in some scenarios
- Result: "Black screen hang" during USB boot

### After v1.9.0 (Current)
**Solution**: USB drivers built-in
```c
// Added to kernel config patching:
CONFIG_USB=y
CONFIG_USB_STORAGE=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_EHCI_HCD=y
```

**Benefits**:
1. ✅ USB works before initrd is even accessed
2. ✅ No dracut dependency for USB
3. ✅ Reliable USB boot on all systems
4. ✅ eFuse USB detection in GRUB works

---

## Answer to the Question

### During ISO Boot (Installer)

**YES**, USB drivers are included in initrd as **modules**:
- Standard Photon kernel 6.12.60-14.ph5
- USB modules in `/lib/modules/6.12.60-14.ph5/kernel/drivers/usb/`
- systemd-udevd loads them automatically
- ✅ USB keyboard, USB install media, USB storage all work

### During Installed System Boot

**USB drivers are BUILT-IN to the kernel** (not in initrd):
- Custom kernel 6.1.159-esx has `CONFIG_USB*=y`
- USB works immediately when kernel starts
- No dependency on initrd modules
- ✅ USB works even if initrd fails to load

---

## Implications for Photon MOK Secure Boot Installation

### Phase 1: Booting the ISO
1. ✅ GRUB (VMware original, not yet MOK) loads
2. ✅ Standard kernel 6.12.60-14.ph5 boots
3. ✅ Initrd with USB modules loads
4. ✅ USB keyboard/mouse work
5. ✅ Installer runs

### Phase 2: Package Installation
- Installer installs linux-mok RPM
- linux-mok contains custom kernel with USB built-in
- Post-install scripts generate new initrd (for installed system)

### Phase 3: First Boot After Installation
1. ✅ GRUB (MOK-signed) loads
2. ✅ Custom kernel 6.1.159-esx (MOK-signed) boots
3. ✅ USB drivers built-in, work immediately
4. ✅ Initrd loads (may or may not have USB modules, doesn't matter)
5. ✅ System boots

---

## Potential Issues

### Issue 1: Initrd Module Mismatch (Low Risk)

**Scenario**: Installer generates initrd for wrong kernel version

**Current Status in v1.9.33**:
- ISO boots with kernel 6.12.60-14.ph5
- Installed system uses kernel 6.1.159-esx
- Initrd modules are for 6.12.60-14.ph5

**Impact**: ⚠️ If installed system's initrd has 6.12.60 modules but kernel is 6.1.159:
- Modules won't load (version mismatch)
- BUT USB still works (built-in to kernel)
- Other modules (filesystems, etc.) may fail

**Mitigation**: v1.9.3 fixed this with post-install script that runs dracut with correct kernel version

### Issue 2: Dracut USB Module Generation (No Risk)

**Scenario**: Dracut tries to include USB modules in installed system's initrd

**Status**: ✅ Not a problem
- Dracut detects USB is built-in (`CONFIG_USB=y`)
- Doesn't include USB modules in initrd
- Initrd is smaller and boots faster

### Issue 3: Module Signing for Modules (Medium Risk)

**Scenario**: Some modules are still modules (not built-in) and need signing

**Current Status**:
- USB critical drivers: built-in ✅
- WiFi drivers: modules ⚠️
- Other drivers: modules ⚠️

**Mitigation**: v1.9.4 fixed module signature stripping by disabling RPM's brp-strip

---

## Summary

| Phase | Kernel | USB Driver Type | Location | Status |
|-------|--------|-----------------|----------|--------|
| ISO Boot | 6.12.60-14.ph5 | Modules | initrd | ✅ Works |
| Installation | 6.12.60-14.ph5 | Modules | initrd | ✅ Works |
| Installed System | 6.1.159-esx | Built-in | vmlinuz | ✅ Works |

**Conclusion**: 
- ✅ YES, USB drivers are available during initrd phase (as modules)
- ✅ BETTER: Installed system has USB built-in (no initrd needed)
- ✅ This architecture ensures USB works in all phases of boot/installation

The v1.9.0+ design is **superior** to module-based USB because:
1. No dependency on dracut
2. No module loading failures
3. Works even if initrd is corrupted
4. eFuse USB detection in GRUB works reliably
