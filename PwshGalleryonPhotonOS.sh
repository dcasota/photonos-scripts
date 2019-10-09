#!/bin/sh
#
# This scripts makes the Microsoft PowerShellGallery available on VMware Photon OS. In addition VMware PowerCLI is installed.
# 
# Installing PowerShell Core on Photon OS does not built-in register PSGallery or nuget.org as source provider.
# 
# However this can be accomplished using a tool from the Microsoft open source Nuget ecosystem.
# See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org
#
# The tool called nuget.exe is Windowsx86-commandline-only. See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
# "The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides all NuGet capabilities;"
# "it can also be run on Mac OSX and Linux using Mono with some limitations."
#
# This scripts downloads all necessary prerequisites (tools, Mono, Nuget.exe) to register the PowerShell Gallery.
# The registration is the oneliner: mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"
#
# After the Powershell Core installation, VMware.PowerCLI is installed.
#
# Remark:
# I didn't figure out how to avoid the storage overload of Mono with nuget.exe.
# In reference to https://www.mono-project.com/docs/tools+libraries/tools/mkbundle/ an avoidance may be possible:
# "Mono can turn .NET applications (executable code and its dependencies) into self-contained executables"
# "that do not rely on Mono being installed on the system to simplify deployment of.NET Applications."
#
#
# History
# 0.1  21.08.2019   dcasota  Initial release
# 0.2  08.10.2019   dcasota  Installable Powershell 6.2.3 with Mono
#
#
# 

monourl="https://download.mono-project.com/sources/mono/mono-6.0.0.334.tar.xz"
monofile="mono-6.0.0.334.tar.xz"
monodir="mono-6.0.0.334"

powershellfile="powershell-6.2.3-linux-x64.tar.gz"
powershellurl="https://github.com/PowerShell/PowerShell/releases/download/v6.2.3/powershell-6.2.3-linux-x64.tar.gz"
powershelldir="~/powershell"

echo "$(date) + Installing ..." >> /tmp/myScript.txt
whoami >> /tmp/myScript.txt

tdnf -y update >> /tmp/myScript.txt
tdnf -y install tar icu libunwind unzip wget >> /tmp/myScript.txt
tdnf -y install linux-api-headers cmake gcc glibc-devel binutils >> /tmp/myScript.txt
yum -y install bison gettext glib2 freetype fontconfig libpng libpng-devel >> /tmp/myScript.txt
yum -y install gcc automake autoconf libtool make bzip2 >> /tmp/myScript.txt

cd /tmp >> /tmp/myScript.txt
wget $monourl >> /tmp/myScript.txt
mkdir ~/mono >> /tmp/myScript.txt
tar xfvj $monofile -C ~/mono >> /tmp/myScript.txt
cd ~/mono/$monodir >> /tmp/myScript.txt
./configure --prefix=/usr/local >> /tmp/myScript.txt
make >> /tmp/myScript.txt
make install >> /tmp/myScript.txt

cd /tmp >> /tmp/myScript.txt
curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2" >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name nuget.org -Source "https://www.nuget.org/api/v2" >> /tmp/myScript.txt

cd /tmp >> /tmp/myScript.txt
wget $powershellurl >> /tmp/myScript.txt
mkdir $powershelldir >> /tmp/myScript.txt
mkdir -p ~/.local/share/powershell/Modules >> /tmp/myScript.txt
tar -xvf ./$powershellfile -C $powershelldir >> /tmp/myScript.txt
~/powershell/pwsh -c '$PSVersionTable' >> /tmp/myScript.txt
~/powershell/pwsh -c 'install-module packagemanagement -force' >> /tmp/myScript.txt
~/powershell/pwsh -c 'install-module powershellget -force' >> /tmp/myScript.txt
~/powershell/pwsh -c 'install-module VMware.PowerCLI -force' >> /tmp/myScript.txt
# powershell/pwsh -c 'Set-PSRepository -Name PSGallery -InstallationPolicy Trusted'

echo "$(date) + Installation finished." >> /tmp/myScript.txt



