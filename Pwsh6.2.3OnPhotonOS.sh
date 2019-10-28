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
        # locales \
        # libicu63 \
        # libssl1.1 \
        # libc6 \
        # libgcc1 \
        # libgssapi-krb5-2 \
        # liblttng-ust0 \
        # libstdc++6 \
        # zlib1g


# Download the powershell '.tar.gz' archive
curl -L https://github.com/PowerShell/PowerShell/releases/download/v6.1.6/powershell-6.1.6-linux-x64.tar.gz -o /tmp/powershell.tar.gz

# Create the target folder where powershell will be placed
sudo mkdir -p /opt/microsoft/powershell/6.2.3

# Expand powershell to the target folder
sudo tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/6.2.3

# Set execute permissions
sudo chmod +x /opt/microsoft/powershell/6.2.3/pwsh

# Create the symbolic link that points to pwsh
sudo ln -s /opt/microsoft/powershell/6.2.3/pwsh /usr/bin/pwsh6.2.3

pwsh6.2.3 -c "get-psrepository"

# Uninstall
rm /tmp/powershell.tar.gz
# rm /usr/bin/pwsh6.2.3
# rm -r ./opt/microsoft/powershell/6.2.3
# Check if no other powershell release is installed which uses the following directories
# rm -r ./root/.cache/powershell
# rm -r ./opt/microsoft/powershell
# rm -r ./root/.local/share/powershell
# rm -r ./usr/local/share/powershell




