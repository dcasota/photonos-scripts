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
			    import-module -name $TmpFile -Scope Global -Verbose -force -erroraction silentlycontinue
            } catch {}
		}
	}
	catch { }
	return ($destinationpath)
}

function workaround.PwshGalleryPrerequisites
{
	$PwshGalleryInstalled = $false
	$PackageManagementVersion="1.4.4"
	$PowershellgetVersion="2.2.1"	
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

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Requires Run with root privileges
workaround.PwshGalleryPrerequisites

# Checks
# PS /root/photonos-scripts-master> get-module
# 
# ModuleType Version    Name                                ExportedCommands
# ---------- -------    ----                                ----------------
# Manifest   6.1.0.0    Microsoft.PowerShell.Management     {Add-Content, Clear-Content, Clear-Item, Clear-ItemProperty...
# Manifest   6.1.0.0    Microsoft.PowerShell.Utility        {Add-Member, Add-Type, Clear-Variable, Compare-Object...}
# Script     1.1.7.0    PackageManagement                   {Find-Package, Find-PackageProvider, Get-Package, Get-Packa...
# Script     1.6.0      PowerShellGet                       {Find-Command, Find-DscResource, Find-Module, Find-RoleCapa...
# 
# 
# PS /root/photonos-scripts-master>


# 1) get-psrepository
# Powershellget 1.6.7, Nuget 2.8.5.210, Packagemanagement 2.2.1
# PackageManagement\Get-PackageSource : Unable to find module providers (PowerShellGet).
# At $PSHome/Modules/PowerShellGet.2.2.1/PSModule.psm1:9515 char:31
# + ... ckageSources = PackageManagement\Get-PackageSource @PSBoundParameters
# +                    ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : InvalidArgument: (Microsoft.Power...etPackageSource:GetPackageSource) [Get-PackageSource], Exception
# + FullyQualifiedErrorId : UnknownProviders,Microsoft.PowerShell.PackageManagement.Cmdlets.GetPackageSource
#
# 2) Register-PSRepository -Name PSGallery -SourceLocation "https://www.powershellgallery.com/api/v2/" -InstallationPolicy Trusted
# Register-PSRepository : Use 'Register-PSRepository -Default' to register the PSGallery repository.
# At line:1 char:1
# + Register-PSRepository -Name PSGallery -SourceLocation "https://www.po ...
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : InvalidArgument: (PSGallery:String) [Register-PSRepository], ArgumentException
# + FullyQualifiedErrorId : UseDefaultParameterSetOnRegisterPSRepository,Register-PSRepository
# 
# 3) Register-PSRepository -Default
# PackageManagement\Register-PackageSource : Unable to find module providers (PowerShellGet).
# At /usr/lib/powershell/Modules/PowerShellGet.1.6.0/PSModule.psm1:4631 char:17
# + ...     $null = PackageManagement\Register-PackageSource @PSBoundParamete ...
# +                 ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : InvalidArgument: (Microsoft.Power...erPackageSource:RegisterPackageSource) [Register-PackageSource], Exception
# + FullyQualifiedErrorId : UnknownProviders,Microsoft.PowerShell.PackageManagement.Cmdlets.RegisterPackageSource
#
# 4) get-packagesource
# WARNING: Unable to find package sources.
#
# 5) get-packageprovider
# Name                     Version          DynamicOptions
# ----                     -------          --------------
# NuGet                    2.8.5.210        Destination, ExcludeVersion, Scope, SkipDependencies, Headers, FilterOnTag,...
#
# 6) get-module
# ModuleType Version    Name                                ExportedCommands
# ---------- -------    ----                                ----------------
# Manifest   6.1.0.0    Microsoft.PowerShell.Management     {Add-Content, Clear-Content, Clear-Item, Clear-ItemProperty...
# Manifest   6.1.0.0    Microsoft.PowerShell.Utility        {Add-Member, Add-Type, Clear-Variable, Compare-Object...}
# Script     1.1.7.0    PackageManagement                   {Find-Package, Find-PackageProvider, Get-Package, Get-Packa...
# Script     1.6.0      PowerShellGet                       {Find-Command, Find-DscResource, Find-Module, Find-RoleCapa...
# 


# Install-Package -Name PowerShellGet -Source https://www.powershellgallery.com/api/v2/ -ProviderName NuGet -MinimumVersion 2.2.1 -MaximumVersion 2.2.1 -force -confirm:$false
