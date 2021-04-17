# .SYNOPSIS
#  This VMware Photon OS github branches packages (specs) report script creates an excel prn.
#
# .NOTES
#   Author:  Daniel Casota
#   Version:
#   0.1   06.03.2021   dcasota  First release
#   0.2   17.04.2021   dcasota  dev added
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
                $Release=$null
                $Release= (($_ | get-content | Select-String -Pattern "^Release:")[0].ToString() -replace "Release:", "").Trim()
                $Release = $Release.Replace("%{?dist}","")
                $Release = $Release.Replace("%{?kat_build:.kat}","")
                $Release = $Release.Replace("%{?kat_build:.%kat_build}","")
                $Release = $Release.Replace("%{?kat_build:.%kat}","")
                $Release = $Release.Replace("%{?kernelsubrelease}","")
                $Release = $Release.Replace(".%{dialogsubversion}","")
                $Version=$null
                $version= (($_ | get-content | Select-String -Pattern "^Version:")[0].ToString() -replace "Version:", "").Trim()
                if ($Release -ne $null) {$Version = $Version+"-"+$Release}
                $Packages +=[PSCustomObject]@{
                    Spec = $_.Name
                    Version = $Version
                    Name = $object.Name
                }
            }
        }
        catch{}
    }
    return $Packages
}

# EDIT
# path with all downloaded and unzipped branch directories of github.com/vmware/photon
$sourcepath="C:\Users\username\Downloads"
# output file
$outputfile="C:\Users\username\Downloads\photonos-package-report.prn"

#arrays
$Packages1=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-1.0
$Packages2=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-2.0
$Packages3=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-3.0
$Packages4=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-4.0
$Packages5=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-dev
$PackagesMaster=ParseDirectory -SourcePath $sourcepath -PhotonDir photon-master

# merge
$result = $Packages1,$Packages2,$Packages3,$Packages4,$PackagesMaster| %{$_}|Select Spec,`
@{l='photon-1.0';e={if($_.Spec -in $Packages1.Spec) {$Packages1[$Packages1.Spec.IndexOf($_.Spec)].version}}},`
@{l='photon-2.0';e={if($_.Spec -in $Packages2.Spec) {$Packages2[$Packages2.Spec.IndexOf($_.Spec)].version}}},`
@{l='photon-3.0';e={if($_.Spec -in $Packages3.Spec) {$Packages3[$Packages3.Spec.IndexOf($_.Spec)].version}}},`
@{l='photon-4.0';e={if($_.Spec -in $Packages4.Spec) {$Packages4[$Packages4.Spec.IndexOf($_.Spec)].version}}},`
@{l='photon-dev';e={if($_.Spec -in $Packages5.Spec) {$Packages5[$Packages5.Spec.IndexOf($_.Spec)].version}}},`
@{l='photon-master';e={if($_.Spec -in $PackagesMaster.Spec) {$PackagesMaster[$PackagesMaster.Spec.IndexOf($_.Spec)].version}}} -Unique | Sort-object Spec

# write output
"Spec"+","+"photon-1.0"+","+"photon-2.0"+","+"photon-3.0"+","+"photon-4.0"+","+"photon-dev"+","+"photon-master"|  out-file $outputfile
$result | % { $_.Spec+","+$_."photon-1.0"+","+$_."photon-2.0"+","+$_."photon-3.0"+","+$_."photon-4.0"+","+$_."photon-dev"+","+$_."photon-master"} |  out-file $outputfile -append
