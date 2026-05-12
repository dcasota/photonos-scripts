Summary:       python-foo with srcname global override
Name:          python-foo
Version:       0.9
Release:       2%{?dist}
URL:           https://example.invalid/foo
Source0:       https://example.invalid/foo/foo-%{version}.tar.gz
%define srcname Foo
%global srcname foo
Group:         Development/Languages/Python

%description
Confirms %global srcname overrides %define srcname (PS L 292-293).
