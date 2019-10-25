#!/bin/sh
#
# This script makes Microsoft Powershell Core, VMware PowerCLI Core and the PowerShellGallery available on Photon OS.
# 
# Installing PowerShell Core on Photon OS does not built-in register PSGallery as source provider.
# One way to accomplish it is using the VMware PowerCLI Core Dockerfile. It uses an Ubuntu 16.04 docker container with Powershell Core 6.x and PowerCLI Core 11.x.
#
#
# History
# 0.1  25.10.2019   dcasota  Initial release
#
# 

echo "$(date) + Docker Pull VMware PowerCLI Core on Photon OS ..."

docker pull vmware/powerclicore:ubuntu16.04
# docker run -it vmware/powerclicore:ubuntu16.04

echo "$(date) + Docker Pull VMware PowerCLI Core on Photon OS finished."