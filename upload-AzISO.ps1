#
# Upload a .vhd'fied bootable ISO to Azure
#
# Prerequisites:
#    - VMware Photon OS 3.0
#    - Powershell + Azure Powershell ( + Azure CLI) release installed
#    - Run as root
#
# History
# 0.1  04.11.2019   dcasota  UNFINISHED! WORK IN PROGRESS!


# Location setting
$LocationName = "westus"

# Resourcegroup setting
$ResourceGroupName = "photonos-lab-rg"

# network setting
$NetworkName = "photonos-lab-network"

# Base Image
$StorageAccountName="vhdfiedbootableiso"
$ContainerName="disks"
$filename="isoboot.vhd"
$BlobName=$filename
$LocalFilePath="/tmp"

# Environment
tdnf update -y
tdnf install wget unzip bzip2 curl -y

# Input parameter
$tenant=Read-Host -Prompt "Enter your Azure tenant id"
$ISOurl=Read-Host -Prompt "Enter your ISO download url"
$ISOfilename= split-path $ISOurl -leaf


cd /root

# Install AzCopy & Login
wget -O azcopy.tar.gz https://aka.ms/downloadazcopy-v10-linux
tar -xf azcopy.tar.gz
./azcopy_linux_amd64_10.3.2/azcopy login --tenant-id $tenant

# Verify Login
if( -not $(Get-AzContext) ) { return }

Set-AzContext -Tenant $tenant

# install vbox
# wget https://download.virtualbox.org/virtualbox/6.0.14/VirtualBox-6.0.14-133895-Linux_amd64.run
# chmod a+x VirtualBox-6.0.14-133895-Linux_amd64.run
# ./VirtualBox-6.0.14-133895-Linux_amd64.run
# TODO
# There were problems setting up VirtualBox.  To re-start the set-up process, run
#   /sbin/vboxconfig
# as root.  If your system is using EFI Secure Boot you may need to sign the
# kernel modules (vboxdrv, vboxnetflt, vboxnetadp, vboxpci) before you can load
# them. Please see your Linux system's documentation for more information.
# 
# VirtualBox has been installed successfully.

# cd $LocalFilePath
cd /root

# convert
# curl -O -J -L $ISOurl
# vboxmanage convertfromraw $ISOfilename $filename
# TODO
# WARNING: The vboxdrv kernel module is not loaded. Either there is no module
#          available for the current kernel (4.19.82-1.ph3) or it failed to
#          load. Please recompile the kernel module and install it by
# 
#            sudo /sbin/vboxconfig
# 
#          You will not be able to start VMs until this problem is fixed.


# Prepare upload
$storageaccount=get-azstorageaccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -ErrorAction SilentlyContinue
if (([string]::IsNullOrEmpty($storageaccount)))
{
    $storageaccount=New-AzStorageAccount -ResourceGroupName $ResourceGroupName -Name $StorageAccountName -Location $LocationName -Kind Storage -SkuName Premium_LRS -ErrorAction SilentlyContinue
}
$storageaccountkey=(get-azstorageaccountkey -ResourceGroupName $ResourceGroupName -name $StorageAccountName)
$storagecontext=$storageaccount.context
New-AzStorageContainer -Name $containerName -Context $storagecontext


Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination "https://$storageaccountname.blob.core.windows.net/$containername/$fileName" -LocalFilePath $filename -Overwrite
# FAIL #1
# error message:
# Add-AzVhd: unsupported format


# FAIL #2 : Upload using Set-AzStorageBlobContent
# -----------------------------------------------
# command(s):
# New-AzStorageContainer -Name $containerName -Context $destinationContext -Permission blob
# Set-AzStorageBlobContent -File $filename -Container $containerName -Blob $BlobName -Context $destinationContext
#
# error message:
# (successfully completes!)
# However, afterwards when creating a VM, the error message shown is 'this is not a blob'. In reference to
# https://www.thomas-zuehlke.de/2019/08/creating-azure-vm-based-on-local-vhd-files/ this is expected as it is not a storage account of type "Pageblob".
# The solution is to use AzCopy, and AzCopy has the prerequisite that the account used must have the role "Blob Data Contributor" assigned. See https://github.com/Azure/azure-storage-azcopy/issues/77.


# FAIL #3 : Upload using AzCopy
# -----------------------------
# command(s):
# /root/azcopy_linux_amd64_10.3.2/azcopy copy $filename $containerSASURI
# error message:
#
# successfully completed. However, afterwards when uploading the following error message occurs:
#  $disk1 = New-AzDisk -Disk $disk1Config -ResourceGroupName $ResourceGroupName -DiskName $disk1name
# New-AzDisk : The specified cookie value in VHD footer indicates that disk 'isobootdisk.vhd' with blob https://vhdfiedbootableiso.blob.core.windows.net:8443/disks/isobootdisk.vhd is not a supported VHD. Disk is expected to have cookie value 'conectix'.
# ErrorCode: BadRequest
# ErrorMessage: The specified cookie value in VHD footer indicates that disk 'isobootdisk.vhd' with blob https://vhdfiedbootableiso.blob.core.windows.net:8443/disks/isobootdisk.vhd is not a supported VHD. Disk is expected to have cookie value 'conectix'.
# ErrorTarget: 
# StatusCode: 400
# ReasonPhrase: Bad Request
# OperationID : 6843143c-f39c-489e-bd97-7fdf50d46c6f
# At line:1 char:10
# + $disk1 = New-AzDisk -Disk $disk1Config -ResourceGroupName $ResourceGr ...
# +          ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
#     + CategoryInfo          : CloseError: (:) [New-AzDisk], ComputeCloudException
#     + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.Automation.NewAzureRmDisk
# 


# FAIL #4 : Upload using Add-AzVhd
# --------------------------------
# command(s):
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination ${containerSASURI} -LocalFilePath $filename -Overwrite
#
# error message:
# Add-AzVhd: https://[put blob name here].blob.core.windows.net/[put container name here]?sv=2019-02-02&sr=c&sig=[your sig]&se=2019-11-20T09%3A14%3A18Z&sp=rw (Parameter'Destination')
#
#
# FAIL #4b : Upload using Add-AzVhd
# ---------------------------------
# command(s):
# $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUploadedVhd -LocalFilePath $filename -Overwrite
#
# error message on Pwsh6.2.3:
#
# Add-AzVhd : unsupported format
# At line:1 char:1
# + Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUp ...
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : CloseError: (:) [Add-AzVhd], VhdParsingException
# + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.StorageServices.AddAzureVhdCommand
# 


# FAIL #5 : Upload using azure cli and add-azvhd
# ----------------------------------------------
# command(s):
# $result=az storage container exists --account-name $storageaccountname --name ${ContainerName} | convertfrom-json
# if ($result.exists -eq $false)
# {
#     az storage container create --name ${ContainerName} --public-access blob --account-name $StorageAccountName --account-key ($storageaccountkey[0]).value
# }
# $result=az storage blob exists --account-key ($storageaccountkey[0]).value --account-name $StorageAccountName --container-name ${ContainerName} --name ${BlobName} | convertfrom-json
# if ($result.exists -eq $false)
# {
#     az storage blob upload --account-name $StorageAccountName `
#     --account-key ($storageaccountkey[0]).value `
#     --container-name ${ContainerName} `
#     --type page `
#     --file $filename `
#     --name ${BlobName}
# }
#
# # Result: completes successfully however throws an error afterwards when creating a VM from the vhd'fied bootable ISO.
#
# FAIL #5b : Upload using azure cli and add-azvhd (az login + connect-azaccount)
# ------------------------------------------------------------------------------
# command(s):
# $urlOfUploadedVhd = "https://${StorageAccountName}.blob.core.windows.net/${ContainerName}/${BlobName}"
# Add-AzVhd -ResourceGroupName $ResourceGroupName -Destination $urlOfUploadedVhd -LocalFilePath $filename -Overwrite
#
# error message on Pwsh6.0:
#
# Detecting the empty data blocks completed.add-azvhd : Operation is not supported on this platform.
# At line:1 char:1
# + add-azvhd -resourcegroupname $resourcegroupname
# + ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
# + CategoryInfo          : CloseError: (:) [Add-AzVhd], PlatformNotSupportedException
# + FullyQualifiedErrorId : Microsoft.Azure.Commands.Compute.StorageServices.AddAzureVhdCommand
# see https://github.com/Azure/azure-powershell/issues/10549
#

# TODO Cleanup vbox, downloaded ISO, etc.
rm -r /root/azcopy_linux_amd64_10.3.2
rm -r /root/azcopy.tar.gz
rm -r /root/VirtualBox-6.0.14-133895-Linux_amd64.run
rm $LocalFilePath/$filename
rm $LocalFilePath/$ISOfilename