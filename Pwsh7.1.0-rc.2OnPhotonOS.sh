#!/bin/sh
# Deploy Powershell v7.1.0-rc.2 on VMware Photon OS
#
# This script deploys Powershell v7.1.0-rc.2 on VMware Photon OS. To start Powershell simply enter "pwsh7.1.0-rc.2".
#
#
# History
# 0.1  08.11.2020   dcasota  Initial release
#
# Prerequisites:
#    - VMware Photon OS 2.0 or above
#    - Run as root
#
#
# Description:
#
# See release info https://github.com/PowerShell/PowerShell/releases/tag/v7.1.0-rc.2
# See blog about PowerShell 7.0 https://devblogs.microsoft.com/powershell/announcing-powershell-7-0/ . There is no differenciation of "Core" anymore.
#
# On latest Photon 4.0 current powershell release is 7.0.0. Simply use 'tdnf install -y powershell'.
# On latest Photon 3.0 current powershell release is 7.0.0. Simply use 'tdnf install -y powershell'.
# On latest Photon 2.0 current powershell release is 6.2.0-preview.2-57. Simply use 'tdnf install -y powershell'.
#
# This script downloads and installs Powershell 7.1.0-rc.2 release.
#    Powershell is installed in /opt/microsoft/powershell/7.1.0-rc.2/ with a symbolic link "pwsh7.1.0-rc.2" that points to /opt/microsoft/powershell/7.1.0-rc.2/pwsh.
#
#    Especially when running on Photon OS 2.0, two workarounds are necessary to be saved in profile /opt/microsoft/powershell/7.1.0-rc.2/profile.ps1.
#       Without those you might run into following issues:
#       find-module VMware.PowerCLI
#       Find-Package: /opt/microsoft/powershell/7.1.0-rc.2/Modules/PowerShellGet/PSModule.psm1
#       Line |
#       8871 |         PackageManagement\Find-Package @PSBoundParameters | Microsoft.PowerShell.Core\ForEach-Object {
#            |         ^ No match was found for the specified search criteria and module name 'VMware.PowerCLI'. Try Get-PSRepository to see all
#            | available registered module repositories.
#    
#       get-psrepository
#       WARNING: Unable to find module repositories.
#    
#       Each time pwsh7.1.0-rc.2 is started the saved profile with the workarounds is loaded.
#       #https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-5.1&redirectedfrom=MSDN
#       Show variables of $PROFILE:
#       $PROFILE | Get-Member -Type NoteProperty
#
#       Workaround #1
#       https://github.com/PowerShell/PowerShellGet/issues/447#issuecomment-476968923
#       Change to TLS1.2
#       [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
#
#       Workaround #2
#       https://github.com/PowerShell/PowerShell/issues/9495#issuecomment-515592672
#       $env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
#
#    The reference installation procedure for pwsh on Linux was published on
#    https://docs.microsoft.com/en-us/powershell/scripting/install/installing-powershell-core-on-linux?view=powershell-7
#
# Provisioning:
#  sudo tdnf install -y curl unzip
#  curl -O -J -L https://github.com/dcasota/photonos-scripts/archive/master.zip
#  unzip ./photonos-scripts-master.zip 
#  cd ./photonos-scripts-master
#  sudo chmod a+x ./*.sh
#  sudo ./pwsh7.1.0-rc.2OnPhotonOS.sh
#
# Limitations / not tested:
# - More restrictive user privileges
# - Proxy functionality
# - Constellations with security protocol or certification check enforcement
# - Side effects with already installed powershell releases
#

# The methodology to describe PS variables has been adopted from
# https://github.com/PowerShell/PowerShell-Docker/blob/master/release/preview/fedora/docker/Dockerfile
export PS_VERSION=7.1.0-rc.2
export PACKAGE_VERSION=7.1.0-rc.2
export PS_PACKAGE=powershell-${PACKAGE_VERSION}-linux-x64.tar.gz
export PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
export PS_INSTALL_FOLDER=/opt/microsoft/powershell/$PS_VERSION
export PS_INSTALL_VERSION=7.1.0-rc.2
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

# Check functionality of powershell
OUTPUT=`$PS_INSTALL_FOLDER/pwsh -c "find-module VMware.PowerCLI"`
if ! (echo $OUTPUT | grep -q "PSGallery"); then
	cat <<EOFProfile > $PS_INSTALL_FOLDER/profile.ps1
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
\$env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0     
EOFProfile
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