#
# tdnf-bad-pre spec file
#
Summary:    basic install test file.
Name:       tdnf-bad-pre
Version:    1.0.0
Release:    1
Vendor:     VMware, Inc.
Distribution:   Photon
License:    VMware
Url:        http://www.vmware.com
Group:      Applications/tdnftest

%description
Part of tdnf test spec. Test bad install scripts.

%prep

%build

%install

%pre
# fail intentionally
%{_bindir}/false

%files

%changelog
*   Fri Apr 2 2021 Oliver Kurth <okurth@vmware.com> 1.0.0-1
    initial package to test '--setopt=tsflags=noscripts'
