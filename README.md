Photon OS on Azure
-
Photon OS, a VMware operating system,  is an open source Linux container host for cloud-native applications. The OS is the preferred platform for IoT edge engineering. It runs docker containers, supports a resource foot print hardened setup, comes with a driver development kit for device drivers, and has package-based lifecycle management systems.
More information: https://vmware.github.io/photon/

This repo contains several scripts to automate the installation and to simplify the use of the powershellgallery packages on Photon OS on Azure. Prerequisites are:
- a Microsoft Azure account
- Windows Powershell with installed Az module

```CreatePhotonOSVMOnAzure.ps1```
-
```CreatePhotonOSVMOnAzure.ps1``` provisions VMware Photon OS on Microsoft Azure. Just download it and edit the script variables for location, resourcegroup, network setting, base image and vm settings. 

Connected to Azure it checks/creates
- resource group
- virtual network
- storage account/container/blob
- vm network settings

A local user account on Photon OS will be created during provisioning. It is created without root permissions. there are some conventions on username and password to know.
- $VMLocalAdminUser = "adminuser" #all small letters
- $VMLocalAdminPassword = "PhotonOs123!" #pwd must be 7-12 characters

The Photon OS image in localfilepath must include name and full drive path of the untar'ed .vhd.
More information: https://github.com/vmware/photon/wiki/Downloading-Photon-OS
For the uploaded .vhd a separate storage account, storage container and storage blob are created.

The ```az vm create``` parameter ```--custom-data``` is a user exit for a post-provisioning process. In this script it is used to pass a bash file. If the custom data file does not exist, nevertheless the creation successfully completes. The bash script is used to:
- install the latest Photon OS updates
- install VMware PowerCLI from the Powershell Gallery

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

```pwshgalleryonphotonos.sh```
-

This scripts installs VMware PowerCLI and makes the Microsoft PowerShellGallery available on Photon OS.

Installing PowerShell Core on Photon OS does not built-in register PSGallery or nuget.org as source provider.
However this can be accomplished using a tool from the Microsoft open source Nuget ecosystem.
See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org

The tool called nuget.exe is Windowsx86-commandline-only. See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
"The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides all NuGet capabilities; it can also be run on Mac OSX and Linux using Mono with some limitations."

This scripts downloads all necessary prerequisites (tools, Mono, Nuget.exe) to register the PowerShell Gallery. The registration is a oneliner:
```mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"```
 
After the Powershell Core installation, VMware PowerCLI is installed.


During custom-data of ```CreatePhotonOSVMOnAzure.ps1```, ```pwshgalleryonphotonos.sh``` is processed. Don't wonder - the full installation takes quite some time. As said, it installs
- Photon OS updates
- Mono, an open source implementation of Microsoft's .NET Framework https://www.mono-project.com/
- Nuget, a Microsoft .NET foundation Windows x86 package manager CLI https://www.nuget.org/
- Windows Packagemanagement (formerly OneGet) and Powershellget, a package management provider based on NuGet provider https://github.com/PowerShell/PowerShellGet/releases
- Packageproviders (nuget, powershellgallery)
- Windows PowershellCore https://github.com/PowerShell/PowerShell
- The VMware PowerCLI powershell module https://www.powershellgallery.com/packages/VMware.PowerCLI

Remark:
In reference to https://www.mono-project.com/docs/tools+libraries/tools/mkbundle/ : "Mono can turn .NET applications (executable code and its dependencies) into self-contained executables that do not rely on Mono being installed on the system to simplify deployment of.NET Applications."
