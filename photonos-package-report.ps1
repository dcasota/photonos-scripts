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
#   0.56  30.05.2025   GitHubCopilot  Implemented parallel processing for spec file parsing, Fix linting errors from parallel processing implementation
#   0.57  02.06.2025   dcasota  various Bugfixes
#
#  .PREREQUISITES
#    - Script actually tested only on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - downloaded and unzipped branch directories of github.com/vmware/photon
#    - PowerShell 7+ for parallel processing capabilities




function ModifySpecFileOpenJDK8 {
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
		[string]$DownloadNameWithoutExtension
    )
    $SpecFile = join-path "$SourcePath" "$photonDir" "SPECS" "$Name" "$SpecFileName"
    $object=get-content $SpecFile


    try
    { (get-command use-culture).Version.ToString() }
    catch
    { install-module -name PowerShellCookbook -AllowClobber -Force -Confirm:$false }

    $sha1=""
    $sha256=""
    $sha512=""
    if ($object -ilike '*%define sha1*') { $certutil = certutil -hashfile $UpdateDownloadFile SHA1 | out-string; $sha1= ($certutil -split "`r`n")[1]  }
    if ($object -ilike '*%define sha256*') { $certutil = certutil -hashfile $UpdateDownloadFile SHA256 | out-string; $sha256= ($certutil -split "`r`n")[1] }
    if ($object -ilike '*%define sha512*') { $certutil = certutil -hashfile $UpdateDownloadFile SHA512 | out-string; $sha512= ($certutil -split "`r`n")[1] }

    $DateEntry = use-culture -Culture en-US {(get-date -UFormat "%a") + " " + (get-date).ToString("MMM") + " " + (get-date -UFormat "%d %Y") }
    $line1=[system.string]::concat("* ",$DateEntry," ","First Last <firstname.lastname@broadcom.com> ",$Update,"-1")

    $skip=$false
    $FileModified = @()
    Foreach ($line in $object)
    {
        if ($skip -eq $false)
        {
            if ($line -ilike '*Version:*') {$line = $line -replace 'Version:.+$', "Version:        1.8.0.$Update"; $FileModified += $line}
            elseif ($line -ilike '*Release:*') {$line = $line -replace 'Release:.+$', 'Release:        1%{?dist}'; $FileModified += $line}
            elseif ($line -ilike '*Source0:*')
            {
                $FileModified += $line
                if ($sha1 -ne "") {$FileModified += [system.string]::concat('%define sha1 ',$DownloadNameWithoutExtension,'=',$sha1); $skip=$true }
                elseif ($sha256 -ne "") {$FileModified += [system.string]::concat('%define sha256 ',$DownloadNameWithoutExtension,'=',$sha256); $skip=$true }
                elseif ($sha512 -ne "") {$FileModified +=[system.string]::concat('%define sha512 ',$DownloadNameWithoutExtension,'=',$sha512); $skip=$true }
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
        $SpecsNewDirectory=join-path "$SourcePath" "$photonDir" "SPECS_NEW" "$Name"
        $Update = [System.IO.Path]::GetFileNameWithoutExtension($Update) # Strips .asc if present
        $fileNameBase = "$Name-$Update"
        $filename = Join-Path -Path $SpecsNewDirectory -ChildPath "$fileNameBase.spec"
        if (!(Test-Path $SpecsNewDirectory)) {New-Item $SpecsNewDirectory -ItemType Directory}
        $FileModified | Set-Content $filename -Force -Confirm:$false
    }
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
		[string]$DownloadNameWithoutExtension
    )
    $SpecFile = join-path "$SourcePath" "$photonDir" "SPECS" "$Name" "$SpecFileName"
    $object=get-content $SpecFile


    try
    { (get-command use-culture).Version.ToString() }
    catch
    { install-module -name PowerShellCookbook -AllowClobber -Force -Confirm:$false }

    $sha1=""
    $sha256=""
    $sha512=""
    if ($object -ilike '*%define sha1*') { $certutil = certutil -hashfile $UpdateDownloadFile SHA1 | out-string; $sha1= ($certutil -split "`r`n")[1]  }
    if ($object -ilike '*%define sha256*') { $certutil = certutil -hashfile $UpdateDownloadFile SHA256 | out-string; $sha256= ($certutil -split "`r`n")[1] }
    if ($object -ilike '*%define sha512*') { $certutil = certutil -hashfile $UpdateDownloadFile SHA512 | out-string; $sha512= ($certutil -split "`r`n")[1] }

    $DateEntry = use-culture -Culture en-US {(get-date -UFormat "%a") + " " + (get-date).ToString("MMM") + " " + (get-date -UFormat "%d %Y") }
    $line1=[system.string]::concat("* ",$DateEntry," ","First Last <first.last@broadcom.com> ",$Update,"-1")

    $skip=$false
    $FileModified = @()
    Foreach ($line in $object)
    {
        if ($skip -eq $false)
        {
            if ($line -ilike '*Version:*') {$line = $line -replace 'Version:.+$', "Version:        $Update"; $FileModified += $line}
            elseif ($line -ilike '*Release:*') {$line = $line -replace 'Release:.+$', 'Release:        1%{?dist}'; $FileModified += $line}
            elseif ($line -ilike '*Source0:*')
            {
                $FileModified += $line
                if ($sha1 -ne "") {$FileModified += [system.string]::concat('%define sha1 ',$DownloadNameWithoutExtension,'=',$sha1); $skip=$true }
                elseif ($sha256 -ne "") {$FileModified += [system.string]::concat('%define sha256 ',$DownloadNameWithoutExtension,'=',$sha256); $skip=$true }
                elseif ($sha512 -ne "") {$FileModified +=[system.string]::concat('%define sha512 ',$DownloadNameWithoutExtension,'=',$sha512); $skip=$true }
            }
            elseif ($line -ilike '%changelog*')
            {
                $FileModified += $line
                #Add Lines after the selected pattern
                $FileModified += $line1
                $FileModified += '- automatic version bump for testing purposes DO NOT USE'
            }
            else {$FileModified += $line}
        }
        else {$skip = $false}
    }


    if ($null -ne $FileModified) {
        $SpecsNewDirectory=join-path "$SourcePath" "$photonDir" "SPECS_NEW" "$Name"
        $Update = [System.IO.Path]::GetFileNameWithoutExtension($Update) # Strips .asc if present
        $fileNameBase = "$Name-$Update"
        $filename = Join-Path -Path $SpecsNewDirectory -ChildPath "$fileNameBase.spec"
        if (!(Test-Path $SpecsNewDirectory)) {New-Item $SpecsNewDirectory -ItemType Directory}
        $FileModified | Set-Content $filename -force -Confirm:$false
    }
}

function ParseDirectory {
	param (
		[parameter(Mandatory = $true)]
		[string]$SourcePath,
		[parameter(Mandatory = $true)]
		[string]$photonDir
	)
    $Packages=@()
    Get-ChildItem -Path "$SourcePath\$photonDir\SPECS" -Recurse -File -Filter "*.spec" | ForEach-Object {
        try
        {
                $Name = Split-Path -Path $_.DirectoryName -Leaf
                $content = Get-Content $_.FullName
                $release=$null
                $release= (($content | Select-String -Pattern "^Release:")[0].ToString() -replace "Release:", "").Trim()
                $release = $release.Replace("%{?dist}","")
                $release = $release.Replace("%{?kat_build:.kat}","")
                $release = $release.Replace("%{?kat_build:.%kat_build}","")
                $release = $release.Replace("%{?kat_build:.%kat}","")
                $release = $release.Replace("%{?kernelsubrelease}","")
                $release = $release.Replace(".%{dialogsubversion}","")
                $version=$null
                $version= (($content | Select-String -Pattern "^Version:")[0].ToString() -ireplace "Version:", "").Trim()
                if ($null -ne $release) {$version = $version+"-"+$release}
                $Source0= (($content | Select-String -Pattern "^Source0:")[0].ToString() -ireplace "Source0:", "").Trim()

                if ($content -ilike '*URL:*') { $url = (($content | Select-String -Pattern "^URL:")[0].ToString() -ireplace "URL:", "").Trim() }

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

                $Packages +=[PSCustomObject]@{
                    Spec = $_.Name
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
                    byaccdate = $byaccdate
                    dialogsubversion = $dialogsubversion
                    subversion = $subversion
                    libedit_release = $libedit_release
                    libedit_version = $libedit_version
                    ncursessubversion = $ncursessubversion
                    cpan_name = $cpan_name
                    xproto_ver = $xproto_ver
                    _url_src = $_url_src
                    _repo_ver = $_repo_ver
                }
        }
        catch{}
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

function urlhealth {
	param (
		[parameter(Mandatory = $true)]
		$checkurl
	)
    $urlhealthrc=""
    try
    {
        $rc = Invoke-WebRequest -Uri $checkurl -UseDefaultCredentials -UseBasicParsing -Method Head -TimeoutSec 10 -ErrorAction Stop
        $urlhealthrc = [int]$rc.StatusCode
    }
    catch
    {
        $urlhealthrc = [int]$_.Exception.Response.StatusCode.value__
        if ($checkurl -ilike '*netfilter.org*')
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
    $Names = $Names | ForEach-Object { if (!($_ | Select-String -Pattern '<' -SimpleMatch)) {Write-Output $_}}
    $Names = $Names | ForEach-Object { if (($_ | Select-String -Pattern '.src.rpm' -SimpleMatch)) {Write-Output $_}}
    $SourceRPMFileURL=""
    $SourceTagURL="https://src.fedoraproject.org/rpms/$ArtefactName/blob/main/f/sources"
    try
    {
        $ArtefactDownloadName=((((((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10) -split '<code class') -split '</code>')[1]) -split '\(') -split '\)')[1]
        $ArtefactVersion=$ArtefactDownloadName -ireplace "${ArtefactName}-",""
        $ArtefactVersion=$ArtefactVersion -ireplace ".tar.gz",""
        $ArtefactVersion=$ArtefactVersion -ireplace "v",""

        $SourceTagURL="https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion"
        $Names = ((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10) -split '/">') -split '/</a>'
        $Names = $Names | foreach-object { if (!($_ | select-string -pattern '<' -simplematch)) {echo $_}}
        $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}

        $NameLatest = ( $Names |Sort-Object {$_-notlike'<*'},{($_-replace '^.*?(\d+).*$','$1') -as [int]} | select-object -last 1 ).ToString()

        $SourceTagURL="https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion/$NameLatest/src/"

        $Names = ((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10) -split '<a href="') -split '"'
        $Names = $Names | foreach-object { if (!($_ | select-string -pattern '<' -simplematch)) {echo $_}}
        $Names = $Names | foreach-object { if (($_ | select-string -pattern '.src.rpm' -simplematch)) {echo $_}}

        $SourceRPMFileName = ( $Names |Sort-Object {$_-notlike'<*'},{($_-replace '^.*?(\d+).*$','$1') -as [int]} | select-object -last 1 ).ToString()

        $SourceRPMFileURL= "https://kojipkgs.fedoraproject.org/packages/$ArtefactName/$ArtefactVersion/$NameLatest/src/$SourceRPMFileName"
    }catch{}
    return $SourceRPMFileURL
}
function GitPhoton {
    param (
        [parameter(Mandatory = $true)]
        [string]$SourcePath,
        [parameter(Mandatory = $true)]
        $release
    )
    #download from repo
    if (!(Test-Path -Path (Join-Path $SourcePath "photon-$release")))
    {
        Set-Location $SourcePath
        git clone -b $release https://github.com/vmware/photon (Join-Path $SourcePath "photon-$release")
        Set-Location (Join-Path $SourcePath "photon-$release")
    }
    else
    {
        Set-Location (Join-Path $SourcePath "photon-$release")
        git fetch
        if ($release -ieq "master") { git merge origin/master }
        elseif ($release -ieq "dev") { git merge origin/dev }
        else { git merge origin/$release }
    }
}

function Source0Lookup {

$Source0LookupData=@'
specfile,Source0Lookup
alsa-lib.spec,https://www.alsa-project.org/files/pub/lib/alsa-lib-%{version}.tar.bz2
alsa-utils.spec,https://www.alsa-project.org/files/pub/utils/alsa-utils-%{version}.tar.bz2
amdvlk.spec,https://github.com/GPUOpen-Drivers/AMDVLK/archive/refs/tags/v-%{version}.tar.gz
ansible.spec,https://github.com/ansible/ansible/archive/refs/tags/v%{version}.tar.gz
apache-ant.spec,https://github.com/apache/ant/archive/refs/tags/rel/%{version}.tar.gz
apache-maven.spec,https://github.com/apache/maven/archive/refs/tags/maven-%{version}.tar.gz
apache-tomcat.spec,https://github.com/apache/tomcat/archive/refs/tags/%{version}.tar.gz
apache-tomcat-native.spec,https://github.com/apache/tomcat-native/archive/refs/tags/%{version}.tar.gz
apparmor.spec,https://launchpad.net/apparmor/3.1/%{version}/+download/apparmor-%{version}.tar.gz
apr.spec,https://github.com/apache/apr/archive/refs/tags/%{version}.tar.gz
apr-util.spec,https://github.com/apache/apr-util/archive/refs/tags/%{version}.tar.gz
argon2.spec,https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/%{version}.tar.gz
asciidoc3.spec,https://gitlab.com/asciidoc3/asciidoc3/-/archive/v%{version}/asciidoc3-v%{version}.tar.gz
atk.spec,https://gitlab.gnome.org/Archive/atk/-/archive/%{version}/atk-%{version}.tar.gz
at-spi2-core.spec,https://github.com/GNOME/at-spi2-core/archive/refs/tags/AT_SPI2_CORE_%{version}.tar.gz
audit.spec,https://github.com/linux-audit/audit-userspace/archive/refs/tags/v%{version}.tar.gz
aufs-util.spec,https://github.com/sfjro/aufs-linux/archive/refs/tags/v%{version}.tar.gz
autoconf.spec,https://github.com/autotools-mirror/autoconf/archive/refs/tags/v%{version}.tar.gz
autogen.spec,https://ftp.gnu.org/gnu/autogen/rel5.18.16/autogen-%{version}.tar.xz
automake.spec,https://github.com/autotools-mirror/automake/archive/refs/tags/v%{version}.tar.gz
backward-cpp.spec,https://github.com/bombela/backward-cpp/archive/refs/tags/v%{version}.tar.gz
bindutils.spec,https://github.com/isc-projects/bind9/archive/refs/tags/v%{version}.tar.gz
boost.spec,https://github.com/boostorg/boost/archive/refs/tags/boost-%{version}.tar.gz
btrfs-progs.spec,https://github.com/kdave/btrfs-progs/archive/refs/tags/v%{version}.tar.gz
bubblewrap.spec,https://github.com/containers/bubblewrap/archive/refs/tags/v%{version}.tar.gz
bzip2.spec,https://github.com/libarchive/bzip2/archive/refs/tags/bzip2-%{version}.tar.gz
cairo.spec,https://gitlab.freedesktop.org/cairo/cairo/-/archive/%{version}/cairo-%{version}.tar.gz
calico-confd.spec,https://github.com/kelseyhightower/confd/archive/refs/tags/v%{version}.tar.gz
c-ares.spec,https://github.com/c-ares/c-ares/archive/refs/tags/cares-%{version}.tar.gz
cassandra.spec,https://github.com/apache/cassandra/archive/refs/tags/cassandra-%{version}.tar.gz
chkconfig.spec,https://github.com/fedora-sysv/chkconfig/archive/refs/tags/%{version}.tar.gz
chrony.spec,https://github.com/mlichvar/chrony/archive/refs/tags/%{version}.tar.gz
chrpath.spec,https://codeberg.org/pere/chrpath/archive/release-%{version}.tar.gz
clang.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/clang-%{version}.src.tar.xz
cloud-init.spec,https://github.com/canonical/cloud-init/archive/refs/tags/%{version}.tar.gz
cloud-utils.spec,https://github.com/canonical/cloud-utils/archive/refs/tags/%{version}.tar.gz
cmake.spec,https://github.com/Kitware/CMake/releases/download/v%{version}/cmake-%{version}.tar.gz
cmocka.spec,https://cmocka.org/files/1.1/cmocka-%{version}.tar.xz
commons-daemon.spec,https://github.com/apache/commons-daemon/archive/refs/tags/commons-daemon-%{version}.tar.gz
compat-gdbm.spec,https://ftp.gnu.org/gnu/gdbm/gdbm-%{version}.tar.gz
confd.spec,https://github.com/projectcalico/confd/archive/refs/tags/v%{version}-0.dev.tar.gz
conmon.spec,https://github.com/containers/conmon/archive/refs/tags/v%{version}.tar.gz
conntrack-tools.spec,https://www.netfilter.org/projects/conntrack-tools/files/conntrack-tools-%{version}.tar.bz2
containers-common.spec,https://github.com/containers/common/archive/refs/tags/v%{version}.tar.gz
coredns.spec,https://github.com/coredns/coredns/archive/refs/tags/v%{version}.tar.gz
cracklib.spec,https://github.com/cracklib/cracklib/archive/refs/tags/v%{version}.tar.gz
cri-tools.spec,https://github.com/kubernetes-sigs/cri-tools/archive/refs/tags/v%{version}.tar.gz
cryptsetup.spec,https://github.com/mbroz/cryptsetup/archive/refs/tags/v%{version}.tar.gz
cups.spec,https://github.com/OpenPrinting/cups/archive/refs/tags/v%{version}.tar.gz
cve-check-tool.spec,https://github.com/clearlinux/cve-check-tool/archive/refs/tags/v%{version}.tar.gz
cyrus-sasl.spec,https://github.com/cyrusimap/cyrus-sasl/archive/refs/tags/cyrus-sasl-%{version}.tar.gz
cython3.spec,https://github.com/cython/cython/archive/refs/tags/%{version}.tar.gz
device-mapper-multipath.spec,https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz
device-mapper-multipath.spec,https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz
dialog.spec,https://invisible-island.net/archives/dialog/dialog-%{version}.tgz
docbook-xml.spec,https://docbook.org/xml/%{version}/docbook-%{version}.zip
docker-20.10.spec,https://github.com/moby/moby/archive/refs/tags/v%{version}.tar.gz
docker-pycreds.spec,https://github.com/shin-/dockerpy-creds/archive/refs/tags/%{version}.tar.gz
dotnet-runtime.spec,https://github.com/dotnet/runtime/archive/refs/tags/v%{version}.tar.gz
dotnet-sdk.spec,https://github.com/dotnet/sdk/archive/refs/tags/v%{version}.tar.gz
doxygen.spec,https://github.com/doxygen/doxygen/archive/refs/tags/Release_%{version}.tar.gz
dracut.spec,https://github.com/dracutdevs/dracut/archive/refs/tags/%{version}.tar.gz
duktape.spec,https://github.com/svaarala/duktape/archive/refs/tags/v%{version}.tar.gz
ebtables.spec,https://www.netfilter.org/pub/ebtables/ebtables-%{version}.tar.gz
ecdsa.spec,https://github.com/tlsfuzzer/python-ecdsa/archive/refs/tags/python-ecdsa-%{version}.tar.gz
ed.spec,https://ftp.gnu.org/gnu/ed/ed-%{version}.tar.lz
efibootmgr.spec,https://github.com/rhboot/efibootmgr/archive/refs/tags/%{version}.tar.gz
emacs.spec,https://ftp.gnu.org/gnu/emacs/emacs-%{version}.tar.xz
erlang.spec,https://github.com/erlang/otp/archive/refs/tags/OTP-%{version}.tar.gz
erlang-sd_notify.spec,https://github.com/systemd/erlang-sd_notify/archive/refs/tags/v%{version}.tar.gz
fatrace.spec,https://github.com/martinpitt/fatrace/archive/refs/tags/%{version}.tar.gz
file.spec,http://ftp.astron.com/pub/file/file-%{version}.tar.gz
flex.spec,https://github.com/westes/flex/archive/refs/tags/v%{version}.tar.gz
fping.spec,https://github.com/schweikert/fping/archive/refs/tags/v%{version}.tar.gz
freetds.spec,https://github.com/FreeTDS/freetds/archive/refs/tags/v%{version}.tar.gz
fribidi.spec,https://github.com/fribidi/fribidi/archive/refs/tags/v%{version}.tar.gz
fuse-overlayfs-snapshotter.spec,https://github.com/containers/fuse-overlayfs/archive/refs/tags/v%{version}.tar.gz
gdk-pixbuf.spec,https://github.com/GNOME/gdk-pixbuf/archive/refs/tags/%{version}.tar.gz
geos.spec,https://github.com/libgeos/geos/archive/refs/tags/%{version}.tar.gz
getdns.spec,https://github.com/getdnsapi/getdns/archive/refs/tags/v%{version}.tar.gz
git.spec,https://www.kernel.org/pub/software/scm/git/%{name}-%{version}.tar.xz
glib.spec,https://github.com/GNOME/glib/archive/refs/tags/%{version}.tar.gz
glibmm.spec,https://github.com/GNOME/glibmm/archive/refs/tags/%{version}.tar.gz
glib-networking.spec,https://github.com/GNOME/glib-networking/archive/refs/tags/%{version}.tar.gz
gnome-common.spec,https://download.gnome.org/sources/gnome-common/3.18/gnome-common-%{version}.tar.xz
gnupg.spec,https://github.com/gpg/gnupg/archive/refs/tags/gnupg-%{version}.tar.gz
gnuplot.spec,https://github.com/gnuplot/gnuplot/archive/refs/tags/%{version}.tar.gz
gnutls.spec,https://github.com/gnutls/gnutls/archive/refs/tags/%{version}.tar.gz
go.spec,https://github.com/golang/go/archive/refs/tags/go%{version}.tar.gz
gobject-introspection.spec,https://github.com/GNOME/gobject-introspection/archive/refs/tags/%{version}.tar.gz
graphene.spec,https://github.com/ebassi/graphene/archive/refs/tags/%{version}.tar.gz
gtest.spec,https://github.com/google/googletest/archive/refs/tags/release-%{version}.tar.gz
gtk3.spec,https://github.com/GNOME/gtk/archive/refs/tags/%{version}.tar.gz
guile.spec,https://ftp.gnu.org/gnu/guile/guile-%{version}.tar.gz
haproxy.spec,https://www.haproxy.org/download/2.2/src/haproxy-%{version}.tar.gz
haproxy-dataplaneapi.spec,https://github.com/haproxytech/dataplaneapi/archive/refs/tags/v%{version}.tar.gz
haveged.spec,https://github.com/jirka-h/haveged/archive/refs/tags/v%{version}.tar.gz
hawkey.spec,https://github.com/rpm-software-management/hawkey/archive/refs/tags/hawkey-%{version}.tar.gz
httpd.spec,https://github.com/apache/httpd/archive/refs/tags/%{version}.tar.gz
httpd-mod_jk.spec,https://github.com/apache/tomcat-connectors/archive/refs/tags/JK_%{version}.tar.gz
http-parser.spec,https://github.com/nodejs/http-parser/archive/refs/tags/v%{version}.tar.gz
icu.spec,https://github.com/unicode-org/icu/releases/download/release-73-1/icu4c-73_1-src.tgz
imagemagick.spec,https://github.com/ImageMagick/ImageMagick/archive/refs/tags/%{version}.tar.gz
inih.spec,https://github.com/benhoyt/inih/archive/refs/tags/r%{version}.tar.gz
intltool.spec,https://launchpad.net/intltool/trunk/%{version}/+download/intltool-%{version}.tar.gz
ipcalc.spec,https://gitlab.com/ipcalc/ipcalc/-/archive/%{version}/ipcalc-%{version}.tar.gz
ipmitool.spec,https://github.com/ipmitool/ipmitool/archive/refs/tags/IPMITOOL_%{version}.tar.gz
ipset.spec,https://ipset.netfilter.org/ipset-%{version}.tar.bz2
iptables.spec,https://www.netfilter.org/projects/iptables/files/iptables-%{version}.tar.xz
iputils.spec,https://github.com/iputils/iputils/archive/refs/tags/s%{version}.tar.gz
ipxe.spec,https://github.com/ipxe/ipxe/archive/refs/tags/v%{version}.tar.gz
jansson.spec,https://github.com/akheron/jansson/archive/refs/tags/v%{version}.tar.gz
json-glib.spec,https://github.com/GNOME/json-glib/archive/refs/tags/%{version}.tar.gz
kafka.spec,https://github.com/apache/kafka/archive/refs/tags/%{version}.tar.gz
kbd.spec,https://github.com/legionus/kbd/archive/refs/tags/%{version}.tar.gz
keepalived.spec,https://github.com/acassen/keepalived/archive/refs/tags/v%{version}.tar.gz
keyutils.spec,https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-%{version}.tar.gz
krb5.spec,https://github.com/krb5/krb5/archive/refs/tags/krb5-%{version}-final.tar.gz
lapack.spec,https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v%{version}.tar.gz
lasso.spec,https://dev.entrouvert.org/lasso/lasso-%{version}.tar.gz
less.spec,https://github.com/gwsw/less/archive/refs/tags/v%{version}.tar.gz
leveldb.spec,https://github.com/google/leveldb/archive/refs/tags/v%{version}.tar.gz
libarchive.spec,https://github.com/libarchive/libarchive/archive/refs/tags/v%{version}.tar.gz
libatomic_ops.spec,https://github.com/ivmai/libatomic_ops/archive/refs/tags/v%{version}.tar.gz
libconfig.spec,https://github.com/hyperrealm/libconfig/archive/refs/tags/v%{version}.tar.gz
libdb.spec,https://github.com/berkeleydb/libdb/archive/refs/tags/v%{version}.tar.gz
libedit.spec,https://www.thrysoee.dk/editline/libedit-20221030-3.1.tar.gz
libestr.spec,https://github.com/rsyslog/libestr/archive/refs/tags/v%{version}.tar.gz
libev.spec,http://dist.schmorp.de/libev/Attic/libev-%{version}.tar.gz
libffi.spec,https://github.com/libffi/libffi/archive/refs/tags/v%{version}.tar.gz
libgcrypt.spec,https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-%{version}.tar.bz2
libglvnd.spec,https://github.com/NVIDIA/libglvnd/archive/refs/tags/v%{version}.tar.gz
libgpg-error.spec,https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-%{version}.tar.bz2
libgudev.spec,https://github.com/GNOME/libgudev/archive/refs/tags/%{version}.tar.gz
liblogging.spec,https://github.com/rsyslog/liblogging/archive/refs/tags/v%{version}.tar.gz
libjpeg-turbo.spec,https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/%{version}.tar.gz
libmetalink.spec,https://launchpad.net/libmetalink/trunk/libmetalink-%{version}/+download/libmetalink-%{version}.tar.bz2
libmnl.spec,https://netfilter.org/projects/libmnl/files/libmnl-%{version}.tar.bz2
libmspack.spec,https://github.com/kyz/libmspack/archive/refs/tags/v%{version}.tar.gz
libnetfilter_conntrack.spec,https://netfilter.org/projects/libnetfilter_conntrack/files/libnetfilter_conntrack-%{version}.tar.bz2
libnetfilter_cthelper.spec,https://netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-%{version}.tar.bz2
libnetfilter_cttimeout.spec,https://netfilter.org/projects/libnetfilter_cttimeout/files/libnetfilter_cttimeout-%{version}.tar.bz2
libnetfilter_queue.spec,https://netfilter.org/projects/libnetfilter_queue/files/libnetfilter_queue-%{version}.tar.bz2
libnfnetlink.spec,https://netfilter.org/projects/libnfnetlink/files/libnfnetlink-%{version}.tar.bz2
libnftnl.spec,https://netfilter.org/projects/libnftnl/files/libnftnl-%{version}.tar.xz
libnl.spec,https://github.com/thom311/libnl/archive/refs/tags/libnl%{version}.tar.gz
librelp.spec,https://download.rsyslog.com/librelp/librelp-%{version}.tar.gz
librsync.spec,https://github.com/librsync/librsync/archive/refs/tags/v%{version}.tar.gz
libpcap.spec,https://github.com/the-tcpdump-group/libpcap/archive/refs/tags/libpcap-%{version}.tar.gz
libselinux.spec,https://github.com/SELinuxProject/selinux/archive/refs/tags/libselinux-%{version}.tar.gz
libsigc++.spec,https://github.com/libsigcplusplus/libsigcplusplus/archive/refs/tags/%{version}.tar.gz
libsirp.spec,https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v%{version}/libslirp-v%{version}.tar.gz
libsoup.spec,https://github.com/GNOME/libsoup/archive/refs/tags/%{version}.tar.gz
libssh2.spec,https://github.com/libssh2/libssh2/archive/refs/tags/libssh2-%{version}.tar.gz
libtar.spec,https://github.com/tklauser/libtar/archive/refs/tags/v%{version}.tar.gz
libteam.spec,https://github.com/jpirko/libteam/archive/refs/tags/v%{version}.tar.gz
libvirt.spec,https://github.com/libvirt/libvirt/archive/refs/tags/v%{version}.tar.gz
libX11.spec,https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-%{version}/libx11-libX11-%{version}.tar.gz
libxkbcommon.spec,https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-%{version}.tar.gz
libXinerama.spec,https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-%{version}/libxinerama-libXinerama-%{version}.tar.gz
libxml2.spec,https://github.com/GNOME/libxml2/archive/refs/tags/v%{version}.tar.gz
libxslt.spec,https://github.com/GNOME/libxslt/archive/refs/tags/v%{version}.tar.gz
libyaml.spec,https://github.com/yaml/libyaml/archive/refs/tags/%{version}.tar.gz
lightwave.spec,https://github.com/vmware-archive/lightwave/archive/refs/tags/v%{version}.tar.gz
linux-firmware.spec,https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-%{version}.tar.gz
linux-PAM.spec,https://github.com/linux-pam/linux-pam/archive/refs/tags/Linux-PAM-%{version}.tar.gz
linuxptp.spec,https://github.com/richardcochran/linuxptp/archive/refs/tags/v%{version}.tar.gz
lksctp-tools.spec,https://github.com/sctp/lksctp-tools/archive/refs/tags/v%{version}.tar.gz
lldb.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/lldb-%{version}.src.tar.xz
llvm.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/llvm-%{version}.src.tar.xz
lm-sensors.spec,https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V%{version}.tar.gz
lshw.spec,https://github.com/lyonel/lshw/archive/refs/tags/%{version}.tar.gz
lsof.spec,https://github.com/lsof-org/lsof/archive/refs/tags/%{version}.tar.gz
lttng-tools.spec,https://github.com/lttng/lttng-tools/archive/refs/tags/v%{version}.tar.gz
lvm2.spec,https://github.com/lvmteam/lvm2/archive/refs/tags/v%{version}.tar.gz
lxcfs.spec,https://github.com/lxc/lxcfs/archive/refs/tags/lxcfs-%{version}.tar.gz
man-db.spec,https://gitlab.com/man-db/man-db/-/archive/%{version}/man-db-%{version}.tar.gz
man-pages.spec,https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git/snapshot/man-pages-%{version}.tar.gz
mariadb.spec,https://github.com/MariaDB/server/archive/refs/tags/mariadb-%{version}.tar.gz
mc.spec,https://github.com/MidnightCommander/mc/archive/refs/tags/%{version}.tar.gz
memcached.spec,https://github.com/memcached/memcached/archive/refs/tags/%{version}.tar.gz
mesa.spec,https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-%{version}/mesa-mesa-%{version}.tar.gz
mkinitcpio.spec,https://github.com/archlinux/mkinitcpio/archive/refs/tags/v%{version}.tar.gz
monitoring-plugins.spec,https://github.com/monitoring-plugins/monitoring-plugins/archive/refs/tags/v%{version}.tar.gz
mpc.spec,https://www.multiprecision.org/downloads/mpc-%{version}.tar.gz
mysql.spec,https://github.com/mysql/mysql-server/archive/refs/tags/mysql-%{version}.tar.gz
nano.spec,https://ftpmirror.gnu.org/nano/nano-%{version}.tar.xz
nasm.spec,https://github.com/netwide-assembler/nasm/archive/refs/tags/nasm-%{version}.tar.gz
ncurses.spec,https://github.com/ThomasDickey/ncurses-snapshots/archive/refs/tags/v%{version}.tar.gz
netmgmt.spec,https://github.com/vmware/photonos-netmgr/archive/refs/tags/v%{version}.tar.gz
net-snmp.spec,https://github.com/net-snmp/net-snmp/archive/refs/tags/v%{version}.tar.gz
net-tools.spec,https://github.com/ecki/net-tools/archive/refs/tags/v%{version}.tar.gz
newt.spec,https://github.com/mlichvar/newt/archive/refs/tags/r%{version}.tar.gz
nftables.spec,https://netfilter.org/projects/nftables/files/nftables-%{version}.tar.bz2
nginx.spec,https://github.com/nginx/nginx/archive/refs/tags/release-%{version}.tar.gz
nss-pam-ldapd.spec,https://github.com/arthurdejong/nss-pam-ldapd/archive/refs/tags/%{version}.tar.gz
nodejs.spec,https://github.com/nodejs/node/archive/refs/tags/v%{version}.tar.gz
openjdk8.spec,https://github.com/openjdk/jdk8u/archive/refs/tags/jdk8u%{subversion}-ga.tar.gz
openjdk11.spec,https://github.com/openjdk/jdk11u/archive/refs/tags/jdk-%{version}-ga.tar.gz
openjdk17.spec,https://github.com/openjdk/jdk17u/archive/refs/tags/jdk-%{version}-ga.tar.gz
openldap.spec,https://github.com/openldap/openldap/archive/refs/tags/OPENLDAP_REL_ENG_%{version}.tar.gz
openresty.spec,https://github.com/openresty/openresty/archive/refs/tags/v%{version}.tar.gz
openssh.spec,https://github.com/openssh/openssh-portable/archive/refs/tags/V_%{version}.tar.gz
ostree.spec,https://github.com/ostreedev/ostree/archive/refs/tags/v%{version}.tar.gz
pam_tacplus.spec,https://github.com/kravietz/pam_tacplus/archive/refs/tags/v%{version}.tar.gz
pandoc.spec,https://github.com/jgm/pandoc/archive/refs/tags/%{version}.tar.gz
pango.spec,https://github.com/GNOME/pango/archive/refs/tags/%{version}.tar.gz
passwdqc.spec,https://github.com/openwall/passwdqc/archive/refs/tags/PASSWDQC_%{version}.tar.gz
password-store.spec,https://github.com/zx2c4/password-store/archive/refs/tags/%{version}.tar.gz
patch.spec,https://ftp.gnu.org/gnu/patch/patch-%{version}.tar.gz
perl.spec,https://github.com/Perl/perl5/archive/refs/tags/v%{version}.tar.gz
perl-URI.spec,https://github.com/libwww-perl/URI/archive/refs/tags/v%{version}.tar.gz
perl-CGI.spec,https://github.com/leejo/CGI.pm/archive/refs/tags/v%{version}.tar.gz
perl-Config-IniFiles.spec,https://github.com/shlomif/perl-Config-IniFiles/archive/refs/tags/releases/%{version}.tar.gz
perl-Data-Validate-IP.spec,https://github.com/houseabsolute/Data-Validate-IP/archive/refs/tags/v%{version}.tar.gz
perl-DBD-SQLite.spec,https://github.com/DBD-SQLite/DBD-SQLite/archive/refs/tags/%{version}.tar.gz
perl-DBI.spec,https://github.com/perl5-dbi/dbi/archive/refs/tags/%{version}.tar.gz    xxx-1
perl-Exporter-Tiny.spec,https://github.com/tobyink/p5-exporter-tiny/archive/refs/tags/%{version}.tar.gz
perl-File-HomeDir.spec,https://github.com/perl5-utils/File-HomeDir/archive/refs/tags/%{version}.tar.gz
perl-File-Which.spec,https://github.com/uperl/File-Which/archive/refs/tags/v%{version}.tar.gz
perl-IO-Socket-SSL.spec,https://github.com/noxxi/p5-io-socket-ssl/archive/refs/tags/%{version}.tar.gz
perl-List-MoreUtils.spec,https://github.com/perl5-utils/List-MoreUtils/archive/refs/tags/%{version}.tar.gz
perl-Module-Build.spec,https://github.com/Perl-Toolchain-Gang/Module-Build/archive/refs/tags/%{version}.tar.gz
perl-Module-Install.spec,https://github.com/Perl-Toolchain-Gang/Module-Install/archive/refs/tags/%{version}.tar.gz
perl-Module-ScanDeps.spec,https://github.com/rschupp/Module-ScanDeps/archive/refs/tags/%{version}.tar.gz
perl-Net-SSLeay.spec,https://github.com/radiator-software/p5-net-ssleay/archive/refs/tags/%{version}.tar.gz
perl-Object-Accessor.spec,https://github.com/jib/object-accessor/archive/refs/tags/%{version}.tar.gz
perl-TermReadKey.spec,https://github.com/jonathanstowe/TermReadKey/archive/refs/tags/%{version}.tar.gz
perl-WWW-Curl.spec,https://github.com/szbalint/WWW--Curl/archive/refs/tags/%{version}.tar.gz
perl-YAML.spec,https://github.com/ingydotnet/yaml-pm/archive/refs/tags/%{version}.tar.gz
perl-YAML-Tiny.spec,https://github.com/Perl-Toolchain-Gang/YAML-Tiny/archive/refs/tags/v%{version}.tar.gz
pgbouncer.spec,https://github.com/pgbouncer/pgbouncer/archive/refs/tags/pgbouncer_%{version}.tar.gz
pgbackrest.spec,https://github.com/pgbackrest/pgbackrest/archive/refs/tags/release/%{version}.tar.gz
pigz.spec,https://github.com/madler/pigz/archive/refs/tags/v%{version}.tar.gz
pmd-nextgen.spec,https://github.com/vmware/pmd/archive/refs/tags/v%{version}.tar.gz
popt.spec,https://github.com/rpm-software-management/popt/archive/refs/tags/popt-%{version}-release.tar.gz
powershell.spec,https://github.com/PowerShell/PowerShell/archive/refs/tags/v%{version}.tar.gz
protobuf-c.spec,https://github.com/protobuf-c/protobuf-c/archive/refs/tags/v%{version}.tar.gz
psmisc.spec,https://gitlab.com/psmisc/psmisc/-/archive/v%{version}/psmisc-v%{version}.tar.gz
pth.spec,https://ftp.gnu.org/gnu/pth/pth-%{version}.tar.gz
pycurl.spec,https://github.com/pycurl/pycurl/archive/refs/tags/REL_%{version}.tar.gz
pygobject.spec,https://gitlab.gnome.org/GNOME/pygobject/-/archive/%{version}/pygobject-%{version}.tar.gz
python3-distro.spec,https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz
python3-pip.spec,https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz
python3-pyroute2.spec,https://github.com/svinota/pyroute2/archive/refs/tags/%{version}.tar.gz
python3-setuptools.spec,https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz
python-alabaster.spec,https://github.com/bitprophet/alabaster/archive/refs/tags/%{version}.tar.gz
python-altgraph.spec,https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz
python-altgraph.spec,https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz
python-appdirs.spec,https://github.com/ActiveState/appdirs/archive/refs/tags/%{version}.tar.gz
python-argparse.spec,https://github.com/ThomasWaldmann/argparse/archive/refs/tags/r%{version}.tar.gz
python-asn1crypto.spec,https://github.com/wbond/asn1crypto/archive/refs/tags/%{version}.tar.gz
python-atomicwrites.spec,https://github.com/untitaker/python-atomicwrites/archive/refs/tags/%{version}.tar.gz
python-attrs.spec,https://github.com/python-attrs/attrs/archive/refs/tags/%{version}.tar.gz
python-automat.spec,https://github.com/glyph/automat/archive/refs/tags/v%{version}.tar.gz
python-autopep8.spec,https://github.com/hhatto/autopep8/archive/refs/tags/v%{version}.tar.gz
python-babel.spec,https://github.com/python-babel/babel/archive/refs/tags/v%{version}.tar.gz
python-backports.ssl_match_hostname.spec,https://files.pythonhosted.org/packages/ff/2b/8265224812912bc5b7a607c44bf7b027554e1b9775e9ee0de8032e3de4b2/backports.ssl_match_hostname-3.7.0.1.tar.gz
python-backports_abc.spec,https://github.com/cython/backports_abc/archive/refs/tags/%{version}.tar.gz
python-bcrypt.spec,https://github.com/pyca/bcrypt/archive/refs/tags/%{version}.tar.gz
python-binary.spec,https://github.com/ofek/binary/archive/refs/tags/v%{version}.tar.gz
python-boto.spec,https://github.com/boto/boto/archive/refs/tags/%{version}.tar.gz
python-boto3.spec,https://github.com/boto/boto3/archive/refs/tags/%{version}.tar.gz
python-botocore.spec,https://github.com/boto/botocore/archive/refs/tags/%{version}.tar.gz
python-CacheControl.spec,https://github.com/ionrock/cachecontrol/archive/refs/tags/v%{version}.tar.gz
python-cachecontrol.spec,https://github.com/ionrock/cachecontrol/archive/refs/tags/v%{version}.tar.gz
python-cachetools.spec,https://github.com/tkem/cachetools/archive/refs/tags/v%{version}.tar.gz
python-cassandra-driver.spec,https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz
python-certifi.spec,https://github.com/certifi/python-certifi/archive/refs/tags/%{version}.tar.gz
python-cffi.spec,https://github.com/python-cffi/cffi/archive/refs/tags/v%{version}.tar.gz
python-chardet.spec,https://github.com/chardet/chardet/archive/refs/tags/%{version}.tar.gz
python-charset-normalizer.spec,https://github.com/Ousret/charset_normalizer/archive/refs/tags/%{version}.tar.gz
python-click.spec,https://github.com/pallets/click/archive/refs/tags/%{version}.tar.gz
python-ConcurrentLogHandler.spec,https://github.com/Preston-Landers/concurrent-log-handler/archive/refs/tags/%{version}.tar.gz
python-configobj.spec,https://github.com/DiffSK/configobj/archive/refs/tags/v%{version}.tar.gz
python-configparser.spec,https://github.com/jaraco/configparser/archive/refs/tags/%{version}.tar.gz
python-constantly.spec,https://github.com/twisted/constantly/archive/refs/tags/%{version}.tar.gz
python-coverage.spec,https://github.com/nedbat/coveragepy/archive/refs/tags/%{version}.tar.gz
python-cql.spec,https://storage.googleapis.com/google-code-archive-downloads/v2/apache-extras.org/cassandra-dbapi2/cql-%{version}.tar.gz
python-cql.spec,https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz
python-cqlsh.spec,hhttps://github.com/jeffwidman/cqlsh/archive/refs/tags/%{version}.tar.gz
python-cqlsh.spec,https://github.com/jeffwidman/cqlsh/archive/refs/tags/%{version}.tar.gz
python-cryptography.spec,https://github.com/pyca/cryptography/archive/refs/tags/%{version}.tar.gz
python-daemon.spec,https://pagure.io/python-daemon/archive/release/%{version}/python-daemon-release/%{version}.tar.gz
python-dateutil.spec,https://github.com/dateutil/dateutil/archive/refs/tags/%{version}.tar.gz
python-decorator.spec,https://github.com/micheles/decorator/archive/refs/tags/%{version}.tar.gz
python-deepmerge.spec,https://github.com/toumorokoshi/deepmerge/archive/refs/tags/v%{version}.tar.gz
python-defusedxml.spec,https://github.com/tiran/defusedxml/archive/refs/tags/v%{version}.tar.gz
python-dis3.spec,https://github.com/KeyWeeUsr/python-dis3/archive/refs/tags/v%{version}.tar.gz
python-distlib.spec,https://github.com/pypa/distlib/archive/refs/tags/%{version}.tar.gz
python-distro.spec,https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz
python-dnspython.spec,https://github.com/rthalley/dnspython/archive/refs/tags/v%{version}.tar.gz
python-docopt.spec,https://github.com/docopt/docopt/archive/refs/tags/%{version}.tar.gz
python-docutils.spec,https://sourceforge.net/projects/docutils/files/docutils/0.19/docutils-%{version}.tar.gz/download
python-ecdsa.spec,https://github.com/tlsfuzzer/python-ecdsa/archive/refs/tags/python-ecdsa-%{version}.tar.gz
python-email-validator.spec,https://github.com/JoshData/python-email-validator/archive/refs/tags/v%{version}.tar.gz
python-etcd.spec,https://github.com/jplana/python-etcd/archive/refs/tags/%{version}.tar.gz
python-ethtool.spec,https://github.com/fedora-python/python-ethtool/archive/refs/tags/v%{version}.tar.gz
python-filelock.spec,https://github.com/tox-dev/py-filelock/archive/refs/tags/v%{version}.tar.gz
python-flit-core.spec,https://github.com/pypa/flit/archive/refs/tags/%{version}.tar.gz
python-fuse.spec,https://github.com/libfuse/python-fuse/archive/refs/tags/v%{version}.tar.gz
python-future.spec,https://github.com/PythonCharmers/python-future/archive/refs/tags/v%{version}.tar.gz
python-futures.spec,https://github.com/agronholm/pythonfutures/archive/refs/tags/%{version}.tar.gz
python-geomet.spec,https://github.com/geomet/geomet/archive/refs/tags/%{version}.tar.gz
python-gevent.spec,https://github.com/gevent/gevent/archive/refs/tags/%{version}.tar.gz
python-graphviz.spec,https://github.com/xflr6/graphviz/archive/refs/tags/%{version}.tar.gz
python-greenlet.spec,https://github.com/python-greenlet/greenlet/archive/refs/tags/%{version}.tar.gz
python-hatch-fancy-pypi-readme.spec,https://github.com/hynek/hatch-fancy-pypi-readme/archive/refs/tags/%{version}.tar.gz
python-hatch-vcs.spec,https://github.com/ofek/hatch-vcs/archive/refs/tags/v%{version}.tar.gz
python-hatchling.spec,https://github.com/pypa/hatch/archive/refs/tags/hatchling-v%{version}.tar.gz
python-hyperlink.spec,https://github.com/python-hyper/hyperlink/archive/refs/tags/v%{version}.tar.gz
python-hypothesis.spec,https://github.com/HypothesisWorks/hypothesis/archive/refs/tags/hypothesis-python-%{version}.tar.gz
python-idna.spec,https://github.com/kjd/idna/archive/refs/tags/v%{version}.tar.gz
python-imagesize.spec,https://github.com/shibukawa/imagesize_py/archive/refs/tags/%{version}.tar.gz
python-importlib-metadata.spec,https://github.com/python/importlib_metadata/archive/refs/tags/v%{version}.tar.gz
python-incremental.spec,https://github.com/twisted/incremental/archive/refs/tags/incremental-%{version}.tar.gz
python-iniconfig.spec,https://github.com/pytest-dev/iniconfig/archive/refs/tags/v%{version}.tar.gz
python-iniparse.spec,https://github.com/candlepin/python-iniparse/archive/refs/tags/%{version}.tar.gz
python-ipaddress.spec,https://github.com/phihag/ipaddress/archive/refs/tags/v%{version}.tar.gz
python-jinja.spec,https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz
python-jinja2.spec,https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz
python-jmespath.spec,https://github.com/jmespath/jmespath.py/archive/refs/tags/%{version}.tar.gz
python-Js2Py.spec,https://files.pythonhosted.org/packages/cb/a5/3d8b3e4511cc21479f78f359b1b21f1fb7c640988765ffd09e55c6605e3b/Js2Py-%{version}.tar.gz
python-jsonpointer.spec,https://github.com/stefankoegl/python-json-pointer/archive/refs/tags/v%{version}.tar.gz
python-jsonpatch.spec,https://github.com/stefankoegl/python-json-patch/archive/refs/tags/v%{version}.tar.gz
python-jsonschema.spec,https://github.com/python-jsonschema/jsonschema/archive/refs/tags/v%{version}.tar.gz
python-looseversion.spec,https://github.com/effigies/looseversion/archive/refs/tags/%{version}.tar.gz
python-M2Crypto.spec,https://gitlab.com/m2crypto/m2crypto/-/archive/%{version}/m2crypto-%{version}.tar.gz
python-macholib.spec,https://github.com/ronaldoussoren/macholib/archive/refs/tags/v%{version}.tar.gz
python-mako.spec,https://github.com/sqlalchemy/mako/archive/refs/tags/rel_%{version}.tar.gz
python-markupsafe.spec,https://github.com/pallets/markupsafe/archive/refs/tags/%{version}.tar.gz
python-mistune.spec,https://github.com/lepture/mistune/archive/refs/tags/v%{version}.tar.gz
python-mock.spec,https://github.com/testing-cabal/mock/archive/refs/tags/%{version}.tar.gz
python-more-itertools.spec,https://github.com/more-itertools/more-itertools/archive/refs/tags/%{version}.tar.gz
python-msgpack.spec,https://github.com/msgpack/msgpack-python/archive/refs/tags/v%{version}.tar.gz
python-ndg-httpsclient.spec,https://github.com/cedadev/ndg_httpsclient/archive/refs/tags/%{version}.tar.gz
python-netaddr.spec,https://github.com/netaddr/netaddr/archive/refs/tags/%{version}.tar.gz
python-netifaces.spec,https://github.com/al45tair/netifaces/archive/refs/tags/release_%{version}.tar.gz
python-nocasedict.spec,https://github.com/pywbem/nocasedict/archive/refs/tags/%{version}.tar.gz
python-nocaselist.spec,https://github.com/pywbem/nocaselist/archive/refs/tags/%{version}.tar.gz
python-ntplib.spec,https://github.com/cf-natali/ntplib/archive/refs/tags/%{version}.tar.gz
python-numpy.spec,https://github.com/numpy/numpy/archive/refs/tags/v%{version}.tar.gz
python-oauthlib.spec,https://github.com/oauthlib/oauthlib/archive/refs/tags/v%{version}.tar.gz
python-pbr.spec,https://opendev.org/openstack/pbr/archive/%{version}.tar.gz
python-packaging.spec,https://github.com/pypa/packaging/archive/refs/tags/%{version}.tar.gz
python-pam.spec,https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz
python-pathspec.spec,https://github.com/cpburnz/python-pathspec/archive/refs/tags/v%{version}.tar.gz
python-pbr.spec,https://opendev.org/openstack/pbr/archive/%{version}.tar.gz
python-pefile.spec,https://github.com/erocarrera/pefile/archive/refs/tags/v%{version}.tar.gz
python-pexpect.spec,https://github.com/pexpect/pexpect/archive/refs/tags/%{version}.tar.gz
python-pip.spec,https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz
python-pluggy.spec,https://github.com/pytest-dev/pluggy/archive/refs/tags/%{version}.tar.gz
python-ply.spec,https://github.com/dabeaz/ply/archive/refs/tags/%{version}.tar.gz
python-portalocker.spec,https://github.com/wolph/portalocker/archive/refs/tags/v%{version}.tar.gz
python-prettytable.spec,https://github.com/jazzband/prettytable/archive/refs/tags/%{version}.tar.gz
python-prometheus_client.spec,https://github.com/prometheus/client_python/archive/refs/tags/v%{version}.tar.gz
python-prompt_toolkit.spec,https://github.com/prompt-toolkit/python-prompt-toolkit/archive/refs/tags/%{version}.tar.gz
python-psutil.spec,https://github.com/giampaolo/psutil/archive/refs/tags/release-%{version}.tar.gz
python-psycopg2.spec,https://github.com/psycopg/psycopg2/archive/refs/tags/%{version}.tar.gz
python-ptyprocess.spec,https://github.com/pexpect/ptyprocess/archive/refs/tags/%{version}.tar.gz
python-py.spec,https://github.com/pytest-dev/py/archive/refs/tags/%{version}.tar.gz
python-pyasn1.spec,https://github.com/pyasn1/pyasn1/archive/refs/tags/v%{version}.tar.gz
python-pyasn1-modules.spec,https://github.com/etingof/pyasn1-modules/archive/refs/tags/v%{version}.tar.gz
python-pycodestyle.spec,https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz
python-pycparser.spec,https://github.com/eliben/pycparser/archive/refs/tags/release_v%{version}.tar.gz
python-pycryptodome.spec,https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz
python-pycryptodomex.spec,https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz
python-pydantic.spec,https://github.com/pydantic/pydantic/archive/refs/tags/v%{version}.tar.gz
python-pyflakes.spec,https://github.com/PyCQA/pyflakes/archive/refs/tags/%{version}.tar.gz
python-Pygments.spec,https://github.com/pygments/pygments/archive/refs/tags/%{version}.tar.gz
python-pygments.spec,https://github.com/pygments/pygments/archive/refs/tags/%{version}.tar.gz
python-PyHamcrest.spec,https://github.com/hamcrest/PyHamcrest/archive/refs/tags/V%{version}.tar.gz
python-pyhamcrest.spec,https://github.com/hamcrest/PyHamcrest/archive/refs/tags/V%{version}.tar.gz
python-pyinstaller.spec,https://github.com/pyinstaller/pyinstaller/archive/refs/tags/v%{version}.tar.gz
python-pyinstaller-hooks-contrib.spec,https://github.com/pyinstaller/pyinstaller-hooks-contrib/archive/refs/tags/v%{version}.tar.gz
python-pyjsparser.spec,https://github.com/PiotrDabkowski/pyjsparser/archive/refs/tags/v%{version}.tar.gz
python-pyjwt.spec,https://github.com/jpadilla/pyjwt/archive/refs/tags/%{version}.tar.gz
python-PyNaCl.spec,https://github.com/pyca/pynacl/archive/refs/tags/%{version}.tar.gz
python-pygobject.spec,https://gitlab.gnome.org/GNOME/pygobject/-/archive/%{version}/pygobject-%{version}.tar.gz
python-pyOpenSSL.spec,https://github.com/pyca/pyopenssl/archive/refs/tags/%{version}.tar.gz
python-pyparsing.spec,https://github.com/pyparsing/pyparsing/archive/refs/tags/pyparsing_%{version}.tar.gz
python-pyrsistent.spec,https://github.com/tobgu/pyrsistent/archive/refs/tags/v%{version}.tar.gz
python-pyserial.spec,https://github.com/pyserial/pyserial/archive/refs/tags/v%{version}.tar.gz
python-pytest.spec,https://github.com/pytest-dev/pytest/archive/refs/tags/%{version}.tar.gz
python-pyudev.spec,https://github.com/pyudev/pyudev/archive/refs/tags/v%{version}.tar.gz
python-pyvim.spec,https://github.com/prompt-toolkit/pyvim/archive/refs/tags/%{version}.tar.gz
python-pyvmomi.spec,https://github.com/vmware/pyvmomi/archive/refs/tags/v%{version}.tar.gz
python-pywbem.spec,https://github.com/pywbem/pywbem/archive/refs/tags/%{version}.tar.gz
python-pytz.spec,https://github.com/stub42/pytz/archive/refs/tags/release_%{version}.tar.gz
python-pyYaml.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz
python-PyYAML.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz
python-requests.spec,https://github.com/psf/requests/archive/refs/tags/v%{version}.tar.gz
python-requests-unixsocket.spec,https://github.com/msabramo/requests-unixsocket/archive/refs/tags/v%{version}.tar.gz
python-requests-toolbelt.spec,https://github.com/requests/toolbelt/archive/refs/tags/%{version}.tar.gz
python-resolvelib.spec,https://github.com/sarugaku/resolvelib/archive/refs/tags/%{version}.tar.gz
python-rsa.spec,https://github.com/sybrenstuvel/python-rsa/archive/refs/tags/version-%{version}.tar.gz
python-ruamel-yaml.spec,https://files.pythonhosted.org/packages/17/2f/f38332bf6ba751d1c8124ea70681d2b2326d69126d9058fbd9b4c434d268/ruamel.yaml-%{version}.tar.gz
python-s3transfer.spec,https://github.com/boto/s3transfer/archive/refs/tags/%{version}.tar.gz
python-scp.spec,https://github.com/jbardin/scp.py/archive/refs/tags/v%{version}.tar.gz
python-semantic-version.spec,https://github.com/rbarrois/python-semanticversion/archive/refs/tags/%{version}.tar.gz
python-service_identity.spec,https://github.com/pyca/service-identity/archive/refs/tags/%{version}.tar.gz
python-setproctitle.spec,https://github.com/dvarrazzo/py-setproctitle/archive/refs/tags/version-%{version}.tar.gz
python-setuptools.spec,https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz
python-setuptools-rust.spec,https://github.com/PyO3/setuptools-rust/archive/refs/tags/v%{version}.tar.gz
python-setuptools_scm.spec,https://github.com/pypa/setuptools_scm/archive/refs/tags/v%{version}.tar.gz
python-simplejson.spec,https://github.com/simplejson/simplejson/archive/refs/tags/v%{version}.tar.gz
python-six.spec,https://github.com/benjaminp/six/archive/refs/tags/%{version}.tar.gz
python-snowballstemmer.spec,https://github.com/snowballstem/snowball/archive/refs/tags/v%{version}.tar.gz
python-sphinx.spec,https://github.com/sphinx-doc/sphinx/archive/refs/tags/v%{version}.tar.gz
python-sphinxcontrib-applehelp.spec,https://github.com/sphinx-doc/sphinxcontrib-applehelp/archive/refs/tags/%{version}.tar.gz
python-sphinxcontrib-devhelp.spec,https://github.com/sphinx-doc/sphinxcontrib-devhelp/archive/refs/tags/%{version}.tar.gz
python-sphinxcontrib-htmlhelp.spec,https://github.com/sphinx-doc/sphinxcontrib-htmlhelp/archive/refs/tags/%{version}.tar.gz
python-sphinxcontrib-jsmath.spec,https://github.com/sphinx-doc/sphinxcontrib-jsmath/archive/refs/tags/%{version}.tar.gz
python-sphinxcontrib-qthelp.spec,https://github.com/sphinx-doc/sphinxcontrib-qthelp/archive/refs/tags/%{version}.tar.gz
python-sphinxcontrib-serializinghtml.spec,https://github.com/sphinx-doc/sphinxcontrib-serializinghtml/archive/refs/tags/%{version}.tar.gz
python-sqlalchemy.spec,https://github.com/sqlalchemy/sqlalchemy/archive/refs/tags/rel_%{version}.tar.gz
python-subprocess32.spec,https://github.com/google/python-subprocess32/archive/refs/tags/%{version}.tar.gz
python-terminaltables.spec,https://github.com/Robpol86/terminaltables/archive/refs/tags/v%{version}.tar.gz
python-toml.spec,https://github.com/uiri/toml/archive/refs/tags/%{version}.tar.gz
python-tornado.spec,https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz
python-Twisted.spec,https://github.com/twisted/twisted/archive/refs/tags/twisted-%{version}.tar.gz
python-typing.spec,https://github.com/python/typing/archive/refs/tags/%{version}.tar.gz
python-typing-extensions.spec,https://github.com/python/typing_extensions/archive/refs/tags/%{version}.tar.gz
python-tzlocal.spec,https://github.com/regebro/tzlocal/archive/refs/tags/%{version}.tar.gz
python-ujson.spec,https://github.com/ultrajson/ultrajson/archive/refs/tags/%{version}.tar.gz
python-urllib3.spec,https://github.com/urllib3/urllib3/archive/refs/tags/%{version}.tar.gz
python-vcversioner.spec,https://github.com/habnabit/vcversioner/archive/refs/tags/%{version}.tar.gz
python-virtualenv.spec,https://github.com/pypa/virtualenv/archive/refs/tags/%{version}.tar.gz
python-wcwidth.spec,https://github.com/jquast/wcwidth/archive/refs/tags/%{version}.tar.gz
python-webob.spec,https://github.com/Pylons/webob/archive/refs/tags/%{version}.tar.gz
python-websocket-client.spec,https://github.com/websocket-client/websocket-client/archive/refs/tags/v%{version}.tar.gz
python-werkzeug.spec,https://github.com/pallets/werkzeug/archive/refs/tags/%{version}.tar.gz
python-wrapt.spec,https://github.com/GrahamDumpleton/wrapt/archive/refs/tags/%{version}.tar.gz
python-xmltodict.spec,https://github.com/martinblech/xmltodict/archive/refs/tags/v%{version}.tar.gz
python-yamlloader.spec,https://github.com/Phynix/yamlloader/archive/refs/tags/%{version}.tar.gz
python-zipp,https://github.com/jaraco/zipp/archive/refs/tags/v%{version}.tar.gz
python-zmq.spec,https://github.com/zeromq/pyzmq/archive/refs/tags/v%{version}.tar.gz
python-zope.event.spec,https://github.com/zopefoundation/zope.event/archive/refs/tags/%{version}.tar.gz
python-zope.interface.spec,https://github.com/zopefoundation/zope.interface/archive/refs/tags/%{version}.tar.gz
pyYaml.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz
rabbitmq.spec,https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz
rabbitmq3.10.spec,https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz
re2.spec,https://github.com/google/re2/archive/refs/tags/%{version}.tar.gz
redis.spec,https://github.com/redis/redis/archive/refs/tags/%{version}.tar.gz
repmgr.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz
rpcsvc-proto.spec,https://github.com/thkukuk/rpcsvc-proto/archive/refs/tags/v%{version}.tar.gz
rpm.spec,https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-%{version}-release.tar.gz
rrdtool.spec,https://github.com/oetiker/rrdtool-1.x/archive/refs/tags/v%{version}.tar.gz
rt-tests.spec,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/snapshot/rt-tests-%{version}.tar.gz
ruby.spec,https://github.com/ruby/ruby/archive/refs/tags/v%{version}.tar.gz
rust.spec,https://github.com/rust-lang/rust/archive/refs/tags/%{version}.tar.gz
rsyslog.spec,https://github.com/rsyslog/rsyslog/archive/refs/tags/v%{version}.tar.gz
serf.spec,https://github.com/apache/serf/archive/refs/tags/%{version}.tar.gz
shadow.spec,https://github.com/shadow-maint/shadow/archive/refs/tags/%{version}.tar.gz
shared-mime-info.spec,https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/%{version}/shared-mime-info-%{version}.tar.gz
slirp4netns.spec,https://github.com/rootless-containers/slirp4netns/archive/refs/tags/v%{version}.tar.gz
spirv-headers.spec,https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/sdk-%{version}.tar.gz
spirv-tools.spec,https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/sdk-%{version}.tar.gz
sqlite.spec,https://github.com/sqlite/sqlite/archive/refs/tags/version-%{version}.tar.gz
strongswan.spec,https://github.com/strongswan/strongswan/releases/download/%{version}/strongswan-%{version}.tar.bz2
subversion.spec,https://github.com/apache/subversion/archive/refs/tags/%{version}.tar.gz
sysstat.spec,http://pagesperso-orange.fr/sebastien.godard/sysstat-%{version}.tar.xz
systemd.spec,https://github.com/systemd/systemd-stable/archive/refs/tags/v%{version}.tar.gz
systemtap.spec,https://sourceware.org/ftp/systemtap/releases/systemtap-%{version}.tar.gz
tar.spec,https://ftp.gnu.org/gnu/tar/tar-%{version}.tar.xz
tboot.spec,https://sourceforge.net/projects/tboot/files/tboot/tboot-%{version}.tar.gz/download
tcp_wrappers.spec,http://ftp.porcupine.org/pub/security/tcp_wrappers_%{version}.tar.gz
termshark.spec,https://github.com/gcla/termshark/archive/refs/tags/v%{version}.tar.gz
tornado.spec,https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz
toybox.spec,https://github.com/landley/toybox/archive/refs/tags/%{version}.tar.gz
tpm2-pkcs11.spec,https://github.com/tpm2-software/tpm2-pkcs11/archive/refs/tags/%{version}.tar.gz
trousers.spec,https://sourceforge.net/projects/trousers/files/trousers/%{version}/trousers-%{version}.tar.gz/download
u-boot.spec,https://github.com/u-boot/u-boot/archive/refs/tags/v%{version}.tar.gz
ulogd.spec,https://netfilter.org/pub/ulogd/ulogd-%{version}.tar.bz2
unbound.spec,https://github.com/NLnetLabs/unbound/archive/refs/tags/release-%{version}.tar.gz
unixODBC.spec,https://github.com/lurcher/unixODBC/archive/refs/tags/%{version}.tar.gz
util-linux.spec,https://github.com/util-linux/util-linux/archive/refs/tags/v%{version}.tar.gz
util-macros.spec,https://ftp.x.org/archive//individual/util/util-macros-%{version}.tar.bz2
uwsgi.spec,https://github.com/unbit/uwsgi/archive/refs/tags/%{version}.tar.gz
valgrind.spec,https://sourceware.org/pub/valgrind/valgrind-%{version}.tar.bz2
vim.spec,https://github.com/vim/vim/archive/refs/tags/v%{version}.tar.gz
vulkan-tools.spec,https://github.com/KhronosGroup/Vulkan-Tools/archive/refs/tags/sdk-%{version}.tar.gz
wavefront-proxy.spec,https://github.com/wavefrontHQ/wavefront-proxy/archive/refs/tags/proxy-%{version}.tar.gz
wayland.spec,https://gitlab.freedesktop.org/wayland/wayland/-/archive/%{version}/wayland-%{version}.tar.gz
wget.spec,https://ftp.gnu.org/gnu/wget/wget-%{version}.tar.gz
wireshark.spec,https://github.com/wireshark/wireshark/archive/refs/tags/wireshark-%{version}.tar.gz
wrapt.spec,https://github.com/GrahamDumpleton/wrapt/archive/refs/tags/%{version}.tar.gz
xerces-c.spec,https://github.com/apache/xerces-c/archive/refs/tags/v%{version}.tar.gz
xinetd.spec,https://github.com/xinetd-org/xinetd/archive/refs/tags/xinetd-%{version}.tar.gz
XML-Parser.spec,https://github.com/toddr/XML-Parser/archive/refs/tags/%{version}.tar.gz
xml-security-c.spec,https://archive.apache.org/dist/santuario/c-library/xml-security-c-%{version}.tar.gz
xmlsec1.spec,https://www.aleksey.com/xmlsec/download/xmlsec1-%{version}.tar.gz
xz.spec,https://github.com/tukaani-project/xz/archive/refs/tags/v%{version}.tar.gz
zlib.spec,https://github.com/madler/zlib/archive/refs/tags/v%{version}.tar.gz
zsh.spec,https://github.com/zsh-users/zsh/archive/refs/tags/zsh-%{version}.tar.gz
'@
$Source0LookupData = $Source0LookupData | convertfrom-csv
return( $Source0LookupData )
}

function CheckURLHealth {
      [CmdletBinding()]
      Param(
        [parameter(Mandatory)]$currentTask,
        [parameter(Mandatory)]$SourcePath,
        [parameter(Mandatory)]$outputfile,
        [parameter(Mandatory)]$accessToken,
        [parameter(Mandatory)]$photonDir,
        [Parameter(Mandatory = $true)]
        $KojiFedoraProjectLookUpDef,  # Koji Fedora lookup definition
        [Parameter(Mandatory = $true)]
        $ModifySpecFileDef,  # Spec file modification definition
        [Parameter(Mandatory = $true)]
        $ModifySpecFileOpenJDK8Def,  # OpenJDK8 spec file modification
        [Parameter(Mandatory = $true)]
        $Source0LookupDef,  # Source0 lookup definition
        [Parameter(Mandatory = $true)]
        $urlhealthDef  # URL health definition

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

    if ($KojiFedoraProjectLookUpDef) {
        Invoke-Expression "function KojiFedoraProjectLookUp { $KojiFedoraProjectLookUpDef }"
    }
    if ($ModifySpecFileDef) {
        Invoke-Expression "function ModifySpecFile { $ModifySpecFileDef }"
    }
    if ($ModifySpecFileOpenJDK8Def) {
        Invoke-Expression "function ModifySpecFileOpenJDK8 { $ModifySpecFileOpenJDK8Def }"
    }
    if ($Source0LookupDef) {
        Invoke-Expression "function Source0Lookup { $Source0LookupDef }"
    }
    if ($urlhealthDef) {
        Invoke-Expression "function URLHealth { $urlhealthDef }"
    }
    $line=@()

    # if ($currentTask.spec -ilike 'libtirpc.spec')
    # {pause}
    # else
    # {return}

    $Source0 = $currentTask.Source0

    # cut last index in $currentTask.version and save value in $version
    $version=""
    $versionArray=($currentTask.version).split("-")
    if ($versionArray.length -gt 0)
    {
        $version=$versionArray[0]
        for ($i=1;$i -lt ($versionArray.length -1);$i++) {$version=$version + "-"+$versionArray[$i]}
        if ($versionArray[$versionArray.Length-1] -ilike '*.*')
        {
            if ([string]((($currentTask.version).split("-"))[-1]).split(".")[-1] -ne "") {$version = [System.String]::concat($version,"-",[string]((($currentTask.version).split("-"))[-1]).split(".")[-1])}
        }
    }


    # --------------------------------------------------------------------------------------------------------------
    # The following Source0 urls have been detected to be wrong or missspelled.
    # This can change. Hence, this section has to be verified from time to time.
    # Until then, before any Source0 url health check the Source0 url value is changed to a manually verified value.
    # --------------------------------------------------------------------------------------------------------------
    Write-Host "Processing $($currentTask.spec) ..."

    $data = Source0Lookup
    $index=($data.'specfile').indexof($currentTask.spec)
    if ([int]$index -ne -1)
    {
        $Source0=$data[$index].'Source0Lookup'
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
        elseif ($currentTask.spec -eq "xmlsec1.spec") {if ($version -lt "1.2.30") {$Source0="https://www.aleksey.com/xmlsec/download/older-releases/xmlsec1-%{version}.tar.gz"} else {$Source0="https://www.aleksey.com/xmlsec/download/xmlsec1-%{version}.tar.gz"}}
        }

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
        if ($Source0 -ilike '*%{url}*') { $Source0 = $Source0 -ireplace '%{url}',$currentTask.url }
        if ($Source0 -ilike '*%{srcname}*') { $Source0 = $Source0 -ireplace '%{srcname}',$currentTask.srcname }
        if ($Source0 -ilike '*%{gem_name}*') { $Source0 = $Source0 -ireplace '%{gem_name}',$currentTask.gem_name }
        if ($Source0 -ilike '*%{extra_version}*') { $Source0 = $Source0 -ireplace '%{extra_version}',$currentTask.extra_version }
        if ($Source0 -ilike '*%{main_version}*') { $Source0 = $Source0 -ireplace '%{main_version}',$currentTask.main_version }
        if ($Source0 -ilike '*%{byaccdate}*') { $Source0 = $Source0 -ireplace '%{byaccdate}',$currentTask.byaccdate }
        if ($Source0 -ilike '*%{dialogsubversion}*') { $Source0 = $Source0 -ireplace '%{dialogsubversion}',$currentTask.dialogsubversion }
        if ($Source0 -ilike '*%{subversion}*') { $Source0 = $Source0 -ireplace '%{subversion}',$currentTask.subversion }
        if ($Source0 -ilike '*%{libedit_release}*') { $Source0 = $Source0 -ireplace '%{libedit_release}',$currentTask.libedit_release }
        if ($Source0 -ilike '*%{libedit_version}*') { $Source0 = $Source0 -ireplace '%{libedit_version}',$currentTask.libedit_version }
        if ($Source0 -ilike '*%{ncursessubversion}*') { $Source0 = $Source0 -ireplace '%{ncursessubversion}',$currentTask.ncursessubversion }
        if ($Source0 -ilike '*%{cpan_name}*') { $Source0 = $Source0 -ireplace '%{cpan_name}',$currentTask.cpan_name }
        if ($Source0 -ilike '*%{xproto_ver}*') { $Source0 = $Source0 -ireplace '%{xproto_ver}',$currentTask.xproto_ver}
        if ($Source0 -ilike '*%{_url_src}*') { $Source0 = $Source0 -ireplace '%{_url_src}',$currentTask._url_src }
        if ($Source0 -ilike '*%{_repo_ver}*') { $Source0 = $Source0 -ireplace '%{_repo_ver}',$currentTask._repo_ver}
    }

    $UpdateAvailable=""
    $urlhealth=""
    $HealthUpdateURL=""
    $UpdateURL=""

    ###############################################################################
    # anomalies - rework for detection necessary
    ###############################################################################

    # for python-daemon.spec because pagure.io webpage downloads are broken. Still the case in June 2025.
    if ($currentTask.spec -eq "python-daemon.spec")
    {
        $Source0="https://files.pythonhosted.org/packages/3d/37/4f10e37bdabc058a32989da2daf29e57dc59dbc5395497f3d36d5f5e2694/python_daemon-3.1.2.tar.gz"
        $UpdateURL="https://files.pythonhosted.org/packages/d9/3c/727b06abb46fead341a2bdad04ba4a4db5395c44c45d8ba0aa82b517e462/python-daemon-2.3.2.tar.gz"
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
        $UpdateURL="https://download.osgeo.org/libtiff/tiff-4.7.0.tar.xz"
        $HealthUpdateURL="200"
        $UpdateAvailable="4.7.0"
    }

    if ($currentTask.spec -eq "mpc.spec")
    {
        $UpdateURL="https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="1.3.1"
    }

    if ($currentTask.spec -eq "python-enum34.spec")
    {
        $UpdateURL="https://files.pythonhosted.org/packages/11/c4/2da1f4952ba476677a42f25cd32ab8aaf0e1c0d0e00b89822b835c7e654c/enum34-1.1.10.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="1.1.10"
    }

    if ($currentTask.spec -eq "runit.spec")
    {
        $UpdateURL="https://smarden.org/runit/runit-2.2.0.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="2.2.0"
    }

    if ($currentTask.spec -eq "sendmail.spec")
    {
        $UpdateURL="https://ftp.sendmail.org/sendmail.8.18.1.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="8.18.1"
    }

    if ($currentTask.spec -eq "zookeeper.spec")
    {
        $UpdateURL="https://www.apache.org/dyn/closer.lua/zookeeper/zookeeper-3.9.3/apache-zookeeper-3.9.3-bin.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="3.9.3"
    }

    if ($currentTask.spec -eq "pgbackrest.spec")
    {
        $UpdateURL="https://github.com/pgbackrest/pgbackrest/archive/refs/tags/release/2.55.1.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="2.55.1"
    }

    if ($currentTask.spec -eq "re2.spec")
    {
        $UpdateURL="https://github.com/google/re2/releases/download/2024-07-02/re2-2024-07-02.tar.gz"
        $HealthUpdateURL="200"
        $UpdateAvailable="2024-07-02"
    }

    ###############################################################################

    $Source0Save=$Source0
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
                    $replace=[System.String]::Concat(('/archive/refs/tags/'),$currentTask.Name,"-","v",$version)
                    $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                    $Source0 = $Source0 -ireplace $replace,$replacenew
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        $Source0=$Source0Save
                        $replace=[System.String]::Concat(('/archive/refs/tags/'),$currentTask.Name,"-",$version)
                        $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                        $Source0 = $Source0 -ireplace $replace,$replacenew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat(('/archive/refs/tags/'),$currentTask.Name,"-",$version)
                            $replacenew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                            $Source0 = $Source0 -ireplace $replace,$replacenew
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
                                                $replace=[System.String]::Concat(('/archive/refs/tags/'),$Name,"-",$version)
                                                $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                                                $Source0 = $Source0 -ireplace $replace,$replacenew
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
                    $replace=[System.String]::Concat(('/archive/'),$currentTask.Name,"-")
                    $Source0 = $Source0 -ireplace $replace,'/archive/refs/tags/'
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        # check without naming but with a 'v' before version
                        $Source0=$Source0Save
                        $replace=[System.String]::Concat(('/archive/'),$currentTask.Name,"-")
                        $Source0 = $Source0 -ireplace $replace,'/archive/refs/tags/v'
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            # check with /releases/download/v{name}/{name}-{version}
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat(('/archive/'),$currentTask.Name,"-",$version)
                            $replacenew=[System.String]::Concat(('/releases/download/v'),$version,"/",$currentTask.Name,"-",$version,'-linux-amd64')
                            $Source0 = $Source0 -ireplace $replace,$replacenew
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
                    $replace=[System.String]::Concat(('/releases/download/'),$currentTask.Name,"-",$version,"/",$currentTask.Name,"-",$version)
                    $replacenew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                    $Source0 = $Source0 -ireplace $replace,$replacenew
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        # check without naming but with a 'v' before version
                        $Source0=$Source0Save
                        $replace=[System.String]::Concat(('/releases/download/'),$version,"/",$currentTask.Name,"-",$version)
                        $replacenew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                        $Source0 = $Source0 -ireplace $replace,$replacenew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat(('/releases/download/'),$version,"/",$currentTask.Name,"-",$version)
                            $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                            $Source0 = $Source0 -ireplace $replace,$replacenew
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
                    $replace=[System.String]::Concat($currentTask.Name,"-",$version)
                    $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                    $Source0 = $Source0 -ireplace $replace,$replacenew
                    $urlhealth = urlhealth($Source0)
                    if ($urlhealth -ne "200")
                    {
                        $Source0=$Source0Save
                        $replace=[System.String]::Concat($currentTask.Name,"-",$version)
                        $replacenew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                        $Source0 = $Source0 -ireplace $replace,$replacenew
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


    $SourceTagURL=""
    $replace=@()
    $NameLatest=""
    $UpdateDownloadName=""


    # Check UpdateAvailable by github tags detection
    if ($Source0 -ilike '*github.com*')
    {
        # Autogenerated SourceTagURL from Source0
        $TmpSource=$Source0 -ireplace 'https://github.com',""
        $TmpSource=$TmpSource -ireplace 'https://www.github.com',""
        $TmpSource=$TmpSource -ireplace 'http://github.com',""
        $TmpSource=$TmpSource -ireplace 'http://www.github.com',""
        $TmpSource=$TmpSource -ireplace '/archive/refs/tags',""
        $SourceTagURLArray=($TmpSource).split("/")
        if ($SourceTagURLArray.length -gt 1)
        {
            $SourceTagURL="https://api.github.com/repos" + "/" + $SourceTagURLArray[1] + "/" + $SourceTagURLArray[2] + "/releases"
        } else {break}

        # pre parse
        switch($currentTask.spec)
        {
            "c-rest-engine.spec" {$SourceTagURL="https://api.github.com/repos/vmware/c-rest-engine/tags"; break }
            "calico-bird.spec" {$SourceTagURL="https://api.github.com/repos/projectcalico/bird/tags"; break}
            "calico-k8s-policy.spec" {$SourceTagURL="https://api.github.com/repos/projectcalico/k8s-policy/tags"; break}
            "cpulimit.spec" {$SourceTagURL="https://api.github.com/repos/opsengine/cpulimit/tags"; break}
            "dbus.spec" {$SourceTagURL="https://api.github.com/repos/dbus/dbus/tags"; break}
            "docker-19.03.spec" {$SourceTagURL="https://api.github.com/repos/docker/docker-ce/tags"; break}
            "go.spec" {$SourceTagURL="https://api.github.com/repos/golang/go/tags"; break}
            "haproxy.spec" {$SourceTagURL="https://api.github.com/repos/haproxy/haproxy/tags"; $replace+="v"; break}
            "hawkey.spec" {$SourceTagURL="https://api.github.com/repos/rpm-software-management/hawkey/tags"; break}
            "ipmitool.spec" {$SourceTagURL="https://api.github.com/repos/ipmitool/ipmitool/tags"; break}
            "ipxe.spec" {$SourceTagURL="https://api.github.com/repos/ipxe/ipxe/tags"; break}
            "kube-controllers.spec" {$SourceTagURL="https://api.github.com/repos/projectcalico/kube-controllers/tags"; break}
            "libcgroup.spec" {$SourceTagURL="https://api.github.com/repos/libcgroup/libcgroup/tags"; break}
            "libglvnd.spec" {$SourceTagURL="https://api.github.com/repos/nvidia/libglvnd/tags"; break}
            "motd.spec" {$SourceTagURL="https://api.github.com/repos/rtnpro/motdgen/tags"; break}
            "netmgmt.spec" {$SourceTagURL="https://api.github.com/repos/vmware/photonos-netmgr/tags"; break}
            "openldap.spec" {$SourceTagURL="https://api.github.com/repos/openldap/openldap/tags"; break}
            "openresty.spec" {$SourceTagURL="https://api.github.com/repos/openresty/openresty/tags"; break}
            "openssh.spec" {$SourceTagURL="https://api.github.com/repos/openssh/openssh-portable/tags"; break}
            "pcstat.spec" {$SourceTagURL="https://api.github.com/repos/tobert/pcstat/tags"; break}
            "python-boto3.spec" {$SourceTagURL="https://api.github.com/repos/boto/boto3/tags"; break}
            "python-decorator.spec" {$SourceTagURL="https://github.com/micheles/decorator/tags"; break}
            "python-etcd.spec" {$SourceTagURL="https://api.github.com/repos/jplana/python-etcd/tags"; break}
            "python-gevent.spec" {$SourceTagURL="https://api.github.com/repos/gevent/gevent/tags"; break}
            "python-hypothesis.spec" {$SourceTagURL="https://github.com/HypothesisWorks/hypothesis/tags/"; break}
            "python3-pyroute2.spec" {$SourceTagURL="https://api.github.com/repos/svinota/pyroute2/tags"; break}
            "python-pyserial.spec" {$SourceTagURL="https://api.github.com/repos/pyserial/pyserial/tags"; break}
            "python-setproctitle.spec" {$SourceTagURL="https://github.com/dvarrazzo/py-setproctitle/tags"; $replace+="version-"; break}
            "python-zmq.spec" {$SourceTagURL="https://api.github.com/repos/zeromq/pyzmq/tags"; break}
            "rpm.spec" {$SourceTagURL="https://api.github.com/repos/rpm-software-management/rpm/tags"; break}
            "salt3.spec" {$SourceTagURL="https://api.github.com/repos/saltstack/salt/tags"; break}
            "selinux-policy.spec" {$SourceTagURL="https://github.com/fedora-selinux/selinux-policy/tags"; break}
        }

        try{
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "token $accessToken")

            if ($SourceTagURL -ilike '*/releases*')
            {
                $Names = (invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10 | convertfrom-json).tag_name
                if ([string]::IsNullOrEmpty($Names))
                {
                    $Names = (invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10 | convertfrom-json).name
                    if ([string]::IsNullOrEmpty($Names))
                    {
                        $Names = ((invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10 | convertfrom-json).assets).name
                        if ([string]::IsNullOrEmpty($Names))
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
                $Names=@()
                do
                {
                    $i++
                    try
                    {
                        $tmpUrl=[System.String]::Concat($SourceTagURL,"?page=",$i)
                        $tmpdata = (invoke-restmethod -uri $tmpUrl -usebasicparsing -TimeoutSec 10 -headers @{Authorization = "Bearer $accessToken"}).name
                        if ([string]::IsNullOrEmpty($tmpdata))
                        { $lastpage=$true }
                        else
                        { $Names += $tmpdata}
                    }
                    catch
                    {
                        $lastpage=$true
                    }
                }
                until ($lastpage -eq $true)

                if ([string]::IsNullOrEmpty($Names))
                {
                    $Names = ((invoke-restmethod -uri $tmpUrl -usebasicparsing -TimeoutSec 10 -headers @{Authorization = "Bearer $accessToken"}) -split "href") -split "rel="
                    $Names = $Names | foreach-object { if (($_ | select-string -pattern '/archive/refs/tags' -simplematch)) {$_}}
                    $Names = ($Names | foreach-object { split-path $_ -leaf }) -ireplace '" ',""
                }

            }

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
            "amdvlk.spec" {$replace +="v-"; break}
            "apache-ant.spec" {$replace +="rel/"; break}
            "apache-maven.spec" {$replace +="workspace-v0"; $replace +="maven-"; break}
            "apache-tomcat.spec"
            {
                if ($outputfile -ilike '*-3.0_*') { $Names = $Names | foreach-object { if ($_ -like '8.*') {$_}}}
                elseif ($outputfile -ilike '*-4.0_*') { $Names = $Names | foreach-object { if ($_ -like '8.*') {$_}}}
                elseif ($outputfile -ilike '*-5.0_*') { $Names = $Names | foreach-object { if ($_ -like '10.*') {$_}}}
            }
            "at-spi2-core.spec" {$replace +="AT_SPI2_CORE_3_6_3"; $replace +="AT_SPI2_CORE_"; break}
            "atk.spec"
            {
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'gnome' -simplematch)) {$_}}
                $replace +="GTK_ALL_"; $replace +="EA_"; $replace +="GAIL_"
                break
            }
            "automake.spec" { $Names = $Names -ireplace "-","."; break }
            "bcc.spec" {$replace +="src-with-submodule.tar.gz"; break}
            "bindutils.spec" {$replace +="wpk-get-rid-of-up-downgrades-"; $replace +="noadaptive"; $replace +="more-adaptive"; $replace +="adaptive"; break}
            "bpftrace.spec" {$replace +="binary.tools.man-bundle.tar.xz"; break}
            "c-ares.spec" {$replace +="cares-"; break}
            "calico-cni.spec" {$replace +="calico-amd64"; $replace +="calico-arm64"; break}
            "calico-confd.spec" {$replace +="-darwin-amd64"; $replace +="confd-"; break}
            "chrpath.spec" {$replace +="RELEASE_"; break}
            "clang.spec" {$replace +="llvmorg-"; break }
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
            "erlang.spec" {$replace +="R16B"; $replace +="OTP-"; $replace +="erl_1211-bp"; break}
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
            "httpd-mod_jk.spec"
            {
                $replace +="JK_"
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
            "lldb.spec"
            {
                $Names = $Names | foreach-object {$_.tolower().replace("llvmorg-","")}
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                $SourceTagURL=[System.String]::Concat("https://github.com/llvm/llvm-project/releases/download/llvmorg-",$NameLatest,"/lldb-",$NameLatest,".src.tar.xz")
                $rc = urlhealth -checkurl $SourceTagURL
                if ($rc -eq "200") {$Names = $NameLatest}
                break
            }
            "llvm.spec"
            {
                $Names = $Names | foreach-object {$_.tolower().replace("llvmorg-","")}
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                $SourceTagURL=[System.String]::Concat("https://github.com/llvm/llvm-project/releases/download/llvmorg-",$NameLatest,"/llvm-",$NameLatest,".src.tar.xz")
                $rc = urlhealth -checkurl $SourceTagURL
                if ($rc -eq "200") {$Names = $NameLatest}
                break
            }
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
                $Names = (invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10).links.href
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
            "openjdk8.spec"
            {
                $Names = $Names | foreach-object { if (($_ | select-string -pattern '-ga' -simplematch)) {$_}}
                $replace +="jdk8u"
                $replace +="-ga"
            }
            "openjdk11.spec"
            {
                $Names = $Names | foreach-object { if (($_ | select-string -pattern '-ga' -simplematch)) {$_}}
                $replace +="jdk-"
                $replace +="-ga"
            }
            "openjdk17.spec"
            {
                $Names = $Names | foreach-object { if (($_ | select-string -pattern '-ga' -simplematch)) {$_}}
                $replace +="jdk-"
                $replace +="-ga"
            }
            "openldap.spec" {$replace +="UTBM_"; $replace +="URE_"; $replace +="UMICH_LDAP_3_3"; $replace +="UCDATA_"; $replace +="TWEB_OL_BASE"; $replace +="SLAPD_BACK_LDAP"; $replace +="PHP3_TOOL_0_0"; $replace +="OPENLDAP_REL_ENG_"; $replace +="LMDB_"; break}
            "open-vm-tools.spec" {$replace +="stable-"; break}
            "pandoc.spec" {$replace +="pandoc-server-"; $replace +="pandoc-lua-engine-"; $replace +="pandoc-cli-0.1"; $replace +="new1.16deb"; $replace +="list"; break}
            "pango.spec" {$replace +="tical-branch-point"; break}
            "perl-Config-IniFiles.spec" {$replace +="releases/"; break}
            "popt.spec" {$replace +="-release"; break}
            "powershell.spec" {$replace +="hashes.sha256";break}
            "pycurl.spec" {$replace +="REL_"; break}
            "python-babel.spec" {$replace +="dev-2a51c9b95d06"; break}
            "python-cassandra-driver.spec" {$replace +="3.9-doc-backports-from-3.1"; $replace +="-backport-prepared-slack"; break}
            "python-decorator.spec"
            {
                $Names = (invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10).links.href
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
                $Names = (invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10).links.href
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '.tar.' -simplematch) {$_}}
                $Names = $Names -replace "/HypothesisWorks/hypothesis/archive/refs/tags/hypothesis-python-",""
                $Names = $Names -replace ".tar.gz",""
                break
            }
            "python-incremental.spec" {$replace +="incremental-"; break}
            "python-lxml.spec" {$replace +="lxml-"; break}
            "python-mako.spec" {$replace +="rel_"; break}
            "python-more-itertools.spec" {$replace +="v"; break}
            "python-networkx.spec" {$replace += "python-networkx-"; $replace += "networkx-"; break }
            "python-numpy.spec" {$replace +="with_maskna"; break}
            "python-pyparsing.spec" {$replace +="pyparsing_"; break}
            "python-setproctitle.spec" {$replace +="version-"; break}
            "python-sqlalchemy.spec" {$replace +="rel_"; break}
            "python-twisted.spec" {$replace += "python-"; $replace += "twisted-";break}
            "python-webob.spec" {$replace +="sprint-coverage"; break}
            "python-pytz.spec" {$replace +="release_"; break}
            "rabbitmq3.10.spec" {
                $Names = $Names | foreach-object { if ($_ | select-string -pattern 'v3.10.' -simplematch) {$_}}
                break
            }
            "ragel.spec" {$replace +="ragel-pre-colm"; $replace +="ragel-barracuda-v5"; $replace +="barracuda-v4"; $replace +="barracuda-v3"; $replace +="barracuda-v2"; $replace +="barracuda-v1"; break}
            "redis.spec" {$replace +="with-deprecated-diskstore"; $replace +="vm-playpen"; $replace +="twitter-20100825"; $replace +="twitter-20100804"; break}
            "rpm.spec" {$replace +="rpm-";$replace +="-release"; break}
            "s3fs-fuse.spec" {$replace +="Pre-v"; break}
            "salt3.spec"  {$Names = $Names -ireplace "-","."; $replace +="Pre.v"; break}
            "selinux-policy.spec"
            {
                $Names = (invoke-webrequest $SourceTagURL -headers $headers -TimeoutSec 10).links.href
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
            "sqlite.spec" {$replace +="version-"; break}
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

                $replace += $currentTask.Name + "."
                $replace += $currentTask.Name + "-"
                $replace += $currentTask.Name + "_"
                $replace += $currentTask.Name
                $replace += "ver"
                $replace += "release_"
                $replace += "release-"
                $replace += "release"
                $i = 0; do { $Names = $Names | foreach-object { $_.tolower().replace(($replace[$i]).tolower(), "") }; $i++ } while ($i -ne $replace.count - 1)

                # $replace | foreach { $Names = $Names -replace $_,""}
                $Names = $Names.Where({ $null -ne $currentTask.Name })
                $Names = $Names.Where({ "" -ne $currentTask.Name })
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^rel/' -simplematch) { $_ -ireplace '^rel/', "" } else { $_ } }
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) { $_ -ireplace '^v', "" } else { $_ } }
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) { $_ -ireplace '^V', "" } else { $_ } }
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) { $_ -ireplace '^r', "" } else { $_ } }
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) { $_ -ireplace '^R', "" } else { $_ } }
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '_' -simplematch) { $_ -ireplace '_', "." } else { $_ } }

                # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) { $_ } }
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) { $_ } }

                $Names = $Names -ireplace "v", ""

                if ($currentTask.spec -notlike "amdvlk.spec") {
                    $Names = $Names | foreach-object { if ($_ -match '\d') { $_ } }
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) { $_ } }
                }

                if ($Names -ilike '*.*') {
                    $NameLatest = ($Names | foreach-object { $tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) { $tmpversion } else { $tag } } | sort-object | select-object -last 1).ToString()
                }
                else {
                    $NameLatest = ($Names | convertfrom-json | sort-object | select-object -last 1).ToString()
                }
                if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object | select-object -last 1).ToString() }
        }
        catch{$NameLatest=""}
        if ($NameLatest -ne "")
        {
            if ($currentTask.spec -ilike 'lshw.spec') {$NameLatest = $NameLatest -replace "9999","B."}
            elseif ($currentTask.spec -ilike 'network-config-manager.spec')
            {
                $NameLatest = $NameLatest -replace ".0.9991",".a"
                $NameLatest = $NameLatest -replace ".0.9992",".b"
                $NameLatest = $NameLatest -replace ".0.9993",".c"
            }
            elseif (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
            {
                try
                {
                    if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
                catch{}
            }
            if ($UpdateAvailable -eq "")
            {
                if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
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
            $Names = ((invoke-restmethod -uri $SourceTagURL -usebasicparsing -TimeoutSec 10) -split 'a href=') -split '>'
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
                $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
            }
            if ($currentTask.spec -ilike 'mozjs60.spec') {$SourceTagURL=$SourceTagURL+$NameLatest+"esr/source/"}
            else {$SourceTagURL=$SourceTagURL+$NameLatest+"/source/"}
        }
        elseif ($currentTask.spec -ilike 'nss.spec')
        {
            $SourceTagURL="https://ftp.mozilla.org/pub/security/nss/releases/"
            $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split 'a href=') -split '>'
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
        elseif ($currentTask.spec -ilike 'nspr.spec')
        {
            $SourceTagURL="https://ftp.mozilla.org/pub/nspr/releases/"
            $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split 'a href=') -split '>'
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
                $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
            }
            $SourceTagURL=$SourceTagURL+"v"+$NameLatest+"/src/"
        }
        elseif (($currentTask.spec -ilike 'python2.spec') -or ($currentTask.spec -ilike 'python3.spec'))
        {
            $replace=@("Python-")
            do
            {
                $SourceTagURL="https://www.python.org/ftp/python/"
                $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split 'a href=') -split '>'
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
                $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -le $replace.count-1)
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                $SourceTagURL=$SourceTagURL+$NameLatest
                $Names = ((((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split "<tr><td") -split 'a href=') -split '>') -split "title="
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
            } until (!([string]::IsNullOrEmpty($Names)))
        }
        else
        {
            # Autogenerated SourceTagURL from Source0
            $SourceTagURLArray=($Source0 ).split("/")
            if ($SourceTagURLArray.length -gt 0)
            {
                for ($i=1;$i -lt ($SourceTagURLArray.length -1);$i++)
                {
                    if ($SourceTagURL -eq "") {$SourceTagURL = $SourceTagURLArray[$i]}
                    else { $SourceTagURL=$SourceTagURL + "/" + $SourceTagURLArray[$i] }
                }
            }
        }


        try{
            $Names=@()
            $Names = ((((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split "<tr><td") -split 'a href=') -split '>') -split "title="
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

            $replace += $currentTask.Name+"."
            $replace += $currentTask.Name+"-"
            $replace += $currentTask.Name+"_"
            $replace += $currentTask.Name
            $replace +="ver"
            $replace +="release_"
            $replace +="release-"
            $replace +="release"
            $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)

            $Names = $Names.Where({ $null -ne $currentTask.Name })
            $Names = $Names.Where({ "" -ne $currentTask.Name })
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^rel/' -simplematch) {$_ -ireplace '^rel/',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) {$_ -ireplace '^v',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) {$_ -ireplace '^V',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) {$_ -ireplace '^r',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) {$_ -ireplace '^R',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '_' -simplematch) {$_ -ireplace '_',"."} else {$_}}

            # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

            if ($Names -ilike '*.*')
            {
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
            }
            else
            {
                $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
            }
            if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
        }
        catch{$NameLatest=""}
        if ($NameLatest -ne "")
        {
            if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
            {
                try
                {
                    if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
                catch{}
            }
            if ($UpdateAvailable -eq "")
            {
                if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
            }
        }
    }

    # Check UpdateAvailable by rubygems.org tags detection
    elseif ($Source0 -ilike '*rubygems.org*')
    {
        $Names=@()
        $replace=@()
        # Autogenerated SourceTagURL from Source0
        $SourceTagURLArray=($Source0).split("-")
        if ($SourceTagURLArray.length -gt 1)
        {
            $SourceTagURL = $SourceTagURLArray[0]
            for ($i=1;$i -lt ($SourceTagURLArray.length -1);$i++) { $SourceTagURL=$SourceTagURL + "-" + $SourceTagURLArray[$i] }
        }
        $replace = ($SourceTagURL -ireplace "/downloads/","/gems/")+"/versions"
        $replace = $replace -ireplace "http://","https://"
        $SourceTagURL=$replace +".atom"
        try{
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "token $accessToken")
            $Names = (invoke-restmethod -uri $SourceTagURL -TimeoutSec 10).id
            $Names = $Names  -replace $replace,""
            $Names = $Names  -replace '/',""

            $Names = $Names  -replace "-java",""
            $Names = $Names  -replace "-i386-mswin32",""
            $Names = $Names  -replace "-x86-mswin32",""
            $Names = $Names  -replace "-x64-mingw-ucrt",""
            $Names = $Names  -replace "-x86-mingw32",""
            $Names = $Names  -replace "-x64-mingw32",""
            $Names = $Names  -replace "-x86-linux",""
            $Names = $Names  -replace "-x86_64-linux",""
            $Names = $Names  -replace "-x86_64-darwin",""
            $Names = $Names  -replace "-arm64-darwin",""
            $Names = $Names  -replace "-arm-linux",""
            $Names = $Names  -replace "mswin32",""
            $Names = $Names  -replace "-aarch64-linux",""

            # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

            if ($Names -ilike '*.*')
            {
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
            }
            else
            {
                $NameLatest = ($Names | convertfrom-json | sort-object | select-object -last 1).ToString()
            }
            if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
        }
        catch{$NameLatest=""}
        if ($NameLatest -ne "")
        {
            if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
            {
                try
                {
                    if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
                catch{}
            }
            if ($UpdateAvailable -eq "")
            {
                if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
            }
        }
    }

    # Check UpdateAvailable by sourceforge tags detection
    elseif ($Source0 -ilike '*sourceforge.net*')
    {
        $Names=@()
        $replace=@()
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
        elseif ($currentTask.spec -ilike 'rng-tools.spec') {$SourceTagURL="https://sourceforge.net/projects/gkernel/files/rng-tools"}
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
            $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
            $headers.Add("Authorization", "token $accessToken")
            $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10) -split 'net.sf.files = {') -split "}};")[1] -split '{'
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
                    $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
                }
                $SourceTagURL="https://sourceforge.net/projects/libusb/files/libusb-"+$NameLatest
                $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10) -split 'net.sf.files = {') -split "}};")[1] -split '{'
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

            $replace += $currentTask.Name+"."
            $replace += $currentTask.Name+"-"
            $replace += $currentTask.Name+"_"
            $replace += $currentTask.Name
            $replace +="release_"
            $replace +="release-"
            $replace +="release"
            $replace +="ver"

            $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)

            # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

            if ($Names -ilike '*.*')
            {
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
            }
            else
            {
                $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
            }
            if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
        }
        catch{$NameLatest=""}
        if ($NameLatest -ne "")
        {
            if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
            {
                try
                {
                    if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
                catch{}
            }
            if ($UpdateAvailable -eq "")
            {
                if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
            }
        }
    }

    elseif ($Source0 -ilike '*https://pagure.io/*')
    {
        $Names = @()
        $replace=@()
        if ($currentTask.spec -ilike 'python-daemon.spec') {$SourceTagURL="https://pagure.io/python-daemon/releases"}

        if ($SourceTagURL -ne "")
        {
            try
            {
                if ([string]::IsNullOrEmpty($Names))
                {
                    $tmpName=$currentTask.Name
                    $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split '-release/') -split '.tar.gz"'
                }

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace +="ver"

                $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)
                $Names = $Names.Where({ $null -ne $currentTask.Name })
                $Names = $Names.Where({ "" -ne $currentTask.Name })
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) {$_ -ireplace '^v',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) {$_ -ireplace '^V',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) {$_ -ireplace '^r',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) {$_ -ireplace '^R',""} else {$_}}

                # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                if ($currentTask.spec -ilike 'atk.spec')
                {
                    $Names = $Names | foreach-object {$_.tolower().replace("_",".")}
                }

                if ($Names -ilike '*.*')
                {
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                }
                else
                {
                    $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
                }
                if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
                {
                    try
                    {
                        if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                        elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                        else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                    }
                    catch{}
                }
                if ($UpdateAvailable -eq "")
                {
                    if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
            }
        }
    }

    # Check UpdateAvailable by freedesktop tags detection
    elseif (($Source0 -ilike '*freedesktop.org*') -or ($Source0 -ilike '*https://gitlab.*'))
    {
        # Hardcoded SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
        $Names = @()
        $replace=@()
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

            $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -headers @{Authorization = "Bearer $accessToken"}) -split "<tr><td") -split 'a href=') -split '>'
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
        elseif ($currentTask.spec -ilike 'gstreamer.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gstreamer/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'ipcalc.spec') {$SourceTagURL="https://gitlab.com/ipcalc/ipcalc/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libslirp.spec') {$SourceTagURL="https://gitlab.freedesktop.org/slirp/libslirp/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libtiff.spec') {$SourceTagURL="https://gitlab.com/libtiff/libtiff/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libx11.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libx11/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libxinerama.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'man-db.spec') {$SourceTagURL="https://gitlab.com/man-db/man-db/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'mesa.spec') {$SourceTagURL="https://gitlab.freedesktop.org/mesa/mesa/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'mm-common.spec') {$SourceTagURL="https://gitlab.gnome.org/GNOME/mm-common/-/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'modemmanager.spec') {$SourceTagURL="https://gitlab.freedesktop.org/modemmanager/modemmanager/-/tags?format=atom"; $replace="-dev"}
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

        if ($SourceTagURL -ne "")
        {
            try{
                if ([string]::IsNullOrEmpty($Names))
                {
                    $Names = (invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing)
                    $Names = $Names.title
                }

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace +="ver"

                $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)
                $Names = $Names.Where({ $null -ne $currentTask.Name })
                $Names = $Names.Where({ "" -ne $currentTask.Name })
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) {$_ -ireplace '^v',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) {$_ -ireplace '^V',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) {$_ -ireplace '^r',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) {$_ -ireplace '^R',""} else {$_}}

                # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                if ($currentTask.spec -ilike 'atk.spec')
                {
                    $Names = $Names | foreach-object {$_.tolower().replace("_",".")}
                }

                if ($Names -ilike '*.*')
                {
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                }
                else
                {
                    $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
                }
                if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
                {
                    try
                    {
                        if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                        elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                        else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                    }
                    catch{}
                }
                if ($UpdateAvailable -eq "")
                {
                    if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
            }
        }
    }

    # Check UpdateAvailable by cpan tags detection
    elseif (($Source0 -ilike '*cpan.metacpan.org/authors*') -or ($Source0 -ilike '*search.cpan.org/CPAN/authors*') -or ($Source0 -ilike '*cpan.org/authors*'))
    {
        # Hardcoded SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
        $Names = @()
        $replace=@()
        # Autogenerated SourceTagURL from Source0
        $SourceTagURLArray=($Source0 ).split("/")
        if ($SourceTagURLArray.length -gt 0)
        {
            for ($i=1;$i -lt ($SourceTagURLArray.length -1);$i++)
            {
                if ($SourceTagURL -eq "") {$SourceTagURL = $SourceTagURLArray[$i]}
                else { $SourceTagURL=$SourceTagURL + "/" + $SourceTagURLArray[$i] }
            }
        }

        if ($SourceTagURL -ne "")
        {
            try{
                if ([string]::IsNullOrEmpty($Names))
                {
                    $Names = ((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10-usebasicparsing) -split 'a href=') -split '>'
                    $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                    $Names = $Names -replace '</a'
                }

                $Names = $Names  -replace ".tar.gz",""
                $Names = $Names  -replace ".tar.bz2",""
                $Names = $Names  -replace ".tar.xz",""
                $Names = $Names  -replace ".tar.lz",""

                if ($currentTask.spec -ilike '*perl-*.spec') { $replace +=  [system.string]::concat(($currentTask.Name -ireplace "perl-",""),"-")}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace +="ver"

                $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)
                $Names = $Names.Where({ $null -ne $currentTask.Name })
                $Names = $Names.Where({ "" -ne $currentTask.Name })
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) {$_ -ireplace '^v',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) {$_ -ireplace '^V',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) {$_ -ireplace '^r',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) {$_ -ireplace '^R',""} else {$_}}

                # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                if ($Names -ilike '*.*')
                {
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                }
                else
                {
                    $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
                }
                if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
                {
                    try
                    {
                        if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                        elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                        else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                    }
                    catch{}
                }
                if ($UpdateAvailable -eq "")
                {
                    if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
            }
        }
    }

    # Check UpdateAvailable by kernel.org tags detection
    elseif ($Source0 -ilike '*kernel.org*')
    {
        $Names=@()
        $replace=@()
        # Hardcoded SourceTagURL from Source0 because detection from Source0 url would have a worse ratio
        if ($currentTask.spec -ilike 'autofs.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/storage/autofs/autofs.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'blktrace.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/axboe/blktrace.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'bluez.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/bluetooth/bluez.git/refs"} #ausnahme
        elseif ($currentTask.spec -ilike 'bridge-utils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/network/bridge/bridge-utils.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'dtc.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/dtc/dtc.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'ethtool.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/network/ethtool/ethtool.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'fio.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'git.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/git/git.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'i2c-tools.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'iproute2.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/network/iproute2/iproute2.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'ipvsadm.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/kernel/ipvsadm/ipvsadm.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'kexec-tools.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'keyutils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'kmod.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libcap.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/libs/libcap/libcap.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libtraceevent.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'libtracefs.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git/refs/tags?format=atom"}
        elseif (($currentTask.spec -ilike 'linux-aws.spec') -or ($currentTask.spec -ilike 'linux-esx.spec') -or ($currentTask.spec -ilike 'linux-rt.spec') -or ($currentTask.spec -ilike 'linux-secure.spec') -or ($currentTask.spec -ilike 'linux.spec') -or ($currentTask.spec -ilike 'linux-api-headers.spec'))
        {
            if ($outputfile -ilike '*-3.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v4.x"; $replace +="linux-"}
            elseif ($outputfile -ilike '*-4.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v5.x"; $replace +="linux-"}
            elseif ($outputfile -ilike '*-5.0_*') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/v6.x"; $replace +="linux-"}
        }
        elseif ($currentTask.spec -ilike 'linux-firmware.spec') {$SourceTagURL="http://www.kernel.org/pub/linux/kernel/firmware"}
        elseif ($currentTask.spec -ilike 'man-pages.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'pciutils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/pciutils/pciutils.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'rt-tests.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'stalld.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/stalld/stalld.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'syslinux.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/boot/syslinux/syslinux.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'trace-cmd.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/utils/trace-cmd/trace-cmd.git/refs/tags?format=atom"; $replace +="v"}
        elseif ($currentTask.spec -ilike 'usbutils.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/linux/kernel/git/gregkh/usbutils.git/refs/tags?format=atom"}
        elseif ($currentTask.spec -ilike 'xfsprogs.spec') {$SourceTagURL="https://git.kernel.org/pub/scm/fs/xfs/xfsprogs-dev.git/refs/tags?format=atom"; $replace +="xfsprogs-dev-"; $replace +="v"}
        else
        {
            $SourceTagURL=(split-path $Source0 -Parent).Replace("\","/")
        }

        if ($SourceTagURL -ne "")
        {
            try{
                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $headers.Add("Authorization", "token $accessToken")
                $Names = (((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing -headers @{Authorization = "Bearer $accessToken"}) -split "<tr><td") -split 'a href=') -split '>'
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

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)
                $Names = $Names.Where({ $null -ne $currentTask.Name })
                $Names = $Names.Where({ "" -ne $currentTask.Name })
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^rel/' -simplematch) {$_ -ireplace '^rel/',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) {$_ -ireplace '^v',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) {$_ -ireplace '^V',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) {$_ -ireplace '^r',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) {$_ -ireplace '^R',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '_' -simplematch) {$_ -ireplace '_',"."} else {$_}}

                # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                $Names = $Names  -replace "v",""
                $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                # post check
                if (($currentTask.spec -ilike 'linux-aws.spec') -or ($currentTask.spec -ilike 'linux-esx.spec') -or ($currentTask.spec -ilike 'linux-rt.spec') -or ($currentTask.spec -ilike 'linux-secure.spec') -or ($currentTask.spec -ilike 'linux.spec') -or ($currentTask.spec -ilike 'linux-api-headers.spec'))
                {
                    if ($outputfile -ilike '*-3.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '4.19.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-4.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '5.10.' -simplematch) {$_}}}
                    elseif ($outputfile -ilike '*-5.0_*') {$Names = $Names | foreach-object { if ($_ | select-string -pattern '6.0' -simplematch) {$_}}}
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

                if ($Names -ilike '*.*')
                {
                    $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
                }
                else
                {
                    $NameLatest = ($Names | convertfrom-json | sort-object |select-object -last 1).ToString()
                }
                if (!($Names.contains($NameLatest))) { $NameLatest = ($Names | sort-object |select-object -last 1).ToString() }
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if (($NameLatest -ilike '*.*') -and ($version -ilike '*.*'))
                {
                    try
                    {
                        if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                        elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                        else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                    }
                    catch{}
                }
                if ($UpdateAvailable -eq "")
                {
                    if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
            }
        }
    }
    elseif (((urlhealth((split-path $Source0 -Parent).Replace("\","/"))) -eq "200") -or `
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
    ($currentTask.spec -ilike "sysstat.spec") -or `
    ($currentTask.spec -ilike "xmlsec1.spec"))
    {

        $SourceTagURL=(split-path $Source0 -Parent).Replace("\","/")

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
        if ($currentTask.spec -ilike "sysstat.spec") {$SourceTagURL="http://sebastien.godard.pagesperso-orange.fr/download.html"}
        if ($currentTask.spec -ilike "xmlsec1.spec") {$SourceTagURL="https://www.aleksey.com/xmlsec/download/"}
        $Names=@()
        $replace=@()
        $NameLatest=""
        try{ $Names = ((((invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -usebasicparsing) -split "<tr><td") -split 'a href=') -split '>') -split "title=" }
        catch
        {
            try
            {
                $session = New-Object Microsoft.PowerShell.Commands.WebRequestSession
                $session.UserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/113.0.0.0 Safari/537.36"
                $Names = Invoke-WebRequest -UseBasicParsing -Uri $SourceTagURL -TimeoutSec 10`
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
        if ($currentTask.spec -ilike "docbook-xml.spec")
        {
            $SourceTagURL="https://docbook.org/xml/"
            $objtmp=@()
            $objtmp = (invoke-webrequest -uri $SourceTagURL -TimeoutSec 10).Links.href
            $objtmp = $objtmp | foreach-object { if ($_ -match '\d') {$_}}
            $objtmp = $objtmp | foreach-object { if (!($_ | select-string -pattern 'CR' -simplematch)) {$_}}
            $objtmp = $objtmp | foreach-object { if (!($_ | select-string -pattern 'b' -simplematch)) {$_}}
            $Latest=([HeapSort]::Sort($objtmp) | select-object -last 1).tostring()
            $SourceTagURL = [system.string]::concat('https://docbook.org/xml/',$Latest)
            $objtmp = (invoke-webrequest -uri $SourceTagURL -TimeoutSec 10).Links.href
            $Names = $objtmp | foreach-object { if ($_ | select-string -pattern 'docbook-' -simplematch) {$_}}
            $Names = $Names  -replace "docbook-xml-",""
            $Names = $Names  -replace "docbook-",""
            $Names = $Names  -replace ".zip",""
        }
        if ($currentTask.spec -ilike "json-c.spec")
        {
            $Names = (invoke-webrequest -uri $SourceTagURL -UseBasicParsing -TimeoutSec 10) -split "<"
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
            elseif ($currentTask.spec -ilike "sysstat.spec") { $replace += "href=http://pagesperso-orange.fr/sebastien.godard/sysstat-"; $replace +='<a'; $replace+="moz-do-not-send=true" ; $Names = $Names -replace '\n',""}

            $replace += $currentTask.Name+"."
            $replace += $currentTask.Name+"-"
            $replace += $currentTask.Name+"_"
            $replace += $currentTask.Name
            $replace +="ver"
            $replace +="release_"
            $replace +="release-"
            $replace +="release"
            $i=0; do {$Names = $Names | foreach-object {$_.tolower().replace(($replace[$i]).tolower(),"")}; $i++} while ($i -ne $replace.count-1)

            $Names = $Names.Where({ $null -ne $currentTask.Name })
            $Names = $Names.Where({ "" -ne $currentTask.Name })
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^rel/' -simplematch) {$_ -ireplace '^rel/',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v' -simplematch) {$_ -ireplace '^v',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V' -simplematch) {$_ -ireplace '^V',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r' -simplematch) {$_ -ireplace '^r',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R' -simplematch) {$_ -ireplace '^R',""} else {$_}}
            $Names = $Names | foreach-object { if ($_ | select-string -pattern '_' -simplematch) {$_ -ireplace '_',"."} else {$_}}

            # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.beta' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1' -simplematch)) {$_}}
                $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.pre1' -simplematch)) {$_}}

                if ($currentTask.spec -notlike "tzdata.spec")
                {
                    $Names = $Names  -replace "v",""
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}
                }

            if ($Names -ilike '*.*')
            {
                $NameLatest = ($Names | foreach-object {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion} else {$tag}} | sort-object | select-object -last 1).ToString()
            }
            else
            {

                try
                {
                    $NameLatest=([HeapSort]::Sort($Names) | select-object -last 1).ToString()
                }
                catch{}
            }
        }
        if ($NameLatest -ne "")
        {
            if ((($NameLatest -ilike '*.*') -or (($NameLatest -match '^\d+$'))) -and ($version -ilike '*.*'))
            {
                try
                {
                    if ([System.Version]$version -lt [System.Version]$NameLatest) {$UpdateAvailable = $NameLatest}
                    elseif ([System.Version]$version -eq [System.Version]$NameLatest) {$UpdateAvailable = "(same version)" }
                    else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
                }
                catch{}
            }
            if ($UpdateAvailable -eq "")
            {
                if ($version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
                elseif ($version -eq $NameLatest) {$UpdateAvailable = "(same version)" }
                else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$NameLatest+" ." }
            }
        }

    }

    # Archived Github repo signalization
    $warning="Warning: repo isn't maintained anymore."
    if ($currentTask.Spec -ilike 'dhcp.spec') {$UpdateAvailable=$warning+" See "+ "https://www.isc.org/dhcp_migration/"}
    elseif ($currentTask.Spec -ilike 'python-argparse.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'python-atomicwrites.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'python-ipaddr.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'python-lockfile.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'python-subprocess32.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'python-terminaltables.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'confd.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'cve-check-tool.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'http-parser.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'fcgi.spec') {$UpdateAvailable=$warning+" See "+ "https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/%{version}.tar.gz ."}
    elseif ($currentTask.Spec -ilike 'libtar.spec') {$UpdateAvailable=$warning+" See "+ "https://sources.debian.org/patches/libtar"}
    elseif ($currentTask.Spec -ilike 'lightwave.spec') {$UpdateAvailable=$warning}

    $warning="Warning: Cannot detect correlating tags from the repo provided."
    if (($currentTask.Spec -ilike 'bluez-tools.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'containers-common.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'cpulimit.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'dcerpc.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'dotnet-sdk.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'dtb-raspberrypi.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'fuse-overlayfs-snapshotter.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'hawkey.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'libgsystem.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'libselinux.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'libsepol.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'libnss-ato.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'lightwave.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'likewise-open.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'linux-firmware.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'motd.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'netmgmt.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'pcstat.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'python-backports.ssl_match_hostname.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'python-iniparse.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'python-geomet.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'python-pyjsparser.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'python-ruamel-yaml.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning+"Also, see "+"https://github.com/commx/ruamel-yaml/archive/refs/tags/%{version}.tar.gz"}
    elseif (($currentTask.Spec -ilike 'rubygem-aws-sdk-s3.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'sqlite2.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
    elseif (($currentTask.Spec -ilike 'tornado.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}

    $warning="Warning: duplicate of python-pam.spec"
    if ($currentTask.Spec -ilike 'python-pycodestyle.spec') {$UpdateAvailable=$warning}

    $warning="Info: Source0 contains a VMware internal url address."
    if ($currentTask.Spec -ilike 'abupdate.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'ant-contrib.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'build-essential.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'ca-certificates.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'distrib-compat.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'docker-vsock.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'fipsify.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'grub2-theme.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'initramfs.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'minimal.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'photon-iso-config.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'photon-release.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'photon-repos.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'photon-upgrade.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'shim-signed.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'stig-hardening.spec') {$UpdateAvailable=$warning}

    $warning="Warning: Source0 seems invalid and no other Official source has been found."
    if ($currentTask.Spec -ilike 'cdrkit.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'crash.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'finger.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'ndsend.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'pcre.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'pypam.spec') {$UpdateAvailable=$warning}

    $warning="Info: Source0 contains a static version number."
    if ($currentTask.Spec -ilike 'autoconf213.spec') {$UpdateAvailable=$warning}
    elseif ($currentTask.Spec -ilike 'etcd-3.3.27.spec') {$UpdateAvailable=$warning}

    $warning="Info: Packaging format .bz2 has changed."
    if ($currentTask.Spec -ilike 'python-twisted.spec') {$UpdateAvailable=$warning}

    # reset to Source0 because of different packaging formats
    if ($currentTask.Spec -ilike 'psmisc.spec') {$Source0 = $currentTask.Source0}

    if (($UpdateAvailable -eq "") -and ($urlhealth -ne "200")) {$Source0=""}


    $versionedUpdateAvailable=""
    # Check in Fedora
    $SourceRPMFile=""
    $SourceRPMFileURL=""
    $SourceRPMFileURL=KojiFedoraProjectLookUp -ArtefactName $currentTask.Name
    if ($SourceRPMFileURL)
    {
        try {
            $DownloadPath=join-path $SourcePath "tmp"
            $SourceRPMFileName = ($SourceRPMFileURL -split '/')[-1]
            $SourceRPMFile = Join-Path $DownloadPath $SourceRPMFileName
            if (!(Test-Path $SourceRPMFile)) {
                try {
                    if (!(Test-Path $DownloadPath)) {New-Item $DownloadPath -ItemType Directory}
                    Invoke-WebRequest -Uri $SourceRPMFileURL -OutFile $SourceRPMFile -TimeoutSec 10
                }
                catch{$SourceRPMFile=""}
            }
            $ArtefactDownloadName=""
            $ArtefactVersion=""
            $tarCommand = "tar"
            if (-not (Get-Command $tarCommand -ErrorAction SilentlyContinue)) {
                Write-Error "tar command not found in runspace for $SourceRPMFile"
                return
            }
            try {
                $nestedFiles = @()
                $process = [System.Diagnostics.Process]::new()
                $process.StartInfo.FileName = $tarCommand
                $process.StartInfo.Arguments = "-tf `"$SourceRPMFile`""
                $process.StartInfo.RedirectStandardOutput = $true
                $process.StartInfo.UseShellExecute = $false
                $process.StartInfo.CreateNoWindow = $true

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
                        if (($nestedFile | select-string -pattern '.tar.gz' -simplematch))
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
                    if (!($ArtefactDownloadName | select-string -pattern $currentTask.Name -simplematch))
                    {
                        # not the same name, hence ignore this false positive
                        $ArtefactVersion=""
                        $ArtefactDownloadName=""
                    }
                    if ($ArtefactDownloadName -ne "")
                    {
                        $UpdateURL=([system.string]::concat($SourceRPMFileURL,"/",$ArtefactDownloadName))
                        $HealthUpdateURL="200"
                        if ($version -lt $ArtefactVersion) {$UpdateAvailable = $ArtefactVersion}
                        elseif ($version -eq $ArtefactVersion) {$UpdateAvailable = "(same version)" }
                        else {$UpdateAvailable = "Warning: "+$currentTask.spec+" Source0 version "+$version+" is higher than detected latest version "+$ArtefactVersion+" ." }
                    }
                }
            }
            catch {
                Write-Error "Failed to extract files from $SourceRPMFile"
                $ArtefactDownloadName=""
                $ArtefactVersion=""
            }
        }
        catch{}
    }


    if (!(($UpdateAvailable -ilike '*Warning*') -or ($UpdateAvailable -ilike '*Info*') -or ($UpdateAvailable -ilike '*same version*')))
    {
        $versionedUpdateAvailable=$UpdateAvailable
        if (($versionedUpdateAvailable -ne "") -and ($UpdateAvailable -ne ""))
        {
            if ($UpdateURL -eq "")
            {
                if ($currentTask.spec -ilike 'byacc.spec')
                {
                    $version = $version -ireplace "2.0.",""
                }

                if ($currentTask.spec -ilike 'docker.spec') { $Source0=[system.string]::concat("https://github.com/moby/moby/archive/refs/tags/v",$version,".tar.gz") }

                if ($currentTask.spec -ilike 'gtest.spec')
                {
                    $version = "release-" + $version
                    $UpdateAvailable ="v" + $UpdateAvailable
                }
                if ($currentTask.spec -ilike 'edgex.spec')
                {
                    $UpdateAvailable ="v" + $UpdateAvailable
                }
                if ($currentTask.spec -ilike 'icu.spec')
                {
                    $versionhiven=$UpdateAvailable.Replace(".","-")
                    $versionunderscore=$UpdateAvailable.Replace(".","_")
                    $Source0=[system.string]::concat("https://github.com/unicode-org/icu/releases/download/release-",$versionhiven,"/icu4c-",$versionunderscore,"-src.tgz")
                }
                if ($currentTask.spec -ilike 'libtirpc.spec') { $Source0=[system.string]::concat("https://downloads.sourceforge.net/project/libtirpc/libtirpc/",$version,"/libtirpc-",$version,".tar.bz2") }

                if (($currentTask.Source0 -ilike '*.tar.bz2*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".tar.bz2")}
                if (($currentTask.Source0 -ilike '*.tar.xz*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".tar.xz")}
                if (($currentTask.Source0 -ilike '*.tgz*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".tgz")}
                if (($currentTask.Source0 -ilike '*.zip*') -and ($Source0 -ilike '*.tar.gz*')) {$Source0=$Source0.replace(".tar.gz",".zip")}

                $versionshort=[system.string]::concat((($version).Split("."))[0],'.',(($version).Split("."))[1])
                $UpdateAvailableshort=[system.string]::concat((($UpdateAvailable).Split("."))[0],'.',(($UpdateAvailable).Split("."))[1])

                $UpdateURL=$Source0 -ireplace $version,$UpdateAvailable
                $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
                $HealthUpdateURL = urlhealth($UpdateURL)
                if ($HealthUpdateURL -ne "200")
                {
                    $UpdateURL=$Source0 -ireplace $version,([string]$UpdateAvailable).Replace(".","_")
                    $UpdateURL=$UpdateURL -ireplace $versionshort,$UpdateAvailableshort
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
                                    $warning="Warning: Manufacturer may changed version packaging format."
                                    $UpdateAvailable=$warning
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
    else
    {
        $UpdateURL=""
        $HealthUpdateURL=""
    }

    if ($HealthUpdateURL -eq "200")
    {
        $UpdateDownloadName = ($UpdateURL -split '/')[-1]

        if ($UpdateDownloadName[0] -eq 'v')
        {
            $UpdateDownloadName = $UpdateDownloadName.substring(1)
        }
        $tmpName=[string](((($UpdateDownloadName -replace ".tar.gz","") -replace ".tar.xz","") -replace ".tgz","") -replace ".tar.lz","") -replace ".tar.bz2",""
        if (!("$tmpName" -match '[A-Za-z]')) { $UpdateDownloadName = [System.String]::Concat($currentTask.Name,"-",$UpdateDownloadName) }

        # $tmpSHAName=$currentTask.SHAName
        # if ($tmpSHAName -ilike '*%{name}*') {$tmpSHAName=$currentTask.Name}

        # if ($UpdateDownloadName -inotlike [system.string]::concat('*',$tmpSHAName,'*')) { $UpdateDownloadName = [System.String]::Concat($tmpSHAName,"-",$UpdateDownloadName) }

        $SourcesNewDirectory=join-path $SourcePath $photonDir "SOURCES_NEW"
        if (!(Test-Path $SourcesNewDirectory)) {New-Item $SourcesNewDirectory -ItemType Directory}

        $UpdateDownloadFile=Join-Path -Path $SourcesNewDirectory -ChildPath $UpdateDownloadName
        if (Test-Path $UpdateDownloadFile) {}
        else
        {
            if ($SourceRPMFile -ne "") # Fedora case
            {
                try {
                    # Generate a unique temporary directory for each thread
                    $uniqueTmpPath = Join-Path -Path $SourcePath -ChildPath "tmp_$([System.Guid]::NewGuid().ToString())"
                    New-Item -Path $uniqueTmpPath -ItemType Directory -Force | Out-Null
                    & tar -xf $SourceRPMFile -C $uniqueTmpPath
                    $tmpContentPath = Join-Path -Path $uniqueTmpPath -ChildPath $UpdateDownloadName
                    if (test-path $tmpContentPath)
                    {
                        Move-Item -Path $tmpContentPath -Destination $SourcesNewDirectory -Force -Confirm:$false
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
                try { Invoke-WebRequest -Uri $UpdateURL -OutFile $UpdateDownloadFile -TimeoutSec 10}
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

                        Invoke-WebRequest -UseBasicParsing -Uri $UpdateURL -OutFile $UpdateDownloadFile -TimeoutSec 10`
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

        if ($currentTask.Spec -ilike 'openjdk8.spec') {ModifySpecFileOpenJDK8 -SpecFileName $currentTask.spec -SourcePath $SourcePath -PhotonDir $photonDir -Name $currentTask.name -Update $UpdateAvailable -UpdateDownloadFile $UpdateDownloadFile -DownloadNameWithoutExtension $currentTask.Name}
        else
        {ModifySpecFile -SpecFileName $currentTask.spec -SourcePath $SourcePath -PhotonDir $photonDir -Name $currentTask.name -Update $UpdateAvailable -UpdateDownloadFile $UpdateDownloadFile -DownloadNameWithoutExtension $currentTask.Name}
    }
    if ($SourceRPMFile -ne "") {
        if (Test-Path $SourceRPMFile) {
            Remove-Item -Path $SourceRPMFile -Force -ErrorAction SilentlyContinue
        }
    }
    $line=[System.String]::Concat($currentTask.spec, ',',$currentTask.source0,',',$Source0,',',$urlhealth,',',$UpdateAvailable,',',$UpdateURL,',',$HealthUpdateURL,',',$currentTask.Name,',',$currentTask.SHAName,',',$UpdateDownloadName)
    return $line
}


function GenerateUrlHealthReports {
    param (
        [string]$SourcePath,
        [string]$accessToken,
        [int]$OuterThrottleLimit,
        [int]$InnerThrottleLimit,
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
        Write-Output "Preparing data for Photon OS 3.0 ..."
        GitPhoton -release "3.0" -SourcePath $SourcePath
        $Packages3 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-3.0"
    }
    if ($GeneratePh4URLHealthReport) {
        Write-Output "Preparing data for Photon OS 4.0 ..."
        GitPhoton -release "4.0" -SourcePath $SourcePath
        $Packages4 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-4.0"
    }
    if ($GeneratePh5URLHealthReport) {
        Write-Output "Preparing data for Photon OS 5.0 ..."
        GitPhoton -release "5.0" -SourcePath $SourcePath
        $Packages5 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-5.0"
    }
    if ($GeneratePh6URLHealthReport) {
        Write-Output "Preparing data for Photon OS 6.0 ..."
        GitPhoton -release "6.0" -SourcePath $SourcePath
        $Packages6 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-6.0"
    }
    if ($GeneratePhCommonURLHealthReport) {
        Write-Output "Preparing data for Photon OS Common ..."
        GitPhoton -release "common" -SourcePath $SourcePath
        $PackagesCommon = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-common"
    }
    if ($GeneratePhDevURLHealthReport) {
        Write-Output "Preparing data for Photon OS Development ..."
        GitPhoton -release "dev" -SourcePath $SourcePath
        $PackagesDev = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-dev"
    }
    if ($GeneratePhMasterURLHealthReport) {
        Write-Output "Preparing data for Photon OS Master ..."
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

        # define variables locally for functions used in parallel tasks
        $CheckURLHealthDef = (Get-Command 'CheckURLHealth' -ErrorAction SilentlyContinue).Definition
        $KojiFedoraProjectLookUpDef = (Get-Command 'KojiFedoraProjectLookUp' -ErrorAction SilentlyContinue).Definition
        $ModifySpecFileDef = (Get-Command 'ModifySpecFile' -ErrorAction SilentlyContinue).Definition
        $ModifySpecFileOpenJDK8Def = (Get-Command 'ModifySpecFileOpenJDK8' -ErrorAction SilentlyContinue).Definition
        $Source0LookupDef = (Get-Command 'Source0Lookup' -ErrorAction SilentlyContinue).Definition
        $urlhealthDef = (Get-Command 'urlhealth' -ErrorAction SilentlyContinue).Definition


        if ($Script:UseParallel) {
            Write-Host "Starting parallel URL health report generation for applicable versions ..."
            $checkUrlHealthTasks | ForEach-Object -Parallel {
                # Capture the task config
                $TaskConfig = $_

                # define variables locally for functions used in parallel tasks
                $SourcePath = $using:SourcePath
                $accessToken = $using:AccessToken
                $OuterThrottleLimit = $using:OuterThrottleLimit
                $InnerThrottleLimit = $using:InnerThrottleLimit
                $CheckURLHealthDef = $using:CheckURLHealthDef
                $KojiFedoraProjectLookUpDef = $using:KojiFedoraProjectLookUpDef
                $ModifySpecFileDef = $using:ModifySpecFileDef
                $ModifySpecFileOpenJDK8Def = $using:ModifySpecFileOpenJDK8Def
                $Source0LookupDef = $using:Source0LookupDef
                $urlhealthDef = $using:urlhealthDef
                if ($CheckURLHealthDef) {
                    Invoke-Expression "function CheckURLHealth { $CheckURLHealthDef }"
                }
                if ($KojiFedoraProjectLookUpDef) {
                    Invoke-Expression "function KojiFedoraProjectLookUp { $KojiFedoraProjectLookUpDef }"
                }
                if ($ModifySpecFileDef) {
                    Invoke-Expression "function ModifySpecFile { $ModifySpecFileDef }"
                }
                if ($ModifySpecFileOpenJDK8Def) {
                    Invoke-Expression "function ModifySpecFileOpenJDK8 { $ModifySpecFileOpenJDK8Def }"
                }
                if ($Source0LookupDef) {
                    Invoke-Expression "function Source0Lookup { $Source0LookupDef }"
                }
                if ($urlhealthDef) {
                    Invoke-Expression "function urlhealth { $urlhealthDef }"
                }
                Write-Output "Generating URLHealth report for $($TaskConfig.Name) ..."
                $outputFileName = "photonos-urlhealth-$($TaskConfig.Release)_$((Get-Date).ToString("yyyyMMddHHmm"))"
                $outputFilePath = Join-Path -Path $SourcePath -ChildPath "$outputFileName.prn"


                # Collect results in memory to avoid file conflicts
                $results=@()
                $line= "Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName"
                $results += $line

                $results += $TaskConfig.Packages | ForEach-Object -Parallel {
                    $currentPackage=$_
                    # define variables locally for functions used in parallel tasks
                    $SourcePath = $using:SourcePath
                    $accessToken = $using:AccessToken
                    $OuterThrottleLimit = $using:OuterThrottleLimit
                    $InnerThrottleLimit = $using:InnerThrottleLimit
                    $CheckURLHealthDef = $using:CheckURLHealthDef
                    $KojiFedoraProjectLookUpDef = $using:KojiFedoraProjectLookUpDef
                    $ModifySpecFileDef = $using:ModifySpecFileDef
                    $ModifySpecFileOpenJDK8Def = $using:ModifySpecFileOpenJDK8Def
                    $Source0LookupDef = $using:Source0LookupDef
                    $urlhealthDef = $using:urlhealthDef
                    if ($CheckURLHealthDef) {
                        Invoke-Expression "function CheckURLHealth { $CheckURLHealthDef }"
                    }
                    if ($KojiFedoraProjectLookUpDef) {
                        Invoke-Expression "function KojiFedoraProjectLookUp { $KojiFedoraProjectLookUpDef }"
                    }
                    if ($ModifySpecFileDef) {
                        Invoke-Expression "function ModifySpecFile { $ModifySpecFileDef }"
                    }
                    if ($ModifySpecFileOpenJDK8Def) {
                        Invoke-Expression "function ModifySpecFileOpenJDK8 { $ModifySpecFileOpenJDK8Def }"
                    }
                    if ($Source0LookupDef) {
                        Invoke-Expression "function Source0Lookup { $Source0LookupDef }"
                    }
                    if ($urlhealthDef) {
                        Invoke-Expression "function urlhealth { $urlhealthDef }"
                    }
                    $outputFilePath = $using:outputFilePath
                    $photonDir = $using:TaskConfig.PhotonDir
                    # Use $using: to access variables from the parent scope
                    CheckURLHealth -currentTask $currentPackage -SourcePath $SourcePath -AccessToken $accessToken `
                        -outputfile $outputFilePath -photonDir $photonDir `
                        -KojiFedoraProjectLookUpDef $using:KojiFedoraProjectLookUpDef -ModifySpecFileDef $using:ModifySpecFileDef `
                        -ModifySpecFileOpenJDK8Def $using:ModifySpecFileOpenJDK8Def -Source0LookupDef $using:Source0LookupDef `
                        -urlhealthDef $using:urlhealthDef
                    Write-Host "Processing"$($currentPackage.Spec)"done."
                } -ThrottleLimit $InnerThrottleLimit

                $results | ForEach-Object { $_ | Out-File $outputFilePath -Append }
            } -ThrottleLimit $OuterThrottleLimit
        } else {
            # Fallback to sequential processing
            Write-Host "Starting sequential URL health report generation for applicable versions..."
            $checkUrlHealthTasks | ForEach-Object {
                $TaskConfig = $_
                Write-Output "Generating URLHealth report for $($TaskConfig.Name) ..."
                $outputFileName = "photonos-urlhealth-$($TaskConfig.Release)_$((Get-Date).ToString("yyyyMMddHHmm"))"
                $outputFilePath = Join-Path -Path $SourcePath -ChildPath "$outputFileName.prn"
                $results=@()
                $line="Spec"+","+"Source0 original"+","+"Modified Source0 for url health check"+","+"UrlHealth"+","+"UpdateAvailable"+","+"UpdateURL"+","+"HealthUpdateURL"+","+"Name"+","+"SHAName"+","+"UpdateDownloadName"
                $results += $line
                $results += $TaskConfig.Packages | ForEach-Object {
                    $currentPackage=$_
                    $photonDir = $TaskConfig.PhotonDir
                    # Use $using: to access variables from the parent scope
                    CheckURLHealth -currentTask $currentPackage -SourcePath $SourcePath -AccessToken $accessToken `
                        -outputfile $outputFilePath -photonDir $photonDir `
                        -KojiFedoraProjectLookUpDef $KojiFedoraProjectLookUpDef -ModifySpecFileDef $ModifySpecFileDef `
                        -ModifySpecFileOpenJDK8Def $ModifySpecFileOpenJDK8Def -Source0LookupDef $Source0LookupDef `
                        -urlhealthDef $urlhealthDef
                }
                $results | ForEach-Object { $_ | Out-File $outputFilePath -Append }
            }
        }
    }
    else {
        Write-Host "No URL health reports were enabled or no package data found."
    }
}


# path with all downloaded and unzipped branch directories of github.com/vmware/photon
$global:sourcepath="$env:public"
$Script:UseParallel = $PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 11
[int]$global:OuterThrottleLimit = 5          # New parameter for outer loop Tasks throttle
[int]$global:InnerThrottleLimit = 15         # New parameter for inner loop Packages throttle
$global:access = Read-Host -Prompt "Please enter your Github Access Token."
$GeneratePh3URLHealthReport=$true
$GeneratePh4URLHealthReport=$true
$GeneratePh5URLHealthReport=$true
$GeneratePh6URLHealthReport=$true
$GeneratePhCommonURLHealthReport=$true
$GeneratePhDevURLHealthReport=$true
$GeneratePhMasterURLHealthReport=$true

$GeneratePhPackageReport=$true

$GeneratePhCommontoPhMasterDiffHigherPackageVersionReport=$true
$GeneratePh5toPh6DiffHigherPackageVersionReport=$true
$GeneratePh4toPh5DiffHigherPackageVersionReport=$true
$GeneratePh3toPh4DiffHigherPackageVersionReport=$true

if (Get-Command git -ErrorAction SilentlyContinue) {}
else {
    Write-Output "Git not found. Trying to install ..."
    winget install --id Git.Git -e --source winget
    Write-Output "Please restart the script."
    exit
}

# Call the new function
$urlHealthPackageData = GenerateUrlHealthReports -SourcePath $global:sourcepath -AccessToken $global:access -OuterThrottleLimit $global:OuterThrottleLimit -InnerThrottleLimit $global:InnerThrottleLimit `
    -GeneratePh3URLHealthReport $GeneratePh3URLHealthReport `
    -GeneratePh4URLHealthReport $GeneratePh4URLHealthReport `
    -GeneratePh5URLHealthReport $GeneratePh5URLHealthReport `
    -GeneratePh6URLHealthReport $GeneratePh6URLHealthReport `
    -GeneratePhCommonURLHealthReport $GeneratePhCommonURLHealthReport `
    -GeneratePhDevURLHealthReport $GeneratePhDevURLHealthReport `
    -GeneratePhMasterURLHealthReport $GeneratePhMasterURLHealthReport


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
    write-output "Generating Package Report ..."
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
    write-output "Generating difference report of common packages with a higher version than same master package ..."
    $outputfile1="$env:public\photonos-diff-report-common-master_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-common"+","+"photon-master"| out-file $outputfile1
    $result | foreach-object {
        # write-output $currentTask.spec
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
    write-output "Generating difference report of 5.0 packages with a higher version than same 6.0 package ..."
    $outputfile1="$env:public\photonos-diff-report-5.0-6.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-5.0"+","+"photon-6.0"| out-file $outputfile1
    $result | foreach-object {
        # write-output $currentTask.spec
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
    write-output "Generating difference report of 4.0 packages with a higher version than same 5.0 package ..."
    $outputfile1="$env:public\photonos-diff-report-4.0-5.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-4.0"+","+"photon-5.0"| out-file $outputfile1
    $result | foreach-object {
        # write-output $currentTask.spec
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
    write-output "Generating difference report of 3.0 packages with a higher version than same 4.0 package ..."
    $outputfile2="$env:public\photonos-diff-report-3.0-4.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-3.0"+","+"photon-4.0"| out-file $outputfile2
    $result | foreach-object {
        # write-output $currentTask.spec
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
