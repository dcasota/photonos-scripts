# Deploying Powershellgallery modules on VMware Photon OS isn't actually possible out-of-the-box.
#
# Deploy Powershell on Photon OS: tdnf -y install powershell 
# As on September 2019 the latest built-in installable powershell release is 6.1.0-271.
#
#
# The same issue of a non-registered Powershellgallery happened on a Windows OS using WMF5.1 at that time.
# This script deploys the releases of powershellget and packagemanagement which were/are valid to workaround the non-registered PSGallery issue.
#
#
# History
# 0.1  15.10.2019   dcasota  UNFINISHED! WORK IN PROGRESS!
#
# Prerequisites:
#    VMware Photon OS 3.0
#

function LogfileAppend($text)
{
	$TimeStamp = (get-date).ToString('dd.MM.yyyy HH:mm:ss.fff')
	Write-Host $TimeStamp  $text
}

function workaround.SaveWMF51
{
 LogfileAppend("Prerequisite WMF 5.1 not implemented.")
}


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
			    import-module -name $TmpFile -NoClobber -Verbose -force -erroraction silentlycontinue
            } catch {}
		}
	}
	catch { }
	return ($destinationpath)
}

function workaround.PwshGalleryPrerequisites
{
	$PwshGalleryInstalled = $false
	try
	{
		LogfileAppend("Check get-psrepository ...")
		#TODO
		if ($PwshGalleryInstalled -eq $false)
		{
			
			LogfileAppend("Check psversion ...")
			if ($psversiontable.psversion.major -lt 5)
			{
				if ($psversiontable.psversion.minor -lt 1) { workaround.SaveWMF51 }
			}
			# https://docs.microsoft.com/en-us/powershell/gallery/psget/get_psget_module
			
			$InstallPackageManagement = $false
			if (((get-module -name packagemanagement -listavailable -ErrorAction SilentlyContinue) -eq $null) -and ((get-module -name packagemanagement -ErrorAction SilentlyContinue) -eq $null)) { $InstallPackagemanagement = $true }
			else
			{
                $tmpvalue=get-module -name packagemanagement
                if (([string]::IsNullOrEmpty($tmpvalue)) -eq $true) {$tmpvalue=get-module -name packagemanagement -listavailable }
                try {
                    if (!(($tmpvalue).version | ? { $_.tostring() -imatch "1.1.7.0" })) { $InstallPackageManagement = $true } #psversiontable = 4 bedingt mit ohne -listavailable
				} catch {}
			}
			if ($InstallPackagemanagement -eq $true)
			{
				LogfileAppend("Installing Packagemanagement release 1.4.5 ...")
				if (test-path("/root/.local/share/powershell/Modules/PackageManagement")) {
                    # rm -r -fo "/root/.local/share/powershell/Modules/PackageManagement" #do not delete it might be a previous version without version number in directory name
                }
				$rc = workaround.Find-ModuleAllVersions -name packagemanagement -version "1.4.5" | workaround.Save-Module -Path "/root/.local/share/powershell/Modules"
				LogfileAppend("Installing Packagemanagement release 1.4.5 : return code $rc")				
				$rc = workaround.Install-NugetPkgOnLinux $rc.name "/root/.local/share/powershell/Modules" "/root/.local/share/powershell/Modules"
				LogfileAppend("Installing Packagemanagement release 1.4.5 done : return code $rc")						
			}		
			
			$InstallPowershellget = $false
			if (((get-module -name powershellget -listavailable -ErrorAction SilentlyContinue) -eq $null) -and ((get-module -name powershellget -ErrorAction SilentlyContinue) -eq $null)) { $InstallPowershellget = $true }
			else
			{
                $tmpvalue=get-module -name powershellget
                if (([string]::IsNullOrEmpty($tmpvalue)) -eq $true) {$tmpvalue=get-module -name powershellget -listavailable }
                try {
				    if (!(($tmpvalue).version | ? { $_.tostring() -imatch "2.2.1" })) { $InstallPowershellget = $true } #psversiontable = 4 bedingt mit ohne -listavailable
				} catch {}
			}
			if ($InstallPowershellget -eq $true)
			{
				LogfileAppend("Installing Powershellget release 2.2.1 ...")
				if (test-path("/root/.local/share/powershell/Modules/Powershellget")) {
                    # rm -r -fo "/root/.local/share/powershell/Modules/Powershellget" #do not delete it might be a previous version without version number in directory name
                }
				$rc = workaround.Find-ModuleAllVersions -name powershellget -version "2.2.1" | workaround.Save-Module -Path "/root/.local/share/powershell/Modules"
				LogfileAppend("Installing Powershellget release 2.2.1 : return code $rc")				
				$rc = workaround.Install-NugetPkgOnLinux $rc.name "/root/.local/share/powershell/Modules" "/root/.local/share/powershell/Modules"
				LogfileAppend("Installing Powershellget release 2.2.1 done : return code $rc")				
			}
					
		}
	}
	catch { }
	$value = 0
	if ($ModuleInstalled -eq $false) { $value = 1 }
	return ($value)
}


# Requires Run with root privileges
workaround.PwshGalleryPrerequisites
# Now, Install-Package works, because Nuget has version 2.8.5.210. However, Register-PSRepository still fails. To fix that, update powershellget to version 1.6.7.
# Install-Package -Name PowerShellGet -Source https://www.powershellgallery.com/api/v2/ -ProviderName NuGet -MinimumVersion 1.6.0 -MaximumVersion 1.6.0 -force -confirm:$false
# The module releases should be now Powershellget 1.6.7, Packagemanagement 1.1.7.0 and Nuget 2.8.5.210
# get-psrepository
# Register-PSRepository -Default
# get-psrepository
# Register-PSRepository -Name PSGallery -SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted
# get-psrepository

