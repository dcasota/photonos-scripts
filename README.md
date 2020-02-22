Photon OS scripts
-
This repo contains several VMware Photon OS related scripts.

Photon OS, a VMware operating system,  is an open source Linux container host for cloud-native applications. The OS is the preferred platform for IoT edge engineering. It runs docker containers, supports a resource foot print hardened setup, comes with a driver development kit for device drivers, and has package-based lifecycle management systems.
More information: https://vmware.github.io/photon/.

Photon OS is the foundation of many VMware software products. VMware vCenter Server Appliance and SRM OS bits are made out of Photon OS. Hence, the functions are optimized for workloads on VMware hypervisor vSphere/ESXi.

Provisioning, failover and failback of Photon OS on other hypervisors in nowadays is a niche use case. Provisioning is supported for
- ISO setup
- Amazon Machine Image
- Google Compute Engine image
- Azure VHD
- Raspberry Pi3

You can find the download bits at https://github.com/vmware/photon/wiki/Downloading-Photon-OS.



```Powershell and PowerCLI on Photon OS```
-
PowerCLI on Photon OS works since release 6.x and needs as prerequisite a supported PowerShell Core release. To install or update Powershell Core enter
- ```tdnf install powershell``` or ```tdnf update powershell```

Install or update PowerCLI in a powershell command enter
- ```install-module -name VMware.PowerCLI``` or ```update-module -name VMware.PowerCLI```.

Good to know, the whole bunch of VMware PowerCLI cmdlets are made available as docker container. Run
- ```docker pull vmware/powerclicore:latest```
- ```docker run -it vmware/powerclicore```



```.NET based PowerCLI cmdlets, flings, apps, etc.```
-
You should find more and more PowerCLI cmdlets modules which work fine, but some cmdlets (and Powershellgallery modules) produces interoperability errors. Simple as that, many Microsoft Windows-specific lowlevel functions were not or are not cross-compatible. Self-contained applications is a development field under construction.

In some situation an alternative functionality method  or a side-by-side installation could be useful. 
![Status Feb20](https://github.com/dcasota/photonos-scripts/blob/master/Status_Feb20.png)

There are few approaches:
- Download and install new PowerShell Core and PowerCLI releases
- Provide more .NET core lowlevel compatibility for cmdlets on Photon OS


Each script ```Pwsh[Release]OnPhotonOS.sh``` deploys the specific Powershell Core release on Photon OS.
Example: Install the actually latest Powershell release 7rc3 using ```Pwsh7rc3OnPhotonOS.ps1```. Simply enter afterwards ```pwsh7rc3```.
See comment inside the scripts. A side-by-side-installation works fine but not all constellations are tested.

![Side-by-side installation](https://github.com/dcasota/photonos-scripts/blob/master/side-side-installation.png)




## Create a Photon OS VM on ESXi
(no study scripts yet)
## Create a Photon OS VM on ARM
(no study scripts yet)
## Create a Photon OS VM on AWS, Google
(no study scripts yet)

## Create a Photon OS VM on Azure
The following scripts may be helpful when creating a Photon OS VM on Azure.
- https://github.com/dcasota/azure-scripts/blob/master/create-AzImage_GenV2-PhotonOS.ps1
- https://github.com/dcasota/azure-scripts/blob/master/create-AzVM_FromImage-PhotonOS.ps1

- https://github.com/dcasota/photonos-scripts/blob/master/CreatePhotonOSVMOnAzure.ps1

```create-AzImage_GenV2-PhotonOS.ps1``` creates a VMware Photon OS 3.0 Rev2 Azure Generation V2 image.
```create-AzVM_FromImage-PhotonOS.ps1``` provisions an Azure Generation V2 VM with the Azure image created using ```create-AzImage_GenV2-PhotonOS.ps1```.
```CreatePhotonOSVMOnAzure.ps1``` provisions VMware Photon OS 3.0 (Generation "V1") on Microsoft Azure.

Why Generation V2?
For system engineers knowledge about the VMware virtual hardware version is crucial when it comes to VM capabilities and natural limitations. Latest capabilities like UEFI boot type and virtualization-based security are still evolving. 
The same begins for cloud virtual hardware like in Azure Generations.
On Azure, VMs with UEFI boot type are not supported yet. However some downgrade options were made available to migrate such on-premises Windows servers to Azure by converting the boot type of the on-premises servers to BIOS while migrating them.

 Some docs artefacts about
- https://docs.microsoft.com/en-us/azure/virtual-machines/windows/generation-2#features-and-capabilities
- https://docs.vmware.com/en/VMware-vSphere/6.7/com.vmware.vsphere.vm_admin.doc/GUID-789C3913-1053-4850-A0F0-E29C3D32B6DA.html

Download the script ```create-AzImage_GenV2-PhotonOS.ps1``` and ```create-AzVM_FromImage-PhotonOS.ps1```. You can pass a bunch of parameters like Azure login, resourcegroup, location name, storage account, container, image name, etc. The first script passes the download URL of the VMware Photon OS release. More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS.
Prerequisites for both scripts are:
- Windows Powershell with installed Az module, Az CLI
- a Microsoft Azure account

First ```create-AzImage_GenV2-PhotonOS.ps1``` installs Azure CLI and the Powershell Az module. It connects to Azure and saves the Az-Context. It checks/creates
- resource group
- virtual network
- storage account/container/blob
- settings for a temporary VM

It creates a temporary Windows VM. Using the AzVMCustomScriptExtension functionality, dynamically created scriptblocks including passed Az-Context are used to postinstall the necessary prerequisites inside that Windows VM. The VMware Photon OS bits for Azure are downloaded from the VMware download location, the extracted VMware Photon OS .vhd is uploaded as Azure page blob and after the Generation V2 image has been created, the Windows VM is deleted. For study purposes the temporary VM created is Microsoft Windows Server 2019 on a Hyper-V Generation V2 virtual hardware using the offering Standard_E4s_v3.

Using ```create-AzVM_FromImage-PhotonOS.ps1``` you can pass Photon OS VM settings. As example, a local user account on Photon OS will be created during provisioning. It is created without root permissions. There are some culprit to know.
- ```[string]$VMLocalAdminUser = "LocalAdminUser"``` # Check if uppercase and lowercase is enforced/supported.
- ```[string]$VMLocalAdminPwd="Secure2020123!"```# 12-123 chars

The script checks/creates
- resource group
- virtual network
- storage account/container/blob
- vm

The script finishes with enabling the Azure boot-diagnostics option.

If root access is required, on the vm serial console login with the user credentials defined during setup, run the following commands:
 - ```whoami```
 - ```sudo passwd -u root```
 - ```sudo passwd root```
 - ```(set new password)```
 - ```su -l root```
 - ```whoami```
  

```CreatePhotonOSVMOnAzure.ps1``` provisions VMware Photon OS 3.0 (Generation "V1") on Microsoft Azure. Just download it and edit the script variables for location, resourcegroup, network setting, base image and vm settings. You must have locally an extracted Photon OS .vhd file. The Photon OS image in $LocalFilePath must include name and full drive path of the untar'ed .vhd.
More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS
For the uploaded .vhd a separate storage account, storage container and storage blob are created.
The ```az vm create``` parameter ```--custom-data``` is a user exit for a post-provisioning process. The option is used to process a bash script to:
- install the latest Photon OS updates
- install VMware PowerCLI from the Powershell Gallery by a predownloaded script called ```dockerpwshgalleryonphotonos.sh``` (see below)
To activate the option simply set the variable $postprovisioning="true" (default). If the custom data file does not exist, nevertheless the creation successfully completes.
Photon OS on Azure disables the root account after custom data has been processed. Per default ssh PermitRootLogin is disabled too.
The script finishes with enabling Azure boot-diagnostics for the serial console option.



Archive
-
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
