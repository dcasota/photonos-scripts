#!/bin/sh
echo "this has been written via cloud-init" + $(date) >> /tmp/myScript.txt
whoami >> /tmp/myScript.txt
tdnf -y update >> /tmp/myScript.txt
tdnf -y install tar icu libunwind unzip wget >> /tmp/myScript.txt
wget https://download.mono-project.com/sources/mono/mono-6.0.0.313.tar.xz >> /tmp/myScript.txt
mkdir ~/mono >> /tmp/myScript.txt
tar -xvf mono-6.0.0.313.tar.xz -C ~/mono >> /tmp/myScript.txt
yum install mono-complete >> /tmp/myScript.txt
tdnf install linux-api-headers cmake gcc glibc-devel binutils >> /tmp/myScript.txt
yum install bison gettext glib2 freetype fontconfig libpng libpng-devel >> /tmp/myScript.txt
yum install java unzip gcc gcc-c++ automake autoconf libtool make bzip2 wget >> /tmp/myScript.txt
cd ~/mono >> /tmp/myScript.txt
./configure --prefix=/usr/local >> /tmp/myScript.txt
make >> /tmp/myScript.txt
make install >> /tmp/myScript.txt
curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe >> /tmp/myScript.txt
mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2" >> /tmp/myScript.txt
wget https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.3/powershell-7.0.0-preview.3-linux-x64.tar.gz >> /tmp/myScript.txt
wget https://vdc-download.vmware.com/vmwb-repository/dcr-public/db25b92c-4abe-42dc-9745-06c6aec452f1/d15f15e7-4395-4b4c-abcf-e673d047fd29/VMware-PowerCLI-11.4.0-14413515.zip >> /tmp/myScript.txt
mkdir ~/powershell >> /tmp/myScript.txt
mkdir -p ~/.local/share/powershell/Modules >> /tmp/myScript.txt
tar -xvf ./powershell-7.0.0-preview.3-linux-x64.tar.gz  -C ~/powershell >> /tmp/myScript.txt
unzip VMware-PowerCLI-11.4.0-14413515.zip -d ~/.local/share/powershell/Modules >> /tmp/myScript.txt
echo "this has been written via cloud-init" + $(date) >> /tmp/myScript.txt
powershell/pwsh >> /tmp/myScript.txt
$PSVersionTable >> /tmp/myScript.txt
get-module -name VMware.PowerCLI -listavailable >> /tmp/myScript.txt
exit >> /tmp/myScript.txt

