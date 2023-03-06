# .SYNOPSIS
#  This VMware Photon OS github branches packages (specs) report script creates an excel prn.
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
#
#  .PREREQUISITES
#    - Script actually tested only on MS Windows OS with Powershell PSVersion 5.1 or higher
#    - downloaded and unzipped branch directories of github.com/vmware/photon 

function ParseDirectory
{
	param (
		[parameter(Mandatory = $true)]
		[string]$SourcePath,
		[parameter(Mandatory = $true)]
		[string]$PhotonDir
	)
    $Packages=@()
    $Objects=Get-ChildItem -Path "$SourcePath\$PhotonDir\SPECS" -Recurse -Directory -Force -ErrorAction SilentlyContinue | Select-Object Name,FullName
    foreach ($object in $objects)
    {
        try
        {
            get-childitem -path $object.FullName -Filter "*.spec" | %{
                $content = $_ | get-content
                $Release=$null
                $Release= (($content | Select-String -Pattern "^Release:")[0].ToString() -replace "Release:", "").Trim()
                $Release = $Release.Replace("%{?dist}","")
                $Release = $Release.Replace("%{?kat_build:.kat}","")
                $Release = $Release.Replace("%{?kat_build:.%kat_build}","")
                $Release = $Release.Replace("%{?kat_build:.%kat}","")
                $Release = $Release.Replace("%{?kernelsubrelease}","")
                $Release = $Release.Replace(".%{dialogsubversion}","")
                $Version=$null
                $version= (($content | Select-String -Pattern "^Version:")[0].ToString() -ireplace "Version:", "").Trim()
                if ($Release -ne $null) {$Version = $Version+"-"+$Release}
                $Source0= (($content | Select-String -Pattern "^Source0:")[0].ToString() -ireplace "Source0:", "").Trim()

                if ($content -ilike '*URL:*') { $url = (($content | Select-String -Pattern "^URL:")[0].ToString() -ireplace "URL:", "").Trim() }

                $srcname=""
                if ($content -ilike '*define srcname*') { $srcname = (($content | Select-String -Pattern '%define srcname')[0].ToString() -ireplace '%define srcname', "").Trim() }
                if ($content -ilike '*global srcname*') { $srcname = (($content | Select-String -Pattern '%global srcname')[0].ToString() -ireplace '%global srcname', "").Trim() }

                $gem_name=""
                if ($content -ilike '*define gem_name*') { $gem_name = (($content | Select-String -Pattern '%define gem_name')[0].ToString() -ireplace '%define gem_name', "").Trim() }
                if ($content -ilike '*global gem_name*') { $gem_name = (($content | Select-String -Pattern '%global gem_name')[0].ToString() -ireplace '%global gem_name', "").Trim() }

                $group=""
                if ($content -ilike '*Group:*') { $group = (($content | Select-String -Pattern '^Group:')[0].ToString() -ireplace 'Group:', "").Trim() }

                $extra_version=""
                if ($content -ilike '*define extra_version*') { $extra_version = (($content | Select-String -Pattern '%define extra_version')[0].ToString() -ireplace '%define extra_version', "").Trim() }

                $main_version=""
                if ($content -ilike '*define main_version*') { $main_version = (($content | Select-String -Pattern '%define main_version')[0].ToString() -ireplace '%define main_version', "").Trim() }

                $byaccdate=""
                if ($content -ilike '*define byaccdate*') { $byaccdate = (($content | Select-String -Pattern '%define byaccdate')[0].ToString() -ireplace '%define byaccdate', "").Trim() }

                $dialogsubversion=""
                if ($content -ilike '*define dialogsubversion*') { $dialogsubversion = (($content | Select-String -Pattern '%define dialogsubversion')[0].ToString() -ireplace '%define dialogsubversion', "").Trim() }

                $libedit_release=""
                if ($content -ilike '*define libedit_release*') { $libedit_release = (($content | Select-String -Pattern '%define libedit_release')[0].ToString() -ireplace '%define libedit_release', "").Trim() }

                $libedit_version=""
                if ($content -ilike '*define libedit_version*') { $libedit_version = (($content | Select-String -Pattern '%define libedit_version')[0].ToString() -ireplace '%define libedit_version', "").Trim() }

                $ncursessubversion=""
                if ($content -ilike '*define ncursessubversion*') { $ncursessubversion = (($content | Select-String -Pattern '%define ncursessubversion')[0].ToString() -ireplace '%define ncursessubversion', "").Trim() }

                $cpan_name=""
                if ($content -ilike '*define cpan_name*') { $cpan_name = (($content | Select-String -Pattern '%define cpan_name')[0].ToString() -ireplace '%define cpan_name', "").Trim() }

                $xproto_ver=""
                if ($content -ilike '*define xproto_ver*') { $xproto_ver = (($content | Select-String -Pattern '%define xproto_ver')[0].ToString() -ireplace '%define xproto_ver', "").Trim() }

                $_url_src=""
                if ($content -ilike '*define _url_src*') { $_url_src = (($content | Select-String -Pattern '%define _url_src')[0].ToString() -ireplace '%define _url_src', "").Trim() }

                $_url_src=""
                if ($content -ilike '*define _repo_ver*') { $_repo_ver = (($content | Select-String -Pattern '%define _repo_ver')[0].ToString() -ireplace '%define _repo_ver', "").Trim() }
                
                $Packages +=[PSCustomObject]@{
                    Spec = $_.Name
                    Version = $Version
                    Name = $object.Name
                    Source0 = $Source0
                    url = $url
                    srcname = $srcname
                    gem_name = $gem_name
                    group = $group
                    extra_version = $extra_version
                    main_version = $main_version
                    byaccdate = $byaccdate
                    dialogsubversion = $dialogsubversion
                    libedit_release = $libedit_release
                    libedit_version = $libedit_version
                    ncursessubversion = $ncursessubversion
                    cpan_name = $cpan_name
                    xproto_ver = $xproto_ver
                    _url_src = $_url_src
                    _repo_ver = $_repo_ver
                }
            }
        }
        catch{}
    }
    return $Packages
}

function Versioncompare
{
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

function urlhealth
{
	param (
		[parameter(Mandatory = $true)]
		$checkurl
	)
    $urlhealthrc=""
    try
    {
        $rc = Invoke-WebRequest -Uri $Source0 -UseDefaultCredentials -UseBasicParsing -Method Head -TimeoutSec 10 -ErrorAction Stop
        $urlhealthrc = [int]$rc.StatusCode
    }
    catch {
        $urlhealthrc = [int]$_.Exception.Response.StatusCode.value__
    }
    return $urlhealthrc
}


# EDIT
# path with all downloaded and unzipped branch directories of github.com/vmware/photon
$sourcepath="$env:public"


function GitPhoton
{
	param (
		[parameter(Mandatory = $true)]
		$release
	)
    #download from repo
    if (!(test-path -path $sourcepath\photon-$release))
    {
        cd $sourcepath
        git clone -b $release https://github.com/vmware/photon $sourcepath\photon-$release
    }
    else
    {
        cd $sourcepath\photon-$release
        git fetch
        if ($release -ieq "master") { git merge origin/master }
        elseif ($release -ieq "dev") { git merge origin/origin/dev }
        else { git merge origin/$release }
    }
}


function CheckURLHealth {
      [CmdletBinding()]
      Param(
        [parameter(Mandatory)]$outputfile,
        [parameter(Mandatory)]$accessToken,
        [parameter(Mandatory,ValueFromPipeline)]$CheckURLHealthPackageObject
     )

    Process{
    # Check Source0 url health in packages5
    $Lines=@()
    $CheckURLHealthPackageObject | foreach {
        $Source0 = $_.Source0


        # cut last index in $_.version and save value in $version
        $Version=""
        $versionArray=($_.version).split("-")
        if ($versionArray.length -gt 0)
        {
            $Version=$versionArray[0]
            for ($i=1;$i -lt ($versionArray.length -1);$i++) {$version=$Version + "-"+$versionArray[$i]}
        }


        # --------------------------------------------------------------------------------------------------------------
        # The following Source0 urls have been detected to be wrong or missspelled.
        # This can change. Hence, this section has to be verified from time to time.
        # Until then, before any Source0 url health check the Source0 url value is changed to a manually verified value.
        # --------------------------------------------------------------------------------------------------------------
        $replace=""

        switch ($_.spec)
        {

        "alsa-lib.spec" {$Source0="https://github.com/alsa-project/alsa-lib/archive/refs/tags/v%{version}.tar.gz"; break}

        "alsa-utils.spec" {$Source0="https://github.com/alsa-project/alsa-utils/archive/refs/tags/v%{version}.tar.gz"; break}

        "apr.spec" {$Source0="https://github.com/apache/apr/archive/refs/tags/%{version}.tar.gz"; break}

        "apr-util.spec" {$Source0="https://github.com/apache/apr-util/archive/refs/tags/%{version}.tar.gz"; break}

        "argon2.spec" {$Source0="https://github.com/P-H-C/phc-winner-argon2/archive/refs/tags/%{version}.tar.gz"; break}

        "audit.spec" {$Source0="https://github.com/linux-audit/audit-userspace/archive/refs/tags/v%{version}.tar.gz"; break}

        "aufs-util.spec" {$Source0="https://github.com/sfjro/aufs-linux/archive/refs/tags/v%{version}.tar.gz"; break} # see https://github.com/sfjro for older linux kernels

        "autogen.spec" {$Source0="https://ftp.gnu.org/gnu/autogen/rel5.18.16/autogen-%{version}.tar.xz"; break}

        "ansible.spec" {$Source0="https://github.com/ansible/ansible/archive/refs/tags/v%{version}.tar.gz"; break}

        "apache-ant.spec" {$Source0="https://github.com/apache/ant/archive/refs/tags/rel/%{version}.tar.gz"; break}

        "apache-maven.spec" {$Source0="https://github.com/apache/maven/archive/refs/tags/maven-%{version}.tar.gz"; break}

        "apache-tomcat.spec" {$Source0="https://github.com/apache/tomcat/archive/refs/tags/%{version}.tar.gz"; break}

        "apache-tomcat-native.spec" {$Source0="https://github.com/apache/tomcat-native/archive/refs/tags/%{version}.tar.gz"; break}

        "atk.spec" {$Source0="https://github.com/GNOME/atk/archive/refs/tags/%{version}.tar.gz"; break}

        "backward-cpp.spec" {$Source0="https://github.com/bombela/backward-cpp/archive/refs/tags/v%{version}.tar.gz"; break}

        "bindutils.spec" {$Source0="https://github.com/isc-projects/bind9/archive/refs/tags/v%{version}.tar.gz"; break}

        "bubblewrap.spec" {$Source0="https://github.com/containers/bubblewrap/archive/refs/tags/v%{version}.tar.gz"; break}

        "bzip2.spec" {$Source0="https://sourceware.org/pub/bzip2/bzip2-%{version}.tar.gz"; break}
        
        "cairo.spec" {$Source0="https://gitlab.freedesktop.org/cairo/cairo/-/archive/%{version}/cairo-%{version}.tar.gz"; break}            

        "calico-confd.spec" {$Source0="https://github.com/kelseyhightower/confd/archive/refs/tags/v%{version}.tar.gz"; break}

        "cassandra.spec" {$Source0="https://github.com/apache/cassandra/archive/refs/tags/cassandra-%{version}.tar.gz"; break}     

        "clang.spec" {$Source0="https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/clang-%{version}.src.tar.xz"; break}

        "chrpath.spec" {$Source0="https://github.com/jwilk-mirrors/chrpath/archive/refs/tags/RELEASE_%{version}.tar.gz"; break}   

        "cloud-init.spec" {$Source0="https://github.com/canonical/cloud-init/archive/refs/tags/%{version}.tar.gz"; break}

        "cmake.spec" {$Source0="https://github.com/Kitware/CMake/releases/download/v%{version}/cmake-%{version}.tar.gz"; break}    

        "confd.spec" {$Source0="https://github.com/projectcalico/confd/archive/refs/tags/v%{version}-0.dev.tar.gz"; break} # Deprecated, new location https://github.com/projectcalico/calico
    
        "conmon.spec" {$Source0="https://github.com/containers/conmon/archive/refs/tags/v%{version}.tar.gz"; break}

        "containers-common.spec" {$Source0="https://github.com/containers/common/archive/refs/tags/v%{version}.tar.gz"; break}
    
        "commons-daemon.spec" {$Source0="https://archive.apache.org/dist/commons/daemon/source/commons-daemon-%{version}-src.tar.gz"; break}

        "compat-gdbm.spec" {$Source0="https://ftp.gnu.org/gnu/gdbm/gdbm-%{version}.tar.gz"; break}

        "conntrack-tools.spec" {$Source0="https://www.netfilter.org/pub/conntrack-tools/conntrack-tools-%{version}.tar.bz2"; break}
    
        "coredns.spec" {$Source0="https://github.com/coredns/coredns/archive/refs/tags/v%{version}.tar.gz"; break}

        "cracklib.spec" {$Source0="https://github.com/cracklib/cracklib/archive/refs/tags/v%{version}.tar.gz"; break}        

        "cri-tools.spec" {$Source0="https://github.com/kubernetes-sigs/cri-tools/archive/refs/tags/v%{version}.tar.gz"; break}

        "cryptsetup.spec" {$Source0="https://github.com/mbroz/cryptsetup/archive/refs/tags/v%{version}.tar.gz"; break}

        "cups.spec" {$Source0="https://github.com/OpenPrinting/cups/archive/refs/tags/v%{version}.tar.gz"; break}

        "cve-check-tool.spec" {$Source0="https://github.com/clearlinux/cve-check-tool/archive/refs/tags/v%{version}.tar.gz"; break} # deprecated on January 7th 2023
   
        "cyrus-sasl.spec" {$Source0="https://github.com/cyrusimap/cyrus-sasl/archive/refs/tags/cyrus-sasl-%{version}.tar.gz"; break}    

        "cython3.spec" {$Source0="https://github.com/cython/cython/archive/refs/tags/%{version}.tar.gz"; break}

        "device-mapper-multipath.spec" {$Source0="https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz"; break}

        "device-mapper-multipath.spec" {$Source0="https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz"; break}

        "dialog.spec" {$Source0="https://invisible-island.net/archives/dialog/dialog-%{version}-20160209.tgz"; break}

        "docker-20.10.spec" {$Source0="https://github.com/moby/moby/archive/refs/tags/v%{version}.tar.gz"; break}

        "docker-pycreds.spec" {$Source0="https://github.com/shin-/dockerpy-creds/archive/refs/tags/%{version}.tar.gz"; break}

        "dotnet-runtime.spec" {$Source0="https://github.com/dotnet/runtime/archive/refs/tags/v%{version}.tar.gz"; break}
        
        "dotnet-sdk.spec" {$Source0="https://github.com/dotnet/sdk/archive/refs/tags/v%{version}.tar.gz"; break}

        "doxygen.spec" {$Source0="https://github.com/doxygen/doxygen/archive/refs/tags/Release_%{version}.tar.gz"; break}
        
        "ebtables.spec" {$Source0="https://www.netfilter.org/pub/ebtables/ebtables-%{version}.tar.gz"; break}

        "ed.spec" {$Source0="https://ftp.gnu.org/gnu/ed/ed-%{version}.tar.lz"; break}

        "efibootmgr.spec" {$Source0="https://github.com/rhboot/efibootmgr/archive/refs/tags/%{version}.tar.gz"; break}

        "emacs.spec" {$Source0="http://ftpmirror.gnu.org/emacs/emacs-%{version}.tar.xz"; break}

        "erlang.spec" {$Source0="https://github.com/erlang/otp/archive/refs/tags/OTP-%{version}.tar.gz"; break}

        "erlang-sd_notify.spec" {$Source0="https://github.com/systemd/erlang-sd_notify/archive/refs/tags/v%{version}.tar.gz"; break}

        "fatrace.spec" {$Source0="https://github.com/martinpitt/fatrace/archive/refs/tags/%{version}.tar.gz"; break}

        "flex.spec" {$Source0="https://github.com/westes/flex/archive/refs/tags/v%{version}.tar.gz"; break}

        "file.spec" {$Source0="http://ftp.astron.com/pub/file/file-%{version}.tar.gz"; break}

        "freetds.spec" {$Source0="https://www.freetds.org/files/stable/freetds-%{version}.tar.gz"; break}

        "fribidi.spec" {$Source0="https://github.com/fribidi/fribidi/archive/refs/tags/v%{version}.tar.gz"; break}

        "fuse-overlayfs-snapshotter.spec" {$Source0="https://github.com/containers/fuse-overlayfs/archive/refs/tags/v%{version}.tar.gz"; break}

        "gtest.spec" {$Source0="https://github.com/google/googletest/archive/refs/tags/release-%{version}.tar.gz"; break}

        "glib.spec" {$Source0="https://github.com/GNOME/glib/archive/refs/tags/%{version}.tar.gz"; break}

        "glib-networking.spec" {$Source0="https://github.com/GNOME/glib-networking/archive/refs/tags/%{version}.tar.gz"; break}

        "glibmm.spec" {$Source0="https://github.com/GNOME/glibmm/archive/refs/tags/%{version}.tar.gz"; break}

        "glslang.spec" { if ($version -gt "9") {$Source0="https://github.com/KhronosGroup/glslang/archive/refs/tags/sdk-%{version}.tar.gz"; break}
        else {$Source0="https://github.com/KhronosGroup/glslang/archive/refs/tags/%{version}.tar.gz"; break}}

        "gnome-common.spec" {$Source0="https://github.com/GNOME/gnome-common/archive/refs/tags/%{version}.tar.gz"; break}
    
        "gobject-introspection.spec" {$Source0="https://github.com/GNOME/gobject-introspection/archive/refs/tags/%{version}.tar.gz"; break}

        "google-compute-engine.spec" {if ($version -lt "20190916") {$Source0="https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/%{version}.tar.gz"; break}
        else {$Source0="https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/v%{version}.tar.gz"; break}}

        "graphene.spec" {$Source0="https://github.com/ebassi/graphene/archive/refs/tags/%{version}.tar.gz"; break}

        "gtest.spec" {$Source0="https://github.com/google/googletest/archive/refs/tags/release-%{version}.tar.gz"; break}

        "gtk3.spec" {$Source0="https://github.com/GNOME/gtk/archive/refs/tags/%{version}.tar.gz"; break}

        "gtk-doc.spec" {if ($version -lt "1.33.0") {$Source0="https://github.com/GNOME/gtk-doc/archive/refs/tags/GTK_DOC_%{version}.tar.gz"; break}
        else {$Source0="https://github.com/GNOME/gtk-doc/archive/refs/tags/%{version}.tar.gz"; break}}

        "guile.spec" {$Source0="https://ftp.gnu.org/gnu/guile/guile-%{version}.tar.gz"; break}

        "haproxy.spec" { $tmpminor=($version.split(".")[0]+"."+$version.split(".")[1]);$Source0="https://www.haproxy.org/download/$tmpminor/src/devel/haproxy-%{version}.tar.gz"; break}

        "haproxy-dataplaneapi.spec" {$Source0="https://github.com/haproxytech/dataplaneapi/archive/refs/tags/v%{version}.tar.gz"; break}

        "haveged.spec" {$Source0="https://github.com/jirka-h/haveged/archive/refs/tags/v%{version}.tar.gz"; break}

        "hawkey.spec" {$Source0="https://github.com/rpm-software-management/hawkey/archive/refs/tags/hawkey-%{version}.tar.gz"; break}

        "httpd.spec" {$Source0="https://github.com/apache/httpd/archive/refs/tags/%{version}.tar.gz"; break}

        "httpd-mod_kj.spec" {$Source0="https://github.com/apache/tomcat-connectors/archive/refs/tags/JK_%{version}.tar.gz"; break }

        "http-parser.spec" {$Source0="https://github.com/nodejs/http-parser/archive/refs/tags/v%{version}.tar.gz"; break} # deprecated on 6th November 2022

        "imagemagick.spec" {$Source0="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/%{version}.tar.gz"; break} # deprecated on 6th November 2022

        "inih.spec" {$Source0="https://github.com/benhoyt/inih/archive/refs/tags/r%{version}.tar.gz"; break}

        "intltool.spec" {$Source0="https://launchpad.net/intltool/trunk/%{version}/+download/intltool-%{version}.tar.gz"; break}

        "ipmitool.spec" {$Source0="https://github.com/ipmitool/ipmitool/archive/refs/tags/IPMITOOL_%{version}.tar.gz"; break}

        "ipset.spec" {$Source0="https://www.netfilter.org/pub/ipset/ipset-%{version}.tar.bz2"; break}

        "iptables.spec" {$Source0="https://www.netfilter.org/pub/iptables/iptables-%{version}.tar.bz2"; break}

        "iputils.spec" {$Source0="https://github.com/iputils/iputils/archive/refs/tags/s%{version}.tar.gz"; break}

        "json-glib.spec" {$Source0="https://github.com/GNOME/json-glib/archive/refs/tags/%{version}.tar.gz"; break}

        "kafka.spec" {$Source0="https://github.com/apache/kafka/archive/refs/tags/%{version}.tar.gz"; $replace="kafka-"; break}

        "kbd.spec" {$Source0="https://github.com/legionus/kbd/archive/refs/tags/%{version}.tar.gz"; break}

        "keyutils.spec" {$Source0="https://git.kernel.org/pub/scm/linux/kernel/git/dhowells/keyutils.git/snapshot/keyutils-%{version}.tar.gz"; break}

        "lapack.spec" {$Source0="https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v%{version}.tar.gz"; break}

        "lasso.spec" {$Source0="https://dev.entrouvert.org/lasso/lasso-%{version}.tar.gz"; break}

        "leveldb.spec" {$Source0="https://github.com/google/leveldb/archive/refs/tags/v%{version}.tar.gz"; break}

        "libconfig.spec" {$Source0="https://github.com/hyperrealm/libconfig/archive/refs/tags/v%{version}.tar.gz"; break}

        "libgcrypt.spec" {$Source0="https://gnupg.org/ftp/gcrypt/libgcrypt/libgcrypt-%{version}.tar.bz2"; break}
         
        "libgpg-error.spec" {$Source0="https://gnupg.org/ftp/gcrypt/libgpg-error/libgpg-error-%{version}.tar.bz2"; break}

        "libXinerama.spec" {$Source0="https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/archive/libXinerama-%{version}/libxinerama-libXinerama-%{version}.tar.gz"; break}

        "libffi.spec" {$Source0="https://github.com/libffi/libffi/archive/refs/tags/v%{version}.tar.gz"; break}

        "libmetalink.spec" {$Source0="https://launchpad.net/libmetalink/trunk/libmetalink-%{version}/+download/libmetalink-%{version}.tar.bz2"; break}

        "libmnl.spec" {$Source0="https://www.netfilter.org/pub/libmnl/libmnl-%{version}.tar.bz2"; break}

        "libnl.spec" {$Source0="https://github.com/thom311/libnl/archive/refs/tags/libnl%{version}.tar.gz"; break}
        
        "libnetfilter_conntrack.spec" {$Source0="https://www.netfilter.org/pub/libnetfilter_conntrack/libnetfilter_conntrack-%{version}.tar.bz2"; break}

        "libnetfilter_cthelper.spec" {$Source0="https://www.netfilter.org/pub/libnetfilter_cthelper/libnetfilter_cthelper-%{version}.tar.bz2"; break}

        "libnetfilter_cttimeout.spec" {$Source0="https://www.netfilter.org/pub/libnetfilter_cttimeout/libnetfilter_cttimeout-%{version}.tar.bz2"; break}

        "libnetfilter_queue.spec" {$Source0="https://www.netfilter.org/pub/libnetfilter_queue/libnetfilter_queue-%{version}.tar.bz2"; break}

        "libnfnetlink.spec" {$Source0="https://www.netfilter.org/pub/libnfnetlink/libnfnetlink-%{version}.tar.bz2"; break}

        "libnftnl.spec" {$Source0="https://www.netfilter.org/pub/libnftnl/libnftnl-%{version}.tar.bz2"; break}

        "librsync.spec" {$Source0="https://github.com/librsync/librsync/archive/refs/tags/v%{version}.tar.gz"; break}

        "libsigc++.spec" {$Source0="https://github.com/libsigcplusplus/libsigcplusplus/archive/refs/tags/%{version}.tar.gz"; break}

        "libsoup.spec" {$Source0="https://github.com/GNOME/libsoup/archive/refs/tags/%{version}.tar.gz"; break}       

        "libxml2.spec" {$Source0="https://github.com/GNOME/libxml2/archive/refs/tags/v%{version}.tar.gz"; break}

        "libxslt.spec" {$Source0="https://github.com/GNOME/libxslt/archive/refs/tags/v%{version}.tar.gz"; break}

        "lldb.spec" {$Source0="https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/lldb-%{version}.src.tar.xz"; break}

        "llvm.spec" {$Source0="https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/llvm-%{version}.src.tar.xz"; break}

        "lm-sensors.spec" {$Source0="https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V%{version}.tar.gz"; break}

        "lshw.spec" {$Source0="https://github.com/lyonel/lshw/archive/refs/tags/%{version}.tar.gz"; break}

        "lsof.spec" {$Source0="https://github.com/lsof-org/lsof/archive/refs/tags/%{version}.tar.gz"; break}

        "lksctp-tools.spec" {$Source0="https://github.com/sctp/lksctp-tools/archive/refs/tags/v%{version}.tar.gz"; break}

        "libev.spec" {$Source0="http://dist.schmorp.de/libev/Attic/libev-%{version}.tar.gz"; break}

        "libselinux.spec" {$Source0="https://github.com/SELinuxProject/selinux/archive/refs/tags/%{version}.tar.gz"; break}

        "libtar.spec" {$Source0="https://github.com/tklauser/libtar/archive/refs/tags/v%{version}.tar.gz"; break}

        "lightwave.spec" {$Source0="https://github.com/vmware-archive/lightwave/archive/refs/tags/v%{version}.tar.gz"; break}

        "linux-firmware.spec" {$Source0="https://mirrors.edge.kernel.org/pub/linux/kernel/firmware/linux-firmware-%{version}.tar.gz"; break}

        "linux-PAM.spec" {$Source0="https://github.com/linux-pam/linux-pam/archive/refs/tags/Linux-PAM-%{version}.tar.gz"; break}

        "linuxptp.spec" {$Source0="https://github.com/richardcochran/linuxptp/archive/refs/tags/v%{version}.tar.gz"; break}

        "lttng-tools.spec" {$Source0="https://github.com/lttng/lttng-tools/archive/refs/tags/v%{version}.tar.gz"; break}

        "lxcfs.spec" {$Source0="https://github.com/lxc/lxcfs/archive/refs/tags/lxcfs-%{version}.tar.gz"; break}

        "man-db.spec" {$Source0="https://gitlab.com/man-db/man-db/-/archive/%{version}/man-db-%{version}.tar.gz"; break}

        "man-pages.spec" {$Source0="https://mirrors.edge.kernel.org/pub/linux/docs/man-pages/Archive/man-pages-%{version}.tar.gz"; break}
    
        "mariadb.spec" {$Source0="https://github.com/MariaDB/server/archive/refs/tags/mariadb-%{version}.tar.gz"; break}

        "mc.spec" {$Source0="https://github.com/MidnightCommander/mc/archive/refs/tags/%{version}.tar.gz"; break}

        "mesa.spec" {$Source0="https://gitlab.freedesktop.org/mesa/mesa/-/archive/mesa-%{version}/mesa-mesa-%{version}.tar.gz"; break}

        "mkinitcpio.spec" {$Source0="https://github.com/archlinux/mkinitcpio/archive/refs/tags/v%{version}.tar.gz"; break}

        "mpc.spec" {$Source0="https://www.multiprecision.org/downloads/mpc-%{version}.tar.gz"; break}
    
        "monitoring-plugins.spec" {$Source0="https://github.com/monitoring-plugins/monitoring-plugins/archive/refs/tags/v%{version}.tar.gz"; break}
    
        "mysql.spec" {$Source0="https://github.com/mysql/mysql-server/archive/refs/tags/mysql-%{version}.tar.gz"; break}

        "nano.spec" {$Source0="https://ftpmirror.gnu.org/nano/nano-%{version}.tar.xz"; break}

        "ncurses.spec" {$Source0="https://github.com/ThomasDickey/ncurses-snapshots/archive/refs/tags/v%{version}.tar.gz"; break}

        "net-tools.spec" {$Source0="https://github.com/ecki/net-tools/archive/refs/tags/v%{version}.tar.gz"; break}

        "netmgmt.spec" {$Source0="https://github.com/vmware/photonos-netmgr/archive/refs/tags/v%{version}.tar.gz"; break}

        "nftables.spec" {$Source0="https://www.netfilter.org/pub/nftables/nftables-%{version}.tar.bz2"; break}
      
        "openldap.spec" {$Source0="https://github.com/openldap/openldap/archive/refs/tags/OPENLDAP_REL_ENG_%{version}.tar.gz"; break}

        "ostree.spec" {$Source0="https://github.com/ostreedev/ostree/archive/refs/tags/v%{version}.tar.gz"; break}

        "pam_tacplus.spec" {$Source0="https://github.com/kravietz/pam_tacplus/archive/refs/tags/v%{version}.tar.gz"; break}

        "pandoc.spec" {$Source0="https://github.com/jgm/pandoc/archive/refs/tags/%{version}.tar.gz"; break}

        "pango.spec" {$Source0="https://github.com/GNOME/pango/archive/refs/tags/%{version}.tar.gz"; break}

        "patch.spec" {$Source0="https://ftp.gnu.org/gnu/patch/patch-%{version}.tar.gz"; break}

        "perl-URI.spec" {$Source0="https://github.com/libwww-perl/URI/archive/refs/tags/v%{version}.tar.gz"; break}

        "popt.spec" {$Source0="http://rpm5.org/files/popt/popt-%{version}.tar.gz"; break}

        "powershell.spec" {$Source0="https://github.com/PowerShell/PowerShell/archive/refs/tags/v%{version}.tar.gz"; break}

        "protobuf-c.spec" {$Source0="https://github.com/protobuf-c/protobuf-c/archive/refs/tags/v%{version}.tar.gz"; break}

        "pth.spec" {$Source0="https://ftp.gnu.org/gnu/pth/pth-%{version}.tar.gz"; break}

        "pycurl.spec" {$Source0="https://github.com/pycurl/pycurl/archive/refs/tags/REL_%{version}.tar.gz"; break}

        "python-requests.spec" {$Source0="https://github.com/psf/requests/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-urllib3.spec" {$Source0="https://github.com/urllib3/urllib3/archive/refs/tags/%{version}.tar.gz"; break}
        "pmd-nextgen.spec" {$Source0="https://github.com/vmware/pmd/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-dateutil.spec" {$Source0="https://github.com/dateutil/dateutil/archive/refs/tags/%{version}.tar.gz"; break}
        "python-alabaster.spec" {$Source0="https://github.com/bitprophet/alabaster/archive/refs/tags/%{version}.tar.gz"; break}
        "python-altgraph.spec" {$Source0="https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz"; break}       
        "python-appdirs.spec" {$Source0="https://github.com/ActiveState/appdirs/archive/refs/tags/%{version}.tar.gz"; break}
        "python-argparse.spec" {$Source0="https://github.com/ThomasWaldmann/argparse/archive/refs/tags/r140.tar.gz"; break} #github archived
        "python-atomicwrites.spec" {$Source0="https://github.com/untitaker/python-atomicwrites/archive/refs/tags/1.4.1.tar.gz"; break} #github archived
        "python-attrs.spec" {$Source0="https://github.com/python-attrs/attrs/archive/refs/tags/%{version}.tar.gz"; break}
        "python-autopep8.spec" {$Source0="https://github.com/hhatto/autopep8/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-babel.spec" {$Source0="https://github.com/python-babel/babel/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-backports.ssl_match_hostname*" {$Source0="https://files.pythonhosted.org/packages/ff/2b/8265224812912bc5b7a607c44bf7b027554e1b9775e9ee0de8032e3de4b2/backports.ssl_match_hostname-3.7.0.1.tar.gz"; break}
        "python-altgraph.spec" {$Source0="https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-bcrypt.spec" {$Source0="https://github.com/pyca/bcrypt/archive/refs/tags/%{version}.tar.gz"; break}
        "python-boto3.spec" {$Source0="https://github.com/boto/boto3/archive/refs/tags/%{version}.tar.gz"; break}
        "python-botocore.spec" {$Source0="https://github.com/boto/botocore/archive/refs/tags/%{version}.tar.gz"; break}
        "python-cachecontrol.spec" {$Source0="https://github.com/ionrock/cachecontrol/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-cassandra-driver.spec" {$Source0="https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz"; break}
        "python-certifi.spec" {$Source0="https://github.com/certifi/python-certifi/archive/refs/tags/%{version}.tar.gz"; break}
        "python-chardet.spec" {$Source0="https://github.com/chardet/chardet/archive/refs/tags/%{version}.tar.gz"; break}
        "python-charset-normalizer.spec" {$Source0="https://github.com/Ousret/charset_normalizer/archive/refs/tags/%{version}.tar.gz"; break}
        "python-click.spec" {$Source0="https://github.com/pallets/click/archive/refs/tags/%{version}.tar.gz"; break}
        "python-cql.spec" {$Source0="https://storage.googleapis.com/google-code-archive-downloads/v2/apache-extras.org/cassandra-dbapi2/cql-%{version}.tar.gz"; break}
        "python-cqlsh.spec" {$Source0="hhttps://github.com/jeffwidman/cqlsh/archive/refs/tags/%{version}.tar.gz"; break}
        "python-ConcurrentLogHandler.spec" {$Source0="https://github.com/Preston-Landers/concurrent-log-handler/archive/refs/tags/%{version}.tar.gz"; break}
        "python-certifi.spec" {$Source0="https://github.com/certifi/python-certifi/archive/refs/tags/%{version}.tar.gz"; break}
        "python-ConcurrentLogHandler.spec" {$Source0="https://github.com/Preston-Landers/concurrent-log-handler/archive/refs/tags/%{version}.tar.gz" }
        "python-configparser.spec" {$Source0="https://github.com/jaraco/configparser/archive/refs/tags/%{version}.tar.gz"; break}
        "python-constantly.spec" {$Source0="https://github.com/twisted/constantly/archive/refs/tags/%{version}.tar.gz"; break}
        "python-cql.spec" {$Source0="https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz"; break}
        "python-cqlsh.spec" {$Source0="https://github.com/jeffwidman/cqlsh/archive/refs/tags/%{version}.tar.gz"; break}
        "python-decorator.spec" {$Source0="https://github.com/micheles/decorator/archive/refs/tags/%{version}.tar.gz"; break}
        "python-deepmerge.spec" {$Source0="https://github.com/toumorokoshi/deepmerge/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-defusedxml.spec" {$Source0="https://github.com/tiran/defusedxml/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-distro.spec" {$Source0="https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz"; break}          
        "python3-distro.spec" {$Source0="https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz"; break} 
        "python-docopt.spec" {$Source0="https://github.com/docopt/docopt/archive/refs/tags/%{version}.tar.gz"; break}
        "python-email-validator.spec" {$Source0="https://github.com/JoshData/python-email-validator/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-etcd.spec" {$Source0="https://github.com/jplana/python-etcd/archive/refs/tags/%{version}.tar.gz"; break}
        "python-ethtool.spec" {$Source0="https://github.com/fedora-python/python-ethtool/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-filelock.spec" {$Source0="https://github.com/tox-dev/py-filelock/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-fuse.spec" {$Source0="https://github.com/libfuse/python-fuse/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-futures.spec" {$Source0="https://github.com/agronholm/pythonfutures/archive/refs/tags/%{version}.tar.gz"; break}
        "python-geomet.spec" {$Source0="https://github.com/geomet/geomet/archive/refs/tags/%{version}.tar.gz"; break}
        "python-gevent.spec" {$Source0="https://github.com/gevent/gevent/archive/refs/tags/%{version}.tar.gz"; break}
        "python-gevent.spec" {$Source0="https://github.com/gevent/gevent/archive/refs/tags/%{version}.tar.gz"; break}
        "python-graphviz.spec" {$Source0="https://github.com/xflr6/graphviz/archive/refs/tags/%{version}.tar.gz"; break}
        "python-greenlet.spec" {$Source0="https://github.com/python-greenlet/greenlet/archive/refs/tags/%{version}.tar.gz"; break}
        "python-hyperlink.spec" {$Source0="https://github.com/python-hyper/hyperlink/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-hypothesis.spec" {$Source0="https://github.com/HypothesisWorks/hypothesis/archive/refs/tags/hypothesis-python-%{version}.tar.gz"; break}
        "python-idna.spec" {$Source0="https://github.com/kjd/idna/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-imagesize.spec" {$Source0="https://github.com/shibukawa/imagesize_py/archive/refs/tags/%{version}.tar.gz"; break}
        "python-incremental.spec" {$Source0="https://github.com/twisted/incremental/archive/refs/tags/incremental-%{version}.tar.gz"; break}
        "python-iniparse.spec" {$Source0="https://github.com/candlepin/python-iniparse/archive/refs/tags/%{version}.tar.gz"; break}   
        "python-ipaddress.spec" {$Source0="https://github.com/phihag/ipaddress/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-jinja.spec" {$Source0="https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz"; break}
        "python-jmespath.spec" {$Source0="https://github.com/jmespath/jmespath.py/archive/refs/tags/%{version}.tar.gz"; break}
        "python-jsonpatch.spec" {$Source0="https://github.com/stefankoegl/python-json-patch/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-jsonschema.spec" {$Source0="https://github.com/python-jsonschema/jsonschema/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-M2Crypto.spec" {$Source0="https://gitlab.com/m2crypto/m2crypto/-/archive/%{version}/m2crypto-%{version}.tar.gz"; break}
        "python-mako.spec" {$Source0="https://github.com/sqlalchemy/mako/archive/refs/tags/rel_%{version}.tar.gz"; break}
        "python-markupsafe.spec" {$Source0="https://github.com/pallets/markupsafe/archive/refs/tags/%{version}.tar.gz"; break}
        "python-more-itertools.spec" {$Source0="https://github.com/more-itertools/more-itertools/archive/refs/tags/%{version}.tar.gz"; break}
        "python-msgpack.spec" {if ($version -lt "0.60.0") {$Source0="https://github.com/msgpack/msgpack-python/archive/refs/tags/%{version}.tar.gz"} else {$Source0="https://github.com/msgpack/msgpack-python/archive/refs/tags/v%{version}.tar.gz"}; break}
        "python-ndg-httpsclient.spec" {$Source0="https://github.com/cedadev/ndg_httpsclient/archive/refs/tags/%{version}.tar.gz"; break}
        "python-numpy.spec" {$Source0="https://github.com/numpy/numpy/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-jinja2.spec" {$Source0="https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz"; break}
        "python-ntplib.spec" {$Source0="https://github.com/cf-natali/ntplib/archive/refs/tags/%{version}.tar.gz"; break}
        "python-oauthlib.spec" {$Source0="https://github.com/oauthlib/oauthlib/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-packaging.spec" {$Source0="https://github.com/pypa/packaging/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pam.spec" {$Source0="https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pexpect.spec" {$Source0="https://github.com/pexpect/pexpect/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pip.spec" {$Source0="https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz"; break}
        "python3-pip.spec" {$Source0="https://github.com/pypa/pip/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pluggy.spec" {$Source0="https://github.com/pytest-dev/pluggy/archive/refs/tags/%{version}.tar.gz"; break}
        "python-ply.spec" {$Source0="https://github.com/dabeaz/ply/archive/refs/tags/%{version}.tar.gz"; break}
        "python-prometheus_client.spec" {$Source0="https://github.com/prometheus/client_python/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-py.spec" {$Source0="https://github.com/pytest-dev/py/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pyasn1-modules.spec" {$Source0="https://github.com/etingof/pyasn1-modules/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pycodestyle.spec" {$Source0="https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz"; break} # duplicate of python-pam
        "python-pycryptodomex.spec" {$Source0="https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pyhamcrest.spec" {$Source0="https://github.com/hamcrest/PyHamcrest/archive/refs/tags/V%{version}.tar.gz"; break}
        "python-pyinstaller-hooks-contrib.spec" {$Source0="https://github.com/pyinstaller/pyinstaller-hooks-contrib/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pyjwt.spec" {$Source0="https://github.com/jpadilla/pyjwt/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pyparsing.spec" {$Source0="https://github.com/pyparsing/pyparsing/archive/refs/tags/pyparsing_%{version}.tar.gz"; break}
        "python-pycparser.spec" {$Source0="https://github.com/eliben/pycparser/archive/refs/tags/release_v%{version}.tar.gz"; break}
        "python-pycryptodome.spec" {$Source0="https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pydantic.spec" {$Source0="https://github.com/pydantic/pydantic/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pyflakes.spec" {$Source0="https://github.com/PyCQA/pyflakes/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pygments.spec" {$Source0="https://github.com/pygments/pygments/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pyinstaller.spec" {$Source0="https://github.com/pyinstaller/pyinstaller/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pyjsparser.spec" {$Source0="https://github.com/PiotrDabkowski/pyjsparser/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-PyNaCl.spec" {$Source0="https://github.com/pyca/pynacl/archive/refs/tags/%{version}.tar.gz"; break}      
        "python-pyopenssl.spec" {$Source0="https://github.com/pyca/pyopenssl/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pyrsistent.spec" {$Source0="https://github.com/tobgu/pyrsistent/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pyserial.spec" {$Source0="https://github.com/pyserial/pyserial/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pytest.spec" {$Source0="https://github.com/pytest-dev/pytest/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pyudev.spec" {$Source0="https://github.com/pyudev/pyudev/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-pyvim.spec" {$Source0="https://github.com/prompt-toolkit/pyvim/archive/refs/tags/%{version}.tar.gz"; break}
        "python-pyvmomi.spec" {$Source0="https://github.com/vmware/pyvmomi/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-resolvelib.spec" {$Source0="https://github.com/sarugaku/resolvelib/archive/refs/tags/%{version}.tar.gz"; break}
        "python-ruamel-yaml.spec" {$Source0="https://files.pythonhosted.org/packages/17/2f/f38332bf6ba751d1c8124ea70681d2b2326d69126d9058fbd9b4c434d268/ruamel.yaml-%{version}.tar.gz"; break}
        "python-scp.spec" {$Source0="https://github.com/jbardin/scp.py/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-service_identity.spec" {$Source0="https://github.com/pyca/service-identity/archive/refs/tags/%{version}.tar.gz"; break}
        "python-setuptools.spec" {$Source0="https://github.com/pypa/setuptools/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-simplejson.spec" {$Source0="https://github.com/simplejson/simplejson/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-snowballstemmer.spec" {$Source0="https://github.com/snowballstem/snowball/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-sphinx.spec" {$Source0="https://github.com/sphinx-doc/sphinx/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-sqlalchemy.spec" {$Source0="https://github.com/sqlalchemy/sqlalchemy/archive/refs/tags/rel_%{version}.tar.gz"; break}
        "python-subprocess32.spec" {$Source0="https://github.com/google/python-subprocess32/archive/refs/tags/%{version}.tar.gz"; break} # archived October 27th 2022
        "python-terminaltables.spec" {$Source0="https://github.com/Robpol86/terminaltables/archive/refs/tags/v%{version}.tar.gz"; break} # archived 7th December 2021
        "python-toml.spec" {$Source0="https://github.com/uiri/toml/archive/refs/tags/%{version}.tar.gz"; break}
        "python-typing.spec" {$Source0="https://github.com/python/typing/archive/refs/tags/%{version}.tar.gz"; break}
        "python-vcversioner.spec" {$Source0="https://github.com/habnabit/vcversioner/archive/refs/tags/%{version}.tar.gz"; break}
        "python-virtualenv.spec" {$Source0="https://github.com/pypa/virtualenv/archive/refs/tags/%{version}.tar.gz"; break}
        "python-webob.spec" {$Source0="https://github.com/Pylons/webob/archive/refs/tags/%{version}.tar.gz"; break}
        "python-websocket-client.spec" {$Source0="https://github.com/websocket-client/websocket-client/archive/refs/tags/v%{version}.tar.gz"; break}
        "python-werkzeug.spec" {$Source0="https://github.com/pallets/werkzeug/archive/refs/tags/%{version}.tar.gz"; break}
        "python-zmq.spec" {$Source0="https://github.com/zeromq/pyzmq/archive/refs/tags/v%{version}.tar.gz"; break}
        "pyYaml.spec" {$Source0="https://github.com/yaml/pyyaml/archive/refs/tags/%{version}.tar.gz"; break}

        "raspberrypi-firmware.spec"
        {
            $Source0="https://github.com/raspberrypi/firmware/archive/refs/tags/%{version}.tar.gz"
            $tmpversion=$_.version
            $tmpversion = $tmpversion -ireplace "1.",""
            $version = [System.String]::Concat("1.",[string]$tmpversion.Replace(".",""))
            break
        }

        "rabbitmq.spec" {$Source0="https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz"; break}

        "rabbitmq3.10.spec" {$Source0="https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz"; break}      

        "rpcsvc-proto.spec" {$Source0="https://github.com/thkukuk/rpcsvc-proto/archive/refs/tags/v%{version}.tar.gz"; break}

        "rpm.spec" {$Source0="https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-%{version}-release.tar.gz"; break}

        "rrdtool.spec" {$Source0="https://github.com/oetiker/rrdtool-1.x/archive/refs/tags/v%{version}.tar.gz"; break}

        "rt-tests.spec" {$Source0="https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/snapshot/rt-tests-%{version}.tar.gz"; break}

        "ruby.spec" {$Source0="https://github.com/ruby/ruby/archive/refs/tags/v%{version}.tar.gz"; break}

        "serf.spec" {$Source0="https://github.com/apache/serf/archive/refs/tags/%{version}.tar.gz"; break }

        "shadow.spec" {$Source0="https://github.com/shadow-maint/shadow/archive/refs/tags/%{version}.tar.gz"; break}

        "shared-mime-info.spec" {$Source0="https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/%{version}/shared-mime-info-%{version}.tar.gz"; break}

        "slirp4netns.spec" {$Source0="https://github.com/rootless-containers/slirp4netns/archive/refs/tags/v%{version}.tar.gz"; break}

        "spirv-headers.spec" {$Source0="https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/sdk-%{version}.tar.gz"; break}

        "spirv-tools.spec" {$Source0="https://github.com/KhronosGroup/SPIRV-Tools/archive/refs/tags/sdk-%{version}.tar.gz"; break}

        "sqlite.spec" {$Source0="https://github.com/sqlite/sqlite/archive/refs/tags/version-%{version}.tar.gz"; break}

        "subversion.spec" {$Source0="https://github.com/apache/subversion/archive/refs/tags/%{version}.tar.gz"; break }

        "systemd.spec" {$Source0="https://github.com/systemd/systemd-stable/archive/refs/tags/v%{version}.tar.gz"; break}

        "systemtap.spec" {$Source0="https://sourceware.org/ftp/systemtap/releases/systemtap-%{version}.tar.gz"; break}

        "tar.spec" {$Source0="https://ftp.gnu.org/gnu/tar/tar-%{version}.tar.xz"; break}

        "tboot.spec" {$Source0="https://sourceforge.net/projects/tboot/files/tboot/tboot-%{version}.tar.gz/download"; break}

        "tcp_wrappers.spec" {$Source0="http://ftp.porcupine.org/pub/security/tcp_wrappers_%{version}.tar.gz"; break}

        "termshark.spec" {$Source0="https://github.com/gcla/termshark/archive/refs/tags/v%{version}.tar.gz"; break}
    
        "tornado.spec" {$Source0="https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz"; break}

        "tpm2-pkcs11.spec" {$Source0="https://github.com/tpm2-software/tpm2-pkcs11/archive/refs/tags/%{version}.tar.gz"; break}

        "trousers.spec" {$Source0="https://sourceforge.net/projects/trousers/files/trousers/%{version}/trousers-%{version}.tar.gz/download"; break}

        "u-boot.spec" {$Source0="https://github.com/u-boot/u-boot/archive/refs/tags/v%{version}.tar.gz"; break}

        "ulogd.spec" {$Source0="https://www.netfilter.org/pub/ulogd/ulogd-%{version}.tar.bz2"; break}

        "unixODBC.spec" {$Source0="https://github.com/lurcher/unixODBC/archive/refs/tags/%{version}.tar.gz"; break}

        "util-linux.spec" {$Source0 = "https://github.com/util-linux/util-linux/archive/refs/tags/v%{version}.tar.gz"; break }

        "uwsgi.spec" {$Source0="https://github.com/unbit/uwsgi/archive/refs/tags/%{version}.tar.gz"; break}

        "valgrind.spec" {$Source0="https://sourceware.org/pub/valgrind/valgrind-%{version}.tar.bz2"; break}

        "vim.spec" {$Source0="https://github.com/vim/vim/archive/refs/tags/v%{version}.tar.gz"; break}

        "vulkan-tools.spec" {$Source0="https://github.com/KhronosGroup/Vulkan-Tools/archive/refs/tags/v%{version}.tar.gz"; break}

        "wavefront-proxy.spec" {$Source0="https://github.com/wavefrontHQ/wavefront-proxy/archive/refs/tags/proxy-%{version}.tar.gz"; break}

        "wayland.spec" {$Source0="https://gitlab.freedesktop.org/wayland/wayland/-/archive/%{version}/wayland-%{version}.tar.gz"; break}

        "wget.spec" {$Source0="https://ftp.gnu.org/gnu/wget/wget-%{version}.tar.gz"; break}

        "wireshark.spec" {$Source0="https://2.na.dl.wireshark.org/src/all-versions/wireshark-%{version}.tar.xz"; break}
        
        "xerces-c.spec" {$Source0="https://github.com/apache/xerces-c/archive/refs/tags/v%{version}.tar.gz"; break}   

        "xinetd.spec" {$Source0="https://github.com/xinetd-org/xinetd/archive/refs/tags/xinetd-%{version}.tar.gz"; break}

        "xmlsec1.spec" {if ($version -lt "1.2.30") {$Source0="https://www.aleksey.com/xmlsec/download/older-releases/xmlsec1-%{version}.tar.gz"; break} else {$Source0="https://www.aleksey.com/xmlsec/download/xmlsec1-%{version}.tar.gz"; break}}

        "xml-security-c.spec" {$Source0 = "https://archive.apache.org/dist/santuario/c-library/xml-security-c-%{version}.tar.gz" }

        "zlib.spec" {$Source0="https://github.com/madler/zlib/archive/refs/tags/v%{version}.tar.gz"; break}

        "zsh.spec" {$Source0="https://github.com/zsh-users/zsh/archive/refs/tags/zsh-%{version}.tar.gz"; break}
        Default {}
        }


        # add url path if necessary and possible
        if (($Source0 -notlike '*//*') -and ($_.url -ne ""))
        {
            if (($_.url -match '.tar.gz$') -or ($_.url -match '.tar.xz$') -or ($_.url -match '.tar.bz2$') -or ($_.url -match '.tgz$'))
            {$Source0=$_.url}
            else
            { $Source0 = [System.String]::Concat(($_.url).Trimend('/'),"/",$Source0) }
        }

        if ($Source0 -ilike '*%{name}*') { $Source0 = $Source0 -ireplace '%{name}',$_.Name }

        if ($Source0 -ilike '*%{version}*') { $Source0 = $Source0 -ireplace '%{version}',$version }

        if ($Source0 -ilike '*%{url}*') { $Source0 = $Source0 -ireplace '%{url}',$_.url }
        if ($Source0 -ilike '*%{srcname}*') { $Source0 = $Source0 -ireplace '%{srcname}',$_.srcname }
        if ($Source0 -ilike '*%{gem_name}*') { $Source0 = $Source0 -ireplace '%{gem_name}',$_.gem_name }
        if ($Source0 -ilike '*%{extra_version}*') { $Source0 = $Source0 -ireplace '%{extra_version}',$_.extra_version }

        if ($Source0 -ilike '*%{main_version}*') { $Source0 = $Source0 -ireplace '%{main_version}',$_.main_version }
        if ($Source0 -ilike '*%{byaccdate}*') { $Source0 = $Source0 -ireplace '%{byaccdate}',$_.byaccdate }
        if ($Source0 -ilike '*%{dialogsubversion}*') { $Source0 = $Source0 -ireplace '%{dialogsubversion}',$_.dialogsubversion }
        if ($Source0 -ilike '*%{libedit_release}*') { $Source0 = $Source0 -ireplace '%{libedit_release}',$_.libedit_release }
        if ($Source0 -ilike '*%{libedit_version}*') { $Source0 = $Source0 -ireplace '%{libedit_version}',$_.libedit_version }
        if ($Source0 -ilike '*%{ncursessubversion}*') { $Source0 = $Source0 -ireplace '%{ncursessubversion}',$_.ncursessubversion }
        if ($Source0 -ilike '*%{cpan_name}*') { $Source0 = $Source0 -ireplace '%{cpan_name}',$_.cpan_name }
        if ($Source0 -ilike '*%{xproto_ver}*') { $Source0 = $Source0 -ireplace '%{xproto_ver}',$_.xproto_ver}
        if ($Source0 -ilike '*%{_url_src}*') { $Source0 = $Source0 -ireplace '%{_url_src}',$_._url_src }
        if ($Source0 -ilike '*%{_repo_ver}*') { $Source0 = $Source0 -ireplace '%{_repo_ver}',$_._repo_ver}


        # different trycatch-combinations to get a healthy Source0 url
        $UpdateAvailable=""
        $urlhealth=""
        $Source0Save=$Source0
        if ($Source0 -like '*{*') {$urlhealth = "substitution_unfinished"}
        else
        {
            $urlhealth = urlhealth($Source0)
            if ($urlhealth -ne "200")
            {
                if ($Source0 -ilike '*github.com*')
                {
                    if ($Source0 -ilike '*/archive/refs/tags/*')
                    {
                        # check /archive/refs/tags/%{name}-v%{version} and /%{name}-%{version}
                        $Source0=$Source0Save
                        $replace=[System.String]::Concat(('/archive/refs/tags/'),$_.Name,"-","v",$version)
                        $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                        $Source0 = $Source0 -ireplace $replace,$replacenew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat(('/archive/refs/tags/'),$_.Name,"-",$version)
                            $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                            $Source0 = $Source0 -ireplace $replace,$replacenew
                            $urlhealth = urlhealth($Source0)
                            if ($urlhealth -ne "200")
                            {
                                $Source0=$Source0Save
                                $replace=[System.String]::Concat(('/archive/refs/tags/'),$_.Name,"-",$version)
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
                                                $NameArray=($_.Name).split("-")
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
                        $replace=[System.String]::Concat(('/archive/'),$_.Name,"-")
                        $Source0 = $Source0 -ireplace $replace,'/archive/refs/tags/'
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            # check without naming but with a 'v' before version
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat(('/archive/'),$_.Name,"-")
                            $Source0 = $Source0 -ireplace $replace,'/archive/refs/tags/v'
                            $urlhealth = urlhealth($Source0)
                            if ($urlhealth -ne "200")
                            {
                                # check with /releases/download/v{name}/{name}-{version}
                                $Source0=$Source0Save
                                $replace=[System.String]::Concat(('/archive/'),$_.Name,"-",$version)
                                $replacenew=[System.String]::Concat(('/releases/download/v'),$version,"/",$_.Name,"-",$version,'-linux-amd64')
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
                        $replace=[System.String]::Concat(('/releases/download/'),$_.Name,"-",$version,"/",$_.Name,"-",$version)
                        $replacenew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                        $Source0 = $Source0 -ireplace $replace,$replacenew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            # check without naming but with a 'v' before version
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat(('/releases/download/'),$version,"/",$_.Name,"-",$version)
                            $replacenew=[System.String]::Concat(('/archive/refs/tags/'),$version)
                            $Source0 = $Source0 -ireplace $replace,$replacenew
                            $urlhealth = urlhealth($Source0)
                            if ($urlhealth -ne "200")
                            {
                                $Source0=$Source0Save
                                $replace=[System.String]::Concat(('/releases/download/'),$version,"/",$_.Name,"-",$version)
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
                        $replace=[System.String]::Concat($_.Name,"-",$version)
                        $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                        $Source0 = $Source0 -ireplace $replace,$replacenew
                        $urlhealth = urlhealth($Source0)
                        if ($urlhealth -ne "200")
                        {
                            $Source0=$Source0Save
                            $replace=[System.String]::Concat($_.Name,"-",$version)
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


        # Check UpdateAvailable by github tags detection
        $replace=@()
        if ($Source0 -ilike '*github.com*')
        {
            $TmpSource=$Source0 -ireplace 'https://github.com',""
            $TmpSource=$TmpSource -ireplace 'https://www.github.com',""
            $TmpSource=$TmpSource -ireplace '/archive/refs/tags',""
            $SourceTagURL="https://api.github.com/repos"
            $SourceTagURLArray=($TmpSource).split("/")
            if ($SourceTagURLArray.length -gt 0)
            {
                $SourceTagURL="https://api.github.com/repos"
                for ($i=1;$i -lt ($SourceTagURLArray.length -1);$i++)
                {
                
                    $SourceTagURL=$SourceTagURL + "/" + $SourceTagURLArray[$i]
                }
            }
            $SourceTagURL=$SourceTagURL + "/releases"

            # pre parse
            switch($_.spec)
            {
                "haproxy.spec" {$SourceTagURL="https://api.github.com/repos/haproxy/haproxy/tags"; $replace+="v"}
            }

            try{
                $headers = New-Object "System.Collections.Generic.Dictionary[[String],[String]]"
                $headers.Add("Authorization", "token $accessToken")

                $Names = (invoke-webrequest $SourceTagURL -headers $headers | convertfrom-json).tag_name
                if (([string]::IsNullOrEmpty($Names)) -or ($_.spec -ilike 'rpm.spec'))
                {
                    $Names = (invoke-webrequest $SourceTagURL -headers $headers | convertfrom-json).name
                    if (([string]::IsNullOrEmpty($Names)) -or ($_.spec -ilike 'rpm.spec'))
                    {
                        $Names = ((invoke-webrequest $SourceTagURL -headers $headers | convertfrom-json).assets).name
                        if (([string]::IsNullOrEmpty($Names)) -or ($_.spec -ilike 'rpm.spec'))
                        {
                            $SourceTagURL=$SourceTagURL -ireplace "/releases","/tags"
                            $i=0
                            $lastpage=$false
                            $Names=@()
                            do
                            {
                                $i++
                                try
                                {
                                    $tmpUrl=[System.String]::Concat($SourceTagURL,"?page=",$i)
                                    $tmpdata = (invoke-restmethod -uri $tmpUrl -usebasicparsing -headers @{Authorization = "Bearer $accessToken"}).name
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
                        }
                        else
                        {
                            # remove ending
                            $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.whl')) {$_}}
                            $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.asc')) {$_}}
                            $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.dmg')) {$_}}
                            $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.zip')) {$_}}
                            $Names = $Names | foreach-object { if (!($_ | select-string -pattern '.exe')) {$_}}
                            $Names = $Names -replace ".tar.gz",""
                            $Names = $Names -replace ".tar.bz2",""
                            $Names = $Names -replace ".tar.xz",""
                        }
                    }
                }



                # post parse
                switch($_.spec)
                {
                "aide.spec" {$replace +="cs.tut.fi.import"; break}
                "backward-cpp.spec" {$replace +="v"; break}
                "bcc.spec" {$replace +="src-with-submodule.tar.gz"}
                "bindutils.spec" {$replace +="wpk-get-rid-of-up-downgrades-"; $replace +="noadaptive"; $replace +="more-adaptive"; $replace +="adaptive" }
                "bpftrace.spec" {$replace +="binary.tools.man-bundle.tar.xz"}
                "apache-maven.spec" {$replace +="workspace-v0"; $replace +="maven-"; break}
                "atk.spec"
                {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'gnome')) {$_}}
                    $replace +="GTK_ALL_"; $replace +="EA_"; $replace +="GAIL_"; break
                }
                "calico-cni.spec" {$replace +="calico-amd64"; $replace +="calico-arm64"}
                "calico-confd.spec" {$replace +="-darwin-amd64"; $replace +="confd-"}
                "chrpath.spec" {$replace +="RELEASE_"; break}
                "libselinux.spec" {$replace +="checkpolicy-3.5"; break} 
                "cloud-init.spec" {$replace +="ubuntu-";$replace +="ubuntu/"; break}
                "colm.spec" {$replace +="colm-barracuda-v5"; $replace +="colm-barracuda-v4"; $replace +="colm-barracuda-v3"; $replace +="colm-barracuda-v2"; $replace +="colm-barracuda-v1"; $replace +="colm-"; break}
                "cni.spec"
                {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern 'cni-plugins-linux-amd64-') {$_}}
                    $replace +="cni-plugins-linux-amd64-"
                    break
                }
                "docker-20.10.spec" {$Names = $Names | foreach-object { if (!($_ | select-string -pattern 'xdocs-v')) {$_}}; break}
                "dracut.spec" {$replace +="RHEL-"; break}
                "efibootmgr.spec" {$replace +="rhel-";$replace +="Revision_"; $replace+="release-tag"; $replace +="-branchpoint"; break}
                "erlang.spec" {$replace +="R16B"; $replace +="OTP-"; $replace +="erl_1211-bp"; break}
                "frr.spec" {$replace +="reindent-master-";$replace +="reindent-"; $replace +="before"; $replace +="after"; break}
                "fribidi.spec" {$replace +="INIT"; break}
                "falco.spec" { $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'agent/')) {$_}} }
                "fuse-overlayfs.spec.spec" {$replace +="aarch64"; break}
                "glib.spec"
                {
                    $replace +="start"; $replace +="PRE_CLEANUP"; $replace +="GNOME_PRINT_"
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'GTK_')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'gobject_')) {$_}}
                    break
                }
                "glibmm.spec" {$replace +="start"}
                "glib-networking.spec" {$replace +="glib-"}
                "glslang.spec" {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'untagged-')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'vulkan-')) {$_}}
                    $replace +="master-tot";$replace +="main-tot";$replace +="sdk-"; $replace +="SDK-candidate-26-Jul-2020";$replace+="Overload400-PrecQual"
                    $replace +="SDK-candidate";$replace+="SDK-candidate-2";$replace+="GL_EXT_shader_subgroup_extended_types-2016-05-10";$replace+="SPIRV99"
                    break
                }
                "gnome-common.spec" {$replace +="version_"; $replace +="v7status"; $replace +="update_for_spell_branch_1"; $replace +="twodaysago"; $replace +="toshok-libmimedir-base"; $replace +="threedaysago"; break}
                "gobject-introspection.spec" {$replace +="INITIAL_RELEASE"; $replace +="GOBJECT_INTROSPECTION_"; break}
                "google-compute-engine.spec" {$replace +="v"; break}
                "gstreamer.spec" {$replace +="sharp-"; break}
                "gtk3.spec" {$replace +="VIRTUAL_ATOM-22-06-"; $replace +="GTK_ALL_"; $replace +="TRISTAN_NATIVE_LAYOUT_START"; $replace +="START"; break}
                "gtk-doc.spec" {$replace +="GTK_DOC_"; $replace +="start"; break}
                "httpd.spec"
                {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'apache')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'mpm-')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'djg')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'dg_')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'wrowe')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'striker')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'PCRE_')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'MOD_SSL_')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'HTTPD_LDAP_')) {$_}}
                    break
                }
                "iperf.spec" {$replace +="trunk"; $replace +="iperf3"; break}
                "ipmitool.spec" {$replace +="ipmitool"; break}
                "iputils.spec" {$replace +="s"; break}
                "initscripts.spec" {$replace +="upstart-"; $replace +="unstable"; break}
                "json-glib.spec" {$replace +="json-glib-"; break}
                "jsoncpp.spec" {$replace +="svn-release-"; $replace +="svn-import"; break}
                "kbd.spec" {$replace +="v"; break}
                "kubernetes-dns.spec" {$replace +="test"; break}
                "kubernetes-metrics-server.spec" {$replace +="metrics-ser-helm-chart-3.8.3"; break}
                "leveldb.spec" {$replace+="v"; break}
                "linux-PAM.spec" {$replace +="pam_unix_refactor"; break}
                "lm-sensors.spec" {$replace +="i2c-2-8-km2"; break}
                "libnl.spec" {$replace +="libnl"; break}
                "libpsl.spec" {$replace +="libpsl-"; $replace +="debian/"; break}
                "librepo.spec" {$replace +="librepo-"; break}
                "libselinux.spec" {$replace +="sepolgen-"; break}
                "libsolv.spec" {$replace +="BASE-SuSE-Code-13_"; $replace +="BASE-SuSE-Code-12_3-Branch"; $replace +="BASE-SuSE-Code-12_2-Branch"; $replace +="BASE-SuSE-Code-12_1-Branch"; $replace +="1-Branch"; break}
                "libsoup.spec"
                {
                    $replace +="SOUP_"; $replace +="libsoup-pre214-branch-base"; $replace +="libsoup-hacking-branch-base"; $replace +="LIB"; $replace +="soup-2-0-branch-base"
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'gnome-')) {$_}}
                    break
                }
                "libX11.spec" { $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'xf86-')) {$_}} }
                "libXinerama.spec" {$replace +="XORG-7_1"; break}
                "libxslt.spec" {$replace +="LIXSLT_"; break}
                "linux-PAM.spec" {$replace +="v"; break}
                "mariadb.spec"
                {
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'toku')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'serg-')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'percona-')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'mysql-')) {$_}}
                    break
                }
                "mc.spec" {$replace +="mc-"; break}
                "mysql.spec" {$replace +="mysql-cluster-"; break}
                "openldap.spec" {$replace +="UTBM_"; $replace +="URE_"; $replace +="UMICH_LDAP_3_3"; $replace +="UCDATA_"; $replace +="TWEB_OL_BASE"; $replace +="SLAPD_BACK_LDAP"; $replace +="PHP3_TOOL_0_0"; break}
                "open-vm-tools.spec" {$replace +="stable-"; break}
                "pandoc.spec" {$replace +="pandoc-server-"; $replace +="pandoc-lua-engine-"; $replace +="pandoc-cli-0.1"; $replace +="new1.16deb"; $replace +="list"; break}
                "pango.spec" {$replace +="tical-branch-point"; break}
                "powershell.spec" {$replace="hashes.sha256";break}
                "python-babel.spec" {$replace +="dev-2a51c9b95d06"; break} 
                "python-cassandra-driver.spec" {$replace +="3.9-doc-backports-from-3.1"; $replace +="-backport-prepared-slack"; break}
                "python-configparser.spec" {$replace +="v"; break}
                "python-decorator.spec" {$replace +="release-"; $replace +="decorator-"; break}
                "python-ethtool.spec" {$replace +="libnl-1-v0.6"; break}
                "python-filelock.spec" {$replace +="v"; break}
                "python-fuse.spec" {$replace +="start"; break}
                "python-incremental.spec" {$replace +="incremental-"; break}
                "python-lxml.spec" {$replace +="lxml-"; break}
                "python-mako.spec" {$replace +="rel_"; break}
                "python-more-itertools.spec" {$replace +="v"; break}
                "python-numpy.spec" {$replace +="with_maskna"; break}
                "python-pyparsing.spec" {$replace +="pyparsing_"; break}
                "python-webob.spec" {$replace +="sprint-coverage"; break}
                "rabbitmq3.10.spec" {
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern 'v3.10.') {$_}}
                    break
                }
                "ragel.spec" {$replace +="ragel-pre-colm"; $replace +="ragel-barracuda-v5"; $replace +="barracuda-v4"; $replace +="barracuda-v3"; $replace +="barracuda-v2"; $replace +="barracuda-v1"; break}
                "redis.spec" {$replace +="with-deprecated-diskstore"; $replace +="vm-playpen"; $replace +="twitter-20100825"; $replace +="twitter-20100804"; break}
                "rpm.spec" {$replace +="rpm-";$replace +="-release"; break}
                "s3fs-fuse.spec" {$replace +="Pre-v"; break}
                "sysdig.spec" {
                    $replace +="sysdig-inspect/"; $replace +="simpledriver-auto-dragent-20170906"; $replace +="s20171003"
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'falco/')) {$_}}
                    break
                }
                "sqlite.spec" {$replace +="version-"; break}
                "squashfs-tools.spec" {$replace +="CVE-2021-41072"; break}
                "uwsgi.spec" {$replace +="no_server_mode"; break}
                "vulkan-headers.spec" {$replace +="vksc"; break}
                "vulkan-loader.spec" {$replace +="windows-rt-"; break}
                "wavefront-proxy.spec" {$replace +="wavefront-"; break}
                "xinetd.spec" {$replace +="xinetd-"; break}
                "zsh.spec" {$Names = $Names | foreach-object { if (!($_ | select-string -pattern '-test')) {$_}}}
                "zstd.spec" {$replace +="zstd"; break}
                Default {}
                }

                    $replace += $_.Name+"."
                    $replace += $_.Name+"-"
                    $replace +="ver"
                    $replace +="release_"
                    $replace +="release-"
                    $replace +="release"
                    $replace | foreach { $Names = $Names -replace $_,""}
                    $Names = $Names.Where({ $null -ne $_ })
                    $Names = $Names.Where({ "" -ne $_ })
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '^rel/') {$_ -ireplace '^rel/',""} else {$_}}
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v') {$_ -ireplace '^v',""} else {$_}}
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V') {$_ -ireplace '^V',""} else {$_}}
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r') {$_ -ireplace '^r',""} else {$_}}
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R') {$_ -ireplace '^R',""} else {$_}}
                    $Names = $Names | foreach-object { if ($_ | select-string -pattern '_') {$_ -ireplace '_',"."} else {$_}}

                    # remove versions developer, release candidates, alpha versions, preview versions and versions without numbers
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'candidate')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-alpha')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-beta')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.0')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.1')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.2')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.3')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc.4')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc1')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc2')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc3')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern 'rc4')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-preview.')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-dev.')) {$_}}
                    $Names = $Names | foreach-object { if (!($_ | select-string -pattern '-pre1')) {$_}}
                    $Names = $Names | foreach-object { if ($_ -match '\d') {$_}}
                    $Names = $Names | foreach-object { if (!($_ -match '[a-zA-Z]')) {$_}}

                $NameLatest = ($Names | % {$tag = $_ ; $tmpversion = [version]::new(); if ([version]::TryParse($tag, [ref]$tmpversion)) {$tmpversion}} | sort-object | select-object -last 1).ToString()
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if ($Version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
            }
        }
        # Check UpdateAvailable by freedesktop tags detection
        elseif (($Source0 -ilike '*freedesktop.org*') -or ($Source0 -ilike '*https://gitlab.*'))
        {
            if ($_.spec -ilike 'dbus.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus/-/tags?format=atom"}
            elseif ($_.spec -ilike 'dbus-glib.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus-glib/-/tags?format=atom"}
            elseif ($_.spec -ilike 'dbus-python.spec') {$SourceTagURL="https://gitlab.freedesktop.org/dbus/dbus-python/-/tags?format=atom"}
            elseif ($_.spec -ilike 'fontconfig.spec') {$SourceTagURL="https://gitlab.freedesktop.org/fontconfig/fontconfig/-/tags?format=atom"}
            elseif ($_.spec -ilike 'gstreamer.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gstreamer/-/tags?format=atom"}
            elseif ($_.spec -ilike 'gstreamer-plugins-base.spec') {$SourceTagURL="https://gitlab.freedesktop.org/gstreamer/gst-plugins-base/-/tags?format=atom"}
            elseif ($_.spec -ilike 'shared-mime-info.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xdg/shared-mime-info/-/tags?format=atom"}
            elseif ($_.spec -ilike 'mesa.spec') {$SourceTagURL="https://gitlab.freedesktop.org/mesa/mesa/-/tags?format=atom"}
            elseif ($_.spec -ilike 'modemmanager.spec') {$SourceTagURL="https://gitlab.freedesktop.org/modemmanager/modemmanager/-/tags?format=atom"}
            elseif ($_.spec -ilike 'pixman.spec') {$SourceTagURL="https://gitlab.freedesktop.org/pixman/pixman/-/tags?format=atom"}
            elseif ($_.spec -ilike 'polkit.spec') {$SourceTagURL="https://gitlab.freedesktop.org/polkit/polkit/-/tags?format=atom"}
            elseif ($_.spec -ilike 'wayland.spec') {$SourceTagURL="https://gitlab.freedesktop.org/wayland/wayland/-/tags?format=atom"}
            elseif ($_.spec -ilike 'wayland-protocols.spec') {$SourceTagURL="https://gitlab.freedesktop.org/wayland/wayland-protocols/-/tags?format=atom"}
            elseif ($_.spec -ilike 'libxinerama.spec') {$SourceTagURL="https://gitlab.freedesktop.org/xorg/lib/libxinerama/-/tags?format=atom"}
            elseif ($_.spec -ilike 'pkg-config.spec') {$SourceTagURL="https://gitlab.freedesktop.org/pkg-config/pkg-config/-/tags?format=atom"}
            elseif ($_.spec -ilike 'cairo.spec') {$SourceTagURL="https://gitlab.freedesktop.org/cairo/cairo/-/tags?format=atom"}
            elseif ($_.spec -ilike 'man-deb.spec') {$SourceTagURL="https://gitlab.com/man-db/man-db/-/tags?format=atom"}

            try{
                $Names = (invoke-restmethod -uri $SourceTagURL -usebasicparsing)

                $replace += $_.Name+"."
                $replace += $_.Name+"-"
                $replace +="ver"
                $Names = $Names.title
                $replace | foreach { $Names = $Names -replace $_,""}
                $Names = $Names.Where({ $null -ne $_ })
                $Names = $Names.Where({ "" -ne $_ }) 
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^v') {$_ -ireplace '^v',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^V') {$_ -ireplace '^V',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^r') {$_ -ireplace '^r',""} else {$_}}
                $Names = $Names | foreach-object { if ($_ | select-string -pattern '^R') {$_ -ireplace '^R',""} else {$_}}
                $Names = $Names | foreach {echo $_"-zz"}
                $NameLatest = ($Names | sort-object -property minor | select -first 1) -replace "-zz",""
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if ($Version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
            }
        }
        # kit.kernel.org tags detection. Not ready for other specs.
        elseif ($_.spec -ilike 'rt-tests.spec')
        {
            try
            {
                $Names = (((((invoke-restmethod -uri "https://git.kernel.org/pub/scm/utils/rt-tests/rt-tests.git/refs/tags?format=atom" -UseBasicParsing) -split "<td>") -ilike '*/pub/scm/utils/rt-tests/rt-tests.git/tag/?h=*') -split ">v") -ilike '*</a></td>*') -ireplace "</a></td>",""
                $Names = $Names | foreach {echo $_"-zz"}
                $NameLatest = ($Names | sort-object -property minor | select -first 1) -replace "-zz",""
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if ($Version -lt $NameLatest) {$UpdateAvailable = $NameLatest}
            }
        }

        # Archived Github repo signalization
        $warning="Warning: repo isn't maintained anymore."
        if ($_.Spec -ilike 'python-argparse.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'python-atomicwrites.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'python-subprocess32.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'python-terminaltables.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'confd.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'cve-check-tool.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'http-parser.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'imagemagick.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'fcgi.spec') {$UpdateAvailable=$warning+" See "+ "https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/%{version}.tar.gz ."}
        elseif ($_.Spec -ilike 'libtar.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'lightwave.spec') {$UpdateAvailable=$warning}

        $warning="Warning: Cannot detect correlating tags from the repo provided."
        if (($_.Spec -ilike 'bluez-tools.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'containers-common.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'cpulimit.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'dcerpc.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'dotnet-sdk.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'dtb-raspberrypi.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'fuse-overlayfs-snapshotter.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'hawkey.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'libgsystem.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'libselinux.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'libsepol.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'libnss-ato.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'lightwave.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'likewise-open.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'linux-firmware.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'motd.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'netmgmt.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'pcstat.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'python-backports.ssl_match_hostname.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'python-iniparse.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning} 
        elseif (($_.Spec -ilike 'python-geomet.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'python-pyjsparser.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}  
        elseif (($_.Spec -ilike 'python-ruamel-yaml.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning+"Also, see "+"https://github.com/commx/ruamel-yaml/archive/refs/tags/%{version}.tar.gz"}
        elseif (($_.Spec -ilike 'rubygem-aws-sdk-s3.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'sqlite2.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}
        elseif (($_.Spec -ilike 'tornado.spec') -and ($UpdateAvailable -eq "")) {$UpdateAvailable=$warning}     

        $warning="Warning: duplicate of python-pam.spec"
        if ($_.Spec -ilike 'python-pycodestyle.spec') {$UpdateAvailable=$warning}

        $warning="Info: Source0 contains a VMware internal url address."
        if ($_.Spec -ilike 'distrib-compat.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'docker-vsock.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'filesystem.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'grub2-theme.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'initramfs.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'photon-iso-config.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'photon-release.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'photon-repos.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'photon-upgrade.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'openssl.spec') {$UpdateAvailable=$warning}

        $warning="Warning: Source0 seems invalid and no other Official source has been found."
        if ($_.Spec -ilike 'cdrkit.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'crash.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'finger.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'ndsend.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'pcre.spec') {$UpdateAvailable=$warning}
        elseif ($_.Spec -ilike 'pypam.spec') {$UpdateAvailable=$warning}

        $warning="Warning: Manufacturer changed packaging format in newer version(s)."
        if (($_.Spec -ilike 'nftables.spec') -and ($Source0 -ilike '*.tar.bz2*')) {$UpdateAvailable=$warning}
        if (($_.Spec -ilike 'ed.spec') -and ($Source0 -ilike '*.tar.lz*')) {$UpdateAvailable=$warning}

        if (($UpdateAvailable -eq "") -and ($urlhealth -ne "200")) {$Source0=""}

        $line=[System.String]::Concat($_.spec, ',',$_.source0,',',$Source0,',',$urlhealth,',',$UpdateAvailable)
        $Lines += $line
    }
    "Spec"+","+"Source0 original"+","+"Recent Source0 modified for UrlHealth"+","+"UrlHealth"+","+"UpdateAvailable"| out-file $outputfile
    $lines | out-file $outputfile -append
    }
}

$access = Read-Host -Prompt "Please enter your Github Access Token."

$GeneratePh3URLHealthReport=$true
$GeneratePh4URLHealthReport=$true
$GeneratePh5URLHealthReport=$true
$GeneratePhPackageReport=$true
$GeneratePh4toPh5DiffHigherPackageVersionReport=$true
$GeneratePh3toPh4DiffHigherPackageVersionReport=$true

if ($GeneratePh3URLHealthReport -ieq $true)
{
    write-output "Generating URLHealth report for Photon OS 3.0 ..."
    GitPhoton -release "3.0"
    $Packages3=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-3.0
    CheckURLHealth -outputfile "$env:public\photonos-urlhealth-3.0_$((get-date).tostring("yyyMMddHHmm")).prn" -accessToken $access -CheckURLHealthPackageObject $Packages3
}


if ($GeneratePh4URLHealthReport -ieq $true)
{
    write-output "Generating URLHealth report for Photon OS 4.0 ..."
    GitPhoton -release "4.0"
    $Packages4=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-4.0
    CheckURLHealth -outputfile "$env:public\photonos-urlhealth-4.0_$((get-date).tostring("yyyMMddHHmm")).prn" -accessToken $access -CheckURLHealthPackageObject $Packages4
}

if ($GeneratePh5URLHealthReport -ieq $true)
{
    write-output "Generating URLHealth report for Photon OS 5.0 ..."
    GitPhoton -release "5.0"
    $Packages5=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-5.0
    CheckURLHealth -outputfile "$env:public\photonos-urlhealth-5.0_$((get-date).tostring("yyyMMddHHmm")).prn" -accessToken $access -CheckURLHealthPackageObject $Packages5
}

if ($GeneratePhPackageReport -ieq $true)
{
    write-output "Generating Package Report ..."
    # fetch + merge per branch
    GitPhoton -release "1.0"
    GitPhoton -release "2.0"
    GitPhoton -release master
    GitPhoton -release dev
    cd $sourcepath
    # read all files from branch
    $Packages1=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-1.0
    $Packages2=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-2.0
    $PackagesMaster=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-master
    $Packages0=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-dev
    $result = $Packages1,$Packages2,$Packages3,$Packages4,$Packages5,$PackagesMaster| %{$_}|Select Spec,`
    @{l='photon-1.0';e={if($_.Spec -in $Packages1.Spec) {$Packages1[$Packages1.Spec.IndexOf($_.Spec)].version}}},`
    @{l='photon-2.0';e={if($_.Spec -in $Packages2.Spec) {$Packages2[$Packages2.Spec.IndexOf($_.Spec)].version}}},`
    @{l='photon-3.0';e={if($_.Spec -in $Packages3.Spec) {$Packages3[$Packages3.Spec.IndexOf($_.Spec)].version}}},`
    @{l='photon-4.0';e={if($_.Spec -in $Packages4.Spec) {$Packages4[$Packages4.Spec.IndexOf($_.Spec)].version}}},`
    @{l='photon-5.0';e={if($_.Spec -in $Packages5.Spec) {$Packages5[$Packages5.Spec.IndexOf($_.Spec)].version}}},`
    @{l='photon-dev';e={if($_.Spec -in $Packages0.Spec) {$Packages0[$Packages0.Spec.IndexOf($_.Spec)].version}}},`
    @{l='photon-master';e={if($_.Spec -in $PackagesMaster.Spec) {$PackagesMaster[$PackagesMaster.Spec.IndexOf($_.Spec)].version}}} -Unique | Sort-object Spec
    $outputfile="$env:public\photonos-package-report_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-1.0"+","+"photon-2.0"+","+"photon-3.0"+","+"photon-4.0"+","+"photon-5.0"+","+"photon-dev"+","+"photon-master"| out-file $outputfile
    $result | % { $_.Spec+","+$_."photon-1.0"+","+$_."photon-2.0"+","+$_."photon-3.0"+","+$_."photon-4.0"+","+$_."photon-5.0"+","+$_."photon-dev"+","+$_."photon-master"} |  out-file $outputfile -append
}

if ($GeneratePh4toPh5DiffHigherPackageVersionReport -ieq $true)
{
    write-output "Generating difference report of 4.0 packages with a higher version than same 5.0 package ..."
    $outputfile1="$env:public\photonos-diff-report-4.0-5.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-4.0"+","+"photon-5.0"| out-file $outputfile1
    $result | % {
        # write-output $_.spec
        if ((!([string]::IsNullOrEmpty($_.'photon-4.0'))) -and (!([string]::IsNullOrEmpty($_.'photon-5.0'))))
        {
            $VersionCompare1 = VersionCompare $_.'photon-4.0' $_.'photon-5.0'
            if ($VersionCompare1 -eq 1)
            {
                $diffspec1=[System.String]::Concat($_.spec, ',',$_.'photon-4.0',',',$_.'photon-5.0')
                $diffspec1 | out-file $outputfile1 -append
            }
        }
    }
}

if ($GeneratePh3toPh4DiffHigherPackageVersionReport -ieq $true)
{
    write-output "Generating difference report of 3.0 packages with a higher version than same 4.0 package ..."
    $outputfile2="$env:public\photonos-diff-report-3.0-4.0_$((get-date).tostring("yyyMMddHHmm")).prn"
    "Spec"+","+"photon-3.0"+","+"photon-4.0"| out-file $outputfile2
    $result | % {
        # write-output $_.spec
        if ((!([string]::IsNullOrEmpty($_.'photon-3.0'))) -and (!([string]::IsNullOrEmpty($_.'photon-4.0'))))
        {
            $VersionCompare2 = VersionCompare $_.'photon-3.0' $_.'photon-4.0'
            if ($VersionCompare2 -eq 1)
            {
                $diffspec2=[System.String]::Concat($_.spec, ',',$_.'photon-3.0',',',$_.'photon-4.0')
                $diffspec2 | out-file $outputfile2 -append
            }
        }
    }
}
