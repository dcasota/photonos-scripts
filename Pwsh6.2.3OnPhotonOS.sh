#!/bin/sh
# Deploy Powershell Core 6.2.3 on VMware Photon OS
#
# This script deploys Powershell Core 6.2.3 on VMware Photon OS. To start Powershell simply enter "pwsh6.2.3".
#
#
# History
# 0.1  28.10.2019   dcasota  Initial release
# 0.2  31.10.2019   dcasota  added more information
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
#    Unfortunately these issues are open for Powershell Core 6.2.3, too. 
#    There are a few workaround possibilities. Keep in mind, applying a workaround means that with specific modules not installed by using install-module, it cannot be updated.
#    If this is not supported in your environment, use 'tdnf install -y powershell'. Sooner or later newer published releases are available.
# 
# This script provides a workaround solution. It downloads and installs Powershell Core 6.2.3 release, installs the module PackageManagement 1.1.7.0 and saves
#    necessary prerequisites in profile /opt/microsoft/powershell/6.2.3/profile.ps1.
#
#    Powershell is installed in /opt/microsoft/powershell/6.2.3/ with a symbolic link "pwsh6.2.3" that points to /opt/microsoft/powershell/6.2.3/pwsh.
#
#    The built-in module PowerShellGet version 2.1.3 in Powershell Core 6.2.3 has a RequiredModules specification of PackageManagement 1.1.7.0.
#    The embedded powershell script installs PackageManagement 1.1.7.0. It provides three helper functions used as cmdlets workaround:
#    - workaround.Find-ModuleAllVersions
#    - workaround.Save-Module
#    - workaround.Install-NugetPkgOnLinux
#    The powershell script allows to specify Package Management and PowerShellGet version. See '\$PackageManagementVersion="1.1.7.0"'.
#
#    Two workarounds are necessary to be saved in profile /opt/microsoft/powershell/6.2.3/profile.ps1.
#       Each time pwsh6.2.3 is started the saved profile with the workarounds is loaded.
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
# Limitations / not tested:
# - More restrictive user privileges
# - Proxy functionality
# - Constellations with security protocol or certification check enforcement
# - Side effects with already installed powershell releases
#

# The methodology to describe PS variables has been adopted from
# https://github.com/PowerShell/PowerShell-Docker/blob/master/release/preview/fedora/docker/Dockerfile
export PS_VERSION=6.2.3
export PACKAGE_VERSION=6.2.3
export PS_PACKAGE=powershell-${PACKAGE_VERSION}-linux-x64.tar.gz
export PS_PACKAGE_URL=https://github.com/PowerShell/PowerShell/releases/download/v${PS_VERSION}/${PS_PACKAGE}
export PS_INSTALL_FOLDER=/opt/microsoft/powershell/$PS_VERSION
export PS_INSTALL_VERSION=6.2.3
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
	# Delete downloaded file
	rm /tmp/powershell.tar.gz
	# Initialize powerShell module analysis cache
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
	
    # Prepare helper functions content
    # Remark: Embedding the complete powershell script in one single variable gave some errors. Therefore it is separated in 4 scriptblock variables PSContent1 to PSContent4.
IFS='' read -r -d '' PSContent1 << "EOF1"
function workaround.Find-ModuleAllVersions
{
	# https://stackoverflow.com/questions/37486587/powershell-v5-how-to-install-modules-to-a-computer-having-no-internet-connecti
	# https://github.com/PowerShell/PowerShellGet/issues/171
	param (
		$Name,
		$proxy,
		$version)
		
	# invoke-restmethod doesn't work correctly without $env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
	# https://github.com/PowerShell/PowerShell/issues/7827 See comment Iyoumans
	$env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
	
	if (([string]::IsNullOrEmpty($proxy)) -eq $true)
	{
		if (([string]::IsNullOrEmpty($version)) -eq $true)
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name'" -SslProtocol Tls -SkipCertificateCheck |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
		else
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name' and Version eq '$version'" -SslProtocol Tls -SkipCertificateCheck |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
	}
	else
	{
		if (([string]::IsNullOrEmpty($version)) -eq $true)
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name'" -proxy $proxy -ProxyUseDefaultCredentials -SslProtocol Tls -SkipCertificateCheck |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
		else
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name' and Version eq '$version'" -proxy $proxy -ProxyUseDefaultCredentials -SslProtocol Tls -SkipCertificateCheck |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
	}
}
EOF1


IFS='' read -r -d '' PSContent2 << "EOF2"
function workaround.Save-Module
{
	param (
		[Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
		$Name,
		[Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $true)]
		$Uri,
		[Parameter(ValueFromPipelineByPropertyName = $true)]
		$Version = "",
		[string]$Path = $pwd,
		[Parameter(ValueFromPipelineByPropertyName = $true, Mandatory = $false)]
		$proxy
	)
	$Path = (Join-Path $Path "$Name.$Version.nupkg")
	
	# invoke-webrequest doesn't work correctly without $env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
	# https://github.com/PowerShell/PowerShell/issues/7827 See comment Iyoumans
	$env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
	
	if ((get-command -name invoke-webrequest) -ne $null)
	{
		if (([string]::IsNullOrEmpty($proxy)) -eq $true) { Invoke-WebRequest $Uri -OutFile $Path -SslProtocol Tls -SkipCertificateCheck -ErrorAction SilentlyContinue }
		else { Invoke-WebRequest $Uri -OutFile $Path -proxy $proxy -ProxyUseDefaultCredentials -SslProtocol Tls -SkipCertificateCheck -ErrorAction SilentlyContinue}
	}
	else
	{
		$webclient = new-object system.net.webclient
		$webclient.downloadfile($Uri, $Path)
	}
	$rc = Get-Item $Path
	return $rc
}
EOF2

IFS='' read -r -d '' PSContent3 << "EOF3"
function workaround.Install-NugetPkgOnLinux
{
	param (
		[parameter(Mandatory = $true)]
		[string]$PackageName,
		[parameter(Mandatory = $true)]
		[string]$PackageVersion,
		[parameter(Mandatory = $true)]
		[string]$filename,
		[parameter(Mandatory = $true)]
		[string]$sourcepath,
		[parameter(Mandatory = $true)]
		[string]$destination
	)
	$destinationspace = $destination
	
	$PathDelimiter="/"
	
	try
	{
		$PackageFileName = ([System.IO.Path]::GetFileNameWithoutExtension($filename))
		$SourceFile = $sourcepath + $PathDelimiter + $filename
		$destinationpath = $destination + $PathDelimiter + $PackageName + $PathDelimiter + $PackageVersion
				
        $i = 1
        $VersionString=""
        for ($i;$i -le (-1 + ($PackageFileName.split(".")).count);$i++)
        {
            if ($Versionstring -eq "") {$Versionstring = ($PackageFileName.split("."))[$i]}
            else { $VersionString = $VersionString + "." + ($PackageFileName.split("."))[$i]}
        }
		
		if ($VersionString -imatch $PackageVersion)
		{
			# Unzipping $Sourcefile to $destinationpath	
			unzip -o $Sourcefile -d $destinationpath		
			chmod -R 755 $(find $destinationpath -type d)
			chmod -R 644 $(find $destinationpath -type f)
			
			# Removing $sourcefile
			remove-item -path ($Sourcefile) -force -recurse -confirm:$false
			
			# Filter and import all .psd1 files
			get-childitem -path $destinationpath -recurse -filter *.psd1| ? {
				$TmpFile = $destinationpath + $PathDelimiter + $_.Name
				try {		
					import-module -name $TmpFile -Scope Global -force -erroraction silentlycontinue
				} catch {}
			}
		}
	}
	catch { }
	return ($destinationpath)
}

# https://github.com/PowerShell/PowerShellGet/issues/447#issuecomment-476968923 , https://powershell.org/forums/topic/is-it-possible-to-enable-tls-1-2-as-default-in-powershell/
# Verify current TLS support of powershell as after Powershell installation the TLS support is SystemDefault 
# [Net.ServicePointManager]::SecurityProtocol
# Change to TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Current TLS support of powershell
# [Net.ServicePointManager]::SecurityProtocol
EOF3

IFS='' read -r -d '' PSContent4 << "EOF4"
try
{
	$InstallPackageManagement = $false
	if (((get-module -name packagemanagement -listavailable -ErrorAction SilentlyContinue) -eq $null) -and ((get-module -name packagemanagement -ErrorAction SilentlyContinue) -eq $null)) { $InstallPackagemanagement = $true }
	else
	{
		$tmpvalue=get-module -name packagemanagement
		if (([string]::IsNullOrEmpty($tmpvalue)) -eq $true) {$tmpvalue=get-module -name packagemanagement -listavailable }
		try {
			if (!(($tmpvalue).version | ? { $_.tostring() -imatch "$PackageManagementVersion" })) { $InstallPackageManagement = $true } #psversiontable = 4 bedingt mit ohne -listavailable
		} catch {}
	}
	if ($InstallPackagemanagement -eq $true)
	{
		# Install Packagemanagement release $PackageManagementVersion
		$rc = workaround.Find-ModuleAllVersions -name packagemanagement -version "$PackageManagementVersion" | workaround.Save-Module -Path "$PSHome/Modules"			
		$rc = workaround.Install-NugetPkgOnLinux "PackageManagement" "$PackageManagementVersion" $rc.name "$PSHome/Modules" "$PSHome/Modules"
	}

	$InstallPowerShellGet = $false
	if (((get-module -name PowerShellGet -listavailable -ErrorAction SilentlyContinue) -eq $null) -and ((get-module -name PowerShellGet -ErrorAction SilentlyContinue) -eq $null)) { $InstallPowerShellGet = $true }
	else
	{
		$tmpvalue=get-module -name PowerShellGet
		if (([string]::IsNullOrEmpty($tmpvalue)) -eq $true) {$tmpvalue=get-module -name PowerShellGet -listavailable }
		try {
			if (!(($tmpvalue).version | ? { $_.tostring() -imatch "$PowerShellGetVersion" })) { $InstallPowerShellGet = $true } #psversiontable = 4 bedingt mit ohne -listavailable
		} catch {}
	}
	if ($InstallPowerShellGet -eq $true)
	{
		# InstallPowerShellGet release $PowerShellGetVersion
		$rc = workaround.Find-ModuleAllVersions -name PowerShellGet -version "$PowerShellGetVersion" | workaround.Save-Module -Path "$PSHome/Modules"			
		$rc = workaround.Install-NugetPkgOnLinux "PowerShellGet" "$PowerShellGetVersion" $rc.name "$PSHome/Modules" "$PSHome/Modules"
	}				
}
catch { }
# if ((Get-PSRepository -name psgallery | %{ $_.InstallationPolicy -match "Untrusted" }) -eq $true) { set-psrepository -name PSGallery -InstallationPolicy Trusted }
EOF4


	# PowerShellGet release 2.1.3 has RequiredModules specification of PackageManagement 1.1.7.0.
	# The dynamically created powershell script contains helper functions which install the specified release of the modules.
	tmpfile=/tmp/tmp1.ps1		
	cat <<EOF1170213 > $tmpfile
# 
$PSContent1
$PSContent2
$PSContent3
\$PackageManagementVersion="1.1.7.0"
\$PowerShellGetVersion="2.1.3"
$PSContent4     
EOF1170213
	$PS_SYMLINK -c $tmpfile -WorkingDirectory /tmp
	rm $tmpfile

	# Two workarounds must be saved in profile /opt/microsoft/powershell/$ReleaseDir/profile.ps1.
	# Each time Pwsh$ReleaseDir is started the saved profile with the workarounds is loaded.
	# #https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_profiles?view=powershell-5.1&redirectedfrom=MSDN
	# Show variables of $PROFILE:
	# $PROFILE | Get-Member -Type NoteProperty
	#
	# Workaround #1
	# https://github.com/PowerShell/PowerShellGet/issues/447#issuecomment-476968923
	# Change to TLS1.2
	# [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
	#
	# Workaround #2
	# https://github.com/PowerShell/PowerShell/issues/9495#issuecomment-515592672
	# $env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0  
	#
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