# What is Photon OS scripts?
This repo contains a bunch of Photon OS related scripts.  
Photon OS is a VMware by Broadcom operating system for open source Linux container host for cloud-native applications. It runs on x86_64 + arm64 processors and on several hyperscaler clouds. See https://vmware.github.io/photon.

# Photon OS as internal appliance development platform
A bunch of commercial VMware by Broadcom products are delivered as appliances, as ISO or OVA, using a closed-source Photon OS edition as underlying operating system. To get an idea, see some weblinks:  
  
Holorouter:                                                      https://vmware.github.io/Holodeck/#what-is-holodeck  
vCenter Server :                                                 https://knowledge.broadcom.com/external/article?legacyId=96577  
vSphere Supervisor Services and Standalone Components:           https://techdocs.broadcom.com/us/en/vmware-cis/vcf/vsphere-supervisor-services-and-standalone-components/latest/release-notes/vmware-vkr-release-notes.html  

There isn't a customer product SKU Photon Platform 2.x, 3.x or 4.x. Hence you cannot buy standalone Photon Platform support. 
Before strictly separating commercial components, there was a VMware Photon Platform 1.x. It hit End of General Support on 2019-03-02.

Commercial appliances each run a specific Photon OS subrelease, governed by strict product development and maintenance rules. Paid support today covers the entire VMware Cloud Foundation bundle.

Note that open-source Photon OS, unlike some other Linux distributions, does not offer paid support. Starting in 2024, the Photon OS maintenance team has prioritised releasing security updates.

The actual open-source Photon OS releases are 1:1 related to Linux kernel releases.  

| Linux kernel  |   Photon OS   | Lifecycle |  
| ------------- | ------------- | --------- |
|     4.4       |      1.x      |    EOL    |
|     4.9       |      2.x      |    EOL    |
|     4.19      |      3.x      |    EOL    |
|     5.10      |      4.x      |           |
|     6.1       |      5.0      |           |
|     6.12      |      (6.0)    |           |
|     6.18/7.0  |      tbd      |           | 

Security is crucial for the commercial appliances and for the open-source Photon OS. The [Security Advisories](https://github.com/vmware/photon/wiki/Security-Advisories) contain the latest cve patches which the Photon OS team populates to maintain the platform secure.

With each Linux kernel update, trillions of packages permutations are given, in theory it's slightly less architecture specific. A slice of it reflects in open-source Photon OS. You can see which packages are made available from contributors at https://github.com/vmware/photon/commits/dev.

# Building open-source Photon OS
The build process for the open-source version of Photon OS is detailed in the [documentation](https://vmware.github.io/photon). The Photon OS team has created a collection of tools and scripts to simplify tasks like maintaining Linux kernel releases, open-source vendor package updates, and patch backports. While these tools are actively being developed, not every workflow is thoroughly documented. Some beginner instructions can be found at https://github.com/dcasota/photonos-scripts/wiki/How-to-build-the-Photon-OS-ISO-file.
  
Building open-source Photon OS happens in three stages:  
- Step 1 : Building the core toolchain package  
- Step 2 : Building stage 2 of the toolchain (two sub-steps)  
- Step 3 : Building all package(s) and dependencies as specified  
  
In Step 1, the core toolchain packages built is about 14 packages:  
['filesystem', 'linux-api-headers', 'glibc', 'zlib', 'file', 'binutils', 'gmp', 'mpfr', 'mpc', 'gcc', 'pkg-config', 'ncurses', 'readline', 'bash'].  
Additional ~112 packages are processed in Step 2. In Step 3, the majority of packages is processed. Those number may vary with the release. Photon OS 6.0 includes more than 1020 packages. Each package is represented by a spec file which contains Photon OS information to build the vendor package as rpm.

The Photon OS team focuses on keeping the essential packages up to date. Most packages belong to those of Step 1 and Step 2.

Productizing the Photon Platform was a strategy until 2017, see the Product lifecycle matrix (search for "VMware Photon Platform"):  https://support.broadcom.com/group/ecx/productlifecycle  
However, cve operations became somewhat difficult and time consuming. For humans it takes time to clearly understand every single mitigation. This wasn't feasible at that time for customers.

See some personal scramblings:
- https://github.com/dcasota/photonos-scripts/wiki/Mitigations-for-CPU-vulnerabilities
- https://github.com/dcasota/photonos-scripts/wiki/NTFS-mount-on-Photon-OS
- https://github.com/dcasota/photonos-scripts/wiki/VMFS6-mount-on-Photon-OS

# Photon OS package Report
The Photon OS package report tool is a powershellcore-compatible script https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/photonos-package-report.ps1 which analyzes each open-source vendor package and checks if there is a newer version available. For each package it locally clones the source, downloads the latest release, creates a newer spec file. It also creates various raw reports stored in https://github.com/dcasota/photonos-scripts/tree/master/photonos-package-report/scans.
  
  
Latest run: March 2, 2026
url health
- [Photon OS 4.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-urlhealth-4.0_202603021624.prn)
- [Photon OS 5.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-urlhealth-5.0_202603021904.prn)
- [Photon OS 6.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-urlhealth-6.0_202603022032.prn)
- [Photon OS common](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-urlhealth-common_202603022130.prn)
- [Photon OS dev](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-urlhealth-dev_202603022130.prn)
- [Photon OS master](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-urlhealth-master_202603022232.prn)

difference report
- [4.0 <> 5.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-diff-report-4.0-5.0_202603030204.prn)
- [5.0 <> 6.0](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-diff-report-5.0-6.0_202603030204.prn)
- [common <>master](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-diff-report-common-master_202603030204.prn)

package report with all packages per Photon OS release version
[Download](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report/scans/photonos-package-report_202603030204.prn)
  
  
The powershellcore script contains a base of download urls for each package. In examines the original download url Source0 inside the spec file. The comma delimited .prn report files contains spec file name, the Source0 original value, the corrected Source0 url after research, the url health check value (200=ok), an "UpdateAvailable" signalisation and much more. For analysis purposes, the reports can be stored e.g. inside a database.

Photon OS package report is a base for further testings. Package work typically starts with 'there is a version of package x in relation to y, which is not or it is integrated to photon release z only.' With the latest tdnf package manager improvements, build system managers can monitor which packages are used during the build process only, which requirements are needed, and by using package report too process first smoke tests with newer releases. This is a step towards handy interoperability lookups of packages release/flavor/architecture like the inter-product viewer in VMware vSphere interoperability guide.

# Baremetal installation / staging
Photon OS runs best on vSphere x86_64. It runs kubernetes, docker containers, supports a resource foot print hardened setup, and has a package-based lifecycle management system. A secure appliance (e.g. virtual hardware v13) installation is built-in VMware hypervisor optimized, and delivered as OVA setup.

Baremetal environments are technically supported. The focus of Photon OS however isn't to run on baremetal. For security purposes, peripheral devices connectivity is restricted. But you can install Photon OS on any x86_64 and arm64 baremetal.

On x86_64, Photon OS comes with different installation flavors: "Security hardened" (minimal), Developer, Real Time, and as Ostree-Host. Since 5.0, there is more support for running Photon OS on ESXi on Arm.
Provisioning Photon OS on Raspberry Pi is supported as well, e.g. see [Configuring a Raspberry Pi 4 for supporting usb license dongle remoting](https://github.com/dcasota/photonos-scripts/wiki/Configure-a-complete-Raspberry-Pi-Virtualhere-installation).

# Azure installation with UEFI boot support
In a Non-vSphere hyperscaler environment - this chapter is Microsoft Azure specific - the following scripts may be helpful when creating a Photon OS virtual machine with UEFI support.
- https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/create-AzImage-PhotonOS.ps1
- https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/create-AzVM_FromImage-PhotonOS.ps1  
```create-AzImage-PhotonOS.ps1``` creates an Azure Generation V2 image, per default of VMware Photon OS 4.0.  
```create-AzVM_FromImage-PhotonOS.ps1``` provisions on Azure a Photon OS VM with the Azure image created using ```create-AzImage-PhotonOS.ps1```.

# PowerCLI on Photon OS
"VMware PowerCLI is a suite of PowerShell modules to manage VMware products and services. VMware PowerCLI includes over 800 cmdlets to easily manage your infrastructure on a global scale." See the weblink https://developer.broadcom.com/powercli.
Actually there is no single package for PowerCLI. Powershell must always have already been installed.
There are three different installation options - container-based, photon os built-in and scripted install.

## package installation (tdnf)
You can install the powershell package right before PowerCLI. Photon OS 3.0 and above supports Powershell since release 6.2.

To install or update Powershell Core enter
- ```tdnf install powershell``` or ```tdnf update powershell```

Install or update PowerCLI in a powershell command enter
- ```install-module -name VMware.PowerCLI``` or ```update-module -name VMware.PowerCLI```

## docker installation
VMware PowerCLI is available as docker container. Run
- ```docker pull vmware/powerclicore:latest```
- ```docker run -it vmware/powerclicore:latest```

## scripted install 
In some scenarios it is helpful to have a specific Powershell release. Some PowerCLI cmdlets on Windows do not work yet on Photon OS. Simple as that, many Microsoft Windows-specific lowlevel functions were not or are not cross-compatible.  
In [PwshOnPhotonOS](https://github.com/dcasota/photonos-scripts/tree/master/PwshOnPhotonOS) you find install scripts for Powershell on Photon OS with focus on fulfilling prerequisites for VMware.PowerCLI. Each script ```Pwsh[Release]OnPhotonOS.sh``` deploys the specific Powershell Core release on Photon OS.

Example: Install the Powershell release 7.1.3 using ```Pwsh7.1.3OnPhotonOS.ps1```. Simply enter afterwards ```pwsh7.1.3```.

![Powershell_on_Photon](https://github.com/dcasota/photonos-scripts/blob/master/PwshOnPhotonOS/Photon2-pwsh-current.png)

Afterwards you easily can install VMware.PowerCLI with ```install-module VMware.PowerCLI```.

### PowerCLI runspace per release - workflow based side-by-side installation testing
Side-by-side-installations in nowadays work fine. This wasn't always the case, see Powershell 6.x warnings.
  
![side-side-installation](https://github.com/dcasota/photonos-scripts/blob/master/PwshOnPhotonOS/side-side-installation.png).

The idea of developing a testing workflow for side-by-side installation combinations using [VMware Tanzu Community Edition](https://tanzucommunityedition.io/) came up as some sort of basics for 'PowerCLI runspace per release'.  
![Status Oct21](https://github.com/dcasota/photonos-scripts/blob/master/PwshOnPhotonOS/Status_Oct21.png)

# Learning from Kube Academy
[Kube Academy](https://kube.academy) contains a huge bunch of Kubernetes learning videos. The 'setting up the workstation' has been adopted to run the labs on Photon OS, see
- https://github.com/dcasota/photonos-scripts/wiki/Kube-Academy---setting-up-the-workstation
- https://github.com/dcasota/photonos-scripts/wiki/Kube-Academy-Scripts

# Docker containers
Docker in most Linux distros has built-in support. Photon OS' architecture strength is the maintenance of all flavors from security-hardened to hardware-optimized. This combination is highly preferred for some container purposes.
See some personal docker container learning progress with [Potree - a WebGL based viewer for large point clouds](https://github.com/dcasota/photonos-scripts/wiki/Configure-Potree,-a-WebGL-based-viewer-for-large-point-clouds,-on-VMware-Photon-OS).


# Automated Kernel Patch Backporting and CVE Coverage Tracking
As security is paramount for Photon OS, keeping kernel patches up-to-date and tracking CVE coverage is critical. The [kernelpatches](kernelpatches/) solution provides automated kernel patch backporting and comprehensive CVE coverage tracking for Photon OS.

## Goal and Key Features

The **kernelpatches** tool automates the complex process of maintaining kernel security patches across different Photon OS versions. Its primary goal is to:

1. **Track CVE Coverage** - Monitor which CVEs affect each kernel version (5.10, 6.1, 6.12) and their current patch status
2. **Automate Patch Backporting** - Download and integrate CVE patches and stable kernel updates into Photon OS spec files
3. **Detect Security Gaps** - Identify CVEs that lack stable backports and require manual attention
4. **Build Patched Kernels** - Generate RPM packages with integrated security patches
5. **Enable Continuous Monitoring** - Support scheduled automation via cron for ongoing security maintenance

## What It Does

The kernelpatches solution analyzes ~7,500 kernel CVEs from NVD (National Vulnerability Database) and tracks each CVE through five states:
- ✅ **Included** - Fix is already in Photon's current kernel version
- ⬆️ **In Newer Stable** - Fix exists in a newer stable patch (upgrade available)
- 🔄 **Patch Available** - Patch exists in spec file but not in stable releases
- ❌ **Missing** - CVE affects kernel but no patch exists (security gap)
- ➖ **Not Applicable** - CVE doesn't affect this kernel version

## Quick Start Example

```bash
# Install the tool
cd kernelpatches
pip install -e .

# Check kernel status and CVE coverage
photon-kernel-backport status --kernel 6.1
photon-kernel-backport matrix --kernel 6.1

# Identify security gaps
photon-kernel-backport gaps --kernel 6.1

# Apply patches (CVE and stable updates)
photon-kernel-backport backport --kernel 6.1 --source all

# Build patched kernel RPMs
photon-kernel-backport build --kernel 6.1

# Automate with cron (daily at 4 AM)
photon-kernel-backport install --cron "0 4 * * *" --kernels 6.1,6.12
```

## Why It Matters

For Photon OS as a security-focused platform, this tool addresses several critical needs:
- **Proactive Security** - Automatically tracks and applies security patches before they become exploits
- **Compliance** - Maintains audit trails of CVE coverage and patch status
- **Reduced Manual Effort** - Automates tedious patch integration and spec file updates
- **Gap Visibility** - Quickly identifies CVEs that need manual intervention
- **Version Management** - Handles multiple kernel versions (4.x/5.10, 5.x/6.1, 6.x/6.12) simultaneously

For detailed documentation, architecture, API reference, and complete command options, see the [kernelpatches README](kernelpatches/README.md).

# Archive

This section contains deprecated scripts and hints. DO NOT USE

```pwshgalleryonphotonos.sh```
This study script makes Microsoft Powershell Core available on Photon OS by using Mono with Nuget.

It uses a tool from the Microsoft open source Nuget ecosystem.
See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org

Keep in mind, that only a small set of modules on powershellgallery work on Linux. On MS Windows, Powershell provides a module NetSecurity which isn't made available on Linux, even not with Powershell 7. Hence, cmdlets like ```Test-Netconnection``` are missing.

The tool called nuget.exe is Windowsx86-commandline-only and is used to support more lowlevel compatibility. See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
"The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides ALL NUGET CAPABILITIES;"
"it can also be run on Mac OSX and Linux using Mono with some limitations."

The script downloads all necessary prerequisites (tools, Mono, Nuget.exe) and builds the Mono software. It installs
- Photon OS updates
- Mono, an open source implementation of Microsoft's .NET Framework https://www.mono-project.com/
- Nuget, a Microsoft .NET foundation Windows x86 package manager CLI https://www.nuget.org/
- Source packageproviders registration (nuget, powershellgallery)
- Windows Packagemanagement (formerly OneGet) and Powershellget, a package management provider based on NuGet provider https://github.com/PowerShell/PowerShellGet/releases
- Windows PowershellCore by Photon OS package provider tdnf

The PowershellGallery registration is the oneliner:
```mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"```

The Microsoft Powershell installation is processed in reference to https://github.com/vmware/powerclicore/blob/master/Dockerfile.

Don't wonder - the full installation takes quite some time. As the Mono installation consumes fifty minutes and more (!) and usually you don't need a full Mono development environment, it became more a learn project. If interested, see files Findings_*.

You can setup nuget.exe with github actions: https://github.com/marketplace/actions/setup-nuget-exe-for-use-with-actions

```Dockerfile```
This Docker image contains Powershell Core 7.0.0 (Beta4) with registered Powershell Gallery.
The Docker image uses Mono with nuget.exe on a Debian OS.
- The mono 6.4.0.198 dockerfile related part original is from https://github.com/mono/docker/blob/master/6.4.0.198/Dockerfile.
- The original installation procedure for Pwsh7 on Linux is from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7

Simply build and run:
- ```cd /yourpathtoDockerfile/```
- ```docker run -it $(docker build -q .)```
