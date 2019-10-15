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


function workaround.Find-ModuleAllVersions
{
	# https://stackoverflow.com/questions/37486587/powershell-v5-how-to-install-modules-to-a-computer-having-no-internet-connecti
	# https://github.com/PowerShell/PowerShellGet/issues/171
	param (
		$Name,
		$proxy,
		$version)
	if (($proxy -eq "") -or ($proxy -eq $null))
	{
		if (($version -eq "") -or ($version -eq $null))
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name'" |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
		else
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name' and Version eq '$version'" |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
	}
	else
	{
		if (($version -eq "") -or ($version -eq $null))
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name'" -proxy $proxy -ProxyUseDefaultCredentials |
			select-Object @{ n = 'Name'; ex = { $_.title.'#text' } },
						  @{ n = 'Version'; ex = { $_.properties.version } },
						  @{ n = 'Uri'; ex = { $_.Content.src } }
		}
		else
		{
			invoke-restmethod "https://www.powershellgallery.com/api/v2/Packages?`$filter=Id eq '$name' and Version eq '$version'" -proxy $proxy -ProxyUseDefaultCredentials |
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
	if ((get-command -name invoke-webrequest) -ne $null)
	{
		if (($proxy -eq "") -or ($proxy -eq $null)) { Invoke-WebRequest $Uri -OutFile $Path -ErrorAction SilentlyContinue }
		else { Invoke-WebRequest $Uri -OutFile $Path -proxy $proxy -ProxyUseDefaultCredentials -ErrorAction SilentlyContinue}
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
				LogfileAppend("Installing packagemanagement ...")
				if (test-path("C:\Program Files\WindowsPowerShell\Modules\PackageManagement")) {
                    # rm -r -fo "C:\Program Files\WindowsPowerShell\Modules\PackageManagement"
                }
				$rc = workaround.Find-ModuleAllVersions -name packagemanagement -version "1.1.7.0" | workaround.Save-Module -Path "C:\Program Files\WindowsPowerShell\Modules"
				$rc = workaround.Install-NugetPkg $rc.name "C:\Program Files\WindowsPowerShell\Modules" "C:\Program Files\WindowsPowerShell\Modules"
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
				LogfileAppend("Installing powershellget ...")
				if (test-path("C:\Program Files\WindowsPowerShell\Modules\Powershellget")) {
                    # rm -r -fo "C:\Program Files\WindowsPowerShell\Modules\Powershellget"
                }
				$rc = workaround.Find-ModuleAllVersions -name powershellget -version "1.6.0" | workaround.Save-Module -Path "C:\Program Files\WindowsPowerShell\Modules"
				$rc = workaround.Install-NugetPkg $rc.name "C:\Program Files\WindowsPowerShell\Modules" "C:\Program Files\WindowsPowerShell\Modules"
			}
			
			$InstallNuget = $false
			if (((get-packageprovider -name nuget -listavailable) -eq $null) -and ((get-packageprovider -name nuget -listavailable) -eq $null)) { $InstallNuget = $true }
			else
			{
				if (!((get-packageprovider -listavailable -name nuget).version | ? { $_.tostring() -imatch "2.8.5.201" })) { $InstallNuget = $true }
				
			}
			if ($InstallNuget -eq $true)
			{
				Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -MaximumVersion 2.8.5.201 -Force -Confirm:$false -Scope AllUsers
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
