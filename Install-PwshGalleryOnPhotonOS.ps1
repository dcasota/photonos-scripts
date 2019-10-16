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
 LogfileAppend("Dummy Function WMF5.1")
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

