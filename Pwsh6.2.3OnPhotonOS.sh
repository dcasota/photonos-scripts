#!/bin/sh
# Deploy Powershell Core 6.2.3 on VMware Photon OS
#
# This script deploys Powershell Core 6.2.3 on VMware Photon OS. To start Powershell simply enter "Pwsh6.2.3".
#
#
# History
# 0.1  28.10.2019   dcasota  UNFINISHED! WORK IN PROGRESS!
#
# Prerequisites:
#    - VMware Photon OS 3.0
#    - No Powershell release installed
#
#
# 'tndf install -y powershell' latest release is 6.1.0 and outdated (October 2019).
# Powershell Core built-in installs the modules PackageManagement and PowerShellGet. Built-in means that automatic update functionality for its modules is included too.
#
# With Powershell Core 6.1.0 release this built-in automatic update functionality is broken. Note that the cmdlets find-module and install-module produces errors.
# There are a few workaround possibilities. Keep in mind, applying a workaround means that with specific modules not installed by using install-module, it cannot be updated.
# If this is not supported in your environment, use 'tdnf install -y powershell'. Sooner or later newer published releases are available.
# 
# This script provides a workaround solution. It downloads and installs Powershell Core 6.2.3 release and installs the module PackageManagement 1.1.7.0.
#
# Powershell is installed in /opt/microsoft/powershell/6.2.3/ with a symbolic link "Pwsh6.2.3" that points to /opt/microsoft/powershell/6.2.3/pwsh.
#
# The built-in module PowerShellGet version 2.1.3 in Powershell Core 6.2.3 has a RequiredModules specification of PackageManagement 1.1.7.0.
# Using an embedded powershell script it installs PackageManagement 1.1.7.0.
# The dynamically created powershell script provides three helper functions used as cmdlets workaround:
# - workaround.Find-ModuleAllVersions
# - workaround.Save-Module
# - workaround.Install-NugetPkgOnLinux
# The powershell script allows to specify Package Management and PowerShellGet version. See '\$PackageManagementVersion="1.1.7.0"'.
#
# After the installation, the functionality of find-module, install-module, get-psrepository, etc. is back.
#
# Limitations:
# - side effects with already installed powershell releases not tested
# - proxy functionality not tested
# - various constellations with security protocol policies or with cert policies not tested
#

# install the requirements
tdnf install -y \
        tar \
        curl \
		libunwind \
		userspace-rcu \
		lttng-ust \
		icu \
		dotnet-runtime

cd /tmp

# install Powershell 6.2.3 
DownloadURL="https://github.com/PowerShell/PowerShell/releases/download/v6.2.3/powershell-6.2.3-linux-x64.tar.gz"
ReleaseDir="6.2.3"
PwshLink=Pwsh$ReleaseDir

ToInstall=true
if (`command -v pwsh`); then
	OUTPUT=`pwsh -c '$PSVersiontable'`
	if (!(echo $OUTPUT | grep -q "$ReleaseDir")); then
		ToInstall=false
	fi
fi
if [ -d /opt/microsoft/powershell/$ReleaseDir/pwsh ]; then
	OUTPUT=`/opt/microsoft/powershell/$ReleaseDir/pwsh -c '$PSVersiontable'`
	if (!(echo $OUTPUT | grep -q "$ReleaseDir")); then
		ToInstall=false
	fi
fi

if ("$ToInstall" = "true"); then
	# Download the powershell '.tar.gz' archive
	curl -L $DownloadURL -o /tmp/powershell.tar.gz
	# Create the target folder where powershell will be placed
	mkdir -p /opt/microsoft/powershell/$ReleaseDir
	# Expand powershell to the target folder
	tar zxf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/$ReleaseDir
	# Set execute permissions
	chmod +x /opt/microsoft/powershell/$ReleaseDir/pwsh
	# Create the symbolic link that points to pwsh
	ln -s /opt/microsoft/powershell/$ReleaseDir/pwsh /usr/bin/$PwshLink
	# delete downloaded file
	rm /tmp/powershell.tar.gz


	RunEmbeddedScript=true
	OUTPUT=`/opt/microsoft/powershell/$ReleaseDir/pwsh -c 'get-psrepository'`
	if (echo $OUTPUT | grep -q "PSGallery"); then
		echo "$ReleaseDir: PSGallery is registered."
		# Check: PSGallery is browseable using "find-module".
		OUTPUT=`/opt/microsoft/powershell/$ReleaseDir/pwsh -c "find-module VMware.PowerCLI"`
		if (echo $OUTPUT | grep -q "PSGallery"); then
			echo "$ReleaseDir: PSGallery is browseable."
			echo "$ReleaseDir: All provisioning tests successfully processed."
			RunEmbeddedScript=false
		else
			echo "ERROR: PSGallery not detected as browseable."
		fi		
	else
		echo "PSGallery not detected as registered."
	fi

	if ("$RunEmbeddedScript" = "true"); then
	
# Prepare helper functions content
IFS='' read -r -d '' PSContent1 << "EOF1"
function LogfileAppend($text)
{
	$TimeStamp = (get-date).ToString('dd.MM.yyyy HH:mm:ss.fff')
	Write-Host $TimeStamp  $text
}
EOF1


IFS='' read -r -d '' PSContent2 << "EOF2"
function workaround.Find-ModuleAllVersions
{
	# https://stackoverflow.com/questions/37486587/powershell-v5-how-to-install-modules-to-a-computer-having-no-internet-connecti
	# https://github.com/PowerShell/PowerShellGet/issues/171
	param (
		$Name,
		$proxy,
		$version)
		
	# https://github.com/PowerShell/PowerShell/issues/7827 See comment Iyoumans
	$env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0
	# [System.AppContext]::SetSwitch("System.Net.Http.UseSocketsHttpHandler", $false)
	
	if (([string]::IsNullOrEmpty($proxy)) -eq $true)
	{
		if (($version -eq "") -or ($version -eq $null))
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
EOF2


IFS='' read -r -d '' PSContent3 << "EOF3"
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
	
	# https://github.com/PowerShell/PowerShell/issues/7827 See comment Iyoumans
	$env:DOTNET_SYSTEM_NET_HTTP_USESOCKETSHTTPHANDLER=0	
	# [System.AppContext]::SetSwitch("System.Net.Http.UseSocketsHttpHandler", $false)
	
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
EOF3

IFS='' read -r -d '' PSContent4 << "EOF4"
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
		LogfileAppend("VersionString = $VersionString")
		
		if ($VersionString -imatch $PackageVersion)
		{
			LogfileAppend("Unzipping $Sourcefile to $destinationpath ...")	
			unzip -o $Sourcefile -d $destinationpath		
			chmod -R 755 $(find $destinationpath -type d)
			chmod -R 644 $(find $destinationpath -type f)
			
			LogfileAppend("Removing $sourcefile ...")
			remove-item -path ($Sourcefile) -force -recurse -confirm:$false
			
			get-childitem -path $destinationpath -recurse -filter *.psd1| ? {
				$TmpFile = $destinationpath + $PathDelimiter + $_.Name
				try {
					LogfileAppend("Import $TmpFile ...")			
					import-module -name $TmpFile -Scope Global -Verbose -force -erroraction silentlycontinue
				} catch {}
			}
		}
	}
	catch { }
	return ($destinationpath)
}


# Requires Run with root privileges

#Run first
#get-module
#get-module -listavailable

# https://powershell.org/forums/topic/is-it-possible-to-enable-tls-1-2-as-default-in-powershell/
# Verify current TLS support of powershell as after Powershell installation the TLS support is SystemDefault 
[Net.ServicePointManager]::SecurityProtocol
# Change to TLS1.2
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# Verify again current TLS support of powershell
[Net.ServicePointManager]::SecurityProtocol
EOF4

IFS='' read -r -d '' PSContent5 << "EOF5"
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
		LogfileAppend("Installing Packagemanagement release $PackageManagementVersion ...")
		$rc = workaround.Find-ModuleAllVersions -name packagemanagement -version "$PackageManagementVersion" | workaround.Save-Module -Path "$PSHome/Modules"
		LogfileAppend("Installing Packagemanagement release $PackageManagementVersion : return code $rc")				
		$rc = workaround.Install-NugetPkgOnLinux "PackageManagement" "$PackageManagementVersion" $rc.name "$PSHome/Modules" "$PSHome/Modules"
		LogfileAppend("Installing Packagemanagement release $PackageManagementVersion done : return code $rc")
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
		LogfileAppend("Installing PowerShellGet release $PowerShellGetVersion ...")
		$rc = workaround.Find-ModuleAllVersions -name PowerShellGet -version "$PowerShellGetVersion" | workaround.Save-Module -Path "$PSHome/Modules"
		LogfileAppend("Installing PowerShellGet release $PowerShellGetVersion : return code $rc")				
		$rc = workaround.Install-NugetPkgOnLinux "PowerShellGet" "$PowerShellGetVersion" $rc.name "$PSHome/Modules" "$PSHome/Modules"
		LogfileAppend("Installing PowerShellGet release $PowerShellGetVersion done : return code $rc")
	}				
}
catch { }
# if ((Get-PSRepository -name psgallery | %{ $_.InstallationPolicy -match "Untrusted" }) -eq $true) { set-psrepository -name PSGallery -InstallationPolicy Trusted }
EOF5


	
# PowerShellGet release 2.1.3 has RequiredModules specification of PackageManagement 1.1.7.0. Use the helper functions to install modules.			
cat <<EOF1170213 > /tmp/tmp1.ps1
# Post-installation for PowerShell 6.2.3
$PSContent1
$PSContent2
$PSContent3
$PSContent4
\$PackageManagementVersion="1.1.7.0"
\$PowerShellGetVersion="2.1.3"
$PSContent5
get-psrepository
find-module VMware.PowerCLI
Get-Module -ListAvailable | Import-Module
find-module VMware.PowerCLI
EOF1170213
$PwshLink -c '/tmp/tmp1.ps1' -WorkingDirectory /tmp

# Now import all available modules in the path specified by the PSModulePath environment variable
# $PwshLink -c 'Get-Module -ListAvailable | Import-Module'
# rm /tmp/tmp1.ps1

OUTPUT=`/opt/microsoft/powershell/$ReleaseDir/pwsh -c 'get-psrepository'`
if (echo $OUTPUT | grep -q "PSGallery"); then
	echo "$ReleaseDir: PSGallery is registered."	
	# Check: PSGallery is browseable using "find-module".
	OUTPUT=`/opt/microsoft/powershell/$ReleaseDir/pwsh -c "find-module VMware.PowerCLI"`
	if (echo $OUTPUT | grep -q "PSGallery"); then
		echo "$ReleaseDir: PSGallery is browseable."
		echo "$ReleaseDir: All provisioning tests successfully processed."
	else
		echo "ERROR: PSGallery not detected as browseable."
	fi		
else
	echo "PSGallery not detected as registered."
fi


fi

fi

# Cleanup
tdnf clean all

# Uninstall
# rm /usr/bin/$PwshLink
# rm -r /opt/microsoft/powershell/$ReleaseDir
# rm -r /tmp/Microsoft.PackageManagement
# Uninstall of all powershell releases
# rm /usr/bin/Pwsh*
# rm -r /opt/microsoft/powershell
# rm -r /root/.cache/powershell
# rm -r /root/.local/share/powershell
# rm -r /usr/local/share/powershell
# rm -r /var/share/powershell