#!/bin/sh
#
# This scripts makes the Microsoft PowerShellGallery available on Photon OS by using Mono with Nuget.
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
# The installation output is /tmp/myScript.txt.
#
#
# Remark:
# In reference to https://www.mono-project.com/docs/tools+libraries/tools/mkbundle/ an avoidance may be possible:
# "Mono can turn .NET applications (executable code and its dependencies) into self-contained executables"
# "that do not rely on Mono being installed on the system to simplify deployment of.NET Applications."
#
#
# History
# 0.1  21.08.2019   dcasota  Initial release
# 0.2  08.10.2019   dcasota  Installable Powershell 6.2.3 with Mono
# 0.3  17.10.2018   dcasota  Adding built-in tdnf powershell package. Removing side installation of Powershell 6.2.3
#
#
# 

monourl="https://download.mono-project.com/sources/mono/mono-6.4.0.198.tar.xz"
monofilename="mono-6.4.0.198.tar.xz"
monodir="mono-6.4.0.198"

echo "$(date) + Installing Microsoft PowerShellGallery on Photon OS by using Mono with Nuget ..."
echo "$(date) + Installing Microsoft PowerShellGallery on Photon OS by using Mono with Nuget ..." >> /tmp/myScript.txt
whoami >> /tmp/myScript.txt


echo "$(date) + Installing Prerequisites of Mono ..."
echo "$(date) + Installing Prerequisites of Mono ..." >> /tmp/myScript.txt
tdnf -y install tar icu libunwind curl >> /tmp/myScript.txt
tdnf -y install linux-api-headers cmake gcc glibc-devel binutils >> /tmp/myScript.txt
yum -y install bison gettext glib2 freetype fontconfig libpng libpng-devel >> /tmp/myScript.txt
yum -y install gcc automake autoconf libtool make bzip2 >> /tmp/myScript.txt

echo "$(date) + Downloading and installing Mono ..."
echo "$(date) + Downloading and installing Mono ..." >> /tmp/myScript.txt
mkdir ~/mono >> /tmp/myScript.txt
cd ~/mono >> /tmp/myScript.txt
curl -o $monofilename $monourl >> /tmp/myScript.txt
tar -xvf $monofilename -C ~/mono >> /tmp/myScript.txt
cd ~/mono/$monodir >> /tmp/myScript.txt
# https://www.mono-project.com/docs/compiling-mono/small-footprint/
./configure --prefix=/usr/local --enable-minimal=aot,profiler --enable-small-config >> /tmp/myScript.txt
make >> /tmp/myScript.txt
make install >> /tmp/myScript.txt

echo "$(date) + Downloading and Mono-Nuget-configuring PwshGallery Source ..."
echo "$(date) + Downloading and Mono-Nuget-configuring PwshGallery Source ..." >> /tmp/myScript.txt
curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2" >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name nuget.org -Source "https://www.nuget.org/api/v2" >> /tmp/myScript.txt

echo "$(date) + Installing Powershell ..."
echo "$(date) + Installing Powershell ..." >> /tmp/myScript.txt
tdnf -y install powershell

echo "$(date) + Installing Powershell modules packagemanagement and powershellget ..."
echo "$(date) + Installing Powershell modules packagemanagement and powershellget ..." >> /tmp/myScript.txt
pwsh -c '$PSVersionTable' >> /tmp/myScript.txt
pwsh -c 'install-module packagemanagement -Scope AllUsers -force' >> /tmp/myScript.txt
pwsh -c 'install-module powershellget -Scope AllUsers -force' >> /tmp/myScript.txt
# pwsh -c 'Set-PSRepository -Name PSGallery -InstallationPolicy Trusted' >> /tmp/myScript.txt

echo "$(date) + Cleanup ..."
cd ~/ >> /tmp/myScript.txt
rm ~/mono/$monofilename >> /tmp/myScript.txt

echo "$(date) + Installing Microsoft PowerShellGallery on Photon OS by using Mono with Nuget finished."
echo "$(date) + Installing Microsoft PowerShellGallery on Photon OS by using Mono with Nuget finished." >> /tmp/myScript.txt



