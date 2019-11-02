#!/bin/sh
tdnf remove -y powershell
rm /usr/bin/Pwsh*
rm /usr/bin/pwsh*
rm -r /opt/microsoft
rm -r /tmp/Microsoft.PackageManagement
rm -r /tmp/photonos-scripts-master
rm /tmp/Core*
rm /tmp/tmp*.ps1
rm /tmp/*.zip
rm -r /root/.config/powershell/
rm -r /root/.cache/powershell
rm -r /root/.local/share/powershell
rm -r /usr/local/share/powershell
rm -r /var/share/powershell
rm -r /var/cache/microsoft/powershell
