#!/bin/sh
# Deploy Powershell Core 6.1.1 on VMware Photon OS
#
# This script installs built-in Powershell Core 6.1.0 package on VMware Photon OS and adds modules PackageManagement and PowerShellGet . To start Powershell simply enter "pwsh".
#
#
# History
# 0.1  01.11.2019   dcasota  Initial release
#
# Prerequisites:
#    - VMware Photon OS 3.0
#    - No Powershell release installed
#    - Run as root
#
#
# Description:
#    The Windows Powershell 6.1.1 version includes modules PowerShellGet 1.6.7 and PackageManagement 1.1.7.2. Hence, the embedded powershell script installs
#    PackageManagement 1.1.7.0 and PowerShellGet 2.1.3 to add the functionality of find-module, install-module, get-psrepository, etc.
#    The embedded powershell script provides three helper functions used as cmdlets workaround:
#    - workaround.Find-ModuleAllVersions
#    - workaround.Save-Module
#    - workaround.Install-NugetPkgOnLinux
#    The powershell script allows to specify Package Management and PowerShellGet version. See '\$PackageManagementVersion="1.1.7.2"'.
#
#    Two workarounds are necessary to be saved in $PROFILE (/root/.config/powershell/Microsoft.PowerShell_profile.ps1).
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
#
#    After the installation, the functionality of find-module, install-module, get-psrepository, etc. is added.
#
# Limitations / not tested:
# - More restrictive user privileges
# - Proxy functionality
# - Constellations with security protocol or certification check enforcement
# - Side effects with already installed powershell releases
#

# language setting
# See https://github.com/vmware/photon/issues/612#issuecomment-287897819

# Define env for localization/globalization
# See https://github.com/dotnet/corefx/blob/master/Documentation/architecture/globalization-invariant-mode.md
export DOTNET_SYSTEM_GLOBALIZATION_INVARIANT=false
# export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# set a fixed location for the Module analysis cache
# Powershell on Linux produces a few log files named with Core* with entries like 'invalid device'. These are from unhandled Module Analysis Cache Path.
#    On Windows: See https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_windows_powershell_5.1?view=powershell-5.1
#       By default, this cache is stored in the file ${env:LOCALAPPDATA}\Microsoft\Windows\PowerShell\ModuleAnalysisCache. 
#    On Linux: See issue https://github.com/PowerShell/PowerShell-Docker/issues/61
# 	    Set up PowerShell module analysis cache path and wait for its creation after powershell installation
#       PSModuleAnalysisCachePath=/var/cache/microsoft/powershell/PSModuleAnalysisCache/ModuleAnalysisCache
export PSModuleAnalysisCachePath=/var/cache/microsoft/powershell/PSModuleAnalysisCache/ModuleAnalysisCache
	
# install powershell
tdnf install -y \
        tar \
        curl \
		libunwind \
		userspace-rcu \
		lttng-ust \
		icu \
		dotnet-runtime \
		powershell

export PS_INSTALL_FOLDER=/usr/lib/powershell
export PS_SYMLINK=pwsh


# Install powershell
if ! [ -d $PS_INSTALL_FOLDER/pwsh ]; then
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
			echo Unzipping $Sourcefile to $destinationpath
			unzip -o $Sourcefile -d $destinationpath		
			chmod -R 755 $(find $destinationpath -type d)
			chmod -R 644 $(find $destinationpath -type f)
			
			echo Removing $sourcefile
			# remove-item -path ($Sourcefile) -force -recurse -confirm:$false
			
			echo Filter and import all .psd1 files
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


	# PowerShellGet release 1.6.7 has RequiredModules specification of PackageManagement 1.1.7.2.
	# The dynamically created powershell script contains helper functions which install the specified release of the modules.
	tmpfile=/tmp/tmp1.ps1		
	cat <<EOF1170213 > $tmpfile
# 
$PSContent1
$PSContent2
$PSContent3
\$PackageManagementVersion="1.1.7.2"
\$PowerShellGetVersion="1.6.7"
$PSContent4     
EOF1170213
	#$PS_SYMLINK -c $tmpfile -WorkingDirectory /tmp
	#rm $tmpfile

fi


# Cleanup
tdnf clean all

# Uninstall
# tdnf remove -y powershell 
# rm -r /root/.config/powershell
# rm -r /root/.cache/powershell
# rm -r /root/.local/share/powershell