Summary:       rubygem-bar with gem_name override
Name:          rubygem-bar
Version:       1.2.3
Release:       1%{?dist}
URL:           https://rubygems.org/gems/bar
Source0:       https://rubygems.org/downloads/bar-%{version}.gem
%define gem_name BAR
%global gem_name bar
Group:         Development/Languages/Ruby

%description
Confirms %global gem_name overrides %define gem_name (PS L 295-297).
