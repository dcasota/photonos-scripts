# .SYNOPSIS
#  This VMware Photon OS github branches packages (specs) report script creates an excel prn.
#
# .NOTES
#   Author:  Daniel Casota
#   Version:
#   0.1   06.03.2021   dcasota  First release
#   0.2   17.04.2021   dcasota  dev added
#   0.3   05.02.2023   dcasota  5.0 added, report release x package with a higher version than same release x+1 package
#   0.4   27.02.2023   dcasota  CheckURLHealth added, timedate stamp in reports' name added 
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
                
                $Packages +=[PSCustomObject]@{
                    Spec = $_.Name
                    Version = $Version
                    Name = $object.Name
                    Source0 = $Source0
                    url = $url
                    srcname = $srcname
                    gem_name = $gem_name
                    group = $group
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
        $rc = Invoke-WebRequest -Uri $Source0 -UseDefaultCredentials -UseBasicParsing -Method Head -TimeoutSec 5 -ErrorAction Stop
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

        # correction for urlnames
        if ($_.Spec -ilike 'pmd-nextgen.spec') {$Source0="https://github.com/vmware/pmd/archive/refs/tags/v%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-dateutil.spec') {$Source0="https://github.com/dateutil/dateutil/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-alabaster.spec') {$Source0="https://github.com/bitprophet/alabaster/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-altgraph.spec') {$Source0="https://github.com/ronaldoussoren/altgraph/releases/tag/v%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-appdirs.spec') {$Source0="https://github.com/ActiveState/appdirs/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-argparse.spec') {$Source0="https://github.com/ThomasWaldmann/argparse/archive/refs/tags/r140.tar.gz"} #github archived
        elseif ($_.Spec -ilike 'python-atomicwrites.spec') {$Source0="https://github.com/untitaker/python-atomicwrites/archive/refs/tags/1.4.1.tar.gz"} #github archived
        elseif ($_.Spec -ilike 'python-attrs.spec') {$Source0="https://github.com/python-attrs/attrs/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-autopep8.spec') {$Source0="https://github.com/hhatto/autopep8/archive/refs/tags/v%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-babel.spec') {$Source0="https://github.com/python-babel/babel/archive/refs/tags/v%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-backports.ssl_match_hostname*') {} # see https://github.com/python/typeshed
        elseif ($_.Spec -ilike 'python-altgraph.spec') {$Source0="https://github.com/ronaldoussoren/altgraph/archive/refs/tags/v%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-bcrypt.spec') {$Source0="https://github.com/pyca/bcrypt/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-boto3.spec') {$Source0="https://github.com/boto/boto3/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-botocore.spec') {$Source0="https://github.com/boto/botocore/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-cachecontrol.spec') {$Source0="https://github.com/ionrock/cachecontrol/archive/refs/tags/v%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-cassandra-driver.spec') {$Source0="https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz"} 
        elseif ($_.Spec -ilike 'python-certifi.spec') {$Source0="https://github.com/certifi/python-certifi/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-chardet.spec') {$Source0="https://github.com/chardet/chardet/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-charset-normalizer.spec') {$Source0="https://github.com/Ousret/charset_normalizer/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-click.spec') {$Source0="https://github.com/pallets/click/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-ConcurrentLogHandler.spec') {$Source0="https://github.com/Preston-Landers/concurrent-log-handler/archive/refs/tags/%{version}.tar.gz"}
        elseif ($_.Spec -ilike 'python-certifi.spec') {$Source0="https://github.com/certifi/python-certifi/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-configparser.spec') {$Source0="https://github.com/jaraco/configparser/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-constantly.spec') {$Source0="https://github.com/twisted/constantly/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-cql.spec') {$Source0="https://github.com/datastax/python-driver/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-decorator.spec') {$Source0="https://github.com/micheles/decorator/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-deepmerge.spec') {$Source0="https://github.com/toumorokoshi/deepmerge/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-defusedxml.spec') {$Source0="https://github.com/tiran/defusedxml/archive/refs/tags/v%{version}.tar.gz"}   

        elseif ($_.Spec -ilike 'python-distro.spec') {$Source0="https://github.com/python-distro/distro/archive/refs/tags/v%{version}.tar.gz"} 

        elseif ($_.Spec -ilike 'python-docopt.spec') {$Source0="https://github.com/docopt/docopt/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-email-validator.spec') {$Source0="https://github.com/JoshData/python-email-validator/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-ethtool.spec') {$Source0="https://github.com/fedora-python/python-ethtool/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-filelock.spec') {$Source0="https://github.com/tox-dev/py-filelock/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-geomet.spec') {$Source0="https://github.com/geomet/geomet/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-gevent.spec') {$Source0="https://github.com/gevent/gevent/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-gevent.spec') {$Source0="https://github.com/gevent/gevent/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-graphviz.spec') {$Source0="https://github.com/xflr6/graphviz/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-greenlet.spec') {$Source0="https://github.com/python-greenlet/greenlet/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-hyperlink.spec') {$Source0="https://github.com/python-hyper/hyperlink/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-hypothesis.spec') {$Source0="https://github.com/HypothesisWorks/hypothesis/archive/refs/tags/hypothesis-python-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-idna.spec') {$Source0="https://github.com/kjd/idna/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-imagesize.spec') {$Source0="https://github.com/shibukawa/imagesize_py/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-incremental.spec') {$Source0="https://github.com/twisted/incremental/archive/refs/tags/incremental-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-iniparse.spec') {$Source0="https://github.com/candlepin/python-iniparse/archive/refs/tags/%{version}.tar.gz"}   

        elseif ($_.Spec -ilike 'python-ipaddress.spec') {$Source0="https://github.com/phihag/ipaddress/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-jinja.spec') {$Source0="https://github.com/pallets/jinja/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-jmespath.spec') {$Source0="https://github.com/jmespath/jmespath.py/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-jsonpatch.spec') {$Source0="https://github.com/stefankoegl/python-json-patch/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-M2Crypto.spec') {$Source0="https://gitlab.com/m2crypto/m2crypto/-/archive/%{version}/m2crypto-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-mako.spec') {$Source0="https://github.com/sqlalchemy/mako/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-markupsafe.spec') {$Source0="https://github.com/pallets/markupsafe/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-more-itertools.spec') {$Source0="https://github.com/more-itertools/more-itertools/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-msgpack.spec') {$Source0="https://github.com/msgpack/msgpack-python/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-ndg-httpsclient.spec') {$Source0="https://github.com/cedadev/ndg_httpsclient/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-ntplib.spec') {$Source0="https://github.com/cf-natali/ntplib/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-oauthlib.spec') {$Source0="https://github.com/oauthlib/oauthlib/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-packaging.spec') {$Source0="https://github.com/pypa/packaging/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pam.spec') {$Source0="https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pexpect.spec') {$Source0="https://github.com/pexpect/pexpect/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pluggy.spec') {$Source0="https://github.com/pytest-dev/pluggy/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-ply.spec') {$Source0="https://github.com/dabeaz/ply/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-prometheus_client.spec') {$Source0="https://github.com/prometheus/client_python/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-py.spec') {$Source0="https://github.com/pytest-dev/py/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyasn1-modules.spec') {$Source0="https://github.com/etingof/pyasn1-modules/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pycodestyle.spec') {$Source0="https://github.com/FirefighterBlu3/python-pam/archive/refs/tags/v%{version}.tar.gz"} # duplicate of python-pam

        elseif ($_.Spec -ilike 'python-pycryptodomex.spec') {$Source0="https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyhamcrest.spec') {$Source0="https://github.com/hamcrest/PyHamcrest/archive/refs/tags/V%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyinstaller-hooks-contrib.spec') {$Source0="https://github.com/pyinstaller/pyinstaller-hooks-contrib/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyjwt.spec') {$Source0="https://github.com/jpadilla/pyjwt/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyparsing.spec') {$Source0="https://github.com/pyparsing/pyparsing/archive/refs/tags/pyparsing_%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pycparser.spec') {$Source0="https://github.com/eliben/pycparser/archive/refs/tags/release_v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pycparser.spec') {$Source0="https://github.com/eliben/pycparser/archive/refs/tags/release_v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pycryptodome.spec') {$Source0="https://github.com/Legrandin/pycryptodome/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pydantic.spec') {$Source0="https://github.com/pydantic/pydantic/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyflakes.spec') {$Source0="https://github.com/PyCQA/pyflakes/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pygments.spec') {$Source0="https://github.com/pygments/pygments/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyinstaller.spec') {$Source0="https://github.com/pyinstaller/pyinstaller/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyjsparser.spec') {$Source0="https://github.com/pyinstaller/pyinstaller/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyopenssl.spec') {$Source0="https://github.com/pyca/pyopenssl/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyrsistent.spec') {$Source0="https://github.com/tobgu/pyrsistent/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyserial.spec') {$Source0="https://github.com/pyserial/pyserial/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyserial.spec') {$Source0="https://github.com/pyserial/pyserial/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pytest.spec') {$Source0="https://github.com/pytest-dev/pytest/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyudev.spec') {$Source0="https://github.com/pyudev/pyudev/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-pyvmomi.spec') {$Source0="https://github.com/vmware/pyvmomi/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-resolvelib.spec') {$Source0="https://github.com/sarugaku/resolvelib/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-scp.spec') {$Source0="https://github.com/jbardin/scp.py/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-service_identity.spec') {$Source0="https://github.com/pyca/service-identity/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-simplejson.spec') {$Source0="https://github.com/simplejson/simplejson/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-sqlalchemy.spec') {$Source0="https://github.com/sqlalchemy/sqlalchemy/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-subprocess32.spec') {$Source0="https://github.com/google/python-subprocess32/archive/refs/tags/%{version}.tar.gz"} # archived October 27th 2022

        elseif ($_.Spec -ilike 'python-terminaltables.spec') {$Source0="https://github.com/Robpol86/terminaltables/archive/refs/tags/v%{version}.tar.gz"} # archived 7th December 2021

        elseif ($_.Spec -ilike 'python-toml.spec') {$Source0="https://github.com/uiri/toml/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-vcversioner.spec') {$Source0="https://github.com/habnabit/vcversioner/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-virtualenv.spec') {$Source0="https://github.com/pypa/virtualenv/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-webob.spec') {$Source0="https://github.com/Pylons/webob/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-werkzeug.spec') {$Source0="https://github.com/pallets/werkzeug/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'rabbitmq.spec') {$Source0="https://github.com/rabbitmq/rabbitmq-server/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'wavefront-proxy.spec') {$Source0="https://github.com/wavefrontHQ/wavefront-proxy/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'wayland.spec') {$Source0="https://gitlab.freedesktop.org/wayland/wayland/-/archive/%{version}/wayland-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'xinetd.spec') {$Source0="https://github.com/xinetd-org/xinetd/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'aufs-util.spec') {$Source0="https://github.com/sfjro/aufs-linux/archive/refs/tags/v%{version}.tar.gz"} # see https://github.com/sfjro for older linux kernels

        elseif ($_.Spec -ilike 'ansible.spec') {$Source0="https://github.com/ansible/ansible/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'apache-ant.spec') {$Source0="https://github.com/apache/ant/archive/refs/tags/rel/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'apache-tomcat-native.spec') {$Source0="https://github.com/apache/tomcat-native/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'atk.spec') {$Source0="https://github.com/GNOME/atk/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'bindutils.spec') {$Source0="https://github.com/isc-projects/bind9/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'bubblewrap.spec') {$Source0="https://github.com/containers/bubblewrap/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'clang.spec') {$Source0="https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/clang-%{version}.src.tar.xz"}

        elseif ($_.Spec -ilike 'cloud-init.spec') {$Source0="https://github.com/canonical/cloud-init/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'confd.spec') {$Source0="https://github.com/projectcalico/confd/archive/refs/tags/v%{version}.dev.tar.gz"} # Deprecated, new location https://github.com/projectcalico/calico
    
        elseif ($_.Spec -ilike 'conmon.spec') {$Source0="https://github.com/containers/conmon/archive/refs/tags/v%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'conmon.spec') {$Source0="https://github.com/containers/conmon/archive/refs/tags/v%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'coredns.spec') {$Source0="https://github.com/coredns/coredns/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'cryptsetup.spec') {$Source0="https://github.com/mbroz/cryptsetup/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'cups.spec') {$Source0="https://github.com/OpenPrinting/cups/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'cve-check-tool.spec') {$Source0="https://github.com/clearlinux/cve-check-tool/archive/refs/tags/v%{version}.tar.gz"} # deprecated on January 7th 2023
   
        elseif ($_.Spec -ilike 'cyrus-sasl.spec') {$Source0="https://github.com/cyrusimap/cyrus-sasl/archive/refs/tags/cyrus-sasl-%{version}.tar.gz"}    

        elseif ($_.Spec -ilike 'cython3.spec') {$Source0="https://github.com/cython/cython/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'device-mapper-multipath.spec') {$Source0="https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'device-mapper-multipath.spec') {$Source0="https://github.com/opensvc/multipath-tools/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'docker-20.10.spec') {$Source0="https://github.com/moby/moby/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'erlang-sd_notify.spec') {$Source0="https://github.com/systemd/erlang-sd_notify/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'fatrace.spec') {$Source0="https://github.com/martinpitt/fatrace/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'flex.spec') {$Source0="https://github.com/westes/flex/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'glib.spec') {$Source0="https://github.com/GNOME/glib/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'glib-networking.spec') {$Source0="https://github.com/GNOME/glib-networking/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'gnome-common.spec') {$Source0="https://github.com/GNOME/gnome-common/archive/refs/tags/%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'gobject-introspection.spec') {$Source0="https://github.com/GNOME/gobject-introspection/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'google-compute-engine.spec') {$Source0="https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'graphene.spec') {$Source0="https://github.com/ebassi/graphene/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'gtest.spec') {$Source0="https://github.com/google/googletest/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'gtk3.spec') {$Source0="https://github.com/GNOME/gtk/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'haproxy.spec') {$Source0="https://github.com/haproxy/haproxy/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'haproxy-dataplaneapi.spec') {$Source0="https://github.com/haproxytech/dataplaneapi/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'haveged.spec') {$Source0="https://github.com/jirka-h/haveged/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'http-parser.spec') {$Source0="https://github.com/nodejs/http-parser/archive/refs/tags/v%{version}.tar.gz"} # deprecated on 6th November 2022

        elseif ($_.Spec -ilike 'imagemagick.spec') {$Source0="https://github.com/ImageMagick/ImageMagick/archive/refs/tags/%{version}.tar.gz"} # deprecated on 6th November 2022

        # elseif ($_.Spec -ilike 'inih.spec') {$Source0="https://github.com/benhoyt/inih/archive/refs/tags/%{version}.tar.gz"} # r%{version} ?

        elseif ($_.Spec -ilike 'json-glib.spec') {$Source0="https://github.com/GNOME/json-glib/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'kafka.spec') {$Source0="https://github.com/apache/kafka/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'lapack.spec') {$Source0="https://github.com/Reference-LAPACK/lapack/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'leveldb.spec') {$Source0="https://github.com/google/leveldb/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'libconfig.spec') {$Source0="https://github.com/hyperrealm/libconfig/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'libffi.spec') {$Source0="https://github.com/libffi/libffi/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'librsync.spec') {$Source0="https://github.com/librsync/librsync/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'libsigc++.spec') {$Source0="https://github.com/libsigcplusplus/libsigcplusplus/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'libxml2.spec') {$Source0="https://github.com/GNOME/libxml2/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'libxslt.spec') {$Source0="https://github.com/GNOME/libxslt/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'lldb.spec') {$Source0="https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/lldb-%{version}.src.tar.xz"}

        elseif ($_.Spec -ilike 'llvm.spec') {$Source0="https://github.com/llvm/llvm-project/releases/download/llvmorg-%{version}/llvm-%{version}.src.tar.xz"}

        elseif ($_.Spec -ilike 'lm-sensors.spec') {$Source0="https://github.com/lm-sensors/lm-sensors/archive/refs/tags/V%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'mariadb.spec') {$Source0="https://github.com/MariaDB/server/archive/refs/tags/mariadb-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'mc.spec') {$Source0="https://github.com/MidnightCommander/mc/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'mkinitcpio.spec') {$Source0="https://github.com/archlinux/mkinitcpio/archive/refs/tags/v%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'monitoring-plugins.spec') {$Source0="https://github.com/monitoring-plugins/monitoring-plugins/archive/refs/tags/v%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'mysql.spec') {$Source0="https://github.com/mysql/mysql-server/archive/refs/tags/mysql-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'ostree.spec') {$Source0="https://github.com/ostreedev/ostree/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'pam_tacplus.spec') {$Source0="https://github.com/ostreedev/ostree/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'pandoc.spec') {$Source0="https://github.com/jgm/pandoc/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'powershell.spec') {$Source0="https://github.com/PowerShell/PowerShell/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'pycurl.spec') {$Source0="https://github.com/pycurl/pycurl/archive/refs/tags/REL_%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-requests.spec') {$Source0="https://github.com/psf/requests/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'python-urllib3.spec') {$Source0="https://github.com/urllib3/urllib3/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'rpcsvc-proto.spec') {$Source0="https://github.com/thkukuk/rpcsvc-proto/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'rpm.spec') {$Source0="https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-%{version}-release.tar.gz"}

        elseif ($_.Spec -ilike 'slirp4netns.spec') {$Source0="https://github.com/rootless-containers/slirp4netns/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'sqlite.spec') {$Source0="https://github.com/sqlite/sqlite/archive/refs/tags/version-%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'systemd.spec') {$Source0="https://github.com/systemd/systemd-stable/archive/refs/tags/v%{version}.tar.gz"}
    
        elseif ($_.Spec -ilike 'tornado.spec') {$Source0="https://github.com/tornadoweb/tornado/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'tpm2-pkcs11.spec') {$Source0="https://github.com/tpm2-software/tpm2-pkcs11/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'u-boot.spec') {$Source0="https://github.com/u-boot/u-boot/archive/refs/tags/v%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'unixODBC.spec') {$Source0="https://github.com/lurcher/unixODBC/archive/refs/tags/%{version}.tar.gz"}

        elseif ($_.Spec -ilike 'uwsgi.spec') {$Source0="https://github.com/unbit/uwsgi/archive/refs/tags/%{version}.tar.gz"}




        if ($Source0 -ilike '*%{name}*') { $Source0 = $Source0 -ireplace '%{name}',$_.Name }

        # add url path if necessary and possible
        if (($Source0 -notlike '*//*') -and ($_.url -ne ""))
        {
            if (($_.url -match '.tar.gz$') -or ($_.url -match '.tar.xz$') -or ($_.url -match '.tar.bz2$') -or ($_.url -match '.tgz$'))
            {$Source0=$_.url}
            else
            { $Source0 = [System.String]::Concat(($_.url).Trimend('/'),"/",$Source0) }
        }




        # cut last index in $_.version and save value in $version
        $Version=""
        $versionArray=($_.version).split("-")
        if ($versionArray.length -gt 0)
        {
            $Version=$versionArray[0]
            for ($i=1;$i -lt ($versionArray.length -1);$i++) {$version=$Version + "-"+$versionArray[$i]}
        }
        if ($Source0 -ilike '*%{version}*') { $Source0 = $Source0 -ireplace '%{version}',$version }

        if ($Source0 -ilike '*%{url}*') { $Source0 = $Source0 -ireplace '%{url}',$_.url }
        if ($Source0 -ilike '*%{srcname}*') { $Source0 = $Source0 -ireplace '%{srcname}',$_.srcname }
        if ($Source0 -ilike '*%{gem_name}*') { $Source0 = $Source0 -ireplace '%{gem_name}',$_.gem_name }



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
                                    $Source0=$Source0Save

                                    $Name=""
                                    $NameArray=($_.Name).split("-")
                                    if ($NameArray.length -gt 1) { $Name=$NameArray[$NameArray.length -1]}

                                    if ($Name -ne "")
                                    {
                                        $replace=[System.String]::Concat(('/archive/refs/tags/'),$Name,"-",$version)
                                        $replacenew=[System.String]::Concat(('/archive/refs/tags/v'),$version)
                                        $Source0 = $Source0 -ireplace $replace,$replacenew
                                        $urlhealth = urlhealth($Source0)
                                        if ($urlhealth -ne "200")
                                        {
                                            $Source0=$Source0Save
                                            $versionnew = $version -ireplace '_','.'
                                            $Source0 = $Source0 -ireplace $version,$versionnew
                                            $urlhealth = urlhealth($Source0)
                                            if ($urlhealth -ne "200")
                                            {
                                                $Source0=$Source0Save
                                                $versionnew = $version -ireplace 'r',''
                                                $Source0 = $Source0 -ireplace $version,$versionnew
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
                if ($urlhealth -ne "200") {$Source0=""}
            }
        }

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

            $SourceTagURL=$SourceTagURL + "/tags"
            try{
                $Names = (invoke-restmethod -uri $SourceTagURL -usebasicparsing -headers @{Authorization = "Bearer $accessToken"})
                $NameLatest = ($Names | sort-object -Property @{Expression={[string]($_.name -replace "\D", "")}} | select -Last 1).Name
            }
            catch{$NameLatest=""}
            if ($NameLatest -ne "")
            {
                if (($Version -ireplace "v","") -lt ($NameLatest -ireplace "v","")) {$UpdateAvailable = $NameLatest}
            }
        }

        $line=[System.String]::Concat($_.spec, ',',$_.source0,',',$Source0,',',$urlhealth,',',$UpdateAvailable)
        $Lines += $line
    }
    "Spec"+","+"Source0 original"+","+"Recent Source0 modified for UrlHealth"+","+"UrlHealth"+","+"UpdateAvailable"| out-file $outputfile
    $lines | out-file $outputfile -append
    }
}

$access = Read-Host -Prompt "Please enter your Github Access Token."

write-output "Generating URLHealth report for Photon OS 3.0 ..."
GitPhoton -release "3.0"
$Packages3=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-3.0
CheckURLHealth -outputfile "$env:public\photonos-urlhealth-3.0_$((get-date).tostring("yyyMMddHHmm")).prn" -accessToken $access -CheckURLHealthPackageObject $Packages3


write-output "Generating URLHealth report for Photon OS 4.0 ..."
GitPhoton -release "4.0"
$Packages4=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-4.0
CheckURLHealth -outputfile "$env:public\photonos-urlhealth-4.0_$((get-date).tostring("yyyMMddHHmm")).prn" -accessToken $access -CheckURLHealthPackageObject $Packages4

write-output "Generating URLHealth report for Photon OS 5.0 ..."
GitPhoton -release "5.0"
$Packages5=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-5.0
CheckURLHealth -outputfile "$env:public\photonos-urlhealth-5.0_$((get-date).tostring("yyyMMddHHmm")).prn" -accessToken $access -CheckURLHealthPackageObject $Packages5


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

