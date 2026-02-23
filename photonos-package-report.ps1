# .SYNOPSIS
#  This VMware Photon OS github branches packages (specs) report script creates various excel prn.
#
# .NOTES
#   Author:  Daniel Casota
#   Version:
#   0.1   06.03.2021   dcasota  First release
#   0.2   17.04.2021   dcasota  dev added
#   0.3   05.02.2023   dcasota  5.0 added, report release x package with a higher version than same release x+1 package
#   0.4   27.02.2023   dcasota  CheckURLHealth added, timedate stamp in reports' name added, url health coverage improvements
#   0.41  28.02.2023   dcasota  url health coverage improvements
#   0.42  01.03.2023   dcasota  url health coverage improvements
#   0.43  06.03.2023   dcasota  url health coverage improvements, updateavailable signalization without alpha/release candidate/pre/dev versions
#   0.44  17.03.2023   dcasota  url health coverage improvements, updateavailable signalization for rubygems.org and sourceforge.net
#   0.45  08.05.2023   dcasota  bugfix for zip.spec + unzip.spec
#   0.46  09.05.2023   dcasota  UpdateURL added
#   0.47  20.05.2023   dcasota  Bugfixes, ModifySpecFile added
#   0.48  03.06.2023   dcasota  Separated sources_new and specs_new directories, bugfixes packages netfilter + python, Source0 urlhealth check
#   0.49  24.01.2024   dcasota  fix chrpath host path
#   0.50  04.02.2024   dcasota  various url fixes
#   0.51  06.03.2024   dcasota  git check added
#   0.52  08.09.2024   dcasota  Ph6 and common added
#   0.53  13.02.2025   dcasota  KojiFedoraProjectLookUp, various url fixes
#   0.54  30.05.2025   GitHubCopilot  Implemented parallel processing for URL health checks, Fix linting errors from parallel processing implementation
#   0.55  30.05.2025   GitHubCopilot  Implemented parallel processing for spec file modifications, Fix linting errors from parallel processing implementation
#   0.56  11.06.2025   dcasota  various bugfixes
#   0.57  17.06.2025   dcasota  data scraping related modifications, in Source0Lookup gitSource/gitBranch/customRegex/replaceStrings added, in CheckUrlHealth new function Convert-ToVersion added, various bugfixes
#   0.58  29.07.2025   dcasota  various bugfixes
#   0.59  11.02.2026   dcasota  various bugfixes
#   0.60  11.02.2026   dcasota  Robustness, security and cross-platform improvements: git timeout handling, safe git calls,
#                               cross-platform path handling (Join-Path, $HOME fallback), OS detection for winget/Get-Counter/Get-CimInstance,
#                               List<T> for performance, safe spec parsing with Get-SpecValue helper, security cleanup at script end
#   0.61  23.02.2026   dcasota  Quarterly version format support (YYYY.Q#.#), Warning/ArchivationDate output columns,
#                               Source0Lookup expansion to 848+ packages, git timeout standardized to 600s,
#                               Linux compatibility fixes, RubyGems JSON API, GNU FTP mirror fallback,
#                               git fetch --prune --prune-tags --tags to ensure all remote tags are synced
#
#  .PREREQUISITES
#    - Script tested on Microsoft Windows 11 and on Photon OS 5.0 with Powershell Core 7.5.4
#    - Powershell: Minimal version: 5.1
#                  Recommended version: 7.4 or higher for parallel processing capabilities
#  .HINTS
#   - For best results, run this script on a machine with good network connectivity and sufficient resources, especially if generating URL health reports for many packages.
#   - To debug:
#     Open the script in Visual Studio Code,
#     uncomment "$Script:UseParallel = $false" to disable parallel processing, 
#     uncomment the debug block in the ParseDirectory function, set the spec file you want to debug in the if condition, for example:
#          # IN CASE OF DEBUG: UNCOMMENT AND DEBUG FROM HERE
#          # -----------------------------------------------
#          if ($currentTask.spec -ilike 'aufs-util.spec')
#          {pause}
#          else
#          {return}
#          # -----------------------------------------------
#     set breakpoint on {pause}, step over(F10) and inspect variables as needed.
#   - To run on Windows: Open Powershell
#     cd your\path\to\photonos-scripts;
#     $env:GITHUB_TOKEN="<YOUR GITHUB_TOKEN>"; $env:GITLAB_USERNAME="<your GITLAB_USERNAME>"; $env:GITLAB_TOKEN="<your GITLAB_TOKEN>"; 
#     pwsh -File .\photonos-package-report.ps1 -sourcepath <path-to-store-the-reports> \
#          -GeneratePh3URLHealthReport $true -GeneratePh4URLHealthReport $true -GeneratePh5URLHealthReport $true -GeneratePh6URLHealthReport $true \
#          -GeneratePhCommonURLHealthReport $true -GeneratePhDevURLHealthReport $true -GeneratePhMasterURLHealthReport $true \
#          -GeneratePhPackageReport $true \
#          -GeneratePhCommontoPhMasterDiffHigherPackageVersionReport $true -GeneratePh5toPh6DiffHigherPackageVersionReport $true -GeneratePh4toPh5DiffHigherPackageVersionReport $true -GeneratePh3toPh4DiffHigherPackageVersionReport $true
#   - To run on WSL:
#     Open Photon OS e.g. "wsl -d Ph5 -u root /bin/bash"
#     Install Powershell Core: tdnf install powershell -y
#     cd /your\path/to/photonos-scripts;
#     export GITHUB_TOKEN="<YOUR GITHUB_TOKEN>"; export GITLAB_USERNAME="<your GITLAB_USERNAME>"; export GITLAB_TOKEN="<your GITLAB_TOKEN>";
#     pwsh -File ./photonos-package-report.ps1 -sourcepath <path-to-store-the-reports> \
#          -GeneratePh3URLHealthReport $true -GeneratePh4URLHealthReport $true -GeneratePh5URLHealthReport $true -GeneratePh6URLHealthReport $true \
#          -GeneratePhCommonURLHealthReport $true -GeneratePhDevURLHealthReport $true -GeneratePhMasterURLHealthReport $true \
#          -GeneratePhPackageReport $true \
#          -GeneratePhCommontoPhMasterDiffHigherPackageVersionReport $true -GeneratePh5toPh6DiffHigherPackageVersionReport $true -GeneratePh4toPh5DiffHigherPackageVersionReport $true -GeneratePh3toPh4DiffHigherPackageVersionReport $true
#   - To run on Photon OS: Open terminal, login as root or a user with sufficient permissions. Same as in WSL.
#


[CmdletBinding()]
param (
    [string]$access=$env:GITHUB_TOKEN,
    [string]$gitlabaccess=$env:GITLAB_TOKEN,
    [string]$sourcepath = $(if ($env:PUBLIC) { $env:PUBLIC } else { $HOME }),
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh3URLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh4URLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh5URLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh6URLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePhCommonURLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePhDevURLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePhMasterURLHealthReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePhPackageReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePhCommontoPhMasterDiffHigherPackageVersionReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh5toPh6DiffHigherPackageVersionReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh4toPh5DiffHigherPackageVersionReport=$true,
    [Parameter(Mandatory = $false)][ValidateNotNull()]$GeneratePh3toPh4DiffHigherPackageVersionReport=$true
)

# Convert string parameters to boolean (needed when using -File with $true/$false)
function Convert-ToBoolean($value) {
    if ($value -is [bool]) { return $value }
    if ($value -is [string]) {
        if ($value -eq '$true' -or $value -eq 'true' -or $value -eq '1') { return $true }
        if ($value -eq '$false' -or $value -eq 'false' -or $value -eq '0') { return $false }
    }
    return [bool]$value
}

$GeneratePh3URLHealthReport = Convert-ToBoolean $GeneratePh3URLHealthReport
$GeneratePh4URLHealthReport = Convert-ToBoolean $GeneratePh4URLHealthReport
$GeneratePh5URLHealthReport = Convert-ToBoolean $GeneratePh5URLHealthReport
$GeneratePh6URLHealthReport = Convert-ToBoolean $GeneratePh6URLHealthReport
$GeneratePhCommonURLHealthReport = Convert-ToBoolean $GeneratePhCommonURLHealthReport
$GeneratePhDevURLHealthReport = Convert-ToBoolean $GeneratePhDevURLHealthReport
$GeneratePhMasterURLHealthReport = Convert-ToBoolean $GeneratePhMasterURLHealthReport
$GeneratePhPackageReport = Convert-ToBoolean $GeneratePhPackageReport
$GeneratePhCommontoPhMasterDiffHigherPackageVersionReport = Convert-ToBoolean $GeneratePhCommontoPhMasterDiffHigherPackageVersionReport
$GeneratePh5toPh6DiffHigherPackageVersionReport = Convert-ToBoolean $GeneratePh5toPh6DiffHigherPackageVersionReport
$GeneratePh4toPh5DiffHigherPackageVersionReport = Convert-ToBoolean $GeneratePh4toPh5DiffHigherPackageVersionReport
$GeneratePh3toPh4DiffHigherPackageVersionReport = Convert-ToBoolean $GeneratePh3toPh4DiffHigherPackageVersionReport

# Helper function to run git commands with timeout
function Invoke-GitWithTimeout {
    param(
        [string]$Arguments,
        [string]$WorkingDirectory = (Get-Location).Path,
        [int]$TimeoutSeconds = 7200 # Default timeout of 2 hours, can be adjusted as needed (kibana, chromium can take a long time to clone)
    )

    try {
        $job = Start-Job -ScriptBlock {
            param($argString, $wd)
            Set-Location $wd
            # Split arguments safely and use & operator instead of Invoke-Expression
            $argArray = $argString -split ' '
            $output = & git @argArray 2>&1
            return $output
        } -ArgumentList $Arguments, $WorkingDirectory

        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($completed) {
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -ErrorAction SilentlyContinue
            return $result
        } else {
            Stop-Job -Job $job -ErrorAction SilentlyContinue
            Remove-Job -Job $job -ErrorAction SilentlyContinue
            Write-Warning "Git command timed out after $TimeoutSeconds seconds: git $Arguments"
            throw "Git operation timed out"
        }
    }
    catch {
        Write-Warning "Git command failed: git $Arguments - Error: $_"
        throw
    }
}

# Helper function to safely extract a value from content using pattern
function Get-SpecValue {
    param(
        [string[]]$Content,
        [string]$Pattern,
        [string]$Replace
    )
    $match = $Content | Select-String -Pattern $Pattern | Select-Object -First 1
    if ($match) {
        return ($match.ToString() -ireplace $Replace, "").Trim()
    }
    return $null
}

function ParseDirectory {
	param (
		[parameter(Mandatory = $true)]
		[string]$SourcePath,
		[parameter(Mandatory = $true)]
		[string]$photonDir
	)
    $Packages = [System.Collections.Generic.List[PSCustomObject]]::new()
    $specsPath = Join-Path -Path $SourcePath -ChildPath $photonDir | Join-Path -ChildPath "SPECS"
    Get-ChildItem -Path $specsPath -Recurse -File -Filter "*.spec" | ForEach-Object {
        $currentFile = $_
        try
        {
            $Name = Split-Path -Path $currentFile.DirectoryName -Leaf
            $content = Get-Content $currentFile.FullName

            $release = Get-SpecValue -Content $content -Pattern "^Release:" -Replace "Release:"
            if (-not $release) { continue }
            $release = $release.Replace("%{?dist}","")
            $release = $release.Replace("%{?kat_build:.kat}","")
            $release = $release.Replace("%{?kat_build:.%kat_build}","")
            $release = $release.Replace("%{?kat_build:.%kat}","")
            $release = $release.Replace("%{?kernelsubrelease}","")
            $release = $release.Replace(".%{dialogsubversion}","")

            $version = Get-SpecValue -Content $content -Pattern "^Version:" -Replace "Version:"
            if (-not $version) { continue }
            $version = "$version-$release"

            $Source0 = Get-SpecValue -Content $content -Pattern "^Source0:" -Replace "Source0:"
            if (-not $Source0) { $Source0 = "" }
            $url = Get-SpecValue -Content $content -Pattern "^URL:" -Replace "URL:"
            if (-not $url) { $url = "" }

            $SHAName=""
            if ($content -ilike '*%define sha1*') {$SHAName = $content | foreach-object{ if ($_ -ilike '*%define sha1*') {((($_ -split '=')[0]).replace('%define sha1',"")).Trim()}}}
            elseif ($content -ilike '*%define sha256*') {$SHAName = $content | foreach-object{ if ($_ -ilike '*%define sha256*') {((($_ -split '=')[0]).replace('%define sha256',"")).Trim()}}}
            elseif ($content -ilike '*%define sha512*') {$SHAName = $content | foreach-object{ if ($_ -ilike '*%define sha512*') {((($_ -split '=')[0]).replace('%define sha512',"")).Trim()}}}

            $srcname=""
            if ($content -ilike '*%define srcname*') { $srcname = (($content | Select-String -Pattern '%define srcname')[0].ToString() -ireplace '%define srcname', "").Trim() }
            if ($content -ilike '*%global srcname*') { $srcname = (($content | Select-String -Pattern '%global srcname')[0].ToString() -ireplace '%global srcname', "").Trim() }

            $gem_name=""
            if ($content -ilike '*%define gem_name*') { $gem_name = (($content | Select-String -Pattern '%define gem_name')[0].ToString() -ireplace '%define gem_name', "").Trim() }
            if ($content -ilike '*%global gem_name*') { $gem_name = (($content | Select-String -Pattern '%global gem_name')[0].ToString() -ireplace '%global gem_name', "").Trim() }

            $group=""
            if ($content -ilike '*Group:*') { $group = (($content | Select-String -Pattern '^Group:')[0].ToString() -ireplace 'Group:', "").Trim() }

            $extra_version=""
            if ($content -ilike '*%define extra_version*') { $extra_version = (($content | Select-String -Pattern '%define extra_version')[0].ToString() -ireplace '%define extra_version', "").Trim() }

            $main_version=""
            if ($content -ilike '*%define main_version*') { $main_version = (($content | Select-String -Pattern '%define main_version')[0].ToString() -ireplace '%define main_version', "").Trim() }

            $upstreamversion=""
            if ($content -ilike '*%define upstreamversion*') { $upstreamversion = (($content | Select-String -Pattern '%define upstreamversion')[0].ToString() -ireplace '%define upstreamversion', "").Trim() }

            $subversion=""
            if ($content -ilike '*%define subversion*') { $subversion = (($content | Select-String -Pattern '%define subversion')[0].ToString() -ireplace '%define subversion', "").Trim() }

            $byaccdate=""
            if ($content -ilike '*define byaccdate*') { $byaccdate = (($content | Select-String -Pattern '%define byaccdate')[0].ToString() -ireplace '%define byaccdate', "").Trim() }

            $dialogsubversion=""
            if ($content -ilike '*%define dialogsubversion*') { $dialogsubversion = (($content | Select-String -Pattern '%define dialogsubversion')[0].ToString() -ireplace '%define dialogsubversion', "").Trim() }

            $libedit_release=""
            if ($content -ilike '*define libedit_release*') { $libedit_release = (($content | Select-String -Pattern '%define libedit_release')[0].ToString() -ireplace '%define libedit_release', "").Trim() }

            $libedit_version=""
            if ($content -ilike '*%define libedit_version*') { $libedit_version = (($content | Select-String -Pattern '%define libedit_version')[0].ToString() -ireplace '%define libedit_version', "").Trim() }

            $ncursessubversion=""
            if ($content -ilike '*%define ncursessubversion*') { $ncursessubversion = (($content | Select-String -Pattern '%define ncursessubversion')[0].ToString() -ireplace '%define ncursessubversion', "").Trim() }

            $cpan_name=""
            if ($content -ilike '*define cpan_name*') { $cpan_name = (($content | Select-String -Pattern '%define cpan_name')[0].ToString() -ireplace '%define cpan_name', "").Trim() }

            $xproto_ver=""
            if ($content -ilike '*%define xproto_ver*') { $xproto_ver = (($content | Select-String -Pattern '%define xproto_ver')[0].ToString() -ireplace '%define xproto_ver', "").Trim() }

            $_url_src=""
            if ($content -ilike '*define _url_src*') { $_url_src = (($content | Select-String -Pattern '%define _url_src')[0].ToString() -ireplace '%define _url_src', "").Trim() }

            $_repo_ver=""
            if ($content -ilike '*%define _repo_ver*') { $_repo_ver = (($content | Select-String -Pattern '%define _repo_ver')[0].ToString() -ireplace '%define _repo_ver', "").Trim() }

            $null = $Packages.Add([PSCustomObject]@{
                content = $content
                Spec = $currentFile.Name
                Version = $version
                Name = $Name
                Source0 = $Source0
                url = $url
                SHAName = $SHAName
                srcname = $srcname
                gem_name = $gem_name
                group = $group
                extra_version = $extra_version
                main_version = $main_version
                upstreamversion = $upstreamversion
                dialogsubversion = $dialogsubversion
                subversion = $subversion
                byaccdate = $byaccdate
                libedit_release = $libedit_release
                libedit_version = $libedit_version
                ncursessubversion = $ncursessubversion
                cpan_name = $cpan_name
                xproto_ver = $xproto_ver
                _url_src = $_url_src
                _repo_ver = $_repo_ver
            })
        }
        catch {
            # Some spec files may not have all expected fields - this is normal
        }
    }
    return $Packages
}

function Versioncompare {
	param (
		[parameter(Mandatory = $true)]
		$versionA,
		[parameter(Mandatory = $true)]
		$versionB
	)
    $resultAGtrB=0

        if ([string]::IsNullOrEmpty($versionA)) {break}
        $itemA=$versionA.split(".-")[0]
        if ([string]::IsNullOrEmpty($itemA)) {break}
        if ($itemA -eq $versionA) {$versionANew=""}
        elseif ($itemA.length -gt 0) {$versionANew=$versionA.Remove(0,$itemA.length+1)}

        if ([string]::IsNullOrEmpty($versionB)) {break}
        $itemB=$versionB.split(".-")[0]
        if ([string]::IsNullOrEmpty($itemB)) {break}
        if ($itemB -eq $versionB) {$versionBNew=""}
        elseif ($itemB.length -gt 0) {$versionBNew=$versionB.Remove(0,$itemB.length+1)}

            if (($null -ne ($itemA -as [int])) -and ($null -ne ($itemB -as [int])))
            {
                if ([int]$itemA -gt [int]$itemB)
                {
                    $resultAGtrB = 1
                }
                elseif ([int]$itemA -eq [int]$itemB)
                {
                    if (!(([string]::IsNullOrEmpty($versionANew))) -and (!([string]::IsNullOrEmpty($versionBNew)))) { $resultAGtrB = VersionCompare $versionANew $versionBNew }
                    elseif (([string]::IsNullOrEmpty($versionANew)) -and ([string]::IsNullOrEmpty($versionBNew))) { $resultAGtrB = 0 }
                    elseif ([string]::IsNullOrEmpty($versionANew)) { $resultAGtrB = 1 }
                    elseif ([string]::IsNullOrEmpty($versionBNew)) { $resultAGtrB = 2 }
                }
                else
                {
                    $resultAGtrB = 2
                }
            }
            else
            {
                if ($itemA -gt $itemB)
                {
                    $resultAGtrB = 1
                }
                elseif ($itemA -eq $itemB)
                {
                    $resultAGtrB = VersionCompare $versionANew $versionBNew
                }
                else
                {
                    $resultAGtrB = 2
                }
            }

    return $resultAGtrB
}

function Clean-VersionNames {
    param([string[]]$Names)
    if ($null -eq $Names -or $Names.Count -eq 0) { return @() }
    $Names = @($Names | Where-Object { -not [string]::IsNullOrEmpty($_) } | ForEach-Object {
        ((($_ -ireplace '^rel/','') -ireplace '^v','') -ireplace '^r','') -replace '_','.'
    })
    if ($Names.Count -eq 0) { return @() }
    $preReleasePattern = 'candidate|-alpha|-beta|\.beta|rc\.[0-4]|rc[1-4]|-preview\.|-dev\.|-pre1|\.pre1'
    $Names = @($Names | Where-Object { $_ -notmatch $preReleasePattern })
    return $Names
}

function GitPhoton {
    param (
        [parameter(Mandatory = $true)]
        [string]$SourcePath,
        [parameter(Mandatory = $true)]
        $release
    )
    #download from repo
    $photonPath = Join-Path -path $SourcePath -childpath "photon-$release"
    if (!(Test-Path -Path $photonPath))
    {
        Set-Location $SourcePath
        try {
            Invoke-GitWithTimeout "clone -b $release https://github.com/vmware/photon `"$photonPath`"" -WorkingDirectory
            Set-Location $photonPath
        }
        catch {
            Write-Warning "Failed to clone photon-$release repository: $_"
            return
        }
    }
    else
    {
        Set-Location $photonPath
        try {
            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $photonPath
            if ($release -ieq "master") { Invoke-GitWithTimeout "merge origin/master" -WorkingDirectory $photonPath }
            elseif ($release -ieq "dev") { Invoke-GitWithTimeout "merge origin/dev" -WorkingDirectory $photonPath}
            elseif ($release -ieq "common") { Invoke-GitWithTimeout "merge origin/common" -WorkingDirectory $photonPath}
            else { Invoke-GitWithTimeout "merge origin/$release" -WorkingDirectory $photonPath}
        }
        catch {
            # If merge fails (e.g., unresolved conflicts), delete and re-clone
            Write-Warning "Failed to update photon-$release repository: $_"
            Write-Warning "Attempting to delete and re-clone photon-$release..."
            Set-Location $SourcePath
            try {
                Remove-Item -Path $photonPath -Recurse -Force -ErrorAction Stop
                Invoke-GitWithTimeout "clone -b $release https://github.com/vmware/photon `"$photonPath`"" -WorkingDirectory $SourcePath
                Set-Location $photonPath
                Write-Host "Successfully re-cloned photon-$release"
            }
            catch {
                Write-Error "Failed to re-clone photon-$release repository: $_"
            }
        }
    }
}

function Source0Lookup {
$Source0LookupData=@'
specfile,Source0Lookup,gitSource,gitBranch,customRegex,replaceStrings,ignoreStrings,Warning,ArchivationDate
abseil-cpp.spec,https://github.com/abseil/abseil-cpp/releases/download/%{version}/abseil-cpp-%{version}.tar.gz,https://github.com/abseil/abseil-cpp.git
aide.spec,https://github.com/aide/aide/archive/refs/tags/v%{version}.tar.gz,https://github.com/aide/aide.git
alsa-lib.spec,https://www.alsa-project.org/files/pub/lib/alsa-lib-%{version}.tar.bz2
alsa-utils.spec,https://www.alsa-project.org/files/pub/utils/alsa-utils-%{version}.tar.bz2
amdvlk.spec,https://github.com/GPUOpen-Drivers/AMDVLK/archive/refs/tags/v-%{version}.tar.gz,https://github.com/GPUOpen-Drivers/AMDVLK.git,,,"v-"
ansible.spec,https://github.com/ansible/ansible/archive/refs/tags/v%{version}.tar.gz,https://github.com/ansible/ansible.git
ansible-community-general.spec,https://github.com/ansible-collections/community.general/archive/refs/tags/%{version}.tar.gz,https://github.com/ansible-collections/community.general.git
ansible-posix.spec,https://github.com/ansible-collections/ansible.posix/archive/refs/tags/%{version}.tar.gz,https://github.com/ansible-collections/ansible.posix.git
apache-ant.spec,https://github.com/apache/ant/archive/refs/tags/rel/%{version}.tar.gz,https://github.com/apache/ant.git,,,"rel/"
apache-maven.spec,https://github.com/apache/maven/archive/refs/tags/maven-%{version}.tar.gz,https://github.com/apache/maven.git,,apache-maven,"workspace-v0,maven-"
apache-tomcat.spec,https://github.com/apache/tomcat/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/tomcat.git
apache-tomcat-native.spec,https://github.com/apache/tomcat-native/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/tomcat-native.git
apparmor.spec,https://launchpad.net/apparmor/3.1/%{version}/+download/apparmor-%{version}.tar.gz
apr.spec,https://github.com/apache/apr/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/apr.git
apr-util.spec,https://github.com/apache/apr-util/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/apr-util.git
argon2.spec,https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/%{version}.tar.gz,https://github.com/P-H-C/phc-winner-argon2.git
asciidoc3.spec,https://gitlab.com/asciidoc3/asciidoc3/-/archive/v%{version}/asciidoc3-v%{version}.tar.gz,https://gitlab.com/asciidoc3/asciidoc3.git
atk.spec,https://gitlab.gnome.org/Archive/atk/-/archive/%{version}/atk-%{version}.tar.gz,https://gitlab.gnome.org/Archive/atk.git,,,"GTK_ALL_,EA_,GAIL_"
at-spi2-core.spec,https://github.com/GNOME/at-spi2-core/archive/refs/tags/AT_SPI2_CORE_%{version}.tar.gz,https://github.com/GNOME/at-spi2-core.git
audit.spec,https://github.com/linux-audit/audit-userspace/archive/refs/tags/v%{version}.tar.gz,https://github.com/linux-audit/audit-userspace.git
aufs-util.spec,https://github.com/sfjro/aufs-linux/archive/refs/tags/v%{version}.tar.gz,https://github.com/sfjro/aufs-linux.git
autoconf.spec,https://github.com/autotools-mirror/autoconf/archive/refs/tags/v%{version}.tar.gz,https://github.com/autotools-mirror/autoconf.git
autogen.spec,https://ftp.gnu.org/gnu/autogen/rel%{version}/autogen-%{version}.tar.xz
autofs.spec,,https://git.kernel.org/pub/scm/linux/storage/autofs/autofs.git
automake.spec,https://github.com/autotools-mirror/automake/archive/refs/tags/v%{version}.tar.gz,https://github.com/autotools-mirror/automake.git
aws-sdk-cpp.spec,https://github.com/aws/aws-sdk-cpp/archive/refs/tags/%{version}.tar.gz,https://github.com/aws/aws-sdk-cpp.git
backward-cpp.spec,https://github.com/bombela/backward-cpp/archive/refs/tags/v%{version}.tar.gz,https://github.com/bombela/backward-cpp.git
bash-completion.spec,https://github.com/scop/bash-completion/releases/download/%{version}/bash-completion-%{version}.tar.xz,https://github.com/scop/bash-completion.git
bats.spec,https://github.com/bats-core/bats-core/archive/refs/tags/v%{version}.tar.gz,https://github.com/bats-core/bats-core.git
bazel.spec,https://github.com/bazelbuild/bazel/releases/download/%{version}/bazel-%{version}-dist.zip,https://github.com/bazelbuild/bazel.git
bcc.spec,https://github.com/iovisor/bcc/archive/refs/tags/v%{version}.tar.gz,https://github.com/iovisor/bcc.git
bindutils.spec,https://github.com/isc-projects/bind9/archive/refs/tags/v%{version}.tar.gz,https://github.com/isc-projects/bind9.git,,,"wpk-get-rid-of-up-downgrades-,noadaptive,more-adaptive,adaptive"
blktrace.spec,,https://git.kernel.org/pub/scm/linux/kernel/git/axboe/blktrace.git,master
bluez.spec,https://www.kernel.org/pub/linux/bluetooth/bluez-%{version}.tar.xz,https://git.kernel.org/pub/scm/bluetooth/bluez.git
bluez-tools.spec,,https://github.com/khvzak/bluez-tools.git
boost.spec,https://github.com/boostorg/boost/archive/refs/tags/boost-%{version}.tar.gz,https://github.com/boostorg/boost.git
bpftrace.spec,https://github.com/bpftrace/bpftrace/archive/refs/tags/v%{version}.tar.gz,https://github.com/bpftrace/bpftrace.git
bridge-utils.spec,,https://git.kernel.org/pub/scm/network/bridge/bridge-utils.git
btrfs-progs.spec,https://github.com/kdave/btrfs-progs/archive/refs/tags/v%{version}.tar.gz,https://github.com/kdave/btrfs-progs.git
bubblewrap.spec,https://github.com/containers/bubblewrap/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/bubblewrap.git
byacc.spec,https://invisible-island.net/archives/byacc/current/byacc-%{version}.tgz
bzip2.spec,https://github.com/libarchive/bzip2/archive/refs/tags/bzip2-%{version}.tar.gz,https://github.com/libarchive/bzip2.git
c-ares.spec,https://github.com/c-ares/c-ares/archive/refs/tags/v%{version}.tar.gz,https://github.com/c-ares/c-ares.git
c-rest-engine.spec,https://github.com/vmware-archive/c-rest-engine/archive/refs/tags/%{version}.tar.gz,https://github.com/vmware-archive/c-rest-engine.git
cairo.spec,https://gitlab.freedesktop.org/cairo/cairo/-/archive/%{version}/cairo-%{version}.tar.gz,https://gitlab.freedesktop.org/cairo/cairo.git
calico.spec,https://github.com/projectcalico/calico/archive/refs/tags/v%{version}.tar.gz,https://github.com/projectcalico/calico.git
calico-bgp-daemon.spec,https://github.com/projectcalico/calico-bgp-daemon/archive/refs/tags/v%{version}.tar.gz,https://github.com/projectcalico/calico-bgp-daemon.git
calico-bird.spec,https://github.com/projectcalico/bird/archive/refs/tags/v%{version}.tar.gz,https://github.com/projectcalico/bird.git
calico-confd.spec,https://github.com/kelseyhightower/confd/archive/refs/tags/v%{version}.tar.gz,https://github.com/kelseyhightower/confd.git
calico-libnetwork.spec,https://github.com/projectcalico/libnetwork-plugin/archive/refs/tags/v%{version}.tar.gz,https://github.com/projectcalico/libnetwork-plugin.git
capstone.spec,https://github.com/capstone-engine/capstone/archive/refs/tags/%{version}.tar.gz,https://github.com/capstone-engine/capstone.git
cassandra.spec,https://github.com/apache/cassandra/archive/refs/tags/cassandra-%{version}.tar.gz,https://github.com/apache/cassandra.git
cereal.spec,https://github.com/USCiLab/cereal/archive/refs/tags/v%{version}.tar.gz,https://github.com/USCiLab/cereal.git
cgroup-utils.spec,https://github.com/peo3/cgroup-utils/archive/refs/tags/v%{version}.tar.gz,https://github.com/peo3/cgroup-utils.git
check.spec,https://github.com/libcheck/check/archive/refs/tags/%{version}.tar.gz,https://github.com/libcheck/check.git
checkpolicy.spec,https://github.com/SELinuxProject/selinux/archive/refs/tags/checkpolicy-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git,,,"checkpolicy-","2008*,2009*,2010*,2011*,2012*,2013*,2014*,2015*,2016*,2017*,2018*,2019*,2020*"
chkconfig.spec,https://github.com/fedora-sysv/chkconfig/archive/refs/tags/%{version}.tar.gz,https://github.com/fedora-sysv/chkconfig.git
chromium.spec,https://github.com/chromium/chromium/archive/refs/tags/%{version}.tar.gz,https://github.com/chromium/chromium.git
chrony.spec,https://github.com/mlichvar/chrony/archive/refs/tags/%{version}.tar.gz,https://github.com/mlichvar/chrony.git
chrpath.spec,https://codeberg.org/pere/chrpath/archive/release-%{version}.tar.gz,https://codeberg.org/pere/chrpath.git
cifs-utils.spec,https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-%{version}.tar.bz2,git://git.samba.org/cifs-utils.git
clang.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/clang-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git,,,"llvmorg-"
cloud-init.spec,https://github.com/canonical/cloud-init/archive/refs/tags/%{version}.tar.gz,https://github.com/canonical/cloud-init.git
cloud-network-setup.spec,https://github.com/vmware-archive/cloud-network-setup/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-archive/cloud-network-setup.git
cloud-utils.spec,https://github.com/canonical/cloud-utils/archive/refs/tags/%{version}.tar.gz,https://github.com/canonical/cloud-utils.git
cmake.spec,https://github.com/Kitware/CMake/releases/download/v%{version}/cmake-%{version}.tar.gz,https://github.com/Kitware/CMake.git
cmocka.spec,https://git.cryptomilk.org/projects/cmocka.git/snapshot/cmocka-%{version}.tar.xz,https://git.cryptomilk.org/projects/cmocka.git
cni.spec,https://github.com/containernetworking/plugins/archive/refs/tags/v%{version}.tar.gz,https://github.com/containernetworking/plugins.git
colm.spec,https://github.com/adrian-thurston/colm/archive/refs/tags/%{version}.tar.gz,https://github.com/adrian-thurston/colm.git
commons-daemon.spec,https://github.com/apache/commons-daemon/archive/refs/tags/commons-daemon-%{version}.tar.gz,https://github.com/apache/commons-daemon.git
compat-gdbm.spec,https://ftp.gnu.org/gnu/gdbm/gdbm-%{version}.tar.gz
confd.spec,https://github.com/projectcalico/confd/archive/refs/tags/v%{version}-0.dev.tar.gz,https://github.com/projectcalico/confd.git
conmon.spec,https://github.com/containers/conmon/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/conmon.git
connect-proxy.spec,https://github.com/gotoh/ssh-connect/archive/refs/tags/%{version}.tar.gz,https://github.com/gotoh/ssh-connect.git
conntrack-tools.spec,https://www.netfilter.org/projects/conntrack-tools/files/conntrack-tools-%{version}.tar.xz,https://git.netfilter.org/conntrack-tools.git
consul.spec,https://github.com/hashicorp/consul/archive/refs/tags/v%{version}.tar.gz,https://github.com/hashicorp/consul.git
containerd.spec,https://github.com/containerd/containerd/archive/refs/tags/v%{version}.tar.gz,https://github.com/containerd/containerd.git
containers-common.spec,https://github.com/containers/common/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/common.git
coredns.spec,https://github.com/coredns/coredns/archive/refs/tags/v%{version}.tar.gz,https://github.com/coredns/coredns.git
copenapi.spec,https://github.com/vmware-archive/copenapi/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-archive/copenapi.git
cppcheck.spec,https://github.com/danmar/cppcheck/archive/refs/tags/%{version}.tar.gz,https://github.com/danmar/cppcheck.git
cracklib.spec,https://github.com/cracklib/cracklib/archive/refs/tags/v%{version}.tar.gz,https://github.com/cracklib/cracklib.git
crash.spec,https://github.com/crash-utility/crash/archive/refs/tags/%{version}.tar.gz,https://github.com/crash-utility/crash.git
createrepo_c.spec,https://github.com/rpm-software-management/createrepo_c/archive/refs/tags/%{version}.tar.gz,https://github.com/rpm-software-management/createrepo_c.git
cri-tools.spec,https://github.com/kubernetes-sigs/cri-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/kubernetes-sigs/cri-tools.git
cronie.spec,https://github.com/cronie-crond/cronie/archive/refs/tags/cronie-%{version}.tar.gz,https://github.com/cronie-crond/cronie.git,,,"cronie-"
crun.spec,https://github.com/containers/crun/releases/download/%{version}/crun-%{version}.tar.gz,https://github.com/containers/crun.git
cryptsetup.spec,https://github.com/mbroz/cryptsetup/archive/refs/tags/v%{version}.tar.gz,https://github.com/mbroz/cryptsetup.git
cscope.spec,https://unlimited.dl.sourceforge.net/project/cscope/cscope/v%{version}/cscope-%{version}.tar.gz
ctags.spec,https://github.com/universal-ctags/ctags/releases/download/v%{version}/universal-ctags-%{version}.tar.gz,https://github.com/universal-ctags/ctags.git,,,"universal-ctags-"
cups.spec,https://github.com/OpenPrinting/cups/archive/refs/tags/v%{version}.tar.gz,https://github.com/OpenPrinting/cups.git
cve-check-tool.spec,https://github.com/clearlinux/cve-check-tool/archive/refs/tags/v%{version}.tar.gz,https://github.com/clearlinux/cve-check-tool.git
cyrus-sasl.spec,https://github.com/cyrusimap/cyrus-sasl/archive/refs/tags/cyrus-sasl-%{version}.tar.gz,https://github.com/cyrusimap/cyrus-sasl.git
cython.spec,https://github.com/cython/cython/releases/download/%{version}/cython-%{version}.tar.gz,https://github.com/cython/cython.git
cython3.spec,https://github.com/cython/cython/archive/refs/tags/%{version}.tar.gz,https://github.com/cython/cython.git
dbus.spec,,https://gitlab.freedesktop.org/dbus/dbus.git
dbus-broker.spec,https://github.com/bus1/dbus-broker/releases/download/v%{version}/dbus-broker-%{version}.tar.xz,https://github.com/bus1/dbus-broker.git
dbus-glib.spec,,https://gitlab.freedesktop.org/dbus/dbus-glib.git
dbus-python.spec,,https://gitlab.freedesktop.org/dbus/dbus-python.git
dbxtool.spec,https://github.com/rhboot/dbxtool/releases/download/dbxtool-%{version}/dbxtool-%{version}.tar.bz2,https://github.com/rhboot/dbxtool.git,,,,,1,2022-08-24
ddclient.spec,https://github.com/ddclient/ddclient/releases/download/v%{version}/ddclient-%{version}.tar.gz,https://github.com/ddclient/ddclient.git
device-mapper-multipath.spec,https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz,https://github.com/opensvc/multipath-tools.git
device-mapper-multipath.spec,https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz,https://github.com/opensvc/multipath-tools.git
dialog.spec,https://invisible-island.net/archives/dialog/dialog-%{version}.tgz
ding-libs.spec,https://github.com/SSSD/ding-libs/releases/download/%{version}/ding-libs-%{version}.tar.gz,https://github.com/SSSD/ding-libs.git
distcc.spec,https://github.com/distcc/distcc/releases/download/v%{version}/distcc-%{version}.tar.gz,https://github.com/distcc/distcc.git
dkms.spec,https://github.com/dkms-project/dkms/archive/refs/tags/v%{version}.tar.gz,https://github.com/dkms-project/dkms.git
docbook-xml.spec,https://github.com/docbook/docbook/archive/refs/tags/%{version}.zip,https://github.com/docbook/docbook.git
docker.spec,https://github.com/moby/moby/archive/refs/tags/docker-v%{version}.tar.gz,https://github.com/moby/moby.git,,,"docker-v"
docker-20.10.spec,https://github.com/moby/moby/archive/refs/tags/v%{version}.tar.gz,https://github.com/moby/moby.git
docker-buildx.spec,https://github.com/docker/buildx/archive/refs/tags/v%{version}.tar.gz,https://github.com/docker/buildx.git
docker-compose.spec,https://github.com/docker/compose/archive/refs/tags/v%{version}.tar.gz,https://github.com/docker/compose.git
docker-py.spec,https://github.com/docker/docker-py/releases/download/%{version}/docker-%{version}.tar.gz,https://github.com/docker/docker-py.git
docker-pycreds.spec,https://github.com/shin-/dockerpy-creds/archive/refs/tags/%{version}.tar.gz,https://github.com/shin-/dockerpy-creds.git
dool.spec,https://github.com/scottchiefbaker/dool/archive/refs/tags/v%{version}.tar.gz,https://github.com/scottchiefbaker/dool.git
dos2unix.spec,https://waterlan.home.xs4all.nl/dos2unix/dos2unix-%{version}.tar.gz,https://git.code.sf.net/p/dos2unix/dos2unix.git
dosfstools.spec,https://github.com/dosfstools/dosfstools/releases/download/v%{version}/dosfstools-%{version}.tar.gz,https://github.com/dosfstools/dosfstools.git
dotnet-runtime.spec,https://github.com/dotnet/runtime/archive/refs/tags/v%{version}.tar.gz,https://github.com/dotnet/runtime.git
dotnet-sdk.spec,https://github.com/dotnet/sdk/archive/refs/tags/v%{version}.tar.gz,https://github.com/dotnet/sdk.git
double-conversion.spec,https://github.com/google/double-conversion/archive/refs/tags/v%{version}.tar.gz,https://github.com/google/double-conversion.git
doxygen.spec,https://github.com/doxygen/doxygen/archive/refs/tags/Release_%{version}.tar.gz,https://github.com/doxygen/doxygen.git
dracut.spec,https://github.com/dracutdevs/dracut/archive/refs/tags/%{version}.tar.gz,https://github.com/dracutdevs/dracut.git,,,,"033-502"
drpm.spec,https://github.com/rpm-software-management/drpm/archive/refs/tags/%{version}.tar.gz,https://github.com/rpm-software-management/drpm.git
dstat.spec,https://github.com/dstat-real/dstat/archive/refs/tags/v%{version}.tar.gz,https://github.com/dstat-real/dstat.git,,,,,1,2020-11-26
dtc.spec,https://www.kernel.org/pub/software/utils/%{name}/%{name}-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/dtc/dtc.git
duktape.spec,https://github.com/svaarala/duktape/archive/refs/tags/v%{version}.tar.gz,https://github.com/svaarala/duktape.git
ebtables.spec,https://www.netfilter.org/pub/ebtables/ebtables-v%{version}.tar.gz
ecdsa.spec,https://github.com/tlsfuzzer/python-ecdsa/archive/refs/tags/python-ecdsa-%{version}.tar.gz,https://github.com/tlsfuzzer/python-ecdsa.git,,,"python-ecdsa-"
ed.spec,https://ftp.gnu.org/gnu/ed/ed-%{version}.tar.lz
edgex.spec,https://github.com/edgexfoundry/edgex-go/archive/refs/tags/v%{version}.tar.gz,https://github.com/edgexfoundry/edgex-go.git
efibootmgr.spec,https://github.com/rhboot/efibootmgr/archive/refs/tags/%{version}.tar.gz,https://github.com/rhboot/efibootmgr.git
efivar.spec,https://github.com/rhboot/efivar/releases/download/%{version}/efivar-%{version}.tar.bz2,https://github.com/rhboot/efivar.git
elasticsearch.spec,https://github.com/elastic/elasticsearch/archive/refs/tags/v%{version}.tar.gz,https://github.com/elastic/elasticsearch.git
elixir.spec,https://github.com/elixir-lang/elixir/archive/v%{version}/elixir-%{version}.tar.gz,https://github.com/elixir-lang/elixir.git
emacs.spec,https://ftp.gnu.org/gnu/emacs/emacs-%{version}.tar.xz
entchant.spec,https://github.com/rrthomas/enchant/archive/refs/tags/v%{version}.tar.gz,https://github.com/rrthomas/enchant.git
erlang.spec,https://github.com/erlang/otp/archive/refs/tags/OTP-%{version}.tar.gz,https://github.com/erlang/otp.git,,erlang,"R16B,OTP-,erl_1211-bp"
erlang-sd_notify.spec,https://github.com/systemd/erlang-sd_notify/archive/refs/tags/v%{version}.tar.gz,https://github.com/systemd/erlang-sd_notify.git
etcd.spec,https://github.com/etcd-io/etcd/archive/refs/tags/v%{version}.tar.gz,https://github.com/etcd-io/etcd.git
ethtool.spec,https://git.kernel.org/pub/scm/network/ethtool/ethtool.git/snapshot/ethtool-%{version}.tar.gz,https://git.kernel.org/pub/scm/network/ethtool/ethtool.git
expat.spec,https://github.com/libexpat/libexpat/releases/download/R_%{version}/expat-%{version}.tar.xz,https://github.com/libexpat/libexpat.git
fail2ban.spec,https://github.com/fail2ban/fail2ban/archive/refs/tags/%{version}.tar.gz,https://github.com/fail2ban/fail2ban.git
fakeroot.spec,https://salsa.debian.org/clint/fakeroot/-/archive/debian/%{version}/fakeroot-debian-%{version}.tar.gz,https://salsa.debian.org/clint/fakeroot.git
fakeroot-ng.spec,https://master.dl.sourceforge.net/project/fakerootng/fakeroot-ng/fakeroot-ng-%{version}.tar.gz,https://git.code.sf.net/p/fakerootng/source.git
falco.spec,https://github.com/falcosecurity/falco/archive/refs/tags/%{version}.tar.gz,https://github.com/falcosecurity/falco.git
fatrace.spec,https://github.com/martinpitt/fatrace/archive/refs/tags/%{version}.tar.gz,https://github.com/martinpitt/fatrace.git
file.spec,http://ftp.astron.com/pub/file/file-%{version}.tar.gz
fio.spec,https://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git/snapshot/%{name}-%{version}.tar.gz,https://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git
flannel.spec,https://github.com/flannel-io/flannel/archive/refs/tags/v%{version}.tar.gz,https://github.com/flannel-io/flannel.git
flex.spec,https://github.com/westes/flex/archive/refs/tags/v%{version}.tar.gz,https://github.com/westes/flex.git
fmt.spec,https://github.com/fmtlib/fmt/archive/refs/tags/%{version}.tar.gz,https://github.com/fmtlib/fmt.git
fontconfig.spec,,https://gitlab.freedesktop.org/fontconfig/fontconfig.git
fping.spec,https://github.com/schweikert/fping/archive/refs/tags/v%{version}.tar.gz,https://github.com/schweikert/fping.git
freetds.spec,https://github.com/FreeTDS/freetds/archive/refs/tags/v%{version}.tar.gz,https://github.com/FreeTDS/freetds.git
fribidi.spec,https://github.com/fribidi/fribidi/archive/refs/tags/v%{version}.tar.gz,https://github.com/fribidi/fribidi.git
frr.spec,https://github.com/FRRouting/frr/archive/refs/tags/frr-%{version}.tar.gz,https://github.com/FRRouting/frr.git
fsarchiver.spec,https://github.com/fdupoux/fsarchiver/releases/download/%{version}/fsarchiver-%{version}.tar.gz,https://github.com/fdupoux/fsarchiver.git
fuse.spec,https://github.com/libfuse/libfuse/releases/download/fuse-2.%{version}/fuse-2.%{version}.tar.gz,https://github.com/libfuse/libfuse.git
fuse3.spec,https://github.com/libfuse/libfuse/releases/download/fuse-3.%{version}/fuse-3.%{version}.tar.gz,https://github.com/libfuse/libfuse.git
fuse-overlayfs-snapshotter.spec,https://github.com/containers/fuse-overlayfs/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/fuse-overlayfs.git
fuse-overlayfs.spec,https://github.com/containers/fuse-overlayfs/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/fuse-overlayfs.git
gcovr.spec,https://github.com/gcovr/gcovr/archive/refs/tags/%{version}.tar.gz,https://github.com/gcovr/gcovr.git
gdk-pixbuf.spec,https://github.com/GNOME/gdk-pixbuf/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gdk-pixbuf.git
geoip-api-c.spec,https://github.com/maxmind/geoip-api-c/releases/download/v%{version}/GeoIP-%{version}.tar.gz,https://github.com/maxmind/geoip-api-c.git
geos.spec,https://github.com/libgeos/geos/archive/refs/tags/%{version}.tar.gz,https://github.com/libgeos/geos.git
getdns.spec,https://github.com/getdnsapi/getdns/archive/refs/tags/v%{version}.tar.gz,https://github.com/getdnsapi/getdns.git
gflags.spec,https://github.com/gflags/gflags/archive/refs/tags/v%{version}.tar.gz,https://github.com/gflags/gflags.git
git.spec,https://www.kernel.org/pub/software/scm/git/%{name}-%{version}.tar.xz,https://git.kernel.org/pub/scm/git/git.git
git-lfs.spec,https://github.com/git-lfs/git-lfs/archive/refs/tags/v%{version}.tar.gz,https://github.com/git-lfs/git-lfs.git
glib.spec,https://github.com/GNOME/glib/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/glib.git
glibmm.spec,https://github.com/GNOME/glibmm/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/glibmm.git
glib-networking.spec,https://github.com/GNOME/glib-networking/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/glib-networking.git
glide.spec,https://github.com/Masterminds/glide/archive/refs/tags/v%{version}.tar.gz,https://github.com/Masterminds/glide.git
glog.spec,https://github.com/google/glog/archive/refs/tags/v%{version}tar.gz,https://github.com/google/glog.git
glslang.spec,https://github.com/KhronosGroup/glslang/archive/refs/tags/%{version}.tar.gz,https://github.com/KhronosGroup/glslang.git
gnome-common.spec,https://download.gnome.org/sources/gnome-common/3.18/gnome-common-%{version}.tar.xz
gnupg.spec,https://github.com/gpg/gnupg/archive/refs/tags/gnupg-%{version}.tar.gz,https://github.com/gpg/gnupg.git
gnuplot.spec,https://github.com/gnuplot/gnuplot/archive/refs/tags/%{version}.tar.gz,https://github.com/gnuplot/gnuplot.git
gnutls.spec,https://github.com/gnutls/gnutls/archive/refs/tags/%{version}.tar.gz,https://github.com/gnutls/gnutls.git
go.spec,https://github.com/golang/go/archive/refs/tags/go%{version}.tar.gz,https://github.com/golang/go.git
go-md2man.spec,https://github.com/cpuguy83/go-md2man/archive/refs/tags/v%{version}.tar.gz,https://github.com/cpuguy83/go-md2man.git
gobgp.spec,https://github.com/osrg/gobgp/archive/refs/tags/v%{version}.tar.gz,https://github.com/osrg/gobgp.git
gobject-introspection.spec,https://github.com/GNOME/gobject-introspection/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gobject-introspection.git
google-benchmark.spec,https://github.com/google/benchmark/archive/refs/tags/v%{version}.tar.gz,https://github.com/google/benchmark.git
google-compute-engine.spec,https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/v%{version}.tar.gz,https://github.com/GoogleCloudPlatform/compute-image-packages.git
google-guest-agent.spec,https://github.com/GoogleCloudPlatform/guest-agent/archive/refs/tags/%{version}.tar.gz,https://github.com/GoogleCloudPlatform/guest-agent.git
google-guest-configs.spec,https://github.com/GoogleCloudPlatform/guest-configs/archive/refs/tags/%{version}.tar.gz,https://github.com/GoogleCloudPlatform/guest-configs.git
google-guest-oslogin.spec,https://github.com/GoogleCloudPlatform/guest-oslogin/archive/refs/tags/%{version}.tar.gz,https://github.com/GoogleCloudPlatform/guest-oslogin.git
govmomi.spec,https://github.com/vmware/govmomi/archive/refs/tags/v%{version}.0.tar.gz,https://github.com/vmware/govmomi.git
gperftools.spec,https://github.com/gperftools/gperftools/releases/download/gperftools-%{version}/gperftools-%{version}.tar.gz,https://github.com/gperftools/gperftools.git
gptfdisk.spec,https://netix.dl.sourceforge.net/project/gptfdisk/gptfdisk/%{version}/gptfdisk-%{version}.tar.gz,https://git.code.sf.net/p/gptfdisk/code.git
graphene.spec,https://github.com/ebassi/graphene/archive/refs/tags/%{version}.tar.gz,https://github.com/ebassi/graphene.git
grpc.spec,https://github.com/grpc/grpc/archive/refs/tags/v%{version}.tar.gz,https://github.com/grpc/grpc.git
gssntlmssp.spec,https://github.com/gssapi/gss-ntlmssp/releases/download/v%{version}/gssntlmssp-%{version}.tar.gz,https://github.com/gssapi/gss-ntlmssp.git
gst-plugins-bad.spec,,https://gitlab.freedesktop.org/gstreamer/gst-plugins-bad.git
gstreamer.spec,,https://gitlab.freedesktop.org/gstreamer/gstreamer.git
gstreamer-plugins-base.spec,https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-%{version}.tar.xz,https://gitlab.freedesktop.org/gstreamer/gstreamer.git,,gst-plugins-base-
gtest.spec,https://github.com/google/googletest/archive/refs/tags/release-%{version}.tar.gz,https://github.com/google/googletest.git
gtk3.spec,https://github.com/GNOME/gtk/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gtk.git
gtk-doc.spec,https://github.com/GNOME/gtk-doc/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gtk-doc.git
guile.spec,https://ftp.gnu.org/gnu/guile/guile-%{version}.tar.gz
haproxy.spec,https://www.haproxy.org/download/3.2/src/haproxy-%{version}.tar.gz,https://github.com/haproxy/haproxy.git
haproxy-dataplaneapi.spec,https://github.com/haproxytech/dataplaneapi/archive/refs/tags/v%{version}.tar.gz,https://github.com/haproxytech/dataplaneapi.git
harfbuzz.spec,,https://github.com/harfbuzz/harfbuzz.git
haveged.spec,https://github.com/jirka-h/haveged/archive/refs/tags/v%{version}.tar.gz,https://github.com/jirka-h/haveged.git
hawkey.spec,https://github.com/rpm-software-management/hawkey/archive/refs/tags/hawkey-%{version}.tar.gz,https://github.com/rpm-software-management/hawkey.git
heapster.spec,https://github.com/kubernetes-retired/heapster/archive/refs/tags/v%{version}.tar.gz,https://github.com/kubernetes-retired/heapster.git
hiredis.spec,https://github.com/redis/hiredis/archive/refs/tags/v%{version}.tar.gz,https://github.com/redis/hiredis.git
htop.spec,https://github.com/htop-dev/htop/archive/refs/tags/%{version}.tar.gz,https://github.com/htop-dev/htop.git
httpd.spec,https://github.com/apache/httpd/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/httpd.git,"trunk"
httpd-mod_jk.spec,https://github.com/apache/tomcat-connectors/archive/refs/tags/JK_%{version}.tar.gz,https://github.com/apache/tomcat-connectors.git,,,"JK_"
http-parser.spec,https://github.com/nodejs/http-parser/archive/refs/tags/v%{version}.tar.gz,https://github.com/nodejs/http-parser.git
hunspell.spec,https://github.com/hunspell/hunspell/releases/download/v%{version}/hunspell-%{version}.tar.gz,https://github.com/hunspell/hunspell.git
hyperscan.spec,https://github.com/intel/hyperscan/archive/refs/tags/v%{version}.tar.gz,https://github.com/intel/hyperscan.git
i2c-tools.spec,https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/snapshot/i2c-tools-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git
iana-etc.spec,https://github.com/Mic92/iana-etc/releases/download/%{version}/iana-etc-%{version}.tar.gz,https://github.com/Mic92/iana-etc.git
ibmtpm.spec,https://github.com/kgoldman/ibmswtpm2/archive/refs/tags/rev183-%{version}.tar.gz,https://github.com/kgoldman/ibmswtpm2.git,,,"rev183-"
icu.spec,https://github.com/unicode-org/icu/releases/download/release-73-1/icu4c-73_1-src.tgz,https://github.com/unicode-org/icu.git
imagemagick.spec,https://github.com/ImageMagick/ImageMagick/archive/refs/tags/%{version}.tar.gz,https://github.com/ImageMagick/ImageMagick.git
ImageMagick.spec,https://github.com/ImageMagick/ImageMagick/archive/refs/tags/%{version}.tar.gz,https://github.com/ImageMagick/ImageMagick.git
influxdb.spec,https://github.com/influxdata/influxdb/archive/refs/tags/v%{version}.tar.gz,https://github.com/influxdata/influxdb.git
inih.spec,https://github.com/benhoyt/inih/archive/refs/tags/r%{version}.tar.gz,https://github.com/benhoyt/inih.git,,,"r"
iniparser.spec,https://github.com/ndevilla/iniparser/archive/refs/tags/v%{version}.tar.gz,https://github.com/ndevilla/iniparser.git
initscripts.spec,https://github.com/fedora-sysv/initscripts/archive/refs/tags/%{version}.tar.gz,https://github.com/fedora-sysv/initscripts.git
intltool.spec,https://launchpad.net/intltool/trunk/%{version}/+download/intltool-%{version}.tar.gz
ipcalc.spec,https://gitlab.com/ipcalc/ipcalc/-/archive/%{version}/ipcalc-%{version}.tar.gz,https://gitlab.com/ipcalc/ipcalc.git
iperf.spec,https://github.com/esnet/iperf/archive/refs/tags/%{version}.tar.gz,https://github.com/esnet/iperf.git
ipmitool.spec,https://github.com/ipmitool/ipmitool/archive/refs/tags/IPMITOOL_%{version}.tar.gz,https://github.com/ipmitool/ipmitool.git
iproute2.spec,,https://git.kernel.org/pub/scm/network/iproute2/iproute2.git,,,
ipset.spec,https://ipset.netfilter.org/ipset-%{version}.tar.bz2
iptables.spec,https://www.netfilter.org/projects/iptables/files/iptables-%{version}.tar.xz
iptraf-ng.spec,https://github.com/iptraf-ng/iptraf-ng/archive/refs/tags/v%{version}.tar.gz,https://github.com/iptraf-ng/iptraf-ng.git
iputils.spec,https://github.com/iputils/iputils/archive/refs/tags/s%{version}.tar.gz,https://github.com/iputils/iputils.git
ipvsadm.spec,,https://git.kernel.org/pub/scm/utils/kernel/ipvsadm/ipvsadm.git
ipxe.spec,https://github.com/ipxe/ipxe/archive/refs/tags/v%{version}.tar.gz,https://github.com/ipxe/ipxe.git
irqbalance.spec,https://github.com/Irqbalance/irqbalance/archive/refs/tags/v%{version}.tar.gz,https://github.com/Irqbalance/irqbalance.git
isa-l.spec,https://github.com/intel/isa-l/archive/refs/tags/v%{version}.tar.gz,https://github.com/intel/isa-l.git
jansson.spec,https://github.com/akheron/jansson/archive/refs/tags/v%{version}.tar.gz,https://github.com/akheron/jansson.git
jemalloc.spec,https://github.com/jemalloc/jemalloc/releases/download/%{version}/jemalloc-%{version}.tar.bz2,https://github.com/jemalloc/jemalloc.git
jc.spec,https://github.com/kellyjonbrazil/jc/archive/refs/tags/v%{version}.tar.gz,https://github.com/kellyjonbrazil/jc.git
jq.spec,https://github.com/jqlang/jq/archive/refs/tags/jq-%{version}.tar.gz,https://github.com/jqlang/jq.git
json-glib.spec,https://github.com/GNOME/json-glib/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/json-glib.git
jsoncpp.spec,https://github.com/open-source-parsers/jsoncpp/archive/refs/tags/%{version}.tar.gz,https://github.com/open-source-parsers/jsoncpp.git
kafka.spec,https://github.com/apache/kafka/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/kafka.git,,,"0.10.2.0-KAFKA-5526"
kapacitor.spec,https://github.com/influxdata/kapacitor/archive/refs/tags/v%{version}.tar.gz,https://github.com/influxdata/kapacitor.git
kbd.spec,https://github.com/legionus/kbd/archive/refs/tags/%{version}.tar.gz,https://github.com/legionus/kbd.git
keepalived.spec,https://github.com/acassen/keepalived/archive/refs/tags/v%{version}.tar.gz,https://github.com/acassen/keepalived.git
kexec-tools.spec,https://www.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools-%{version}.tar.xz,https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git
keyutils.spec,https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-%{version}.tar.gz,https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git
kibana.spec,https://github.com/elastic/kibana/archive/refs/tags/v%{version}.tar.gz,https://github.com/elastic/kibana.git
kmod.spec,,https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git,,,
kpatch.spec,https://github.com/dynup/kpatch/archive/refs/tags/v%{version}.tar.gz,https://github.com/dynup/kpatch.git
krb5.spec,https://github.com/krb5/krb5/archive/refs/tags/krb5-%{version}-final.tar.gz,https://github.com/krb5/krb5.git
ktap.spec,https://github.com/ktap/ktap/archive/refs/tags/v%{version}.tar.gz,https://github.com/ktap/ktap.git
kube-bench.spec,https://github.com/aquasecurity/kube-bench/archive/refs/tags/v%{version}.tar.gz,https://github.com/aquasecurity/kube-bench.git
kube-controllers.spec,https://github.com/projectcalico/kube-controllers/archive/refs/tags/v%{version}.tar.gz,https://github.com/projectcalico/kube-controllers.git,,,,,1,2025-10-20
kubernetes-dashboard.spec,https://github.com/kubernetes-retired/dashboard/archive/refs/tags/kubernetes-dashboard-%{version}.tar.gz,https://github.com/kubernetes-retired/dashboard.git
kubernetes-dns.spec,https://github.com/kubernetes/dns/archive/refs/tags/%{version}.tar.gz,https://github.com/kubernetes/dns.git
kubernetes-metrics-server.spec,https://github.com/kubernetes-sigs/metrics-server/archive/refs/tags/v%{version}.tar.gz,https://github.com/kubernetes-sigs/metrics-server.git
kubernetes.spec,https://github.com/kubernetes/kubernetes/archive/refs/tags/v%{version}.tar.gz,https://github.com/kubernetes/kubernetes.git
lapack.spec,https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v%{version}.tar.gz,https://github.com/Reference-LAPACK/lapack.git
lasso.spec,https://dev.entrouvert.org/lasso/lasso-%{version}.tar.gz
less.spec,https://github.com/gwsw/less/archive/refs/tags/v%{version}.tar.gz,https://github.com/gwsw/less.git
leveldb.spec,https://github.com/google/leveldb/archive/refs/tags/v%{version}.tar.gz,https://github.com/google/leveldb.git
libaio.spec,https://pagure.io/libaio/archive/libaio-{version}/libaio-libaio-{version}.tar.gz,https://pagure.io/libaio.git
libarchive.spec,https://github.com/libarchive/libarchive/archive/refs/tags/v%{version}.tar.gz,https://github.com/libarchive/libarchive.git
libatomic_ops.spec,https://github.com/ivmai/libatomic_ops/archive/refs/tags/v%{version}.tar.gz,https://github.com/ivmai/libatomic_ops.git
libbpf.spec,https://github.com/libbpf/libbpf/archive/refs/tags/v%{version}.tar.gz,https://github.com/libbpf/libbpf.git
libcalico.spec,https://github.com/projectcalico/libcalico/archive/refs/tags/v%{version}.tar.gz,https://github.com/projectcalico/libcalico.git,,,,,1,2019-10-22
libcap.spec,,https://git.kernel.org/pub/scm/libs/libcap/libcap.git
libcap-ng.spec,https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v%{version}.tar.gz,https://github.com/stevegrubb/libcap-ng.git
libcbor.spec,https://github.com/PJK/libcbor/archive/refs/tags/v%{version}.tar.gz,https://github.com/PJK/libcbor.git
libcgroup.spec,https://github.com/libcgroup/libcgroup/archive/refs/tags/v%{version}.tar.gz,https://github.com/libcgroup/libcgroup.git
libclc.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/libclc-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git
libconfig.spec,https://github.com/hyperrealm/libconfig/archive/refs/tags/v%{version}.tar.gz,https://github.com/hyperrealm/libconfig.git
libdaemon.spec,https://0pointer.de/lennart/projects/libdaemon/libdaemon-%{version}.tar.gz
libdb.spec,https://github.com/berkeleydb/libdb/archive/refs/tags/v%{version}.tar.gz,https://github.com/berkeleydb/libdb.git
libdrm.spec,https://gitlab.freedesktop.org/mesa/libdrm/-/archive/libdrm-%{version}/libdrm-libdrm-%{version}.tar.gz,https://gitlab.freedesktop.org/mesa/libdrm.git
libedit.spec,https://www.thrysoee.dk/editline/libedit-20251016-3.1.tar.gz
libepoxy.spec,https://github.com/anholt/libepoxy/archive/refs/tags/%{version}.tar.gz,https://github.com/anholt/libepoxy.git
libestr.spec,https://github.com/rsyslog/libestr/archive/refs/tags/v%{version}.tar.gz,https://github.com/rsyslog/libestr.git
libev.spec,http://dist.schmorp.de/libev/Attic/libev-%{version}.tar.gz
libevent.spec,https://github.com/libevent/libevent/releases/download/release-%{version}-stable/libevent-%{version}-stable.tar.gz,https://github.com/libevent/libevent.git
libfastjson.spec,https://github.com/rsyslog/libfastjson/archive/refs/tags/v%{version}.0.tar.gz,https://github.com/rsyslog/libfastjson.git
libffi.spec,https://github.com/libffi/libffi/archive/refs/tags/v%{version}.tar.gz,https://github.com/libffi/libffi.git
libfido2.spec,https://github.com/Yubico/libfido2/archive/refs/tags/%{version}.tar.gz,https://github.com/Yubico/libfido2.git
libgcrypt.spec,https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-%{version}.tar.bz2
libgd.spec,https://github.com/libgd/libgd/releases/download/gd-%{version}/libgd-%{version}.tar.xz,https://github.com/libgd/libgd.git,,,"gd-,GD_"
libglvnd.spec,https://github.com/NVIDIA/libglvnd/archive/refs/tags/v%{version}.tar.gz,https://github.com/NVIDIA/libglvnd.git
libgpg-error.spec,https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-%{version}.tar.bz2
libgudev.spec,https://github.com/GNOME/libgudev/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/libgudev.git
libhugetlbfs.spec,https://github.com/libhugetlbfs/libhugetlbfs/releases/download/%{version}/libhugetlbfs-%{version}.tar.gz,https://github.com/libhugetlbfs/libhugetlbfs.git
libical.spec,https://github.com/libical/libical/releases/download/v%{version}/libical-%{version}.tar.gz,https://github.com/libical/libical.git
libldb.spec,https://gitlab.com/samba-team/devel/samba/-/archive/ldb-%{version}/samba-ldb-%{version}.tar.gz
liblogging.spec,https://github.com/rsyslog/liblogging/archive/refs/tags/v%{version}.tar.gz,https://github.com/rsyslog/liblogging.git
libjpeg-turbo.spec,https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/%{version}.tar.gz,https://github.com/libjpeg-turbo/libjpeg-turbo.git
libmbim.spec,https://gitlab.freedesktop.org/mobile-broadband/libmbim/-/archive/%{version}/libmbim-%{version}.tar.gz,https://gitlab.freedesktop.org/mobile-broadband/libmbim.git
libmd.spec,https://archive.hadrons.org/software/libmd/libmd-%{version}.tar.xz,https://github.com/guillemj/libmd.git
libmetalink.spec,https://github.com/metalink-dev/libmetalink/releases/download/release-%{version}/libmetalink-%{version}.tar.bz2,https://github.com/metalink-dev/libmetalink.git
libmnl.spec,https://www.netfilter.org/projects/libmnl/files/libmnl-%{version}.tar.bz2
libmspack.spec,https://github.com/kyz/libmspack/archive/refs/tags/v%{version}.tar.gz,https://github.com/kyz/libmspack.git
libndp.spec,https://github.com/jpirko/libndp/archive/refs/tags/v%{version}.tar.gz,https://github.com/jpirko/libndp.git
libnetconf2.spec,https://github.com/CESNET/libnetconf2/archive/refs/tags/v%{version}.tar.gz,https://github.com/CESNET/libnetconf2.git
libnetfilter_conntrack.spec,https://www.netfilter.org/projects/libnetfilter_conntrack/files/libnetfilter_conntrack-%{version}.tar.xz
libnetfilter_cthelper.spec,https://www.netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-%{version}.tar.bz2
libnetfilter_cttimeout.spec,https://www.netfilter.org/projects/libnetfilter_cttimeout/files/libnetfilter_cttimeout-%{version}.tar.bz2
libnetfilter_queue.spec,https://www.netfilter.org/projects/libnetfilter_queue/files/libnetfilter_queue-%{version}.tar.bz2
libnfnetlink.spec,https://www.netfilter.org/projects/libnfnetlink/files/libnfnetlink-%{version}.tar.bz2,https://git.netfilter.org/libnfnetlink.git
libnftnl.spec,https://www.netfilter.org/projects/libnftnl/files/libnftnl-%{version}.tar.xz,https://git.netfilter.org/libnftnl.git,,,"libnftnl-"
libnl.spec,https://github.com/thom311/libnl/archive/refs/tags/libnl%{version}.tar.gz,https://github.com/thom311/libnl.git
libnss-ato.spec,https://github.com/donapieppo/libnss-ato/archive/refs/tags/v%{version}.tar.gz,https://github.com/donapieppo/libnss-ato.git
libnvme.spec,https://github.com/linux-nvme/libnvme/archive/refs/tags/v%{version}.tar.gz,https://github.com/linux-nvme/libnvme.git
libpsl.spec,https://github.com/rockdaboot/libpsl/archive/refs/tags/%{version}.tar.gz,https://github.com/rockdaboot/libpsl.git
libpwquality.spec,https://github.com/libpwquality/libpwquality/releases/download/libpwquality-%{version}/libpwquality-%{version}.tar.bz2,https://github.com/libpwquality/libpwquality.git
librdkafka.spec,https://github.com/confluentinc/librdkafka/archive/refs/tags/v%{version}.tar.gz,https://github.com/confluentinc/librdkafka.git
librelp.spec,https://download.rsyslog.com/librelp/librelp-%{version}.tar.gz
librepo.spec,https://github.com/rpm-software-management/librepo/archive/refs/tags/%{version}.tar.gz,https://github.com/rpm-software-management/librepo.git
librsync.spec,https://github.com/librsync/librsync/archive/refs/tags/v%{version}.tar.gz,https://github.com/librsync/librsync.git
libpcap.spec,https://github.com/the-tcpdump-group/libpcap/archive/refs/tags/libpcap-%{version}.tar.gz,https://github.com/the-tcpdump-group/libpcap.git
libqmi.spec,,https://gitlab.freedesktop.org/mobile-broadband/libqmi.git
libseccomp.spec,https://github.com/seccomp/libseccomp/releases/download/v%{version}/libseccomp-%{version}.tar.gz,https://github.com/seccomp/libseccomp.git
libselinux.spec,https://github.com/SELinuxProject/selinux/archive/refs/tags/libselinux-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git
libsemanage.spec,https://github.com/SELinuxProject/selinux/releases/download/%{version}/libsemanage-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git
libsigc++.spec,https://github.com/libsigcplusplus/libsigcplusplus/archive/refs/tags/%{version}.tar.gz,https://github.com/libsigcplusplus/libsigcplusplus.git
libslirp.spec,https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v%{version}/libslirp-v%{version}.tar.gz,https://gitlab.freedesktop.org/slirp/libslirp.git
libsolv.spec,https://github.com/openSUSE/libsolv/archive/refs/tags/%{version}.tar.gz,https://github.com/openSUSE/libsolv.git
libsoup.spec,https://github.com/GNOME/libsoup/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/libsoup.git
libssh.spec,https://www.libssh.org/files/0.11/libssh-%{version}.tar.xz,https://git.libssh.org/projects/libssh.git
libssh2.spec,https://github.com/libssh2/libssh2/archive/refs/tags/libssh2-%{version}.tar.gz,https://github.com/libssh2/libssh2.git
libtalloc.spec,https://gitlab.com/samba-team/devel/samba/-/archive/talloc-%{version}/talloc-%{version}.tar.gz
libtar.spec,https://github.com/tklauser/libtar/archive/refs/tags/v%{version}.tar.gz,https://github.com/tklauser/libtar.git
libtdb.spec,https://gitlab.com/samba-team/devel/samba/-/archive/tdb-%{version}/tdb-%{version}.tar.gz
libtevent.spec,https://gitlab.com/samba-team/devel/samba/-/archive/tevent-%{version}/tevent-%{version}.tar.gz
libteam.spec,https://github.com/jpirko/libteam/archive/refs/tags/v%{version}.tar.gz,https://github.com/jpirko/libteam.git
libtiff.spec,,https://gitlab.com/libtiff/libtiff.git
libtirpc.spec,https://unlimited.dl.sourceforge.net/project/libtirpc/libtirpc/%{version}/libtirpc-%{version}.tar.bz2,git://linux-nfs.org/~steved/libtirpc.git
libtraceevent.spec,,https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git
libtracefs.spec,,https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git
libuv.spec,https://github.com/libuv/libuv/archive/refs/tags/v%{version}.tar.gz,https://github.com/libuv/libuv.git
libvirt.spec,https://github.com/libvirt/libvirt/archive/refs/tags/v%{version}.tar.gz,https://github.com/libvirt/libvirt.git
libwebp.spec,https://github.com/webmproject/libwebp/archive/refs/tags/v%{version}.tar.gz,https://github.com/webmproject/libwebp.git
libX11.spec,https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-%{version}/libx11-libX11-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libx11.git
libx11.spec,https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-%{version}/libx11-libX11-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libx11.git
libxcb.spec,https://gitlab.freedesktop.org/xorg/lib/libxcb/-/archive/libxcb-%{version}/libxcb-libxcb-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libxcb.git
libxcrypt.spec,https://github.com/besser82/libxcrypt/releases/download/v%{version}/libxcrypt-%{version}.tar.xz,https://github.com/besser82/libxcrypt.git
libxkbcommon.spec,https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-%{version}.tar.gz,https://github.com/xkbcommon/libxkbcommon.git,,,"xkbcommon-"
libXinerama.spec,https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-%{version}/libxinerama-libXinerama-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libxinerama.git
libxinerama.spec,https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-%{version}/libxinerama-libXinerama-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libxinerama.git
libxml2.spec,https://github.com/GNOME/libxml2/archive/refs/tags/v%{version}.tar.gz,https://github.com/GNOME/libxml2.git
libxslt.spec,https://github.com/GNOME/libxslt/archive/refs/tags/v%{version}.tar.gz,https://github.com/GNOME/libxslt.git
libyaml.spec,https://github.com/yaml/libyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/libyaml.git
libyang.spec,https://github.com/CESNET/libyang/archive/refs/tags/v%{version}.tar.gz,https://github.com/CESNET/libyang.git
lightstep-tracer-cpp.spec,https://github.com/lightstep/lightstep-tracer-cpp/archive/refs/tags/v%{version}.0.tar.gz,,,,,"v0_"
lighttpd.spec,https://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-%{version}.tar.gz,https://git.lighttpd.net/lighttpd/lighttpd1.4.git,,,
lightwave.spec,https://github.com/vmware-archive/lightwave/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-archive/lightwave.git
linux-firmware.spec,https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-%{version}.tar.gz
linux-PAM.spec,https://github.com/linux-pam/linux-pam/archive/refs/tags/Linux-PAM-%{version}.tar.gz,https://github.com/linux-pam/linux-pam.git
Linux-PAM.spec,https://github.com/linux-pam/linux-pam/archive/refs/tags/Linux-PAM-%{version}.tar.gz,https://github.com/linux-pam/linux-pam.git
linuxptp.spec,https://github.com/richardcochran/linuxptp/archive/refs/tags/v%{version}.tar.gz,https://github.com/richardcochran/linuxptp.git
liota.spec,https://github.com/vmware-archive/liota/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-archive/liota.git,,,,,1,2021-03-15
lksctp-tools.spec,https://github.com/sctp/lksctp-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/sctp/lksctp-tools.git
lldb.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/lldb-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git,,,"llvmorg-"
lldpad.spec,https://github.com/intel/openlldp/archive/refs/tags/v%{version}.tar.gz,https://github.com/intel/openlldp.git
llvm.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/llvm-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git,,,"llvmorg-"
lm-sensors.spec,https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V%{version}.tar.gz,https://github.com/lm-sensors/lm-sensors.git
log4cpp.spec,https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-%{version}.tar.gz?viasf=1,https://git.code.sf.net/p/log4cpp/codegit.git
logstash.spec,https://github.com/elastic/logstash/archive/refs/tags/v%{version}.tar.gz,https://github.com/elastic/logstash.git
lshw.spec,https://github.com/lyonel/lshw/archive/refs/tags/%{version}.tar.gz,https://github.com/lyonel/lshw.git,,,"B."
lsof.spec,https://github.com/lsof-org/lsof/archive/refs/tags/%{version}.tar.gz,https://github.com/lsof-org/lsof.git
lttng-tools.spec,https://github.com/lttng/lttng-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/lttng/lttng-tools.git
lttng-ust.spec,https://lttng.org/files/lttng-ust/lttng-ust-%{version}.tar.bz2
lvm2.spec,https://github.com/lvmteam/lvm2/archive/refs/tags/v%{version}.tar.gz,https://github.com/lvmteam/lvm2.git
lxcfs.spec,https://github.com/lxc/lxcfs/archive/refs/tags/lxcfs-%{version}.tar.gz,https://github.com/lxc/lxcfs.git
lz4.spec,https://github.com/lz4/lz4/releases/download/v%{version}/lz4-%{version}.tar.gz,https://github.com/lz4/lz4.git
lzo.spec,http://www.oberhumer.com/opensource/lzo/download/lzo-%{version}.tar.gz
man-db.spec,https://gitlab.com/man-db/man-db/-/archive/%{version}/man-db-%{version}.tar.gz,https://gitlab.com/man-db/man-db.git
man-pages.spec,https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git/snapshot/man-pages-%{version}.tar.gz,https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git
mariadb.spec,https://github.com/MariaDB/server/archive/refs/tags/mariadb-%{version}.tar.gz,https://github.com/MariaDB/server.git
mc.spec,https://github.com/MidnightCommander/mc/archive/refs/tags/%{version}.tar.gz,https://github.com/MidnightCommander/mc.git
memcached.spec,https://github.com/memcached/memcached/archive/refs/tags/%{version}.tar.gz,https://github.com/memcached/memcached.git
mesa.spec,https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-%{version}/mesa-mesa-%{version}.tar.gz,https://gitlab.freedesktop.org/mesa/mesa.git
meson.spec,https://github.com/mesonbuild/meson/releases/download/%{version}/meson-%{version}.tar.gz,https://github.com/mesonbuild/meson.git
mkinitcpio.spec,https://github.com/archlinux/mkinitcpio/archive/refs/tags/v%{version}.tar.gz,https://github.com/archlinux/mkinitcpio.git
mm-common.spec,,https://gitlab.gnome.org/GNOME/mm-common.git
ModemManager.spec,,https://gitlab.freedesktop.org/modemmanager/modemmanager.git
modemmanager.spec,,https://gitlab.freedesktop.org/modemmanager/modemmanager.git
mokutil.spec,https://github.com/lcp/mokutil/archive/refs/tags/%{version}.tar.gz,https://github.com/lcp/mokutil.git
monitoring-plugins.spec,https://github.com/monitoring-plugins/monitoring-plugins/archive/refs/tags/v%{version}.tar.gz,https://github.com/monitoring-plugins/monitoring-plugins.git
msr-tools.spec,https://github.com/intel/msr-tools/archive/refs/tags/msr-tools-%{version}.tar.gz,https://github.com/intel/msr-tools.git
mpc.spec,https://www.multiprecision.org/downloads/mpc-%{version}.tar.gz
mysql.spec,https://github.com/mysql/mysql-server/archive/refs/tags/mysql-%{version}.tar.gz,https://github.com/mysql/mysql-server.git
nano.spec,https://ftpmirror.gnu.org/nano/nano-%{version}.tar.xz,https://git.savannah.gnu.org/git/nano.git
nasm.spec,https://github.com/netwide-assembler/nasm/archive/refs/tags/nasm-%{version}.tar.gz,https://github.com/netwide-assembler/nasm.git
ncurses.spec,https://github.com/ThomasDickey/ncurses-snapshots/archive/refs/tags/v%{version}.tar.gz,https://github.com/ThomasDickey/ncurses-snapshots.git
ndctl.spec,https://github.com/pmem/ndctl/archive/refs/tags/v%{version}.tar.gz,https://github.com/pmem/ndctl.git
nerdctl.spec,https://github.com/containerd/nerdctl/archive/refs/tags/v%{version}.tar.gz,https://github.com/containerd/nerdctl.git
net-snmp.spec,https://github.com/net-snmp/net-snmp/archive/refs/tags/v%{version}.tar.gz,https://github.com/net-snmp/net-snmp.git
net-tools.spec,https://github.com/ecki/net-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/ecki/net-tools.git
netkit-telnet.spec,https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/%{version}/netkit-telnet-debian-%{version}.tar.gz,https://salsa.debian.org/debian/netkit-telnet.git
netmgmt.spec,https://github.com/vmware/photonos-netmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/photonos-netmgr.git
network-config-manager.spec,https://github.com/vmware/network-config-manager/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/network-config-manager.git
network-event-broker.spec,https://github.com/vmware/network-event-broker/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/network-event-broker.git
newt.spec,https://github.com/mlichvar/newt/archive/refs/tags/r%{version}.tar.gz,https://github.com/mlichvar/newt.git
nftables.spec,https://www.netfilter.org/projects/nftables/files/nftables-%{version}.tar.xz
nghttp2.spec,https://github.com/nghttp2/nghttp2/releases/download/v%{version}/nghttp2-%{version}.tar.xz,https://github.com/nghttp2/nghttp2.git
nginx.spec,https://github.com/nginx/nginx/archive/refs/tags/release-%{version}.tar.gz,https://github.com/nginx/nginx.git
nginx-ingress.spec,https://github.com/nginxinc/kubernetes-ingress/archive/refs/tags/v%{version}.tar.gz,https://github.com/nginxinc/kubernetes-ingress.git
ninja-build.spec,https://github.com/ninja-build/ninja/archive/refs/tags/v%{version}.tar.gz,https://github.com/ninja-build/ninja.git
nmap.spec,https://nmap.org/dist/nmap-%{version}.tar.bz2,https://github.com/nmap/nmap.git
nodejs-8.17.0.spec,https://nodejs.org/download/release/v8.17.0/node-v8.17.0.tar.xz
nodejs-9.11.2.spec,https://nodejs.org/download/release/v9.11.2/node-v9.11.2.tar.xz
nodejs-10.24.0.spec,https://nodejs.org/download/release/v10.24.0/node-v10.24.0.tar.xz
nss-altfiles.spec,https://github.com/aperezdc/nss-altfiles/archive/refs/tags/v%{version}.tar.gz,https://github.com/aperezdc/nss-altfiles.git
nss-pam-ldapd.spec,https://github.com/arthurdejong/nss-pam-ldapd/archive/refs/tags/%{version}.tar.gz,https://github.com/arthurdejong/nss-pam-ldapd.git
ntp.spec,https://github.com/ntp-project/ntp/archive/refs/tags/NTP_%{version}.tar.gz,https://github.com/ntp-project/ntp.git,,,"NTP_"
nodejs.spec,https://github.com/nodejs/node/archive/refs/tags/v%{version}.tar.gz,https://github.com/nodejs/node.git
numactl.spec,https://github.com/numactl/numactl/releases/download/v%{version}/numactl-%{version}.tar.gz,https://github.com/numactl/numactl.git
nvme-cli.spec,https://github.com/linux-nvme/nvme-cli/archive/refs/tags/v%{version}.tar.gz,https://github.com/linux-nvme/nvme-cli.git
nxtgn-openssl.spec,https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1w.tar.gz,https://github.com/openssl/openssl.git
oniguruma.spec,https://github.com/kkos/oniguruma/releases/download/v%{version}/onig-%{version}.tar.gz,https://github.com/kkos/oniguruma.git
open-iscsi.spec,https://github.com/open-iscsi/open-iscsi/archive/refs/tags/%{version}.tar.gz,https://github.com/open-iscsi/open-iscsi.git
open-isns.spec,https://github.com/open-iscsi/open-isns/archive/refs/tags/v%{version}.tar.gz,https://github.com/open-iscsi/open-isns.git
open-sans-fonts.spec,https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_%{version}.orig.tar.xz,https://github.com/googlefonts/opensans.git
open-vm-tools.spec,https://github.com/vmware/open-vm-tools/archive/refs/tags/stable-%{version}.tar.gz,https://github.com/vmware/open-vm-tools.git
open-vmdk.spec,https://github.com/vmware/open-vmdk/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/open-vmdk.git
openjdk8.spec,https://github.com/openjdk/jdk8u/archive/refs/tags/jdk8u%{subversion}-ga.tar.gz,https://github.com/openjdk/jdk8u.git,,,"jdk8u,-ga"
openjdk10.spec,https://github.com/openjdk/jdk10u/archive/refs/tags/jdk-%{version}-ga.tar.gz,https://github.com/openjdk/jdk10u.git,,,"jdk-10",,1,2022-08-31
openjdk11.spec,https://github.com/openjdk/jdk11u/archive/refs/tags/jdk-%{version}.tar.gz,https://github.com/openjdk/jdk11u.git,,,"jdk-11"
openjdk17.spec,https://github.com/openjdk/jdk17u/archive/refs/tags/jdk-%{version}.tar.gz,https://github.com/openjdk/jdk17u.git,,,"jdk-17"
openjdk21.spec,https://github.com/openjdk/jdk21u/archive/refs/tags/jdk-%{version}.tar.gz,https://github.com/openjdk/jdk21u.git,,,"jdk-,-ga"
openldap.spec,https://github.com/openldap/openldap/archive/refs/tags/OPENLDAP_REL_ENG_%{version}.tar.gz,https://github.com/openldap/openldap.git,,,"UTBM_,URE_,UMICH_LDAP_3_3,UCDATA_,TWEB_OL_BASE,SLAPD_BACK_LDAP,PHP3_TOOL_0_0,OPENLDAP_REL_ENG_,LMDB_"
openresty.spec,https://github.com/openresty/openresty/archive/refs/tags/v%{version}.tar.gz,https://github.com/openresty/openresty.git
openscap.spec,https://github.com/OpenSCAP/openscap/releases/download/%{version}/openscap-%{version}.tar.gz,https://github.com/OpenSCAP/openscap.git
openssh.spec,https://github.com/openssh/openssh-portable/archive/refs/tags/V_%{version}.tar.gz,https://github.com/openssh/openssh-portable.git
ostree.spec,https://github.com/ostreedev/ostree/archive/refs/tags/v%{version}.tar.gz,https://github.com/ostreedev/ostree.git
p11-kit.spec,https://github.com/p11-glue/p11-kit/releases/download/%{version}/p11-kit-%{version}.tar.xz,https://github.com/p11-glue/p11-kit.git
pam_tacplus.spec,https://github.com/kravietz/pam_tacplus/archive/refs/tags/v%{version}.tar.gz,https://github.com/kravietz/pam_tacplus.git
pandoc.spec,https://github.com/jgm/pandoc/archive/refs/tags/%{version}.tar.gz,https://github.com/jgm/pandoc.git
pango.spec,https://github.com/GNOME/pango/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/pango.git
paramiko.spec,https://github.com/paramiko/paramiko/archive/refs/tags/%{version}.tar.gz,https://github.com/paramiko/paramiko.git
passwdqc.spec,https://github.com/openwall/passwdqc/archive/refs/tags/PASSWDQC_%{version}.tar.gz,https://github.com/openwall/passwdqc.git
password-store.spec,https://github.com/zx2c4/password-store/archive/refs/tags/%{version}.tar.gz,https://github.com/zx2c4/password-store.git
patch.spec,https://ftp.gnu.org/gnu/patch/patch-%{version}.tar.gz
pciutils.spec,https://www.kernel.org/pub/software/utils/pciutils/pciutils-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/pciutils/pciutils.git
pcre.spec,https://netix.dl.sourceforge.net/project/pcre/pcre/%{version}/pcre-%{version}.tar.bz2,https://github.com/PCRE2Project/pcre1.git
pcre2.spec,https://github.com/PCRE2Project/pcre2/releases/download/pcre2-%{version}/pcre2-%{version}.tar.gz,https://github.com/PCRE2Project/pcre2.git
pcstat.spec,https://github.com/tobert/pcstat/archive/refs/tags/v%{version}.tar.gz,https://github.com/tobert/pcstat.git
perftest.spec,https://github.com/linux-rdma/perftest/archive/refs/tags/%{version}.tar.gz,https://github.com/linux-rdma/perftest.git
perl.spec,https://github.com/Perl/perl5/archive/refs/tags/v%{version}.tar.gz,https://github.com/Perl/perl5.git
perl-URI.spec,https://github.com/libwww-perl/URI/archive/refs/tags/v%{version}.tar.gz,https://github.com/libwww-perl/URI.git
perl-CGI.spec,https://github.com/leejo/CGI.pm/archive/refs/tags/v%{version}.tar.gz,https://github.com/leejo/CGI.pm.git
perl-Config-IniFiles.spec,https://github.com/shlomif/perl-Config-IniFiles/archive/refs/tags/releases/%{version}.tar.gz,https://github.com/shlomif/perl-Config-IniFiles.git,,,"releases/"
perl-Crypt-SSLeay.spec,https://github.com/nanis/Crypt-SSLeay/archive/refs/tags/0.73_04.tar.gz,https://github.com/nanis/Crypt-SSLeay.git
perl-Data-Validate-IP.spec,https://github.com/houseabsolute/Data-Validate-IP/archive/refs/tags/v%{version}.tar.gz,https://github.com/houseabsolute/Data-Validate-IP.git
perl-DBD-SQLite.spec,https://github.com/DBD-SQLite/DBD-SQLite/archive/refs/tags/%{version}.tar.gz,https://github.com/DBD-SQLite/DBD-SQLite.git
perl-DBI.spec,https://github.com/perl5-dbi/dbi/archive/refs/tags/%{version}.tar.gz,https://github.com/perl5-dbi/dbi.git
perl-Exporter-Tiny.spec,https://github.com/tobyink/p5-exporter-tiny/archive/refs/tags/%{version}.tar.gz,https://github.com/tobyink/p5-exporter-tiny.git
perl-File-HomeDir.spec,https://github.com/perl5-utils/File-HomeDir/archive/refs/tags/%{version}.tar.gz,https://github.com/perl5-utils/File-HomeDir.git
perl-File-Which.spec,https://github.com/uperl/File-Which/archive/refs/tags/v%{version}.tar.gz,https://github.com/uperl/File-Which.git
perl-IO-Socket-SSL.spec,https://github.com/noxxi/p5-io-socket-ssl/archive/refs/tags/%{version}.tar.gz,https://github.com/noxxi/p5-io-socket-ssl.git
perl-JSON.spec,https://github.com/makamaka/JSON/archive/refs/tags/%{version}.tar.gz,https://github.com/makamaka/JSON.git
perl-JSON-Any.spec,https://github.com/karenetheridge/JSON-Any/archive/refs/tags/v%{version}.tar.gz,https://github.com/karenetheridge/JSON-Any.git
perl-libintl.spec,https://github.com/gflohr/libintl-perl/archive/refs/tags/v%{version}.tar.gz,https://github.com/gflohr/libintl-perl.git
perl-List-MoreUtils.spec,https://github.com/perl5-utils/List-MoreUtils/archive/refs/tags/%{version}.tar.gz,https://github.com/perl5-utils/List-MoreUtils.git
perl-Module-Build.spec,https://github.com/Perl-Toolchain-Gang/Module-Build/archive/refs/tags/%{version}.tar.gz,https://github.com/Perl-Toolchain-Gang/Module-Build.git
perl-Module-Install.spec,https://github.com/Perl-Toolchain-Gang/Module-Install/archive/refs/tags/%{version}.tar.gz,https://github.com/Perl-Toolchain-Gang/Module-Install.git
perl-Module-ScanDeps.spec,https://github.com/rschupp/Module-ScanDeps/archive/refs/tags/%{version}.tar.gz,https://github.com/rschupp/Module-ScanDeps.git
perl-Net-SSLeay.spec,https://github.com/radiator-software/p5-net-ssleay/archive/refs/tags/%{version}.tar.gz,https://github.com/radiator-software/p5-net-ssleay.git
perl-Object-Accessor.spec,https://github.com/jib/object-accessor/archive/refs/tags/%{version}.tar.gz,https://github.com/jib/object-accessor.git
perl-Path-Class.spec,https://github.com/kenahoo/Path-Class/archive/refs/tags/v%{version}.tar.gz,https://github.com/kenahoo/Path-Class.git
perl-TermReadKey.spec,https://github.com/jonathanstowe/TermReadKey/archive/refs/tags/%{version}.tar.gz,https://github.com/jonathanstowe/TermReadKey.git
perl-Try-Tiny.spec,https://github.com/p5sagit/Try-Tiny/archive/refs/tags/v%{version}.tar.gz,https://github.com/p5sagit/Try-Tiny.git
perl-WWW-Curl.spec,https://github.com/szbalint/WWW--Curl/archive/refs/tags/%{version}.tar.gz,https://github.com/szbalint/WWW--Curl.git
perl-YAML.spec,https://github.com/ingydotnet/yaml-pm/archive/refs/tags/%{version}.tar.gz,https://github.com/ingydotnet/yaml-pm.git
perl-YAML-Tiny.spec,https://github.com/Perl-Toolchain-Gang/YAML-Tiny/archive/refs/tags/v%{version}.tar.gz,https://github.com/Perl-Toolchain-Gang/YAML-Tiny.git
pgaudit.spec,https://github.com/pgaudit/pgaudit/archive/refs/tags/1.5.%{version}.tar.gz,https://github.com/pgaudit/pgaudit.git
pgaudit13.spec,https://github.com/pgaudit/pgaudit/archive/refs/tags/1.5.%{version}.tar.gz,https://github.com/pgaudit/pgaudit.git
pgaudit14.spec,https://github.com/pgaudit/pgaudit/archive/refs/tags/1.6.%{version}.tar.gz,https://github.com/pgaudit/pgaudit.git
pgaudit15.spec,https://github.com/pgaudit/pgaudit/archive/refs/tags/1.7.%{version}.tar.gz,https://github.com/pgaudit/pgaudit.git
pgaudit16.spec,https://github.com/pgaudit/pgaudit/archive/refs/tags/16.%{version}.tar.gz,https://github.com/pgaudit/pgaudit.git
pgaudit17.spec,https://github.com/pgaudit/pgaudit/archive/refs/tags/17.%{version}.tar.gz,https://github.com/pgaudit/pgaudit.git
pgbouncer.spec,https://github.com/pgbouncer/pgbouncer/archive/refs/tags/pgbouncer_%{version}.tar.gz,https://github.com/pgbouncer/pgbouncer.git
pgbackrest.spec,https://github.com/pgbackrest/pgbackrest/archive/refs/tags/release/%{version}.tar.gz,https://github.com/pgbackrest/pgbackrest.git
photon-checksum-generator.spec,https://github.com/vmware-archive/photon-checksum-generator/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-archive/photon-checksum-generator.git,,,,,1,2026-01-20
photon-os-container-builder.spec,https://github.com/vmware-samples/photon-os-container-builder/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-samples/photon-os-container-builder.git
photon-os-installer.spec,https://github.com/vmware/photon-os-installer/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/photon-os-installer.git
pigz.spec,https://github.com/madler/pigz/archive/refs/tags/v%{version}.tar.gz,https://github.com/madler/pigz.git
pixman.spec,,https://gitlab.freedesktop.org/pixman/pixman.git
pkg-config.spec,,https://gitlab.freedesktop.org/pkg-config/pkg-config.git
pmd.spec,https://github.com/vmware/pmd/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/pmd.git
pmd-ng.spec,https://github.com/vmware/pmd-next-gen/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/pmd-next-gen.git
pmd-nextgen.spec,https://github.com/vmware/pmd/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/pmd.git
podman.spec,https://github.com/containers/podman/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/podman.git
policycoreutils.spec,https://github.com/SELinuxProject/selinux/releases/download/%{version}/policycoreutils-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git
polkit.spec,,https://gitlab.freedesktop.org/polkit/polkit.git
popt.spec,https://github.com/rpm-software-management/popt/archive/refs/tags/popt-%{version}-release.tar.gz,https://github.com/rpm-software-management/popt.git
powershell.spec,https://github.com/PowerShell/PowerShell/archive/refs/tags/v%{version}.tar.gz,https://github.com/PowerShell/PowerShell.git
procmail.spec,https://github.com/BuGlessRB/procmail/archive/refs/tags/v%{version}.tar.gz,https://github.com/BuGlessRB/procmail.git
protobuf.spec,https://github.com/protocolbuffers/protobuf/archive/refs/tags/v%{version}.tar.gz,https://github.com/protocolbuffers/protobuf.git
protobuf-c.spec,https://github.com/protobuf-c/protobuf-c/archive/refs/tags/v%{version}.tar.gz,https://github.com/protobuf-c/protobuf-c.git
psmisc.spec,https://gitlab.com/psmisc/psmisc/-/archive/v%{version}/psmisc-v%{version}.tar.gz,https://gitlab.com/psmisc/psmisc.git
pth.spec,https://ftp.gnu.org/gnu/pth/pth-%{version}.tar.gz,https://gitlab.com/psmisc/psmisc.git
pycurl.spec,https://github.com/pycurl/pycurl/archive/refs/tags/REL_%{version}.tar.gz,https://github.com/pycurl/pycurl.git,,,"REL_"
pygobject.spec,https://gitlab.gnome.org/GNOME/pygobject/-/archive/%{version}/pygobject-%{version}.tar.gz,https://gitlab.gnome.org/GNOME/pygobject.git
python3-distro.spec,https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-distro/distro.git
python3-gcovr.spec,https://github.com/gcovr/gcovr/archive/refs/tags/%{version}.tar.gz,https://github.com/gcovr/gcovr.git
python3-pip.spec,https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/pip.git
python3-pyroute2.spec,https://github.com/svinota/pyroute2/archive/refs/tags/%{version}.tar.gz,https://github.com/svinota/pyroute2.git
python3-setuptools.spec,https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz,https://github.com/pypa/setuptools.git
python-alabaster.spec,https://github.com/bitprophet/alabaster/archive/refs/tags/%{version}.tar.gz,https://github.com/bitprophet/alabaster.git
python-altgraph.spec,https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz,https://github.com/ronaldoussoren/altgraph.git
python-antlrpythonruntime.spec,http://www.antlr3.org/download/Python/antlr_python_runtime-%{version}.tar.gz,,,,"antlr_python_runtime-"
python-appdirs.spec,https://github.com/ActiveState/appdirs/archive/refs/tags/%{version}.tar.gz,https://github.com/ActiveState/appdirs.git
python-argparse.spec,https://github.com/ThomasWaldmann/argparse/archive/refs/tags/r%{version}.tar.gz,https://github.com/ThomasWaldmann/argparse.git
python-asn1crypto.spec,https://github.com/wbond/asn1crypto/archive/refs/tags/%{version}.tar.gz,https://github.com/wbond/asn1crypto.git
python-atomicwrites.spec,https://github.com/untitaker/python-atomicwrites/archive/refs/tags/%{version}.tar.gz,https://github.com/untitaker/python-atomicwrites.git
python-attrs.spec,https://github.com/python-attrs/attrs/archive/refs/tags/%{version}.tar.gz,https://github.com/python-attrs/attrs.git
python-automat.spec,https://github.com/glyph/automat/archive/refs/tags/v%{version}.tar.gz,https://github.com/glyph/automat.git
python-autopep8.spec,https://github.com/hhatto/autopep8/archive/refs/tags/v%{version}.tar.gz,https://github.com/hhatto/autopep8.git
python-babel.spec,https://github.com/python-babel/babel/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-babel/babel.git
python-backports.ssl_match_hostname.spec,https://files.pythonhosted.org/packages/ff/2b/8265224812912bc5b7a607c44bf7b027554e1b9775e9ee0de8032e3de4b2/backports.ssl_match_hostname-3.7.0.1.tar.gz
python-backports_abc.spec,https://github.com/cython/backports_abc/archive/refs/tags/%{version}.tar.gz,https://github.com/cython/backports_abc.git
python-bcrypt.spec,https://github.com/pyca/bcrypt/archive/refs/tags/%{version}.tar.gz,https://github.com/pyca/bcrypt.git
python-binary.spec,https://github.com/ofek/binary/archive/refs/tags/v%{version}.tar.gz,https://github.com/ofek/binary.git
python-boto.spec,https://github.com/boto/boto/archive/refs/tags/%{version}.tar.gz,https://github.com/boto/boto.git
python-boto3.spec,https://github.com/boto/boto3/archive/refs/tags/%{version}.tar.gz,https://github.com/boto/boto3.git
python-botocore.spec,https://github.com/boto/botocore/archive/refs/tags/%{version}.tar.gz,https://github.com/boto/botocore.git
python-CacheControl.spec,https://github.com/ionrock/cachecontrol/archive/refs/tags/v%{version}.tar.gz,https://github.com/ionrock/cachecontrol.git
python-cachecontrol.spec,https://github.com/ionrock/cachecontrol/archive/refs/tags/v%{version}.tar.gz,https://github.com/ionrock/cachecontrol.git
python-cachetools.spec,https://github.com/tkem/cachetools/archive/refs/tags/v%{version}.tar.gz,https://github.com/tkem/cachetools.git
python-cassandra-driver.spec,https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz,https://github.com/datastax/python-driver.git
python-certifi.spec,https://github.com/certifi/python-certifi/archive/refs/tags/%{version}.tar.gz,https://github.com/certifi/python-certifi.git
python-cffi.spec,https://github.com/python-cffi/cffi/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-cffi/cffi.git
python-chardet.spec,https://github.com/chardet/chardet/archive/refs/tags/%{version}.tar.gz,https://github.com/chardet/chardet.git
python-charset-normalizer.spec,https://github.com/Ousret/charset_normalizer/archive/refs/tags/%{version}.tar.gz,https://github.com/Ousret/charset_normalizer.git
python-click.spec,https://github.com/pallets/click/archive/refs/tags/%{version}.tar.gz,https://github.com/pallets/click.git
python-ConcurrentLogHandler.spec,https://github.com/Preston-Landers/concurrent-log-handler/archive/refs/tags/%{version}.tar.gz,https://github.com/Preston-Landers/concurrent-log-handler.git
python-configobj.spec,https://github.com/DiffSK/configobj/archive/refs/tags/v%{version}.tar.gz,https://github.com/DiffSK/configobj.git
python-configparser.spec,https://github.com/jaraco/configparser/archive/refs/tags/%{version}.tar.gz,https://github.com/jaraco/configparser.git
python-constantly.spec,https://github.com/twisted/constantly/archive/refs/tags/%{version}.tar.gz,https://github.com/twisted/constantly.git
python-coverage.spec,https://github.com/nedbat/coveragepy/archive/refs/tags/%{version}.tar.gz,https://github.com/nedbat/coveragepy.git
python-cql.spec,https://storage.googleapis.com/google-code-archive-downloads/v2/apache-extras.org/cassandra-dbapi2/cql-%{version}.tar.gz
python-cql.spec,https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz,https://github.com/datastax/python-driver.git
python-cqlsh.spec,https://github.com/jeffwidman/cqlsh/archive/refs/tags/%{version}.tar.gz,https://github.com/jeffwidman/cqlsh.git
python-cqlsh.spec,https://github.com/jeffwidman/cqlsh/archive/refs/tags/%{version}.tar.gz,https://github.com/jeffwidman/cqlsh.git
python-cryptography.spec,https://github.com/pyca/cryptography/archive/refs/tags/%{version}.tar.gz,https://github.com/pyca/cryptography.git
python-daemon.spec,https://pagure.io/python-daemon/archive/release/%{version}/python-daemon-release/%{version}.tar.gz
python-dateutil.spec,https://github.com/dateutil/dateutil/archive/refs/tags/%{version}.tar.gz,https://github.com/dateutil/dateutil.git
python-decorator.spec,https://github.com/micheles/decorator/archive/refs/tags/%{version}.tar.gz,https://github.com/micheles/decorator.git
python-deepmerge.spec,https://github.com/toumorokoshi/deepmerge/archive/refs/tags/v%{version}.tar.gz,https://github.com/toumorokoshi/deepmerge.git
python-defusedxml.spec,https://github.com/tiran/defusedxml/archive/refs/tags/v%{version}.tar.gz,https://github.com/tiran/defusedxml.git
python-dis3.spec,https://github.com/KeyWeeUsr/python-dis3/archive/refs/tags/v%{version}.tar.gz,https://github.com/KeyWeeUsr/python-dis3.git
python-distlib.spec,https://github.com/pypa/distlib/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/distlib.git
python-distro.spec,https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-distro/distro.git
python-dnspython.spec,https://github.com/rthalley/dnspython/archive/refs/tags/v%{version}.tar.gz,https://github.com/rthalley/dnspython.git
python-docopt.spec,https://github.com/docopt/docopt/archive/refs/tags/%{version}.tar.gz,https://github.com/docopt/docopt.git
python-docutils.spec,https://netix.dl.sourceforge.net/project/docutils/docutils/%{version}/docutils-%{version}.tar.gz,,,,,"docutils-"
python-ecdsa.spec,https://github.com/tlsfuzzer/python-ecdsa/archive/refs/tags/python-ecdsa-%{version}.tar.gz,https://github.com/tlsfuzzer/python-ecdsa.git,,,"python-ecdsa-"
python-email-validator.spec,https://github.com/JoshData/python-email-validator/archive/refs/tags/v%{version}.tar.gz,https://github.com/JoshData/python-email-validator.git
python-etcd.spec,https://github.com/jplana/python-etcd/archive/refs/tags/%{version}.tar.gz,https://github.com/jplana/python-etcd.git
python-ethtool.spec,https://github.com/fedora-python/python-ethtool/archive/refs/tags/v%{version}.tar.gz,https://github.com/fedora-python/python-ethtool.git
python-filelock.spec,https://github.com/tox-dev/py-filelock/archive/refs/tags/v%{version}.tar.gz,https://github.com/tox-dev/py-filelock.git
python-flit-core.spec,https://github.com/pypa/flit/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/flit.git
python-fuse.spec,https://github.com/libfuse/python-fuse/archive/refs/tags/v%{version}.tar.gz,https://github.com/libfuse/python-fuse.git
python-future.spec,https://github.com/PythonCharmers/python-future/archive/refs/tags/v%{version}.tar.gz,https://github.com/PythonCharmers/python-future.git
python-futures.spec,https://github.com/agronholm/pythonfutures/archive/refs/tags/%{version}.tar.gz,https://github.com/agronholm/pythonfutures.git
python-geomet.spec,https://github.com/geomet/geomet/archive/refs/tags/%{version}.tar.gz,https://github.com/geomet/geomet.git
python-gevent.spec,https://github.com/gevent/gevent/archive/refs/tags/%{version}.tar.gz,https://github.com/gevent/gevent.git
python-google-auth.spec,https://github.com/googleapis/google-auth-library-python/archive/refs/tags/v%{version}.tar.gz,https://github.com/googleapis/google-auth-library-python.git
python-graphviz.spec,https://github.com/xflr6/graphviz/archive/refs/tags/%{version}.tar.gz,https://github.com/xflr6/graphviz.git
python-greenlet.spec,https://github.com/python-greenlet/greenlet/archive/refs/tags/%{version}.tar.gz,https://github.com/python-greenlet/greenlet.git
python-hatch-fancy-pypi-readme.spec,https://github.com/hynek/hatch-fancy-pypi-readme/archive/refs/tags/%{version}.tar.gz,https://github.com/hynek/hatch-fancy-pypi-readme.git
python-hatch-vcs.spec,https://github.com/ofek/hatch-vcs/archive/refs/tags/v%{version}.tar.gz,https://github.com/ofek/hatch-vcs.git
python-hatchling.spec,https://github.com/pypa/hatch/archive/refs/tags/hatchling-v%{version}.tar.gz,https://github.com/pypa/hatch.git
python-hyperlink.spec,https://github.com/python-hyper/hyperlink/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-hyper/hyperlink.git
python-hypothesis.spec,https://github.com/HypothesisWorks/hypothesis/archive/refs/tags/hypothesis-python-%{version}.tar.gz,https://github.com/HypothesisWorks/hypothesis.git
python-idna.spec,https://github.com/kjd/idna/archive/refs/tags/v%{version}.tar.gz,https://github.com/kjd/idna.git
python-imagesize.spec,https://github.com/shibukawa/imagesize_py/archive/refs/tags/%{version}.tar.gz,https://github.com/shibukawa/imagesize_py.git
python-importlib-metadata.spec,https://github.com/python/importlib_metadata/archive/refs/tags/v%{version}.tar.gz,https://github.com/python/importlib_metadata.git
python-incremental.spec,https://github.com/twisted/incremental/archive/refs/tags/incremental-%{version}.tar.gz,https://github.com/twisted/incremental.git,,python-incremental,"incremental-"
python-iniconfig.spec,https://github.com/pytest-dev/iniconfig/archive/refs/tags/v%{version}.tar.gz,https://github.com/pytest-dev/iniconfig.git
python-iniparse.spec,https://github.com/candlepin/python-iniparse/archive/refs/tags/%{version}.tar.gz,https://github.com/candlepin/python-iniparse.git
python-ipaddress.spec,https://github.com/phihag/ipaddress/archive/refs/tags/v%{version}.tar.gz,https://github.com/phihag/ipaddress.git
python-jinja.spec,https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz,https://github.com/pallets/jinja.git
python-jinja2.spec,https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz,https://github.com/pallets/jinja.git
python-jmespath.spec,https://github.com/jmespath/jmespath.py/archive/refs/tags/%{version}.tar.gz,https://github.com/jmespath/jmespath.py.git
python-jsonpointer.spec,https://github.com/stefankoegl/python-json-pointer/archive/refs/tags/v%{version}.tar.gz,https://github.com/stefankoegl/python-json-pointer.git
python-jsonpatch.spec,https://github.com/stefankoegl/python-json-patch/archive/refs/tags/v%{version}.tar.gz,https://github.com/stefankoegl/python-json-patch.git
python-jsonschema.spec,https://github.com/python-jsonschema/jsonschema/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-jsonschema/jsonschema.git
python-kubernetes.spec,https://github.com/kubernetes-client/python/archive/refs/tags/v%{version}.tar.gz,https://github.com/kubernetes-client/python.git
python-linux-procfs.spec,https://git.kernel.org/pub/scm/libs/python/python-linux-procfs/python-linux-procfs.git/snapshot/python-linux-procfs-%{version}.tar.gz,https://git.kernel.org/pub/scm/libs/python/python-linux-procfs/python-linux-procfs.git,,,"python-linux-procfs-"
python-looseversion.spec,https://github.com/effigies/looseversion/archive/refs/tags/%{version}.tar.gz,https://github.com/effigies/looseversion.git
python-lxml.spec,https://github.com/lxml/lxml/archive/refs/tags/lxml-%{version}.tar.gz,https://github.com/lxml/lxml.git,,,"python-lxml-,lxml-"
python-M2Crypto.spec,https://gitlab.com/m2crypto/m2crypto/-/archive/%{version}/m2crypto-%{version}.tar.gz,https://gitlab.com/m2crypto/m2crypto.git
python-m2r.spec,https://github.com/miyakogi/m2r/archive/refs/tags/v%{version}.tar.gz,https://github.com/miyakogi/m2r.git,,,,,1,2022-10-17
python-macholib.spec,https://github.com/ronaldoussoren/macholib/archive/refs/tags/v%{version}.tar.gz,https://github.com/ronaldoussoren/macholib.git
python-mako.spec,https://github.com/sqlalchemy/mako/archive/refs/tags/rel_%{version}.tar.gz,https://github.com/sqlalchemy/mako.git,,,"rel_"
python-markupsafe.spec,https://github.com/pallets/markupsafe/archive/refs/tags/%{version}.tar.gz,https://github.com/pallets/markupsafe.git
python-mistune.spec,https://github.com/lepture/mistune/archive/refs/tags/v%{version}.tar.gz,https://github.com/lepture/mistune.git
python-mock.spec,https://github.com/testing-cabal/mock/archive/refs/tags/%{version}.tar.gz,https://github.com/testing-cabal/mock.git
python-more-itertools.spec,https://github.com/more-itertools/more-itertools/archive/refs/tags/%{version}.tar.gz,https://github.com/more-itertools/more-itertools.git
python-msgpack.spec,https://github.com/msgpack/msgpack-python/archive/refs/tags/v%{version}.tar.gz,https://github.com/msgpack/msgpack-python.git
python-ndg-httpsclient.spec,https://github.com/cedadev/ndg_httpsclient/archive/refs/tags/%{version}.tar.gz,https://github.com/cedadev/ndg_httpsclient.git
python-netaddr.spec,https://github.com/netaddr/netaddr/archive/refs/tags/%{version}.tar.gz,https://github.com/netaddr/netaddr.git
python-netifaces.spec,https://github.com/al45tair/netifaces/archive/refs/tags/release_%{version}.tar.gz,https://github.com/al45tair/netifaces.git
python-nocasedict.spec,https://github.com/pywbem/nocasedict/archive/refs/tags/%{version}.tar.gz,https://github.com/pywbem/nocasedict.git
python-nocaselist.spec,https://github.com/pywbem/nocaselist/archive/refs/tags/%{version}.tar.gz,https://github.com/pywbem/nocaselist.git
python-ntplib.spec,https://github.com/cf-natali/ntplib/archive/refs/tags/%{version}.tar.gz,https://github.com/cf-natali/ntplib.git
python-numpy.spec,https://github.com/numpy/numpy/archive/refs/tags/v%{version}.tar.gz,https://github.com/numpy/numpy.git
python-oauthlib.spec,https://github.com/oauthlib/oauthlib/archive/refs/tags/v%{version}.tar.gz,https://github.com/oauthlib/oauthlib.git
python-packaging.spec,https://github.com/pypa/packaging/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/packaging.git
python-pam.spec,https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz,https://github.com/FirefighterBlu3/python-pam.git
python-paramiko.spec,https://github.com/paramiko/paramiko/archive/refs/tags/%{version}.tar.gz,https://github.com/paramiko/paramiko.git
python-pathspec.spec,https://github.com/cpburnz/python-pathspec/archive/refs/tags/v%{version}.tar.gz,https://github.com/cpburnz/python-pathspec.git
python-pbr.spec,https://tarballs.openstack.org/pbr/pbr-%{version}.tar.gz,https://opendev.org/openstack/pbr.git,,,"python-pbr"
python-pg8000.spec,https://codeberg.org/tlocke/pg8000/archive/%{version}.tar.gz,https://codeberg.org/tlocke/pg8000.git
python-pefile.spec,https://github.com/erocarrera/pefile/archive/refs/tags/v%{version}.tar.gz,https://github.com/erocarrera/pefile.git
python-pexpect.spec,https://github.com/pexpect/pexpect/archive/refs/tags/%{version}.tar.gz,https://github.com/pexpect/pexpect.git
python-pika.spec,https://github.com/pika/pika/releases/download/%{version}/pika-%{version}.tar.gz,https://github.com/pika/pika.git
python-pip.spec,https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/pip.git
python-pkgconfig.spec,https://github.com/matze/pkgconfig/archive/refs/tags/v%{version}.tar.gz,https://github.com/matze/pkgconfig.git
python-platformdirs.spec,https://github.com/tox-dev/platformdirs/archive/refs/tags/%{version}.tar.gz,https://github.com/tox-dev/platformdirs.git
python-pluggy.spec,https://github.com/pytest-dev/pluggy/archive/refs/tags/%{version}.tar.gz,https://github.com/pytest-dev/pluggy.git
python-ply.spec,https://github.com/dabeaz/ply/archive/refs/tags/%{version}.tar.gz,https://github.com/dabeaz/ply.git
python-portalocker.spec,https://github.com/wolph/portalocker/archive/refs/tags/v%{version}.tar.gz,https://github.com/wolph/portalocker.git
python-prettytable.spec,https://github.com/jazzband/prettytable/archive/refs/tags/%{version}.tar.gz,https://github.com/jazzband/prettytable.git
python-prometheus_client.spec,https://github.com/prometheus/client_python/archive/refs/tags/v%{version}.tar.gz,https://github.com/prometheus/client_python.git
python-prompt_toolkit.spec,https://github.com/prompt-toolkit/python-prompt-toolkit/archive/refs/tags/%{version}.tar.gz,https://github.com/prompt-toolkit/python-prompt-toolkit.git
python-psutil.spec,https://github.com/giampaolo/psutil/archive/refs/tags/release-%{version}.tar.gz,https://github.com/giampaolo/psutil.git
python-psycopg2.spec,https://github.com/psycopg/psycopg2/archive/refs/tags/%{version}.tar.gz,https://github.com/psycopg/psycopg2.git
python-ptyprocess.spec,https://github.com/pexpect/ptyprocess/archive/refs/tags/%{version}.tar.gz,https://github.com/pexpect/ptyprocess.git
python-py.spec,https://github.com/pytest-dev/py/archive/refs/tags/%{version}.tar.gz,https://github.com/pytest-dev/py.git
python-pyasn1.spec,https://github.com/pyasn1/pyasn1/archive/refs/tags/v%{version}.tar.gz,https://github.com/pyasn1/pyasn1.git
python-pyasn1-modules.spec,https://github.com/etingof/pyasn1-modules/archive/refs/tags/v%{version}.tar.gz,https://github.com/etingof/pyasn1-modules.git
python-pycodestyle.spec,https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz,https://github.com/FirefighterBlu3/python-pam.git
python-pycparser.spec,https://github.com/eliben/pycparser/archive/refs/tags/release_v%{version}.tar.gz,https://github.com/eliben/pycparser.git
python-pycryptodome.spec,https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz,https://github.com/Legrandin/pycryptodome.git
python-pycryptodomex.spec,https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz,https://github.com/Legrandin/pycryptodome.git
python-pydantic.spec,https://github.com/pydantic/pydantic/archive/refs/tags/v%{version}.tar.gz,https://github.com/pydantic/pydantic.git
python-pyflakes.spec,https://github.com/PyCQA/pyflakes/archive/refs/tags/%{version}.tar.gz,https://github.com/PyCQA/pyflakes.git
python-Pygments.spec,https://github.com/pygments/pygments/archive/refs/tags/%{version}.tar.gz,https://github.com/pygments/pygments.git
python-pygments.spec,https://github.com/pygments/pygments/archive/refs/tags/%{version}.tar.gz,https://github.com/pygments/pygments.git
python-pygobject.spec,,https://gitlab.gnome.org/GNOME/pygobject.git
python-PyHamcrest.spec,https://github.com/hamcrest/PyHamcrest/archive/refs/tags/V%{version}.tar.gz,https://github.com/hamcrest/PyHamcrest.git
python-pyhamcrest.spec,https://github.com/hamcrest/PyHamcrest/archive/refs/tags/V%{version}.tar.gz,https://github.com/hamcrest/PyHamcrest.git
python-pyinstaller.spec,https://github.com/pyinstaller/pyinstaller/archive/refs/tags/v%{version}.tar.gz,https://github.com/pyinstaller/pyinstaller.git
python-pyinstaller-hooks-contrib.spec,https://github.com/pyinstaller/pyinstaller-hooks-contrib/archive/refs/tags/v%{version}.tar.gz,https://github.com/pyinstaller/pyinstaller-hooks-contrib.git
python-pyjsparser.spec,https://github.com/PiotrDabkowski/pyjsparser/archive/refs/tags/v%{version}.tar.gz,https://github.com/PiotrDabkowski/pyjsparser.git
python-pyjwt.spec,https://github.com/jpadilla/pyjwt/archive/refs/tags/%{version}.tar.gz,https://github.com/jpadilla/pyjwt.git
python-PyJWT.spec,https://github.com/jpadilla/pyjwt/archive/refs/tags/%{version}.tar.gz,https://github.com/jpadilla/pyjwt.git
python-PyNaCl.spec,https://github.com/pyca/pynacl/archive/refs/tags/%{version}.tar.gz,https://github.com/pyca/pynacl.git
python-pygobject.spec,https://gitlab.gnome.org/GNOME/pygobject/-/archive/%{version}/pygobject-%{version}.tar.gz,https://gitlab.gnome.org/GNOME/pygobject.git
python-pyOpenSSL.spec,https://github.com/pyca/pyopenssl/archive/refs/tags/%{version}.tar.gz,https://github.com/pyca/pyopenssl.git
python-pyparsing.spec,https://github.com/pyparsing/pyparsing/archive/refs/tags/pyparsing_%{version}.tar.gz,https://github.com/pyparsing/pyparsing.git
python-pyrsistent.spec,https://github.com/tobgu/pyrsistent/archive/refs/tags/v%{version}.tar.gz,https://github.com/tobgu/pyrsistent.git
python-pyserial.spec,https://github.com/pyserial/pyserial/archive/refs/tags/v%{version}.tar.gz,https://github.com/pyserial/pyserial.git
python-pytest.spec,https://github.com/pytest-dev/pytest/archive/refs/tags/%{version}.tar.gz,https://github.com/pytest-dev/pytest.git
python-pyudev.spec,https://github.com/pyudev/pyudev/archive/refs/tags/v%{version}.tar.gz,https://github.com/pyudev/pyudev.git
python-pyvim.spec,https://github.com/prompt-toolkit/pyvim/archive/refs/tags/%{version}.tar.gz,https://github.com/prompt-toolkit/pyvim.git
python-pyvmomi.spec,https://github.com/vmware/pyvmomi/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/pyvmomi.git
python-pywbem.spec,https://github.com/pywbem/pywbem/archive/refs/tags/%{version}.tar.gz,https://github.com/pywbem/pywbem.git
python-pytz.spec,https://github.com/stub42/pytz/archive/refs/tags/release_%{version}.tar.gz,https://github.com/stub42/pytz.git
python-pytz-deprecation-shim.spec,https://github.com/pganssle/pytz-deprecation-shim/archive/refs/tags/%{version}.tar.gz,https://github.com/pganssle/pytz-deprecation-shim.git
python-pyYaml.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/pyyaml.git
python-PyYAML.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/pyyaml.git
python-requests.spec,https://github.com/psf/requests/archive/refs/tags/v%{version}.tar.gz,https://github.com/psf/requests.git
python-requests-oauthlib.spec,https://github.com/requests/requests-oauthlib/archive/refs/tags/v%{version}.tar.gz,https://github.com/requests/requests-oauthlib.git
python-requests-unixsocket.spec,https://github.com/msabramo/requests-unixsocket/archive/refs/tags/v%{version}.tar.gz,https://github.com/msabramo/requests-unixsocket.git
python-requests-toolbelt.spec,https://github.com/requests/toolbelt/archive/refs/tags/%{version}.tar.gz,https://github.com/requests/toolbelt.git
python-resolvelib.spec,https://github.com/sarugaku/resolvelib/archive/refs/tags/%{version}.tar.gz,https://github.com/sarugaku/resolvelib.git
python-rsa.spec,https://github.com/sybrenstuvel/python-rsa/archive/refs/tags/version-%{version}.tar.gz,https://github.com/sybrenstuvel/python-rsa.git,,,"version-"
python-s3transfer.spec,https://github.com/boto/s3transfer/archive/refs/tags/%{version}.tar.gz,https://github.com/boto/s3transfer.git
python-schedutils.spec,https://git.kernel.org/pub/scm/libs/python/python-schedutils/python-schedutils.git/snapshot/python-schedutils-%{version}.tar.gz,https://git.kernel.org/pub/scm/libs/python/python-schedutils/python-schedutils.git
python-scp.spec,https://github.com/jbardin/scp.py/archive/refs/tags/v%{version}.tar.gz,https://github.com/jbardin/scp.py.git
python-scramp.spec,https://codeberg.org/tlocke/scramp/archive/%{version}.tar.gz, https://codeberg.org/tlocke/scramp.git
python-semantic-version.spec,https://github.com/rbarrois/python-semanticversion/archive/refs/tags/%{version}.tar.gz,https://github.com/rbarrois/python-semanticversion.git
python-service_identity.spec,https://github.com/pyca/service-identity/archive/refs/tags/%{version}.tar.gz,https://github.com/pyca/service-identity.git
python-setproctitle.spec,https://github.com/dvarrazzo/py-setproctitle/archive/refs/tags/version-%{version}.tar.gz,https://github.com/dvarrazzo/py-setproctitle.git,,,"version-"
python-setuptools.spec,https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz,https://github.com/pypa/setuptools.git
python-setuptools-rust.spec,https://github.com/PyO3/setuptools-rust/archive/refs/tags/v%{version}.tar.gz,https://github.com/PyO3/setuptools-rust.git
python-setuptools_scm.spec,https://github.com/pypa/setuptools_scm/archive/refs/tags/v%{version}.tar.gz,https://github.com/pypa/setuptools_scm.git
python-simplejson.spec,https://github.com/simplejson/simplejson/archive/refs/tags/v%{version}.tar.gz,https://github.com/simplejson/simplejson.git
python-six.spec,https://github.com/benjaminp/six/archive/refs/tags/%{version}.tar.gz,https://github.com/benjaminp/six.git
python-snowballstemmer.spec,https://github.com/snowballstem/snowball/archive/refs/tags/v%{version}.tar.gz,https://github.com/snowballstem/snowball.git
python-sortedcontainers.spec,https://github.com/grantjenks/python-sortedcontainers/archive/refs/tags/v%{version}.tar.gz,https://github.com/grantjenks/python-sortedcontainers.git
python-sphinx.spec,https://github.com/sphinx-doc/sphinx/archive/refs/tags/v%{version}.tar.gz,https://github.com/sphinx-doc/sphinx.git
python-sphinxcontrib-applehelp.spec,https://github.com/sphinx-doc/sphinxcontrib-applehelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-applehelp.git
python-sphinxcontrib-devhelp.spec,https://github.com/sphinx-doc/sphinxcontrib-devhelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-devhelp.git
python-sphinxcontrib-htmlhelp.spec,https://github.com/sphinx-doc/sphinxcontrib-htmlhelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-htmlhelp.git
python-sphinxcontrib-jsmath.spec,https://github.com/sphinx-doc/sphinxcontrib-jsmath/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-jsmath.git
python-sphinxcontrib-qthelp.spec,https://github.com/sphinx-doc/sphinxcontrib-qthelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-qthelp.git
python-sphinxcontrib-serializinghtml.spec,https://github.com/sphinx-doc/sphinxcontrib-serializinghtml/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-serializinghtml.git
python-sqlalchemy.spec,https://github.com/sqlalchemy/sqlalchemy/archive/refs/tags/rel_%{version}.tar.gz,https://github.com/sqlalchemy/sqlalchemy.git,,,"rel_"
python-subprocess32.spec,https://github.com/google/python-subprocess32/archive/refs/tags/%{version}.tar.gz,https://github.com/google/python-subprocess32.git
python-systemd.spec,https://github.com/systemd/python-systemd/archive/refs/tags/v%{version}.tar.gz,https://github.com/systemd/python-systemd.git
python-terminaltables.spec,https://github.com/Robpol86/terminaltables/archive/refs/tags/v%{version}.tar.gz,https://github.com/Robpol86/terminaltables.git
python-toml.spec,https://github.com/uiri/toml/archive/refs/tags/%{version}.tar.gz,https://github.com/uiri/toml.git
python-tornado.spec,https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz,https://github.com/tornadoweb/tornado.git
python-Twisted.spec,https://github.com/twisted/twisted/archive/refs/tags/twisted-%{version}.tar.gz,https://github.com/twisted/twisted.git
python-typing.spec,https://github.com/python/typing/archive/refs/tags/%{version}.tar.gz,https://github.com/python/typing.git
python-typing-extensions.spec,https://github.com/python/typing_extensions/archive/refs/tags/%{version}.tar.gz,https://github.com/python/typing_extensions.git
python-tzlocal.spec,https://github.com/regebro/tzlocal/archive/refs/tags/%{version}.tar.gz,https://github.com/regebro/tzlocal.git
python-ujson.spec,https://github.com/ultrajson/ultrajson/archive/refs/tags/%{version}.tar.gz,https://github.com/ultrajson/ultrajson.git
python-urllib3.spec,https://github.com/urllib3/urllib3/archive/refs/tags/%{version}.tar.gz,https://github.com/urllib3/urllib3.git
python-vcversioner.spec,https://github.com/habnabit/vcversioner/archive/refs/tags/%{version}.tar.gz,https://github.com/habnabit/vcversioner.git
python-versioningit.spec,https://github.com/jwodder/versioningit/archive/refs/tags/v%{version}.tar.gz,https://github.com/jwodder/versioningit.git
python-virtualenv.spec,https://github.com/pypa/virtualenv/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/virtualenv.git
python-wcwidth.spec,https://github.com/jquast/wcwidth/archive/refs/tags/%{version}.tar.gz,https://github.com/jquast/wcwidth.git
python-webob.spec,https://github.com/Pylons/webob/archive/refs/tags/%{version}.tar.gz,https://github.com/Pylons/webob.git
python-websocket-client.spec,https://github.com/websocket-client/websocket-client/archive/refs/tags/v%{version}.tar.gz,https://github.com/websocket-client/websocket-client.git
python-werkzeug.spec,https://github.com/pallets/werkzeug/archive/refs/tags/%{version}.tar.gz,https://github.com/pallets/werkzeug.git
python-wrapt.spec,https://github.com/GrahamDumpleton/wrapt/archive/refs/tags/%{version}.tar.gz,https://github.com/GrahamDumpleton/wrapt.git
python-xmltodict.spec,https://github.com/martinblech/xmltodict/archive/refs/tags/v%{version}.tar.gz,https://github.com/martinblech/xmltodict.git
python-yamlloader.spec,https://github.com/Phynix/yamlloader/archive/refs/tags/%{version}.tar.gz,https://github.com/Phynix/yamlloader.git
python-zipp.spec,https://github.com/jaraco/zipp/archive/refs/tags/v%{version}.tar.gz,https://github.com/jaraco/zipp.git
python-zmq.spec,https://github.com/zeromq/pyzmq/archive/refs/tags/v%{version}.tar.gz,https://github.com/zeromq/pyzmq.git
python-zope.event.spec,https://github.com/zopefoundation/zope.event/archive/refs/tags/%{version}.tar.gz,https://github.com/zopefoundation/zope.event.git
python-zope.interface.spec,https://github.com/zopefoundation/zope.interface/archive/refs/tags/%{version}.tar.gz,https://github.com/zopefoundation/zope.interface.git
pyYaml.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/pyyaml.git
rabbitmq.spec,https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz,https://github.com/rabbitmq/rabbitmq-server.git
rabbitmq3.10.spec,https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz,https://github.com/rabbitmq/rabbitmq-server.git
rabbitmq-server.spec,https://github.com/rabbitmq/rabbitmq-server/releases/download/v%{version}/rabbitmq-server-%{version}.tar.xz,https://github.com/rabbitmq/rabbitmq-server.git
ragel.spec,https://github.com/adrian-thurston/ragel/archive/refs/tags/%{version}.tar.gz,https://github.com/adrian-thurston/ragel.git
rapidjson.spec,https://github.com/miloyip/rapidjson/archive/refs/tags/v%{version}.tar.gz,https://github.com/miloyip/rapidjson.git
raspberrypi-firmware.spec,https://github.com/raspberrypi/firmware/archive/refs/tags/%{version}.tar.gz,https://github.com/raspberrypi/firmware.git
rdma-core.spec,https://github.com/linux-rdma/rdma-core/releases/download/v%{version}/rdma-core-%{version}.tar.gz,https://github.com/linux-rdma/rdma-core.git
re2.spec,https://github.com/google/re2/archive/refs/tags/%{version}.tar.gz,https://github.com/google/re2.git
redis.spec,https://github.com/redis/redis/archive/refs/tags/%{version}.tar.gz,https://github.com/redis/redis.git
repmgr.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr10.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr13.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr14.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr15.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr16.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr17.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
rng-tools.spec,https://github.com/nhorman/rng-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/nhorman/rng-tools.git
rootlesskit.spec,https://github.com/rootless-containers/rootlesskit/archive/refs/tags/v%{version}.tar.gz,https://github.com/rootless-containers/rootlesskit.git
rpcsvc-proto.spec,https://github.com/thkukuk/rpcsvc-proto/archive/refs/tags/v%{version}.tar.gz,https://github.com/thkukuk/rpcsvc-proto.git
rpm.spec,https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-%{version}-release.tar.gz,https://github.com/rpm-software-management/rpm.git,,rpm,"rpm-,-release"
rpm-ostree.spec,https://github.com/coreos/rpm-ostree/releases/download/v%{version}/rpm-ostree-%{version}.tar.xz,https://github.com/coreos/rpm-ostree.git
rrdtool.spec,https://github.com/oetiker/rrdtool-1.x/archive/refs/tags/v%{version}.tar.gz,https://github.com/oetiker/rrdtool-1.x.git
rsync.spec,https://github.com/RsyncProject/rsync/archive/refs/tags/v%{version}.tar.gz,https://github.com/RsyncProject/rsync.git
rt-tests.spec,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/snapshot/rt-tests-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
ruby.spec,https://github.com/ruby/ruby/archive/refs/tags/v%{version}.tar.gz,https://github.com/ruby/ruby.git,,,"@"
rubygem-aws-sdk-s3.spec,https://rubygems.org/downloads/aws-sdk-s3-%{version}.gem
runc.spec,https://github.com/opencontainers/runc/archive/refs/tags/v%{version}.tar.gz,https://github.com/opencontainers/runc.git
rust.spec,https://github.com/rust-lang/rust/archive/refs/tags/%{version}.tar.gz,https://github.com/rust-lang/rust.git
rsyslog.spec,https://github.com/rsyslog/rsyslog/archive/refs/tags/v%{version}.tar.gz,https://github.com/rsyslog/rsyslog.git
rt-tests.spec,,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
s3fs-fuse.spec,https://github.com/s3fs-fuse/s3fs-fuse/archive/refs/tags/v%{version}.tar.gz,https://github.com/s3fs-fuse/s3fs-fuse.git
salt3.spec,https://github.com/saltstack/salt/releases/download/v%{version}/salt-%{version}.tar.gz,https://github.com/saltstack/salt.git,,,"salt-"
samba-client.spec,https://gitlab.com/samba-team/devel/samba/-/archive/samba-%{version}/samba-samba-%{version}.tar.gz
sbsigntools.spec,https://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git/snapshot/sbsigntools-%{version}.tar.gz,https://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git,,,
selinux-policy.spec,https://github.com/fedora-selinux/selinux-policy/archive/refs/tags/v%{version}.tar.gz,https://github.com/fedora-selinux/selinux-policy.git,,,
selinux-python.spec,https://github.com/SELinuxProject/selinux/releases/download/%{version}/selinux-python-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git
semodule-utils.spec,https://github.com/SELinuxProject/selinux/releases/download/%{version}/semodule-utils-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git
serf.spec,https://github.com/apache/serf/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/serf.git
setools.spec,https://github.com/SELinuxProject/setools/releases/download/%{version}/setools-%{version}.tar.bz2,https://github.com/SELinuxProject/setools.git
sg3_utils.spec,https://github.com/hreinecke/sg3_utils/archive/refs/tags/v%{version}.tar.gz,https://github.com/hreinecke/sg3_utils.git
shadow.spec,https://github.com/shadow-maint/shadow/archive/refs/tags/%{version}.tar.gz,https://github.com/shadow-maint/shadow.git
shared-mime-info.spec,https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/%{version}/shared-mime-info-%{version}.tar.gz,https://gitlab.freedesktop.org/xdg/shared-mime-info.git
shim.spec,https://github.com/rhboot/shim/releases/download/%{version}/shim-%{version}.tar.bz2,https://github.com/rhboot/shim.git
shim-signed.spec,https://packages.broadcom.com/photon/photon_sources/1.0/shim-signed-%{version}.tar.xz
slirp4netns.spec,https://github.com/rootless-containers/slirp4netns/archive/refs/tags/v%{version}.tar.gz,https://github.com/rootless-containers/slirp4netns.git
snappy.spec,https://github.com/google/snappy/archive/refs/tags/%{version}.tar.gz,https://github.com/google/snappy.git
snoopy.spec,https://github.com/a2o/snoopy/archive/refs/tags/snoopy-%{version}.tar.gz,https://github.com/a2o/snoopy.git
spdlog.spec,https://github.com/gabime/spdlog/archive/refs/tags/v%{version}.tar.gz,https://github.com/gabime/spdlog.git
spirv-headers.spec,https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-%{version}.tar.gz,https://github.com/KhronosGroup/SPIRV-Headers.git,,,"vulkan-sdk-"
spirv-llvm-translator.spec,https://github.com/KhronosGroup/SPIRV-LLVM-Translator/archive/refs/tags/v%{version}.tar.gz,https://github.com/KhronosGroup/SPIRV-LLVM-Translator.git
spirv-tools.spec,https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/vulkan-sdk-%{version}.0.tar.gz,https://github.com/KhronosGroup/SPIRV-Tools.git,,,"vulkan-sdk-"
sqlite.spec,https://github.com/sqlite/sqlite/archive/refs/tags/version-%{version}.tar.gz,https://github.com/sqlite/sqlite.git,,,"version-"
squashfs-tools.spec,https://github.com/plougher/squashfs-tools/archive/refs/tags/%{version}.tar.gz,https://github.com/plougher/squashfs-tools.git
sshfs.spec,https://github.com/libfuse/sshfs/archive/refs/tags/sshfs-%{version}.tar.gz,https://github.com/libfuse/sshfs.git
sssd.spec,https://github.com/SSSD/sssd/archive/refs/tags/%{version}.tar.gz,https://github.com/SSSD/sssd.git
stalld.spec,,https://git.kernel.org/pub/scm/utils/stalld/stalld.git
strongswan.spec,https://github.com/strongswan/strongswan/releases/download/%{version}/strongswan-%{version}.tar.bz2,https://github.com/strongswan/strongswan.git
stunnel.spec,https://github.com/mtrojnar/stunnel/archive/refs/tags/stunnel-%{version}.tar.gz,https://github.com/mtrojnar/stunnel.git
subversion.spec,https://github.com/apache/subversion/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/subversion.git
synce4l.spec,https://github.com/intel/synce4l/archive/refs/tags/%{version}.tar.gz,https://github.com/intel/synce4l.git
sysdig.spec,https://github.com/draios/sysdig/archive/refs/tags/%{version}.tar.gz,https://github.com/draios/sysdig.git
syslinux.spec,,https://git.kernel.org/pub/scm/boot/syslinux/syslinux.git
syslog-ng.spec,https://github.com/syslog-ng/syslog-ng/archive/refs/tags/syslog-ng-%{version}.tar.gz,https://github.com/syslog-ng/syslog-ng.git
sysstat.spec,https://github.com/sysstat/sysstat/archive/refs/tags/v%{version}.tar.gz,https://github.com/sysstat/sysstat.git
systemd.spec,https://github.com/systemd/systemd-stable/archive/refs/tags/v%{version}.tar.gz,https://github.com/systemd/systemd-stable.git
systemtap.spec,https://github.com/cdkey/systemtap/archive/refs/tags/release-%{version}.tar.gz,https://github.com/cdkey/systemtap.git,,,"release-"
tar.spec,https://ftp.gnu.org/gnu/tar/tar-%{version}.tar.xz
tboot.spec,https://sourceforge.net/projects/tboot/files/tboot/tboot-%{version}.tar.gz/download
tcp_wrappers.spec,http://ftp.porcupine.org/pub/security/tcp_wrappers_%{version}.tar.gz
tcsh.spec,https://github.com/tcsh-org/tcsh/archive/refs/tags/TCSH%{version}.tar.gz,https://github.com/tcsh-org/tcsh.git,,,"TCSH"
tdnf.spec,https://github.com/vmware/tdnf/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/tdnf.git
telegraf.spec,https://github.com/influxdata/telegraf/archive/refs/tags/v%{version}.tar.gz,https://github.com/influxdata/telegraf.git
termshark.spec,https://github.com/gcla/termshark/archive/refs/tags/v%{version}.tar.gz,https://github.com/gcla/termshark.git
thin-provisioning-tools.spec,https://github.com/jthornber/thin-provisioning-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/jthornber/thin-provisioning-tools.git
tini.spec,https://github.com/krallin/tini/archive/refs/tags/v%{version}.tar.gz,https://github.com/krallin/tini.git
tiptop.spec,https://files.inria.fr/pacap/tiptop/tiptop-%{version}.tar.gz,https://gitlab.inria.fr/rohou/tiptop.git,,,"tiptop-"
tmux.spec,https://github.com/tmux/tmux/archive/refs/tags/%{version}.tar.gz,https://github.com/tmux/tmux.git
tornado.spec,https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz,https://github.com/tornadoweb/tornado.git
toybox.spec,https://github.com/landley/toybox/archive/refs/tags/%{version}.tar.gz,https://github.com/landley/toybox.git
tpm2-abrmd.spec,https://github.com/tpm2-software/tpm2-abrmd/archive/refs/tags/%{version}.tar.gz,https://github.com/tpm2-software/tpm2-abrmd.git
tpm2-pkcs11.spec,https://github.com/tpm2-software/tpm2-pkcs11/archive/refs/tags/%{version}.tar.gz,https://github.com/tpm2-software/tpm2-pkcs11.git
tpm2-pytss.spec,https://github.com/tpm2-software/tpm2-pytss/archive/refs/tags/%{version}.tar.gz,https://github.com/tpm2-software/tpm2-pytss.git
tpm2-tools.spec,https://github.com/tpm2-software/tpm2-tools/archive/refs/tags/%{version}.tar.gz,https://github.com/tpm2-software/tpm2-tools.git
tpm2-tss.spec,https://github.com/tpm2-software/tpm2-tss/archive/refs/tags/%{version}.tar.gz,https://github.com/tpm2-software/tpm2-tss.git
trace-cmd.spec,,https://git.kernel.org/pub/scm/utils/trace-cmd/trace-cmd.git
tree.spec,https://gitlab.com/OldManProgrammer/unix-tree/-/archive/%{version}/unix-tree-%{version}.tar.gz,https://gitlab.com/OldManProgrammer/unix-tree.git
trousers.spec,https://sourceforge.net/projects/trousers/files/trousers/%{version}/trousers-%{version}.tar.gz/download
tuna.spec,https://www.kernel.org/pub/software/utils/tuna/tuna-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/tuna/tuna.git
tuned.spec,https://github.com/redhat-performance/tuned/archive/refs/tags/v%{version}.tar.gz,https://github.com/redhat-performance/tuned.git
tzdata.spec,https://data.iana.org/time-zones/releases/tzdata%{version}.tar.gz
u-boot.spec,https://github.com/u-boot/u-boot/archive/refs/tags/v%{version}.tar.gz,https://github.com/u-boot/u-boot.git
ulogd.spec,https://www.netfilter.org/projects/ulogd/files/ulogd-%{version}.tar.xz
uriparser.spec,https://github.com/uriparser/uriparser/releases/download/uriparser-%{version}/uriparser-%{version}.tar.bz2,https://github.com/uriparser/uriparser.git
userspace-rcu.spec,https://github.com/urcu/userspace-rcu/archive/refs/tags/v%{version}.tar.gz,https://github.com/urcu/userspace-rcu.git,,,
unbound.spec,https://github.com/NLnetLabs/unbound/archive/refs/tags/release-%{version}.tar.gz,https://github.com/NLnetLabs/unbound.git
unixODBC.spec,https://github.com/lurcher/unixODBC/archive/refs/tags/%{version}.tar.gz,https://github.com/lurcher/unixODBC.git
urw-fonts.spec,https://github.com/twardoch/urw-core35-fonts/archive/refs/tags/v%{version}.tar.gz,https://github.com/twardoch/urw-core35-fonts.git
usbutils.spec,https://www.kernel.org/pub/linux/utils/usb/usbutils/usbutils-%{version}.tar.xz,https://git.kernel.org/pub/scm/linux/kernel/git/gregkh/usbutils.git
utf8proc.spec,https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v%{version}.tar.gz,https://github.com/JuliaStrings/utf8proc.git
util-linux.spec,https://github.com/util-linux/util-linux/archive/refs/tags/v%{version}.tar.gz,https://github.com/util-linux/util-linux.git
util-macros.spec,https://ftp.x.org/archive//individual/util/util-macros-%{version}.tar.bz2
uwsgi.spec,https://github.com/unbit/uwsgi/archive/refs/tags/%{version}.tar.gz,https://github.com/unbit/uwsgi.git
valgrind.spec,https://sourceware.org/pub/valgrind/valgrind-%{version}.tar.bz2
vernemq.spec,https://github.com/vernemq/vernemq/archive/refs/tags/%{version}.tar.gz,https://github.com/vernemq/vernemq.git
vim.spec,https://github.com/vim/vim/archive/refs/tags/v%{version}.tar.gz,https://github.com/vim/vim.git
vsftp.spec,https://security.appspot.com/downloads/vsftpd-%{version}.tar.gz
vulkan-headers.spec,https://github.com/KhronosGroup/Vulkan-Headers/archive/refs/tags/v%{version}.tar.gz,https://github.com/KhronosGroup/Vulkan-Headers.git
vulkan-loader.spec,https://github.com/KhronosGroup/Vulkan-Loader/archive/refs/tags/v%{version}.tar.gz,https://github.com/KhronosGroup/Vulkan-Loader.git
vulkan-tools.spec,https://github.com/KhronosGroup/Vulkan-Tools/archive/refs/tags/sdk-%{version}.tar.gz,https://github.com/KhronosGroup/Vulkan-Tools.git
WALinuxAgent.spec,https://github.com/Azure/WALinuxAgent/archive/refs/tags/v%{version}.tar.gz,https://github.com/Azure/WALinuxAgent.git
wal2json17.spec,https://github.com/eulerto/wal2json/archive/refs/tags/wal2json_%{version}.tar.gz,https://github.com/eulerto/wal2json.git,,,"wal2json_"
wavefront-proxy.spec,https://github.com/wavefrontHQ/wavefront-proxy/archive/refs/tags/proxy-%{version}.tar.gz,https://github.com/wavefrontHQ/wavefront-proxy.git
wayland.spec,https://gitlab.freedesktop.org/wayland/wayland/-/archive/%{version}/wayland-%{version}.tar.gz,https://gitlab.freedesktop.org/wayland/wayland.git
wayland-protocols.spec,,https://gitlab.freedesktop.org/wayland/wayland-protocols.git
wget.spec,https://ftp.gnu.org/gnu/wget/wget-%{version}.tar.gz
whois.spec,https://salsa.debian.org/md/whois/-/archive/%{version}/whois-%{version}.tar.gz,https://salsa.debian.org/md/whois.git
wireshark.spec,https://github.com/wireshark/wireshark/archive/refs/tags/wireshark-%{version}.tar.gz,https://github.com/wireshark/wireshark.git
wpa_supplicant.spec,https://w1.fi/releases/wpa_supplicant-%{version}.tar.gz
wrapt.spec,https://github.com/GrahamDumpleton/wrapt/archive/refs/tags/%{version}.tar.gz,https://github.com/GrahamDumpleton/wrapt.git
xerces-c.spec,https://github.com/apache/xerces-c/archive/refs/tags/v%{version}.tar.gz,https://github.com/apache/xerces-c.git
xinetd.spec,https://github.com/xinetd-org/xinetd/archive/refs/tags/xinetd-%{version}.tar.gz,https://github.com/xinetd-org/xinetd.git
XML-Parser.spec,https://github.com/toddr/XML-Parser/archive/refs/tags/%{version}.tar.gz,https://github.com/toddr/XML-Parser.git
xml-security-c.spec,https://archive.apache.org/dist/santuario/c-library/xml-security-c-%{version}.tar.gz
xmlsec1.spec,https://github.com/lsh123/xmlsec/releases/download/%{version}/xmlsec1-%{version}.tar.gz,https://github.com/lsh123/xmlsec.git
xxhash.spec,https://github.com/Cyan4973/xxHash/archive/refs/tags/v%{version}.tar.gz,https://github.com/Cyan4973/xxHash.git
xz.spec,https://github.com/tukaani-project/xz/archive/refs/tags/v%{version}.tar.gz,https://github.com/tukaani-project/xz.git
yajl.spec,https://github.com/lloyd/yajl/archive/refs/tags/%{version}.tar.gz,https://github.com/lloyd/yajl.git
yaml-cpp.spec,https://github.com/jbeder/yaml-cpp/archive/refs/tags/yaml-cpp-%{version}.tar.gz,https://github.com/jbeder/yaml-cpp.git
yarn.spec,https://github.com/yarnpkg/yarn/archive/refs/tags/v%{version}.tar.gz,https://github.com/yarnpkg/yarn.git
zchunk.spec,https://github.com/zchunk/zchunk/archive/refs/tags/%{version}.tar.gz,https://github.com/zchunk/zchunk.git
zeromq.spec,https://github.com/zeromq/libzmq/releases/download/v%{version}/zeromq-%{version}.tar.gz,https://github.com/zeromq/libzmq.git
zlib.spec,https://github.com/madler/zlib/archive/refs/tags/v%{version}.tar.gz,https://github.com/madler/zlib.git
zookeeper.spec,https://github.com/apache/zookeeper/archive/refs/tags/release-%{version}.tar.gz,https://github.com/apache/zookeeper.git
zsh.spec,https://github.com/zsh-users/zsh/archive/refs/tags/zsh-%{version}.tar.gz,https://github.com/zsh-users/zsh.git
zstd.spec,https://github.com/facebook/zstd/releases/download/v%{version}/zstd-%{version}.tar.gz,https://github.com/facebook/zstd.git
'@
$Source0LookupData = $Source0LookupData | convertfrom-csv
return( $Source0LookupData )
}

function ModifySpecFile {
    param (
        [parameter(Mandatory = $true)]
        [string]$SpecFileName,
        [parameter(Mandatory = $true)]
        [string]$SourcePath,
        [parameter(Mandatory = $true)]
        [string]$photonDir,
        [parameter(Mandatory = $true)]
        [string]$Name,
        [parameter(Mandatory = $true)]
        [string]$Update,
        [parameter(Mandatory = $true)]
        [string]$UpdateDownloadFile,
        [parameter(Mandatory = $true)]
        [boolean]$OpenJDK8,
        [parameter(Mandatory = $true)]
        [string]$SHALine
    )
    $SpecFile = join-path -path (join-path -path (join-path -path (join-path -path "$SourcePath" -childpath "$photonDir") -childpath "SPECS") -childpath "$Name") -childpath "$SpecFileName"
    if (!(Test-Path $SpecFile)) {
        Write-Warning "Spec file not found, skipping modification: $SpecFile"
        return
    }
    $object=get-content $SpecFile

    $DateEntry = use-culture -Culture en-US {(get-date -UFormat "%a") + " " + (get-date).ToString("MMM") + " " + (get-date -UFormat "%d %Y") }
    $line1=[system.string]::concat("* ",$DateEntry," ","First Last <firstname.lastname@broadcom.com> ",$Update,"-1")

    $skip=$false
    $FileModified = @()
    Foreach ($line in $object)
    {
        if ($skip -eq $false)
        {
            if ($line -ilike '*Version:*') {
                if ($OpenJDK8) {$line = $line -replace 'Version:.+$', "Version:        1.8.0.$Update"}
                else {$line = $line -replace 'Version:.+$', "Version:        $Update"}
                $FileModified += $line
            }
            elseif ($line -ilike '*Release:*') {$line = $line -replace 'Release:.+$', 'Release:        1%{?dist}'; $FileModified += $line}
            elseif ($line -ilike '*Source0:*')
            {
                $FileModified += $line
                $FileModified += $SHALine
                $skip=$true
            }
            elseif ($line -ilike '%changelog*')
            {
                $FileModified += $line
                #Add Lines after the selected pattern
                $FileModified += $line1
                $FileModified += '- automatic version bump for testing purposes DO NOT USE'
            }
            elseif ($line -ilike '%define subversion*')
            {
                $FileModified += [system.string]::concat('%define subversion ',$Update)
            }
            else {$FileModified += $line}
        }
        else {$skip = $false}
    }

    if ($null -ne $FileModified) {
        $SpecsNewDirectory=join-path -path (join-path -path (join-path -path "$SourcePath" -childpath "$photonDir") -childpath "SPECS_NEW") -childpath "$Name"
        if (!(Test-Path $SpecsNewDirectory)) {New-Item $SpecsNewDirectory -ItemType Directory}

        if ($Update)
        {
            if ($Update -is [system.string]) {
                if ([System.IO.Path]::GetExtension($Update.Trim())) {$Update = [System.IO.Path]::GetFileNameWithoutExtension($Update.Trim())} # Strips .asc if present
            }
            $filename = (Join-Path -Path $SpecsNewDirectory -ChildPath ([system.string]::concat($Name,"-",$Update.Trim(),".spec"))).Trim()
            $FileModified | Set-Content $filename -Force -Confirm:$false
        }
    }
}

function urlhealth {
    param (
        [parameter(Mandatory = $true)]
        $checkurl
    )
    $urlhealthrc=""
    try
    {
        # Create a web request with HEAD method
        $request = [System.Net.HttpWebRequest]::Create($checkurl)
        $request.Method = "HEAD"

        # Get the response
        $rc = $request.GetResponse()
        $urlhealthrc = [int]$rc.StatusCode
        $rc.Close()
    }
    catch
    {
        $urlhealthrc = [int]$_.Exception.Response.StatusCode.value__
        if (($checkurl -ilike '*netfilter.org*') -or ($checkurl -ilike 'https://ftp.*'))
        {
            $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
            $session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36"
            $Referer=""
            if ($checkurl -ilike '*libnetfilter_conntrack*') {$Referer="https://www.netfilter.org/projects/libnetfilter_conntrack/downloads.html"}
            elseif ($checkurl -ilike '*libmnl*') {$Referer="https://www.netfilter.org/projects/libmnl/downloads.html"}
            elseif ($checkurl -ilike '*libnetfilter_cthelper*') {$Referer="https://www.netfilter.org/projects/libnetfilter_cthelper/downloads.html"}
            elseif ($checkurl -ilike '*libnetfilter_cttimeout*') {$Referer="https://www.netfilter.org/projects/libnetfilter_cttimeout/downloads.html"}
            elseif ($checkurl -ilike '*libnetfilter_queue*') {$Referer="https://www.netfilter.org/projects/libnetfilter_queue/downloads.html"}
            elseif ($checkurl -ilike '*libnfnetlink*') {$Referer="https://www.netfilter.org/projects/libnfnetlink/downloads.html"}
            elseif ($checkurl -ilike '*libnftnl*') {$Referer="https://www.netfilter.org/projects/libnftnl/downloads.html"}
            elseif ($checkurl -ilike '*nftables*') {$Referer="https://www.netfilter.org/projects/nftables/downloads.html"}
            elseif ($checkurl -ilike '*conntrack-tools*') {$Referer="https://www.netfilter.org/projects/conntrack-tools/downloads.html"}
            elseif ($checkurl -ilike '*iptables*') {$Referer="https://www.netfilter.org/projects/iptables/downloads.html"}

            try {
                $rc = Invoke-WebRequest -UseBasicParsing -Uri $checkurl -Method Head -TimeoutSec 10 -ErrorAction Stop `
                -WebSession $session `
                -Headers @{
                "Accept"="text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                "Accept-Encoding"="gzip, deflate, br"
                "Accept-Language"="en-US,en;q=0.9"
                "Referer"="$Referer"
                "Sec-Fetch-Dest"="document"
                "Sec-Fetch-Mode"="navigate"
                "Sec-Fetch-Site"="same-origin"
                "Sec-Fetch-User"="?1"
                "Upgrade-Insecure-Requests"="1"
                "sec-ch-ua"="`"Google Chrome`";v=`"113`", `"Chromium`";v=`"113`", `"Not-A.Brand`";v=`"24`""
                "sec-ch-ua-mobile"="?0"
                "sec-ch-ua-platform"="`"Windows`""
                }
                $urlhealthrc = [int]$rc.StatusCode
            } catch {
                $urlhealthrc = [int]$_.Exception.Response.StatusCode.value__
            }
        }
    }
    return $urlhealthrc
}
function KojiFedoraProjectLookUp {
# https://koji.fedoraproject.org/ contains a lot of Linux source packages.
# Beside the fedora packages, the source is included, but it has to be extracted from the appropriate package. Inside that download source package, you find the .tar.gz bits.
# To get an idea, see the following example.
#    download = https://kojipkgs.fedoraproject.org//packages/libaio/0.3.111/21.fc42/src/libaio-0.3.111-21.fc42.src.rpm
#
# The URL contains "libaio", the version and release, and in src directory, the fedora source package.
# Inside that package information is the .tar.gz source, here it's libaio-0.3.111.tar.gz.
#
# $SourceTagURL="https://src.fedoraproject.org/rpms/libaio/blob/main/f/sources"
# $version = ((((((Invoke-RestMethod -Uri $SourceTagURL -UseBasicParsing) -split '<code class') -split '</code>')[1]) -split '\(') -split '\)')[1]
# The example uses the latest 0.3.111 version in 21.fc42 release.
# Hence, programmatically traverse https://kojipkgs.fedoraproject.org//packages/libaio/0.3.111, then traverse the subdirectories until reaching the highest number 21.fc42
# https://kojipkgs.fedoraproject.org/packages/libaio/0.3.111/21.fc42/src/libaio-0.3.111-21.fc42.src.rpm

    param (
        [parameter(Mandatory = $true)]
        [string]$ArtefactName
    )
    $SourceRPMFileURL=""
    $SourceTagURL="https://src.fedoraproject.org/rpms/$ArtefactName/blob/main/f/sources"
    try
    {
        $ArtefactDownloadName=((((((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10 -ErrorAction Stop) -split '<code class') -split '</code>')[1]) -split '\(') -split '\)')[1]
        $ArtefactVersion=$ArtefactDownloadName -ireplace "${ArtefactName}-",""
        if ($ArtefactName -ieq "connect-proxy") {$ArtefactVersion=$ArtefactDownloadName -ireplace "ssh-connect-",""}
        if ($ArtefactName -ieq "python-pbr") {$ArtefactVersion=$ArtefactDownloadName -ireplace "pbr-",""}
        $ArtefactVersion=$ArtefactVersion -ireplace ".tar.gz",""
        $ArtefactVersion=$ArtefactVersion -ireplace "v",""

        $SourceTagURL="https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion"
        $Names = ((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10 -ErrorAction Stop) -split '/">') -split '/</a>'
        $Names = $Names | foreach-object { if (!($_ | select-string -pattern '<' -simplematch)) {$_}}
        $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}

        $NameLatest = ( $Names |Sort-Object {$_ -notlike '<*'},{($_ -replace '^.*?(\d+).*$','$1') -as [int]} | select-object -last 1 ).ToString()

        $SourceTagURL="https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion/$NameLatest/src/"

        $Names = ((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10 -ErrorAction Stop) -split '<a href="') -split '"'
        $Names = $Names | foreach-object { if (!($_ | select-string -pattern '<' -simplematch)) {$_}}
        $Names = $Names | foreach-object { if (($_ | select-string -pattern '.src.rpm' -simplematch)) {$_}}

        $SourceRPMFileName = ( $Names |Sort-Object {$_ -notlike '<*'},{($_ -replace '^.*?(\d+).*$','$1') -as [int]} | select-object -last 1 ).ToString()

        $SourceRPMFileURL= "https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion/$NameLatest/src/$SourceRPMFileName"
    }catch{
        # Silently ignore Koji lookup failures - package may not exist in Fedora
    }
    return $SourceRPMFileURL
}

function CheckURLHealth {
      [CmdletBinding()]
      Param(
        [parameter(Mandatory)]$currentTask,
        [parameter(Mandatory)]$SourcePath,
        [parameter(Mandatory)]$outputfile,
        [parameter(Mandatory)]$accessToken,
        [parameter(Mandatory)]$photonDir
    )

    class HeapSort {
    # Heapsort algorithmus from Doug Finke
    # https://github.com/dfinke/SortingAlgorithms/blob/master/HeapSort.ps1
    # modified to compare concated ascii code values
        [array] static Sort($targetList) {
            $heapSize = $targetList.Count

            for ([int]$p = ($heapSize - 1) / 2; $p -ge 0; $p--) {
                [HeapSort]::MaxHeapify($targetList, $heapSize, $p)
            }

            for ($i = $targetList.Count - 1; $i -gt 0; $i--) {
                $temp = $targetList[$i]
                $targetList[$i] = $targetList[0]
                $targetList[0] = $temp

                $heapSize--
                [HeapSort]::MaxHeapify($targetList, $heapSize, 0)
            }
            return $targetList
        }

        static MaxHeapify($targetList, $heapSize, $index) {
            $left = ($index + 1) * 2 - 1
            $right = ($index + 1) * 2
            $largest = 0

            if ($left -lt $heapSize -and [int64]([system.string]::concat((([system.Text.Encoding]::Default.GetBytes($targetList[$left])) | foreach-object tostring 000))) -gt [int64]([system.string]::concat((([system.Text.Encoding]::Default.GetBytes($targetList[$index])) | foreach-object tostring 000)))) {
                $largest = $left
            }
            else {
                $largest = $index
            }

            if ($right -lt $heapSize -and [int64]([system.string]::concat((([system.Text.Encoding]::Default.GetBytes($targetList[$right])) | foreach-object tostring 000))) -gt [int64]([system.string]::concat((([system.Text.Encoding]::Default.GetBytes($targetList[$largest])) | foreach-object tostring 000)))) {
                $largest = $right
            }

            if ($largest -ne $index) {
                $temp = $targetList[$index]
                $targetList[$index] = $targetList[$largest]
                $targetList[$largest] = $temp

                [HeapSort]::MaxHeapify($targetList, $heapSize, $largest)
            }
        }
    }

    function Get-HighestJdkVersion {
        param (
            [Parameter(Mandatory=$true)]
            [string[]]$Names,
            [Parameter(Mandatory=$true)]
            [int]$MajorRelease,
            [Parameter(Mandatory=$true)]
            [string]$filter
        )

        $returnValue=$null
        # Filter entries starting with "jdk-11"
        $tmp=[System.String]::concat($filter,"*")
        $jdkVersions = $Names | Where-Object { $_ -like $tmp }

        # Helper function to parse version strings
        function Parse-Version {
            param (
                [string]$Version
            )

            # Initialize default values
            $major = $MajorRelease
            $minor = 0
            $patch = 0
            $build = 0
            $isGa = $false

            # Remove "jdk-" prefix
            $tmp=[System.String]::concat("^",$filter)
            $versionPart = $Version -replace $tmp, ""

            # Check for -ga suffix
            if ($versionPart -match "-ga$") {
                $isGa = $true
                $versionPart = $versionPart -replace "-ga$", ""
            }

            # Split into version and build parts
            $parts = $versionPart -split "\+"
            $versionString = $parts[0]

            # Check if version string contains dots (e.g., 11.0.28)
            if ($versionString -match "\.") {
                $versionNumbers = $versionString.Split(".")
                if ($versionNumbers.Count -ge 1 -and $versionNumbers[0] -match "^\d+$") {
                    $major = [int]$versionNumbers[0]
                }
                if ($versionNumbers.Count -ge 2 -and $versionNumbers[1] -match "^\d+$") {
                    $minor = [int]$versionNumbers[1]
                }
                if ($versionNumbers.Count -ge 3 -and $versionNumbers[2] -match "^\d+$") {
                    $patch = [int]$versionNumbers[2]
                }
            }
            # If no dots, assume it's just "11" (e.g., jdk-11+0)
            elseif ($versionString -match "^\d+$") {
                $major = [int]$versionString
            }

            # Parse build number if present
            if ($parts.Count -ge 2 -and $parts[1] -match "^\d+$") {
                $build = [int]$parts[1]
            }

            return [PSCustomObject]@{
                Original = $Version
                Major = $major
                Minor = $minor
                Patch = $patch
                Build = $build
                IsGa = $isGa
            }
        }

        # Parse all versions
        $parsedVersions = $jdkVersions | ForEach-Object { Parse-Version $_ }

        # Sort versions
        $sortedVersions = $parsedVersions | Sort-Object -Property @{
            Expression = { $_.Major }
            Descending = $true
        }, @{
            Expression = { $_.Minor }
            Descending = $true
        }, @{
            Expression = { $_.Patch }
            Descending = $true
        }, @{
            Expression = { if ($_.IsGa) { [int]::MaxValue } else { $_.Build } }
            Descending = $true
        }

        # Return the original string of the highest version
        if ($sortedVersions) {$returnValue = $sortedVersions[0].Original -ireplace "jdk-"}
        return $returnValue
    }

    # Function to check if a string is integer-like (e.g., "018", "059")
    function Test-IntegerLike {
        param (
            [string]$Value
        )
        return $Value -match '^\d+$'
    }

    # Helper function to parse version string
    function Parse-Version {
        param ([string]$InputVersion)
        # Normalize hyphen-separated versions to dot-separated for parsing
        $normalizedVersion = $InputVersion -replace '-', '.'
        $parts = $normalizedVersion -split '\.'

        # Case 1: Date-based format (YYYYMMDD-X.Y)
        if ($InputVersion -match '^\d{8}-\d+\.\d+') {
            $date = [int64]$parts[0]  # YYYYMMDD
            $versionNumber = "$($parts[1]).$($parts[2])"  # X.Y as string
            return @{ Type = 'DateVersion'; Date = $date; VersionNumber = $versionNumber }
        }
        # Case 2: Version-date format (X.Y.YYYYMMDD)
        elseif ($InputVersion -match '^\d+\.\d+\.\d{8}') {
            $versionNumber = "$($parts[0]).$($parts[1])"  # X.Y as string
            $date = [int64]$parts[2]  # YYYYMMDD
            return @{ Type = 'VersionDate'; Date = $date; VersionNumber = $versionNumber }
        }
        # Case 2b: Quarterly version format (YYYY.Q#.#)
        elseif ($InputVersion -match '^(\d{4})\.Q(\d+)\.(\d+)$') {
            $year = [int]$Matches[1]
            $quarter = [int]$Matches[2]
            $patch = [int]$Matches[3]
            return @{ Type = 'StandardVersion'; Components = @($year, $quarter, $patch) }
        }
        # Case 3: Standard version format (X.Y, X.Y.Z, X.Y.Z.W, etc.)
        elseif ($normalizedVersion -match '^\d+(\.\d+)+$') {
            $components = $parts | ForEach-Object { [int]$_ }
            return @{ Type = 'StandardVersion'; Components = $components }
        }
        # Case 4: Integer-like numeric (e.g., 001 to 059)
        elseif ($InputVersion -match '^\d+$') {
            $trimmed = $InputVersion.TrimStart('0')
            if ($trimmed -eq '') { $trimmed = '0' }
            return @{ Type = 'Integer'; Value = [int64]$trimmed }
        }
        # Case 5: Decimal numeric (e.g., 0.91)
        else {
            $trimmed = $normalizedVersion.TrimStart('0')
            if ($trimmed -eq '') { $trimmed = '0' }
            if ([double]::TryParse($trimmed, [ref]$null)) {
                return @{ Type = 'Decimal'; Value = [double]$trimmed }
            }
            # Fallback to string if not numeric
            return @{ Type = 'String'; Value = $InputVersion }
        }
    }

    # Function to compare version strings
    function Compare-VersionStrings {
        param (
            [string]$Namelatest,
            [string]$Version
        )

        try {
            $v1 = Parse-Version -InputVersion $Namelatest
            $v2 = Parse-Version -InputVersion $Version

            # Rule 1: Both are date-based formats
            if ($v1.Type -in @('DateVersion', 'VersionDate') -and $v2.Type -in @('DateVersion', 'VersionDate')) {
                # Compare dates first
                if ($v1.Date -gt $v2.Date) { return 1 }
                if ($v1.Date -lt $v2.Date) { return -1 }
                # If dates are equal, compare version numbers as strings
                if ($v1.VersionNumber -gt $v2.VersionNumber) { return 1 }
                if ($v1.VersionNumber -lt $v2.VersionNumber) { return -1 }
                return 0
            }
            # Rule 2: One is date-based, it takes priority (higher)
            if ($v1.Type -in @('DateVersion', 'VersionDate') -and $v2.Type -notin @('DateVersion', 'VersionDate')) {
                return 1
            }
            if ($v2.Type -in @('DateVersion', 'VersionDate') -and $v1.Type -notin @('DateVersion', 'VersionDate')) {
                return -1
            }
            # Rule 3: Both are standard version formats (X.Y, X.Y.Z, X.Y.Z.W, etc.)
            if ($v1.Type -eq 'StandardVersion' -and $v2.Type -eq 'StandardVersion') {
                $maxLength = [math]::Max($v1.Components.Length, $v2.Components.Length)
                for ($i = 0; $i -lt $maxLength; $i++) {
                    $c1 = if ($i -lt $v1.Components.Length) { $v1.Components[$i] } else { 0 }
                    $c2 = if ($i -lt $v2.Components.Length) { $v2.Components[$i] } else { 0 }
                    if ($c1 -gt $c2) { return 1 }
                    if ($c1 -lt $c2) { return -1 }
                }
                return 0
            }
            # Rule 4: Both are integer-like numerics (e.g., 001 to 059)
            if ($v1.Type -eq 'Integer' -and $v2.Type -eq 'Integer') {
                if ($v1.Value -gt $v2.Value) { return 1 }
                if ($v1.Value -lt $v2.Value) { return -1 }
                return 0
            }
            # Rule 5: Both are decimal numerics (e.g., 0.91)
            if ($v1.Type -eq 'Decimal' -and $v2.Type -eq 'Decimal') {
                if ($v1.Value -gt $v2.Value) { return 1 }
                if ($v1.Value -lt $v2.Value) { return -1 }
                return 0
            }
            # Rule 6: Integer vs. Decimal (Integer takes priority)
            if ($v1.Type -eq 'Integer' -and $v2.Type -eq 'Decimal') {
                if ($v1.Value -gt [int64]$v2.Value) { return 1 }
                if ($v1.Value -lt [int64]$v2.Value) { return -1 }
                return 0
            }
            if ($v2.Type -eq 'Integer' -and $v1.Type -eq 'Decimal') {
                if ([int64]$v1.Value -gt $v2.Value) { return 1 }
                if ([int64]$v1.Value -lt $v2.Value) { return -1 }
                return 0
            }
            # Rule 7: StandardVersion vs. Integer or Decimal
            if ($v1.Type -eq 'StandardVersion' -and $v2.Type -in @('Integer', 'Decimal')) {
                $c2 = if ($v2.Type -eq 'Integer') { $v2.Value } elseif ($v2.Type -eq 'Decimal') { [int64]$v2.Value } else { 0 }
                if ($v1.Components[0] -gt $c2) { return 1 }
                if ($v1.Components[0] -lt $c2) { return -1 }
                return 0
            }
            if ($v2.Type -eq 'StandardVersion' -and $v1.Type -in @('Integer', 'Decimal')) {
                $c1 = if ($v1.Type -eq 'Integer') { $v1.Value } elseif ($v1.Type -eq 'Decimal') { [int64]$v1.Value } else { 0 }
                if ($c1 -gt $v2.Components[0]) { return 1 }
                if ($c1 -lt $v2.Components[0]) { return -1 }
                return 0
            }
            # Rule 8: Fallback to string comparison
            if ($v1.Value -gt $v2.Value) { return 1 }
            if ($v1.Value -lt $v2.Value) { return -1 }
            return 0
        }
        catch {
            Write-Error $_.Exception.Message
            return $null
        }
    }

    # Function to convert a version string to a comparable value
    function Convert-ToVersion {
        param (
            [Parameter(Mandatory=$true)]
            [string]$VersionInput
        )
        # Use Parse-Version from Compare-VersionStrings for consistency
        $parsed = Parse-Version -InputVersion $VersionInput
        switch ($parsed.Type) {
            'StandardVersion' { return $parsed.Components }
            'Integer' { return $parsed.Value }
            'Decimal' { return $parsed.Value }
            'DateVersion' { return $VersionInput } # String comparison for date-based
            'VersionDate' { return $VersionInput } # String comparison for date-based
            default { return $VersionInput } # Fallback to string
        }
    }

    # Main routine to get the latest name
    function Get-LatestName {
        param (
            [Parameter(Mandatory=$false)]
            [AllowEmptyString()]
            [AllowNull()]
            [string[]]$Names
        )

        # Filter out null and empty strings first
        if ($Names) {
            $Names = @($Names | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        }

        if (-not $Names -or $Names.Count -eq 0) {
            return ""
        }

        # Check if any name matches the version number pattern (dot or hyphen-separated)
        $versionNames = @($Names | Where-Object { $_ -match '^\d+([.-]Q?\d+)*$' })

        if ($versionNames -and $versionNames.Count -gt 0) {
            # Use bubble-sort style to find the maximum using Compare-VersionStrings
            $latest = $versionNames[0]
            foreach ($name in $versionNames) {
                $result = Compare-VersionStrings -Namelatest $name -Version $latest
                if ($result -eq 1) {
                    $latest = $name
                }
            }
            return $latest
        } else {
            # Handle non-version names (sort lexicographically and take the last one)
            try {
                # Try to parse as JSON if applicable
                $parsedNames = $Names | ConvertFrom-Json -ErrorAction Stop
                return ($parsedNames | Sort-Object | Select-Object -Last 1).ToString()
            } catch {
                # Fallback to lexicographic sort of original strings
                $sorted = $Names | Sort-Object | Select-Object -Last 1
                if ($sorted) { return $sorted.ToString() }
                return ""
            }
        }
    }

    function Get-FileHashWithRetry {
        <#
        .SYNOPSIS
            Computes file hash with automatic retry on lock ("being used by another process").
            Optimized for high-frequency calls (e.g. parallel processing pipelines).
            Fully cross-platform (PowerShell 7+ / .NET on Linux, macOS, Windows).
            Cybersecurity: pure built-in cmdlet, bounded execution, specific exception filter.
        #>
        [CmdletBinding()]
        param(
            [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
            [string]$Path,

            [ValidateSet('SHA1','SHA256','SHA512')]
            [string]$Algorithm = 'SHA512',

            [int]$TimeoutSeconds = 30,          # short default for performance-critical loops
            [int]$RetryIntervalMs = 500         # slow polling (500 ms = ~2 checks/sec)
        )

        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        $attempt = 0

        while ((Get-Date) -lt $deadline) {
            $attempt++
            try {
                # Single atomic call: open → hash → close
                $hashInfo = Get-FileHash -LiteralPath $Path -Algorithm $Algorithm
                Write-Verbose "Hash succeeded on attempt $attempt for $Path"
                return $hashInfo
            }
            catch [System.IO.IOException] {
                # Precise lock detection (works identically on Linux and Windows)
                if ($_.Exception.Message -like '*being used by another process*' -or
                    $_.Exception.HResult -eq -2147024864) {   # 0x80070020 = ERROR_SHARING_VIOLATION

                    if ((Get-Date) -ge $deadline) { break }
                    Start-Sleep -Milliseconds $RetryIntervalMs
                    continue
                }
                # Any other IO error (permissions, disk full, etc.) → fail fast
                throw
            }
        }

        throw "Timeout ($TimeoutSeconds s / $attempt attempts) waiting for file to unlock: $Path"
    }    


    $UpdateAvailable=""
    $urlhealth=""
    [System.string]$HealthUpdateURL=""
    [System.string]$UpdateURL=""
    [System.string]$SourceTagURL=""
    $NameLatest=""
    [System.string]$UpdateDownloadName=""
    $Names=@()
    $version=""
    $replace=@()
    [System.string]$Source0=""
    [System.string]$GitSource=""
    $gitBranch=""
    [System.string]$customRegex=""
    $ignore=@()
    [System.string]$Warning=""
    [System.string]$ArchivationDate=""

    # IN CASE OF DEBUG: UNCOMMENT AND DEBUG FROM HERE
    # -----------------------------------------------
    # if ($currentTask.spec -ilike 'aufs-util.spec')
    # {pause}
    # else
    # {return}
    # -----------------------------------------------    

    $Source0 = $currentTask.Source0

    # cut last index in $currentTask.version and save value in $version
    $versionArray=($currentTask.version).split("-")
    if ($versionArray.length -gt 0)
    {
        $version=$versionArray[0]
        for ($i=1;$i -lt ($versionArray.length -1);$i++) {$version = [System.String]::concat($version,"-",$versionArray[$i])}
        if ($versionArray[$versionArray.Length-1] -ilike '*.*')
        {
            if ([string]((($currentTask.version).split("-"))[-1]).split(".")[-1] -ne "") {$version = [System.String]::concat($version,"-",[string]((($currentTask.version).split("-"))[-1]).split(".")[-1])}
        }
    }

    # release-dependant Source0 url lookup. This is a static method and must be checked from time to time.
    if ($currentTask.spec -eq "motd.spec")
    {
        switch ($photonDir) {
            {($_ -eq "photon-3.0") -or ($_ -eq "photon-4.0")} {
                $Source0="https://github.com/rtnpro/motdgen/archive/refs/tags/%{version}.tar.gz"
                $GitSource="https://github.com/rtnpro/motdgen.git"
            }
            default {
                $Source0="https://packages.broadcom.com/artifactory/photon/photon_sources/1.0/photon-motdgen-%{version}.tar.gz"
                # VMware internal url https://github-vcf.devops.broadcom.net/vcf/photon-motdgen
            }
        }
    }

    # -------------------------------------------------------------------------------------------------------------------
    # Most Source0 urls inside the spec files are not the source url but indicate where to find the source.
    # Hence, the Source0 url value is updated to a new value.
    # The new value results from static Source0Lookup and if/then clauses. This method must be checked from time to time.
    # -------------------------------------------------------------------------------------------------------------------
    $data = Source0Lookup
    $index=($data.'specfile').indexof($currentTask.spec)
    if ([int]$index -ne -1)
    {
        $Source0 = $data[$index].'Source0Lookup'
        $GitSource = $data[$index].'gitSource'
        $gitBranch = $data[$index].'gitBranch'
        $customRegex = $data[$index].'customRegex'
        $replace += $data[$index].'replaceStrings' -split ","
        $ignore += $data[$index].'ignoreStrings' -split ","
    }
    else
    {
        if ($currentTask.spec -eq "glslang.spec") { if ($version -gt "9") {$Source0="https://github.com/KhronosGroup/glslang/archive/refs/tags/sdk-%{version}.tar.gz"}
                                                    else {$Source0="https://github.com/KhronosGroup/glslang/archive/refs/tags/%{version}.tar.gz"}}
        elseif ($currentTask.spec -eq "google-compute-engine.spec") {if ($version -lt "20190916") {$Source0="https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/%{version}.tar.gz"}
                                                                    else {$Source0="https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/v%{version}.tar.gz"}}
        elseif ($currentTask.spec -eq "gtk-doc.spec") {if ($version -lt "1.33.0") {$Source0="https://github.com/GNOME/gtk-doc/archive/refs/tags/GTK_DOC_%{version}.tar.gz"}
                                                        else {$Source0="https://github.com/GNOME/gtk-doc/archive/refs/tags/%{version}.tar.gz"}}
        elseif ($currentTask.spec -eq "haproxy.spec") { $tmpminor=($version.split(".")[0]+"."+$version.split(".")[1]);$Source0="https://www.haproxy.org/download/$tmpminor/src/devel/haproxy-%{version}.tar.gz"}
        elseif ($currentTask.spec -eq "raspberrypi-firmware.spec")
        {
            $Source0="https://github.com/raspberrypi/firmware/archive/refs/tags/%{version}.tar.gz"
            $tmpversion=$currentTask.version
            $tmpversion = $tmpversion -ireplace "1.",""
            $version = [System.String]::Concat("1.",[string]$tmpversion.Replace(".",""))
        }
    }


    if ($Source0 -ilike '*%{url}*') { $Source0 = $Source0 -ireplace '%{url}',$currentTask.url }
    # add url path if necessary and possible
    if (($Source0 -notlike '*//*') -and ($currentTask.url -ne ""))
    {
        if (($currentTask.url -match '.tar.gz$') -or ($currentTask.url -match '.tar.xz$') -or ($currentTask.url -match '.tar.bz2$') -or ($currentTask.url -match '.tgz$'))
        {$Source0=$currentTask.url}
        else
        { $Source0 = [System.String]::Concat(($currentTask.url).Trimend('/'),$Source0) }
    }
    # replace variables
    $Source0 = $Source0 -ireplace '%{name}',$currentTask.Name
    $Source0 = $Source0 -ireplace '%{version}',$version

    if ($Source0 -like '*{*')
    {
        if ($Source0 -ilike '*%{srcname}*') { $Source0 = $Source0 -ireplace '%{srcname}',$currentTask.srcname }
        if ($Source0 -ilike '*%{gem_name}*') { $Source0 = $Source0 -ireplace '%{gem_name}',$currentTask.gem_name }
        if ($Source0 -ilike '*%{extra_version}*') { $Source0 = $Source0 -ireplace '%{extra_version}',$currentTask.extra_version }
        if ($Source0 -ilike '*%{main_version}*') { $Source0 = $Source0 -ireplace '%{main_version}',$currentTask.main_version }
        if ($Source0 -ilike '*%{byaccdate}*') { $Source0 = $Source0 -ireplace '%{byaccdate}',$currentTask.byaccdate }
        if ($Source0 -ilike '*%{dialogsubversion}*') { $Source0 = $Source0 -ireplace '%{dialogsubversion}',$currentTask.dialogsubversion }
        if ($Source0 -ilike '*%{subversion}*') { $Source0 = $Source0 -ireplace '%{subversion}',$currentTask.subversion }
        if ($Source0 -ilike '*%{upstreamversion}*') { $Source0 = $Source0 -ireplace '%{upstreamversion}',$currentTask.upstreamversion }
        if ($Source0 -ilike '*%{libedit_release}*') { $Source0 = $Source0 -ireplace '%{libedit_release}',$currentTask.libedit_release }
        if ($Source0 -ilike '*%{libedit_version}*') { $Source0 = $Source0 -ireplace '%{libedit_version}',$currentTask.libedit_version }
        if ($Source0 -ilike '*%{ncursessubversion}*') { $Source0 = $Source0 -ireplace '%{ncursessubversion}',$currentTask.ncursessubversion }
        if ($Source0 -ilike '*%{cpan_name}*') { $Source0 = $Source0 -ireplace '%{cpan_name}',$currentTask.cpan_name }
        if ($Source0 -ilike '*%{xproto_ver}*') { $Source0 = $Source0 -ireplace '%{xproto_ver}',$currentTask.xproto_ver}
        if ($Source0 -ilike '*%{_url_src}*') { $Source0 = $Source0 -ireplace '%{_url_src}',$currentTask._url_src }
        if ($Source0 -ilike '*%{_repo_ver}*') { $Source0 = $Source0 -ireplace '%{_repo_ver}',$currentTask._repo_ver}
    }


    # -------------------------------------------------------------------------------------------------------------------
    # anomalies - rework for detection necessary
    # -------------------------------------------------------------------------------------------------------------------

    # The author Jörg Schilling passed away in October 2021.
    # The original URL http://gd.tuwien.ac.at/utils/schilling/cdrtoolscdrkit-1.1.11.tar.gz is no longer accessible.
    # The project is unmaintained upstream but still widely packaged in Debian, Ubuntu, Fedora, Arch Linux, Alpine, openSUSE, etc. (package name cdrkit or genisoimage).
    # Current official continuation (schilytools — the full collection including cdrtools/cdrecord, star, smake, sccs, etc.): https://codeberg.org/schilytools/schilytools
    if ($currentTask.spec -eq "cdrkit.spec")
    {
        $UpdateUrl="https://deb.debian.org/debian/pool/main/c/cdrkit/cdrkit_1.1.11.orig.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="1.1.11"
        $Warning="1"
        $ArchivationDate="2021-10-10"
    }

    if ($currentTask.spec -eq "iptraf.spec")
    {
        $UpdateURL="https://distro.ibiblio.org/fatdog/source/800/iptraf-3.0.1.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="3.0.1"
    }

    if ($currentTask.spec -eq "json-spirit.spec")
    {
        $UpdateURL="https://api-main.codeproject.com/v1/article/JSON_Spirit/downloadAttachment?src=JSON_Spirit/json_spirit_v4.08.zip"
        $HealthUpdateURL="200"
        $UpdateAvailable="3.1.2"
    }

    if ($currentTask.spec -eq "libassuan.spec")
    {
        $UpdateURL="https://www.gnupg.org/ftp/gcrypt/libassuan/libassuan-3.0.2.tar.bz2"
        $HealthUpdateURL="200"
        $UpdateAvailable="3.0.2"
    }

    if ($currentTask.spec -eq "libtiff.spec")
    {
        $UpdateURL="https://download.osgeo.org/libtiff/tiff-4.7.1.tar.xz"
        $HealthUpdateURL="200"
        $UpdateAvailable="4.7.1"
    }

    if ($currentTask.spec -eq "mpc.spec")
    {
        $UpdateURL="https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="1.3.1"
    }

    # for python-daemon.spec because pagure.io webpage downloads are broken. Still the case in June 2025.
    if ($currentTask.spec -eq "python-daemon.spec")
    {
        $UpdateURL="https://files.pythonhosted.org/packages/3d/37/4f10e37bdabc058a32989da2daf29e57dc59dbc5395497f3d36d5f5e2694/python_daemon-3.1.2.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="3.1.2"
    }

     if ($currentTask.spec -eq "python-enum.spec")
    {
        $UpdateURL="https://files.pythonhosted.org/packages/02/a0/32e1d5a21b703f600183e205aafc6773577e16429af5ad3c3f9b956b07ca/enum-0.4.7.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="0.4.7"
    }

    if ($currentTask.spec -eq "python-enum34.spec")
    {
        $UpdateURL="https://files.pythonhosted.org/packages/11/c4/2da1f4952ba476677a42f25cd32ab8aaf0e1c0d0e00b89822b835c7e654c/enum34-1.1.10.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="1.1.10"
    }

    if ($currentTask.spec -eq "python-Js2Py.spec")
    {
        $UpdateURL="https://files.pythonhosted.org/packages/cb/a5/3d8b3e4511cc21479f78f359b1b21f1fb7c640988765ffd09e55c6605e3b/Js2Py-0.74.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="0.74"
    }

    if ($currentTask.spec -eq "python-ruamel-yaml.spec")
    {
        $UpdateURL="https://files.pythonhosted.org/packages/c7/3b/ebda527b56beb90cb7652cb1c7e4f91f48649fbcd8d2eb2fb6e77cd3329b/ruamel_yaml-0.19.1.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="0.19.1"
    }

    if ($currentTask.spec -eq "runit.spec")
    {
        $UpdateURL="https://smarden.org/runit/runit-2.3.0.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="2.3.0"
    }

    if ($currentTask.spec -eq "sendmail.spec")
    {
        $UpdateURL="https://ftp.sendmail.org/sendmail.8.18.2.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="8.18.2"
    }

    if ($currentTask.spec -eq "vsftpd.spec")
    {
        $UpdateURL="https://security.appspot.com/downloads/vsftpd-3.0.5.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="3.0.5"
    }

    if ($currentTask.spec -eq "dtb-raspberrypi.spec")
    {
        $GitSource="https://github.com/raspberrypi/linux.git"
        switch ($photonDir) {
            {($_ -eq "photon-3.0")} {
                $gitBranch="rpi-4.19.y"
            }
            {($_ -eq "photon-4.0")} {
                $gitBranch="rpi-5.10.y"
            }
            {($_ -eq "photon-5.0")} {
                $gitBranch="rpi-6.1.y"
            }
            {($_ -eq "photon-6.0")} {
                $gitBranch="rpi-6.12.y"
            }
            default {
                $gitBranch="rpi-6.12.y"
            }
        }
    }

    # use case of ftp.gnu.org https://github.com/conan-io/conan-center-index/issues/27830
    # ftp.gnu.org is often down. ftpmirror.gnu.org might redirect to unsecure mirrors.
    # ftp.funet.fi is very stable and has the same content as ftp.gnu.org.
    if ($Source0.Contains("ftp.gnu.org")) {
        $Source0 = $Source0 -replace "ftp.gnu.org", "ftp.funet.fi/pub/gnu/ftp.gnu.org"
    }

    # -------------------------------------------------------------------------------------------------------------------
    # Search updates available depending on the source type
    # -------------------------------------------------------------------------------------------------------------------
    $Source0Save=$Source0

    # Check UpdateAvailable by git tags detection
    if ($GitSource)
    {
        $SourceTagURL=$GitSource
        # Data Scraping Proof of Work
        if ($SourceTagURL -like "*.git") {
            if ($SourceTagURL -match "/([^/]+)\.git$") {
                $repoName = $Matches[1]
                Push-Location
                try {
                    $ClonePath=[System.String](join-path -path (join-path -path $SourcePath -childpath $photonDir) -childpath "clones")
                    if (!(Test-Path $ClonePath)) {New-Item $ClonePath -ItemType Directory}
                    
                    # override with special cases
                    if ($currentTask.spec -ilike 'gstreamer-plugins-base.spec') {$repoName="gst-plugins-base-"}

                    # Push the current directory to the stack
                    $SourceClonePath=[System.String](join-path -path $ClonePath -childpath $repoName)
                    $cloneAttempt = 0
                    $maxCloneAttempts = 2
                    while ($cloneAttempt -lt $maxCloneAttempts) {
                        $cloneAttempt++
                        if (!(Test-Path $SourceClonePath)) {
                            Set-Location -Path $ClonePath -ErrorAction Stop
                            # Clone the repository
                            try {
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "clone $SourceTagURL -b $gitBranch $repoName" -WorkingDirectory $ClonePath | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "clone $SourceTagURL $repoName" -WorkingDirectory $ClonePath | Out-Null
                                    # the very first time, you receive the origin names and not the version names. From the 2nd run, all is fine.
                                    if (Test-Path $SourceClonePath) {
                                        Set-Location $SourceClonePath
                                        if (!([string]::IsNullOrEmpty($gitBranch))) {
                                            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags origin $gitBranch" -WorkingDirectory $SourceClonePath| Out-Null
                                        } else {
                                            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $SourceClonePath | Out-Null
                                        }
                                    } else {
                                        Write-Warning "Clone directory not created for $repoName - clone may have failed silently"
                                    }
                                }
                            }
                            catch {
                                Write-Warning "Git clone failed for $repoName : $_"
                            }
                        }
                        else {
                            # Navigate to the repository directory
                            Set-Location -Path $SourceClonePath -ErrorAction Stop # --git-dir [...] fetch does not work correctly
                            try {
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "fetch --prune --prune-tags --tags origin $gitBranch" -WorkingDirectory $SourceClonePath | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $SourceClonePath | Out-Null
                                }
                            }
                            catch {
                                Write-Warning "Git fetch failed for $repoName : $_"
                            }
                        }

                        # Run git tag -l and collect output in an array
                        if ((Test-Path $SourceClonePath) -and (Test-Path (Join-Path $SourceClonePath ".git"))) {
                            if (!([string]::IsNullOrEmpty($customRegex))) {$Names = git tag -l | Where-Object { $_ -match "^$([regex]::Escape($repoName))-" } | ForEach-Object { $_.Trim()}}
                            else {$Names = git tag -l | ForEach-Object { $_.Trim() }}
                            $urlhealth="200"
                            break
                        } else {
                            if ($cloneAttempt -lt $maxCloneAttempts) {
                                Write-Warning "No valid git repository at $SourceClonePath for $repoName - deleting and retrying (attempt $cloneAttempt of $maxCloneAttempts)"
                                if (Test-Path $SourceClonePath) { Remove-Item -Path $SourceClonePath -Recurse -Force -ErrorAction SilentlyContinue }
                            } else {
                                Write-Warning "No valid git repository at $SourceClonePath for $repoName after $maxCloneAttempts attempts - skipping tag listing"
                                $Names = @()
                            }
                        }
                    }
                } catch {
                    Write-Warning "Git operation failed for $repoName : $_"
                }
                finally {
                    pop-location
                }
            }
        }

        # special cases
        if ($currentTask.spec -like "openjdk11.spec") { $NameLatest = Get-HighestJdkVersion -Names $Names -MajorRelease 11 -Filter "jdk-11"; $Names=$null}
        if ($currentTask.spec -like "openjdk17.spec") { $NameLatest = Get-HighestJdkVersion -Names $Names -MajorRelease 17 -Filter "jdk-17"; $Names=$null}
        if ($currentTask.spec -like "openjdk21.spec") { $NameLatest = Get-HighestJdkVersion -Names $Names -MajorRelease 21 -Filter "jdk-21"; $Names=$null}

        try {
            if (($SourceTagURL -ne "") -and ($null -ne $Names)) {

                if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                $replace +="-final"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                $Names = Clean-VersionNames $Names

                if ($currentTask.spec -notlike "amdvlk.spec")
                {
                    $Names = $Names  -replace "v",""
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                }

                # get name latest
                if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
            }
        }catch{$NameLatest=""}

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

            $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                # Write-Host "$Namelatest is higher than $version"
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                # Write-Host "$version is higher than $Namelatest"
                $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
            }
            else {
                # Write-Host "$Namelatest is equal to $version"
                $UpdateAvailable = "(same version)"
            }
         }
    }
    # Check UpdateAvailable by github tags detection
    else
    {
    if ($Source0 -like '*{*') {$urlhealth = "substitution_unfinished"}
    else
    {
        $urlhealth = urlhealth($Source0)
        if ($urlhealth -ne "200")
        {
            # different trycatch-combinations to get a healthy github.com related Source0 url
            if ($Source0 -ilike '*github.com*')
            {
                if ($Source0 -ilike '*/archive/refs/tags/*')
                {
                    # check /archive/refs/tags/%{name}-v%{version} and /%{name}-%{version}
                    $Source0=$Source0Save
                    $tmp=[System.String]::Concat(('/archive/refs/tags/'),$currentTask.Name,"-","v",$version)
                    $tmpnew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                    $Source0 = $Source0 -ireplace $tmp,$tmpnew
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        $Source0=$Source0Save
                        $tmp=[System.String]::Concat(('/archive/refs/tags/'),$currentTask.Name,"-",$version)
                        $tmpnew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                        $Source0 = $Source0 -ireplace $tmp,$tmpnew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                            $tmp=[System.String]::Concat(('/archive/refs/tags/'),$currentTask.Name,"-",$version)
                            $tmpnew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                            $Source0 = $Source0 -ireplace $tmp,$tmpnew
                            $urlhealth = urlhealth($Source0)
                            if ($urlhealth -ne "200")
                            {
                                # some versions have a _ in their version number
                                $Source0=$Source0Save
                                $versionnew = ([string]$version).Replace("_",".")
                                $Source0 = $Source0 -ireplace $version,$versionnew
                                $urlhealth = urlhealth($Source0)
                                if ($urlhealth -ne "200")
                                {
                                    # some versions need a - in their version number
                                    $Source0=$Source0Save
                                    $versionnew = ([string]$version).Replace(".","-")
                                    $Source0 = $Source0 -ireplace $version,$versionnew
                                    $urlhealth = urlhealth($Source0)
                                    if ($urlhealth -ne "200")
                                    {
                                        # some versions need a _ in their version number
                                        $Source0=$Source0Save
                                        $versionnew = ([string]$version).Replace(".","_")
                                        $Source0 = $Source0 -ireplace $version,$versionnew
                                        $urlhealth = urlhealth($Source0)
                                        if ($urlhealth -ne "200")
                                        {
                                            $Name=""
                                            $NameArray=($currentTask.Name).split("-")
                                            if ($NameArray.length -gt 0) { $Name=$NameArray[$NameArray.length -1]}
                                            if ($Name -ne "")
                                            {
                                                $tmp=[System.String]::Concat(('/archive/refs/tags/'),$Name,"-",$version)
                                                $tmpnew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                                                $Source0 = $Source0 -ireplace $tmp,$tmpnew
                                                $urlhealth = urlhealth($Source0)
                                                if ($urlhealth -ne "200")
                                                {
                                                    $Source0=$Source0Save
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                elseif ($Source0 -ilike '*/archive/*')
                {
                    $Source0=$Source0Save
                    $tmp=[System.String]::Concat(('/archive/'),$currentTask.Name,"-")
                    $Source0 = $Source0 -ireplace $tmp,'/archive/refs/tags/'
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        # check without naming but with a 'v' before version
                        $Source0=$Source0Save
                        $tmp=[System.String]::Concat(('/archive/'),$currentTask.Name,"-")
                        $Source0 = $Source0 -ireplace $tmp,'/archive/refs/tags/v'
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            # check with /releases/download/v{name}/{name}-{version}
                            $Source0=$Source0Save
                            $tmp=[System.String]::Concat(('/archive/'),$currentTask.Name,"-",$version)
                            $tmpnew=[System.String]::Concat(('/releases/download/v'),$version,"/",$currentTask.Name,"-",$version,'-linux-amd64')
                            $Source0 = $Source0 -ireplace $tmp,$tmpnew
                            $urlhealth = urlhealth($Source0)
                            if ($urlhealth -ne "200")
                            {
                                $Source0=$Source0Save
                            }
                        }
                    }
                }
                elseif (($Source0 -ilike '*/releases/download/*') -and ($Source0 -notlike '*/refs/tags/*'))
                {
                    $Source0=$Source0Save
                    $tmp=[System.String]::Concat(('/releases/download/'),$currentTask.Name,"-",$version,"/",$currentTask.Name,"-",$version)
                    $tmpnew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                    $Source0 = $Source0 -ireplace $tmp,$tmpnew
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        # check without naming but with a 'v' before version
                        $Source0=$Source0Save
                        $tmp=[System.String]::Concat(('/releases/download/'),$version,"/",$currentTask.Name,"-",$version)
                        $tmpnew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                        $Source0 = $Source0 -ireplace $tmp,$tmpnew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                            $tmp=[System.String]::Concat(('/releases/download/'),$version,"/",$currentTask.Name,"-",$version)
                            $tmpnew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                            $Source0 = $Source0 -ireplace $tmp,$tmpnew
                            $urlhealth = urlhealth($Source0)
                            if ($urlhealth -ne "200")
                            {
                                $Source0=$Source0Save
                            }
                        }
                    }
                }
                else
                {
                    $Source0=$Source0Save
                    $tmp=[System.String]::Concat($currentTask.Name,"-",$version)
                    $tmpnew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                    $Source0 = $Source0 -ireplace $tmp,$tmpnew
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        $Source0=$Source0Save
                        $tmp=[System.String]::Concat($currentTask.Name,"-",$version)
                        $tmpnew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                        $Source0 = $Source0 -ireplace $tmp,$tmpnew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                        }
                    }
                }
            }
            if ($urlhealth -ne "200")
            {
                $urlhealth = urlhealth($Source0)
            }
        }
    }
    if ($Source0 -ilike '*github.com*')
    {
        # Populate header information for github api requests
        $headers = @{
            Authorization = "Bearer $accessToken"
            Accept = "application/vnd.github.v3+json"  # Specify GitHub API version
        }
        # Autogenerated SourceTagURL from Source0
        $TmpSource=$Source0 -ireplace 'https://github.com',""
        $TmpSource=$TmpSource -ireplace 'https://www.github.com',""
        $TmpSource=$TmpSource -ireplace 'http://github.com',""
        $TmpSource=$TmpSource -ireplace 'http://www.github.com',""
        $TmpSource=$TmpSource -ireplace '/archive/refs/tags',""
        $TmpSource=$TmpSource -ireplace '/archive',""
        $SourceTagURLArray=($TmpSource).split("/")

        if ($SourceTagURLArray.Length -gt 1) {
            if ($Source0 -like "*/archive/*") {
                $SourceTagURL = "https://api.github.com/repos/$($SourceTagURLArray[1])/$($SourceTagURLArray[2])/tags"
            }
            elseif ($Source0 -like "*/releases/download/*") {
                $SourceTagURL = "https://api.github.com/repos/$($SourceTagURLArray[1])/$($SourceTagURLArray[2])/releases"
            }

            # special cases
            $specs = @(
                "apr-util.spec",
                "go.spec",
                "httpd.spec",
                "hwloc.spec",
                "jna.spec",
                "libmodulemd.spec",
                "libnsl.spec",
                "libxkbcommon.spec",
                "lmdb.spec",
                "logrotate.spec",
                "mariadb.spec",
                "mkinitcpio.spec",
                "npth.spec",
                "openjdk11.spec",
                "openjdk17.spec",
                "openjdk21.spec",
                "paho-c.spec",
                "python-coverage.spec",
                "python-decorator.spec",
                "python-hypothesis.spec",
                "python-networkx.spec",
                "python-rsa.spec",
                "python-wheel.spec",
                "selinux-policy.spec"
            )
            if ($currentTask.spec -in $specs) {
                $SourceTagURL = "https://github.com/" + $SourceTagURLArray[1] + "/" + $SourceTagURLArray[2] + "/tags"
            }
        }

        if (!([string]::IsNullOrEmpty($SourceTagURL))) {
            try{
                if ($SourceTagURL -ilike '*/releases*')
                {
                    $Names = (invoke-webrequest $SourceTagURL -UseBasicParsing -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop | convertfrom-json).tag_name
                    if ([string]::IsNullOrEmpty($Names -join ''))
                    {
                        $Names = (invoke-webrequest $SourceTagURL -UseBasicParsing -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop | convertfrom-json).name
                        if ([string]::IsNullOrEmpty($Names -join ''))
                        {
                            $Names = ((invoke-webrequest $SourceTagURL -UseBasicParsing -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop | convertfrom-json).assets).name
                            if ([string]::IsNullOrEmpty($Names -join ''))
                            {
                                $SourceTagURL=$SourceTagURL -ireplace "/releases","/tags"
                            }
                        }
                    }
                }
                if ($SourceTagURL -ilike '*/tags*')
                {
                    $i=0
                    $lastpage=$false
                    do
                    {
                        $i++
                        try
                        {
                            $tmpUrl=[System.String]::Concat($SourceTagURL,"?page=",$i)
                            $tmpdata = (invoke-restmethod -uri $tmpUrl -usebasicparsing -TimeoutSec 10 -headers $headers -ErrorAction Stop).name
                            if ([string]::IsNullOrEmpty($tmpdata -join ''))
                            { $lastpage=$true }
                            else
                            {
                                $Names += $tmpdata
                                # do not parse all pages because the rate limit might become an issue. Hence, use the first page only and set $lastpage=true.
                                if (!($currentTask.spec -ilike 'edgex.spec')) {$lastpage=true}
                            }
                        }
                        catch
                        {
                            $lastpage=$true
                        }
                    }
                    until ($lastpage -eq $true)

                    if ([string]::IsNullOrEmpty($Names))
                    {
                        $Names = ((invoke-restmethod -uri $tmpUrl -usebasicparsing -TimeoutSec 10 -headers @{Authorization = "Bearer $accessToken"} -ErrorAction Stop) -split "href") -split "rel="
                        $Names = $Names | foreach-object { if (($_ | select-string -pattern '/archive/refs/tags' -simplematch)) {$_}}
                        $Names = ($Names | foreach-object { split-path $_ -leaf }) -ireplace '" ',""
                    }

                }

                if ($Names) {
                    # remove ending
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.whl' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.asc' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.dmg' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.zip' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.exe' -simplematch)) {$_}}
                    $Names = $Names -replace ".tar.gz",""
                    $Names = $Names -replace ".tar.bz2",""
                    $Names = $Names -replace ".tar.xz",""

                    # post parse
                    switch($currentTask.spec)
                    {
                    "aide.spec" {$replace +="cs.tut.fi.import"; $replace+=".release"; break}
                    "apache-tomcat.spec"
                    {
                        if ($outputfile -ilike '*-3.0_*') { $Names = $Names | foreach-object { if ($_ -like '8.*') {$_}}}
                        elseif ($outputfile -ilike '*-4.0_*') { $Names = $Names | foreach-object { if ($_ -like '8.*') {$_}}}
                        elseif ($outputfile -ilike '*-5.0_*') { $Names = $Names | foreach-object { if ($_ -like '10.*') {$_}}}
                    }
                    "at-spi2-core.spec" {$replace +="AT_SPI2_CORE_3_6_3"; $replace +="AT_SPI2_CORE_"; break}
                    "automake.spec" { $Names = $Names -ireplace "-","."; break }
                    "bcc.spec" {$replace +="src-with-submodule.tar.gz"; break}
                    "bpftrace.spec" {$replace +="binary.tools.man-bundle.tar.xz"; break}
                    "calico-cni.spec" {$replace +="calico-amd64"; $replace +="calico-arm64"; break}
                    "calico-confd.spec" {$replace +="-darwin-amd64"; $replace +="confd-"; break}
                    "chrpath.spec" {$replace +="RELEASE_"; break}
                    "cloud-init.spec" {$replace +="ubuntu-";$replace +="ubuntu/"; break}
                    "colm.spec" {$replace +="colm-barracuda-v5"; $replace +="colm-barracuda-v4"; $replace +="colm-barracuda-v3"; $replace +="colm-barracuda-v2"; $replace +="colm-barracuda-v1"; $replace +="colm-"; break}
                    "cni.spec"
                    {
                        # $Names = $Names | foreach-object { if ($_ | select-string -pattern 'cni-plugins-linux-amd64-' -simplematch) {$_}}
                        # $replace +="cni-plugins-linux-amd64-"
                        $replace +="v"
                        break
                    }
                    "docker-20.10.spec" {$Names = $Names | foreach-object { if (!($_ | select-string -pattern 'xdocs-v' -simplematch)) {$_}}; break}
                    "dracut.spec" {$replace +="RHEL-"; break}
                    "ecdsa.spec" {$replace +="python-ecdsa-"; break}
                    "efibootmgr.spec" {$replace +="rhel-";$replace +="Revision_"; $replace+="release-tag"; $replace +="-branchpoint"; break}
                    "frr.spec" {$replace +="reindent-master-";$replace +="reindent-"; $replace +="before"; $replace +="after"; break}
                    "fribidi.spec" {$replace +="INIT"; break}
                    "falco.spec" { $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'agent/' -simplematch)) {$_}} ; break}
                    "fuse-overlayfs.spec.spec" {$replace +="aarch64"; break}
                    "glib.spec"
                    {
                        $replace +="start"; $replace +="PRE_CLEANUP"; $replace +="GNOME_PRINT_"
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'GTK_' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'gobject_' -simplematch)) {$_}}
                        break
                    }
                    "glibmm.spec"
                    {
                        $replace +="start"
                        break
                    }
                    "glib-networking.spec" {$replace +="glib-"; break}
                    "glslang.spec" {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'untagged-' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'vulkan-' -simplematch)) {$_}}
                        $replace +="master-tot";$replace +="main-tot";$replace +="sdk-"; $replace +="SDK-candidate-26-Jul-2020";$replace+="Overload400-PrecQual"
                        $replace +="SDK-candidate";$replace+="SDK-candidate-2";$replace+="GL_EXT_shader_subgroup_extended_types-2016-05-10";$replace+="SPIRV99"
                        break
                    }
                    "gnome-common.spec" {$replace +="version_"; $replace +="v7status"; $replace +="update_for_spell_branch_1"; $replace +="twodaysago"; $replace +="toshok-libmimedir-base"; $replace +="threedaysago"; break}
                    "gobject-introspection.spec" {$replace +="INITIAL_RELEASE"; $replace +="GOBJECT_INTROSPECTION_"; break}
                    "go.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'weekly' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'release' -simplematch)) {$_}}
                        break
                    }
                    "gstreamer.spec" {$replace +="sharp-"; break}
                    "gtk3.spec" {$replace +="VIRTUAL_ATOM-22-06-"; $replace +="GTK_ALL_"; $replace +="TRISTAN_NATIVE_LAYOUT_START"; $replace +="START"; break}
                    "gtk-doc.spec" {$replace +="GTK_DOC_"; $replace +="start"; break}
                    "httpd.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'apache' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'mpm-' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'djg' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'dg_' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'wrowe' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'striker' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'PCRE_' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'MOD_SSL_' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'HTTPD_LDAP_' -simplematch)) {$_}}
                        break
                    }
                    "icu.spec"
                    {
                        $Names = $Names | foreach-object { if (($_ | select-string -pattern 'release-' -simplematch)) {$_ -ireplace 'release-',""}}
                        $Names = $Names | foreach-object { $_ -ireplace '-',"."}
                        break
                    }
                    "inih.spec" {$replace +="r"; break}
                    "iperf.spec" {$replace +="trunk"; $replace +="iperf3"; break}
                    "iputils.spec" {$replace +="s"; break}
                    "initscripts.spec" {$replace +="upstart-"; $replace +="unstable"; break}
                    "json-glib.spec" {$replace +="json-glib-"; break}
                    "jsoncpp.spec" {$replace +="svn-release-"; $replace +="svn-import"; break}
                    "krb5.spec" {$replace+="-final"; break}
                    "kubernetes-dns.spec" {$replace +="test"; break}
                    "kubernetes-metrics-server.spec" {$replace +="metrics-ser-helm-chart-3.8.3"; break}
                    "libevent.spec" {$replace +="-stable"; break}
                    "libgd.spec" {$replace +="gd-"; break }
                    "libev.spec" {$replace +="rel-"; break}
                    "libnl.spec" {$replace +="libnl"; break}
                    "libpsl.spec" {$replace +="libpsl-"; $replace +="debian/"; break}
                    "librepo.spec" {$replace +="librepo-"; break}
                    "libselinux.spec" {$replace +="sepolgen-"; $replace +="checkpolicy-3.5"; break}
                    "libsolv.spec" {$replace +="BASE-SuSE-Code-13_"; $replace +="BASE-SuSE-Code-12_3-Branch"; $replace +="BASE-SuSE-Code-12_2-Branch"; $replace +="BASE-SuSE-Code-12_1-Branch"; $replace +="1-Branch"; break}
                    "libsoup.spec"
                    {
                        $replace +="SOUP_"; $replace +="libsoup-pre214-branch-base"; $replace +="libsoup-hacking-branch-base"; $replace +="LIB"; $replace +="soup-2-0-branch-base"
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'gnome-' -simplematch)) {$_}}
                        break
                    }
                    "libX11.spec" { $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'xf86-' -simplematch)) {$_}} ; break}
                    "libXinerama.spec" {$replace +="XORG-7_1"; break}
                    "libxml2.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'LIBXML2' -simplematch)) {$_}}
                        break
                    }
                    "libxslt.spec" {$replace +="LIXSLT_"; break}
                    "linux-PAM.spec" {$replace +="pam_unix_refactor"; break}
                    "lm-sensors.spec"
                    {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '-' -simplematch) {$_ -ireplace '-',"."} else {$_}}
                        $replace +="i2c.2.8.km2"; $replace+="v."
                        break
                    }
                    "lshw.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'A.' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'T.' -simplematch)) {$_}}
                        $Names = $Names -ireplace "B.","9999" # tag detection for later
                    }
                    "lz4.spec" { $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'r' -simplematch)) {$_}} ; break}
                    "mariadb.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'toku' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'serg-' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'percona-' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'mysql-' -simplematch)) {$_}}
                        break
                    }
                    "mc.spec" {$replace +="mc-"; break}
                    "mkinitcpio.spec"
                    {
                        $SourceTagURL="https://github.com/archlinux/mkinitcpio/tags"
                        $Names = (invoke-webrequest $SourceTagURL -UseBasicParsing -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop).links.href
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                        $Names = $Names -replace "/archlinux/mkinitcpio/archive/refs/tags/v",""
                        $Names = $Names -replace ".tar.gz",""
                        break
                    }
                    "ModemManager.spec" {$replace +="-dev"; break}
                    "mysql.spec" {$replace +="mysql-cluster-"; break}
                    "network-config-manager.spec"
                    {
                        $Names = $Names -ireplace ".a",".0.9991"
                        $Names = $Names -ireplace ".b",".0.9992"
                        $Names = $Names -ireplace ".c",".0.9993"
                        break
                    }
                    "newt.spec" {$replace +="r"; $Names = $Names -replace "-","."; break}
                    "ninja-build.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'release-' -simplematch)) {$_}}
                        break
                    }
                    "open-vm-tools.spec" {$replace +="stable-"; break}
                    "pandoc.spec" {$replace +="pandoc-server-"; $replace +="pandoc-lua-engine-"; $replace +="pandoc-cli-0.1"; $replace +="new1.16deb"; $replace +="list"; break}
                    "pango.spec" {$replace +="tical-branch-point"; break}
                    "popt.spec" {$replace +="-release"; break}
                    "powershell.spec" {$replace +="hashes.sha256";break}
                    "python-babel.spec" {$replace +="dev-2a51c9b95d06"; break}
                    "python-cassandra-driver.spec" {$replace +="3.9-doc-backports-from-3.1"; $replace +="-backport-prepared-slack"; break}
                    "python-decorator.spec"
                    {
                        $Names = (invoke-webrequest $SourceTagURL -headers $headers -method Get -TimeoutSec 10 -ErrorAction Stop).links.href
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                        $Names = $Names -replace "/micheles/decorator/archive/refs/tags/",""
                        $Names = $Names -replace ".tar.gz",""
                        break
                    }
                    "python-ethtool.spec" {$replace +="libnl-1-v0.6"; break}
                    "python-fuse.spec" {$replace +="start"; break}
                    "python-hatchling.spec"
                    {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern 'hatchling-' -simplematch) {$_}}
                        $replace +="hatchling-v"
                    }
                    "python-hypothesis.spec"
                    {
                        $Names = (invoke-webrequest $SourceTagURL -UseBasicParsing -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop).links.href
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                        $Names = $Names -replace "/HypothesisWorks/hypothesis/archive/refs/tags/hypothesis-python-",""
                        $Names = $Names -replace ".tar.gz",""
                        break
                    }
                    "python-lxml.spec" {$replace +="lxml-"; break}
                    "python-more-itertools.spec" {$replace +="v"; break}
                    "python-networkx.spec" {$replace += "python-networkx-"; $replace += "networkx-"; break }
                    "python-numpy.spec" {$replace +="with_maskna"; break}
                    "python-pyparsing.spec" {$replace +="pyparsing_"; break}
                    "python-setproctitle.spec" {$replace +="version-"; break}
                    "python-twisted.spec" {$replace += "python-"; $replace += "twisted-";break}
                    "python-webob.spec" {$replace +="sprint-coverage"; break}
                    "python-pytz.spec" {$replace +="release_"; break}
                    "rabbitmq3.10.spec" {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern 'v3.10.' -simplematch) {$_}}
                        break
                    }
                    "ragel.spec" {$replace +="ragel-pre-colm"; $replace +="ragel-barracuda-v5"; $replace +="barracuda-v4"; $replace +="barracuda-v3"; $replace +="barracuda-v2"; $replace +="barracuda-v1"; break}
                    "redis.spec" {$replace +="with-deprecated-diskstore"; $replace +="vm-playpen"; $replace +="twitter-20100825"; $replace +="twitter-20100804"; break}
                    "s3fs-fuse.spec" {$replace +="Pre-v"; break}
                    "salt3.spec"  {$Names = $Names -ireplace "-","."; $replace +="Pre.v"; break}
                    "selinux-policy.spec"
                    {
                        $Names = (invoke-webrequest $SourceTagURL -UseBasicParsing -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop).links.href
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                        $Names = $Names -replace "/fedora-selinux/selinux-policy/archive/refs/tags/v",""
                        $Names = $Names -replace ".tar.gz",""
                        $replace +="y2023"
                        break
                    }
                    "spirv-tools.spec" {$replace +="sdk-"; break}
                    "sysdig.spec" {
                        $replace +="sysdig-inspect/"; $replace +="simpledriver-auto-dragent-20170906"; $replace +="s20171003"
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'falco/' -simplematch)) {$_}}
                        break
                    }
                    "systemd.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'systemd-v' -simplematch)) {$_}}
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'udev-' -simplematch)) {$_}}
                        $Names = $Names -ireplace "v",""
                        $Names = $Names -ireplace "-","."
                        $Names = $Names | foreach-object { try{if ([int]$_ -gt 173) {$_}}catch{}}
                        break
                    }
                    "squashfs-tools.spec" {$replace +="CVE-2021-41072"; break}
                    "uwsgi.spec" {$replace +="no_server_mode"; break}
                    "vulkan-headers.spec" {$replace +="vksc"; break}
                    "vulkan-loader.spec" {$replace +="windows-rt-"; break}
                    "vulkan-tools.spec" {$replace +="sdk-"; break}
                    "wavefront-proxy.spec" {$replace +="wavefront-";$replace +="proxy-"; break}
                    "xinetd.spec"
                    {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '-' -simplematch) {$_ -ireplace '-',"."} else {$_}}
                        $replace +="xinetd."
                        $replace +="20030122"
                        break
                    }
                    "xxhash.spec"
                    {
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'r' -simplematch)) {$_}}
                        break
                    }
                    "zsh.spec" {$Names = $Names | foreach-object { if (!($_ | select-string -pattern '-test' -simplematch)) {$_}} ; break}
                    "zstd.spec" {$replace +="zstd"; break}
                    Default {}
                    }

                    if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                    $replace += $currentTask.Name + "."
                    $replace += $currentTask.Name + "-"
                    $replace += $currentTask.Name + "_"
                    $replace += $currentTask.Name
                    $replace += "ver"
                    $replace += "release_"
                    $replace += "release-"
                    $replace += "release"
                    # Do not add [...]replace(($replace[$i]).tolower() because later e.g. for downloading resources the exact case-sensitive match is important.
                    foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                    $Names = Clean-VersionNames $Names

                    $Names = $Names -ireplace "v", ""

                    if ($currentTask.spec -notlike "amdvlk.spec") {
                        $Names = $Names | foreach-object { if ($_ -match '\d') { $_ } }
                        $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) { $_ } }
                    }

                    # get name latest
                    if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
                }
            }
            catch{$NameLatest=""}
        }

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

            if ($currentTask.spec -ilike 'lshw.spec') {$NameLatest = $NameLatest -replace "9999","B."}
            if ($currentTask.spec -ilike 'network-config-manager.spec')
            {
                $NameLatest = $NameLatest -replace ".0.9991",".a"
                $NameLatest = $NameLatest -replace ".0.9992",".b"
                $NameLatest = $NameLatest -replace ".0.9993",".c"
            }

            $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                # Write-Host "$Namelatest is higher than $version"
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                # Write-Host "$version is higher than $Namelatest"
                $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
            }
            else {
                # Write-Host "$Namelatest is equal to $version"
                $UpdateAvailable = "(same version)"
            }
         }
    }
    # Check UpdateAvailable by ftp.* and download.savannah.gnug.org tags detection
    elseif (($Source0 -ilike '*ftp.*') -or ($Source0 -ilike '*/ftp/*') -or ($Source0 -ilike '*ftpmirror.*') -or ($Source0 -ilike '*download.savannah.gnu.org*'))
    {
        # ausnahmen
        if (($currentTask.spec -ilike 'mozjs.spec') -or ($currentTask.spec -ilike 'mozjs60.spec'))
        {
            $SourceTagURL="https://ftp.mozilla.org/pub/firefox/releases/"
            $Names = ((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10 -ErrorAction Stop) -split 'a href=') -split '>'
            if ($Names) {
                $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                $Names = $Names -replace '/</a'

                if ($currentTask.spec -ilike 'mozjs60.spec')
                {
                    $Names = $Names | foreach-object { if ($_ -match '60.') {$_}}
                    $Names = $Names -replace "esr"
                }
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                if ($Names -ilike '*.*')
                {
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                }
                else
                {
                    try{$NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()}catch{}
                }
                if ($currentTask.spec -ilike 'mozjs60.spec') {$SourceTagURL=$SourceTagURL+$NameLatest+"esr/source/"}
                else {$SourceTagURL=$SourceTagURL+$NameLatest+"/source/"}
            }
        }
        elseif ($currentTask.spec -ilike 'nss.spec')
        {
            $SourceTagURL="https://ftp.mozilla.org/pub/security/nss/releases/"
            $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split 'a href=') -split '>'
            if ($Names) {
                $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                $Names = $Names -replace '/</a',""
                $Names = $Names -replace "NSS_",""
                $Names = $Names -replace "_RTM",""
                $Names = $Names -replace "_","."
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                $NameLatest = $NameLatest.replace(".","_")
                $SourceTagURL=[System.String]::Concat($SourceTagURL,"NSS_",$NameLatest,"_RTM/src/")
            }
        }
        elseif ($currentTask.spec -ilike 'nspr.spec')
        {
            $SourceTagURL="https://ftp.mozilla.org/pub/nspr/releases/"
            $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split 'a href=') -split '>'
            if ($Names) {
                $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                $Names = $Names -replace '/</a'
                $Names = $Names -replace "v"
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                if ($Names -ilike '*.*')
                {
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                }
                else
                {
                    try{$NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()}catch{}
                }
                $SourceTagURL=$SourceTagURL+"v"+$NameLatest+"/src/"
            }
        }
        elseif (($currentTask.spec -ilike 'python2.spec') -or ($currentTask.spec -ilike 'python3.spec'))
        {
            $replace=@("Python-")
            do
            {
                $SourceTagURL="https://www.python.org/ftp/python/"
                $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split 'a href=') -split '>'
                if ($Names) {
                    $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                    $Names = $Names -replace '/</a'

                    if ($currentTask.spec -ilike 'python2.spec')
                    {
                        $Names = $Names | foreach-object { if ($_ -match '^2.') {$_}}
                    }
                    elseif ($currentTask.spec -ilike 'python3.spec')
                    {
                        $Names = $Names | foreach-object { if ($_ -match '^3.') {$_}}
                    }
                    # Do not add [...]replace(($replace[$i]).tolower() because later e.g. for downloading resources the exact case-sensitive match is important.
                    foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                    $SourceTagURL=$SourceTagURL+$NameLatest
                    $Names = ((((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split "<tr><td") -split 'a href=') -split '>') -split "title="
                    if ($Names) {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                        $Names = ($Names | foreach-object { if (!($_ | select-string -pattern '</a' -simplematch)) {$_}}) -ireplace '"',""
                        $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.sig' -simplematch)) {$_}}
                        $Names = $Names  -replace ".tar.gz",""
                        $Names = $Names  -replace ".tar.bz2",""
                        $Names = $Names  -replace ".tar.xz",""
                        $Names = $Names  -replace ".tar.lz",""
                        $Names = $Names -ireplace "Python-",""
                        $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                        $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                        if ([string]::IsNullOrEmpty($Names)) {$replace +=$NameLatest}
                    }
                }
            } until (!([string]::IsNullOrEmpty($Names -join '')))
        }
        else
        {
            # Extract SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
            $SourceTagURL=$Source0 -replace "/[^/]+$", "/"
        }


        try{
            $Names = ((((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split "<tr><td") -split 'a href=') -split '>') -split "title="
            if ($Names) {
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                $Names = ($Names | foreach-object { if (!($_ | select-string -pattern '</a' -simplematch)) {$_}}) -ireplace '"',""
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.sig' -simplematch)) {$_}}
                $Names = $Names  -replace ".tar.gz",""
                $Names = $Names  -replace ".tar.bz2",""
                $Names = $Names  -replace ".tar.xz",""
                $Names = $Names  -replace ".tar.lz",""

                if ($currentTask.spec -ilike 'compat-gdbm.spec') {$replace +="gdbm-"}
                elseif ($currentTask.spec -ilike 'grub2.spec') {$replace +="grub-"}
                elseif ($currentTask.spec -ilike 'freetype2.spec') {$replace +="freetype-"}
                elseif ($currentTask.spec -ilike 'libldb.spec') {$replace +="ldb-"}
                elseif ($currentTask.spec -ilike 'libtalloc.spec') {$replace +="talloc-"}
                elseif ($currentTask.spec -ilike 'libtdb.spec') {$replace +="tdb-"}
                elseif ($currentTask.spec -ilike 'libtevent.spec') {$replace +="tevent-"}
                elseif ($currentTask.spec -ilike 'mozjs.spec') {$replace +="/pub/firefox/releases/"+$NameLatest+"/source/firefox-"; $replace +=".source"; $replace +=".asc"}
                elseif ($currentTask.spec -ilike 'mozjs60.spec') {$replace +="/pub/firefox/releases/"+$NameLatest+"esr/source/firefox-"; $replace +="esr.source"; $replace +=".asc"}
                elseif ($currentTask.spec -ilike 'nspr.spec') {$replace +="/pub/nspr/releases/v"+$NameLatest+"/src/nspr-"}
                elseif ($currentTask.spec -ilike 'nss.spec') {$replace +="/pub/security/nss/releases/NSS_"+$NameLatest+"_RTM/src/"}
                elseif ($currentTask.spec -ilike 'proto.spec') {$replace +="xproto-"}
                elseif ($currentTask.spec -ilike 'samba-client.spec') {$replace +="samba-"}
                elseif ($currentTask.spec -ilike 'wget.spec') {$Names = $Names | foreach-object { if (!($_ | select-string -pattern 'wget2-' -simplematch)) {$_}}}
                elseif ($currentTask.spec -ilike 'xorg-applications.spec') {$replace +="bdftopcf-"}
                elseif ($currentTask.spec -ilike 'xorg-fonts.spec') {$replace +="encodings-"}


                if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                # Do not add [...]replace(($replace[$i]).tolower() because later e.g. for downloading resources the exact case-sensitive match is important.
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                $Names = Clean-VersionNames $Names

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                # get name latest
                if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
            }
        }
        catch{$NameLatest=""}

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

            $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                # Write-Host "$Namelatest is higher than $version"
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                # Write-Host "$version is higher than $Namelatest"
                $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
            }
            else {
                # Write-Host "$Namelatest is equal to $version"
                $UpdateAvailable = "(same version)"
            }
         }
    }

    # Check UpdateAvailable by rubygems.org API (JSON-based, more reliable than HTML scraping)
    elseif ($Source0 -ilike '*rubygems.org*')
    {
        # Use RubyGems API for reliable version detection
        # API endpoint: https://rubygems.org/api/v1/versions/{gem_name}.json
        $gemName = $currentTask.gem_name
        if ([string]::IsNullOrEmpty($gemName)) {
            # Fallback: extract gem name from spec filename (e.g., rubygem-aws-sdk-s3.spec -> aws-sdk-s3)
            $gemName = $currentTask.spec -replace '^rubygem-', '' -replace '\.spec$', ''
        }

        $apiUrl = "https://rubygems.org/api/v1/versions/$gemName.json"

        try {
            $versions = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10 -ErrorAction Stop

            if ($versions -and $versions.Count -gt 0) {
                # Filter out prerelease versions (those with prerelease = true)
                $stableVersions = $versions | Where-Object { $_.prerelease -eq $false }

                if ($stableVersions -and $stableVersions.Count -gt 0) {
                    # Get the latest stable version (first in the list - API returns sorted by created_at desc)
                    $latestVersion = $stableVersions[0]
                    $NameLatest = $latestVersion.number

                    # Construct download URL
                    $UpdateURL = "https://rubygems.org/downloads/$gemName-$NameLatest.gem"
                    $HealthUpdateURL = urlhealth($UpdateURL)
                }
            }
        }
        catch {
            $NameLatest = ""
            Write-Warning "RubyGems API call failed for $gemName : $_"
        }

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) { [string]$version = [string]$version.version }

            $result = Compare-VersionStrings -Namelatest $NameLatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $($currentTask.spec) between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                $UpdateAvailable = "Warning: " + $currentTask.spec + " Source0 version " + $version + " is higher than detected latest version " + $NameLatest + " ."
            }
            else {
                $UpdateAvailable = "(same version)"
            }
        }
    }

    # Check UpdateAvailable by sourceforge tags detection
    elseif ($Source0 -ilike '*sourceforge.net*')
    {
        # Autogenerated SourceTagURL from Source0
        $SourceTagURLArray=($Source0).replace("http://","")
        $SourceTagURLArray=($SourceTagURLArray).replace("https://","")
        $SourceTagURLArray=($SourceTagURLArray).replace("sourceforge.net/","")
        $SourceTagURLArray=($SourceTagURLArray).replace("downloads.project/","")
        $SourceTagURLArray=($SourceTagURLArray).replace("projects/","")
        $SourceTagURLArray=($SourceTagURLArray).replace("prdownloads.","")
        $SourceTagURLArray=($SourceTagURLArray).replace("downloads.","")
        $SourceTagURLArray=($SourceTagURLArray).replace("download.","")
        $SourceTagURLArray=($SourceTagURLArray).replace("gkernel/files/","")
        $SourceTagURLArray=($SourceTagURLArray).replace("sourceforge/","")

        $tmpName=($SourceTagURLArray -split "/")[0]
        $SourceTagURL="https://sourceforge.net/projects/$tmpName/files/$tmpName"
        if ($currentTask.spec -ilike 'docbook-xsl.spec') {$SourceTagURL="https://sourceforge.net/projects/docbook/files/docbook-xsl"}
        elseif ($currentTask.spec -ilike 'expect.spec') {$SourceTagURL="https://sourceforge.net/projects/expect/files/Expect"} #uppercase E
        elseif ($currentTask.spec -ilike 'fakeroot-ng.spec') {$SourceTagURL="https://sourceforge.net/projects/fakerootng/files/fakeroot-ng"}
        elseif ($currentTask.spec -ilike 'libpng.spec') {$SourceTagURL="https://sourceforge.net/projects/libpng/files/libpng16"}
        elseif  ($currentTask.spec -ilike 'nfs-utils.spec') {$SourceTagURL="https://sourceforge.net/projects/nfs/files/nfs-utils"}
        elseif  ($currentTask.spec -ilike 'openipmi.spec') {$SourceTagURL="https://sourceforge.net/projects/openipmi/files/OpenIPMI%202.0%20Library/"}
        elseif  ($currentTask.spec -ilike 'procps-ng.spec') {$SourceTagURL="http://sourceforge.net/projects/procps-ng/files/Production/"}
        elseif ($currentTask.spec -ilike 'tcl.spec') {$SourceTagURL="https://sourceforge.net/projects/tcl/files/Tcl"}
        elseif ($currentTask.spec -ilike 'unzip.spec')
        {
            $SourceTagURL='https://sourceforge.net/projects/infozip/files/UnZip%206.x%20%28latest%29/UnZip%206.0/'
            if ($version -eq "6.0") {$version="60"}
        }
        elseif  ($currentTask.spec -ilike 'xmlstarlet.spec') {$SourceTagURL='https://sourceforge.net/projects/xmlstar/files/xmlstarlet'}
        elseif  ($currentTask.spec -ilike 'zip.spec')
        {
            $SourceTagURL='https://sourceforge.net/projects/infozip/files/Zip%203.x%20%28latest%29/3.0/'
            if ($version -eq "3.0") {$version="30"}
            $replace += "zip30.zip"
        }
        try{
            $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop) -split 'net.sf.files = {') -split "}};")[1] -split '{'
            if ($Names) {
                $Names = (($Names -split ',') | foreach-object { if($_ | select-string -pattern '"name":' -simplematch) {$_ -ireplace '"name":',""}}) -ireplace '"',""

                if ($currentTask.spec -ilike "backward-cpp.spec") {$replace +="v"}
                elseif ($currentTask.spec -ilike "e2fsprogs.spec") {$replace +="v"}
                elseif ($currentTask.spec -ilike "libusb.spec")
                {
                    $Names = $Names  -replace "libusb-compat-",""
                    $Names = $Names  -replace "libusb-",""
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                    if ($Names -ilike '*.*')
                    {
                        $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                    }
                    else
                    {
                        try{$NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()}catch{}
                    }
                    $SourceTagURL="https://sourceforge.net/projects/libusb/files/libusb-"+$NameLatest
                    $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop) -split 'net.sf.files = {') -split "}};")[1] -split '{'
                    $Names = (($Names -split ',') | foreach-object { if ($_ | select-string -pattern '"name":' -simplematch) {$_ -ireplace '"name":',""}}) -ireplace '"',""
                }
                elseif ($currentTask.spec -ilike 'tboot.spec')
                {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2007' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2008' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2009' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2010' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2011' -simplematch)) {$_}}
                }

                $Names = $Names  -replace ".tar.gz",""
                $Names = $Names  -replace ".tar.bz2",""
                $Names = $Names  -replace ".tar.xz",""
                $Names = $Names  -replace ".tar.lz",""

                if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                $replace +="ver"

                # Do not add [...]replace(($replace[$i]).tolower() because later e.g. for downloading resources the exact case-sensitive match is important.
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                $Names = Clean-VersionNames $Names

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                # get name latest
                if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
            }
        }
        catch{$NameLatest=""}

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

            $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                # Write-Host "$Namelatest is higher than $version"
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                # Write-Host "$version is higher than $Namelatest"
                $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
            }
            else {
                # Write-Host "$Namelatest is equal to $version"
                $UpdateAvailable = "(same version)"
            }
         }
    }

    elseif ($Source0 -ilike '*https://pagure.io/*')
    {
        if ($currentTask.spec -ilike 'python-daemon.spec') {$SourceTagURL="https://pagure.io/python-daemon/releases"}

        if ($SourceTagURL -ne "")
        {
            try
            {
                if ([string]::IsNullOrEmpty($Names -join ''))
                {
                    $tmpName=$currentTask.Name
                    $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split '-release/') -split '.tar.gz"'
                }
                if ($Names) {

                    if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                    $replace += $currentTask.Name+"."
                    $replace += $currentTask.Name+"-"
                    $replace += $currentTask.Name+"_"
                    $replace +="ver"

                    # Do not add [...]replace(($replace[$i]).tolower() because later e.g. for downloading resources the exact case-sensitive match is important.
                    foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                    $Names = Clean-VersionNames $Names

                    $Names = $Names  -replace "v",""
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                    if ($currentTask.spec -ilike 'atk.spec')
                    {
                        $Names = $Names | foreach-object {$_.tolower().replace("_",".")}
                    }

                    # get name latest
                    if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
                }
            }
            catch{$NameLatest=""}

            if ($NameLatest -ne "")
            {
                if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

                $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

                if ($null -eq $result) {
                    Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
                }
                elseif ($result -gt 0) {
                    # Write-Host "$Namelatest is higher than $version"
                    $UpdateAvailable = $NameLatest
                }
                elseif ($result -lt 0) {
                    # Write-Host "$version is higher than $Namelatest"
                    $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
                }
                else {
                    # Write-Host "$Namelatest is equal to $version"
                    $UpdateAvailable = "(same version)"
                }
            }
        }
    }
    # Check UpdateAvailable by freedesktop tags detection
    elseif (($Source0 -ilike '*freedesktop.org*') -or ($Source0 -ilike '*https://gitlab.*'))
    {
        # Hardcoded SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
        if ($currentTask.spec -ilike 'asciidoc3.spec') {$SourceTagURL="https://gitlab.com/asciidoc3/asciidoc3.git"}
        elseif ($currentTask.spec -ilike 'atk.spec') {$SourceTagURL="https://gitlab.gnome.org/Archive/atk.git"}
        elseif ($currentTask.spec -ilike 'cairo.spec') {$SourceTagURL="https://gitlab.freedesktop.org/cairo/cairo.git"}
        elseif ($currentTask.spec -ilike 'dbus.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus.git"}
        elseif ($currentTask.spec -ilike 'dbus-glib.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus-glib.git"}
        elseif ($currentTask.spec -ilike 'dbus-python.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus-python.git"}
        elseif ($currentTask.spec -ilike 'fontconfig.spec') {$SourceTagURL="https://gitlab.freedesktop.org/fontconfig/fontconfig.git"}
        elseif ($currentTask.spec -ilike 'harfbuzz.spec') {$SourceTagURL="https://gitlab.freedesktop.org/harfbuzz/harfbuzz.git"}
        elseif ($currentTask.spec -ilike 'gst-plugins-bad.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gst-plugins-bad.git"}
        elseif ($currentTask.spec -ilike 'gstreamer-plugins-base.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gst-plugins-base.git"; $replace +="gst-plugins-base-"}
        elseif ($currentTask.spec -ilike 'libdrm.spec') {$SourceTagURL="https://gitlab.freedesktop.org/drm/libdrm.git"}
        elseif ($currentTask.spec -ilike 'libqmi.spec') {$SourceTagURL="https://gitlab.freedesktop.org/libqmi/libqmi.git"}
        elseif ($currentTask.spec -ilike 'libxcb.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xcb/libxcb.git"}
        elseif ($currentTask.spec -ilike 'ModemManager.spec') {$SourceTagURL="https://gitlab.freedesktop.org/modemmanager/modemmanager.git"}
        elseif ($currentTask.spec -ilike 'libmbim.spec') {$SourceTagURL="https://gitlab.freedesktop.org/libmbim/libmbim.git"}
        elseif ($currentTask.spec -ilike 'gstreamer.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gstreamer.git"}
        elseif ($currentTask.spec -ilike 'ipcalc.spec') {$SourceTagURL="https://gitlab.com/ipcalc/ipcalc.git"}
        elseif ($currentTask.spec -ilike 'libslirp.spec') {$SourceTagURL="https://gitlab.freedesktop.org/slirp/libslirp.git"}
        elseif ($currentTask.spec -ilike 'libtiff.spec') {$SourceTagURL="https://gitlab.com/libtiff/libtiff.git"}
        elseif ($currentTask.spec -ilike 'libx11.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libx11.git"}
        elseif ($currentTask.spec -ilike 'libxinerama.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libxinerama.git"}
        elseif ($currentTask.spec -ilike 'man-db.spec') {$SourceTagURL="https://gitlab.com/man-db/man-db.git"}
        elseif ($currentTask.spec -ilike 'mesa.spec') {$SourceTagURL="https://gitlab.freedesktop.org/mesa/mesa.git"}
        elseif ($currentTask.spec -ilike 'mm-common.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/mm-common.git"}
        elseif ($currentTask.spec -ilike 'modemmanager.spec') {$SourceTagURL="https://gitlab.freedesktop.org/modemmanager/modemmanager.git"; $replace+="-dev"}
        elseif ($currentTask.spec -ilike 'pixman.spec') {$SourceTagURL="https://gitlab.freedesktop.org/pixman/pixman.git"}
        elseif ($currentTask.spec -ilike 'pkg-config.spec') {$SourceTagURL="https://gitlab.freedesktop.org/pkg-config/pkg-config.git"}
        elseif ($currentTask.spec -ilike 'polkit.spec') {$SourceTagURL="https://gitlab.freedesktop.org/polkit/polkit.git"}
        elseif ($currentTask.spec -ilike 'psmisc.spec') {$SourceTagURL="https://gitlab.com/psmisc/psmisc.git"}
        elseif ($currentTask.spec -ilike 'pygobject.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/pygobject.git"}
        elseif ($currentTask.spec -ilike 'python-M2Crypto.spec') {$SourceTagURL="https://gitlab.com/m2crypto/m2crypto.git"}
        elseif ($currentTask.spec -ilike 'python-pygobject.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/pygobject/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'shared-mime-info.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xdg/shared-mime-info.git"}
        elseif ($currentTask.spec -ilike 'wayland.spec') {$SourceTagURL="https://gitlab.freedesktop.org/wayland/wayland.git"}
        elseif ($currentTask.spec -ilike 'wayland-protocols.spec') {$SourceTagURL="https://gitlab.freedesktop.org/wayland/wayland-protocols.git"}
        elseif ($currentTask.spec -ilike 'libldb.spec') {$SourceTagURL="https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=ldb*&format=atom"; $replace+="ldb-"}
        elseif ($currentTask.spec -ilike 'libtalloc.spec') {$SourceTagURL="https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=talloc*&format=atom"; $replace+="talloc-"}
        elseif ($currentTask.spec -ilike 'libtdb.spec') {$SourceTagURL="https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=tdb*&format=atom"; $replace+="tdb-"}
        elseif ($currentTask.spec -ilike 'libtevent.spec') {$SourceTagURL="https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=tevent*&format=atom"; $replace+="tevent-"}
        elseif ($currentTask.spec -ilike 'samba-client.spec') {$SourceTagURL="https://gitlab.com/samba-team/devel/samba/-/tags?sort=updated_desc&search=samba*&format=atom"; $replace+="samba-"}
        elseif ($currentTask.spec -ilike 'xcb-proto.spec') {$SourceTagURL="https://xcb.freedesktop.org/dist/"}

        # Data Scraping Proof of Work
        if ($SourceTagURL -like "*.git")
        {
            if ($SourceTagURL -match "/([^/]+)\.git$") {
                $repoName = $Matches[1]
                Push-Location
                try {
                    $ClonePath=[System.String](join-path -path (join-path -path $SourcePath -childpath $photonDir) -childpath "clones")
                    if (!(Test-Path $ClonePath)) {New-Item $ClonePath -ItemType Directory}
                    # Push the current directory to the stack
                    $SourceClonePath=[System.String](join-path -path $ClonePath -childpath $repoName)
                    $cloneAttempt = 0
                    $maxCloneAttempts = 2
                    while ($cloneAttempt -lt $maxCloneAttempts) {
                        $cloneAttempt++
                        if (!(Test-Path $SourceClonePath)) {
                            Set-Location -Path $ClonePath -ErrorAction Stop
                            # Clone the repository
                            try {
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "clone $SourceTagURL -b $gitBranch $repoName" -WorkingDirectory $ClonePath | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "clone $SourceTagURL $repoName" -WorkingDirectory $ClonePath | Out-Null
                                    # the very first time, you receive the origin names and not the version names. From the 2nd run, all is fine.
                                    if (Test-Path $SourceClonePath) {
                                        Set-Location $SourceClonePath
                                        if (!([string]::IsNullOrEmpty($gitBranch))) {
                                            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags origin $gitBranch" -WorkingDirectory $SourceClonePath | Out-Null
                                        } else {
                                            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $SourceClonePath | Out-Null
                                        }
                                    } else {
                                        Write-Warning "Clone directory not created for $repoName - clone may have failed silently"
                                    }
                                }
                            }
                            catch {
                                Write-Warning "Git clone failed for $repoName : $_"
                            }
                        }
                        else {
                            # Navigate to the repository directory
                            Set-Location -Path $SourceClonePath -ErrorAction Stop # --git-dir [...] fetch does not work correctly
                            try {
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "fetch --prune --prune-tags --tags origin $gitBranch" -WorkingDirectory $SourceClonePath | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $SourceClonePath | Out-Null
                                }
                            }
                            catch {
                                Write-Warning "Git fetch failed for $repoName : $_"
                            }
                        }
                        # Run git tag -l and collect output in an array
                        if ((Test-Path $SourceClonePath) -and (Test-Path (Join-Path $SourceClonePath ".git"))) {
                            if ("" -eq $customRegex) {$Names = git tag -l | Where-Object { $_ -match "^$([regex]::Escape($repoName))-" } | ForEach-Object { $_.Trim()}}
                            else {$Names = git tag -l | ForEach-Object { $_.Trim() }}
                            $urlhealth="200"
                            break
                        } else {
                            if ($cloneAttempt -lt $maxCloneAttempts) {
                                Write-Warning "No valid git repository at $SourceClonePath for $repoName - deleting and retrying (attempt $cloneAttempt of $maxCloneAttempts)"
                                if (Test-Path $SourceClonePath) { Remove-Item -Path $SourceClonePath -Recurse -Force -ErrorAction SilentlyContinue }
                            } else {
                                Write-Warning "No valid git repository at $SourceClonePath for $repoName after $maxCloneAttempts attempts - skipping tag listing"
                                $Names = @()
                            }
                        }
                    }
                } catch {
                    Write-Warning "Git operation failed for $repoName : $_"
                }
                finally {
                    pop-location
                }
            }
        }
        if (($SourceTagURL -ne "") -and (($null -eq $Names) -or ("" -eq $Names)))
        {
            # Old code
            # Hardcoded SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
            if ($currentTask.spec -ilike 'asciidoc3.spec') {$SourceTagURL="https://gitlab.com/asciidoc3/asciidoc3/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'atk.spec') {$SourceTagURL="https://gitlab.gnome.org/Archive/atk/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'cairo.spec') {$SourceTagURL="https://gitlab.freedesktop.org/cairo/cairo/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'dbus.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'dbus-glib.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus-glib/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'dbus-python.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus-python/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'fontconfig.spec') {$SourceTagURL="https://gitlab.freedesktop.org/fontconfig/fontconfig/-/tags?format=atom"}
            elseif (($currentTask.spec -ilike 'harfbuzz.spec') -or ($currentTask.spec -ilike 'gst-plugins-bad.spec') -or ($currentTask.spec -ilike 'gstreamer-plugins-base.spec') -or ($currentTask.spec -ilike 'libdrm.spec') -or ($currentTask.spec -ilike 'libqmi.spec') -or ($currentTask.spec -ilike 'libxcb.spec') -or ($currentTask.spec -ilike 'ModemManager.spec') -or ($currentTask.spec -ilike 'xcb-proto.spec' -or ($currentTask.spec -ilike 'libmbim.spec'))) # ausnahmen
            {
                if ($currentTask.spec -ilike 'harfbuzz.spec') {$SourceTagURL="https://www.freedesktop.org/software/harfbuzz/release/"}
                elseif ($currentTask.spec -ilike 'gst-plugins-bad.spec') {$SourceTagURL="https://gstreamer.freedesktop.org/src/gst-plugins-bad"}
                elseif ($currentTask.spec -ilike 'gstreamer-plugins-base.spec') {$SourceTagURL="https://gstreamer.freedesktop.org/src/gst-plugins-base"; $replace +="gst-plugins-base-"}
                elseif ($currentTask.spec -ilike 'libdrm.spec') {$SourceTagURL="https://dri.freedesktop.org/libdrm/"}
                elseif ($currentTask.spec -ilike 'libqmi.spec') {$SourceTagURL="https://www.freedesktop.org/software/libqmi/"}
                elseif ($currentTask.spec -ilike 'libxcb.spec') {$SourceTagURL="http://xcb.freedesktop.org/dist/"}
                elseif ($currentTask.spec -ilike 'ModemManager.spec') {$SourceTagURL="https://www.freedesktop.org/software/ModemManager/"}
                elseif ($currentTask.spec -ilike 'xcb-proto.spec') {$SourceTagURL="http://xcb.freedesktop.org/dist/"}
                elseif ($currentTask.spec -ilike 'libmbim.spec') {$SourceTagURL="https://www.freedesktop.org/software/libmbim/"}
                $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -headers @{Authorization = "Bearer $accessToken"} -ErrorAction Stop) -split "<tr><td") -split 'a href=') -split '>'
                if ($Names) {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'commit' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern "'" -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '"' -simplematch)) {$_}}
                    $Names = $Names -ireplace '</a',""
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.sig' -simplematch)) {$_}}
                    $Names = $Names  -replace ".tar.gz",""
                    $Names = $Names  -replace ".tar.bz2",""
                    $Names = $Names  -replace ".tar.xz",""
                    $Names = $Names  -replace ".tar.lz",""
                }
            }
            elseif ($currentTask.spec -ilike 'gstreamer.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gstreamer/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'ipcalc.spec') {$SourceTagURL="https://gitlab.com/ipcalc/ipcalc/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'libslirp.spec') {$SourceTagURL="https://gitlab.freedesktop.org/slirp/libslirp/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'libtiff.spec') {$SourceTagURL="https://gitlab.com/libtiff/libtiff/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'libx11.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libx11/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'libxinerama.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'man-db.spec') {$SourceTagURL="https://gitlab.com/man-db/man-db/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'mesa.spec') {$SourceTagURL="https://gitlab.freedesktop.org/mesa/mesa/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'mm-common.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/mm-common/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'modemmanager.spec') {$SourceTagURL="https://gitlab.freedesktop.org/modemmanager/modemmanager/-/tags?format=atom"; $replace+="-dev"}
            elseif ($currentTask.spec -ilike 'pixman.spec') {$SourceTagURL="https://gitlab.freedesktop.org/pixman/pixman/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'pkg-config.spec') {$SourceTagURL="https://gitlab.freedesktop.org/pkg-config/pkg-config/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'polkit.spec') {$SourceTagURL="https://gitlab.freedesktop.org/polkit/polkit/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'psmisc.spec') {$SourceTagURL="https://gitlab.com/psmisc/psmisc/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'pygobject.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/pygobject/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'python-M2Crypto.spec') {$SourceTagURL="https://gitlab.com/m2crypto/m2crypto/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'python-pygobject.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/pygobject/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'shared-mime-info.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xdg/shared-mime-info/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'wayland.spec') {$SourceTagURL="https://gitlab.freedesktop.org/wayland/wayland/-/tags?format=atom"}
            elseif ($currentTask.spec -ilike 'wayland-protocols.spec') {$SourceTagURL="https://gitlab.freedesktop.org/wayland/wayland-protocols/-/tags?format=atom"}
            try {
                if (!($Names))
                {
                    $Names = invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop
                    $Names = $Names.title
                }
            }catch {}
        }

        try {
            if (($SourceTagURL -ne "") -and ($null -ne $Names)) {

                if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                $Names = Clean-VersionNames $Names

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                # post check
                if ($currentTask.spec -ilike 'atk.spec')
                {
                    $Names = $Names | foreach-object {$_.tolower().replace("_",".")}
                }

                # get name latest
                if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
            }
        }catch{$NameLatest=""}

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

            $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                # Write-Host "$Namelatest is higher than $version"
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                # Write-Host "$version is higher than $Namelatest"
                $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
            }
            else {
                # Write-Host "$Namelatest is equal to $version"
                $UpdateAvailable = "(same version)"
            }
         }
    }

    # Check UpdateAvailable by cpan tags detection
    elseif (($Source0 -ilike '*cpan.metacpan.org/authors*') -or ($Source0 -ilike '*search.cpan.org/CPAN/authors*') -or ($Source0 -ilike '*cpan.org/authors*'))
    {
        # Extract SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
        $SourceTagURL=$Source0 -replace "/[^/]+$", "/"

        if ($SourceTagURL -ne "")
        {
            try{
                if ([string]::IsNullOrEmpty($Names -join ''))
                {
                    $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split 'a href=') -split '>'
                }

                if ($Names) {
                    $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                    $Names = $Names -replace '</a'

                    $Names = $Names  -replace ".tar.gz",""
                    $Names = $Names  -replace ".tar.bz2",""
                    $Names = $Names  -replace ".tar.xz",""
                    $Names = $Names  -replace ".tar.lz",""

                    if ($currentTask.spec -ilike '*perl-*.spec') {
                        $replace += [system.string]::concat(($currentTask.Name -ireplace "perl-",""),"-")
                        $replace +=  [system.string]::concat(($currentTask.Name -ireplace "perl-",""),"-perl-")
                    }

                    if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                    $replace += $currentTask.Name+"."
                    $replace += $currentTask.Name+"-"
                    $replace += $currentTask.Name+"_"
                    $replace +="ver"

                    foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                    $Names = Clean-VersionNames $Names

                    $Names = $Names  -replace "v",""
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                    # get name latest
                    if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
                }
            }
            catch{$NameLatest=""}

            if ($NameLatest -ne "")
            {
                if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

                $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

                if ($null -eq $result) {
                    Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
                }
                elseif ($result -gt 0) {
                    # Write-Host "$Namelatest is higher than $version"
                    $UpdateAvailable = $NameLatest
                }
                elseif ($result -lt 0) {
                    # Write-Host "$version is higher than $Namelatest"
                    $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
                }
                else {
                    # Write-Host "$Namelatest is equal to $version"
                    $UpdateAvailable = "(same version)"
                }
            }
        }
    }

    # Check UpdateAvailable by kernel.org tags detection
    elseif ($Source0 -ilike '*kernel.org*')
    {
        $customRegex=""
        # Hardcoded SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
        if ($currentTask.spec -ilike 'autofs.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/storage/autofs/autofs.git"}
        elseif ($currentTask.spec -ilike 'blktrace.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/axboe/blktrace.git"; $branch="master"}
        elseif ($currentTask.spec -ilike 'bluez.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/bluetooth/bluez.git";$customRegex="bluez"} #ausnahme
        elseif ($currentTask.spec -ilike 'bridge-utils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/network/bridge/bridge-utils.git"}
        elseif ($currentTask.spec -ilike 'dtc.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/dtc/dtc.git";}
        elseif ($currentTask.spec -ilike 'ethtool.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/network/ethtool/ethtool.git"}
        elseif ($currentTask.spec -ilike 'fio.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git"}
        elseif ($currentTask.spec -ilike 'git.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/git/git.git"}
        elseif ($currentTask.spec -ilike 'i2c-tools.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git"}
        elseif ($currentTask.spec -ilike 'iproute2.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/network/iproute2/iproute2.git";$customRegex="iproute2"}
        elseif ($currentTask.spec -ilike 'ipvsadm.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/kernel/ipvsadm/ipvsadm.git/"}
        elseif ($currentTask.spec -ilike 'kexec-tools.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git"}
        elseif ($currentTask.spec -ilike 'keyutils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git"}
        elseif ($currentTask.spec -ilike 'kmod.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git";;$customRegex="kmod"}
        elseif ($currentTask.spec -ilike 'libcap.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git"}
        elseif ($currentTask.spec -ilike 'libtraceevent.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git"}
        elseif ($currentTask.spec -ilike 'libtracefs.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git"}
        elseif (($currentTask.spec -ilike 'linux-aws.spec') -or ($currentTask.spec -ilike 'linux-esx.spec') -or ($currentTask.spec -ilike 'linux-rt.spec') -or ($currentTask.spec -ilike 'linux-secure.spec') -or ($currentTask.spec -ilike 'linux.spec') -or ($currentTask.spec -ilike 'linux-6.1.spec') -or ($currentTask.spec -ilike 'linux-api-headers.spec'))
        {
            if ($outputfile -ilike '*-3.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v4.x"; $replace +="linux-";$customRegex="linux"}
            elseif ($outputfile -ilike '*-4.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v5.x"; $replace +="linux-";$customRegex="linux"}
            elseif ($outputfile -ilike '*-5.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v6.x"; $replace +="linux-";$customRegex="linux"}
            elseif ($outputfile -ilike '*-6.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v6.x"; $replace +="linux-";$customRegex="linux"}
            elseif ($outputfile -ilike '*-common_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v6.x"; $replace +="linux-";$customRegex="linux"}
            elseif ($outputfile -ilike '*-master_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v6.x"; $replace +="linux-";$customRegex="linux"}
            elseif ($outputfile -ilike '*-dev_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v6.x"; $replace +="linux-";$customRegex="linux"}
        }
        elseif ($currentTask.spec -ilike 'linux-firmware.spec') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/firmware"}
        elseif ($currentTask.spec -ilike 'man-pages.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git"}
        elseif ($currentTask.spec -ilike 'pciutils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/pciutils/pciutils.git"}
        elseif ($currentTask.spec -ilike 'rt-tests.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git"}
        elseif ($currentTask.spec -ilike 'stalld.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/stalld/stalld.git"}
        elseif ($currentTask.spec -ilike 'syslinux.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/boot/syslinux/syslinux.git"}
        elseif ($currentTask.spec -ilike 'trace-cmd.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/trace-cmd/trace-cmd.git"; $replace +="v"}
        elseif ($currentTask.spec -ilike 'usbutils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/gregkh/usbutils.git"}
        elseif ($currentTask.spec -ilike 'xfsprogs.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/fs/xfs/xfsprogs-dev.git"; $replace +="xfsprogs-dev-"; $replace +="v";;$customRegex="xfsprogs"}
        else
        {
            if ($Source0) {
                $SourceTagURL=(split-path $Source0 -Parent).Replace([IO.Path]::DirectorySeparatorChar,"/")
            }
        }

        # Data Scraping Proof of Work
        if ($SourceTagURL -like "*.git")
        {
            if ($SourceTagURL -match "/([^/]+)\.git$") {
                $repoName = $Matches[1]
                Push-Location
                try {
                    $ClonePath=[System.String](join-path -path (join-path -path $SourcePath -childpath $photonDir) -childpath "clones")
                    if (!(Test-Path $ClonePath)) {New-Item $ClonePath -ItemType Directory}
                    # Push the current directory to the stack
                    $SourceClonePath=[System.String](join-path -path $ClonePath -childpath $repoName)
                    $cloneAttempt = 0
                    $maxCloneAttempts = 2
                    while ($cloneAttempt -lt $maxCloneAttempts) {
                        $cloneAttempt++
                        if (!(Test-Path $SourceClonePath)) {
                            Set-Location -Path $ClonePath -ErrorAction Stop
                            # Clone the repository
                            try {
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "clone $SourceTagURL -b $gitBranch $repoName" -WorkingDirectory $ClonePath | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "clone $SourceTagURL $repoName" -WorkingDirectory $ClonePath | Out-Null
                                    # the very first time, you receive the origin names and not the version names. From the 2nd run, all is fine.
                                    if (Test-Path $SourceClonePath) {
                                        Set-Location -Path $SourceClonePath -ErrorAction Stop
                                        if (!([string]::IsNullOrEmpty($gitBranch))) {
                                            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags origin $gitBranch" -WorkingDirectory $SourceClonePath | Out-Null
                                        } else {
                                            Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $SourceClonePath | Out-Null
                                        }
                                    } else {
                                        Write-Warning "Clone directory not created for $repoName - clone may have failed silently"
                                    }
                                }
                            }
                            catch {
                                Write-Warning "Git clone failed for $repoName : $_"
                            }
                        }
                        else {
                            # Navigate to the repository directory
                            Set-Location -Path $SourceClonePath -ErrorAction Stop # --git-dir [...] fetch does not work correctly
                            try {
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "fetch --prune --prune-tags --tags origin $gitBranch" -WorkingDirectory $SourceClonePath | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "fetch --prune --prune-tags --tags" -WorkingDirectory $SourceClonePath | Out-Null
                                }
                            }
                            catch {
                                Write-Warning "Git fetch failed for $repoName : $_"
                            }
                        }
                        # Run git tag -l and collect output in an array
                        if ((Test-Path $SourceClonePath) -and (Test-Path (Join-Path $SourceClonePath ".git"))) {
                            Set-Location -Path $SourceClonePath -ErrorAction SilentlyContinue
                            if ("" -eq $customRegex) {$Names = git tag -l | Where-Object { $_ -match "^$([regex]::Escape($repoName))-" } | ForEach-Object { $_.Trim()}}
                            else {$Names = git tag -l | ForEach-Object { $_.Trim() }}
                            $urlhealth="200"
                            break
                        } else {
                            if ($cloneAttempt -lt $maxCloneAttempts) {
                                Write-Warning "No valid git repository at $SourceClonePath for $repoName - deleting and retrying (attempt $cloneAttempt of $maxCloneAttempts)"
                                if (Test-Path $SourceClonePath) { Remove-Item -Path $SourceClonePath -Recurse -Force -ErrorAction SilentlyContinue }
                            } else {
                                Write-Warning "No valid git repository at $SourceClonePath for $repoName after $maxCloneAttempts attempts - skipping tag listing"
                                $Names = @()
                            }
                        }
                    }
                } catch {
                    Write-Warning "Git operation failed for $repoName : $_"
                }
                finally {
                    pop-location
                }
            }
        }
        if (($SourceTagURL -ne "") -and (($null -eq $Names) -or ("" -eq $Names)))
        {
            try{
                $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split "<tr><td") -split 'a href=') -split '>'
                if ($Names) {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'commit' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern "'" -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '"' -simplematch)) {$_}}
                    $Names = $Names -ireplace '</a',""
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.sig' -simplematch)) {$_}}
                    $Names = $Names  -replace ".tar.gz",""
                    $Names = $Names  -replace ".tar.bz2",""
                    $Names = $Names  -replace ".tar.xz",""
                    $Names = $Names  -replace ".tar.lz",""
                    $urlhealth="200"
                }
            } catch {
                # Silently ignore web request failures - URL may be temporarily unavailable
            }
        }
        try {
            if (($SourceTagURL -ne "") -and ($null -ne $Names)) {

                if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                $Names = Clean-VersionNames $Names

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                # post check
                if (($currentTask.spec -ilike 'linux-aws.spec') -or ($currentTask.spec -ilike 'linux-esx.spec') -or ($currentTask.spec -ilike 'linux-rt.spec') -or ($currentTask.spec -ilike 'linux-secure.spec') -or ($currentTask.spec -ilike 'linux.spec') -or ($currentTask.spec -ilike 'linux-api-headers.spec'))
                {
                    if ($outputfile -ilike '*-3.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '4.19.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-4.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '5.10.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-5.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '6.1.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-6.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '6.1.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-common_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '6.12.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-master_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '6.1.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-dev_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '6.1.' -simplematch) {$_}}}
                }
                if ($currentTask.spec -ilike 'kexec-tools.spec')
                {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2006' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2007' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2008' -simplematch)) {$_}}
                }
                if ($currentTask.spec -ilike 'libcap.spec')
                {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2006' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '2007' -simplematch)) {$_}}
                }

                # get name latest
                if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}
            }
        }catch{$NameLatest=""}

        if ($NameLatest -ne "")
        {
            if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

            $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

            if ($null -eq $result) {
                Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
            }
            elseif ($result -gt 0) {
                # Write-Host "$Namelatest is higher than $version"
                $UpdateAvailable = $NameLatest
            }
            elseif ($result -lt 0) {
                # Write-Host "$version is higher than $Namelatest"
                $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
            }
            else {
                # Write-Host "$Namelatest is equal to $version"
                $UpdateAvailable = "(same version)"
            }
        }
    }
    # all other types
    elseif (($Source0 -and ((urlhealth((split-path $Source0 -Parent).Replace([IO.Path]::DirectorySeparatorChar,"/"))) -eq "200")) -or `
    ($currentTask.spec -ilike "apparmor.spec") -or `
    ($currentTask.spec -ilike "bzr.spec") -or `
    ($currentTask.spec -ilike "chrpath.spec") -or `
    ($currentTask.spec -ilike "conntrack-tools.spec") -or `
    ($currentTask.spec -ilike "ebtables.specconntrack-tools.spec") -or `
    ($currentTask.spec -ilike "eventlog.spec") -or `
    ($currentTask.spec -ilike "intltool.spec") -or `
    ($currentTask.spec -ilike "iotop.spec") -or `
    ($currentTask.spec -ilike "ipset.spec") -or `
    ($currentTask.spec -ilike "iptables.spec") -or `
    ($currentTask.spec -ilike "itstool.spec") -or `
    ($currentTask.spec -ilike "json-c.spec") -or `
    ($currentTask.spec -ilike "js.spec") -or `
    ($currentTask.spec -ilike "lasso.spec") -or `
    ($currentTask.spec -ilike "libmnl.spec") -or `
    ($currentTask.spec -ilike "libmetalink.spec") -or `
    ($currentTask.spec -ilike "libnetfilter_conntrack.spec") -or `
    ($currentTask.spec -ilike "libnetfilter_cthelper.spec") -or `
    ($currentTask.spec -ilike "libnetfilter_cttimeout.spec") -or `
    ($currentTask.spec -ilike "libnetfilter_queue.spec") -or `
    ($currentTask.spec -ilike "libnfnetlink.spec") -or `
    ($currentTask.spec -ilike "libnftnl.spec") -or `
    ($currentTask.spec -ilike "libteam.spec") -or `
    ($currentTask.spec -ilike "nftables.spec") -or `
    ($currentTask.spec -ilike "openvswitch.spec") -or `
    ($currentTask.spec -ilike "python-pbr.spec") -or `
    ($currentTask.spec -ilike "wireguard-tools.spec"))
    {
        if ($Source0) {
            $SourceTagURL=(split-path $Source0 -Parent).Replace([IO.Path]::DirectorySeparatorChar,"/")
        }

        if ($currentTask.spec -ilike "chrpath.spec") {$SourceTagURL="https://codeberg.org/pere/chrpath/tags"}
        if ($currentTask.spec -ilike "apparmor.spec") {$SourceTagURL="https://launchpad.net/apparmor/+download"}
        if ($currentTask.spec -ilike "bzr.spec") {$SourceTagURL="https://launchpad.net/bzr/+download"}
        if ($currentTask.spec -ilike "intltool.spec") {$SourceTagURL="https://launchpad.net/intltool/+download"}
        if ($currentTask.spec -ilike "ipset.spec") {$SourceTagURL="https://ipset.netfilter.org/install.html"}
        if ($currentTask.spec -ilike "itstool.spec") {$SourceTagURL="https://itstool.org/download.html"}
        if ($currentTask.spec -ilike "js.spec") {$SourceTagURL="https://archive.mozilla.org/pub/js/"}
        if ($currentTask.spec -ilike "json-c.spec") {$SourceTagURL="https://s3.amazonaws.com/json-c_releases/"}
        if ($currentTask.spec -ilike "openvswitch.spec") {$SourceTagURL="https://www.openvswitch.org/download"}
        if ($currentTask.spec -ilike "python-pbr.spec") {$SourceTagURL="https://opendev.org/openstack/pbr/tags"}
        if ($currentTask.spec -ilike "xmlsec1.spec") {$SourceTagURL="https://www.aleksey.com/xmlsec/download/"}
        if ($currentTask.spec -ilike "wireguard-tools.spec") {$SourceTagURL="https://git.zx2c4.com/wireguard-tools/refs/tags"}

        try{ $Names = ((((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -ErrorAction Stop) -split "<tr><td") -split 'a href=') -split '>') -split "title=" }
        catch
        {
            try
            {
                $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36"
                $Names = Invoke-WebRequest -UseBasicParsing -Uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop `
                -WebSession $session `
                -Headers @{
                "Accept"="text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                    "Accept-Encoding"="gzip, deflate, br"
                    "Accept-Language"="en-US,en;q=0.9"
                    "Cache-Control"="max-age=0"
                    "Sec-Fetch-Dest"="document"
                    "Sec-Fetch-Mode"="navigate"
                    "Sec-Fetch-Site"="none"
                    "Sec-Fetch-User"="?1"
                    "Upgrade-Insecure-Requests"="1"
                    "sec-ch-ua"="`"Google Chrome`";v=`"113`", `"Chromium`";v=`"113`", `"Not-A.Brand`";v=`"24`""
                    "sec-ch-ua-mobile"="?0"
                    "sec-ch-ua-platform"="`"Windows`""
                }
                $Names = $Names.Links.href
            }
            catch{}
        }

        if ($Names) {
            # urlhealth must have been successful
            $urlhealth = "200"
            if ($currentTask.spec -ilike "docbook-xml.spec")
            {
                $SourceTagURL="https://docbook.org/xml/"
                $objtmp=@()
                $objtmp = (invoke-webrequest -UseBasicParsing -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop).Links.href
                $objtmp = $objtmp | foreach-object { if ($_ -match '\d') {$_}}
                $objtmp = $objtmp | foreach-object { if (!($_ | select-string -pattern 'CR' -simplematch)) {$_}}
                $objtmp = $objtmp | foreach-object { if (!($_ | select-string -pattern 'b' -simplematch)) {$_}}
                $Latest=([HeapSort]::Sort($objtmp) | select-object -last 1).tostring()
                $SourceTagURL = [system.string]::concat('https://docbook.org/xml/',$Latest)
                $objtmp = (invoke-webrequest -UseBasicParsing -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop).Links.href
                $Names = $objtmp | foreach-object { if ($_ | select-string -pattern 'docbook-' -simplematch) {$_}}
                $Names = $Names  -replace "docbook-xml-",""
                $Names = $Names  -replace "docbook-",""
                $Names = $Names  -replace ".zip",""
            }
            if ($currentTask.spec -ilike "byacc.spec")
            {
                $Names = (invoke-webrequest -UseBasicParsing -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop).Links.href
                if ($Names)
                {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern 'byacc-' -simplematch) {$_}}
                    $Names = $Names  -replace "byacc-",""
                }             
            }            
            if ($currentTask.spec -ilike "json-c.spec")
            {
                $Names = (invoke-webrequest -UseBasicParsing -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop) -split "<"
                $Names = $Names | foreach-object { if ($_ | select-string -pattern 'Key>releases/json-c-' -simplematch) {$_ -ireplace "Key>releases/json-c-",""}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-nodoc.tar.gz' -simplematch)) {$_}}
            }

            if (!([Object]::ReferenceEquals($Names,$null)))
            {
                if ($currentTask.spec -notlike "docbook-xml.spec")
                {
                    if (((($Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}).count) -eq 0) -or ($_.spec -ilike "dialog.spec") -or ($_.spec -ilike "byacc.spec"))
                    {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tgz' -simplematch) {$_}}
                    }
                    else
                    {
                        $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                    }
                    $Names = ($Names | foreach-object { if (!($_ | select-string -pattern '</a' -simplematch)) {$_}}) -ireplace '"',""
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.tgz.asc' -simplematch)) {$_}}
                    $Names = $Names  -replace "-src.tar.gz",""
                    $Names = $Names  -replace ".tar.gz",""
                    $Names = $Names  -replace ".tar.bz2",""
                    $Names = $Names  -replace ".tar.xz",""
                    $Names = $Names  -replace ".tar.lz",""
                    $Names = $Names  -replace ".tgz",""
                }

                if ($currentTask.spec -ilike "chrpath.spec")
                {
                    $Names = $Names | foreach-object { ($_ -split "href=") -split 'rel='}
                    $Names = ($Names | foreach-object { if (($_ | select-string -pattern '/pere/chrpath' -simplematch)) {$_}}) -ireplace '/pere/chrpath/archive/release-',""
                }

                if (($currentTask.spec -ilike "apparmor.spec") -or ($currentTask.spec -ilike "bzr.spec") -or ($currentTask.spec -ilike "intltool.spec") -or ($currentTask.spec -ilike "libmetalink.spec") -or ($currentTask.spec -ilike "itstool.spec") -or ($currentTask.spec -ilike "openssl.spec") -or ($currentTask.spec -ilike "openssl-fips-provider.spec"))
                {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '/' -simplematch) {($_ -split '/')[-1]}}
                }
                elseif ($currentTask.spec -ilike "curl.spec") { $Names = $Names  -replace "download/","" }
                elseif ($currentTask.spec -ilike "js.spec") { $replace += "/pub/js/"; $replace +="-1.0.0"}
                elseif ($currentTask.spec -ilike "lsscsi.spec") { $replace += "lsscsi-030" }
                elseif ($currentTask.spec -ilike "ltrace.spec") { $replace += ".orig" }
                elseif ($currentTask.spec -ilike "tzdata.spec")
                {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern 'tzdata' -simplematch) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.tar.z' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.asc' -simplematch)) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.sign' -simplematch)) {$_}}
                    $replace += "beta"
                }
                elseif ($currentTask.spec -ilike "qemu-img.spec") { $replace += "qemu-" }
                elseif ($currentTask.spec -ilike "python-pbr.spec")
                {
                    $Names = ($Names -split "/openstack/pbr/archive/") -split ' rel=nofollow'
                }
                elseif ($currentTask.spec -ilike "python-stevedore.spec") { $replace += "stevedore-" }
                elseif ($currentTask.spec -ilike "python-antlrpythonruntime.spec") { $replace += "antlr_python_runtime-" }
                elseif ($currentTask.spec -ilike "openvswitch.spec") { $replace += "https://www.openvswitch.org/releases/openvswitch-" }
                elseif ($currentTask.spec -ilike "wireguard-tools.spec") { $replace += "/wireguard-tools/snapshot/wireguard-tools-";$replace += "'"}


                if ($ignore) {$Names = $Names | Where-Object { $n = $_; -not ($ignore | Where-Object { $n -like $_ }) }}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
                $Names = Clean-VersionNames $Names

                if ($currentTask.spec -notlike "tzdata.spec")
                {
                    $Names = $Names  -replace "v",""
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                }

                # get name latest
                if (!([string]::IsNullOrEmpty($Names -join ''))) {$NameLatest = Get-LatestName -Names $Names}

                if ($currentTask.spec -ilike "tzdata.spec") {
                    $NameLatest = $Names | Sort-Object {
                        # Extract year (digits at start)
                        $yearPart = $_ -replace '[a-z]', ''
                        # Convert to int, normalize 2-digit years to 19XX (e.g., "96" -> 1996)
                        $year = if ($yearPart -match '^\d{2}$') { [int]("19${yearPart}") } else { [int]$yearPart }
                        # Extract letter (last char, empty if none)
                        $letterPart = if ($_ -match '[a-z]$') { $_ -replace '\d', '' } else { '' }
                        # Return tuple for sorting: year (numeric), then letter (alphabetic)
                        [tuple]::Create($year, $letterPart)
                    } -Descending | Select-Object -First 1
                }
            }
            if ($NameLatest -ne "")
            {
                if ($version -is [PSCustomObject]) {[string]$version = [string]$version.version}

                $result = Compare-VersionStrings -Namelatest $Namelatest -Version $version

                if ($null -eq $result) {
                    Write-Host "Comparison for $currentTask.spec between $NameLatest and $version failed due to invalid input."
                }
                elseif ($result -gt 0) {
                    # Write-Host "$Namelatest is higher than $version"
                    $UpdateAvailable = $NameLatest
                }
                elseif ($result -lt 0) {
                    # Write-Host "$version is higher than $Namelatest"
                    $UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ."
                }
                else {
                    # Write-Host "$Namelatest is equal to $version"
                    $UpdateAvailable = "(same version)"
                }
            }
        }

    }
    }
    # -------------------------------------------------------------------------------------------------------------------
    # Signalization of not accessible or archived repositories
    # -------------------------------------------------------------------------------------------------------------------
    $warningText="Warning: repo isn't maintained anymore."
    if ($currentTask.Spec -ilike 'dhcp.spec') {$warning=$warningText+" See "+ "https://www.isc.org/dhcp_migration/"}
    elseif ($currentTask.Spec -ilike 'c-rest-engine.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'copenapi.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'cloud-network-setup.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'confd.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'cve-check-tool.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'fcgi.spec') {$warning=$warningText+" See "+ "https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/%{version}.tar.gz ."}
    elseif ($currentTask.Spec -ilike 'heapster.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'http-parser.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'kubernetes-dashboard.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'libtar.spec') {$warning=$warningText+" See "+ "https://sources.debian.org/patches/libtar"}
    elseif ($currentTask.Spec -ilike 'lightwave.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'python-argparse.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'python-atomicwrites.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'python-ipaddr.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'python-lockfile.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'python-subprocess32.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'python-terminaltables.spec') {$warning=$warningText}

    $warningText="Warning: Cannot detect correlating tags from the repo provided."
    if (($currentTask.Spec -ilike 'bluez-tools.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'containers-common.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'cpulimit.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'dbxtool.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'dcerpc.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'dotnet-sdk.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'dtb-raspberrypi.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'fuse-overlayfs-snapshotter.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'hawkey.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'libgsystem.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'libselinux.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'libsepol.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'libnss-ato.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'lightwave.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'likewise-open.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'linux-firmware.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'motd.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'netmgmt.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'pcstat.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'python-backports.ssl_match_hostname.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'python-iniparse.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'python-geomet.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'python-pyjsparser.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'python-ruamel-yaml.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText+" Also, see "+"https://github.com/commx/ruamel-yaml/archive/refs/tags/%{version}.tar.gz"}
    elseif (($currentTask.Spec -ilike 'sqlite2.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}
    elseif (($currentTask.Spec -ilike 'tornado.spec') -and ($UpdateAvailable -eq "")) {$warning=$warningText}

    $warningText="Warning: duplicate of python-pam.spec"
    if ($currentTask.Spec -ilike 'python-pycodestyle.spec') {$warning=$warningText}

    $warningText="Info: Source0 contains a VMware internal url address."
    if ($currentTask.Spec -ilike 'abupdate.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'ant-contrib.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'basic.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'build-essential.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'ca-certificates.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'distrib-compat.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'docker-vsock.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'fipsify.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'grub2-theme.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'initramfs.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'minimal.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'photon-iso-config.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'photon-release.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'photon-repos.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'photon-upgrade.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'rubygem-async-io.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'shim-signed.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'stig-hardening.spec') {$warning=$warningText}

    $warningText="Warning: Source0 seems invalid and no other Official source has been found."
    if ($currentTask.Spec -ilike 'cdrkit.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'crash.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'finger.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'ndsend.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'pcre.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'pypam.spec') {$warning=$warningText}

    $warningText="Info: Source0 contains a static version number."
    if ($currentTask.Spec -ilike 'autoconf213.spec') {$warning=$warningText}
    elseif ($currentTask.Spec -ilike 'etcd-3.3.27.spec') {$warning=$warningText}

    $warningText="Info: Packaging format .bz2 has changed to another one."
    if ($currentTask.Spec -ilike 'conntrack-tools.spec') {$warning=$warningText}
    if ($currentTask.Spec -ilike 'libnftnl.spec') {$warning=$warningText}      
    if ($currentTask.Spec -ilike 'python-twisted.spec') {$warning=$warningText}

    # reset to Source0 because of different packaging formats
    if ($currentTask.Spec -ilike 'psmisc.spec') {$Source0 = $currentTask.Source0}

    if (($UpdateAvailable -eq "") -and ($urlhealth -ne "200")) {$Source0=""}


    # -------------------------------------------------------------------------------------------------------------------
    # Search and store available updates, also with lookup from Fedora repository
    # -------------------------------------------------------------------------------------------------------------------
    $versionedUpdateAvailable=""
    # Check in Fedora
    $SourceRPMFile=""
    $SourceRPMFileURL=""
    $SourceRPMFileURL=KojiFedoraProjectLookUp -ArtefactName $currentTask.Name
    if ($SourceRPMFileURL)
    {
        try {
            $DownloadPath=[System.String](join-path -path (join-path -path $SourcePath -childpath $photonDir) -childpath "SOURCES_KojiFedora")
            if (!(Test-Path $DownloadPath)) {New-Item $DownloadPath -ItemType Directory}

            $SourceRPMFileName = ($SourceRPMFileURL -split '/')[-1]
            $SourceRPMFile = Join-Path $DownloadPath $SourceRPMFileName
            if (!(Test-Path $SourceRPMFile)) {
                try {
                    Invoke-WebRequest -UseBasicParsing -Uri $SourceRPMFileURL -OutFile $SourceRPMFile -TimeoutSec 10 -ErrorAction Stop
                }
                catch{$SourceRPMFile=""}
            }
            if ($SourceRPMFile -ne "")
            {
                $ArtefactDownloadName=""
                $ArtefactVersion=""
                try {
                    $nestedFiles = @()

                    # check if the process "tar" is running for the source file
                    $timeoutSeconds = 60
                    $startTime = Get-Date

                    # Wait while a tar process for the source file is running, up to 60 seconds
                    while (((Get-Date) - $startTime).TotalSeconds -lt $timeoutSeconds) {
                        $tarProcess = Get-Process -Name "tar" -ErrorAction SilentlyContinue | Where-Object { $_.CommandLine -like "*$SourceRPMFile*" }
                        if (-not $tarProcess) {
                            break
                        }
                        else {
                            Write-Host "A tar process for $SourceRPMFile is still running. Waiting..."
                            Start-Sleep -Seconds 1
                        }
                    }

                    $process = [System.Diagnostics.Process]::new()
                    $process.StartInfo.FileName = "tar"
                    $process.StartInfo.Arguments = "-tf `"$SourceRPMFile`""
                    $process.StartInfo.RedirectStandardOutput = $true
                    $process.StartInfo.UseShellExecute = $false
                    $process.StartInfo.CreateNoWindow = $true
                    $process.StartInfo.WorkingDirectory = $DownloadPath

                    $process.Start() | Out-Null
                    $timeoutMilliseconds = 60000  # 60 seconds timeout
                    $completed = $process.WaitForExit($timeoutMilliseconds)

                    if (-not $completed) {
                        $process.Kill()
                        $nestedFiles = @()
                        $process.Dispose()
                    }
                    else {
                        $nestedFiles = $process.StandardOutput.ReadToEnd() -split "`n" | Where-Object { $_ }
                        $process.Dispose()
                    }

                    if ($null -ne $nestedFiles)
                    {
                        foreach ($nestedFile in $nestedFiles ) {
                            $nestedFile = $nestedFile.Trim()
                            if ($nestedFile -match '\.tar\.gz$')
                            {
                                $ArtefactDownloadName=$nestedFile
                                $ArtefactVersion=$ArtefactDownloadName -ireplace ([system.string]::concat($currentTask.Name,"-")),""
                                $ArtefactVersion=$ArtefactVersion -ireplace ".tar.gz",""
                                $ArtefactVersion=$ArtefactVersion -ireplace "v",""
                            }
                        }
                    }
                    if ($ArtefactDownloadName -ne "")
                    {
                        if ($ArtefactDownloadName -ne "")
                        {
                            if ($UpdateAvailable -lt $ArtefactVersion) {
                                $UpdateAvailable = $ArtefactVersion
                                $UpdateURL=([system.string]::concat($SourceRPMFileURL,"/",$ArtefactDownloadName))
                                $HealthUpdateURL="200"
                            }
                            else {
                                $ArtefactVersion=""
                                $ArtefactDownloadName=""
                                $SourceRPMFile=""
                            }
                        }
                    }
                }
                catch {
                    Write-Error "Failed to extract files from $SourceRPMFile"
                    $ArtefactDownloadName=""
                    $ArtefactVersion=""
                }
            }
        }
        catch {
            # Silently ignore Koji/Fedora lookup failures
        }
    }

    # -------------------------------------------------------------------------------------------------------------------
    # Check health of UpdateURLs
    # -------------------------------------------------------------------------------------------------------------------
    if (!(($UpdateAvailable -ilike '*Warning*') -or ($UpdateAvailable -ilike '*Info*') -or ($UpdateAvailable -ilike '*same version*')))
    {
        $versionedUpdateAvailable=$UpdateAvailable
        if (($versionedUpdateAvailable -ne "") -and ($UpdateAvailable -ne ""))
        {
            if ($UpdateURL -eq "")
            {

                if ($currentTask.spec -ilike 'libqmi.spec') { $Source0=[system.string]::concat("https://gitlab.freedesktop.org/mobile-broadband/libqmi/-/archive/",$version,"/libqmi-",$version,".tar.gz")}

                if ($currentTask.spec -ilike 'gtest.spec')
                {
                    $version = "release-" + $version
                    $UpdateAvailable ="v" + $UpdateAvailable
                }
                if ($currentTask.spec -ilike 'icu.spec')
                {
                    $versionhiven=$UpdateAvailable.Replace(".","-")
                    $versionunderscore=$UpdateAvailable.Replace(".","_")
                    $Source0=[system.string]::concat("https://github.com/unicode-org/icu/releases/download/release-",$versionhiven,"/icu4c-",$versionunderscore,"-src.tgz")
                }
                if ($currentTask.spec -ilike 'libtirpc.spec') { $Source0=[system.string]::concat("https://downloads.sourceforge.net/project/libtirpc/libtirpc/",$version,"/libtirpc-",$version,".tar.bz2") }

                if (($Source0Save -ilike '*.tar.bz2*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".tar.bz2")}
                if (($Source0Save -ilike '*.tar.xz*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".tar.xz")}
                if (($Source0Save -ilike '*.tgz*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".tgz")}
                if (($Source0Save -ilike '*.zip*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".zip")}

                $versionshort=[system.string]::concat((([string]$version).Split("."))[0],'.',(([string]$version).Split("."))[1])
                $UpdateAvailableStr = [string]$UpdateAvailable
                if ($UpdateAvailableStr -like '*.*') {
                    $UpdateAvailableshort=[system.string]::concat((($UpdateAvailableStr).Split("."))[0],'.',(($UpdateAvailableStr).Split("."))[1])
                } else {
                    $UpdateAvailableshort = $UpdateAvailableStr
                }

                $UpdateURL=$Source0 -ireplace $version,$UpdateAvailable
                $HealthUpdateURL = urlhealth($UpdateURL)
                if ($HealthUpdateURL -ne "200")
                {
                    $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
                    $HealthUpdateURL = urlhealth($UpdateURL)
                    if ($HealthUpdateURL -ne "200")
                    {
                        $UpdateURL=$Source0 -ireplace $version,([string]$UpdateAvailable).Replace(".","_")
                        $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
                        $HealthUpdateURL = urlhealth($UpdateURL)
                        if ($HealthUpdateURL -ne "200")
                        {
                            $UpdateURL=$Source0 -ireplace $version,([string]$UpdateAvailable).Replace(".","_")
                            $UpdateURL=$UpdateURL -ireplace $versionshort,([string]$UpdateAvailableShort).Replace(".","_")
                            $HealthUpdateURL = urlhealth($UpdateURL)
                            if ($HealthUpdateURL -ne "200")
                            {
                                $UpdateURL=$Source0 -ireplace $version,([string]$UpdateAvailable).Replace(".","-")
                                $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
                                $HealthUpdateURL = urlhealth($UpdateURL)
                                if ($HealthUpdateURL -ne "200")
                                {
                                    $UpdateURL=$currentTask.Source0 -ireplace '%{name}',$currentTask.name
                                    $UpdateURL=$UpdateURL -ireplace '%{version}',$version
                                    $UpdateURL=$UpdateURL -ireplace $version,$UpdateAvailable
                                    $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
                                    $HealthUpdateURL = urlhealth($UpdateURL)
                                    if ($HealthUpdateURL -ne "200")
                                    {
                                        $UpdateURL=$currentTask.Source0 -ireplace '%{name}',$currentTask.name
                                        $UpdateURL=$UpdateURL -ireplace '%{version}',$version
                                        $UpdateURL=$UpdateURL -ireplace $version,([string]$UpdateAvailable).Replace(".","_")
                                        $UpdateURL=$UpdateURL -ireplace $version,$UpdateAvailable
                                        $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
                                        $HealthUpdateURL = urlhealth($UpdateURL)
                                        if ($HealthUpdateURL -ne "200")
                                        {
                                            $warningText="Warning: Manufacturer may changed version packaging format."
                                            $warning=$warningText
                                            $UpdateURL=""
                                            $HealthUpdateURL =""
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
    else
    {
        $UpdateURL=""
        $HealthUpdateURL=""
    }

    # -------------------------------------------------------------------------------------------------------------------
    # Store update available and updated specfile
    # -------------------------------------------------------------------------------------------------------------------
    if ($HealthUpdateURL -eq "200")
    {
        $UpdateDownloadName = ($UpdateURL -split '/')[-1]
        $SaveUpdateDownloadName = $UpdateDownloadName

        # exceptions
        # common exception
        if (($UpdateDownloadName[0] -ieq 'v') -and ($UpdateDownloadName[1] -ne '-')) {$UpdateDownloadName = $UpdateDownloadName.substring(1)}
        # individual exceptions
        if ($currentTask.spec -ilike 'inih.spec') { $UpdateDownloadName = $UpdateDownloadName -ireplace "^r","libinih-"}
        if ($currentTask.spec -ilike 'open-vm-tools.spec') {$UpdateDownloadName = [System.String]::Concat("open-vm-tools-",$UpdateDownloadName)}
        if ($currentTask.spec -ilike 'samba-client.spec') { $UpdateDownloadName = $UpdateDownloadName -ireplace "samba-samba-","samba-"}
        if ($currentTask.spec -ilike 'httpd-mod_jk.spec') {
            $UpdateDownloadName = $UpdateDownloadName -ireplace "JK_",""
            $UpdateDownloadName = $UpdateDownloadName -ireplace "_","."
            $UpdateDownloadName = [System.String]::Concat("tomcat-connectors-",$UpdateDownloadName)
        }
        # exceptions to add the $currentTask.name to the UpdateDownloadName
        # regex pattern that removes all the target extensions (.tar.gz, .tar.xz, .tgz, .tar.lz, .tar.bz2)
        $tmpName = [System.String]($UpdateDownloadName -replace "\.tar\.(gz|xz|lz|bz2)|\.tgz","")
        if (!("$tmpName" -match '[A-Za-z]')) { $UpdateDownloadName = [System.String]::Concat($currentTask.Name,"-",$UpdateDownloadName) }
        # A few sources do not contain their name in the download name, but only "release-" or "rel_".
        # Accordingly to https://packages.vmware.com/photon/photon_sources/1.0/ the downloadname must be [name]-[version].[ending].
        if (($UpdateDownloadName.StartsWith("Release", [StringComparison]::OrdinalIgnoreCase)) -or ($UpdateDownloadName.StartsWith("Rel_", [StringComparison]::OrdinalIgnoreCase))) {
            $UpdateDownloadName = $UpdateDownloadName -ireplace "Release_",[System.String]::Concat($currentTask.Name,"-")
            $UpdateDownloadName = $UpdateDownloadName -ireplace "Release-",[System.String]::Concat($currentTask.Name,"-")
            $UpdateDownloadName = $UpdateDownloadName -ireplace "Rel_",[System.String]::Concat($currentTask.Name,"-")
            $UpdateDownloadName = $UpdateDownloadName -ireplace "_","."
        }
        if (($UpdateDownloadName.StartsWith("v-", [StringComparison]::OrdinalIgnoreCase))) {
            $UpdateDownloadName = $UpdateDownloadName -ireplace "v-",[System.String]::Concat($currentTask.Name,"-")
        }        


        $SourcesNewDirectory=[System.String](join-path -path (join-path -path $SourcePath -childpath $photonDir) -childpath "SOURCES_NEW")
        if (!(Test-Path $SourcesNewDirectory)) {New-Item $SourcesNewDirectory -ItemType Directory}

        $UpdateDownloadFile=[System.String](Join-Path -Path $SourcesNewDirectory -ChildPath $UpdateDownloadName).Trim()
        if (!(Test-Path $UpdateDownloadFile)) {
            if ($SourceRPMFile -ne "") # Fedora case
            {
                try {
                    # Generate a unique temporary directory for each thread
                    $uniqueTmpPath = Join-Path -Path $SourcePath -ChildPath "tmp_$([System.Guid]::NewGuid().ToString())"
                    if (!(Test-Path $uniqueTmpPath)) {New-Item $uniqueTmpPath -ItemType Directory}

                    $nestedFiles = @()
                    $process = [System.Diagnostics.Process]::new()
                    $process.StartInfo.FileName = "tar"
                    $process.StartInfo.Arguments = "-xf `"$SourceRPMFile`""
                    $process.StartInfo.RedirectStandardOutput = $true
                    $process.StartInfo.UseShellExecute = $false
                    $process.StartInfo.CreateNoWindow = $true
                    $process.StartInfo.WorkingDirectory = $uniqueTmpPath

                    $process.Start() | Out-Null
                    $timeoutMilliseconds = 60000  # 60 seconds timeout
                    $completed = $process.WaitForExit($timeoutMilliseconds)

                    if (-not $completed) {
                        $process.Kill()
                        $nestedFiles = @()
                    }
                    $process.Dispose()

                    $tmpContentPath = (Join-Path -Path $uniqueTmpPath -ChildPath $SaveUpdateDownloadName).Trim()
                    if (test-path $tmpContentPath)
                    {
                        Move-Item -Path $tmpContentPath -Destination $UpdateDownloadFile -Force -Confirm:$false
                    }
                }
                catch {
                    Write-Error "Error processing $SourceRPMFile in thread: $_"
                }
                finally {
                    # Clean up
                    Remove-Item -Path $uniqueTmpPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            else
            {
                try {
                    # Invoke-WebRequest -Uri $UpdateURL -UseBasicParsing -Verbose:$false -OutFile $UpdateDownloadFile -TimeoutSec 10
                    (New-Object System.Net.WebClient).DownloadFile($UpdateURL, $UpdateDownloadFile)
                }
                catch
                {
                    if ($UpdateURL -ilike '*netfilter.org*')
                    {
                        $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                        $session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36"
                        $Referer=""
                        if ($UpdateURL -ilike '*libnetfilter_conntrack*') {$Referer="https://www.netfilter.org/projects/libnetfilter_conntrack/downloads.html"}
                        elseif ($UpdateURL -ilike '*libmnl*') {$Referer="https://www.netfilter.org/projects/libmnl/downloads.html"}
                        elseif ($UpdateURL -ilike '*libnetfilter_cthelper*') {$Referer="https://www.netfilter.org/projects/libnetfilter_cthelper/downloads.html"}
                        elseif ($UpdateURL -ilike '*libnetfilter_cttimeout*') {$Referer="https://www.netfilter.org/projects/libnetfilter_cttimeout/downloads.html"}
                        elseif ($UpdateURL -ilike '*libnetfilter_queue*') {$Referer="https://www.netfilter.org/projects/libnetfilter_queue/downloads.html"}
                        elseif ($UpdateURL -ilike '*libnfnetlink*') {$Referer="https://www.netfilter.org/projects/libnfnetlink/downloads.html"}
                        elseif ($UpdateURL -ilike '*libnftnl*') {$Referer="https://www.netfilter.org/projects/libnftnl/downloads.html"}
                        elseif ($UpdateURL -ilike '*nftables*') {$Referer="https://www.netfilter.org/projects/nftables/downloads.html"}
                        elseif ($UpdateURL -ilike '*conntrack-tools*') {$Referer="https://www.netfilter.org/projects/conntrack-tools/downloads.html"}
                        elseif ($UpdateURL -ilike '*iptables*') {$Referer="https://www.netfilter.org/projects/iptables/downloads.html"}

                        Invoke-WebRequest -UseBasicParsing -Uri $UpdateURL -OutFile $UpdateDownloadFile -TimeoutSec 10 -ErrorAction Stop `
                        -WebSession $session `
                        -Headers @{
                        "Accept"="text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7"
                            "Accept-Encoding"="gzip, deflate, br"
                            "Accept-Language"="en-US,en;q=0.9"
                            "Referer"="$Referer"
                            "Sec-Fetch-Dest"="document"
                            "Sec-Fetch-Mode"="navigate"
                            "Sec-Fetch-Site"="same-origin"
                            "Sec-Fetch-User"="?1"
                            "Upgrade-Insecure-Requests"="1"
                            "sec-ch-ua"="`"Google Chrome`";v=`"113`", `"Chromium`";v=`"113`", `"Not-A.Brand`";v=`"24`""
                            "sec-ch-ua-mobile"="?0"
                            "sec-ch-ua-platform"="`"Windows`""
                        }
                    }
                }
            }
        }

        # get SHA value
        [system.string]$SHALine=""
        [system.string]$SHAValue=""

        if ($UpdateDownloadFile) {
            if (Test-Path $UpdateDownloadFile)
            {
                if ($currentTask.content -ilike '*%define sha1*') { $SHAValue = (Get-FileHashWithRetry $UpdateDownloadFile -Algorithm SHA1).Hash;$SHALine = [system.string]::concat('%define sha1 ',$currentTask.Name,'=',$SHAValue) }
                if ($currentTask.content -ilike '*%define sha256*') { $SHAValue = (Get-FileHashWithRetry $UpdateDownloadFile -Algorithm SHA256).Hash;$SHALine = [system.string]::concat('%define sha256 ',$currentTask.Name,'=',$SHAValue) }
                if ($currentTask.content -ilike '*%define sha512*') { $SHAValue = (Get-FileHashWithRetry $UpdateDownloadFile -Algorithm SHA512).Hash;$SHALine = [system.string]::concat('%define sha512 ',$currentTask.Name,'=',$SHAValue) }
                    # if the spec file does not contain any sha value, add sha512
                if ((!($currentTask.content -ilike '*%define sha512*')) -and (!($object -ilike '*%define sha256*')) -and (!($object -ilike '*%define sha1*'))) { $SHAValue = (Get-FileHashWithRetry $UpdateDownloadFile -Algorithm SHA512).Hash; $SHALine = [system.string]::concat('%define sha512 ',$currentTask.Name,'=',$SHAValue) }
            }
        }
        # Add a space to signalitze that something went wrong when extracting SHAvalue but do not stop modifying the spec file.
        if ([string]::IsNullOrEmpty($SHALine)) { $SHALine=" " }

        if ($currentTask.Spec -ilike 'openjdk8.spec') {ModifySpecFile -SpecFileName $currentTask.spec -SourcePath $SourcePath -PhotonDir $photonDir -Name $currentTask.name -Update $UpdateAvailable -UpdateDownloadFile $UpdateDownloadFile -OpenJDK8 $true -SHALine $SHALine}
        else {ModifySpecFile -SpecFileName $currentTask.spec -SourcePath $SourcePath -PhotonDir $photonDir -Name $currentTask.name -Update $UpdateAvailable -UpdateDownloadFile $UpdateDownloadFile -OpenJDK8 $false -SHALine $SHALine}
    }

    [System.String]::Concat($currentTask.spec,',',$currentTask.source0,',',$Source0,',',$urlhealth,',',$UpdateAvailable,',',$UpdateURL,',',$HealthUpdateURL,',',$currentTask.Name,',',$SHAValue,',',$UpdateDownloadName,',',$Warning,',',$ArchivationDate)
}

function GenerateUrlHealthReports {
    param (
        [string]$SourcePath,
        [string]$accessToken,
        [int]$ThrottleLimit,
        [bool]$GeneratePh3URLHealthReport,
        [bool]$GeneratePh4URLHealthReport,
        [bool]$GeneratePh5URLHealthReport,
        [bool]$GeneratePh6URLHealthReport,
        [bool]$GeneratePhCommonURLHealthReport,
        [bool]$GeneratePhDevURLHealthReport,
        [bool]$GeneratePhMasterURLHealthReport
    )

    $Packages3 = $null
    $Packages4 = $null
    $Packages5 = $null
    $Packages6 = $null
    $PackagesCommon = $null
    $PackagesDev = $null
    $PackagesMaster = $null

    if ($GeneratePh3URLHealthReport) {
        Write-Host "Preparing data for Photon OS 3.0 ..."
        GitPhoton -release "3.0" -SourcePath $SourcePath
        $Packages3 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-3.0"
    }
    if ($GeneratePh4URLHealthReport) {
        Write-Host "Preparing data for Photon OS 4.0 ..."
        GitPhoton -release "4.0" -SourcePath $SourcePath
        $Packages4 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-4.0"
    }
    if ($GeneratePh5URLHealthReport) {
        Write-Host "Preparing data for Photon OS 5.0 ..."
        GitPhoton -release "5.0" -SourcePath $SourcePath
        $Packages5 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-5.0"
    }
    if ($GeneratePh6URLHealthReport) {
        Write-Host "Preparing data for Photon OS 6.0 ..."
        GitPhoton -release "6.0" -SourcePath $SourcePath
        $Packages6 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-6.0"
    }
    if ($GeneratePhCommonURLHealthReport) {
        Write-Host "Preparing data for Photon OS Common ..."
        GitPhoton -release "common" -SourcePath $SourcePath
        $PackagesCommon = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-common"
    }
    if ($GeneratePhDevURLHealthReport) {
        Write-Host "Preparing data for Photon OS Development ..."
        GitPhoton -release "dev" -SourcePath $SourcePath
        $PackagesDev = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-dev"
    }
    if ($GeneratePhMasterURLHealthReport) {
        Write-Host "Preparing data for Photon OS Master ..."
        GitPhoton -release "master" -SourcePath $SourcePath
        $PackagesMaster = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-master"
    }

    # Initialize and populate the list of tasks for URL health checks
    $checkUrlHealthTasks = @()
    if ($GeneratePh3URLHealthReport -and $null -ne $Packages3) { $checkUrlHealthTasks += @{ Name = "Photon OS 3.0"; Release = "3.0"; Packages = $Packages3; PhotonDir = "photon-3.0" } }
    if ($GeneratePh4URLHealthReport -and $null -ne $Packages4) { $checkUrlHealthTasks += @{ Name = "Photon OS 4.0"; Release = "4.0"; Packages = $Packages4; PhotonDir = "photon-4.0" } }
    if ($GeneratePh5URLHealthReport -and $null -ne $Packages5) { $checkUrlHealthTasks += @{ Name = "Photon OS 5.0"; Release = "5.0"; Packages = $Packages5; PhotonDir = "photon-5.0" } }
    if ($GeneratePh6URLHealthReport -and $null -ne $Packages6) { $checkUrlHealthTasks += @{ Name = "Photon OS 6.0"; Release = "6.0"; Packages = $Packages6; PhotonDir = "photon-6.0" } }
    if ($GeneratePhCommonURLHealthReport -and $null -ne $PackagesCommon) { $checkUrlHealthTasks += @{ Name = "Photon OS Common"; Release = "common"; Packages = $PackagesCommon; PhotonDir = "photon-common" } }
    if ($GeneratePhDevURLHealthReport -and $null -ne $PackagesDev) { $checkUrlHealthTasks += @{ Name = "Photon OS Development"; Release = "dev"; Packages = $PackagesDev; PhotonDir = "photon-dev" } }
    if ($GeneratePhMasterURLHealthReport -and $null -ne $PackagesMaster) { $checkUrlHealthTasks += @{ Name = "Photon OS Master"; Release = "master"; Packages = $PackagesMaster; PhotonDir = "photon-master" } }

    if ($checkUrlHealthTasks.Count -gt 0) {
        if ($Script:UseParallel) {
            Write-Host "Starting parallel URL health report generation for applicable versions ..."
            # Pre-capture all necessary function definitions and data once
            $FunctionDefinitions = @{
                CheckURLHealth = (Get-Command 'CheckURLHealth' -ErrorAction SilentlyContinue).Definition
                urlhealth = (Get-Command 'urlhealth' -ErrorAction SilentlyContinue).Definition
                KojiFedoraProjectLookUp = (Get-Command 'KojiFedoraProjectLookUp' -ErrorAction SilentlyContinue).Definition
                ModifySpecFile = (Get-Command 'ModifySpecFile' -ErrorAction SilentlyContinue).Definition
                Source0Lookup = (Get-Command 'Source0Lookup' -ErrorAction SilentlyContinue).Definition
                'Invoke-GitWithTimeout' = (Get-Command 'Invoke-GitWithTimeout' -ErrorAction SilentlyContinue).Definition
                'Clean-VersionNames' = (Get-Command 'Clean-VersionNames' -ErrorAction SilentlyContinue).Definition
                HeapSortClass = $HeapSortClassDef
            }
            $initParts = @()
            foreach ($entry in $FunctionDefinitions.GetEnumerator()) {
                if ($entry.Value) {
                    if ($entry.Key -eq 'HeapSortClass') { $initParts += $entry.Value }
                    else { $initParts += "function $($entry.Key) { $($entry.Value) }" }
                }
            }
            $CombinedInitScript = $initParts -join "`n"
            $ParallelContext = @{
                SourcePath = $SourcePath
                AccessToken = $AccessToken
                InitScript = $CombinedInitScript
            }
            $checkUrlHealthTasks | ForEach-Object {
                # Safely reference variables from the parent scope
                $TaskConfig = $_

                Write-Host "Generating URLHealth report for $($TaskConfig.Name) ..."
                $outputFileName = "photonos-urlhealth-$($TaskConfig.Release)_$((Get-Date).ToString("yyyyMMddHHmm"))"
                $outputFilePath = Join-Path -Path $sourcePath -ChildPath "$outputFileName.prn"

                # Create a thread-safe collection for all results
                $results = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
                $TaskConfig.Packages | ForEach-Object -parallel {
                    Invoke-Expression $using:ParallelContext.InitScript

                    # Safely reference variables from the parent scope
                    $currentPackage = $_
                    Write-Host "Processing $($currentPackage.name) ..."
                    $result = [system.string](CheckURLHealth -currentTask $currentPackage -SourcePath $using:ParallelContext.SourcePath -AccessToken $using:ParallelContext.AccessToken -outputfile $using:outputFilePath -photonDir $using:TaskConfig.PhotonDir)
                    ($using:results).Add($result)
                } -ThrottleLimit $ThrottleLimit

                $sb = New-Object System.Text.StringBuilder
                $sb.AppendLine("Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName,warning,ArchivationDate") | Out-Null
                # Filter and collect matching items, then sort
                $filteredResults = $results | ForEach-Object {
                    $pattern = '^(.*?)([a-zA-Z0-9][a-zA-Z0-9._-]*\.spec.*)$'
                    if ($_ -match $pattern) { $matches[2] }
                } | Sort-Object
                # Append sorted results to StringBuilder
                $filteredResults | ForEach-Object {
                    $sb.AppendLine($_) | Out-Null
                }
                [System.IO.File]::AppendAllText($outputFilePath, $sb.ToString())
            }
        } else {
            # Fallback to sequential processing
            Write-Host "Starting sequential URL health report generation for applicable versions..."
            $checkUrlHealthTasks | ForEach-Object {
                # Safely reference variables from the parent scope
                $TaskConfig = $_

                Write-Host "Generating URLHealth report for $($TaskConfig.Name) ..."
                $outputFileName = "photonos-urlhealth-$($TaskConfig.Release)_$((Get-Date).ToString("yyyyMMddHHmm"))"
                $outputFilePath = Join-Path -Path $sourcePath -ChildPath "$outputFileName.prn"

                # Create a simple array for sequential processing results
                $results = @()
                $results += "Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName,warning,ArchivationDate"
                $packageCount = $TaskConfig.Packages.Count
                $processedCount = 0
                foreach ($currentPackage in $TaskConfig.Packages) {
                    $processedCount++
                    Write-Host "Processing [$processedCount/$packageCount] $($currentPackage.name) ..."
                    $result = [system.string](CheckURLHealth -currentTask $currentPackage -SourcePath $SourcePath -AccessToken $accessToken -outputfile $outputFilePath -photonDir $TaskConfig.PhotonDir)
                    Write-Host "  -> Done: $($currentPackage.name)"
                    $results += $result
                }
                Write-Host "DEBUG: Finished processing all packages for $($TaskConfig.Name)"
                Write-Host "DEBUG: Results count: $($results.Count)"
                $sb = New-Object System.Text.StringBuilder
                $sb.AppendLine("Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName,warning,ArchivationDate") | Out-Null
                Write-Host "DEBUG: Filtering results..."
                # Filter and collect matching items, then sort
                $filteredResults = $results | ForEach-Object {
                    $pattern = '^(.*?)([a-zA-Z0-9][a-zA-Z0-9._-]*\.spec.*)$'
                    if ($_ -match $pattern) { $matches[2] }
                } | Sort-Object
                Write-Host "DEBUG: Filtered results count: $($filteredResults.Count)"
                # Append sorted results to StringBuilder
                $filteredResults | ForEach-Object {
                    $sb.AppendLine($_) | Out-Null
                }
                Write-Host "DEBUG: Writing to file: $outputFilePath"
                [System.IO.File]::AppendAllText($outputFilePath, $sb.ToString())
                Write-Host "DEBUG: Finished writing to file for $($TaskConfig.Name)"
            }
        }
    }
    else {
        Write-Host "No URL health reports were enabled or no package data found."
    }
    Write-Host "DEBUG: GenerateUrlHealthReports function completed"
}


# Script execution starts
Write-Host "=================================================="
Write-Host "Photon OS Package Report Script v0.61"
Write-Host "Starting at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "=================================================="

# Set security protocol to TLS 1.2 and TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Detect OS platform
$Script:RunningOnWindows = $PSVersionTable.PSEdition -eq 'Desktop' -or $env:OS -eq 'Windows_NT' -or $IsWindows

# Check if the required commands are available
Write-Host "Checking required commands (git, tar)..."
$requiredCommands = @("git", "tar")
foreach ($cmdName in $requiredCommands) {
    if (-not (Get-Command $cmdName -ErrorAction SilentlyContinue)) {
        Write-Host "$cmdName not found. Trying to install ..."
        if ($Script:RunningOnWindows) {
            $wingetId = switch ($cmdName) {
                "git" { "Git.Git" }
                "tar" { "GnuWin32.Tar" }
            }
            winget install --id $wingetId -e --source winget
        } else {
            Write-Warning "Auto-install not supported on this platform. Please install $cmdName manually using your package manager (apt, yum, brew, etc.)"
        }
        Write-Host "Please restart the script."
        exit
    }
}
Write-Host "Required commands found."

Write-Host "Checking PowerShellCookbook module..."
try {
    $useCultureCmd = Get-Command use-culture -ErrorAction Stop
    Write-Host "PowerShellCookbook module is available."
}
catch {
    Write-Host "PowerShellCookbook module not found. Attempting to install..."
    try {
        Install-Module -Name PowerShellCookbook -AllowClobber -Force -Confirm:$false -Scope CurrentUser -ErrorAction Stop
        Write-Host "PowerShellCookbook module installed."
    }
    catch {
        Write-Warning "Could not install PowerShellCookbook module: $_"
        Write-Warning "Some culture-specific formatting features may not be available."
    }
}


# parallel processing support
Write-Host "Checking parallel processing support..."
$Script:UseParallel = $PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4

# For testing or troubleshooting, you can disable parallel processing by setting $Script:UseParallel to $false
# $Script:UseParallel = $false

Write-Host "Parallel processing: $($Script:UseParallel)"

# Get current CPU usage and core count (cross-platform)
Write-Host "Gathering system information..."
$cpuUsage = 0
$cpuCores = [Environment]::ProcessorCount
if ($Script:RunningOnWindows) {
    try {
        $cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time' -ErrorAction Stop
        $cpuUsage = [math]::Round($cpuCounter.CounterSamples.CookedValue)
        $cpuCores = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
    } catch {
        Write-Warning "Could not get CPU performance counter, using defaults"
    }
}
Write-Host "CPU Cores: $cpuCores, Current CPU Usage: $cpuUsage%"
# Calculate ThrottleLimit based on CPU usage
# Example: If CPU usage is low (<50%), use up to 80% of cores; if high, reduce to 20% or a minimum
if ($cpuUsage -lt 50) {
    $throttleLimit = [math]::Round($cpuCores * 0.8)
} else {
    $throttleLimit = [math]::Max(1, [math]::Round($cpuCores * 0.2))
}
$throttleLimit = 20 # Set a hard cap to prevent overloading the system

# Set global variables from script parameters
$global:sourcepath = $sourcepath

# Validate SourcePath exists
if (-not (Test-Path -Path $global:sourcepath -PathType Container)) {
    Write-Error "Source path does not exist or is not a directory: $global:sourcepath"
    return
}
Write-Host "Source path validated: $global:sourcepath"

# SAFETY WARNING: Adding '*' as git safe.directory to handle cross-filesystem ownership issues
# (e.g., WSL accessing Windows files, network shares, or different user ownership).
# This bypasses Git's ownership security check for ALL directories globally.
# This is required because git clone operations create nested subdirectories (e.g., photon-3.0/clones/*)
# and Git's safe.directory does not support recursive wildcards.
# Review if this is acceptable for your environment. The entry persists in global git config after script completion.
# To remove after script: git config --global --unset-all safe.directory
Write-Host "Adding wildcard to git safe.directory (required for nested clone directories)..."
git config --global --add safe.directory '*' 2>$null
$global:ThrottleLimit = $throttleLimit

# Prompt for GitHub access token if not provided
if (-not $access) {
    $secureToken = Read-Host -Prompt "Please enter your Github Access Token" -AsSecureString
    $global:access = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
    $secureToken = $null  # Clear the secure string variable
    if ([string]::IsNullOrWhiteSpace($global:access)) {
        Write-Error "Access token cannot be empty"
        return
    }
}
else {
    $global:access = $access
}

if (-not $gitlabaccess) {
    $global:gitlabusername = Read-Host -Prompt "Please enter your Gitlab username"
    if ([string]::IsNullOrWhiteSpace($global:gitlabusername)) {
        Write-Error "Username cannot be empty"
        return
    }

    $secureToken = Read-Host -Prompt "Please enter your Gitlab Access Token" -AsSecureString
    $global:gitlabaccess = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureToken))
    $secureToken = $null  # Clear the secure string variable
    if ([string]::IsNullOrWhiteSpace($global:gitlabaccess)) {
        Write-Error "Access token cannot be empty"
        return
    }

    try {
        git config --global credential.https://gitlab.freedesktop.org.username $global:gitlabusername
        git config --global credential.https://gitlab.freedesktop.org.password $global:gitlabaccess
        Write-Host "Git configuration updated successfully."
    } catch {
        Write-Error "Failed to update Git configuration: $_"
    }
}
else {
    $global:gitlabaccess = $gitlabaccess
}


# Call the new function
Write-Host "DEBUG: Calling GenerateUrlHealthReports..."
$urlHealthPackageData = GenerateUrlHealthReports -SourcePath $global:sourcepath -AccessToken $global:access -ThrottleLimit $global:ThrottleLimit `
    -GeneratePh3URLHealthReport ([bool]$GeneratePh3URLHealthReport) `
    -GeneratePh4URLHealthReport ([bool]$GeneratePh4URLHealthReport) `
    -GeneratePh5URLHealthReport ([bool]$GeneratePh5URLHealthReport) `
    -GeneratePh6URLHealthReport ([bool]$GeneratePh6URLHealthReport) `
    -GeneratePhCommonURLHealthReport ([bool]$GeneratePhCommonURLHealthReport) `
    -GeneratePhDevURLHealthReport ([bool]$GeneratePhDevURLHealthReport) `
    -GeneratePhMasterURLHealthReport ([bool]$GeneratePhMasterURLHealthReport)
Write-Host "DEBUG: GenerateUrlHealthReports returned"

# Assign returned package data to existing variables if they were generated
if ($null -ne $urlHealthPackageData) {
    if ($GeneratePh3URLHealthReport) { $Packages3 = $urlHealthPackageData.Packages3 }
    if ($GeneratePh4URLHealthReport) { $Packages4 = $urlHealthPackageData.Packages4 }
    if ($GeneratePh5URLHealthReport) { $Packages5 = $urlHealthPackageData.Packages5 }
    if ($GeneratePh6URLHealthReport) { $Packages6 = $urlHealthPackageData.Packages6 }
    if ($GeneratePhCommonURLHealthReport) { $PackagesCommon = $urlHealthPackageData.PackagesCommon }
    if ($GeneratePhDevURLHealthReport) { $PackagesDev = $urlHealthPackageData.PackagesDev }
    if ($GeneratePhMasterURLHealthReport) { $PackagesMaster = $urlHealthPackageData.PackagesMaster }
}

if ($GeneratePhPackageReport)
{
    Write-Host "Generating Package Report ..."
    # fetch + merge per branch
    GitPhoton -release "3.0" -sourcePath $SourcePath
    GitPhoton -release "4.0" -sourcePath $SourcePath
    GitPhoton -release "5.0" -sourcePath $SourcePath
    GitPhoton -release "6.0" -sourcePath $SourcePath
    GitPhoton -release master -sourcePath $SourcePath
    GitPhoton -release dev -sourcePath $SourcePath
    GitPhoton -release common -sourcePath $SourcePath
    Set-location  $SourcePath
    # read all files from branch
    $Packages3=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-3.0
    $Packages4=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-4.0
    $Packages5=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-5.0
    $Packages6=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-6.0
    $PackagesCommon=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-common
    $PackagesDev=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-dev
    $PackagesMaster=ParseDirectory -SourcePath $SourcePath -PhotonDir photon-master
    $result = $Packages3,$Packages4,$Packages5,$Packages6,$PackagesCommon,$PackagesDev,$PackagesMaster| foreach-object{$currentTask}|Select-Object Spec,`
    @{l='photon-3.0';e={if($currentTask.Spec -in $Packages3.Spec) {$Packages3[$Packages3.Spec.IndexOf($currentTask.Spec)].version}}},`
    @{l='photon-4.0';e={if($currentTask.Spec -in $Packages4.Spec) {$Packages4[$Packages4.Spec.IndexOf($currentTask.Spec)].version}}},`
    @{l='photon-5.0';e={if($currentTask.Spec -in $Packages5.Spec) {$Packages5[$Packages5.Spec.IndexOf($currentTask.Spec)].version}}},`
    @{l='photon-6.0';e={if($currentTask.Spec -in $Packages6.Spec) {$Packages6[$Packages6.Spec.IndexOf($currentTask.Spec)].version}}},`
    @{l='photon-common';e={if($currentTask.Spec -in $PackagesCommon.Spec) {$PackagesCommon[$PackagesCommon.Spec.IndexOf($currentTask.Spec)].version}}},`
    @{l='photon-dev';e={if($currentTask.Spec -in $PackagesDev.Spec) {$PackagesDev[$PackagesDev.Spec.IndexOf($currentTask.Spec)].version}}},`
    @{l='photon-master';e={if($currentTask.Spec -in $PackagesMaster.Spec) {$PackagesMaster[$PackagesMaster.Spec.IndexOf($currentTask.Spec)].version}}} -Unique | Sort-object Spec
    $outputfile="$env:public\photonos-package-report_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-3.0"+","+"photon-4.0"+","+"photon-5.0"+","+"photon-6.0"+","+"photon-common"+","+"photon-dev"+","+"photon-master"| out-file $outputfile
    $result | foreach-object { $currentTask.Spec+","+$currentTask."photon-3.0"+","+$currentTask."photon-4.0"+","+$currentTask."photon-5.0"+","+$currentTask."photon-6.0"+","+$currentTask."photon-common"+","+$currentTask."photon-dev"+","+$currentTask."photon-master"} |  out-file $outputfile -append
}

if ($GeneratePhCommontoPhMasterDiffHigherPackageVersionReport)
{
    Write-Host "Generating difference report of common packages with a higher version than same master package ..."
    $outputfile1="$env:public\photonos-diff-report-common-master_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-common"+","+"photon-master"| out-file $outputfile1
    $result | foreach-object {
        # Write-Host $currentTask.spec
        if ((!([string]::IsNullOrEmpty($currentTask.'photon-common'))) -and (!([string]::IsNullOrEmpty($currentTask.'photon-master'))))
        {
            $versionCompare1 = VersionCompare $currentTask.'photon-common' $currentTask.'photon-master'
            if ($versionCompare1 -eq 1)
            {
                $diffspec1=[System.String]::Concat($currentTask.spec, ',',$currentTask.'photon-common',',',$currentTask.'photon-master')
                $diffspec1 | out-file $outputfile1 -append
            }
        }
    }
}

if ($GeneratePh5toPh6DiffHigherPackageVersionReport)
{
    Write-Host "Generating difference report of 5.0 packages with a higher version than same 6.0 package ..."
    $outputfile1="$env:public\photonos-diff-report-5.0-6.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-5.0"+","+"photon-6.0"| out-file $outputfile1
    $result | foreach-object {
        # Write-Host $currentTask.spec
        if ((!([string]::IsNullOrEmpty($currentTask.'photon-5.0'))) -and (!([string]::IsNullOrEmpty($currentTask.'photon-6.0'))))
        {
            $versionCompare1 = VersionCompare $currentTask.'photon-5.0' $currentTask.'photon-6.0'
            if ($versionCompare1 -eq 1)
            {
                $diffspec1=[System.String]::Concat($currentTask.spec, ',',$currentTask.'photon-5.0',',',$currentTask.'photon-6.0')
                $diffspec1 | out-file $outputfile1 -append
            }
        }
    }
}

if ($GeneratePh4toPh5DiffHigherPackageVersionReport)
{
    Write-Host "Generating difference report of 4.0 packages with a higher version than same 5.0 package ..."
    $outputfile1="$env:public\photonos-diff-report-4.0-5.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-4.0"+","+"photon-5.0"| out-file $outputfile1
    $result | foreach-object {
        # Write-Host $currentTask.spec
        if ((!([string]::IsNullOrEmpty($currentTask.'photon-4.0'))) -and (!([string]::IsNullOrEmpty($currentTask.'photon-5.0'))))
        {
            $versionCompare1 = VersionCompare $currentTask.'photon-4.0' $currentTask.'photon-5.0'
            if ($versionCompare1 -eq 1)
            {
                $diffspec1=[System.String]::Concat($currentTask.spec, ',',$currentTask.'photon-4.0',',',$currentTask.'photon-5.0')
                $diffspec1 | out-file $outputfile1 -append
            }
        }
    }
}

if ($GeneratePh3toPh4DiffHigherPackageVersionReport)
{
    Write-Host "Generating difference report of 3.0 packages with a higher version than same 4.0 package ..."
    $outputfile2="$env:public\photonos-diff-report-3.0-4.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-3.0"+","+"photon-4.0"| out-file $outputfile2
    $result | foreach-object {
        # Write-Host $currentTask.spec
        if ((!([string]::IsNullOrEmpty($currentTask.'photon-3.0'))) -and (!([string]::IsNullOrEmpty($currentTask.'photon-4.0'))))
        {
            $versionCompare2 = VersionCompare $currentTask.'photon-3.0' $currentTask.'photon-4.0'
            if ($versionCompare2 -eq 1)
            {
                $diffspec2=[System.String]::Concat($currentTask.spec, ',',$currentTask.'photon-3.0',',',$currentTask.'photon-4.0')
                $diffspec2 | out-file $outputfile2 -append
            }
        }
    }
}

# Security cleanup: Clear sensitive data from memory
Write-Host "Cleaning up sensitive data..."
if ($global:access) { Remove-Variable -Name access -Scope Global -ErrorAction SilentlyContinue }
if ($global:gitlabaccess) { Remove-Variable -Name gitlabaccess -Scope Global -ErrorAction SilentlyContinue }
if ($global:gitlabusername) { Remove-Variable -Name gitlabusername -Scope Global -ErrorAction SilentlyContinue }

# Clean up git credentials from global config
if ($Script:RunningOnWindows) {
    git config --global --unset credential.https://gitlab.freedesktop.org.username 2>$null
    git config --global --unset credential.https://gitlab.freedesktop.org.password 2>$null
}

Write-Host "Script completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
