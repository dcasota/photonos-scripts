Photon OS scripts
-
This repo contains several VMware Photon OS related scripts. A major part is related to run PowerCLI on Photon OS.

Photon OS, a VMware operating system,  is an open source Linux container host for cloud-native applications. It runs docker containers, supports a resource foot print hardened setup, comes with a driver development kit for device drivers, and has package-based lifecycle management systems.
More information: https://vmware.github.io/photon/.

The VMware Photon Platform 1.x hit End of General Support on 2019-03-02 according to https://lifecycle.vmware.com/. There still is an Enterprise Application Policy https://www.vmware.com/support/policies/enterprise-application.html though.

There isn't a customer product SKU Photon Platform 2.x, 3.x or 4.x. Hence you cannot buy official Photon Platform support. 

The open source Photon OS has nothing to do with the VMware customer products in which Photon OS is a part of. VCSA, vSphere Replication, Workstation, vRealize Operations, and much more run on a strict VMware internal ~pipeline for that commercial product.

For the open source product you can find the download bits at https://github.com/vmware/photon/wiki/Downloading-Photon-OS.

The open source Photon OS evolution is highly interesting. There are different OS appliance flavors for "Generic", "VMware hypervisor optimized", "AWS optimized", "Security hardened" and "Real Time". Provisioning, failover and failback of Photon OS on other platforms and architectures (x86_64 + arm64) in nowadays isn't a niche use case like in 2017.

Provisioning is supported for
- ISO setup
- Amazon Machine Image
- Google Compute Engine image
- Azure VHD
- Raspberry Pi


In a Non-vSphere environment, as example on Azure, the following scripts may be helpful when creating a Photon OS VM.
- https://github.com/dcasota/azure-scripts/blob/master/create-AzImage-PhotonOS.ps1
- https://github.com/dcasota/azure-scripts/blob/master/create-AzVM_FromImage-PhotonOS.ps1
```create-AzImage-PhotonOS.ps1``` creates an Azure Generation V2 image, per default of VMware Photon OS 3.0 Rev2.
```create-AzVM_FromImage-PhotonOS.ps1``` provisions on Azure a Photon OS VM with the Azure image created using ```create-AzImage-PhotonOS.ps1```.

A major aspect always was/is security. The Security Advisories for 1.x, 2.x, 3.x may give an idea of the necessity of chain of packages to be held safe https://github.com/vmware/photon/wiki/Security-Advisories.

With each Linux kernel update trillions of packages permutations are given, in theory it's slightly less architecture specific. A slice of it reflects in Photon OS. You can see which packages are made available from contributors at https://github.com/vmware/photon/commits/dev.




# PowerCLI on Photon OS
As consumer you can download and install any release of PowerCLI on VMware Photon OS. There are three different options - container-based, photon os built-in and scripted install.
![Status Feb21_1](https://github.com/dcasota/photonos-scripts/blob/master/Status_Feb21_1.png)

VMware PowerCLI is available as docker container. Run
- ```docker pull vmware/powerclicore:latest```
- ```docker run -it vmware/powerclicore:latest```



Photon OS built-in supports Powershell since 6.2. so you simply can install the package right before PowerCLI.

To install or update Powershell Core enter
- ```tdnf install powershell``` or ```tdnf update powershell```

Install or update PowerCLI in a powershell command enter
- ```install-module -name VMware.PowerCLI``` or ```update-module -name VMware.PowerCLI```


In some use cases it is necessary to have a specific Powershell release. Some PowerCLI cmdlets on Windows do not work yet on Photon OS. Simple as that, many Microsoft Windows-specific lowlevel functions were not or are not cross-compatible.
In this repo you find install scripts for Powershell on Photon OS with focus on fulfilling prerequisites for VMware.PowerCLI. Each script ```Pwsh[Release]OnPhotonOS.sh``` deploys the specific Powershell Core release on Photon OS.

Example: Install the Powershell release 7.0.3 using ```Pwsh7.0.3OnPhotonOS.ps1```. Simply enter afterwards ```pwsh7.0.3```.

![Powershell_on_Photon](https://github.com/dcasota/photonos-scripts/blob/master/Photon2-pwsh-current.png)

Afterwards you easily can install VMware.PowerCLI with ```install-module VMware.PowerCLI```.

A side-by-side-installation works fine but not all constellations are tested. Have a look to the release notes of Powershell Core as well.
![Side-by-side installation](https://github.com/dcasota/photonos-scripts/blob/master/side-side-installation.png)








Archive
-
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
