Summary:       commit-test — define overrides global per PS L 341-343
Name:          commit-test
Version:       0.0.1
Release:       1%{?dist}
URL:           https://example.invalid/commit-test
Source0:       https://example.invalid/commit-test-%{version}.tar.gz
%global commit_id aaaa1111
%define commit_id bbbb2222
Group:         Misc

%description
PS L 341-343: global first, define overrides — expect commit_id=bbbb2222.
