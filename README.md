# What is Photon OS scripts?
This repo contains a bunch of Photon OS related scripts.  
Photon OS is a VMware operating system for open source Linux container host for cloud-native applications. It runs on x86_64 + arm64 processors and on several hyperscaler clouds. See https://vmware.github.io/photon .

# Use Case 1 - Photon OS as platform for hosting forensics tools
"Using the recommendations of the Kernel Self-Protection Project (KSPP), the Photon OS Linux Kernel is secure from the start."
As for any forensic platform, the availability of Photon OS is highly important. The planned EOL schedule has been specified [here]( https://blogs.vmware.com/vsphere/2022/01/photon-1-x-end-of-support-announcement.html).

 The actual Photon OS releases are 1:1 related to Linux kernel releases.
| Linux kernel  |   Photon OS   |
| ------------- | ------------- |
|     4.4       |      1.x      |
|     4.9       |      2.x      |
|     4.19      |      3.x      |
|     5.10      |      4.x      |
|     6.07      |      5.0 Beta |

Photon OS supports forensics tools components. As example, it can be configured to read/write different imager formats - here some findings:
- https://github.com/dcasota/photonos-scripts/wiki/NTFS-mount-on-Photon-OS
- https://github.com/dcasota/photonos-scripts/wiki/VMFS6-mount-on-Photon-OS

The [Security Advisories](https://github.com/vmware/photon/wiki/Security-Advisories) may give an idea of the necessity of chains of packages to be held safe. It takes time to clearly understand a single mitigation. See some personal progress [here](https://github.com/dcasota/photonos-scripts/wiki/Mitigations-for-CPU-vulnerabilities).

With each Linux kernel update trillions of packages permutations are given, in theory it's slightly less architecture specific. A slice of it reflects in Photon OS. You can see which packages are made available from contributors at https://github.com/vmware/photon/commits/dev.

Packages work begin with 'there is a version of package x in relation to y, which is not or it is integrated to photon release z only.' There is no handy interoperability lookup of packages release/flavor/architecture like the inter-product viewer in VMware vSphere interoperability guide though.

The following screenshot depicts a part of the concept idea.
![Package Report Concept](https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report_concept.png)

This powershell script creates the package report. 
https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report.ps1

The comma delimited .prn output file simply lists all Photon OS Github specs names with releases per Photon OS Github Branch. Output file sample:
https://github.com/dcasota/photonos-scripts/blob/master/photonos-package-report.prn

# Use Case 2 - Baremetal installation / staging
Baremetal environments are technically supported. The focus of Photon OS however isn't primarily to run on baremetal. For security purposes, peripheral devices connectivity is restricted. But you can install Photon OS on any x86_64 and arm64 baremetal.

On x86_64, Photon OS comes with different installation flavors: "Security hardened" (minimal), Developer, Real Time, and as Ostree-Host.

Photon OS runs best on vSphere x86_64. It runs kubernetes, docker containers, supports a resource foot print hardened setup, and has a package-based lifecycle management system. The secure appliance (virtual hardware v13) installation is built-in VMware hypervisor optimized, and delivered as OVA setup.

Also, since 5.0 beta, there is more support for running Photon OS on ESXi on Arm.

Provisioning Photon OS on Raspberry Pi is supported as well, e.g. see [Configuring a Raspberry Pi 4 for supporting usb license dongle remoting](https://github.com/dcasota/photonos-scripts/wiki/Configure-a-complete-Raspberry-Pi-Virtualhere-installation).

# Use Case 3 - Azure installation with UEFI boot support
In a Non-vSphere hyperscaler environment - this chapter is Microsoft Azure specific - the following scripts may be helpful when creating a Photon OS virtual machine with UEFI support.
- https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/create-AzImage-PhotonOS.ps1
- https://github.com/dcasota/azure-scripts/blob/master/PhotonOS/create-AzVM_FromImage-PhotonOS.ps1  
```create-AzImage-PhotonOS.ps1``` creates an Azure Generation V2 image, per default of VMware Photon OS 4.0.  
```create-AzVM_FromImage-PhotonOS.ps1``` provisions on Azure a Photon OS VM with the Azure image created using ```create-AzImage-PhotonOS.ps1```.

# Use Case 4 - PowerCLI on Photon OS
"VMware PowerCLI is a suite of PowerShell modules to manage VMware products and services. VMware PowerCLI includes over 800 cmdlets to easily manage your infrastructure on a global scale." See the [interoperability matrix](https://developer.vmware.com/docs/17472/-compatibility-matrix).
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

# Use Case 5 - Learning from Kube Academy
[Kube Academy](https://kube.academy) contains a huge bunch of Kubernetes learning videos. The 'setting up the workstation' has been adopted to run the labs on Photon OS, see
- https://github.com/dcasota/photonos-scripts/wiki/Kube-Academy---setting-up-the-workstation
- https://github.com/dcasota/photonos-scripts/wiki/Kube-Academy-Scripts

# Use Case 6 - Docker containers
Docker in most Linux distros has built-in support. Photon OS' architecture strength is the maintenance of all flavors from security-hardened to hardware-optimized. This combination is highly preferred for some container purposes.
See some personal docker container learning progress with [Potree - a WebGL based viewer for large point clouds](https://github.com/dcasota/photonos-scripts/wiki/Configure-Potree,-a-WebGL-based-viewer-for-large-point-clouds,-on-VMware-Photon-OS).

# Use Case 7 - ISO build machine on Photon OS
From a packages update service consistency perspective, there is always a good moment for creating an ISO binary.
Photon OS can be used as ISO build platform. Some personal progress using Photon OS as Photon OS ISO build machine has been documented on [How to build the Photon OS ISO file](https://github.com/dcasota/photonos-scripts/wiki/How-to-build-the-Photon-OS-ISO-file). Photon OS could be used to create eg. Microsoft Windows ISO builds from [uupdump.net](https://uupdump.net) as well.

# Photon OS components in commercial products and open-source Photon OS
From a paid support perspective, open source Photon OS has nothing to do with the VMware commercial products in which some Photon OS components are a customized part of. VCSA, vSphere Replication, Workstation, vRealize Operations, and much more run on a strict VMware governance for that commercial product.

There isn't a customer product SKU Photon Platform 2.x, 3.x or 4.x. Hence you cannot buy official Photon Platform support. 

Before strictly separating commercial components, there was a VMware Photon Platform 1.x. It hit End of General Support on 2019-03-02.
For VMware products' Enterprise Application Policy, see https://www.vmware.com/support/policies/enterprise-application.html.

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
