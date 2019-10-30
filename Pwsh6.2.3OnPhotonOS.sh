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
# Powershell Core built-in provisions the modules PackageManagement and PowerShellGet. Built-in means that automatic update functionality for its modules is included too.
#
# With Powershell Core 6.1.0 release this built-in automatic update functionality is broken. Note that the cmdlets find-module and install-module produces errors.
# There are a few workaround possibilities. Keep in mind, applying a workaround means that with specific modules not installed by using install-module, it cannot be updated.
# If this is not supported in your environment, use the 'tdnf install -y powershell' release. Sooner or later newer published releases are available.
# 
# This script provides a workaround solution. It downloads and installs Powershell Core 6.2.3 release and installs the module PackageManagement 1.1.7.0.
#
# Powershell is installed in /opt/microsoft/powershell/6.2.3/ and creates a symbolic link "Pwsh6.2.3" that points to /opt/microsoft/powershell/6.2.3/pwsh.
#
# The built-in module PowerShellGet version 2.1.3 in Powershell Core 6.2.3 has a RequiredModules specification of PackageManagement 1.1.7.0.
# Hence, the script using an embedded powershell script installs PackageManagement 1.1.7.0.
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
OUTPUT=`$PwshLink -c '$PSVersiontable'`
if (!(echo $OUTPUT | grep -q "$ReleaseDir")); then
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

	OUTPUT=`$PwshLink -c "get-psrepository"`
	if (echo $OUTPUT | grep -q "PSGallery"); then
		echo "$PwshLink: PSGallery is registered."
		# Check: PSGallery is browseable using "find-module".
		OUTPUT=`$PwshLink -c "find-module VMware.PowerCLI"`
		if (echo $OUTPUT | grep -q "PSGallery"); then
			echo "$PwshLink: PSGallery is browseable."
			echo "$PwshLink: All provisioning tests successfully processed."
		else
			echo "ERROR: PSGallery not detected as browseable."
		fi		
	else
		echo "PSGallery not detected as registered."
	fi
fi
	
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
	if (($proxy -eq "") -or ($proxy -eq $null))
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
		if (($version -eq "") -or ($version -eq $null))
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
		if (($proxy -eq "") -or ($proxy -eq $null)) { Invoke-WebRequest $Uri -OutFile $Path -SslProtocol Tls -SkipCertificateCheck -ErrorAction SilentlyContinue }
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
			
			chmod 755 $destinationpath/*
			
			LogfileAppend("Removing $sourcefile ...")
			remove-item -path ($Sourcefile) -force -recurse -confirm:$false
			
			get-childitem -path $destinationpath -recurse -filter *.psd1| ? {
				$TmpFile = $destinationpath + $PathDelimiter + $_.Name
				try {
					LogfileAppend("importing-name $TmpFile ...")			
					import-module -name $TmpFile -Global -Scope Global -Verbose -force -erroraction silentlycontinue
				} catch {}
			}
		}
	}
	catch { }
	return ($destinationpath)
}


# Requires Run with root privileges
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$PwshGalleryInstalled = $false
EOF4

IFS='' read -r -d '' PSContent5 << "EOF5"
try
{
	LogfileAppend("Check get-psrepository ...")
	#TODO
	if ($PwshGalleryInstalled -eq $false)
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
			if (test-path("$PSHome/Modules/PackageManagement")) {
				# rm -r -fo "$PSHome/Modules/PackageManagement" #do not delete it might be a previous version without version number in directory name
			}
			$rc = workaround.Find-ModuleAllVersions -name packagemanagement -version "$PackageManagementVersion" | workaround.Save-Module -Path "$PSHome/Modules"
			LogfileAppend("Installing Packagemanagement release $PackageManagementVersion : return code $rc")				
			$rc = workaround.Install-NugetPkgOnLinux "PackageManagement" "$PackageManagementVersion" $rc.name "$PSHome/Modules" "$PSHome/Modules"
			LogfileAppend("Installing Packagemanagement release $PackageManagementVersion done : return code $rc")						
		}		
		
		$InstallPowershellget = $false
		if (((get-module -name powershellget -listavailable -ErrorAction SilentlyContinue) -eq $null) -and ((get-module -name powershellget -ErrorAction SilentlyContinue) -eq $null)) { $InstallPowershellget = $true }
		else
		{
			$tmpvalue=get-module -name powershellget
			if (([string]::IsNullOrEmpty($tmpvalue)) -eq $true) {$tmpvalue=get-module -name powershellget -listavailable }
			try {
				if (!(($tmpvalue).version | ? { $_.tostring() -imatch "$PowershellgetVersion" })) { $InstallPowershellget = $true } #psversiontable = 4 bedingt mit ohne -listavailable
			} catch {}
		}
		if ($InstallPowershellget -eq $true)
		{
			LogfileAppend("Installing Powershellget release $PowershellgetVersion ...")
			if (test-path("$PSHome/Modules/Powershellget")) {
				# rm -r -fo "$PSHome/Modules/Powershellget" #do not delete it might be a previous version without version number in directory name
			}
			$rc = workaround.Find-ModuleAllVersions -name powershellget -version "$PowershellgetVersion" | workaround.Save-Module -Path "$PSHome/Modules"
			LogfileAppend("Installing Powershellget release $PowershellgetVersion : return code $rc")				
			$rc = workaround.Install-NugetPkgOnLinux "PowerShellGet" "$PowershellgetVersion" $rc.name "$PSHome/Modules" "$PSHome/Modules"
			LogfileAppend("Installing Powershellget release $PowershellgetVersion done : return code $rc")				
		}				
	}
}
catch { }
# if ((Get-PSRepository -name psgallery | %{ $_.InstallationPolicy -match "Untrusted" }) -eq $true) { set-psrepository -name PSGallery -InstallationPolicy Trusted }
EOF5

# PowerShellGet release 2.1.3 has RequiredModules specification of PackageManagement 1.1.7.0. Use the helper functions and install PackageManagement 1.1.7.0.
# Do not change '\$PowershellgetVersion="2.1.3"'. This is the PowerShellget module version in Powershell Core 6.2.3.
cat <<EOF1172167 > /tmp/tmp1.ps1
# Post-installation for PowerShell 6.2.3
$PSContent1
$PSContent2
$PSContent3
$PSContent4
	\$PackageManagementVersion="1.1.7.0"
	\$PowershellgetVersion="2.1.3"
$PSContent5
EOF1172167
$PwshLink -c "/tmp/tmp1.ps1"
# rm /tmp/tmp1.ps1

OUTPUT=`$PwshLink -c "get-psrepository"`
if (echo $OUTPUT | grep -q "PSGallery"); then
	echo "$PwshLink: PSGallery is registered."	
	# Check: PSGallery is browseable using "find-module".
	OUTPUT=`$PwshLink -c "find-module VMware.PowerCLI"`
	if (echo $OUTPUT | grep -q "PSGallery"); then
		echo "$PwshLink: PSGallery is browseable."
		echo "$PwshLink: All provisioning tests successfully processed."		
	else
		echo "ERROR: PSGallery not detected as browseable. Executing Install-PwshGalleryOnPhotonOs.ps1 failed."
	fi		
else
	echo "PSGallery not detected as registered. Executing Install-PwshGalleryOnPhotonOs.ps1 failed."
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