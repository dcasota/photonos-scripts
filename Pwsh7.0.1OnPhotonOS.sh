#!/bin/sh
# Deploy Powershell v7.0.1 on VMware Photon OS
#
# This script deploys Powershell v7.0.1 on VMware Photon OS. To start Powershell simply enter "pwsh7.0.1".
#
#
# History
# 0.1  08.03.2020   dcasota  Initial release
#
# Prerequisites:
#    - VMware Photon OS 3.0
#    - Run as root
#
#
# Description:
#
# See blog about PowerShell 7.0 https://devblogs.microsoft.com/powershell/announcing-powershell-7-0/ . There is no differenciation of "Core" anymore.
#
# On Photon 'tndf install -y powershell' latest release is 6.2.3.
# This script downloads and installs Powershell 7 release.
#    Powershell is installed in /opt/microsoft/powershell/7.0.1/ with a symbolic link "pwsh7" that points to /opt/microsoft/powershell/7.0.1/pwsh.
#
# Limitations / not tested:
# - More restrictive user privileges
# - Proxy functionality
# - Constellations with security protocol or certification check enforcement
# - Side effects with already installed powershell releases
#

# The methodology to describe PS variables has been adopted from
# https://github.com/PowerShell/PowerShell-Docker/blob/master/release/preview/fedora/docker/Dockerfile
export PS_VERSION=7.0.1
export PACKAGE_VERSION=7.0.1
export PS_PACKAGE=powershell-${PACKAGE_VERSION}-linux-x64.tar.gz
export PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
export PS_INSTALL_FOLDER=/opt/microsoft/powershell/$PS_VERSION
export PS_INSTALL_VERSION=7.0.1
export PS_SYMLINK=pwsh$PS_INSTALL_VERSION

# set a fixed location for the Module analysis cache
# Powershell on Linux produces a few log files named with Core* with entries like 'invalid device'. These are from unhandled Module Analysis Cache Path.
#    On Windows: See https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_5.1?view=powershell-5.1
#       By default, this cache is stored in the file ${env:LOCALAPPDATA}\Microsoft\Windows\PowerShell\ModuleAnalysisCache. 
#    On Linux: See issue https://github.com/PowerShell/PowerShell-Docker/issues/61
# 	    Set up PowerShell module analysis cache path and wait for its creation after powershell installation
#       PSModuleAnalysisCachePath=/var/cache/microsoft/powershell/PSModuleAnalysisCache/ModuleAnalysisCache
export PSModuleAnalysisCachePath=/var/cache/microsoft/powershell/PSModuleAnalysisCache/ModuleAnalysisCache
	
# install dependencies
tdnf install -y \
        tar \
        curl \
		libunwind \
		userspace-rcu \
		lttng-ust \
		icu \
		dotnet-runtime

cd /tmp

# Install powershell
if ! [ -d $PS_INSTALL_FOLDER/pwsh ]; then
	# Download the powershell '.tar.gz' archive
	curl -L $PS_PACKAGE_URL -o /tmp/powershell.tar.gz
	# Create the target folder where powershell will be placed
	mkdir -p $PS_INSTALL_FOLDER
	# Expand powershell to the target folder
	tar zxf /tmp/powershell.tar.gz -C $PS_INSTALL_FOLDER
	# Set execute permissions
	chmod +x $PS_INSTALL_FOLDER/pwsh
	# Create the symbolic link that points to pwsh
	ln -s $PS_INSTALL_FOLDER/pwsh /usr/bin/$PS_SYMLINK
	# delete downloaded file
	rm /tmp/powershell.tar.gz
	# set a fixed location for the Module analysis cache and initialize powerShell module analysis cache
	$PS_SYMLINK \
        -NoLogo \
        -NoProfile \
        -Command " \
          \$ErrorActionPreference = 'Stop' ; \
          \$ProgressPreference = 'SilentlyContinue' ; \
          while(!(Test-Path -Path \$env:PSModuleAnalysisCachePath)) {  \
            Write-Host "'Waiting for $env:PSModuleAnalysisCachePath'" ; \
            Start-Sleep -Seconds 6 ; \
          }"	
fi

# Cleanup
tdnf clean all

# Uninstall
# rm /usr/bin/$PS_SYMLINK
# rm -r $PS_INSTALL_FOLDER
# Uninstall of all powershell releases
# rm /usr/bin/pwsh*
# rm -r /opt/microsoft/powershell
# rm -r /root/.cache/powershell
# rm -r /root/.local/share/powershell
# rm -r /usr/local/share/powershell
# rm -r /var/share/powershell
# rm -r /var/cache/microsoft/powershell