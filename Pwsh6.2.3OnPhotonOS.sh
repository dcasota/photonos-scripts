#!/bin/sh
# Deploy Powershell Core 6.2.3 on VMware Photon OS
#
# This script deploys Powershell Core 6.2.3 on VMware Photon OS.
#
# 
#
#
#
# History
# 0.1  28.10.2019   dcasota  Initial release
#
# Prerequisites:
#    VMware Photon OS 3.0
#
# 

DownloadURL="https://github.com/PowerShell/PowerShell/releases/download/v6.2.3/powershell-6.2.3-linux-x64.tar.gz"
ReleaseDir="6.2.3"
PwshLink=Pwsh$ReleaseDir


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

OUTPUT=`$PwshLink -c "get-psrepository"`
if (echo $OUTPUT | grep -q "PSGallery"); then echo "PSGallery is registered.";
else
echo "PSGallery not detected as registered. Executing Install-PwshGalleryOnPhotonOs.ps1 ..."

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
		$PackageName = ([System.IO.Path]::GetFileNameWithoutExtension($filename))
		$SourceFile = $sourcepath + $PathDelimiter + $filename
		$destinationpath = $destination + $PathDelimiter + $PackageName
				
        $i = 1
        $VersionString=""
        for ($i;$i -le (-1 + ($PackageName.split(".")).count);$i++)
        {
            if ($Versionstring -eq "") {$Versionstring = ($PackageName.split("."))[$i]}
            else { $VersionString = $VersionString + "." + ($PackageName.split("."))[$i]}
        }
		LogfileAppend("VersionString = $VersionString")

        # TODO assembling directory name by using version number out of packagename or out of leading subdirectory
		LogfileAppend("Unzipping $Sourcefile to $destinationpath ...")	
		unzip -o $Sourcefile -d $destinationpath
	
		LogfileAppend("Removing $sourcefile ...")
		remove-item -path ($Sourcefile) -force -recurse -confirm:$false
		
		get-childitem -path $destinationpath -recurse -filter *.psd1| ? {
			$TmpFile = $destinationpath + $PathDelimiter + $_.Name
            try {
				LogfileAppend("importing-name $TmpFile ...")			
			    import-module -name $TmpFile -Prefix $VersionString -Scope Global -Verbose -force -erroraction silentlycontinue
            } catch {}
		}
	}
	catch { }
	return ($destinationpath)
}
EOF4

IFS='' read -r -d '' PSContent5 << "EOF5"
function workaround.PwshGalleryPrerequisites
{
	$PwshGalleryInstalled = $false
	$PackageManagementVersion="1.1.7.2"
	$PowershellgetVersion="1.6.7"	
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
				$rc = workaround.Install-NugetPkgOnLinux $rc.name "$PSHome/Modules" "$PSHome/Modules"
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
				$rc = workaround.Install-NugetPkgOnLinux $rc.name "$PSHome/Modules" "$PSHome/Modules"
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

cat <<EOFHere > /tmp/Install-PwshGalleryOnPhotonOs.ps1
$PSContent1
$PSContent2
$PSContent3
$PSContent4
$PSContent5
EOFHere

$PwshLink -c "/tmp/Install-PwshGalleryOnPhotonOs.ps1"

OUTPUT=`$PwshLink -c "get-psrepository"`

if (echo $OUTPUT | grep -q "PSGallery"); then echo "PSGallery is registered.";
else
echo "ERROR: PSGallery not detected as registered. Executing Install-PwshGalleryOnPhotonOs.ps1 failed."
fi

# More to test: if Pwsh is installed, even with PSGallery trusted, find-module may not work.
OUTPUT=`$PwshLink -c "find-module VMware.PowerCLI"`
if (echo $OUTPUT | grep -q "PSGallery"); then echo "PSGallery is browseable.";
else
echo "ERROR: PSGallery not detected as browseable. Executing Install-PwshGalleryOnPhotonOs.ps1 failed."
fi

fi

# Cleanup
rm /tmp/powershell.tar.gz
# rm /tmp/Install-PwshGalleryOnPhotonOs.ps1
tdnf clean all

# Run Powershell
$PwshLink

# Uninstall
# rm /usr/bin/$PwshLink
# rm -r /opt/microsoft/powershell/$ReleaseDir
# Check if no other powershell release is installed which uses the following directories
# rm -r /root/.cache/powershell
# rm -r /opt/microsoft/powershell
# rm -r /root/.local/share/powershell
# rm -r /usr/local/share/powershell