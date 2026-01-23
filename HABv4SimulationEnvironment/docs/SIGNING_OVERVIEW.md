# Secure Boot Signing vs RPM Signing: A Comprehensive Guide

## Overview

This document explains the fundamental differences between **UEFI Secure Boot signing** and **RPM package signing**, their purposes, and when each is required. These are two completely separate security mechanisms that serve different purposes in the software supply chain.

## Quick Comparison

| Aspect | Secure Boot Signing | RPM Signing |
|--------|---------------------|-------------|
| **Purpose** | Verify boot chain integrity | Verify package authenticity |
| **Key Type** | X.509 certificates (DER/PEM) | GPG/PGP keys |
| **What's Signed** | EFI binaries (bootx64.efi, grubx64.efi, vmlinuz) | RPM package files |
| **Verified By** | UEFI firmware, shim, GRUB | rpm, tdnf, dnf, yum |
| **When Verified** | Boot time (before OS loads) | Package install/update time |
| **Key Storage** | UEFI db/dbx, MokList (NVRAM) | RPM keyring, filesystem |
| **Standard** | UEFI 2.x, Microsoft UEFI CA | RPM 4.x, OpenPGP (RFC 4880) |

## Secure Boot Signing (EFI Binary Signing)

### What It Does

Secure Boot signing ensures that only trusted code executes during the boot process, from firmware to kernel. It creates a **chain of trust**:

```
UEFI Firmware (Platform Key)
    ↓ verifies
Microsoft UEFI CA (in db)
    ↓ verifies  
shim (bootx64.efi) - Microsoft-signed
    ↓ verifies (using MokList)
GRUB (grubx64.efi) - MOK-signed
    ↓ verifies (optional, via shim_lock)
Linux Kernel (vmlinuz) - MOK-signed
```

### Key Components

1. **Platform Key (PK)**: OEM-controlled, rarely changed
2. **Key Exchange Keys (KEK)**: Authorizes db/dbx updates
3. **Signature Database (db)**: Contains trusted certificates (e.g., Microsoft UEFI CA)
4. **Forbidden Database (dbx)**: Revoked signatures
5. **Machine Owner Key (MOK)**: User-controlled keys enrolled via MokManager

### Signing Process

```bash
# Sign an EFI binary with MOK key
sbsign --key MOK.key --cert MOK.crt --output signed.efi unsigned.efi

# Verify signature
sbverify --cert MOK.crt signed.efi
```

### When It's Verified

- **At every boot**, before the OS loads
- Cannot be bypassed without physical access or disabling Secure Boot
- Firmware refuses to execute unsigned/untrusted binaries

## RPM Package Signing (GPG Signing)

### What It Does

RPM signing ensures that software packages:
1. Come from a trusted source (authenticity)
2. Haven't been modified since signing (integrity)
3. Can be traced to a specific publisher (non-repudiation)

### Key Components

1. **GPG Private Key**: Used to sign packages (kept secret)
2. **GPG Public Key**: Distributed to verify signatures
3. **RPM Keyring**: System database of trusted public keys

### Signing Process

```bash
# Generate GPG key pair
gpg --batch --gen-key <<EOF
Key-Type: RSA
Key-Length: 4096
Name-Real: My Signing Key
Name-Email: signing@example.com
Expire-Date: 0
%no-protection
EOF

# Sign an RPM package
rpmsign --addsign --key-id="My Signing Key" package.rpm

# Verify signature
rpm --checksig package.rpm
rpm -K package.rpm
```

### When It's Verified

- **At package installation time** (rpm -i, tdnf install, dnf install)
- Can be bypassed with `--nosignature` flag
- Repository configuration can require/skip signature checks

## Why Both Are Needed

### Scenario: Without Secure Boot Signing
```
Attacker replaces vmlinuz on disk
    ↓
System boots with malicious kernel
    ↓
Rootkit installed before OS loads
    ↓
RPM signatures are useless (kernel is compromised)
```

### Scenario: Without RPM Signing
```
Attacker compromises package repository/mirror
    ↓
User installs malicious package
    ↓
System compromised after boot
    ↓
Secure Boot passed, but malware now running
```

### Complete Protection Requires Both

| Attack Vector | Secure Boot | RPM Signing | Both |
|--------------|-------------|-------------|------|
| Boot chain tampering | ✓ Protected | ✗ Not protected | ✓ |
| Package repository compromise | ✗ Not protected | ✓ Protected | ✓ |
| Man-in-the-middle on updates | ✗ Not protected | ✓ Protected | ✓ |
| Physical boot media swap | ✓ Protected | ✗ Not protected | ✓ |
| Offline disk modification | ✓ Protected (boot) | ✓ Protected (install) | ✓ |

---

# Regulatory Compliance Requirements

## United States

### NIST SP 800-53 (Rev 5.2.0, August 2025)

NIST Special Publication 800-53 provides security controls for federal information systems. Relevant controls include:

**SI-7: Software, Firmware, and Information Integrity**
- Requires integrity verification mechanisms
- Mandates cryptographic verification for software updates
- Applies to both boot-time and runtime integrity

**SA-12: Supply Chain Risk Management**
- Requires protection against supply chain threats
- Software signing is a key control for supply chain integrity

**CM-14: Signed Components**
- Explicitly requires cryptographic signatures on software components
- Verification of signatures before installation

> *"Organizations employ cryptographic mechanisms to verify the integrity of software, firmware, and information. Verification of software integrity includes verifying digital signatures."* — NIST SP 800-53 SI-7

**Applicability to RPM Signing:**
- Federal agencies and contractors must implement package signing
- Both source (SRPM) and binary (RPM) packages should be signed
- Key management must follow NIST guidelines

### FedRAMP (Federal Risk and Authorization Management Program)

FedRAMP mandates NIST 800-53 controls for cloud services. Additional requirements:

**FedRAMP Policy for Cryptographic Module Selection (January 2025)**
- Cryptographic modules must be FIPS 140-validated
- Software updates must maintain integrity through cryptographic verification
- Package signing keys should be protected in validated modules

**Practical Requirements:**
- GPG keys used for RPM signing should be stored in HSMs where possible
- Signing must use FIPS-approved algorithms (RSA-2048+, SHA-256+)
- Public keys must be distributed through secure channels

### FIPS 140-3

While FIPS 140-3 primarily covers cryptographic modules, it impacts signing:

**Software Integrity (Section 5)**
- Cryptographic modules must verify software integrity
- Code signing is implied for module firmware updates

**Algorithm Requirements:**
- RSA: 2048-bit minimum (3072-bit recommended)
- SHA-256 minimum for digests
- ECDSA P-256 or higher

### CISA Secure Software Development Framework

CISA recommends:
- Code signing for all distributed software
- Verification of signatures during installation
- Secure key management practices

## European Union

### EU Cyber Resilience Act (CRA) - Effective December 2024

The CRA introduces mandatory cybersecurity requirements for products with digital elements:

**Article 10: Security Requirements**
- Products must be designed with security by default
- Software integrity must be verifiable
- Updates must be authenticated and integrity-protected

**Annex I: Essential Cybersecurity Requirements**
- *"Products with digital elements shall be delivered with a secure by default configuration, including the possibility to reset the product to its original state."*
- *"Products shall ensure the integrity of software and firmware."*

**Software Signing Implications:**
- Manufacturers must implement code signing
- Package signatures ensure update integrity
- SBOM (Software Bill of Materials) must be maintained

**Penalties for Non-Compliance:**
- Up to €15 million or 2.5% of global annual turnover
- Market access restrictions in EU

### NIS2 Directive (Network and Information Security)

Applies to essential and important entities:

**Article 21: Cybersecurity Risk Management**
- Supply chain security requirements
- Software integrity verification
- Incident reporting for compromised software

## International Standards

### Common Criteria (ISO/IEC 15408)

Common Criteria certification requires:

**FCS_COP.1: Cryptographic Operation**
- Cryptographic algorithms for signing must meet standards
- Key sizes must be appropriate for protection period

**FPT_TST: TSF Self Test**
- Software integrity testing at startup
- Verification of critical components

**Evaluation Assurance Levels (EAL):**
- EAL4+: Requires detailed design documentation including signing processes
- Government systems often require EAL4 or higher

### ISO 27001:2022

**A.8.24: Use of Cryptography**
- Policy for cryptographic controls
- Key management procedures

**A.8.32: Change Management**
- Integrity verification for software changes
- Signed packages support change control

### CA/Browser Forum Baseline Requirements

For publicly-trusted code signing certificates:

**Effective February 2025:**
- Maximum validity: 460 days (reduced from 39 months)
- Stricter key protection requirements
- Enhanced subscriber vetting

---

# Summary: When Is RPM Signing Required?

## Mandatory Scenarios

| Scenario | Regulation/Standard | Requirement |
|----------|---------------------|-------------|
| US Federal Systems | NIST 800-53, FedRAMP | Yes - SI-7, CM-14 |
| US Defense | DISA STIGs | Yes - Mandatory |
| EU Market (digital products) | Cyber Resilience Act | Yes - Article 10 |
| Critical Infrastructure (EU) | NIS2 Directive | Yes - Article 21 |
| Healthcare (US) | HIPAA + NIST | Recommended |
| Financial Services | PCI-DSS 4.0 | Recommended |
| Government Procurement | Common Criteria | Often Required |

## Recommended Scenarios

- Enterprise software distribution
- Multi-tenant environments
- Container image distribution
- Software supply chain security
- DevSecOps pipelines

## Optional Scenarios

- Personal/development use
- Isolated test environments
- Air-gapped systems with physical security

---

# HABv4 Implementation Recommendation

For the HABv4 Simulation Environment, implementing RPM signing provides:

1. **Complete Security Chain**: Boot integrity (Secure Boot) + Package integrity (RPM signing)
2. **Compliance Readiness**: Supports NIST, FedRAMP, CRA requirements
3. **Supply Chain Protection**: Verifiable package authenticity
4. **Educational Value**: Demonstrates full enterprise security model

The `--rpm-signing` option enables this capability while keeping it optional for simpler use cases.

---

## References

1. NIST SP 800-53 Rev 5.2.0 (August 2025) - https://csrc.nist.gov/pubs/sp/800/53/r5
2. FedRAMP Policy for Cryptographic Module Selection (January 2025)
3. EU Cyber Resilience Act - Regulation (EU) 2024/2847
4. NIS2 Directive - Directive (EU) 2022/2555
5. Common Criteria ISO/IEC 15408:2022
6. CA/Browser Forum Code Signing Baseline Requirements v3.10.0
7. FIPS 140-3 - NIST SP 800-140
8. Red Hat: RPM and GPG Package Verification Guide
