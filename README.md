Photon OS scripts
-
This repo contains several VMware Photon OS related scripts.

Photon OS, a VMware operating system,  is an open source Linux container host for cloud-native applications. The OS is the preferred platform for IoT edge engineering. It runs docker containers, supports a resource foot print hardened setup, comes with a driver development kit for device drivers, and has package-based lifecycle management systems.
More information: https://vmware.github.io/photon/

```CreatePhotonOSVMOnAzure.ps1```
-
```CreatePhotonOSVMOnAzure.ps1``` provisions VMware Photon OS on Microsoft Azure. Just download it and edit the script variables for location, resourcegroup, network setting, base image and vm settings.

Prerequisites are:
- VMware Photon OS 3.0 GA downloaded and unzipped .vhd
- Windows Powershell with installed Az module
- a Microsoft Azure account

Connected to Azure the script checks/creates
- resource group
- virtual network
- storage account/container/blob
- vm network settings

A local user account on Photon OS will be created during provisioning. It is created without root permissions. there are some default on username and password to know.
- $VMLocalAdminUser = "adminuser" #all small letters
- $VMLocalAdminPassword = "PhotonOs123!" #pwd must be 7-12 characters

The Photon OS image in $LocalFilePath must include name and full drive path of the untar'ed .vhd.
More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS
For the uploaded .vhd a separate storage account, storage container and storage blob are created.

The ```az vm create``` parameter ```--custom-data``` is a user exit for a post-provisioning process. The option is used to process a bash script to:
- install the latest Photon OS updates
- install VMware PowerCLI from the Powershell Gallery by a predownloaded script called ```dockerpwshgalleryonphotonos.sh``` (see below)

To activate the option simply set the variable $postprovisioning="true" (default). If the custom data file does not exist, nevertheless the creation successfully completes.

The script finishes with enabling Azure boot-diagnostics for the serial console option.

Photon OS on Azure disables the root account after custom data has been processed. Per default ssh PermitRootLogin is disabled too.
If root access is required, on the vm serial console login with the user credentials defined during setup. Run the following commands:
```
whoami
sudo passwd -u root
sudo passwd root
 (set new password)
su -l root
whoami
```

```PowerCLI and Powershell(Gallery) on Photon OS```
-
The described scripts are related to PowerCLI and to Powershell(Gallery) on Photon OS as these two functionalities are not built-in available, at least as per October 2019.

There are few approaches. The following overview helps to choose the appropriate solution.

![Status Oct19](https://github.com/dcasota/photonos-scripts/blob/master/Status_Oct19.png)

```dockerpwshgalleryonphotonos.sh```
-
This script makes Microsoft Powershell Core, VMware PowerCLI Core and the PowerShellGallery available on Photon OS.
Installing PowerShell Core on Photon OS does not built-in register PSGallery as source provider.
One way to accomplish it is using the VMware PowerCLI Core Dockerfile. It uses an Ubuntu 16.04 docker container with Powershell Core 6.x and PowerCLI Core 11.x.

Simply pull and run:
- ```docker pull vmware/powerclicore:ubuntu16.04```
- ```docker run -it vmware/powerclicore:ubuntu16.04```

If in ```CreatePhotonOSVMOnAzure.ps1``` the variable $postprovisioning="true" is set, ```dockerpwshgalleryonphotonos.sh``` is processed.

```pwshgalleryonphotonos.sh```
-
This study script makes Microsoft Powershell and the Microsoft PowerShellGallery available on Photon OS by using Mono with Nuget. It does not make use any docker container.

Installing PowerShell Core on Photon OS does not built-in register PSGallery or nuget.org as source provider.
One way to accomplish it is using a tool from the Microsoft open source Nuget ecosystem.
See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org

The tool called nuget.exe is Windowsx86-commandline-only. See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
"The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides all NuGet capabilities;"
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

Don't wonder - the full installation takes quite some time. As the Mono installation consumes 1 hour and more (!) and usually you don't need a full Mono development environment, it became more a learn project. If interested, see files Findings_*.

```Dockerfile```
-
This Docker image contains Powershell Core 7.0.0 (Beta4) with registered Powershell Gallery.

The Docker image uses Mono with nuget.exe on a Debian OS.
- The mono 6.4.0.198 dockerfile related part original is from https://github.com/mono/docker/blob/master/6.4.0.198/Dockerfile.
- The original installation procedure for Pwsh7 on Linux is from https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7

```Pwsh6.2.3OnPhotonOS.sh```
-
This script deploys Powershell Core 6.2.3 on VMware Photon OS. To start Powershell simply enter "Pwsh6.2.3".
With Powershell Core 6.1.0 and above the built-in automatic update functionality often is broken. There are a few workaround possibilities. Keep in mind, applying a workaround means that with specific modules not installed by using install-module, it cannot be updated. If this is not supported in your environment, use 'tdnf install -y powershell'. Sooner or later newer published releases are available.
This script provides a workaround solution. It downloads and installs Powershell Core 6.2.3 release, installs the module PackageManagement 1.1.7.0 and saves necessary prerequisites in profile /opt/microsoft/powershell/6.2.3/profile.ps1.
