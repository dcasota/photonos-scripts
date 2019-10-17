#!/bin/sh
#
# This study script makes Microsoft Powershell Core and the PowerShellGallery available on Photon OS by using Mono with Nuget.
# 
# Installing PowerShell Core on Photon OS does not built-in register PSGallery or nuget.org as source provider.
# One way to accomplish it is using a tool from the Microsoft open source Nuget ecosystem.
# See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org
#
# The tool called nuget.exe is Windowsx86-commandline-only. See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
# "The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides all NuGet capabilities;"
# "it can also be run on Mac OSX and Linux using Mono with some limitations."
# This scripts downloads all necessary prerequisites (tools, Mono, Nuget.exe) and builds the Mono software.
# The  registration is the oneliner: mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"
#
# Mono related weblinks:
# https://www.mono-project.com/docs/compiling-mono/small-footprint/
# https://www.mono-project.com/docs/compiling-mono/linux/
# https://github.com/mono/mono/blob/master/README.md
# https://www.mono-project.com/docs/compiling-mono/unsupported-advanced-compile-options/
#
# Remark on Nuget.exe on Linux:
# In reference to https://www.mono-project.com/docs/tools+libraries/tools/mkbundle/ it could be possible to turn Nuget.exe into
# a self-contained executable that does not rely on Mono being installed on the system. If interested, see Findings_MkbundledNuget.txt in this repo archive.
#
#
# History
# 0.1  21.08.2019   dcasota  Initial release
# 0.2  08.10.2019   dcasota  Installable Powershell 6.2.3 with Mono
# 0.3  17.10.2018   dcasota  Adding built-in tdnf powershell package. Code cleanup.
#
#
# 

monourl="https://download.mono-project.com/sources/mono/mono-6.4.0.198.tar.xz"
monofilename="mono-6.4.0.198.tar.xz"
monodir="mono-6.4.0.198"

echo "$(date) + Installing Microsoft PowerShellGallery on Photon OS by using Mono with Nuget ..."
whoami

echo "$(date) + Installing Prerequisites of Mono ..."
tdnf -y install tar icu libunwind curl
tdnf -y install linux-api-headers cmake gcc glibc-devel binutils
yum -y install bison gettext glib2 freetype fontconfig libpng libpng-devel
yum -y install gcc automake autoconf libtool make bzip2

echo "$(date) + Downloading and installing Mono ..."
mkdir ~/mono
cd ~/mono
curl -o $monofilename $monourl
tar -xvf $monofilename -C ~/mono
cd ~/mono/$monodir
# ./configure --prefix=/usr/local --enable-small-config=yes --enable-minimal=aot,profiler
./configure --prefix=/usr/local
make -j4
make install

echo "$(date) + Downloading and Configuring PwshGallery Source by Mono with Nuget ..."
curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"
mono /usr/local/bin/nuget.exe sources Add -Name nuget.org -Source "https://www.nuget.org/api/v2"

echo "$(date) + Installing Powershell ..."
# This part is in reference from https://github.com/vmware/powerclicore/blob/master/Dockerfile
# Install PowerShell and unzip on Photon
tdnf install -y powershell unzip

# Set working directory so stuff doesn't end up in /
cd /root

# Install PackageManagement and PowerShellGet
# This is temporary until it is included in the PowerShell Core package for Photon
curl -O -J -L https://www.powershellgallery.com/api/v2/package/PackageManagement
unzip PackageManagement -d /usr/lib/powershell/Modules/PackageManagement
rm -f PackageManagement

curl -O -J -L https://www.powershellgallery.com/api/v2/package/PowerShellGet
unzip PowerShellGet -d /usr/lib/powershell/Modules/PowerShellGet
rm -f PowerShellGet

# Workaround for https://github.com/vmware/photon/issues/752
mkdir -p /usr/lib/powershell/ref/
ln -s /usr/lib/powershell/*.dll /usr/lib/powershell/ref/

pwsh -c 'Set-PSRepository -Name PSGallery -InstallationPolicy Trusted'

echo "$(date) + Cleanup ..."
cd ~/
# Final clean up
tdnf erase -y unzip
tdnf clean all
rm ~/mono/$monofilename
# Remove unnecessary installed prerequisites of Mono

echo "$(date) + Installing Microsoft PowerShellGallery on Photon OS by using Mono with Nuget finished."



