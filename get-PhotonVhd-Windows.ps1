#
# Helper-script to download and to extract VMware Photon OS .vhd.
#
# History
# 0.1   27.01.2020   dcasota  Initial release
#
#


Function DeGZip-File{
# Original Source https://scatteredcode.net/download-and-extract-gzip-tar-with-powershell/
    Param(
        $infile,
        $outfile = ($infile -replace '\.gz$','')
        )
    $input = New-Object System.IO.FileStream $inFile, ([IO.FileMode]::Open), ([IO.FileAccess]::Read), ([IO.FileShare]::Read)
    $output = New-Object System.IO.FileStream $outFile, ([IO.FileMode]::Create), ([IO.FileAccess]::Write), ([IO.FileShare]::None)
    $gzipStream = New-Object System.IO.Compression.GzipStream $input, ([IO.Compression.CompressionMode]::Decompress)
    $buffer = New-Object byte[](1024)
    while($true){
        $read = $gzipstream.Read($buffer, 0, 1024)
        if ($read -le 0){break}
        $output.Write($buffer, 0, $read)
        }
    $gzipStream.Close()
    $output.Close()
    $input.Close()
}


param([string]$Uri="http://dl.bintray.com/vmware/photon/3.0/Rev2/photon-azure-3.0-9355405.vhd.tar.gz")
param([string]$tmppath=$env:temp)

$PhotonOSTarGzFileName=split-path -path $Uri -Leaf
$PhotonOSTarFileName=$PhotonOSTarGzFileName.Substring(0,$PhotonOSTarGzFileName.LastIndexOf('.')).split('\')[-1]
$PhotonOSVhdFilename=$PhotonOSTarFileName.Substring(0,$PhotonOSTarFileName.LastIndexOf('.')).split('\')[-1]

# check Azure CLI
az help 1>$null 2>$null
if ($lastexitcode -ne 0)
{
    Invoke-WebRequest -Uri https://aka.ms/installazurecliwindows -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'
}

# check Azure Powershell
if (([string]::IsNullOrEmpty((get-module -name Az* -listavailable)))) {install-module Az -force -Confirm $false -ErrorAction SilentlyContinue}

# check PS7Zip
if (([string]::IsNullOrEmpty((get-module -name PS7zip -listavailable)))) {install-module PS7zip -force -Confirm $false -ErrorAction SilentlyContinue}

$tarfile=$tmppath + "\"+$PhotonOSTarFileName
$vhdfile=$tmppath + "\"+$PhotonOSVhdFilename
$gzfile=$tmppath + "\"+$PhotonOSTarGzFileName

if (!(Test-Path -d $vhdfile))
{
    if (Test-Path -d $tmppath)
    {
        cd $tmppath
        if (!(Test-Path $gzfile))
        {

            $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'" | select-object @{Name="FreeGB";Expression={[math]::Round($_.Freespace/1GB,2)}}
            if ($disk.FreeGB > 35)
            {
                Invoke-WebRequest $Uri -OutFile $PhotonOSTarGzFileName
                if (Test-Path $gzfile)
                {
                    DeGZip-File $gzfile $tarfile
                    if (Test-Path $tarfile)
                    {
                        # if $tarfile successfully extracted, delete $gzfile
                        Remove-Item -Path $gzfile
                        Expand-7zip $tarfile -destinationpath $tmppath
                        # if $vhdfile successfully extracted, delete $tarfile
                        if (Test-Path -d $vhdfile) { Remove-Item -Path $tarfile}
                    }
                }
            }
        }
    }
}
