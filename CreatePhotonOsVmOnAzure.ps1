#
# Create a VMware photon OS VM on Microsoft Azure
#
# History
# 0.1  21.08.2019   dcasota  Initial release
# 0.2  04.09.2019   dcasota  replace new-azvm with az vm create
# 0.3  08.09.2019   dcasota  custom-data bash file added
#
# related weblinks
# https://vmware.github.io/photon/assets/files/html/3.0/photon_installation/setting-up-azure-storage-and-uploading-the-vhd.html
# https://www.virtuallyghetto.com/2019/01/powershell-for-photonos-on-raspberry-pi-3.html#more-163856

# Requires Run as Administrator
# Get the ID and security principal of the current user account
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
# Get the security principal for the Administrator role
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (-not ($myWindowsPrincipal.IsInRole($adminRole))) { return }


# Location setting
$LocationName = "westeurope"

# Resourcegroup setting
$ResourceGroupName = "photonos-lab-rg"

# network setting
$NetworkName = "photonos-lab-network"

# virtual network and subnets setting
$VnetAddressPrefix = "192.168.0.0/16"
$ServerSubnetAddressPrefix = "192.168.1.0/24"

# Base Image
$StorageAccountName="photonos$(Get-Random)"
$ContainerName="disks"
$BlobName="photon-azure-3.0-26156e2.vhd"
#This is the locally unzipped .vhd from https://vmware.bintray.com/photon/3.0/GA/azure/photon-azure-3.0-26156e2.vhd.tar.gz
$LocalFilePath="G:\photon-azure-3.0-26156e2.vhd.tar\${BlobName}"

# vm settings
$VMName = "photonos"
$VMSize = "Standard_A1"
$ComputerName = $VMName
$NICName = "${VMName}nic"
$VMLocalAdminUser = "adminuser" #all small letters
$VMLocalAdminPassword = "PhotonOs123!" #pwd must be 7-12 characters
$diskSizeGB = '16' # minimum is 16gb
$PublicIPDNSName="mypublicdns$(Get-Random)"
$nsgName = "myNetworkSecurityGroup"

# Create az login object. You get a pop-up prompting you to enter the credentials.
$cred = Get-Credential -Message "Enter a username and password for az login."
connect-Azaccount -Credential $cred
# Verify Login
if( -not $(Get-AzContext) ) { return }

# Verify VM doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] `
$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if (-not ([string]::IsNullOrEmpty($VM))) { return }

# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($result)))
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}

$vnet = get-azvirtualnetwork -name $networkname -ResourceGroupName $resourcegroupname -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($vnet)))
{
    $ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $ServerSubnetAddressPrefix
    $vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
    $vnet | Set-AzVirtualNetwork
}

# Prepare vhd
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($storageaccount)))
{
    New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind Storage -SkuName Standard_LRS -ErrorAction SilentlyContinue
}
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)


$result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
if ($result.exists -eq $false)
{
    az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
}

#Upload and create managed image from the uploaded VHD
$urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"

$result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
if ($result.exists -eq $false)
{
    az storage blob upload --account-name $StorageAccountName `
    --account-key ($storageaccountkey[0]).value `
    --container-name ${ContainerName} `
    --type page `
    --file $LocalFilePath `
    --name ${BlobName}
}

# create vm
# -----------

# VM local admin setting
$VMLocalAdminSecurePassword = ConvertTo-SecureString $VMLocalAdminPassword -AsPlainText -Force
$LocalAdminUserCredential = New-Object System.Management.Automation.PSCredential ($VMLocalAdminUser, $VMLocalAdminSecurePassword)

# networksecurityruleconfig
$nsg=get-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($nsg)))
{
    $rdpRule = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
    -SourceAddressPrefix Internet -SourcePortRange * `
    -DestinationAddressPrefix * -DestinationPortRange 3389
    $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule
}
# Create a public IP address
$nic=get-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($nic)))
{
    $pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
    # Create a virtual network card and associate with public IP address and NSG
    $nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
        -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id
}

# create custom data file for az vm create --custom-data
$BashFileName="simple_bash.sh"
$BashFile=${env:TMP}+"\"+${BashFileName}
if (Test-path($Bashfile)) {remove-item $Bashfile -Force}
(echo '#!/bin/sh')>$BashFile
(echo 'echo "this has been written via cloud-init" + $(date) >> /tmp/myScript.txt')>>$BashFile
(echo 'whoami >> /tmp/myScript.txt')>>$BashFile
(echo 'tdnf -y update >> /tmp/myScript.txt')>>$BashFile
(echo 'tdnf -y install tar icu libunwind unzip wget >> /tmp/myScript.txt')>>$BashFile
(echo 'wget https://download.mono-project.com/sources/mono/mono-6.0.0.313.tar.xz >> /tmp/myScript.txt')>>$BashFile
(echo 'mkdir ~/mono >> /tmp/myScript.txt')>>$BashFile
(echo 'tar -xvf mono-6.0.0.313.tar.xz -C ~/mono >> /tmp/myScript.txt')>>$BashFile
(echo 'yum install mono-complete >> /tmp/myScript.txt')>>$BashFile
(echo 'tdnf install linux-api-headers cmake gcc glibc-devel binutils >> /tmp/myScript.txt')>>$BashFile
(echo 'yum install bison gettext glib2 freetype fontconfig libpng libpng-devel >> /tmp/myScript.txt')>>$BashFile
(echo 'yum install java unzip gcc gcc-c++ automake autoconf libtool make bzip2 wget >> /tmp/myScript.txt')>>$BashFile
(echo 'cd ~/mono >> /tmp/myScript.txt')>>$BashFile
(echo './configure --prefix=/usr/local >> /tmp/myScript.txt')>>$BashFile
(echo 'make >> /tmp/myScript.txt')>>$BashFile
(echo 'make install >> /tmp/myScript.txt')>>$BashFile
(echo 'curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe >> /tmp/myScript.txt')>>$BashFile
(echo 'mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2" >> /tmp/myScript.txt')>>$BashFile
(echo 'wget https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.3/powershell-7.0.0-preview.3-linux-x64.tar.gz >> /tmp/myScript.txt')>>$BashFile
(echo 'wget https://vdc-download.vmware.com/vmwb-repository/dcr-public/db25b92c-4abe-42dc-9745-06c6aec452f1/d15f15e7-4395-4b4c-abcf-e673d047fd29/VMware-PowerCLI-11.4.0-14413515.zip >> /tmp/myScript.txt')>>$BashFile
(echo 'mkdir ~/powershell >> /tmp/myScript.txt')>>$BashFile
(echo 'mkdir -p ~/.local/share/powershell/Modules >> /tmp/myScript.txt')>>$BashFile
(echo 'tar -xvf ./powershell-7.0.0-preview.3-linux-x64.tar.gz  -C ~/powershell >> /tmp/myScript.txt')>>$BashFile
(echo 'unzip VMware-PowerCLI-11.4.0-14413515.zip -d ~/.local/share/powershell/Modules >> /tmp/myScript.txt')>>$BashFile
(echo 'echo "this has been written via cloud-init" + $(date) >> /tmp/myScript.txt')>>$BashFile
(echo 'powershell/pwsh >> /tmp/myScript.txt')>>$BashFile
(echo '$PSVersionTable >> /tmp/myScript.txt')>>$BashFile
(echo 'get-module -name VMware.PowerCLI -listavailable >> /tmp/myScript.txt')>>$BashFile
(echo 'exit >> /tmp/myScript.txt')>>$BashFile

#save and reapply location info
$locationstack=get-location
set-location -Path $psscriptroot
# az vm create
az vm create --resource-group $ResourceGroupName --location $LocationName --name $vmName `
--size $VMSize `
--admin-username $VMLocalAdminUser --admin-password $VMLocalAdminPassword `
--storage-account $StorageAccountName `
--storage-container-name ${ContainerName} `
--os-type linux `
--use-unmanaged-disk `
--os-disk-size-gb $diskSizeGB `
--image $urlOfUploadedVhd `
--computer-name $computerName `
--nics $nic.Id `
--generate-ssh-keys `
--custom-data $BashFileName
set-location -path $locationstack

# enable boot diagnostics for serial console option
az vm boot-diagnostics enable --name $vmName --resource-group $ResourceGroupName --storage "https://${StorageAccountName}.blob.core.windows.net" 

# Verify that the vm was created
$vmList = Get-AzVM -ResourceGroupName $resourceGroupName
$vmList.Name

# after setup:
#  (login with user credentials)
# whoami
# sudo passwd -u root
# sudo passwd root
#  (set new password)
# su -l root
# whoami
# powershell/pwsh
#  $PSVersionTable
#  get-module -name VMware.PowerCLI -listavailable


# via docker mono + nuget?
# docker pull mono

# lokales mono + nuget
# wget https://download.mono-project.com/sources/mono/mono-6.0.0.313.tar.xz
# tar -xvf mono-6.0.0.313.tar.xz
# curl https://download.mono-project.com/repo/centos7-stable.repo | tee /etc/yum.repos.d/mono-centos7-stable.repo
# yum install mono-complete
# tdnf install linux-api-headers
# tdnf install gcc glibc-devel binutils
# tdnf install cmake
# yum install bison gettext glib2 freetype fontconfig libpng libpng-devel
# yum install java unzip gcc gcc-c++ automake autoconf libtool make bzip2 wget
# cd ~/dotnet/mono-6.0.0.313
# ./configure --prefix=/usr/local
# make
# make install
# https://unix.stackexchange.com/questions/120248/install-mono-and-monodevelop-on-a-new-redhat-6-5-workstation

# curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
# alias nuget="mono /usr/local/bin/nuget.exe"

# dotnet nuget hat noch keine parameter list oder install!
# tdnf -y install lttng-ust libcurl openssl-libs krb5-libs libicu zlib
# wget https://dot.net/v1/dotnet-install.sh
# chmod a+x ./dotnet-install.sh
# ./dotnet-install.sh -version latest
# wget https://download.visualstudio.microsoft.com/download/pr/daf57b64-36b6-405e-9e12-0a8627b46951/07c100dd9aed24440e9147daf79f2aa2/dotnet-runtime-3.0.0-preview9-19423-09-linux-x64.tar.gz
# mkdir ~/dotnet
# tar -xvf dotnet-runtime-3.0.0-preview9-19423-09-linux-x64.tar.gz -C ~/dotnet
# wget https://download.visualstudio.microsoft.com/download/pr/9f21e352-9d2c-4e3b-af45-915da89158db/0e8a7ea83cc08d4bcf417a927a36ed6f/dotnet-runtime-2.2.6-linux-x64.tar.gz
# tar -xvf dotnet-runtime-2.2.6-linux-x64.tar.gz
# https://download.visualstudio.microsoft.com/download/pr/228832ea-805f-45ab-8c88-fa36165701b9/16ce29a06031eeb09058dee94d6f5330/dotnet-sdk-2.2.401-linux-x64.tar.gz
# tar -xvf dotnet-sdk-2.2.401-linux-x64.tar.gz
# ~/dotnet/dotnet nuget --help



# wget https://github.com/dcasota/photonosonazure/archive/master.zip
# unzip master.zip
# root/photonosonazure-master> ./CreatePhotonOsVmOnAzure.ps1


#https://github.com/vmware/photon/issues/815

#https://unix.stackexchange.com/questions/120248/install-mono-and-monodevelop-on-a-new-redhat-6-5-workstation
#https://stackoverflow.com/questions/38118548/how-to-install-nuget-from-command-line-on-linux
#https://stackoverflow.com/questions/41387467/how-to-install-nuget-on-amazon-linux
#https://download.mono-project.com/sources/mono/
#https://vmware.github.io/photon/assets/files/html/3.0/photon_admin/compiling-c-code-on-the-minimal-version-of-photon-os.html

#wget https://download.mono-project.com/sources/mono/mono-6.0.0.313.tar.xz
#mkdir ~/mono
#tar -xvf mono-6.0.0.313.tar.xz -C ~/mono
#yum install mono-complete
#tdnf install linux-api-headers cmake gcc glibc-devel binutils
#yum install bison gettext glib2 freetype fontconfig libpng libpng-devel
#yum install java unzip gcc gcc-c++ automake autoconf libtool make bzip2 wget
#cd ~/mono
#./configure --prefix=/usr/local
#make
#make install
#curl -o /usr/local/bin/nuget.exe https://dist.nuget.org/win-x86-commandline/latest/nuget.exe
#mono /usr/local/bin/nuget.exe sources Add -Name PSGallery -Source "https://www.powershellgallery.com/api/v2"

#wget https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.3/powershell-7.0.0-preview.3-linux-x64.tar.gz
#mkdir ~/powershell
#tar -xvf ./powershell-7.0.0-preview.3-linux-x64.tar.gz -C ~/powershell
#powershell/pwsh
# get-psrepository