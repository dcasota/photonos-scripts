%define debug_package %{nil}
%define firmware_dir /lib/firmware

Name:           linux-firmware-iwlwifi-ax211
Version:        20260128
Release:        1.ph5
Summary:        Intel Wi-Fi 6E AX211 firmware for iwlwifi driver
License:        Redistributable, no modification permitted
URL:            https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git
Group:          System Environment/Kernel
Vendor:         Intel Corporation
BuildArch:      noarch

# Conflicts with linux-firmware if it provides newer versions
Provides:       iwlwifi-so-a0-gf-a0-firmware = %{version}
Provides:       iwlwifi-so-a0-gf4-a0-firmware = %{version}

Source0:        iwlwifi-so-a0-gf-a0-72.ucode
Source1:        iwlwifi-so-a0-gf-a0-73.ucode
Source2:        iwlwifi-so-a0-gf-a0-74.ucode
Source3:        iwlwifi-so-a0-gf-a0-77.ucode
Source4:        iwlwifi-so-a0-gf-a0-78.ucode
Source5:        iwlwifi-so-a0-gf-a0-79.ucode
Source6:        iwlwifi-so-a0-gf-a0-81.ucode
Source7:        iwlwifi-so-a0-gf-a0-83.ucode
Source8:        iwlwifi-so-a0-gf-a0-84.ucode
Source9:        iwlwifi-so-a0-gf-a0-86.ucode
Source10:       iwlwifi-so-a0-gf-a0-89.ucode
Source11:       iwlwifi-so-a0-gf-a0.pnvm
Source12:       iwlwifi-so-a0-gf4-a0-72.ucode
Source13:       iwlwifi-so-a0-gf4-a0-73.ucode
Source14:       iwlwifi-so-a0-gf4-a0-74.ucode
Source15:       iwlwifi-so-a0-gf4-a0-77.ucode
Source16:       iwlwifi-so-a0-gf4-a0-78.ucode
Source17:       iwlwifi-so-a0-gf4-a0-79.ucode
Source18:       iwlwifi-so-a0-gf4-a0-81.ucode
Source19:       iwlwifi-so-a0-gf4-a0-83.ucode
Source20:       iwlwifi-so-a0-gf4-a0-84.ucode
Source21:       iwlwifi-so-a0-gf4-a0-86.ucode
Source22:       iwlwifi-so-a0-gf4-a0-89.ucode
Source23:       iwlwifi-so-a0-gf4-a0.pnvm
Source24:       LICENCE.iwlwifi_firmware

%description
This package contains the Intel proprietary firmware files for the
Intel Wi-Fi 6E AX211 (160MHz) wireless adapter.

The AX211 is a Wi-Fi 6E (802.11ax) adapter supporting:
- 2.4 GHz, 5 GHz, and 6 GHz bands
- Up to 160 MHz channel bandwidth
- MU-MIMO and OFDMA
- Bluetooth 5.3

Hardware IDs supported:
- Intel(R) Wi-Fi 6E AX211 160MHz (PCI ID: 8086:51f0, 8086:51f1)
- Intel(R) Wi-Fi 6E AX211 (various subsystem IDs)

Kernel requirement: 5.14 or later with iwlwifi driver (CONFIG_IWLWIFI=m)

The firmware is loaded by the iwlwifi kernel module when the device is
detected. The driver will request firmware files matching the device's
hardware revision.

%prep
# Nothing to prepare - binary firmware files

%build
# Nothing to build - binary firmware files

%install
mkdir -p %{buildroot}%{firmware_dir}
mkdir -p %{buildroot}%{_datadir}/licenses/%{name}

# Install firmware files
install -m 644 %{SOURCE0} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE1} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE2} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE3} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE4} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE5} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE6} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE7} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE8} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE9} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE10} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE11} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE12} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE13} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE14} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE15} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE16} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE17} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE18} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE19} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE20} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE21} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE22} %{buildroot}%{firmware_dir}/
install -m 644 %{SOURCE23} %{buildroot}%{firmware_dir}/

# Install license
install -m 644 %{SOURCE24} %{buildroot}%{_datadir}/licenses/%{name}/

%files
%license %{_datadir}/licenses/%{name}/LICENCE.iwlwifi_firmware
%{firmware_dir}/iwlwifi-so-a0-gf-a0-72.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-73.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-74.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-77.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-78.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-79.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-81.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-83.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-84.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-86.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0-89.ucode
%{firmware_dir}/iwlwifi-so-a0-gf-a0.pnvm
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-72.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-73.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-74.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-77.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-78.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-79.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-81.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-83.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-84.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-86.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0-89.ucode
%{firmware_dir}/iwlwifi-so-a0-gf4-a0.pnvm

%post
# Reload udev rules to pick up new firmware
if [ -x /usr/bin/udevadm ]; then
    /usr/bin/udevadm control --reload-rules 2>/dev/null || true
fi
echo "Intel Wi-Fi 6E AX211 firmware installed."
echo "If the adapter is already present, reload the driver:"
echo "  modprobe -r iwlwifi && modprobe iwlwifi"

%changelog
* Tue Jan 28 2026 Photon OS <photonos@vmware.com> - 20260128-1
- Initial package for Intel Wi-Fi 6E AX211
- Firmware from linux-firmware git (main branch)
- Includes so-a0-gf-a0 and so-a0-gf4-a0 variants
- Firmware versions 72-89 for maximum compatibility
