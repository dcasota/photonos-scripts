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
#   0.60  11.02.2026   dcasota  Add timeout handling for git operations to prevent hanging parallel processes
#
#  .PREREQUISITES
#    - Script tested on Microsoft Windows 11
#    - Powershell: Minimal version: 5.1
#                  Recommended version: 7.4 or higher for parallel processing capabilities
#

[CmdletBinding()]
param (
    [string]$access=$env:GITHUB_TOKEN,
    [string]$gitlabacess=$env:GITLAB_TOKEN,
    [string]$sourcepath = $env:PUBLIC,
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

# Helper function to run git commands with timeout
function Invoke-GitWithTimeout {
    param(
        [string]$Arguments,
        [string]$WorkingDirectory = (Get-Location).Path,
        [int]$TimeoutSeconds = 60
    )
    
    try {
        $job = Start-Job -ScriptBlock {
            param($argString, $wd)
            Set-Location $wd
            $cmd = "git $argString"
            $output = Invoke-Expression $cmd 2>&1
            return $output
        } -ArgumentList $Arguments, $WorkingDirectory
        
        $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
        if ($completed) {
            $result = Receive-Job -Job $job
            Remove-Job -Job $job -Force
            return $result
        } else {
            Stop-Job -Job $job -Force
            Remove-Job -Job $job -Force
            Write-Warning "Git command timed out after $TimeoutSeconds seconds: git $Arguments"
            throw "Git operation timed out"
        }
    }
    catch {
        Write-Warning "Git command failed: git $Arguments - Error: $_"
        throw
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

            $Packages +=[PSCustomObject]@{
                content = $content
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
            Invoke-GitWithTimeout "clone -b $release https://github.com/vmware/photon `"$photonPath`"" -WorkingDirectory $SourcePath -TimeoutSeconds 300
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
            Invoke-GitWithTimeout "fetch" -WorkingDirectory $photonPath -TimeoutSeconds 120
            if ($release -ieq "master") { Invoke-GitWithTimeout "merge origin/master" -WorkingDirectory $photonPath -TimeoutSeconds 60 }
            elseif ($release -ieq "dev") { Invoke-GitWithTimeout "merge origin/dev" -WorkingDirectory $photonPath -TimeoutSeconds 60 }
            elseif ($release -ieq "common") { Invoke-GitWithTimeout "merge origin/common" -WorkingDirectory $photonPath -TimeoutSeconds 60 }
            else { Invoke-GitWithTimeout "merge origin/$release" -WorkingDirectory $photonPath -TimeoutSeconds 60 }
        }
        catch {
            Write-Warning "Failed to update photon-$release repository: $_"
        }
    }
}

function Source0Lookup {
$Source0LookupData=@'
specfile,Source0Lookup,gitSource,gitBranch,customRegex,replaceStrings,ignoreStrings
alsa-lib.spec,https://www.alsa-project.org/files/pub/lib/alsa-lib-%{version}.tar.bz2
alsa-utils.spec,https://www.alsa-project.org/files/pub/utils/alsa-utils-%{version}.tar.bz2
amdvlk.spec,https://github.com/GPUOpen-Drivers/AMDVLK/archive/refs/tags/v-%{version}.tar.gz,https://github.com/GPUOpen-Drivers/AMDVLK.git,,,"v-"
ansible.spec,https://github.com/ansible/ansible/archive/refs/tags/v%{version}.tar.gz,https://github.com/ansible/ansible.git
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
autogen.spec,https://ftp.gnu.org/gnu/autogen/rel5.18.16/autogen-5.18.16.tar.xz
autofs.spec,,https://git.kernel.org/pub/scm/linux/storage/autofs/autofs.git
automake.spec,https://github.com/autotools-mirror/automake/archive/refs/tags/v%{version}.tar.gz,https://github.com/autotools-mirror/automake.git
backward-cpp.spec,https://github.com/bombela/backward-cpp/archive/refs/tags/v%{version}.tar.gz,https://github.com/bombela/backward-cpp.git
bindutils.spec,https://github.com/isc-projects/bind9/archive/refs/tags/v%{version}.tar.gz,https://github.com/isc-projects/bind9.git,,,"wpk-get-rid-of-up-downgrades-,noadaptive,more-adaptive,adaptive"
blktrace.spec,,https://git.kernel.org/pub/scm/linux/kernel/git/axboe/blktrace.git,master
bluez.spec,https://www.kernel.org/pub/linux/bluetooth/bluez-%{version}.tar.xz,https://git.kernel.org/pub/scm/bluetooth/bluez.git,,,
boost.spec,https://github.com/boostorg/boost/archive/refs/tags/boost-%{version}.tar.gz,https://github.com/boostorg/boost.git
bridge-utils.spec,,https://git.kernel.org/pub/scm/network/bridge/bridge-utils.git
btrfs-progs.spec,https://github.com/kdave/btrfs-progs/archive/refs/tags/v%{version}.tar.gz,https://github.com/kdave/btrfs-progs.git
bubblewrap.spec,https://github.com/containers/bubblewrap/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/bubblewrap.git
bzip2.spec,https://github.com/libarchive/bzip2/archive/refs/tags/bzip2-%{version}.tar.gz,https://github.com/libarchive/bzip2.git
c-ares.spec,https://github.com/c-ares/c-ares/archive/refs/tags/cares-%{version}.tar.gz,https://github.com/c-ares/c-ares.git
cairo.spec,https://gitlab.freedesktop.org/cairo/cairo/-/archive/%{version}/cairo-%{version}.tar.gz,https://gitlab.freedesktop.org/cairo/cairo.git
calico-confd.spec,https://github.com/kelseyhightower/confd/archive/refs/tags/v%{version}.tar.gz,https://github.com/kelseyhightower/confd.git
cassandra.spec,https://github.com/apache/cassandra/archive/refs/tags/cassandra-%{version}.tar.gz,https://github.com/apache/cassandra.git
cifs-utils.spec,https://download.samba.org/pub/linux-cifs/cifs-utils/cifs-utils-%{version}.tar.bz2,git://git.samba.org/cifs-utils.git
chkconfig.spec,https://github.com/fedora-sysv/chkconfig/archive/refs/tags/%{version}.tar.gz,https://github.com/fedora-sysv/chkconfig.git
chrony.spec,https://github.com/mlichvar/chrony/archive/refs/tags/%{version}.tar.gz,https://github.com/mlichvar/chrony.git
chrpath.spec,https://codeberg.org/pere/chrpath/archive/release-%{version}.tar.gz,https://codeberg.org/pere/chrpath.git
clang.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/clang-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git,,,"llvmorg-"
cloud-init.spec,https://github.com/canonical/cloud-init/archive/refs/tags/%{version}.tar.gz,https://github.com/canonical/cloud-init.git
cloud-utils.spec,https://github.com/canonical/cloud-utils/archive/refs/tags/%{version}.tar.gz,https://github.com/canonical/cloud-utils.git
cmake.spec,https://github.com/Kitware/CMake/releases/download/v%{version}/cmake-%{version}.tar.gz,https://github.com/Kitware/CMake.git
cmocka.spec,https://git.cryptomilk.org/projects/cmocka.git/snapshot/cmocka-%{version}.tar.xz,https://git.cryptomilk.org/projects/cmocka.git/
commons-daemon.spec,https://github.com/apache/commons-daemon/archive/refs/tags/commons-daemon-%{version}.tar.gz,https://github.com/apache/commons-daemon.git
compat-gdbm.spec,https://ftp.gnu.org/gnu/gdbm/gdbm-%{version}.tar.gz
confd.spec,https://github.com/projectcalico/confd/archive/refs/tags/v%{version}-0.dev.tar.gz,https://github.com/projectcalico/confd.git
conmon.spec,https://github.com/containers/conmon/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/conmon.git
connect-proxy.spec,,https://src.fedoraproject.org/rpms/connect-proxy.git,rawhide
conntrack-tools.spec,https://www.netfilter.org/projects/conntrack-tools/files/conntrack-tools-%{version}.tar.bz2
containers-common.spec,https://github.com/containers/common/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/common.git
coredns.spec,https://github.com/coredns/coredns/archive/refs/tags/v%{version}.tar.gz,https://github.com/coredns/coredns.git
cracklib.spec,https://github.com/cracklib/cracklib/archive/refs/tags/v%{version}.tar.gz,https://github.com/cracklib/cracklib.git
cri-tools.spec,https://github.com/kubernetes-sigs/cri-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/kubernetes-sigs/cri-tools.git
cryptsetup.spec,https://github.com/mbroz/cryptsetup/archive/refs/tags/v%{version}.tar.gz,https://github.com/mbroz/cryptsetup.git
cups.spec,https://github.com/OpenPrinting/cups/archive/refs/tags/v%{version}.tar.gz,https://github.com/OpenPrinting/cups.git
cve-check-tool.spec,https://github.com/clearlinux/cve-check-tool/archive/refs/tags/v%{version}.tar.gz,https://github.com/clearlinux/cve-check-tool.git
cyrus-sasl.spec,https://github.com/cyrusimap/cyrus-sasl/archive/refs/tags/cyrus-sasl-%{version}.tar.gz,https://github.com/cyrusimap/cyrus-sasl.git
cython3.spec,https://github.com/cython/cython/archive/refs/tags/%{version}.tar.gz,https://github.com/cython/cython.git
dbus.spec,,https://gitlab.freedesktop.org/dbus/dbus.git
dbus-glib.spec,,https://gitlab.freedesktop.org/dbus/dbus-glib.git
dbus-python.spec,,https://gitlab.freedesktop.org/dbus/dbus-python.git
ddclient.spec,https://github.com/ddclient/ddclient/releases/download/v%{version}/ddclient-%{version}.tar.gz,https://github.com/ddclient/ddclient.git
device-mapper-multipath.spec,https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz,https://github.com/opensvc/multipath-tools.git
device-mapper-multipath.spec,https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz,https://github.com/opensvc/multipath-tools.git
dialog.spec,https://invisible-island.net/archives/dialog/dialog-%{version}.tgz
dtc.spec,https://www.kernel.org/pub/software/utils/%{name}/%{name}-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/dtc/dtc.git
docbook-xml.spec,https://docbook.org/xml/%{version}/docbook-%{version}.zip
docker.spec,https://github.com/moby/moby/archive/refs/tags/v%{version}.tar.gz,https://github.com/moby/moby.git
docker-20.10.spec,https://github.com/moby/moby/archive/refs/tags/v%{version}.tar.gz,https://github.com/moby/moby.git
docker-pycreds.spec,https://github.com/shin-/dockerpy-creds/archive/refs/tags/%{version}.tar.gz,https://github.com/shin-/dockerpy-creds.git
dotnet-runtime.spec,https://github.com/dotnet/runtime/archive/refs/tags/v%{version}.tar.gz,https://github.com/dotnet/runtime.git
dotnet-sdk.spec,https://github.com/dotnet/sdk/archive/refs/tags/v%{version}.tar.gz,https://github.com/dotnet/sdk.git
doxygen.spec,https://github.com/doxygen/doxygen/archive/refs/tags/Release_%{version}.tar.gz,https://github.com/doxygen/doxygen.git
dracut.spec,https://github.com/dracutdevs/dracut/archive/refs/tags/%{version}.tar.gz,https://github.com/dracutdevs/dracut.git,,,,"033-502"
duktape.spec,https://github.com/svaarala/duktape/archive/refs/tags/v%{version}.tar.gz,https://github.com/svaarala/duktape.git
ebtables.spec,https://www.netfilter.org/pub/ebtables/ebtables-%{version}.tar.gz
ecdsa.spec,https://github.com/tlsfuzzer/python-ecdsa/archive/refs/tags/python-ecdsa-%{version}.tar.gz,https://github.com/tlsfuzzer/python-ecdsa.git
ed.spec,https://ftp.gnu.org/gnu/ed/ed-%{version}.tar.lz
efibootmgr.spec,https://github.com/rhboot/efibootmgr/archive/refs/tags/%{version}.tar.gz,https://github.com/rhboot/efibootmgr.git
emacs.spec,https://ftp.gnu.org/gnu/emacs/emacs-%{version}.tar.xz
erlang.spec,https://github.com/erlang/otp/archive/refs/tags/OTP-%{version}.tar.gz,https://github.com/erlang/otp.git,,erlang,"R16B,OTP-,erl_1211-bp"
erlang-sd_notify.spec,https://github.com/systemd/erlang-sd_notify/archive/refs/tags/v%{version}.tar.gz,https://github.com/systemd/erlang-sd_notify.git
ethtool.spec,https://git.kernel.org/pub/scm/network/ethtool/ethtool.git/snapshot/ethtool-%{version}.tar.gz,https://git.kernel.org/pub/scm/network/ethtool/ethtool.git
fatrace.spec,https://github.com/martinpitt/fatrace/archive/refs/tags/%{version}.tar.gz,https://github.com/martinpitt/fatrace.git
file.spec,http://ftp.astron.com/pub/file/file-%{version}.tar.gz
fio.spec,https://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git/snapshot/%{name}-%{version}.tar.gz,https://git.kernel.org/pub/scm/linux/kernel/git/axboe/fio.git
flex.spec,https://github.com/westes/flex/archive/refs/tags/v%{version}.tar.gz,https://github.com/westes/flex.git
fontconfig.spec,,https://gitlab.freedesktop.org/fontconfig/fontconfig.git
fping.spec,https://github.com/schweikert/fping/archive/refs/tags/v%{version}.tar.gz,https://github.com/schweikert/fping.git
freetds.spec,https://github.com/FreeTDS/freetds/archive/refs/tags/v%{version}.tar.gz,https://github.com/FreeTDS/freetds.git
fribidi.spec,https://github.com/fribidi/fribidi/archive/refs/tags/v%{version}.tar.gz,https://github.com/fribidi/fribidi.git
fuse-overlayfs-snapshotter.spec,https://github.com/containers/fuse-overlayfs/archive/refs/tags/v%{version}.tar.gz,https://github.com/containers/fuse-overlayfs.git
gdk-pixbuf.spec,https://github.com/GNOME/gdk-pixbuf/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gdk-pixbuf.git
geos.spec,https://github.com/libgeos/geos/archive/refs/tags/%{version}.tar.gz,https://github.com/libgeos/geos.git
getdns.spec,https://github.com/getdnsapi/getdns/archive/refs/tags/v%{version}.tar.gz,https://github.com/getdnsapi/getdns.git
git.spec,https://www.kernel.org/pub/software/scm/git/%{name}-%{version}.tar.xz,https://git.kernel.org/pub/scm/git/git.git
glib.spec,https://github.com/GNOME/glib/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/glib.git
glibmm.spec,https://github.com/GNOME/glibmm/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/glibmm.git
glib-networking.spec,https://github.com/GNOME/glib-networking/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/glib-networking.git
gnome-common.spec,https://download.gnome.org/sources/gnome-common/3.18/gnome-common-%{version}.tar.xz
gnupg.spec,https://github.com/gpg/gnupg/archive/refs/tags/gnupg-%{version}.tar.gz,https://github.com/gpg/gnupg.git
gnuplot.spec,https://github.com/gnuplot/gnuplot/archive/refs/tags/%{version}.tar.gz,https://github.com/gnuplot/gnuplot.git
gnutls.spec,https://github.com/gnutls/gnutls/archive/refs/tags/%{version}.tar.gz,https://github.com/gnutls/gnutls.git
go.spec,https://github.com/golang/go/archive/refs/tags/go%{version}.tar.gz,https://github.com/golang/go.git
gobject-introspection.spec,https://github.com/GNOME/gobject-introspection/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gobject-introspection.git
graphene.spec,https://github.com/ebassi/graphene/archive/refs/tags/%{version}.tar.gz,https://github.com/ebassi/graphene.git
gst-plugins-bad.spec,,https://gitlab.freedesktop.org/gstreamer/gst-plugins-bad.git
gstreamer.spec,,https://gitlab.freedesktop.org/gstreamer/gstreamer.git
gstreamer-plugins-base.spec,https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-%{version}.tar.xz,https://gitlab.freedesktop.org/gstreamer/gstreamer.git,,gst-plugins-base-
gtest.spec,https://github.com/google/googletest/archive/refs/tags/release-%{version}.tar.gz,https://github.com/google/googletest.git
gtk3.spec,https://github.com/GNOME/gtk/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/gtk.git
guile.spec,https://ftp.gnu.org/gnu/guile/guile-%{version}.tar.gz
haproxy.spec,https://www.haproxy.org/download/2.2/src/haproxy-%{version}.tar.gz
haproxy-dataplaneapi.spec,https://github.com/haproxytech/dataplaneapi/archive/refs/tags/v%{version}.tar.gz,https://github.com/haproxytech/dataplaneapi.git
harfbuzz.spec,,https://github.com/harfbuzz/harfbuzz.git
haveged.spec,https://github.com/jirka-h/haveged/archive/refs/tags/v%{version}.tar.gz,https://github.com/jirka-h/haveged.git
hawkey.spec,https://github.com/rpm-software-management/hawkey/archive/refs/tags/hawkey-%{version}.tar.gz,https://github.com/rpm-software-management/hawkey.git
httpd.spec,https://github.com/apache/httpd/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/httpd.git
httpd-mod_jk.spec,https://github.com/apache/tomcat-connectors/archive/refs/tags/JK_%{version}.tar.gz,https://github.com/apache/tomcat-connectors.git,,,"JK_"
http-parser.spec,https://github.com/nodejs/http-parser/archive/refs/tags/v%{version}.tar.gz,https://github.com/nodejs/http-parser.git
i2c-tools.spec,https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git/snapshot/i2c-tools-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/i2c-tools/i2c-tools.git
icu.spec,https://github.com/unicode-org/icu/releases/download/release-73-1/icu4c-73_1-src.tgz,https://github.com/unicode-org/icu.git
imagemagick.spec,https://github.com/ImageMagick/ImageMagick/archive/refs/tags/%{version}.tar.gz,https://github.com/ImageMagick/ImageMagick.git
inih.spec,https://github.com/benhoyt/inih/archive/refs/tags/r%{version}.tar.gz,https://github.com/benhoyt/inih.git,,,"r"
intltool.spec,https://launchpad.net/intltool/trunk/%{version}/+download/intltool-%{version}.tar.gz
ipcalc.spec,https://gitlab.com/ipcalc/ipcalc/-/archive/%{version}/ipcalc-%{version}.tar.gz,https://gitlab.com/ipcalc/ipcalc.git
ipmitool.spec,https://github.com/ipmitool/ipmitool/archive/refs/tags/IPMITOOL_%{version}.tar.gz,https://github.com/ipmitool/ipmitool.git
iproute2.spec,,https://git.kernel.org/pub/scm/network/iproute2/iproute2.git,,,
ipset.spec,https://ipset.netfilter.org/ipset-%{version}.tar.bz2
iptables.spec,https://www.netfilter.org/projects/iptables/files/iptables-%{version}.tar.xz
iputils.spec,https://github.com/iputils/iputils/archive/refs/tags/s%{version}.tar.gz,https://github.com/iputils/iputils.git
ipvsadm.spec,,https://git.kernel.org/pub/scm/utils/kernel/ipvsadm/ipvsadm.git
ipxe.spec,https://github.com/ipxe/ipxe/archive/refs/tags/v%{version}.tar.gz,https://github.com/ipxe/ipxe.git
jansson.spec,https://github.com/akheron/jansson/archive/refs/tags/v%{version}.tar.gz,https://github.com/akheron/jansson.git
json-glib.spec,https://github.com/GNOME/json-glib/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/json-glib.git
kafka.spec,https://github.com/apache/kafka/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/kafka.git,,,"0.10.2.0-KAFKA-5526"
kbd.spec,https://github.com/legionus/kbd/archive/refs/tags/%{version}.tar.gz,https://github.com/legionus/kbd.git
keepalived.spec,https://github.com/acassen/keepalived/archive/refs/tags/v%{version}.tar.gz,https://github.com/acassen/keepalived.git
kexec-tools.spec,https://www.kernel.org/pub/linux/utils/kernel/kexec/kexec-tools-%{version}.tar.xz,https://git.kernel.org/pub/scm/utils/kernel/kexec/kexec-tools.git
keyutils.spec,https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-%{version}.tar.gz,https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git
kmod.spec,,https://git.kernel.org/pub/scm/utils/kernel/kmod/kmod.git,,,
krb5.spec,https://github.com/krb5/krb5/archive/refs/tags/krb5-%{version}-final.tar.gz,https://github.com/krb5/krb5.git
lapack.spec,https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v%{version}.tar.gz,https://github.com/Reference-LAPACK/lapack.git
lasso.spec,https://dev.entrouvert.org/lasso/lasso-%{version}.tar.gz
libldb.spec,https://gitlab.com/samba-team/devel/samba/-/archive/ldb-%{version}/samba-ldb-%{version}.tar.gz
less.spec,https://github.com/gwsw/less/archive/refs/tags/v%{version}.tar.gz,https://github.com/gwsw/less.git
leveldb.spec,https://github.com/google/leveldb/archive/refs/tags/v%{version}.tar.gz,https://github.com/google/leveldb.git
libarchive.spec,https://github.com/libarchive/libarchive/archive/refs/tags/v%{version}.tar.gz,https://github.com/libarchive/libarchive.git
libatomic_ops.spec,https://github.com/ivmai/libatomic_ops/archive/refs/tags/v%{version}.tar.gz,https://github.com/ivmai/libatomic_ops.git
libcap.spec,,https://git.kernel.org/pub/scm/libs/libcap/libcap.git
libconfig.spec,https://github.com/hyperrealm/libconfig/archive/refs/tags/v%{version}.tar.gz,https://github.com/hyperrealm/libconfig.git
libdb.spec,https://github.com/berkeleydb/libdb/archive/refs/tags/v%{version}.tar.gz,https://github.com/berkeleydb/libdb.git
libdrm.spec,https://gitlab.freedesktop.org/mesa/libdrm/-/archive/libdrm-%{version}/libdrm-libdrm-%{version}.tar.gz,https://gitlab.freedesktop.org/mesa/libdrm.git
libedit.spec,https://www.thrysoee.dk/editline/libedit-20221030-3.1.tar.gz
libestr.spec,https://github.com/rsyslog/libestr/archive/refs/tags/v%{version}.tar.gz,https://github.com/rsyslog/libestr.git
libev.spec,http://dist.schmorp.de/libev/Attic/libev-%{version}.tar.gz
libffi.spec,https://github.com/libffi/libffi/archive/refs/tags/v%{version}.tar.gz,https://github.com/libffi/libffi.git
libgcrypt.spec,https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-%{version}.tar.bz2
libglvnd.spec,https://github.com/NVIDIA/libglvnd/archive/refs/tags/v%{version}.tar.gz,https://github.com/NVIDIA/libglvnd.git
libgpg-error.spec,https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-%{version}.tar.bz2
libgudev.spec,https://github.com/GNOME/libgudev/archive/refs/tags/%{version}.tar.gz
liblogging.spec,https://github.com/rsyslog/liblogging/archive/refs/tags/v%{version}.tar.gz
libjpeg-turbo.spec,https://github.com/libjpeg-turbo/libjpeg-turbo/archive/refs/tags/%{version}.tar.gz
libmbim.spec,https://gitlab.freedesktop.org/mobile-broadband/libmbim/-/archive/%{version}/libmbim-%{version}.tar.gz,https://gitlab.freedesktop.org/mobile-broadband/libmbim.git
libmetalink.spec,https://launchpad.net/libmetalink/trunk/libmetalink-%{version}/+download/libmetalink-%{version}.tar.bz2
libmnl.spec,https://netfilter.org/projects/libmnl/files/libmnl-%{version}.tar.bz2
libmspack.spec,https://github.com/kyz/libmspack/archive/refs/tags/v%{version}.tar.gz
libnetfilter_conntrack.spec,https://netfilter.org/projects/libnetfilter_conntrack/files/libnetfilter_conntrack-%{version}.tar.bz2
libnetfilter_cthelper.spec,https://netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-%{version}.tar.bz2
libnetfilter_cttimeout.spec,https://netfilter.org/projects/libnetfilter_cttimeout/files/libnetfilter_cttimeout-%{version}.tar.bz2
libnetfilter_queue.spec,https://netfilter.org/projects/libnetfilter_queue/files/libnetfilter_queue-%{version}.tar.bz2
libnfnetlink.spec,https://netfilter.org/projects/libnfnetlink/files/libnfnetlink-%{version}.tar.bz2
libnftnl.spec,https://netfilter.org/projects/libnftnl/files/libnftnl-%{version}.tar.xz
libnl.spec,https://github.com/thom311/libnl/archive/refs/tags/libnl%{version}.tar.gz,https://github.com/thom311/libnl.git
librelp.spec,https://download.rsyslog.com/librelp/librelp-%{version}.tar.gz
librsync.spec,https://github.com/librsync/librsync/archive/refs/tags/v%{version}.tar.gz,https://github.com/librsync/librsync.git
libpcap.spec,https://github.com/the-tcpdump-group/libpcap/archive/refs/tags/libpcap-%{version}.tar.gz,https://github.com/the-tcpdump-group/libpcap.git
libqmi.spec,,https://gitlab.freedesktop.org/mobile-broadband/libqmi.git
libselinux.spec,https://github.com/SELinuxProject/selinux/archive/refs/tags/libselinux-%{version}.tar.gz,https://github.com/SELinuxProject/selinux.git
libsigc++.spec,https://github.com/libsigcplusplus/libsigcplusplus/archive/refs/tags/%{version}.tar.gz,https://github.com/libsigcplusplus/libsigcplusplus.git
libslirp.spec,https://gitlab.freedesktop.org/slirp/libslirp/-/archive/v%{version}/libslirp-v%{version}.tar.gz,https://gitlab.freedesktop.org/slirp/libslirp.git
libsoup.spec,https://github.com/GNOME/libsoup/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/libsoup.git
libssh2.spec,https://github.com/libssh2/libssh2/archive/refs/tags/libssh2-%{version}.tar.gz,https://github.com/libssh2/libssh2.git
libtalloc.spec,https://gitlab.com/samba-team/devel/samba/-/archive/talloc-%{version}/talloc-%{version}.tar.gz
libtar.spec,https://github.com/tklauser/libtar/archive/refs/tags/v%{version}.tar.gz,https://github.com/tklauser/libtar.git
libtdb.spec,https://gitlab.com/samba-team/devel/samba/-/archive/tdb-%{version}/tdb-%{version}.tar.gz
libtevent.spec,https://gitlab.com/samba-team/devel/samba/-/archive/tevent-%{version}/tevent-%{version}.tar.gz
libteam.spec,https://github.com/jpirko/libteam/archive/refs/tags/v%{version}.tar.gz,https://github.com/jpirko/libteam.git
libtiff.spec,,https://gitlab.com/libtiff/libtiff.git
libtraceevent.spec,,https://git.kernel.org/pub/scm/libs/libtrace/libtraceevent.git
libtracefs.spec,,https://git.kernel.org/pub/scm/libs/libtrace/libtracefs.git
libvirt.spec,https://github.com/libvirt/libvirt/archive/refs/tags/v%{version}.tar.gz,https://github.com/libvirt/libvirt.git
libX11.spec,https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-%{version}/libx11-libX11-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libx11.git
libx11.spec,https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-%{version}/libx11-libX11-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libx11.git
libxcb.spec,https://gitlab.freedesktop.org/xorg/lib/libxcb/-/archive/libxcb-%{version}/libxcb-libxcb-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libxcb.git
libxkbcommon.spec,https://github.com/xkbcommon/libxkbcommon/archive/refs/tags/xkbcommon-%{version}.tar.gz,https://github.com/xkbcommon/libxkbcommon.git,,,"xkbcommon-"
libXinerama.spec,https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-%{version}/libxinerama-libXinerama-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libxinerama.git
libxinerama.spec,https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-%{version}/libxinerama-libXinerama-%{version}.tar.gz,https://gitlab.freedesktop.org/xorg/lib/libxinerama.git
libxml2.spec,https://github.com/GNOME/libxml2/archive/refs/tags/v%{version}.tar.gz,https://github.com/GNOME/libxml2.git
libxslt.spec,https://github.com/GNOME/libxslt/archive/refs/tags/v%{version}.tar.gz,https://github.com/GNOME/libxslt.git
libyaml.spec,https://github.com/yaml/libyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/libyaml.git
lightstep-tracer-cpp.spec,https://github.com/lightstep/lightstep-tracer-cpp/archive/refs/tags/v%{version}.0.tar.gz,,,,,"v0_"
lighttpd.spec,https://download.lighttpd.net/lighttpd/releases-1.4.x/lighttpd-%{version}.tar.gz,https://git.lighttpd.net/lighttpd/lighttpd1.4.git,,,
lightwave.spec,https://github.com/vmware-archive/lightwave/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware-archive/lightwave.git
linux-firmware.spec,https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-%{version}.tar.gz
linux-PAM.spec,https://github.com/linux-pam/linux-pam/archive/refs/tags/Linux-PAM-%{version}.tar.gz,https://github.com/linux-pam/linux-pam.git
linuxptp.spec,https://github.com/richardcochran/linuxptp/archive/refs/tags/v%{version}.tar.gz,https://github.com/richardcochran/linuxptp.git
lksctp-tools.spec,https://github.com/sctp/lksctp-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/sctp/lksctp-tools.git
lldb.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/lldb-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git,,,"llvmorg-"
llvm.spec,https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/llvm-%{version}.src.tar.xz,https://github.com/llvm/llvm-project.git,,,"llvmorg-"
lm-sensors.spec,https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V%{version}.tar.gz,https://github.com/lm-sensors/lm-sensors.git
lshw.spec,https://github.com/lyonel/lshw/archive/refs/tags/%{version}.tar.gz,https://github.com/lyonel/lshw.git
lsof.spec,https://github.com/lsof-org/lsof/archive/refs/tags/%{version}.tar.gz,https://github.com/lsof-org/lsof.git
lttng-tools.spec,https://github.com/lttng/lttng-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/lttng/lttng-tools.git
lvm2.spec,https://github.com/lvmteam/lvm2/archive/refs/tags/v%{version}.tar.gz,https://github.com/lvmteam/lvm2.git
lxcfs.spec,https://github.com/lxc/lxcfs/archive/refs/tags/lxcfs-%{version}.tar.gz,https://github.com/lxc/lxcfs.git
man-db.spec,https://gitlab.com/man-db/man-db/-/archive/%{version}/man-db-%{version}.tar.gz,https://gitlab.com/man-db/man-db.git
man-pages.spec,https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git/snapshot/man-pages-%{version}.tar.gz,https://git.kernel.org/pub/scm/docs/man-pages/man-pages.git
mariadb.spec,https://github.com/MariaDB/server/archive/refs/tags/mariadb-%{version}.tar.gz,https://github.com/MariaDB/server.git
mc.spec,https://github.com/MidnightCommander/mc/archive/refs/tags/%{version}.tar.gz,https://github.com/MidnightCommander/mc.git
memcached.spec,https://github.com/memcached/memcached/archive/refs/tags/%{version}.tar.gz,https://github.com/memcached/memcached.git
mesa.spec,https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-%{version}/mesa-mesa-%{version}.tar.gz,https://gitlab.freedesktop.org/mesa/mesa.git
mkinitcpio.spec,https://github.com/archlinux/mkinitcpio/archive/refs/tags/v%{version}.tar.gz,https://github.com/archlinux/mkinitcpio.git
mm-common.spec,,https://gitlab.gnome.org/GNOME/mm-common.git
ModemManager.spec,,https://gitlab.freedesktop.org/modemmanager/modemmanager.git
modemmanager.spec,,https://gitlab.freedesktop.org/modemmanager/modemmanager.git
monitoring-plugins.spec,https://github.com/monitoring-plugins/monitoring-plugins/archive/refs/tags/v%{version}.tar.gz,https://github.com/monitoring-plugins/monitoring-plugins.git
mpc.spec,https://www.multiprecision.org/downloads/mpc-%{version}.tar.gz
mysql.spec,https://github.com/mysql/mysql-server/archive/refs/tags/mysql-%{version}.tar.gz,https://github.com/mysql/mysql-server.git
nano.spec,https://ftpmirror.gnu.org/nano/nano-%{version}.tar.xz,https://git.savannah.gnu.org/git/nano.git
nasm.spec,https://github.com/netwide-assembler/nasm/archive/refs/tags/nasm-%{version}.tar.gz,https://github.com/netwide-assembler/nasm.git
ncurses.spec,https://github.com/ThomasDickey/ncurses-snapshots/archive/refs/tags/v%{version}.tar.gz,https://github.com/ThomasDickey/ncurses-snapshots.git
netmgmt.spec,https://github.com/vmware/photonos-netmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/photonos-netmgr.git
net-snmp.spec,https://github.com/net-snmp/net-snmp/archive/refs/tags/v%{version}.tar.gz,https://github.com/net-snmp/net-snmp.git
net-tools.spec,https://github.com/ecki/net-tools/archive/refs/tags/v%{version}.tar.gz,https://github.com/ecki/net-tools.git
newt.spec,https://github.com/mlichvar/newt/archive/refs/tags/r%{version}.tar.gz,https://github.com/mlichvar/newt.git
nftables.spec,https://netfilter.org/projects/nftables/files/nftables-%{version}.tar.bz2
nginx.spec,https://github.com/nginx/nginx/archive/refs/tags/release-%{version}.tar.gz,https://github.com/nginx/nginx.git
nss-pam-ldapd.spec,https://github.com/arthurdejong/nss-pam-ldapd/archive/refs/tags/%{version}.tar.gz,https://github.com/arthurdejong/nss-pam-ldapd.git
nodejs.spec,https://github.com/nodejs/node/archive/refs/tags/v%{version}.tar.gz,https://github.com/nodejs/node.git
openjdk8.spec,https://github.com/openjdk/jdk8u/archive/refs/tags/jdk8u%{subversion}-ga.tar.gz,https://github.com/openjdk/jdk8u.git,,,"jdk8u,-ga"
openjdk11.spec,https://github.com/openjdk/jdk11u/archive/refs/tags/jdk-%{version}.tar.gz,https://github.com/openjdk/jdk11u.git,,,"jdk-11*"
openjdk17.spec,https://github.com/openjdk/jdk17u/archive/refs/tags/jdk-%{version}.tar.gz,https://github.com/openjdk/jdk17u.git,,,"jdk-17*"
openjdk21.spec,https://github.com/openjdk/jdk21u/archive/refs/tags/jdk-%{version}.tar.gz,https://github.com/openjdk/jdk21u.git,,,"jdk-,-ga"
openldap.spec,https://github.com/openldap/openldap/archive/refs/tags/OPENLDAP_REL_ENG_%{version}.tar.gz,https://github.com/openldap/openldap.git,,,"UTBM_,URE_,UMICH_LDAP_3_3,UCDATA_,TWEB_OL_BASE,SLAPD_BACK_LDAP,PHP3_TOOL_0_0,OPENLDAP_REL_ENG_,LMDB_"
openresty.spec,https://github.com/openresty/openresty/archive/refs/tags/v%{version}.tar.gz,https://github.com/openresty/openresty.git
openssh.spec,https://github.com/openssh/openssh-portable/archive/refs/tags/V_%{version}.tar.gz,https://github.com/openssh/openssh-portable.git
ostree.spec,https://github.com/ostreedev/ostree/archive/refs/tags/v%{version}.tar.gz,https://github.com/ostreedev/ostree.git
pam_tacplus.spec,https://github.com/kravietz/pam_tacplus/archive/refs/tags/v%{version}.tar.gz,https://github.com/kravietz/pam_tacplus.git
pandoc.spec,https://github.com/jgm/pandoc/archive/refs/tags/%{version}.tar.gz,https://github.com/jgm/pandoc.git
pango.spec,https://github.com/GNOME/pango/archive/refs/tags/%{version}.tar.gz,https://github.com/GNOME/pango.git
passwdqc.spec,https://github.com/openwall/passwdqc/archive/refs/tags/PASSWDQC_%{version}.tar.gz,https://github.com/openwall/passwdqc.git
password-store.spec,https://github.com/zx2c4/password-store/archive/refs/tags/%{version}.tar.gz,https://github.com/zx2c4/password-store.git
patch.spec,https://ftp.gnu.org/gnu/patch/patch-%{version}.tar.gz
pciutils.spec,https://www.kernel.org/pub/software/utils/pciutils/pciutils-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/pciutils/pciutils.git
perl.spec,https://github.com/Perl/perl5/archive/refs/tags/v%{version}.tar.gz,https://github.com/Perl/perl5.git
perl-URI.spec,https://github.com/libwww-perl/URI/archive/refs/tags/v%{version}.tar.gz,https://github.com/libwww-perl/URI.git
perl-CGI.spec,https://github.com/leejo/CGI.pm/archive/refs/tags/v%{version}.tar.gz,https://github.com/leejo/CGI.pm.git
perl-Config-IniFiles.spec,https://github.com/shlomif/perl-Config-IniFiles/archive/refs/tags/releases/%{version}.tar.gz,https://github.com/shlomif/perl-Config-IniFiles.git,,,"releases/"
perl-Data-Validate-IP.spec,https://github.com/houseabsolute/Data-Validate-IP/archive/refs/tags/v%{version}.tar.gz,https://github.com/houseabsolute/Data-Validate-IP.git
perl-DBD-SQLite.spec,https://github.com/DBD-SQLite/DBD-SQLite/archive/refs/tags/%{version}.tar.gz,https://github.com/DBD-SQLite/DBD-SQLite.git
perl-DBI.spec,https://github.com/perl5-dbi/dbi/archive/refs/tags/%{version}.tar.gz,https://github.com/perl5-dbi/dbi.git
perl-Exporter-Tiny.spec,https://github.com/tobyink/p5-exporter-tiny/archive/refs/tags/%{version}.tar.gz,https://github.com/tobyink/p5-exporter-tiny.git
perl-File-HomeDir.spec,https://github.com/perl5-utils/File-HomeDir/archive/refs/tags/%{version}.tar.gz,https://github.com/perl5-utils/File-HomeDir.git
perl-File-Which.spec,https://github.com/uperl/File-Which/archive/refs/tags/v%{version}.tar.gz,https://github.com/uperl/File-Which.git
perl-IO-Socket-SSL.spec,https://github.com/noxxi/p5-io-socket-ssl/archive/refs/tags/%{version}.tar.gz,https://github.com/noxxi/p5-io-socket-ssl.git
perl-List-MoreUtils.spec,https://github.com/perl5-utils/List-MoreUtils/archive/refs/tags/%{version}.tar.gz,https://github.com/perl5-utils/List-MoreUtils.git
perl-Module-Build.spec,https://github.com/Perl-Toolchain-Gang/Module-Build/archive/refs/tags/%{version}.tar.gz,https://github.com/Perl-Toolchain-Gang/Module-Build.git
perl-Module-Install.spec,https://github.com/Perl-Toolchain-Gang/Module-Install/archive/refs/tags/%{version}.tar.gz,https://github.com/Perl-Toolchain-Gang/Module-Install.git
perl-Module-ScanDeps.spec,https://github.com/rschupp/Module-ScanDeps/archive/refs/tags/%{version}.tar.gz,https://github.com/rschupp/Module-ScanDeps.git
perl-Net-SSLeay.spec,https://github.com/radiator-software/p5-net-ssleay/archive/refs/tags/%{version}.tar.gz,https://github.com/radiator-software/p5-net-ssleay.git
perl-Object-Accessor.spec,https://github.com/jib/object-accessor/archive/refs/tags/%{version}.tar.gz,https://github.com/jib/object-accessor.git
perl-TermReadKey.spec,https://github.com/jonathanstowe/TermReadKey/archive/refs/tags/%{version}.tar.gz,https://github.com/jonathanstowe/TermReadKey.git
perl-WWW-Curl.spec,https://github.com/szbalint/WWW--Curl/archive/refs/tags/%{version}.tar.gz,https://github.com/szbalint/WWW--Curl.git
perl-YAML.spec,https://github.com/ingydotnet/yaml-pm/archive/refs/tags/%{version}.tar.gz,https://github.com/ingydotnet/yaml-pm.git
perl-YAML-Tiny.spec,https://github.com/Perl-Toolchain-Gang/YAML-Tiny/archive/refs/tags/v%{version}.tar.gz,https://github.com/Perl-Toolchain-Gang/YAML-Tiny.git
pgbouncer.spec,https://github.com/pgbouncer/pgbouncer/archive/refs/tags/pgbouncer_%{version}.tar.gz,https://github.com/pgbouncer/pgbouncer.git
pgbackrest.spec,https://github.com/pgbackrest/pgbackrest/archive/refs/tags/release/%{version}.tar.gz,https://github.com/pgbackrest/pgbackrest.git
pigz.spec,https://github.com/madler/pigz/archive/refs/tags/v%{version}.tar.gz,https://github.com/madler/pigz.git
pixman.spec,,https://gitlab.freedesktop.org/pixman/pixman.git
pkg-config.spec,,https://gitlab.freedesktop.org/pkg-config/pkg-config.git
pmd-nextgen.spec,https://github.com/vmware/pmd/archive/refs/tags/v%{version}.tar.gz,https://github.com/vmware/pmd.git
polkit.spec,,https://gitlab.freedesktop.org/polkit/polkit.git
popt.spec,https://github.com/rpm-software-management/popt/archive/refs/tags/popt-%{version}-release.tar.gz,https://github.com/rpm-software-management/popt.git
powershell.spec,https://github.com/PowerShell/PowerShell/archive/refs/tags/v%{version}.tar.gz,https://github.com/PowerShell/PowerShell.git
protobuf-c.spec,https://github.com/protobuf-c/protobuf-c/archive/refs/tags/v%{version}.tar.gz,https://github.com/protobuf-c/protobuf-c.git
psmisc.spec,https://gitlab.com/psmisc/psmisc/-/archive/v%{version}/psmisc-v%{version}.tar.gz,https://gitlab.com/psmisc/psmisc.git
pth.spec,https://ftp.gnu.org/gnu/pth/pth-%{version}.tar.gz,https://gitlab.com/psmisc/psmisc.git
pycurl.spec,https://github.com/pycurl/pycurl/archive/refs/tags/REL_%{version}.tar.gz,https://github.com/pycurl/pycurl.git,,,"REL_"
pygobject.spec,https://gitlab.gnome.org/GNOME/pygobject/-/archive/%{version}/pygobject-%{version}.tar.gz,https://gitlab.gnome.org/GNOME/pygobject.git
python3-distro.spec,https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-distro/distro.git
python3-pip.spec,https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/pip.git
python3-pyroute2.spec,https://github.com/svinota/pyroute2/archive/refs/tags/%{version}.tar.gz,https://github.com/svinota/pyroute2.git
python3-setuptools.spec,https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz,https://github.com/pypa/setuptools.git
python-alabaster.spec,https://github.com/bitprophet/alabaster/archive/refs/tags/%{version}.tar.gz,https://github.com/bitprophet/alabaster.git
python-altgraph.spec,https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz,https://github.com/ronaldoussoren/altgraph.git
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
python-docutils.spec,https://sourceforge.net/projects/docutils/files/docutils/0.19/docutils-%{version}.tar.gz/download
python-ecdsa.spec,https://github.com/tlsfuzzer/python-ecdsa/archive/refs/tags/python-ecdsa-%{version}.tar.gz,https://github.com/tlsfuzzer/python-ecdsa.git
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
python-Js2Py.spec,https://files.pythonhosted.org/packages/cb/a5/3d8b3e4511cc21479f78f359b1b21f1fb7c640988765ffd09e55c6605e3b/Js2Py-%{version}.tar.gz
python-jsonpointer.spec,https://github.com/stefankoegl/python-json-pointer/archive/refs/tags/v%{version}.tar.gz,https://github.com/stefankoegl/python-json-pointer.git
python-jsonpatch.spec,https://github.com/stefankoegl/python-json-patch/archive/refs/tags/v%{version}.tar.gz,https://github.com/stefankoegl/python-json-patch.git
python-jsonschema.spec,https://github.com/python-jsonschema/jsonschema/archive/refs/tags/v%{version}.tar.gz,https://github.com/python-jsonschema/jsonschema.git
python-looseversion.spec,https://github.com/effigies/looseversion/archive/refs/tags/%{version}.tar.gz,https://github.com/effigies/looseversion.git
python-M2Crypto.spec,https://gitlab.com/m2crypto/m2crypto/-/archive/%{version}/m2crypto-%{version}.tar.gz,https://gitlab.com/m2crypto/m2crypto.git
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
python-pathspec.spec,https://github.com/cpburnz/python-pathspec/archive/refs/tags/v%{version}.tar.gz,https://github.com/cpburnz/python-pathspec.git
python-pbr.spec,https://opendev.org/openstack/pbr/archive/%{version}.tar.gz,https://opendev.org/openstack/pbr.git,,python-pbr
python-pefile.spec,https://github.com/erocarrera/pefile/archive/refs/tags/v%{version}.tar.gz,https://github.com/erocarrera/pefile.git
python-pexpect.spec,https://github.com/pexpect/pexpect/archive/refs/tags/%{version}.tar.gz,https://github.com/pexpect/pexpect.git
python-pip.spec,https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz,https://github.com/pypa/pip.git
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
python-pyYaml.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/pyyaml.git
python-PyYAML.spec,https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz,https://github.com/yaml/pyyaml.git
python-requests.spec,https://github.com/psf/requests/archive/refs/tags/v%{version}.tar.gz,https://github.com/psf/requests.git
python-requests-unixsocket.spec,https://github.com/msabramo/requests-unixsocket/archive/refs/tags/v%{version}.tar.gz,https://github.com/msabramo/requests-unixsocket.git
python-requests-toolbelt.spec,https://github.com/requests/toolbelt/archive/refs/tags/%{version}.tar.gz,https://github.com/requests/toolbelt.git
python-resolvelib.spec,https://github.com/sarugaku/resolvelib/archive/refs/tags/%{version}.tar.gz,https://github.com/sarugaku/resolvelib.git
python-rsa.spec,https://github.com/sybrenstuvel/python-rsa/archive/refs/tags/version-%{version}.tar.gz,https://github.com/sybrenstuvel/python-rsa.git,,,"version-"
python-ruamel-yaml.spec,https://files.pythonhosted.org/packages/17/2f/f38332bf6ba751d1c8124ea70681d2b2326d69126d9058fbd9b4c434d268/ruamel.yaml-%{version}.tar.gz
python-s3transfer.spec,https://github.com/boto/s3transfer/archive/refs/tags/%{version}.tar.gz,https://github.com/boto/s3transfer.git
python-scp.spec,https://github.com/jbardin/scp.py/archive/refs/tags/v%{version}.tar.gz,https://github.com/jbardin/scp.py.git
python-semantic-version.spec,https://github.com/rbarrois/python-semanticversion/archive/refs/tags/%{version}.tar.gz,https://github.com/rbarrois/python-semanticversion.git
python-service_identity.spec,https://github.com/pyca/service-identity/archive/refs/tags/%{version}.tar.gz,https://github.com/pyca/service-identity.git
python-setproctitle.spec,https://github.com/dvarrazzo/py-setproctitle/archive/refs/tags/version-%{version}.tar.gz,https://github.com/dvarrazzo/py-setproctitle.git
python-setuptools.spec,https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz,https://github.com/pypa/setuptools.git
python-setuptools-rust.spec,https://github.com/PyO3/setuptools-rust/archive/refs/tags/v%{version}.tar.gz,https://github.com/PyO3/setuptools-rust.git
python-setuptools_scm.spec,https://github.com/pypa/setuptools_scm/archive/refs/tags/v%{version}.tar.gz,https://github.com/pypa/setuptools_scm.git
python-simplejson.spec,https://github.com/simplejson/simplejson/archive/refs/tags/v%{version}.tar.gz,https://github.com/simplejson/simplejson.git
python-six.spec,https://github.com/benjaminp/six/archive/refs/tags/%{version}.tar.gz,https://github.com/benjaminp/six.git
python-snowballstemmer.spec,https://github.com/snowballstem/snowball/archive/refs/tags/v%{version}.tar.gz,https://github.com/snowballstem/snowball.git
python-sphinx.spec,https://github.com/sphinx-doc/sphinx/archive/refs/tags/v%{version}.tar.gz,https://github.com/sphinx-doc/sphinx.git
python-sphinxcontrib-applehelp.spec,https://github.com/sphinx-doc/sphinxcontrib-applehelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-applehelp.git
python-sphinxcontrib-devhelp.spec,https://github.com/sphinx-doc/sphinxcontrib-devhelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-devhelp.git
python-sphinxcontrib-htmlhelp.spec,https://github.com/sphinx-doc/sphinxcontrib-htmlhelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-htmlhelp.git
python-sphinxcontrib-jsmath.spec,https://github.com/sphinx-doc/sphinxcontrib-jsmath/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-jsmath.git
python-sphinxcontrib-qthelp.spec,https://github.com/sphinx-doc/sphinxcontrib-qthelp/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-qthelp.git
python-sphinxcontrib-serializinghtml.spec,https://github.com/sphinx-doc/sphinxcontrib-serializinghtml/archive/refs/tags/%{version}.tar.gz,https://github.com/sphinx-doc/sphinxcontrib-serializinghtml.git
python-sqlalchemy.spec,https://github.com/sqlalchemy/sqlalchemy/archive/refs/tags/rel_%{version}.tar.gz,https://github.com/sqlalchemy/sqlalchemy.git,,,"rel_"
python-subprocess32.spec,https://github.com/google/python-subprocess32/archive/refs/tags/%{version}.tar.gz,https://github.com/google/python-subprocess32.git
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
re2.spec,https://github.com/google/re2/archive/refs/tags/%{version}.tar.gz,https://github.com/google/re2.git
redis.spec,https://github.com/redis/redis/archive/refs/tags/%{version}.tar.gz,https://github.com/redis/redis.git
repmgr.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr10.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr13.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr14.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr15.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
repmgr16.spec,https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v%{version}.tar.gz,https://github.com/EnterpriseDB/repmgr.git
rpcsvc-proto.spec,https://github.com/thkukuk/rpcsvc-proto/archive/refs/tags/v%{version}.tar.gz,https://github.com/thkukuk/rpcsvc-proto.git
rpm.spec,https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-%{version}-release.tar.gz,https://github.com/rpm-software-management/rpm.git,,rpm,"rpm-,-release"
rrdtool.spec,https://github.com/oetiker/rrdtool-1.x/archive/refs/tags/v%{version}.tar.gz,https://github.com/oetiker/rrdtool-1.x.git
rt-tests.spec,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/snapshot/rt-tests-%{version}.tar.gz,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
ruby.spec,https://github.com/ruby/ruby/archive/refs/tags/v%{version}.tar.gz,https://github.com/ruby/ruby.git,,,"@"
rust.spec,https://github.com/rust-lang/rust/archive/refs/tags/%{version}.tar.gz,https://github.com/rust-lang/rust.git
rsyslog.spec,https://github.com/rsyslog/rsyslog/archive/refs/tags/v%{version}.tar.gz,https://github.com/rsyslog/rsyslog.git
rt-tests.spec,,https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git
samba-client.spec,https://gitlab.com/samba-team/devel/samba/-/archive/samba-%{version}/samba-samba-%{version}.tar.gz
sbsigntools.spec,https://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git/snapshot/sbsigntools-%{version}.tar.gz,https://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git,,,
selinux-policy.spec,https://github.com/fedora-selinux/selinux-policy/archive/refs/tags/v%{version}.tar.gz,https://github.com/fedora-selinux/selinux-policy.git,,,
serf.spec,https://github.com/apache/serf/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/serf.git
shadow.spec,https://github.com/shadow-maint/shadow/archive/refs/tags/%{version}.tar.gz,https://github.com/shadow-maint/shadow.git
shared-mime-info.spec,https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/%{version}/shared-mime-info-%{version}.tar.gz,https://gitlab.freedesktop.org/xdg/shared-mime-info.git
slirp4netns.spec,https://github.com/rootless-containers/slirp4netns/archive/refs/tags/v%{version}.tar.gz,https://github.com/rootless-containers/slirp4netns.git
spirv-headers.spec,https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/sdk-%{version}.tar.gz,https://github.com/KhronosGroup/SPIRV-Headers.git
spirv-tools.spec,https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/sdk-%{version}.tar.gz,https://github.com/KhronosGroup/SPIRV-Tools.git
sqlite.spec,https://github.com/sqlite/sqlite/archive/refs/tags/version-%{version}.tar.gz,https://github.com/sqlite/sqlite.git,,,"version-"
stalld.spec,,https://git.kernel.org/pub/scm/utils/stalld/stalld.git
strongswan.spec,https://github.com/strongswan/strongswan/releases/download/%{version}/strongswan-%{version}.tar.bz2,https://github.com/strongswan/strongswan.git
subversion.spec,https://github.com/apache/subversion/archive/refs/tags/%{version}.tar.gz,https://github.com/apache/subversion.git
syslinux.spec,,https://git.kernel.org/pub/scm/boot/syslinux/syslinux.git
sysstat.spec,http://pagesperso-orange.fr/sebastien.godard/sysstat-%{version}.tar.xz
systemd.spec,https://github.com/systemd/systemd-stable/archive/refs/tags/v%{version}.tar.gz,https://github.com/systemd/systemd-stable.git
systemtap.spec,https://sourceware.org/ftp/systemtap/releases/systemtap-%{version}.tar.gz
tar.spec,https://ftp.gnu.org/gnu/tar/tar-%{version}.tar.xz
tboot.spec,https://sourceforge.net/projects/tboot/files/tboot/tboot-%{version}.tar.gz/download
tcp_wrappers.spec,http://ftp.porcupine.org/pub/security/tcp_wrappers_%{version}.tar.gz
termshark.spec,https://github.com/gcla/termshark/archive/refs/tags/v%{version}.tar.gz,https://github.com/gcla/termshark.git
tornado.spec,https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz,https://github.com/tornadoweb/tornado.git
toybox.spec,https://github.com/landley/toybox/archive/refs/tags/%{version}.tar.gz,https://github.com/landley/toybox.git
tpm2-pkcs11.spec,https://github.com/tpm2-software/tpm2-pkcs11/archive/refs/tags/%{version}.tar.gz,https://github.com/tpm2-software/tpm2-pkcs11.git
trace-cmd.spec,,https://git.kernel.org/pub/scm/utils/trace-cmd/trace-cmd.git
trousers.spec,https://sourceforge.net/projects/trousers/files/trousers/%{version}/trousers-%{version}.tar.gz/download
tzdata.spec,https://data.iana.org/time-zones/releases/tzdata%{version}.tar.gz
u-boot.spec,https://github.com/u-boot/u-boot/archive/refs/tags/v%{version}.tar.gz,https://github.com/u-boot/u-boot.git
ulogd.spec,https://netfilter.org/pub/ulogd/ulogd-%{version}.tar.bz2
userspace-rcu.spec,https://github.com/urcu/userspace-rcu/archive/refs/tags/v%{version}.tar.gz,https://github.com/urcu/userspace-rcu.git,,,
unbound.spec,https://github.com/NLnetLabs/unbound/archive/refs/tags/release-%{version}.tar.gz,https://github.com/NLnetLabs/unbound.git
unixODBC.spec,https://github.com/lurcher/unixODBC/archive/refs/tags/%{version}.tar.gz,https://github.com/lurcher/unixODBC.git
usbutils.spec,https://www.kernel.org/pub/linux/utils/usb/usbutils/usbutils-%{version}.tar.xz,https://git.kernel.org/pub/scm/linux/kernel/git/gregkh/usbutils.git
util-linux.spec,https://github.com/util-linux/util-linux/archive/refs/tags/v%{version}.tar.gz,https://github.com/util-linux/util-linux.git
util-macros.spec,https://ftp.x.org/archive//individual/util/util-macros-%{version}.tar.bz2
uwsgi.spec,https://github.com/unbit/uwsgi/archive/refs/tags/%{version}.tar.gz,https://github.com/unbit/uwsgi.git
valgrind.spec,https://sourceware.org/pub/valgrind/valgrind-%{version}.tar.bz2
vim.spec,https://github.com/vim/vim/archive/refs/tags/v%{version}.tar.gz,https://github.com/vim/vim.git
vulkan-tools.spec,https://github.com/KhronosGroup/Vulkan-Tools/archive/refs/tags/sdk-%{version}.tar.gz,https://github.com/KhronosGroup/Vulkan-Tools.git
wavefront-proxy.spec,https://github.com/wavefrontHQ/wavefront-proxy/archive/refs/tags/proxy-%{version}.tar.gz,https://github.com/wavefrontHQ/wavefront-proxy.git
wayland.spec,https://gitlab.freedesktop.org/wayland/wayland/-/archive/%{version}/wayland-%{version}.tar.gz,https://gitlab.freedesktop.org/wayland/wayland.git
wayland-protocols.spec,,https://gitlab.freedesktop.org/wayland/wayland-protocols.git
wget.spec,https://ftp.gnu.org/gnu/wget/wget-%{version}.tar.gz
wireshark.spec,https://github.com/wireshark/wireshark/archive/refs/tags/wireshark-%{version}.tar.gz,https://github.com/wireshark/wireshark.git
wrapt.spec,https://github.com/GrahamDumpleton/wrapt/archive/refs/tags/%{version}.tar.gz,https://github.com/GrahamDumpleton/wrapt.git
xerces-c.spec,https://github.com/apache/xerces-c/archive/refs/tags/v%{version}.tar.gz,https://github.com/apache/xerces-c.git
xinetd.spec,https://github.com/xinetd-org/xinetd/archive/refs/tags/xinetd-%{version}.tar.gz,https://github.com/xinetd-org/xinetd.git
XML-Parser.spec,https://github.com/toddr/XML-Parser/archive/refs/tags/%{version}.tar.gz,https://github.com/toddr/XML-Parser.git
xml-security-c.spec,https://archive.apache.org/dist/santuario/c-library/xml-security-c-%{version}.tar.gz
xmlsec1.spec,https://www.aleksey.com/xmlsec/download/xmlsec1-%{version}.tar.gz,https://github.com/lsh123/xmlsec.git
xz.spec,https://github.com/tukaani-project/xz/archive/refs/tags/v%{version}.tar.gz,https://github.com/tukaani-project/xz.git
zlib.spec,https://github.com/madler/zlib/archive/refs/tags/v%{version}.tar.gz,https://github.com/madler/zlib.git
zsh.spec,https://github.com/zsh-users/zsh/archive/refs/tags/zsh-%{version}.tar.gz,https://github.com/zsh-users/zsh.git
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
    }catch{}
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
            [Parameter(Mandatory=$true)]
            [string[]]$Names
        )

        if (-not $Names) {
            return ""
        }

        # Check if any name matches the version number pattern (dot or hyphen-separated)
        $isVersionList = $Names | Where-Object { $_ -match '^\d+([.-]\d+)*$' } | Measure-Object | Select-Object -ExpandProperty Count

        if ($isVersionList -gt 0) {
            # Process version-like names
            $processedNames = $Names | ForEach-Object {
                $original = $_
                if (Test-IntegerLike -Value $original) {
                    # Treat integer-like strings (e.g., "059") with their numeric value
                    $numericValue = [double]($original -replace '^0+', '') # Remove leading zeros for numeric comparison
                    [PSCustomObject]@{
                        Original = $original
                        IsIntegerLike = $true
                        SortValue = $numericValue
                        Version = $null
                    }
                } else {
                    # Parse version strings (e.g., "0.9", "4-0-0-1")
                    $version = Convert-ToVersion -VersionInput $original
                    [PSCustomObject]@{
                        Original = $original
                        IsIntegerLike = $false
                        SortValue = $null
                        Version = $version
                    }
                }
            }

            # Sort names using Compare-VersionStrings, ensuring $sortedNames is a collection of PSCustomObjects
            $sortedNames = $processedNames | Sort-Object -Property @{
                Expression = {
                    $current = $_.Original
                    $maxResult = 0
                    foreach ($other in $Names) {
                        if ($other -ne $current) {
                            $result = Compare-VersionStrings -Namelatest $current -Version $other
                            if ($result -eq 1 -and $maxResult -lt 1) { $maxResult = 1 }
                            if ($result -eq -1 -and $maxResult -gt -1) { $maxResult = -1 }
                        }
                    }
                    [tuple]::Create($maxResult, $current)
                }; Descending = $true
            }

            # Debug output to verify $sortedNames structure
            # Write-Output "Sorted Names: $($sortedNames | Format-Table -AutoSize | Out-String)"

            # Return the original string of the latest name
            return $sortedNames | Select-Object -First 1 -ExpandProperty Original
        } else {
            # Handle non-version names (sort lexicographically and take the last one)
            try {
                # Try to parse as JSON if applicable
                $parsedNames = $Names | ConvertFrom-Json -ErrorAction Stop
                return ($parsedNames | Sort-Object | Select-Object -Last 1).ToString()
            } catch {
                # Fallback to lexicographic sort of original strings
                return ($Names | Sort-Object | Select-Object -Last 1).ToString()
            }
        }
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

    # In case of debug: uncomment and debug from here
    # if ($currentTask.spec -ilike 'WALinuxAgent.spec')
    # {pause}
    # else
    # {return}

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
        elseif ($currentTask.spec -eq "xmlsec1.spec") {if ($version -lt "1.2.30") {$Source0="https://www.aleksey.com/xmlsec/download/older-releases/xmlsec1-%{version}.tar.gz"} else {$Source0="https://www.aleksey.com/xmlsec/download/xmlsec1-%{version}.tar.gz"}}
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
                    # Push the current directory to the stack
                    $SourceClonePath=[System.String](join-path -path $ClonePath -childpath $repoName)
                    if (!(Test-Path $SourceClonePath)) {
                        Set-Location -Path $ClonePath -ErrorAction Stop
                        # Clone the repository
                        try {
                            if (!([string]::IsNullOrEmpty($gitBranch))) {
                                Invoke-GitWithTimeout "clone $SourceTagURL -b $gitBranch $repoName" -WorkingDirectory $ClonePath -TimeoutSeconds 120 | Out-Null
                            } else {
                                Invoke-GitWithTimeout "clone $SourceTagURL $repoName" -WorkingDirectory $ClonePath -TimeoutSeconds 120 | Out-Null
                                # the very first time, you receive the origin names and not the version names. From the 2nd run, all is fine.
                                Set-Location $SourceClonePath
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "fetch -b $gitBranch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "fetch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
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
                                Invoke-GitWithTimeout "fetch -b $gitBranch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                            } else {
                                Invoke-GitWithTimeout "fetch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                            }
                        }
                        catch {
                            Write-Warning "Git fetch failed for $repoName : $_"
                        }
                    }

                    # override with special cases
                    if ($currentTask.spec -ilike 'gstreamer-plugins-base.spec') {$repoName="gst-plugins-base-"}
                    # Run git tag -l and collect output in an array
                    if (!([string]::IsNullOrEmpty($customRegex))) {$Names = git tag -l | Where-Object { $_ -match "^$([regex]::Escape($repoName))-" } | ForEach-Object { $_.Trim()}}
                    else {$Names = git tag -l | ForEach-Object { $_.Trim() }}
                    $urlhealth="200"
                } catch {}
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

                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

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
                    $Names = (invoke-webrequest $SourceTagURL -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop | convertfrom-json).tag_name
                    if ([string]::IsNullOrEmpty($Names -join ''))
                    {
                        $Names = (invoke-webrequest $SourceTagURL -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop | convertfrom-json).name
                        if ([string]::IsNullOrEmpty($Names -join ''))
                        {
                            $Names = ((invoke-webrequest $SourceTagURL -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop | convertfrom-json).assets).name
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
                    "c-ares.spec" {$replace +="cares-"; break}
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
                        $Names = (invoke-webrequest $SourceTagURL -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop).links.href
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
                        $Names = (invoke-webrequest $SourceTagURL -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop).links.href
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
                        $Names = (invoke-webrequest $SourceTagURL -headers $headers -Method Get -TimeoutSec 10 -ErrorAction Stop).links.href
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

                    if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

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


                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

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

    # Check UpdateAvailable by rubygems.org tags detection
    elseif ($Source0 -ilike '*rubygems.org*')
    {
        # Extract SourceTagURL from Source0
        $SourceTagURL = [System.String]::Concat(('https://rubygems.org/gems/'),$currentTask.gem_name,"/versions")
        try{
            $Names = invoke-restmethod -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop
            if ($Names) {

                $Names = ($Names -split 'a href=') -split '>'
                $Names = ($Names | foreach-object { if ($_ | select-string -pattern '</a' -simplematch) {$_}}) -replace '"',""
                $Names = $Names -replace '</a'

                $Names = $Names  -replace $replace,""

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

                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

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

                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

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

                    if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

                    $replace += $currentTask.Name+"."
                    $replace += $currentTask.Name+"-"
                    $replace += $currentTask.Name+"_"
                    $replace +="ver"

                    # Do not add [...]replace(($replace[$i]).tolower() because later e.g. for downloading resources the exact case-sensitive match is important.
                    foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
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
                    if (!(Test-Path $SourceClonePath)) {
                        Set-Location -Path $ClonePath -ErrorAction Stop
                        # Clone the repository
                        try {
                            if (!([string]::IsNullOrEmpty($gitBranch))) {
                                Invoke-GitWithTimeout "clone $SourceTagURL -b $gitBranch $repoName" -WorkingDirectory $ClonePath -TimeoutSeconds 120 | Out-Null
                            } else {
                                Invoke-GitWithTimeout "clone $SourceTagURL $repoName" -WorkingDirectory $ClonePath -TimeoutSeconds 120 | Out-Null
                                # the very first time, you receive the origin names and not the version names. From the 2nd run, all is fine.
                                Set-Location $SourceClonePath
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "fetch -b $gitBranch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "fetch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
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
                                Invoke-GitWithTimeout "fetch -b $gitBranch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                            } else {
                                Invoke-GitWithTimeout "fetch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                            }
                        }
                        catch {
                            Write-Warning "Git fetch failed for $repoName : $_"
                        }
                    }
                    # Run git tag -l and collect output in an array
                    if ("" -eq $customRegex) {$Names = git tag -l | Where-Object { $_ -match "^$([regex]::Escape($repoName))-" } | ForEach-Object { $_.Trim()}}
                    else {$Names = git tag -l | ForEach-Object { $_.Trim() }}
                    $urlhealth="200"
                } catch {}
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

                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
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

                    if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

                    $replace += $currentTask.Name+"."
                    $replace += $currentTask.Name+"-"
                    $replace += $currentTask.Name+"_"
                    $replace +="ver"

                    foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
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
            $SourceTagURL=(split-path $Source0 -Parent).Replace("\","/")
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
                    if (!(Test-Path $SourceClonePath)) {
                        Set-Location -Path $ClonePath -ErrorAction Stop
                        # Clone the repository
                        try {
                            if (!([string]::IsNullOrEmpty($gitBranch))) {
                                Invoke-GitWithTimeout "clone $SourceTagURL -b $gitBranch $repoName" -WorkingDirectory $ClonePath -TimeoutSeconds 120 | Out-Null
                            } else {
                                Invoke-GitWithTimeout "clone $SourceTagURL $repoName" -WorkingDirectory $ClonePath -TimeoutSeconds 120 | Out-Null
                                # the very first time, you receive the origin names and not the version names. From the 2nd run, all is fine.
                                Set-Location -Path $SourceClonePath -ErrorAction Stop
                                if (!([string]::IsNullOrEmpty($gitBranch))) {
                                    Invoke-GitWithTimeout "fetch -b $gitBranch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                                } else {
                                    Invoke-GitWithTimeout "fetch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
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
                                Invoke-GitWithTimeout "fetch -b $gitBranch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                            } else {
                                Invoke-GitWithTimeout "fetch" -WorkingDirectory $SourceClonePath -TimeoutSeconds 60 | Out-Null
                            }
                        }
                        catch {
                            Write-Warning "Git fetch failed for $repoName : $_"
                        }
                    }
                    # Run git tag -l and collect output in an array
                    Set-Location -Path $SourceClonePath -ErrorAction SilentlyContinue
                    if ("" -eq $customRegex) {$Names = git tag -l | Where-Object { $_ -match "^$([regex]::Escape($repoName))-" } | ForEach-Object { $_.Trim()}}
                    else {$Names = git tag -l | ForEach-Object { $_.Trim() }}
                    $urlhealth="200"
                } catch {}
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
            } catch {}
        }
        try {
            if (($SourceTagURL -ne "") -and ($null -ne $Names)) {

                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}
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
    ($currentTask.spec -ilike "xmlsec1.spec") -or `
    ($currentTask.spec -ilike "wireguard-tools.spec"))
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
                $objtmp = (invoke-webrequest -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop).Links.href
                $objtmp = $objtmp | foreach-object { if ($_ -match '\d') {$_}}
                $objtmp = $objtmp | foreach-object { if (!($_ | select-string -pattern 'CR' -simplematch)) {$_}}
                $objtmp = $objtmp | foreach-object { if (!($_ | select-string -pattern 'b' -simplematch)) {$_}}
                $Latest=([HeapSort]::Sort($objtmp) | select-object -last 1).tostring()
                $SourceTagURL = [system.string]::concat('https://docbook.org/xml/',$Latest)
                $objtmp = (invoke-webrequest -uri $SourceTagURL -TimeoutSec 10 -ErrorAction Stop).Links.href
                $Names = $objtmp | foreach-object { if ($_ | select-string -pattern 'docbook-' -simplematch) {$_}}
                $Names = $Names  -replace "docbook-xml-",""
                $Names = $Names  -replace "docbook-",""
                $Names = $Names  -replace ".zip",""
            }
            if ($currentTask.spec -ilike "json-c.spec")
            {
                $Names = (invoke-webrequest -uri $SourceTagURL -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop) -split "<"
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
                elseif ($currentTask.spec -ilike "wireguard-tools.spec") { $replace += "/wireguard-tools/snapshot/wireguard-tools-";$replace += "'"}


                if ($ignore) {$Names = $Names | foreach-object { $NamesObj = $_; foreach ($item in $ignore) {if (!($NamesObj | select-string -pattern $item -simplematch)) {$NamesObj}}}}

                $replace += $currentTask.Name+"."
                $replace += $currentTask.Name+"-"
                $replace += $currentTask.Name+"_"
                $replace += $currentTask.Name
                $replace +="ver"
                $replace +="release_"
                $replace +="release-"
                $replace +="release"
                foreach ($item in $replace) {$Names = $Names | ForEach-Object { $_ -replace [regex]::Escape($item), "" }}

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
                    Invoke-WebRequest -Uri $SourceRPMFileURL -OutFile $SourceRPMFile -TimeoutSec 10 -ErrorAction Stop
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
        catch{}
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
                if ($currentTask.spec -ilike 'byacc.spec')
                {
                    $version = $version -ireplace "2.0.",""
                }

                if ($currentTask.spec -ilike 'docker.spec') { $Source0=[system.string]::concat("https://github.com/moby/moby/archive/refs/tags/v",$version,".tar.gz") }

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

                $versionshort=[system.string]::concat((($version).Split("."))[0],'.',(($version).Split("."))[1])
                $UpdateAvailableshort=[system.string]::concat((($UpdateAvailable).Split("."))[0],'.',(($UpdateAvailable).Split("."))[1])

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
            $UpdateDownloadName = $UpdateDownloadName -ireplace "Rel_",[System.String]::Concat($currentTask.Name,"-")
            $UpdateDownloadName = $UpdateDownloadName -ireplace "_","."
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
                if ($currentTask.content -ilike '*%define sha1*') { $SHAValue = (get-filehash $UpdateDownloadFile -Algorithm SHA1).Hash;$SHALine = [system.string]::concat('%define sha1 ',$currentTask.Name,'=',$SHAValue) }
                if ($currentTask.content -ilike '*%define sha256*') { $SHAValue = (get-filehash $UpdateDownloadFile -Algorithm SHA256).Hash;$SHALine = [system.string]::concat('%define sha256 ',$currentTask.Name,'=',$SHAValue) }
                if ($currentTask.content -ilike '*%define sha512*') { $SHAValue = (get-filehash $UpdateDownloadFile -Algorithm SHA512).Hash;$SHALine = [system.string]::concat('%define sha512 ',$currentTask.Name,'=',$SHAValue) }
                    # if the spec file does not contain any sha value, add sha512
                if ((!($currentTask.content -ilike '*%define sha512*')) -and (!($object -ilike '*%define sha256*')) -and (!($object -ilike '*%define sha1*'))) { $SHAValue = (get-filehash $UpdateDownloadFile -Algorithm SHA512).Hash; $SHALine = [system.string]::concat('%define sha512 ',$currentTask.Name,'=',$SHAValue) }
            }
        }
        # Add a space to signalitze that something went wrong when extracting SHAvalue but do not stop modifying the spec file.
        if ([string]::IsNullOrEmpty($SHALine)) { $SHALine=" " }

        if ($currentTask.Spec -ilike 'openjdk8.spec') {ModifySpecFile -SpecFileName $currentTask.spec -SourcePath $SourcePath -PhotonDir $photonDir -Name $currentTask.name -Update $UpdateAvailable -UpdateDownloadFile $UpdateDownloadFile -OpenJDK8 $true -SHALine $SHALine}
        else {ModifySpecFile -SpecFileName $currentTask.spec -SourcePath $SourcePath -PhotonDir $photonDir -Name $currentTask.name -Update $UpdateAvailable -UpdateDownloadFile $UpdateDownloadFile -OpenJDK8 $false -SHALine $SHALine}
    }

    [System.String]::Concat($currentTask.spec,',',$currentTask.source0,',',$Source0,',',$urlhealth,',',$UpdateAvailable,',',$UpdateURL,',',$HealthUpdateURL,',',$currentTask.Name,',',$SHAValue,',',$UpdateDownloadName)
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
        Write-host "Preparing data for Photon OS 3.0 ..."
        GitPhoton -release "3.0" -SourcePath $SourcePath
        $Packages3 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-3.0"
    }
    if ($GeneratePh4URLHealthReport) {
        Write-host "Preparing data for Photon OS 4.0 ..."
        GitPhoton -release "4.0" -SourcePath $SourcePath
        $Packages4 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-4.0"
    }
    if ($GeneratePh5URLHealthReport) {
        Write-host "Preparing data for Photon OS 5.0 ..."
        GitPhoton -release "5.0" -SourcePath $SourcePath
        $Packages5 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-5.0"
    }
    if ($GeneratePh6URLHealthReport) {
        Write-host "Preparing data for Photon OS 6.0 ..."
        GitPhoton -release "6.0" -SourcePath $SourcePath
        $Packages6 = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-6.0"
    }
    if ($GeneratePhCommonURLHealthReport) {
        Write-host "Preparing data for Photon OS Common ..."
        GitPhoton -release "common" -SourcePath $SourcePath
        $PackagesCommon = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-common"
    }
    if ($GeneratePhDevURLHealthReport) {
        Write-host "Preparing data for Photon OS Development ..."
        GitPhoton -release "dev" -SourcePath $SourcePath
        $PackagesDev = ParseDirectory -SourcePath $SourcePath -PhotonDir "photon-dev"
    }
    if ($GeneratePhMasterURLHealthReport) {
        Write-host "Preparing data for Photon OS Master ..."
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
            write-host "Starting parallel URL health report generation for applicable versions ..."
            # Pre-capture all necessary function definitions and data once
            $FunctionDefinitions = @{
                CheckURLHealth = (Get-Command 'CheckURLHealth' -ErrorAction SilentlyContinue).Definition
                urlhealth = (Get-Command 'urlhealth' -ErrorAction SilentlyContinue).Definition
                KojiFedoraProjectLookUp = (Get-Command 'KojiFedoraProjectLookUp' -ErrorAction SilentlyContinue).Definition
                ModifySpecFile = (Get-Command 'ModifySpecFile' -ErrorAction SilentlyContinue).Definition
                Source0Lookup = (Get-Command 'Source0Lookup' -ErrorAction SilentlyContinue).Definition
                HeapSortClass = $HeapSortClassDef
            }
            $ParallelContext = @{
                SourcePath = $SourcePath
                AccessToken = $AccessToken
                FunctionDefs = $FunctionDefinitions
            }
            $checkUrlHealthTasks | ForEach-Object {
                # Safely reference variables from the parent scope
                $TaskConfig = $_

                Write-host "Generating URLHealth report for $($TaskConfig.Name) ..."
                $outputFileName = "photonos-urlhealth-$($TaskConfig.Release)_$((Get-Date).ToString("yyyyMMddHHmm"))"
                $outputFilePath = Join-Path -Path $sourcePath -ChildPath "$outputFileName.prn"

                # Create a thread-safe collection for all results
                $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
                $results += $TaskConfig.Packages | ForEach-Object -parallel {
                    # Initialize functions in runspace
                    $FunctionDefs = $using:ParallelContext.FunctionDefs
                    $FunctionDefs.GetEnumerator() | Where-Object { $_.Value } | ForEach-Object {
                        if ($_.Key -eq 'HeapSortClass') {
                        Invoke-Expression $_.Value
                        } else {
                        Invoke-Expression "function $($_.Key) { $($_.Value) }"
                        }
                    }

                    # Safely reference variables from the parent scope
                    $currentPackage = $_
                    write-host "Processing $($currentPackage.name) ..."
                    [system.string](CheckURLHealth -currentTask $currentPackage -SourcePath $using:ParallelContext.SourcePath -AccessToken $using:ParallelContext.AccessToken -outputfile $using:outputFilePath -photonDir $using:TaskConfig.PhotonDir)
                } -ThrottleLimit $ThrottleLimit

                $sb = New-Object System.Text.StringBuilder
                $sb.AppendLine("Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName") | Out-Null
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
            write-host "Starting sequential URL health report generation for applicable versions..."
            $checkUrlHealthTasks | ForEach-Object {
                # Safely reference variables from the parent scope
                $TaskConfig = $_

                Write-host "Generating URLHealth report for $($TaskConfig.Name) ..."
                $outputFileName = "photonos-urlhealth-$($TaskConfig.Release)_$((Get-Date).ToString("yyyyMMddHHmm"))"
                $outputFilePath = Join-Path -Path $sourcePath -ChildPath "$outputFileName.prn"

                # Create a thread-safe collection for all results
                $results = [System.Collections.Concurrent.ConcurrentBag[object]]::new()
                $results += "Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName"
                $results += $TaskConfig.Packages | ForEach-Object {
                    # Safely reference variables from the parent scope
                    $currentPackage = $_
                    write-host "Processing $($currentPackage.name) ..."
                    [system.string](CheckURLHealth -currentTask $currentPackage -SourcePath $SourcePath -AccessToken $accessToken -outputfile $outputFilePath -photonDir $TaskConfig.PhotonDir)
                }
                $sb = New-Object System.Text.StringBuilder
                $sb.AppendLine("Spec,Source0 original,Modified Source0 for url health check,UrlHealth,UpdateAvailable,UpdateURL,HealthUpdateURL,Name,SHAName,UpdateDownloadName") | Out-Null
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
        }
    }
    else {
        write-host "No URL health reports were enabled or no package data found."
    }
}


# Set security protocol to TLS 1.2 and TLS 1.3
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

# Check if the required commands are available
$commands = @(
    @{ Name = "git"; Id = "Git.Git" },
    @{ Name = "tar"; Id = "GnuWin32.Tar" }
)
foreach ($cmd in $commands) {
    if (-not (Get-Command $cmd.Name -ErrorAction SilentlyContinue)) {
        Write-Output "$($cmd.Name) not found. Trying to install ..."
        winget install --id $cmd.Id -e --source winget
        Write-Output "Please restart the script."
        exit
    }
}
try { (get-command use-culture).Version.ToString() | Out-Null }
catch { install-module -name PowerShellCookbook -AllowClobber -Force -Confirm:$false }


# parallel processing support
$Script:UseParallel = $PSVersionTable.PSVersion.Major -ge 7 -and $PSVersionTable.PSVersion.Minor -ge 4
# Get current CPU usage percentage
$cpuCounter = Get-Counter '\Processor(_Total)\% Processor Time'
$cpuUsage = [math]::Round($cpuCounter.CounterSamples.CookedValue)
# Get the number of logical CPU cores
$cpuCores = (Get-CimInstance -ClassName Win32_Processor).NumberOfLogicalProcessors
# Calculate ThrottleLimit based on CPU usage
# Example: If CPU usage is low (<50%), use up to 80% of cores; if high, reduce to 20% or a minimum
if ($cpuUsage -lt 50) {
    $throttleLimit = [math]::Round($cpuCores * 0.8)
} else {
    $throttleLimit = [math]::Max(1, [math]::Round($cpuCores * 0.2))
}
$throttleLimit = 20 # Set a hard cap to prevent overloading the system

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


# Call the new function
$urlHealthPackageData = GenerateUrlHealthReports -SourcePath $global:sourcepath -AccessToken $global:access -ThrottleLimit $global:ThrottleLimit `
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
