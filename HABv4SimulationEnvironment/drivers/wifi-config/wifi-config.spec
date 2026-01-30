Summary:        WiFi configuration package for Photon OS MOK Secure Boot
Name:           wifi-config
Version:        1.0.0
Release:        1.ph5
License:        MIT
Group:          System Environment/Base
URL:            https://github.com/dcasota/photonos-scripts
Vendor:         HABv4 Project
Distribution:   Photon

BuildArch:      noarch

Requires:       libnl
Requires:       wpa_supplicant

%description
WiFi configuration package for Photon OS with MOK Secure Boot.
This package:
- Configures wpa_supplicant with correct cipher settings (CCMP)
- Enables wpa_supplicant service for wlan0
- Disables Intel iwlwifi LAR (Location Aware Regulatory) to use system regulatory
- Creates proper systemd-networkd configuration for DHCP on wlan0

%install
mkdir -p %{buildroot}/etc/wpa_supplicant
mkdir -p %{buildroot}/etc/systemd/network
mkdir -p %{buildroot}/etc/modprobe.d
mkdir -p %{buildroot}/usr/lib/systemd/system-preset

# Create default wpa_supplicant configuration
cat > %{buildroot}/etc/wpa_supplicant/wpa_supplicant-wlan0.conf << 'EOF'
# WiFi configuration for Photon OS MOK Secure Boot
# Edit this file to add your network credentials

ctrl_interface=/run/wpa_supplicant
ctrl_interface_group=wheel
update_config=1

# Cipher settings - CCMP for WPA2-AES (recommended)
# Do NOT use GCCMP - that's a typo that causes connection failures
group=CCMP
pairwise=CCMP

# Protected Management Frames (802.11w)
# 0=disabled, 1=optional, 2=required
ieee80211w=1

# Example network configuration (uncomment and edit):
# network={
#     ssid="YourNetworkName"
#     psk="YourPassword"
#     key_mgmt=WPA-PSK
#     proto=RSN
#     pairwise=CCMP
#     group=CCMP
# }
EOF

# Create modprobe.d config to disable iwlwifi LAR
cat > %{buildroot}/etc/modprobe.d/iwlwifi-lar.conf << 'EOF'
# Disable Intel iwlwifi Location Aware Regulatory (LAR)
# This allows the system regulatory database (wireless-regdb) to be used
# instead of the firmware's built-in geo-location based restrictions.
# This fixes "80 MHz not supported, disabling VHT" on Intel WiFi adapters.
options iwlwifi lar_disable=1
EOF

# Create systemd-networkd config for wlan0 DHCP
cat > %{buildroot}/etc/systemd/network/50-wlan0-dhcp.network << 'EOF'
# WiFi interface configuration for DHCP
[Match]
Name=wlan0

[Network]
DHCP=yes
IPv6AcceptRA=yes

[DHCP]
UseDNS=yes
UseNTP=yes
UseMTU=yes
EOF

# Create systemd preset to enable wpa_supplicant@wlan0
cat > %{buildroot}/usr/lib/systemd/system-preset/90-wifi-config.preset << 'EOF'
enable wpa_supplicant@wlan0.service
EOF

%post
# Enable wpa_supplicant service for wlan0
systemctl enable wpa_supplicant@wlan0.service 2>/dev/null || true

# Reload systemd to pick up new preset
systemctl daemon-reload 2>/dev/null || true

# Reload modprobe configuration
if [ -d /sys/module/iwlwifi ]; then
    # Module already loaded - notify user to reboot
    echo "NOTE: iwlwifi module is loaded. Reboot required for LAR disable to take effect."
fi

# Restart systemd-networkd if running to pick up new config
systemctl try-restart systemd-networkd 2>/dev/null || true

%files
%defattr(-,root,root)
%config(noreplace) /etc/wpa_supplicant/wpa_supplicant-wlan0.conf
%config(noreplace) /etc/modprobe.d/iwlwifi-lar.conf
%config(noreplace) /etc/systemd/network/50-wlan0-dhcp.network
/usr/lib/systemd/system-preset/90-wifi-config.preset

%changelog
* Thu Jan 30 2026 HABv4 Project <mok@photon.local> 1.0.0-1
- Initial release
- Configure wpa_supplicant with CCMP cipher (fix GCCMP typo issue)
- Disable iwlwifi LAR to enable 80MHz channels
- Add systemd-networkd DHCP configuration for wlan0
- Enable wpa_supplicant@wlan0 service
