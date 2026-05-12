# Photon OS URL Health Issues - branch 5.0

**Source file:** photonos-urlhealth-5.0_202605120200.prn

**Total packages analyzed:** 1113

**Total packages with issues:** 180

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 2 | URL substitution unfinished | 1 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 14 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 18 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 29 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 75 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 44 | Low-Medium |

---

## 2. URL Substitution Unfinished

| # | Spec | Name | Source0 Original | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | dhcp.spec | dhcp | `ftp://ftp.isc.org/isc/dhcp/${version}/%{name}-%{version}.tar.gz` | `` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |

---

## 3. Source URL Unreachable (UrlHealth=0)

| # | Spec | Name | Modified Source0 | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | abupdate.spec | abupdate | `abupdate` | Info: Source0 contains a VMware internal url address. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 2 | build-essential.spec | build-essential | `license.txt` | Info: Source0 contains a VMware internal url address. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 3 | cdrkit.spec | cdrkit | `http://gd.tuwien.ac.at/utils/schilling/cdrtoolscdrkit-1.1.11.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 4 | distrib-compat.spec | distrib-compat | `%{name}-%{version}.tar.bz2` | Info: Source0 contains a VMware internal url address. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 5 | filesystem.spec | filesystem | `clock` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 6 | finger.spec | finger | `ftp://ftp.uk.linux.org/pub/linux/Networking/netkit/bsd-finger-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 7 | gc.spec | gc | `http://www.hboehm.info/gc/gc_source/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 8 | hyper-v.spec | hyper-v | `%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 9 | photon-iso-config.spec | photon-iso-config | `%{name}-%{version}.tar.gz` | Info: Source0 contains a VMware internal url address. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 10 | python-daemon.spec | python-daemon | `https://pagure.io/python-daemon/archive/release/2.3.2/python-daemon-release/2.3.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 11 | python-ruamel-yaml.spec | python-ruamel-yaml | `https://files.pythonhosted.org/packages/ruamel.yaml-0.17.21.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 12 | repmgr18.spec | repmgr | `https://repmgr.org/download/%{srcname}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 13 | tcpdump.spec | tcpdump | `http://www.tcpdump.org/release/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 14 | wal2json18.spec | wal2json | `https://github.com/eulerto/wal2json/archive/refs/tags/wal2json-2.6.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | dtb-raspberrypi.spec | dtb-raspberrypi | Warning: dtb-raspberrypi.spec Source0 version 6.1.10.2023.02.28 is higher than detected latest version 1.20230405 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | gst-plugins-bad.spec | gst-plugins-bad | Warning: gst-plugins-bad.spec Source0 version 1.25.1 is higher than detected latest version 1.19.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | jsoncpp.spec | jsoncpp | Warning: jsoncpp.spec Source0 version 1.9.5 is higher than detected latest version 1.9.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.10.1alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 20240514 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | linux.spec | linux | Warning: linux.spec Source0 version 6.1.164-acvp} is higher than detected latest version 6.1.172 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.19 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 2.0 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | perl-Module-ScanDeps.spec | perl-Module-ScanDeps | Warning: perl-Module-ScanDeps.spec Source0 version 1.37 is higher than detected latest version 1.35 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | python-hatchling.spec | python-hatchling | Warning: python-hatchling.spec Source0 version 1.11.1 is higher than detected latest version 0.23.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | python-pycodestyle.spec | python-pycodestyle | Warning: python-pycodestyle.spec Source0 version 2.9.1 is higher than detected latest version 2.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | python-pytz-deprecation-shim.spec | python-pytz-deprecation-shim | Warning: python-pytz-deprecation-shim.spec Source0 version 0.1.0.post0 is higher than detected latest version 0.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | python-pyvim.spec | python-pyvim | Warning: python-pyvim.spec Source0 version 3.0.3 is higher than detected latest version 2.0.24 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 16 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 17 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 18 | xorg-fonts.spec | xorg-fonts | Warning: xorg-fonts.spec Source0 version 7.7 is higher than detected latest version 1.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | apache-maven.spec | apache-maven | `https://github.com/apache/maven/archive/refs/tags/maven-3.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | cscope.spec | cscope | `https://unlimited.dl.sourceforge.net/project/cscope/cscope/v15.9/cscope-15.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | dwarves.spec | dwarves | `http://fedorapeople.org/~acme/dwarves/dwarves-1.24.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | erlang.spec | erlang | `https://github.com/erlang/otp/archive/refs/tags/OTP-27.3.4.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | eventlog.spec | eventlog | `https://www.balabit.com/downloads/files/eventlog/0.2/eventlog_0.2.12.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | fakeroot.spec | fakeroot | `https://salsa.debian.org/clint/fakeroot/-/archive/debian/1.37.1.1/fakeroot-debian-1.37.1.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | gptfdisk.spec | gptfdisk | `https://netix.dl.sourceforge.net/project/gptfdisk/gptfdisk/1.0.9/gptfdisk-1.0.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | gstreamer-plugins-base.spec | gstreamer-plugins-base | `https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-1.25.1.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | iptables.spec | iptables | `https://www.netfilter.org/projects/iptables/files/iptables-1.8.9.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | lasso.spec | lasso | `https://dev.entrouvert.org/lasso/lasso-2.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | libbsd.spec | libbsd | `https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | libclc.spec | libclc | `https://github.com/llvm/llvm-project/releases/download/llvmorg-18.1.8/libclc-18.1.8.src.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | libdaemon.spec | libdaemon | `https://0pointer.de/lennart/projects/libdaemon/libdaemon-0.14.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | libevent.spec | libevent | `https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | libmnl.spec | libmnl | `https://www.netfilter.org/projects/libmnl/files/libmnl-1.0.5.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | libnetfilter_cthelper.spec | libnetfilter_cthelper | `https://www.netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-1.0.1.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | libnetfilter_cttimeout.spec | libnetfilter_cttimeout | `https://www.netfilter.org/projects/libnetfilter_cttimeout/files/libnetfilter_cttimeout-1.0.1.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | libnetfilter_queue.spec | libnetfilter_queue | `https://www.netfilter.org/projects/libnetfilter_queue/files/libnetfilter_queue-1.0.5.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | libnvme.spec | libnvme | `https://github.com/linux-nvme/libnvme/archive/refs/tags/v1.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | lzo.spec | lzo | `https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | netkit-telnet.spec | netkit-telnet | `https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/0.17/netkit-telnet-debian-0.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | nftables.spec | nftables | `https://www.netfilter.org/projects/nftables/files/nftables-1.0.6.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | nmap.spec | nmap | `https://nmap.org/dist/nmap-7.93.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | python-docutils.spec | python-docutils | `https://netix.dl.sourceforge.net/project/docutils/docutils/0.19/docutils-0.19.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | python-incremental.spec | python-incremental | `https://github.com/twisted/incremental/archive/refs/tags/incremental-24.7.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | xorg-applications.spec | xorg-applications | `https://www.x.org/archive/individual/util/bdftopcf-7.7.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | ModemManager.spec | ModemManager | 1.24.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | clang.spec | clang | 22.1.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | dbus-python.spec | dbus-python | 1.4.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | expat.spec | expat | 20000512 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | fontconfig.spec | fontconfig | 2.17.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | govmomi.spec | govmomi | 0.54.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | icu.spec | icu | 78.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | kbd.spec | kbd | 2.9.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | kexec-tools.spec | kexec-tools | 20080324 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | libXScrnSaver.spec | libXScrnSaver | 1.2.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | libXau.spec | libXau | 1.0.12 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | libXcomposite.spec | libXcomposite | 0.4.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | libXdamage.spec | libXdamage | 1.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | libXdmcp.spec | libXdmcp | 1.1.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | libXext.spec | libXext | 1.3.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | libXfixes.spec | libXfixes | 6.0.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | libXfont2.spec | libXfont2 | 2.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | libXi.spec | libXi | 1.8.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | libXrandr.spec | libXrandr | 1.5.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | libXrender.spec | libXrender | 0.9.12 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | libXt.spec | libXt | 1.3.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | libXtst.spec | libXtst | 1.2.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | libcap.spec | libcap | 20071031 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | libdrm.spec | libdrm | 200-0-1-20020822 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | libfontenc.spec | libfontenc | 1.1.9 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | libpciaccess.spec | libpciaccess | 0.19 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | libselinux.spec | libselinux | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | libsemanage.spec | libsemanage | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | lldb.spec | lldb | 22.1.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | llvm.spec | llvm | 22.1.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 36 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 37 | lz4.spec | lz4 | 131 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 38 | mesa.spec | mesa | 20090313 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 39 | mm-common.spec | mm-common | 1.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 40 | mozjs.spec | mozjs | 150.0.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 41 | ncurses.spec | ncurses | 6.6.20260509 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 42 | ninja-build.spec | ninja-build | 120715 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 43 | nss.spec | nss | 3.123.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 44 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 45 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 46 | perftest.spec | perftest | 26.01.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 47 | perl-IPC-Run.spec | perl-IPC-Run | 20260402 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 48 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 49 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 50 | pgaudit13.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 51 | pgaudit14.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 52 | pgaudit15.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 53 | pgaudit16.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 54 | pgaudit17.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 55 | policycoreutils.spec | policycoreutils | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 56 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 57 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 58 | pth.spec | pth | 23.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 59 | python-configparser.spec | python-configparser | 7.2.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 60 | python-filelock.spec | python-filelock | 3.29.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 61 | python-google-auth.spec | python-google-auth | 1946 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 62 | python-more-itertools.spec | python-more-itertools | 11.0.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 63 | python-pyparsing.spec | python-pyparsing | 3.3.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 64 | qemu.spec | qemu | /9.1.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 65 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 66 | selinux-python.spec | selinux-python | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 67 | semodule-utils.spec | semodule-utils | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 68 | spirv-headers.spec | spirv-headers | 1.5.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 69 | spirv-tools.spec | spirv-tools | 2026.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 70 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 71 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 72 | util-macros.spec | util-macros | 1.20.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 73 | vulkan-tools.spec | vulkan-tools | 1.4.351 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 74 | xtrans.spec | xtrans | 1.6.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 75 | xxhash.spec | xxhash | 42 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | Linux-PAM.spec | Linux-PAM | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 2 | ant-contrib.spec | ant-contrib | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 3 | apr-util.spec | apr-util | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 4 | aufs-util.spec | aufs-util | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 5 | basic.spec | basic | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 6 | bluez-tools.spec | bluez-tools | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 7 | ca-certificates.spec | ca-certificates | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 8 | cloud-network-setup.spec | cloud-network-setup | 200 | 0.2.3 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 9 | containerd.spec | containerd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 10 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 11 | cups.spec | cups | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 12 | cve-check-tool.spec | cve-check-tool | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 13 | dbus.spec | dbus | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 14 | docker.spec | docker | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 15 | gawk.spec | gawk | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 16 | grub2-theme.spec | grub2-theme | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 17 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 18 | http-parser.spec | http-parser | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 19 | initramfs.spec | initramfs | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 20 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 21 | libcap.spec | libcap | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 22 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 23 | linuxptp.spec | linuxptp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 24 | minimal.spec | minimal | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 25 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 26 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 27 | pgbackrest.spec | pgbackrest | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 28 | photon-release.spec | photon-release | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 29 | photon-repos.spec | photon-repos | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 30 | photon-upgrade.spec | photon-upgrade | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 31 | python-argparse.spec | python-argparse | 200 | 140 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 32 | python-atomicwrites.spec | python-atomicwrites | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 33 | python-backports.ssl_match_hostname.spec | python-backports.ssl_match_hostname | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 34 | python-lockfile.spec | python-lockfile | 200 |  | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 35 | python-psycopg2.spec | python-psycopg2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 36 | python-pyjsparser.spec | python-pyjsparser | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 37 | python-terminaltables.spec | python-terminaltables | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 38 | rpm.spec | rpm | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 39 | rubygem-async-io.spec | rubygem-async-io | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 40 | runc.spec | runc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 41 | shim-signed.spec | shim-signed | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 42 | stalld.spec | stalld | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 43 | stig-hardening.spec | stig-hardening | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 44 | strace.spec | strace | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |

