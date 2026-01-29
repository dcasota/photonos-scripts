Summary:        Linux wireless configuration utility
Name:           iw
Version:        6.9
Release:        1.ph5
License:        ISC
Group:          System Environment/Base
URL:            https://wireless.wiki.kernel.org/en/users/documentation/iw
Vendor:         VMware, Inc.
Distribution:   Photon

Source0:        https://git.kernel.org/pub/scm/linux/kernel/git/jberg/iw.git/snapshot/iw-%{version}.tar.gz

BuildRequires:  libnl-devel
BuildRequires:  pkg-config
BuildRequires:  gcc
BuildRequires:  make

Requires:       libnl

%description
iw is a new nl80211 based CLI configuration utility for wireless devices.
It supports all new drivers that have been added to the kernel since
wireless extensions became deprecated (around 2007).

iw can be used to:
- List all wireless devices and their capabilities
- Set up wireless interfaces (managed, monitor, ad-hoc, mesh)
- Scan for available networks
- Connect to networks
- Set regulatory domain
- Show link status and signal strength
- Configure TX power and bitrates

%prep
%setup -q -n iw-%{version}

%build
make %{?_smp_mflags} V=1

%install
make DESTDIR=%{buildroot} PREFIX=/usr SBINDIR=/usr/sbin install

%files
%defattr(-,root,root)
%license COPYING
%doc README
/usr/sbin/iw
%{_mandir}/man8/iw.8*

%changelog
* Thu Jan 30 2026 Photon MOK Build <mok@photon.local> 6.9-1
- Initial package for Photon OS 5.0 MOK Secure Boot
- Provides wireless configuration utility for regulatory domain management
