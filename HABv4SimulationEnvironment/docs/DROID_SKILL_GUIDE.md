# Using the Droid Skill for HABv4 Development

This project includes a **Factory Droid skill** that enables AI-assisted development, troubleshooting, and ISO creation. This guide explains how developers can leverage the skill to accelerate their work.

## What is a Droid Skill?

A Droid skill is a specialized knowledge module that helps Factory's AI assistant (Droid) understand domain-specific concepts, code patterns, and workflows. When you work with Droid in this repository, it automatically loads the skill and gains expert knowledge about:

- UEFI Secure Boot architecture
- Photon OS boot process
- MOK (Machine Owner Key) management
- ISO creation and modification
- RPM package building and signing
- Troubleshooting boot issues

## Getting Started

### Prerequisites

1. Install Factory CLI or use Factory in your IDE
2. Clone this repository
3. Navigate to the `HABv4SimulationEnvironment` directory

### Activating the Skill

The skill is automatically loaded when you work in this repository. Simply start a conversation with Droid:

```bash
# Start Droid in the project directory
cd photonos-scripts/HABv4SimulationEnvironment
droid
```

Or use Factory in your IDE (VS Code, JetBrains, etc.).

## Common Developer Tasks

### 1. Building the Tool

Ask Droid to help you build the ISO creator:

```
User: Build the PhotonOS-HABv4Emulation-ISOCreator tool

Droid: I'll compile the tool for you...
[Droid runs: cd src && make]
```

### 2. Creating a Secure Boot ISO

```
User: Create a Secure Boot ISO for Photon OS 5.0

Droid: I'll build the ISO. This will:
1. Download Photon OS 5.0 ISO if not present
2. Generate MOK signing keys
3. Build MOK-signed RPM packages
4. Create the Secure Boot ISO
[Droid runs: ./PhotonOS-HABv4Emulation-ISOCreator -b]
```

### 3. Diagnosing Boot Issues

```
User: My ISO won't boot with Secure Boot enabled. Can you diagnose it?

Droid: I'll analyze the ISO structure and signatures...
[Droid runs: ./PhotonOS-HABv4Emulation-ISOCreator -D /path/to/iso]
[Provides detailed analysis of what's wrong and how to fix it]
```

### 4. Understanding the Code

```
User: How does the RPM Secure Boot Patcher work?

Droid: The RPM Secure Boot Patcher (in rpm_secureboot_patcher.c) works by:
1. Discovering boot packages by file paths (version-agnostic)
2. Generating MOK-signed variant SPEC files
3. Building RPMs with proper Provides/Conflicts
...
[Explains the architecture with code references]
```

### 5. Modifying the Boot Chain

```
User: I want to add a new menu option to the GRUB configuration

Droid: I'll help you modify the grub.cfg generation. 
The menu is created in build_grub_config() around line 2450...
[Shows relevant code and suggests changes]
```

### 6. Adding New Features

```
User: Can you add support for signing with a hardware security module (HSM)?

Droid: I'll analyze the current signing code and propose HSM integration:
1. Current signing uses sbsign with file-based keys
2. We could add PKCS#11 support for HSM signing
3. Here's the implementation plan...
[Creates detailed implementation plan]
```

## Skill Capabilities

### What Droid Knows About This Project

| Topic | Knowledge Level |
|-------|-----------------|
| UEFI Secure Boot chain | Expert |
| Photon OS installer | Expert |
| MOK enrollment process | Expert |
| GRUB2 module system | Expert |
| RPM spec file creation | Expert |
| ISO creation (xorriso) | Expert |
| EFI binary signing (sbsign) | Expert |
| GPG/RPM signing | Expert |
| Kernel module signing | Expert |
| Troubleshooting boot issues | Expert |

### Example Questions Droid Can Answer

**Architecture:**
- "How does shim verify the GRUB signature?"
- "What's the difference between db and MokList?"
- "Why do we need a custom GRUB stub without shim_lock?"

**Implementation:**
- "How do I add a new kernel parameter to the boot menu?"
- "How does the kickstart-based installation work?"
- "Where is the efiboot.img created?"

**Troubleshooting:**
- "Why am I getting 'Policy Violation' errors?"
- "The installer doesn't detect my disk, what's wrong?"
- "MOK enrollment doesn't persist after reboot"

**Compliance:**
- "What's the difference between Secure Boot signing and RPM signing?"
- "How do I meet NIST 800-53 requirements?"
- "What regulations require package signing?"

## Advanced Usage

### 1. Kernel Build Support

The tool automatically builds kernels from Photon OS sources with Secure Boot configuration:

```
User: Build a Secure Boot ISO (which includes custom kernel)

Droid: I'll build the ISO. This now automatically:
1. Finds kernel source in /root/5.0/stage/SOURCES/ or common directories
2. Applies Photon OS config (config-esx_x86_64) + edge requirements
3. Enables CONFIG_MODULE_SIG, CONFIG_LOCK_DOWN, CONFIG_USB=y (built-in)
4. Builds and signs the kernel with MOK
5. Injects custom kernel/modules into linux-mok RPM (v1.9.1+)
[Explains the build process and runs it]
```

### 2. eFuse USB Security

For hardware security simulation:

```
User: Create an ISO that requires an eFuse USB dongle to boot

Droid: I'll build with eFuse verification:
1. Generate eFuse simulation data
2. Build ISO with -E flag (requires eFuse USB)
3. Create the USB dongle
[Runs: ./PhotonOS-HABv4Emulation-ISOCreator -b -E -u /dev/sdX]
```

### 3. Driver Integration (WiFi, etc.)

For systems requiring additional hardware support:

```
User: Create an ISO with Intel WiFi 6E AX211 support

Droid: I'll build with driver integration:
1. Include wireless-regdb for regulatory database
2. Include iw for wireless configuration utility
3. Include linux-firmware-iwlwifi-ax211 for Intel WiFi firmware
4. Enable required kernel configs (WIRELESS, WLAN, CFG80211, MAC80211, crypto)
5. GPG sign all driver RPMs if --rpm-signing enabled
[Runs: ./PhotonOS-HABv4Emulation-ISOCreator -b --drivers --rpm-signing]
```

**Available driver packages in `drivers/RPM/`:**
- `wireless-regdb-2024.01.23-1.ph5.noarch.rpm` - WiFi regulatory database
- `iw-6.9-1.ph5.x86_64.rpm` - nl80211 wireless config utility  
- `linux-firmware-iwlwifi-ax211-20260128-1.noarch.rpm` - Intel WiFi 6E firmware

**Rebuilding driver packages:**
```bash
./drivers/build-wireless-packages.sh
```

### 4. Compliance Builds

For regulated environments:

```
User: Create a FedRAMP-compliant ISO with RPM signing

Droid: For FedRAMP compliance, I'll enable:
1. RPM signing (NIST 800-53 SI-7, CM-14)
2. GPG key generation with 4096-bit RSA
3. Package signature verification in kickstart
[Runs: ./PhotonOS-HABv4Emulation-ISOCreator -b -R]
```

## Contributing with Droid

### Adding New Features

1. Describe what you want to implement
2. Droid analyzes existing code and conventions
3. Droid proposes an implementation plan
4. Review and approve the plan
5. Droid implements the feature
6. Droid runs tests and verifies the build

### Fixing Bugs

1. Describe the bug or error message
2. Droid analyzes the code path
3. Droid identifies root cause
4. Droid proposes and implements fix
5. Droid verifies the fix works

### Code Review

```
User: Review my changes to the RPM patcher

Droid: I'll analyze your changes...
[Reviews code for:
- Coding style consistency
- Security implications
- Error handling
- Edge cases
- Documentation]
```

## Skill File Location

The skill definition is at:
```
.factory/skills/photonos-secureboot-iso/SKILL.md
```

This file contains the complete knowledge base that Droid uses when working with this project.

## Updating the Skill

If you add new features or fix bugs, consider updating the skill documentation:

```
User: Update the skill documentation to include the new kernel build feature

Droid: I'll update SKILL.md with:
1. New command line options
2. Directory structure for kernel sources
3. Build process explanation
4. Troubleshooting for kernel builds
```

## Architecture Decision Records

### ADR-001: MOK Package Integration Approaches

When integrating Custom MOK packages alongside VMware Original packages, several implementation options were evaluated:

#### Option A: GRUB Menu Selection + Separate Package Files
Two GRUB entries passing different kernel parameters to select package configs.
- **Pros**: Clear separation at boot menu, no installer UI changes
- **Cons**: Requires installer patch for parameter handling, two menu entries

#### Option B: Modify packages_minimal.json Only
Replace packages_minimal.json with MOK packages directly.
- **Pros**: Simplest implementation, minimal patches
- **Cons**: No VMware Original option, user doesn't see explicit MOK choice

#### Option C: Add New Entry to build_install_options_all.json (SELECTED)
Add "Photon MOK Secure Boot" as new package selection in installer UI.
- **Pros**: Explicit MOK choice, preserves original options, follows installer patterns
- **Cons**: More complex initrd modification, requires linuxselector.py patch

#### Option D: Dual ISO Approach
Generate two separate ISOs for MOK and VMware Original.
- **Pros**: Complete separation, simple per-ISO
- **Cons**: Two ISOs to manage, doubles storage

#### Option E: GRUB Chainload Approach
GRUB menu chainloads different configs or installers.
- **Pros**: VMware Original path completely unmodified
- **Cons**: Complex GRUB config, Secure Boot signature issues

#### Option F: Installer UI Patch - New Screen
Add new screen before package selection for boot configuration choice.
- **Pros**: Clean UX, explicit choice with descriptions
- **Cons**: Most invasive modification, breaks with installer updates

#### Option G: Environment-Based Auto-Detection
Auto-detect VMware vs physical and select packages accordingly.
- **Pros**: Zero user decision, automatic correct selection
- **Cons**: No override option, may misdetect environments

#### Option H: Kernel Parameter + Installer Patch
Pass kernel parameter from GRUB, installer reads cmdline to select packages.
- **Pros**: Clean separation, GRUB controls choice
- **Cons**: Requires cmdline parsing patch

#### Decision Matrix

| Option | Complexity | User Clarity | Maintainability | Flexibility |
|--------|------------|--------------|-----------------|-------------|
| A | Medium | High | Medium | High |
| B | Low | Low | High | Low |
| C | Medium | High | Medium | High |
| D | Low | High | Low | Medium |
| E | High | High | Low | Medium |
| F | High | High | Low | High |
| G | Medium | Low | High | Low |
| H | Medium | High | Medium | High |

**Selected**: Option C - Best balance of user clarity, maintainability, and flexibility.

---

## Troubleshooting Droid Issues

### Skill Not Loading

If Droid doesn't seem to know about Secure Boot:
1. Verify you're in the `HABv4SimulationEnvironment` directory
2. Check that `.factory/skills/photonos-secureboot-iso/SKILL.md` exists
3. Restart your Droid session

### Droid Gives Incorrect Information

The skill may need updates if:
- New Photon OS versions have different behavior
- Upstream changes to photon-os-installer
- New UEFI/shim requirements

Update the skill file with correct information and submit a PR.

## Best Practices

1. **Be specific**: "Build ISO for 5.0 with RPM signing" is better than "build it"
2. **Provide context**: If you have an error, share the full error message
3. **Verify results**: Always test the generated ISOs on actual hardware
4. **Update documentation**: If you discover something new, ask Droid to update the docs
