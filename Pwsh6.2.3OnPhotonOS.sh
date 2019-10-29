#!/bin/sh
# Deploy Powershell Core 6.2.3 on VMware Photon OS
#
# This script deploys Powershell Core 6.2.3 on VMware Photon OS.
#
#
# History
# 0.1  28.10.2019   dcasota  UNFINISHED! WORK IN PROGRESS!
#
# Prerequisites:
#    VMware Photon OS 3.0
#
#
# Powershell Core 6.2.3 on Vmware Photon OS does not built-in provide PSGallery functionality.
#
# Using Powershell Core 6.2.3 built-in packagemanagement 1.3.2 and powershellget 2.1.3 releases the cmdlets find-module, get-psrepository and install-module produce errors.
#
# This can be fixed. The old Powershell Core 6.0.5 release is the baseline. find-module, get-psrepository and install-module work fine. It uses packagemanagement 1.1.7.2 and powershellget 1.6.7.
# This script installs Powershell Core 6.0.5 with additional packagemanagement and powershellget releases, then it side-by-side installs Powershell Core 6.2.3 to enable PSGallery functionality.
#
#
# This script contains workaround functions to ensure the import of specific modules. The idea is to find a combination of packagemanagement and
# powershellget releases with workaround functions which re-ensure the use of find-module, get-psrepository and install-module.
#
# Powershell Core
# v7.0.0-preview.5
# v7.0.0-preview.4
# v6.2.3
# v6.1.6
# v7.0.0-preview.3
# v7.0.0-preview.2
# v6.2.2
# v6.1.5
# v7.0.0-preview.1
# v6.2.1
# 
# Packagemanagement
#     1.4.5
#     1.4.4
#     1.4.3
#     1.4.2
#     1.4.1
#     1.4
#     1.3.2
#     1.3.1
#     1.2.4
#     1.2.2
#     1.1.7.2
#     1.1.7.0
#     1.1.6.0
#     1.1.4.0
#     1.1.3.0
#     1.1.1.0
#     1.1.0.0
#
# Powershellget
#     2.2.1
#     2.2
#     2.1.5
#     2.1.4
#     2.1.3
#     2.1.2
#     2.1.1
#     2.1.0
#     2.0.4
#     2.0.3
#     2.0.1
#     2.0.0
#     1.6.7
#     1.6.6
#     1.6.5
#     1.6.0
#     1.5.0.0
#     1.1.3.2
#     1.1.3.1
#     1.1.2.0
#     1.1.1.0
#     1.1.0.0
# 
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

# First, install powershell 6.0.5
DownloadURL="https://github.com/PowerShell/PowerShell/releases/download/v6.0.5/powershell-6.0.5-linux-x64.tar.gz"
ReleaseDir="6.0.5"
PwshLink=Pwsh$ReleaseDir
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


# Side-by-side installation of Powershell Core 6.2.3
# --------------------------------------------------
# 1) Install Powershell 6.2.3 
DownloadURL="https://github.com/PowerShell/PowerShell/releases/download/v6.2.3/powershell-6.2.3-linux-x64.tar.gz"
ReleaseDir="6.2.3"
PwshLink=Pwsh$ReleaseDir	
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
	
# Prepare post-installation powershell content
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
		
			LogfileAppend("Removing $sourcefile ...")
			remove-item -path ($Sourcefile) -force -recurse -confirm:$false
			
			get-childitem -path $destinationpath -recurse -filter *.psd1| ? {
				$TmpFile = $destinationpath + $PathDelimiter + $_.Name
				try {
					LogfileAppend("importing-name $TmpFile ...")			
					import-module -name $TmpFile -Global -Verbose -force -erroraction silentlycontinue
				} catch {}
			}
		}
	}
	catch { }
	return ($destinationpath)
}

function workaround.PwshGalleryPrerequisites
{
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
	$value = 0
	if ($ModuleInstalled -eq $false) { $value = 1 }
	return ($value)
}

# Requires Run with root privileges
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
workaround.PwshGalleryPrerequisites
# if ((Get-PSRepository -name psgallery | %{ $_.InstallationPolicy -match "Untrusted" }) -eq $true) { set-psrepository -name PSGallery -InstallationPolicy Trusted }
EOF5

cat <<EOF1172167 > /tmp/tmp1.ps1
# Post-installation for PowerShell 6.2.3
$PSContent1
$PSContent2
$PSContent3
$PSContent4
	\$PackageManagementVersion="1.1.7.2"
	\$PowershellgetVersion="1.6.7"
$PSContent5
EOF1172167
$PwshLink -c "/tmp/tmp1.ps1"

# Packagemanagement
#     1.4.5
#     1.4.4
#     1.4.3
#     1.4.2
#     1.4.1
#     1.4
#     1.3.2
#     1.3.1
#     1.2.4
#     1.2.2
#     1.1.7.2
#     1.1.7.0
#     1.1.6.0
#     1.1.4.0
#     1.1.3.0
#     1.1.1.0
#     1.1.0.0
#
# Powershellget
#     2.2.1
#     2.2
#     2.1.5
#     2.1.4
#     2.1.3
#     2.1.2
#     2.1.1
#     2.1.0
#     2.0.4
#     2.0.3
#     2.0.1
#     2.0.0
#     1.6.7




# 2) Remove all Powershellget and PackageManagement modules
#rm -r /opt/microsoft/powershell/6.2.3/Modules/PackageManagement
#rm -r /opt/microsoft/powershell/6.2.3/Modules/PowerShellGet
#rm -r /usr/local/share/powershell/Modules/PackageManagement
#rm -r /usr/local/share/powershell/Modules/PowerShellGet
#rm -r /root/.cache/powershell/PowerShellGet
#rm -r /root/.cache/powershell/PackageManagement
#
# 3) Install fixed module releases PackageManagement 1.1.7.2 and PowerShellGet 1.6.7
#mkdir -p /opt/microsoft/powershell/6.2.3/Modules/PackageManagement/1.1.7.2/
#cp -Rv /opt/microsoft/powershell/6.0.5/Modules/PackageManagement/1.1.7.2/ /opt/microsoft/powershell/6.2.3/Modules/PackageManagement/
#$PwshLink -c "import-module /opt/microsoft/powershell/6.2.3/Modules/PackageManagement/1.1.7.2/PackageManagement.psd1 -Scope Global -verbose"
#$PwshLink -c "import-module /opt/microsoft/powershell/6.2.3/Modules/PackageManagement/1.1.7.2/PackageManagement.psd1 -Scope Local -verbose"
#
#mkdir -p /opt/microsoft/powershell/6.2.3/Modules/PowerShellGet/1.6.7/
#cp -Rv /opt/microsoft/powershell/6.0.5/Modules/PowerShellGet/1.6.7/ /opt/microsoft/powershell/6.2.3/Modules/PowerShellGet/
#$PwshLink -c "import-module /opt/microsoft/powershell/6.2.3/Modules/PowerShellGet/1.6.7/PowerShellGet.psd1 -Scope Global -verbose"
#$PwshLink -c "import-module /opt/microsoft/powershell/6.2.3/Modules/PowerShellGet/1.6.7/PowerShellGet.psd1 -Scope Local -verbose"
#
#mkdir /opt/microsoft/powershell/6.2.3/Modules/PackageManagement
#mkdir /opt/microsoft/powershell/6.2.3/Modules/PowerShellGet
#mkdir /usr/local/share/powershell/Modules/PackageManagement
#mkdir /usr/local/share/powershell/Modules/PowerShellGet
#$PwshLink -c "/tmp/tmp1.ps1"
#
# Get-Module -ListAvailable PowerShellGet,PackageManagement
#
# import-packageprovider -name NuGet -RequiredVersion 3.0.0.1

# rm -r /usr/local/share/powershell/Modules/PackageManagement/1.4.5
# unregister-psrepository -name PSGallery
# register-psrepository -Default

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
# rm /tmp/Install-PwshGalleryOnPhotonOs.ps1
tdnf clean all

# Uninstall
# rm /usr/bin/$PwshLink
# rm -r /opt/microsoft/powershell/$ReleaseDir
# Check if no other powershell release is installed which uses the following directories
# rm -r /root/.cache/powershell
# rm -r /opt/microsoft/powershell
# rm -r /root/.local/share/powershell
# rm -r /usr/local/share/powershell