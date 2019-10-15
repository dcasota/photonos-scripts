#!/bin/sh
# Deploy Powershell7 on VMware Photon OS
#
# This script deploys Powershell7 (Preview4) on VMware Photon OS.
# The reference installation procedure for Pwsh7 on Linux was published on
# https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7
#
#
# History
# 0.1  15.10.2019   dcasota  Initial release
#
# Prerequisites:
#    VMware Photon OS 3.0
#
# 

tdnf -y update

# install the requirements
tdnf install -y \
        less \
        ca-certificates \
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
curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.4/powershell-7.0.0-preview.4-linux-x64.tar.gz -o /tmp/powershell.tar.gz

# Create the target folder where powershell will be placed
sudo mkdir -p /opt/microsoft/powershell/7-preview

# Expand powershell to the target folder
sudo tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7-preview

# Set execute permissions
sudo chmod +x /opt/microsoft/powershell/7-preview/pwsh

# Create the symbolic link that points to pwsh
sudo ln -s /opt/microsoft/powershell/7-preview/pwsh /usr/bin/pwsh-preview

# Start PowerShell
pwsh-preview



