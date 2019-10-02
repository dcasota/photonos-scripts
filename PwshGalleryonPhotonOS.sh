#!/bin/sh
echo "$(date) + Installing ..." >> /tmp/myScript.txt
whoami >> /tmp/myScript.txt
tdnf -y update >> /tmp/myScript.txt
tdnf -y install tar icu libunwind unzip wget >> /tmp/myScript.txt
tdnf -y install linux-api-headers cmake gcc glibc-devel binutils >> /tmp/myScript.txt
yum -y install bison gettext glib2 freetype fontconfig libpng libpng-devel >> /tmp/myScript.txt
yum -y install gcc automake autoconf libtool make bzip2 >> /tmp/myScript.txt
# wget https://download.mono-project.com/sources/mono/mono-6.0.0.313.tar.xz >> /tmp/myScript.txt
# wget https://download.mono-project.com/sources/mono/mono-5.18.1.28.tar.bz2 >> /tmp/myScript.txt
wget https://download.mono-project.com/sources/mono/mono-5.18.0.225.tar.bz2 >> /tmp/myScript.txt
mkdir ~/mono >> /tmp/myScript.txt
tar xfvj mono-5.18.0.225.tar.bz2 -C ~/mono >> /tmp/myScript.txt
cd ~/mono/mono-5.18.0.225 >> /tmp/myScript.txt
./configure --prefix=/usr/local >> /tmp/myScript.txt
make >> /tmp/myScript.txt
make install >> /tmp/myScript.txt
cd /tmp >> /tmp/myScript.txt
curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2" >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name nuget.org -Source "https://www.nuget.org/api/v2" >> /tmp/myScript.txt
wget https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.3/powershell-7.0.0-preview.3-linux-x64.tar.gz >> /tmp/myScript.txt
mkdir ~/powershell >> /tmp/myScript.txt
mkdir -p ~/.local/share/powershell/Modules >> /tmp/myScript.txt
tar -xvf ./powershell-7.0.0-preview.3-linux-x64.tar.gz  -C ~/powershell >> /tmp/myScript.txt
powershell/pwsh -c '$PSVersionTable' >> /tmp/myScript.txt
powershell/pwsh -c 'install-module packagemanagement -force' >> /tmp/myScript.txt
powershell/pwsh -c 'install-module powershellget -force' >> /tmp/myScript.txt
powershell/pwsh -c 'install-module Az -force' >> /tmp/myScript.txt
powershell/pwsh -c 'install-module VMware.PowerCLI -force' >> /tmp/myScript.txt
# powershell/pwsh -c 'Set-PSRepository -Name PSGallery -InstallationPolicy Trusted'
echo "$(date) + Installation finished." >> /tmp/myScript.txt



