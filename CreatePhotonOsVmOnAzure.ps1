﻿#
# Create a VMware photon OS VM on Microsoft Azure
#
# History
# 0.1  21.08.2019   dcasota  Initial release
# 0.2  04.09.2019   dcasota  replace new-azvm with az vm create  
#
# related weblinks
# https://vmware.github.io/photon/assets/files/html/3.0/photon_installation/setting-up-azure-storage-and-uploading-the-vhd.html
# https://www.virtuallyghetto.com/2019/01/powershell-for-photonos-on-raspberry-pi-3.html#more-163856


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

# create lab resource group if it does not exist
$result = get-azresourcegroup -name $ResourceGroupName -Location $LocationName -ErrorAction SilentlyContinue
if ($null -eq $result)
{
    New-AzResourceGroup -Name $ResourceGroupName -Location $LocationName
}


$ServerSubnet  = New-AzVirtualNetworkSubnetConfig -Name frontendSubnet  -AddressPrefix $ServerSubnetAddressPrefix
$vnet = New-AzVirtualNetwork -Name $NetworkName -ResourceGroupName $ResourceGroupName -Location $LocationName -AddressPrefix $VnetAddressPrefix -Subnet $ServerSubnet
$vnet | Set-AzVirtualNetwork

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

# Verify VM doesn't exist
[Microsoft.Azure.Commands.Compute.Models.PSVirtualMachine] `
$VM = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue
if (-not ([string]::IsNullOrEmpty($VM))) { return }

# networksecurityruleconfig
$rdpRule = New-AzNetworkSecurityRuleConfig -Name myRdpRule -Description "Allow RDP" `
    -Access Allow -Protocol Tcp -Direction Inbound -Priority 110 `
    -SourceAddressPrefix Internet -SourcePortRange * `
    -DestinationAddressPrefix * -DestinationPortRange 3389
 $nsg = New-AzNetworkSecurityGroup -Name $nsgName -ResourceGroupName $ResourceGroupName -Location $LocationName -SecurityRules $rdpRule

# Create a public IP address
$pip = New-AzPublicIpAddress -ResourceGroupName $ResourceGroupName -Location $LocationName -Name $PublicIPDNSName -AllocationMethod Static -IdleTimeoutInMinutes 4
# Create a virtual network card and associate with public IP address and NSG
$nic = New-AzNetworkInterface -Name $NICName -ResourceGroupName $ResourceGroupName -Location $LocationName `
 -SubnetId $vnet.Subnets[0].Id -PublicIpAddressId $pip.Id -NetworkSecurityGroupId $nsg.Id

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
--generate-ssh-keys

# enable boot diagnostics for serial console option
az vm boot-diagnostics enable --name $vmName --resource-group $ResourceGroupName --storage "https://${StorageAccountName}.blob.core.windows.net" 

# Verify that the vm was created
$vmList = Get-AzVM -ResourceGroupName $resourceGroupName
$vmList.Name

# custom data
# --------------
#  (login)
# whoami
# sudo passwd -u root
# sudo passwd root
#  (set new password)
# su -l root
# whoami
# 
# tdnf -y update
# tdnf -y install tar icu libunwind unzip wget
# wget https://github.com/PowerShell/PowerShell/releases/download/v7.0.0-preview.3/powershell-7.0.0-preview.3-linux-x64.tar.gz
# wget https://vdc-download.vmware.com/vmwb-repository/dcr-public/db25b92c-4abe-42dc-9745-06c6aec452f1/d15f15e7-4395-4b4c-abcf-e673d047fd29/VMware-PowerCLI-11.4.0-14413515.zip
# mkdir ~/powershell
# mkdir -p ~/.local/share/powershell/Modules
# tar -xvf ./powershell-7.0.0-preview.3-linux-x64.tar.gz  -C ~/powershell
# unzip VMware-PowerCLI-11.4.0-14413515.zip -d ~/.local/share/powershell/Modules
# powershell/pwsh
#  $PSVersionTable
#  get-module -name VMware.PowerCLI -listavailable