Summary:       Linux kernel with %{?kernelsubrelease}
Name:          kernel
Version:       6.6.12
Release:       1.ph6%{?kernelsubrelease}%{?dist}
URL:           https://www.kernel.org
Source0:       https://www.kernel.org/pub/linux/kernel/v6.x/linux-%{version}.tar.xz
%define ncursessubversion 20221231
Group:         System Environment/Kernel

%description
Kernel fixture covering %{?kernelsubrelease} stripping.
