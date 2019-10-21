# Dockerfile for Powershell Core 7.0.0 (Beta 4) and with PSGallery
#
# PowerShell Core on Linux is supported since release 6.x.
# Installing PowerShell Core as example on VMware Photon OS does not built-in register PSGallery or nuget.org as source provider.
# One way to accomplish it is using a tool from the Microsoft open source Nuget ecosystem.
# See https://docs.microsoft.com/en-us/nuget/policies/ecosystem, https://docs.microsoft.com/en-us/nuget/nuget-org/licenses.nuget.org
#
# See https://docs.microsoft.com/en-us/nuget/install-nuget-client-tools
# "The nuget.exe CLI, nuget.exe, is the command-line utility for Windows that provides all NuGet capabilities;"
# "it can also be run on Mac OSX and Linux using Mono with some limitations."
# The powershellgallery registration is an oneliner: mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"
# 
# The mono dockerfile related part original is from
# https://github.com/mono/docker/blob/master/6.4.0.198/Dockerfile
# It uses Debian as OS and downloads and builds Mono.
#
# The original installation procedure for Pwsh7 on Linux is from
# https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7
#
# Remark: Build time may take 15-20 minutes.
#
#
# ---------------------------------------------------------------
FROM mono:6.4.0.198-slim

ENV TERM linux

WORKDIR /root

# Set terminal. If we don't do this, weird readline things happen.
RUN apt-get update && \
    apt-get install -y binutils curl mono-devel ca-certificates-mono fsharp mono-vbnc nuget referenceassemblies-pcl && \
    rm -rf /var/lib/apt/lists/* /tmp/* && \
    curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/v5.2.0/nuget.exe && \
	curl -L https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.4/powershell-7.0.0-preview.4-linux-x64.tar.gz -o /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7-preview && \
    tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7-preview && \
    chmod +x /opt/microsoft/powershell/7-preview/pwsh && \
    ln -s /opt/microsoft/powershell/7-preview/pwsh /usr/bin/pwsh-preview && \
    rm /tmp/powershell.tar.gz


CMD ["/usr/bin/pwsh-preview"]