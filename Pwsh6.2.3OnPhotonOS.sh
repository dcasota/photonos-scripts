#!/bin/sh
# Deploy Powershell Core 6.2.3 on VMware Photon OS
#
# This script deploys Powershell Core 6.2.3 on VMware Photon OS.
#
# The reference installation procedure is based on Pwsh7 on Linux and was published at
# https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7
# 
#
#
#
# History
# 0.1  28.10.2019   dcasota  UNFINISHED! WORK IN PROGRESS!
#
# Prerequisites:
#    VMware Photon OS 3.0
#
# 

# install the requirements
tdnf install -y \
        tar \
        curl
		
$DownloadURL="https://github.com/PowerShell/PowerShell/releases/download/v6.2.3/powershell-6.2.3-linux-x64.tar.gz"
$ReleaseDir="6.2.3"
$PwshLink=Pwsh$ReleaseDir

# Download the powershell '.tar.gz' archive
curl -L $DownloadURL -o /tmp/powershell.tar.gz

# Create the target folder where powershell will be placed
sudo mkdir -p /opt/microsoft/powershell/$ReleaseDir

# Expand powershell to the target folder
sudo tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/$ReleaseDir

# Set execute permissions
sudo chmod +x /opt/microsoft/powershell/$ReleaseDir/pwsh

# Create the symbolic link that points to pwsh
sudo ln -s /opt/microsoft/powershell/$ReleaseDir/pwsh /usr/bin/$PwshLink

$PwshLink -c "get-psrepository"

# Uninstall
rm /tmp/powershell.tar.gz
# rm /usr/bin/$PwshLink
# rm -r ./opt/microsoft/powershell/$ReleaseDir
# Check if no other powershell release is installed which uses the following directories
# rm -r ./root/.cache/powershell
# rm -r ./opt/microsoft/powershell
# rm -r ./root/.local/share/powershell
# rm -r ./usr/local/share/powershell




