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

function workaround.Install-NugetPkg
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
	
	$PathDelimiter="\"
	if ($PSVersiontable.Platform -eq "Unix") {$PathDelimiter="/"}
	
	try
	{
		$PackageName = ([System.IO.Path]::GetFileNameWithoutExtension($filename))
		$NewFileName = $PackageName + ".zip"
		$SourceFile = $sourcepath + $PathDelimiter + $NewFileName
		
		if (test-path ($SourceFile)) {
			LogfileAppend("$Sourcefile found. Removing $Sourcefile ...")
			remove-item -path ($SourceFile) -force
		}
		
		LogfileAppend("Do rename item ($sourcepath + $PathDelimiter + $filename).name ...")
		[System.IO.Path]::changeextension("$sourcepath + $PathDelimiter + $filename",'.zip')
		[System.IO.Path]::changeextension($sourcefile, '.zip')
		LogfileAppend("Name after renaming : $Sourcefile")
		
        $i = 1
        $VersionString=""
        for ($i;$i -le (-1 + ($PackageName.split(".")).count);$i++)
        {
            if ($Versionstring -eq "") {$Versionstring = ($PackageName.split("."))[$i]}
            else { $VersionString = $VersionString + "." + ($PackageName.split("."))[$i]}
        }
		
        # Assembling directory name by using version number out of packagename or out of leading subdirectory
		LogfileAppend("new-object -comobject shell.application")
		$shell = new-object -comobject shell.application
		$tmpzip = $shell.namespace($sourcefile)
		LogfileAppend("Name is $tmpzip")		
		$tmpdir = ""
		foreach ($item in $tmpzip.items())
		{
		    LogfileAppend("Checking $item ...")		
			if (($item.IsFolder -eq $true) -and (($tmpzip.items()).count -eq 1)) {
			   LogfileAppend("Set as tmpdir = $item.name ...")	
				$tmpdir = $item.name 
			}
		}
		if ($tmpdir -ne "")
		{
            if ($tmpdir -ne $VersionString)
            {
			    LogfileAppend("Set destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0]  + $PathDelimiter + ($tmpdir.split("."))[0] ...")				
				$destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0]  + $PathDelimiter + ($tmpdir.split("."))[0]
			}
			else
			{
			    LogfileAppend("Set destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0]	...")
				$destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0]
			}
		}
		else
		{
			if ($VersionString -eq "") {
				LogfileAppend("Set destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0] ...")
				$destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0]
			}
			else {
				LogfileAppend("Set destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0] + $PathDelimiter + $Versionstring ...")
				$destinationspacenew = $destinationspace + $PathDelimiter + ($PackageName.split("."))[0] + $PathDelimiter + $Versionstring
			}
		}
	    LogfileAppend("path is $destinationspacenew")
		new-item -itemtype directory -force -path $destinationspacenew -ErrorAction SilentlyContinue
		foreach ($item in $tmpzip.items())
		{
			$vOptions = 0x14
			#TODO
			# https://stackoverflow.com/questions/27768303/how-to-unzip-a-file-in-powershell
			# https://stackoverflow.com/questions/45618605/create-extract-zip-file-and-overwrite-existing-files-content
			# https://vcsjones.com/2012/11/11/unzipping-files-with-powershell-in-server-core-the-new-way/
			if ($item.isfolder -eq $false) {
				LogfileAppend("file $item is copied to $destinationspacenew ...")
				$shell.namespace($destinationspacenew).copyhere($item, $vOptions)
			}
            else {
				LogfileAppend("directory $item.path is created ...")
				new-item -itemtype directory -force -path $item.path -ErrorAction SilentlyContinue
			}
		}
		LogfileAppend("Removing $sourcefile ...")
		remove-item -path ($sourcefile) -force -recurse -confirm:$false
		get-childitem -path $destinationspacenew -recurse -filter *.psd1| ? {
			$TmpFile = $destinationspacenew + $PathDelimiter + $_.Name
            try {
				LogfileAppend("importing-name $TmpFile ...")			
			    import-module -name $TmpFile -NoClobber -Verbose -force -scope global -erroraction silentlycontinue
            } catch {}
		}
	}
	catch { }
	return ($destinationspacenew)
}

function workaround.PowerCLIPrerequisitesV10.1.0.8346946_V2
{
	$ModuleInstalled = $false
	try
	{
		LogfileAppend("Check VMware.PowerCLI 10.1.0.8346946 ...")
		if (((get-module -name VMware.PowerCLI -listavailable -ErrorAction SilentlyContinue) -ne $null) -and ((get-module -name VMware.PowerCLI -ErrorAction SilentlyContinue) -ne $null))
		{
			if (((get-module -name VMware.PowerCLI -listavailable) | ?{ $_.version.Tostring() -imatch "10.1.0.8346946" })) { $ModuleInstalled = $true }
		}
		if ($ModuleInstalled -eq $false)
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
				LogfileAppend("Installing Packagemanagement release 1.1.7.0 ...")
				if (test-path("/opt/microsoft/powershell/7-preview/Modules/PackageManagement")) {
                    # rm -r -fo "/opt/microsoft/powershell/7-preview/Modules/PackageManagement"
                }
				$rc = workaround.Find-ModuleAllVersions -name packagemanagement -version "1.1.7.0" | workaround.Save-Module -Path "/opt/microsoft/powershell/7-preview/Modules"
				LogfileAppend("Installing Packagemanagement release 1.1.7.0 : return code $rc")				
				$rc = workaround.Install-NugetPkg $rc.name "/opt/microsoft/powershell/7-preview/Modules" "/opt/microsoft/powershell/7-preview/Modules"
				LogfileAppend("Installing Packagemanagement release 1.1.7.0 done : return code $rc")						
			}		
			
			$InstallPowershellget = $false
			if (((get-module -name powershellget -listavailable -ErrorAction SilentlyContinue) -eq $null) -and ((get-module -name powershellget -ErrorAction SilentlyContinue) -eq $null)) { $InstallPowershellget = $true }
			else
			{
                $tmpvalue=get-module -name powershellget
                if (([string]::IsNullOrEmpty($tmpvalue)) -eq $true) {$tmpvalue=get-module -name powershellget -listavailable }
                try {
				    if (!(($tmpvalue).version | ? { $_.tostring() -imatch "1.6.0" })) { $InstallPowershellget = $true } #psversiontable = 4 bedingt mit ohne -listavailable
				} catch {}
			}
			if ($InstallPowershellget -eq $true)
			{
				LogfileAppend("Installing Powershellget release 1.6.0 ...")
				if (test-path("/opt/microsoft/powershell/7-preview/Modules/Powershellget")) {
                    # rm -r -fo "/opt/microsoft/powershell/7-preview/Modules/Powershellget"
                }
				$rc = workaround.Find-ModuleAllVersions -name powershellget -version "1.6.0" | workaround.Save-Module -Path "/opt/microsoft/powershell/7-preview/Modules"
				LogfileAppend("Installing Powershellget release 1.6.0 : return code $rc")				
				$rc = workaround.Install-NugetPkg $rc.name "/opt/microsoft/powershell/7-preview/Modules" "/opt/microsoft/powershell/7-preview/Modules"
				LogfileAppend("Installing Powershellget release 1.6.0 done : return code $rc")				
			}
			
			$InstallNuget = $false
			if (((get-packageprovider -name nuget -listavailable) -eq $null) -and ((get-packageprovider -name nuget -listavailable) -eq $null)) { $InstallNuget = $true }
			else
			{
				if (!((get-packageprovider -listavailable -name nuget).version | ? { $_.tostring() -imatch "2.8.5.201" })) { $InstallNuget = $true }
				
			}
			if ($InstallNuget -eq $true)
			{
				LogfileAppend("Installing Nuget release 2.8.5.201 ...")
				$rc = Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -MaximumVersion 2.8.5.201 -Force -Confirm:$false -Scope AllUsers
				LogfileAppend("Installing Nuget release 2.8.5.201 done : return code $rc")				
			}
			
			# Register-PSRepository -Name PSGallery -SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted -Default		
			if ((Get-PSRepository -name psgallery | %{ $_.InstallationPolicy -match "Untrusted" }) -eq $true) { set-psrepository -name PSGallery -InstallationPolicy Trusted }

		}
	}
	catch { }
	$value = 0
	if ($ModuleInstalled -eq $false) { $value = 1 }
	return ($value)
}


# Requires Run as Administrator
$rc = workaround.PowerCLIPrerequisitesV10.1.0.8346946_V2

