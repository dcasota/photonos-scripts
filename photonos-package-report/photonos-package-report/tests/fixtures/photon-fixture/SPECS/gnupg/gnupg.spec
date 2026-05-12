Summary:       GnuPG with %{?kat_build:.kat} release token
Name:          gnupg
Version:       2.2.40
Release:       3%{?kat_build:.kat}%{?dist}
URL:           https://gnupg.org/
Source0:       https://gnupg.org/ftp/gcrypt/gnupg/gnupg-%{version}.tar.bz2
%define sha512 gnupg-2.2.40.tar.bz2=ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100ffeeddccbbaa9988776655443322110011
Group:         Applications/System

%description
GnuPG fixture covering %{?kat_build:.kat} stripping in Release.
