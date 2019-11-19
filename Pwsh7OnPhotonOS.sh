#!/bin/sh
# Deploy Powershell Core v7.0.0-preview.5 on VMware Photon OS
#
# This script deploys Powershell Core v7.0.0-preview.5 on VMware Photon OS. To start Powershell simply enter "pwsh7p5".
#
#
# History
# 0.1  31.10.2019   dcasota  Initial release
# 0.11 19.11.2019   dcasota  comment line start pwsh corrected
#
# Prerequisites:
#    - VMware Photon OS 3.0
#    - No Powershell release installed
#    - Run as root
#
#
# Description:
# 'tndf install -y powershell' latest release is 6.1.0 and outdated (October 2019).
#    Powershell Core built-in installs the modules PackageManagement and PowerShellGet. Built-in means that automatic update functionality for its modules is included too.
#
# With Powershell Core 6.1.0 and above the built-in automatic update functionality often is broken. Cmdlets find-module, install-module, etc. produces errors.
# Unfortunately these issues are open for Powershell Core v7.0.0-preview.5, too. 
# There are a few workaround possibilities. Keep in mind, applying a workaround means that with specific modules not installed by using install-module, it cannot be updated.
# If this is not supported in your environment, use 'tdnf install -y powershell'. Sooner or later newer published releases are available.
# 
# This script provides a workaround solution. It downloads and installs Powershell Core 7p5 release, and saves necessary prerequisites in profile
#    /opt/microsoft/powershell/7.0.0-preview.5/profile.ps1.
#
#    Powershell is installed in /opt/microsoft/powershell/7.0.0-preview.5/ with a symbolic link "pwsh7p5" that points to /opt/microsoft/powershell/7.0.0-preview.5/pwsh.
#
#    Two workarounds are necessary to be saved in profile /opt/microsoft/powershell/7.0.0-preview.5/profile.ps1.
#       Each time pwsh7p5 is started the saved profile with the workarounds is loaded.
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
#
#    After the installation, the functionality of find-module, install-module, get-psrepository, etc. is back.
#
#
# Limitations / not tested:
# - More restrictive user privileges
# - Proxy functionality
# - Constellations with security protocol or certification check enforcement
# - Side effects with already installed powershell releases
#

# The methodology to describe PS variables has been adopted from
# https://github.com/PowerShell/PowerShell-Docker/blob/master/release/preview/fedora/docker/Dockerfile
export PS_VERSION=7.0.0-preview.5
export PACKAGE_VERSION=7.0.0-preview.5
export PS_PACKAGE=powershell-${PACKAGE_VERSION}-linux-x64.tar.gz
export PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
export PS_INSTALL_FOLDER=/opt/microsoft/powershell/$PS_VERSION
export PS_INSTALL_VERSION=7p5
export PS_SYMLINK=pwsh$PS_INSTALL_VERSION

# language setting
# See https://github.com/vmware/photon/issues/612#issuecomment-287897819

# Define env for localization/globalization
# See https://github.com/dotnet/corefx/blob/master/Documentation/architecture/globalization-invariant-mode.md
# Photon dotnet-runtime version is 2.2.0-1.ph3. So this fix isn't needed anymore. See https://github.com/microsoft/msbuild/issues/3066#issuecomment-372104257
# export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
# export LC_ALL=en_US.UTF-8
# export LANG=en_US.UTF-8


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