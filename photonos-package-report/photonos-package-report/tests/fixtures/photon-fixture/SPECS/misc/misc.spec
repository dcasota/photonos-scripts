Summary:       misc fixture — covers all remaining %define capture branches
Name:          misc
Version:       4.5.6
Release:       2%{?dist}
URL:           https://example.invalid/misc
Source0:       https://example.invalid/misc-%{version}.tar.gz
%define byaccdate 20210808
%define libedit_release 50
%define libedit_version 20221030
%define cpan_name Misc::Bundle
%define xproto_ver 7.0.31
%define _url_src https://example.invalid/src
%define _repo_ver 9.9.9
%define extra_version rc1
%define main_version 4.5
%define upstreamversion 4.5.6-beta
%define subversion 6
Group:         Misc

%description
Covers byaccdate, libedit_release, libedit_version, cpan_name, xproto_ver,
_url_src, _repo_ver, extra_version, main_version, upstreamversion, subversion.
