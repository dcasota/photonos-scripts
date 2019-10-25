#
# Create a VMware photon OS VM on Microsoft Azure
#
# related weblinks
# https://vmware.github.io/photon/assets/files/html/3.0/photon_installation/setting-up-azure-storage-and-uploading-the-vhd.html
#
# History
# 0.1  21.08.2019   dcasota  Initial release
# 0.2  04.09.2019   dcasota  replace new-azvm with az vm create
# 0.3  08.09.2019   dcasota  custom-data bash file added
# 0.4  09.09.2019   dcasota  mono+nuget+powershell+PowerCLI installation added
# 0.5  10.09.2019   dcasota  Azure Powershell installation added, added connectivity to Powershellgallery
# 0.6  17.10.2019   dcasota  Switch true/false for any postprovisioning added
#
#

$ScriptPath=$PSScriptRoot

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

# Postprovisioning with Powershell(+PwshGallery)
$postprovisioning=$true

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

# az vm create
#save and reapply location info
$locationstack=get-location
set-location -Path ${ScriptPath}

if ($postprovisioning -eq "true")
{
	# create custom data file for az vm create --custom-data
	# Must have write permission to $Scriptpath
	$BashfileName="custom_bash.sh"
	$Bashfile=${ScriptPath}+"\"+$BashFileName
	if (Test-path(${Bashfile})) {remove-item ${Bashfile} -Force}
	(echo '#!/bin/sh')>${Bashfile}
	(echo 'echo $(date) + "Cloud-init custom data installing ..." >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'whoami >> /tmp/myScript.txt >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'tdnf -y update >> /tmp/myScript.txt >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'tdnf -y install tar icu libunwind unzip curl >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'mkdir ~/photonos-scripts >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'cd ~/photonos-scripts >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'curl -O -J -L https://github.com/dcasota/photonos-scripts/archive/master.zip >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'unzip ~/photonos-scripts/photonos-scripts-master.zip -d ~/photonos-scripts >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'cd ~/photonos-scripts/photonos-scripts-master >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'chmod a+x ./*.sh >> /tmp/myScript.txt')>>${Bashfile}
	(echo './DockerPwshGalleryonPhotonOS.sh >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'cd ~/ >> /tmp/myScript.txt')>>${Bashfile}
	(echo '# rm -r ~/photonos-scripts >> /tmp/myScript.txt')>>${Bashfile}
	(echo 'echo $(date) + "Cloud-init custom data installed." >> /tmp/myScript.txt')>>${Bashfile}
	Get-ChildItem ${Bashfile} | % { $x = get-content -raw -path $_.fullname; $x -replace "`r`n","`n" | set-content -path $_.fullname }

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
	--custom-data $Bashfilename
}
else
{
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
}
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
