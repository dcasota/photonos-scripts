Photon OS scripts
-
This repo contains several VMware Photon OS related scripts.

Photon OS, a VMware operating system,  is an open source Linux container host for cloud-native applications. The OS is the preferred platform for IoT edge engineering. It runs docker containers, supports a resource foot print hardened setup, comes with a driver development kit for device drivers, and has package-based lifecycle management systems.
More information: https://vmware.github.io/photon/.

Photon OS is the foundation of many VMware software products. VMware vCenter Server Appliance bits to give an idea are made out of Photon OS. Hence, the functions are optimized for workloads on VMware hypervisor vSphere/ESXi.

Provisioning, failover and failback of Photon OS on other hypervisors in nowadays is a niche use case. Provisioning is supported for
- ISO setup
- Amazon Machine Image
- Google Compute Engine image
- Azure VHD
- Raspberry Pi3

You can find the download bits at https://github.com/vmware/photon/wiki/Downloading-Photon-OS.

## Create a Photon OS VM on ESXi
See https://vmware.github.io/photon/assets/files/html/1.0-2.0/Running-Photon-OS-on-vSphere.html

## Create a Photon OS VM on Azure
The following scripts may be helpful when creating a Photon OS VM on Azure.
- https://github.com/dcasota/azure-scripts/blob/master/create-AzImage-PhotonOS.ps1
- https://github.com/dcasota/azure-scripts/blob/master/create-AzVM_FromImage-PhotonOS.ps1

```create-AzImage-PhotonOS.ps1``` creates per default a VMware Photon OS 3.0 Rev2 Azure Generation V2 image.
```create-AzVM_FromImage-PhotonOS.ps1``` provisions on Azure a Photon OS VM with the Azure image created using ```create-AzImage-PhotonOS.ps1```.
 
```Powershell and PowerCLI on Photon OS```
-
PowerCLI on Photon OS needs as prerequisite a supported PowerShell release. To install or update Powershell Core enter
- ```tdnf install powershell``` or ```tdnf update powershell```

Install or update PowerCLI in a powershell command enter
- ```install-module -name VMware.PowerCLI``` or ```update-module -name VMware.PowerCLI```.

Good to know, the whole bunch of VMware PowerCLI cmdlets are made available as docker container. Run
- ```docker pull vmware/powerclicore:latest```
- ```docker run -it vmware/powerclicore:latest```


In this repo you find install scripts for Powershell on Photon OS with focus on fulfilling prerequisites for VMware.PowerCLI. Each script ```Pwsh[Release]OnPhotonOS.sh``` deploys the specific Powershell Core release on Photon OS.
Example: Install the actually latest Powershell release 7.0.3 using ```Pwsh7.0.3OnPhotonOS.ps1```. Simply enter afterwards ```pwsh7.0.3```.
![Powershell_on_Photon](https://github.com/dcasota/photonos-scripts/blob/master/Photon2-pwsh-current.png)

Afterwards you easily can install VMware.PowerCLI with ```install-module VMware.PowerCLI```.

A side-by-side-installation works fine but not all constellations are tested. Have a look to the release notes of Powershell Core as well.
![Side-by-side installation](https://github.com/dcasota/photonos-scripts/blob/master/side-side-installation.png)

As consumer you can download and install newer made available releases PowerCLI. I've visualized three different options - container, photon os built-in and scripted install - of a PowerCLI installation.
![Status Feb21_1](https://github.com/dcasota/photonos-scripts/blob/master/Status_Feb21_1.png)

It is expected that you find more and more .NET based cmdlets, modules, etc. which work fine, but there are a lot of cmdlets (and Powershellgallery modules) which produces interoperability errors or are not available. Simple as that, many Microsoft Windows-specific lowlevel functions were not or are not cross-compatible. On MS Windows, Powershell provides a module NetSecurity which isn't made available on Linux, even not with Powershell 7. Hence, cmdlets like ```Test-Netconnection``` are missing.

## Install Photon OS on ARM
(no study scripts yet)
## Create a Photon OS VM as AWS AMI machine and as Google Compute machine
(no study scripts yet)


Archive
-

```CreatePhotonOSVMOnAzure.ps1```
The script provisions VMware Photon OS 3.0 (Generation "V1") on Microsoft Azure. Just download it and edit the script variables for location, resourcegroup, network setting, base image and vm settings. You must have locally an extracted Photon OS .vhd file. The Photon OS image in $LocalFilePath must include name and full drive path of the untar'ed .vhd.
More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS
For the uploaded .vhd a separate storage account, storage container and storage blob are created.
The ```az vm create``` parameter ```--custom-data``` is a user exit for a post-provisioning process. The option is used to process a bash script to:
- install the latest Photon OS updates
- install VMware PowerCLI from the Powershell Gallery by a predownloaded script called ```dockerpwshgalleryonphotonos.sh``` (see below)
To activate the option simply set the variable $postprovisioning="true" (default). If the custom data file does not exist, nevertheless the creation successfully completes.
Photon OS on Azure disables the root account after custom data has been processed. Per default ssh PermitRootLogin is disabled too.
The script finishes with enabling Azure boot-diagnostics for the serial console option.

```dockerpwshgalleryonphotonos.sh```
This script makes Microsoft Powershell Core, VMware PowerCLI Core and the PowerShellGallery available on Photon OS.
It is using the VMware PowerCLI Core Dockerfile. It uses an Ubuntu 16.04 docker container with Powershell Core 6.x and PowerCLI Core 11.x.

Simply pull and run:
- ```docker pull vmware/powerclicore:ubuntu16.04```
- ```docker run -it vmware/powerclicore:ubuntu16.04```

If in ```CreatePhotonOSVMOnAzure.ps1``` the variable $postprovisioning="true" is set, ```dockerpwshgalleryonphotonos.sh``` is processed.

```pwshgalleryonphotonos.sh```
This study script makes Microsoft Powershell Core available on Photon OS by using Mono with Nuget.

It uses a tool from the Microsoft open source Nuget ecosystem.
See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org

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
