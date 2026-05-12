Summary:       Hello world example
Name:          hello
Version:       2.10
Release:       1%{?dist}
License:       GPL
URL:           https://www.gnu.org/software/hello/
Source0:       https://ftp.gnu.org/gnu/hello/hello-%{version}.tar.gz
%define sha1 hello-2.10.tar.gz=abcdef0123456789abcdef0123456789abcdef01
Group:         Applications/Text

%description
Trivial GNU hello fixture.
