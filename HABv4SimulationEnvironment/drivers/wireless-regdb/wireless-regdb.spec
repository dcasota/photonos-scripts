Summary:        Linux wireless regulatory database
Name:           wireless-regdb
Version:        2024.01.23
Release:        1.ph5
License:        ISC
Group:          System Environment/Base
URL:            https://wireless.wiki.kernel.org/en/developers/regulatory/wireless-regdb
Vendor:         VMware, Inc.
Distribution:   Photon

Source0:        https://git.kernel.org/pub/scm/linux/kernel/git/sforshee/wireless-regdb.git/snapshot/wireless-regdb-%{version}.tar.gz

BuildArch:      noarch

%description
The wireless-regdb package contains the regulatory database used by the
Linux kernel wireless subsystem (cfg80211) to determine the allowed
radio frequencies and transmission power levels for wireless devices
in different countries and regions.

This database is essential for WiFi regulatory compliance and enables
proper channel and power settings based on geographic location.

%prep
%setup -q -n wireless-regdb-%{version}

%build
# Pre-built binary database - no compilation needed

%install
mkdir -p %{buildroot}/lib/firmware
install -m 644 regulatory.db %{buildroot}/lib/firmware/
install -m 644 regulatory.db.p7s %{buildroot}/lib/firmware/

%files
%defattr(-,root,root)
%license LICENSE
/lib/firmware/regulatory.db
/lib/firmware/regulatory.db.p7s

%changelog
* Thu Jan 30 2026 Photon MOK Build <mok@photon.local> 2024.01.23-1
- Initial package for Photon OS 5.0 MOK Secure Boot
- Provides regulatory database for WiFi 80MHz/DFS channel support
