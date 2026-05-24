# Photon OS URL Health Issues - branch main

**Source file:** photonos-urlhealth-main_202605241942.prn

**Total packages analyzed:** 1621

**Total packages with issues:** 676

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 2 | High |
| 2 | URL substitution unfinished | 3 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 23 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 18 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 34 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 74 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 578 | Low-Medium |

---

## 1. Source URL Blank / Macro Unresolved (UrlHealth=blank)

The Source0 URL contains unexpanded RPM macros or is empty.

| # | Spec | Name | Source0 Original | Fix Suggestion |
|---|---|---|---|---|
| 1 | chromium.spec | chromium | `https://github.com/chromium/chromium/archive/%{name}-%{version}.tar.xz` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 2 | raspberrypi-firmware.spec | raspberrypi-firmware | `%{name}-%{version}.tar.gz` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |

---

## 2. URL Substitution Unfinished

| # | Spec | Name | Source0 Original | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | alternatives.spec | alternatives | `https://github.com/fedora-sysv/chkconfig/archive/refs/tags/%{src_name}-%{version` | `https://github.com/fedora-sysv/chkconfig/archive/refs/tags/%{src_name}-1.32.tar.` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |
| 2 | python3-msal.spec | python3-msal | `https://github.com/AzureAD/%{full_name}/archive/%{version}/%{full_name}-%{versio` | `` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |
| 3 | squid.spec | squid | `https://github.com/squid-cache/squid/archive/refs/tags/%{upstream_name}_%{upstre` | `https://github.com/squid-cache/squid/archive/refs/tags/%{upstream_name}_%{upstre` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |

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
| 7 | hyper-v.spec | hyper-v | `%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 8 | linux.spec | linux | `http://www.kernel.org/pub/linux/kernel/v6.x/linux-%{version}.tar.xz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 9 | photon-iso-config.spec | photon-iso-config | `%{name}-%{version}.tar.gz` | Info: Source0 contains a VMware internal url address. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 10 | procps-ng.spec | procps-ng | `https://sourceforge.net/projects/procps-ng/files/Production/procps-4.0.6.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 11 | python-daemon.spec | python-daemon | `https://pagure.io/python-daemon/archive/release/2.3.2/python-daemon-release/2.3.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 12 | python-installer.spec | python-installer | `https://github.com/pypa/installer/archive/refs/tags/installer-0.7.0.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 13 | python-ruamel-yaml.spec | python-ruamel-yaml | `https://files.pythonhosted.org/packages/ruamel.yaml-0.19.1.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 14 | python3-Pygments.spec | python3-Pygments | `https://github.com/pygments/pygments/archive/refs/tags/pygments-2.19.2.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 15 | python3-iniconfig.spec | python3-iniconfig | `https://github.com/RonnyPfannschmidt/iniconfig/archive/refs/tags/iniconfig-2.3.0.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 16 | python3-iniparse.spec | python3-iniparse | `http://iniparse.googlecode.com/files/iniparse-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 17 | python3-legacy-cgi.spec | python3-legacy-cgi | `legacy_cgi-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 18 | python3-markupsafe.spec | python3-markupsafe | `https://github.com/pallets/markupsafe/archive/refs/tags/markupsafe-3.0.3.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 19 | python3-roman-numerals.spec | python3-roman-numerals | `roman_numerals-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 20 | python3-trove-classifiers.spec | python3-trove-classifiers | `https://github.com/pypa/trove-classifiers/archive/refs/tags/trove-classifiers-2026.1.14.14.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 21 | python3-wheel.spec | python3-wheel | `https://github.com/pypa/wheel/archive/refs/tags/wheel-0.46.3.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 22 | repmgr18.spec | repmgr | `https://repmgr.org/download/%{srcname}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 23 | wal2json18.spec | wal2json | `https://github.com/eulerto/wal2json/archive/refs/tags/wal2json-2.6.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | apparmor.spec | apparmor | Warning: apparmor.spec Source0 version 4.1.6 is higher than detected latest version 4.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | dracut.spec | dracut | Warning: dracut.spec Source0 version 109 is higher than detected latest version 059 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | gst-plugins-bad.spec | gst-plugins-bad | Warning: gst-plugins-bad.spec Source0 version 1.25.1 is higher than detected latest version 1.19.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | ibmtpm.spec | ibmtpm | Warning: ibmtpm.spec Source0 version 20240802.183 is higher than detected latest version 2024-08-02 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.11alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 20240514 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.19 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | mdadm.spec | mdadm | Warning: mdadm.spec Source0 version 4.6 is higher than detected latest version 4.4 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 2.0 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | perl-Module-ScanDeps.spec | perl-Module-ScanDeps | Warning: perl-Module-ScanDeps.spec Source0 version 1.37 is higher than detected latest version 1.35 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | python-pycodestyle.spec | python-pycodestyle | Warning: python-pycodestyle.spec Source0 version 2.9.1 is higher than detected latest version 2.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | python-pytz-deprecation-shim.spec | python-pytz-deprecation-shim | Warning: python-pytz-deprecation-shim.spec Source0 version 0.1.0.post0 is higher than detected latest version 0.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | python-pyvim.spec | python-pyvim | Warning: python-pyvim.spec Source0 version 3.0.3 is higher than detected latest version 2.0.24 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 16 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 17 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 18 | systemd.spec | systemd | Warning: systemd.spec Source0 version 257.13 is higher than detected latest version 256 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | apache-maven.spec | apache-maven | `https://github.com/apache/maven/archive/refs/tags/maven-3.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | cscope.spec | cscope | `https://unlimited.dl.sourceforge.net/project/cscope/cscope/v15.9/cscope-15.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | dwarves.spec | dwarves | `http://fedorapeople.org/~acme/dwarves/dwarves-1.24.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | erlang.spec | erlang | `https://github.com/erlang/otp/archive/refs/tags/OTP-27.3.4.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | fakeroot.spec | fakeroot | `https://salsa.debian.org/clint/fakeroot/-/archive/debian/1.37.1.1/fakeroot-debian-1.37.1.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | gptfdisk.spec | gptfdisk | `https://netix.dl.sourceforge.net/project/gptfdisk/gptfdisk/1.0.9/gptfdisk-1.0.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | gstreamer-plugins-base.spec | gstreamer-plugins-base | `https://gstreamer.freedesktop.org/src/gst-plugins-base/gst-plugins-base-1.25.1.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | iptables.spec | iptables | `https://www.netfilter.org/projects/iptables/files/iptables-1.8.13.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | lasso.spec | lasso | `https://dev.entrouvert.org/lasso/lasso-2.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | libbsd.spec | libbsd | `https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | libdisplay-info.spec | libdisplay-info | `https://gitlab.freedesktop.org/emersion/libdisplay-info/-/archive/0.3.0/libdisplay-info-0.3.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | libevent.spec | libevent | `https://github.com/libevent/libevent/releases/download/release-2.1.12-stable/libevent-2.1.12-stable.` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | libmnl.spec | libmnl | `https://www.netfilter.org/projects/libmnl/files/libmnl-1.0.5.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | libnetfilter_cthelper.spec | libnetfilter_cthelper | `https://www.netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-1.0.1.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | libnetfilter_cttimeout.spec | libnetfilter_cttimeout | `https://www.netfilter.org/projects/libnetfilter_cttimeout/files/libnetfilter_cttimeout-1.0.1.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | libnetfilter_queue.spec | libnetfilter_queue | `https://www.netfilter.org/projects/libnetfilter_queue/files/libnetfilter_queue-1.0.5.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | linux-api-headers.spec | linux-api-headers | `http://www.kernel.org/pub/linux/kernel/v6.x/linux-6.1.79.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | linux-esx.spec | linux | `http://www.kernel.org/pub/linux/kernel/v6.x/linux-6.12.87.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | nftables.spec | nftables | `https://www.netfilter.org/projects/nftables/files/nftables-1.1.6.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | nmap.spec | nmap | `https://nmap.org/dist/nmap-7.93.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | openjdk25.spec | openjdk | `https://github.com/openjdk/jdk25u/archive/refs/tags/jdk-25.0.2-ga.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | python-calver.spec | python-calver | `https://files.pythonhosted.org/packages/source/c/calver/calver-2025.10.20.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | python-docutils.spec | python-docutils | `https://netix.dl.sourceforge.net/project/docutils/docutils/0.19/docutils-0.19.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | python-incremental.spec | python-incremental | `https://github.com/twisted/incremental/archive/refs/tags/incremental-24.7.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | python-meson-python.spec | python-meson-python | `https://files.pythonhosted.org/packages/32/98/7fe5d1bf741c03c6eea04b6245737dbd79657d4f9200e82fcbb4cc` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | python-py.spec | python-py | `https://github.com/pytest-dev/py/archive/refs/tags/1.11.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | python-pyproject-metadata.spec | python-pyproject-metadata | `https://files.pythonhosted.org/packages/83/fa/8bf4fa41adfebd95dce360afe3f5fca243a17932089d3d5486e95c` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | python-versioneer.spec | python-versioneer | `https://files.pythonhosted.org/packages/32/d7/854e45d2b03e1a8ee2aa6429dd396d002ce71e5d88b77551b2fb24` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | python3-hatchling.spec | python3-hatchling | `https://github.com/pypa/hatch/releases/download/hatchling-v1.29.0/hatchling-1.29.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 33 | repmgr17.spec | repmgr | `https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v5.5.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 34 | spirv-headers.spec | spirv-headers | `https://github.com/KhronosGroup/SPIRV-Headers/archive/refs/tags/vulkan-sdk-1.4.341.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | dtb-raspberrypi.spec | dtb-raspberrypi | 20250916 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | erofs-utils.spec | erofs-utils | 20190826 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | expat.spec | expat | 20000512 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | fontconfig.spec | fontconfig | 2.18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | govmomi.spec | govmomi | 0.54.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | icu.spec | icu | 78.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | kbd.spec | kbd | 2.9.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | kexec-tools.spec | kexec-tools | 20080324 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | libXScrnSaver.spec | libXScrnSaver | 1.2.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | libXau.spec | libXau | 1.0.12 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | libXcomposite.spec | libXcomposite | 0.4.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | libXdamage.spec | libXdamage | 1.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | libXdmcp.spec | libXdmcp | 1.1.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | libXext.spec | libXext | 1.3.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | libXfixes.spec | libXfixes | 6.0.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | libXfont2.spec | libXfont2 | 2.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | libXi.spec | libXi | 1.8.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | libXrandr.spec | libXrandr | 1.5.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | libXrender.spec | libXrender | 0.9.12 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | libXt.spec | libXt | 1.3.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | libXtst.spec | libXtst | 1.2.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | libcap.spec | libcap | 20071031 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | libdrm.spec | libdrm | 200-0-1-20020822 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | libfontenc.spec | libfontenc | 1.1.9 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | libpciaccess.spec | libpciaccess | 0.19 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | libselinux.spec | libselinux | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | libsemanage.spec | libsemanage | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | libslirp.spec | libslirp | 2.5.20200525 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | lz4.spec | lz4 | 131 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 36 | mesa.spec | mesa | 20090313 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 37 | mm-common.spec | mm-common | 1.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 38 | mozjs.spec | mozjs | 151.0.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 39 | ncurses.spec | ncurses | 6.6.20260523 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 40 | ninja-build.spec | ninja-build | 120715 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 41 | nss.spec | nss | 3.124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 42 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 43 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 44 | perftest.spec | perftest | 26.01.5 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 45 | perl-IPC-Run.spec | perl-IPC-Run | 20260402 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 46 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 47 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 48 | pgaudit13.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 49 | pgaudit14.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 50 | pgaudit15.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 51 | pgaudit16.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 52 | pgaudit17.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 53 | policycoreutils.spec | policycoreutils | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 54 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 55 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 56 | python-configparser.spec | python-configparser | 7.2.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 57 | python-filelock.spec | python-filelock | 3.29.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 58 | python-google-auth.spec | python-google-auth | 1946 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 59 | python-more-itertools.spec | python-more-itertools | 11.1.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 60 | python-pyparsing.spec | python-pyparsing | 3.3.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 61 | python-vcs-versioning.spec | python-vcs-versioning | 9.2.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 62 | qemu.spec | qemu | /9.1.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 63 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 64 | selinux-python.spec | selinux-python | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 65 | semodule-utils.spec | semodule-utils | 20200710 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 66 | spirv-tools.spec | spirv-tools | 2026.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 67 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 68 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 69 | util-macros.spec | util-macros | 1.20.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 70 | vulkan-tools.spec | vulkan-tools | 1.4.352 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 71 | wayland-protocols.spec | wayland-protocols | 1.48 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 72 | wireshark.spec | wireshark | 4.6.16 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 73 | xtrans.spec | xtrans | 1.6.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 74 | xxhash.spec | xxhash | 42 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | GConf.spec | GConf | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 2 | ImageMagick.spec | ImageMagick | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 3 | Linux-PAM.spec | Linux-PAM | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 4 | ModemManager.spec | ModemManager | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 5 | WALinuxAgent.spec | WALinuxAgent | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 6 | ansible-community-general.spec | ansible-community-general | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 7 | ansible-posix.spec | ansible-posix | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 8 | ansible.spec | ansible | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 9 | ant-contrib.spec | ant-contrib | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 10 | apparmor.spec | apparmor | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 11 | apr-util.spec | apr-util | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 12 | asciidoc3.spec | asciidoc3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 13 | audit.spec | audit | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 14 | aufs-util.spec | aufs-util | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 15 | bash-completion.spec | bash-completion | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 16 | bash.spec | bash | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 17 | basic.spec | basic | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 18 | bazel.spec | bazel | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 19 | bcc.spec | bcc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 20 | bluez-tools.spec | bluez-tools | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 21 | bluez.spec | bluez | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 22 | bpftrace.spec | bpftrace | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 23 | bridge-utils.spec | bridge-utils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 24 | btrfs-progs.spec | btrfs-progs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 25 | bubblewrap.spec | bubblewrap | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 26 | c-ares.spec | c-ares | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 27 | ca-certificates.spec | ca-certificates | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 28 | calico-bgp-daemon.spec | calico-bgp-daemon | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 29 | checkpolicy.spec | checkpolicy | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 30 | chkconfig.spec | chkconfig | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 31 | clang.spec | clang | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 32 | cloud-init.spec | cloud-init | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 33 | cloud-network-setup.spec | cloud-network-setup | 200 | 0.2.3 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 34 | containerd.spec | containerd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 35 | cppunit.spec | cppunit | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 36 | cracklib.spec | cracklib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 37 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 38 | createrepo_c.spec | createrepo_c | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 39 | createrepo_c.spec | createrepo_c | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 40 | crun.spec | crun | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 41 | ctags.spec | ctags | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 42 | cve-check-tool.spec | cve-check-tool | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 43 | cython3.spec | cython3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 44 | dbus-broker.spec | dbus-broker | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 45 | dbus-python.spec | dbus-python | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 46 | dbus.spec | dbus | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 47 | dhcp.spec | dhcp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 48 | distcc.spec | distcc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 49 | docker-buildx.spec | docker-buildx | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 50 | docker-py.spec | docker-py | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 51 | docker-pycreds.spec | docker-pycreds | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 52 | docker.spec | docker | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 53 | dool.spec | dool | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 54 | dotnet-runtime.spec | dotnet-runtime | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 55 | dotnet-sdk.spec | dotnet-sdk | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 56 | doxygen.spec | doxygen | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 57 | dracut.spec | dracut | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 58 | drpm.spec | drpm | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 59 | ethtool.spec | ethtool | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 60 | eventlog.spec | eventlog | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 61 | fail2ban.spec | fail2ban | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 62 | falco.spec | falco | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 63 | findutils.spec | findutils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 64 | fio.spec | fio | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 65 | fontconfig.spec | fontconfig | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 66 | frr.spec | frr | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 67 | fsarchiver.spec | fsarchiver | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 68 | gawk.spec | gawk | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 69 | gcc.spec | gcc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 70 | gdb.spec | gdb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 71 | geoip-api-c.spec | geoip-api-c | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 72 | git.spec | git | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 73 | glib.spec | glib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 74 | glibc.spec | glibc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 75 | glibmm.spec | glibmm | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 76 | glslang.spec | glslang | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 77 | go.spec | go | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 78 | gobgp.spec | gobgp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 79 | gobject-introspection.spec | gobject-introspection | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 80 | gpsd.spec | gpsd | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 81 | grub2-theme.spec | grub2-theme | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 82 | gstreamer.spec | gstreamer | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 83 | gtk-doc.spec | gtk-doc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 84 | harfbuzz.spec | harfbuzz | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 85 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 86 | hiredis.spec | hiredis | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 87 | http-parser.spec | http-parser | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 88 | hyperscan.spec | hyperscan | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 89 | ibmtpm.spec | ibmtpm | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 90 | icu.spec | icu | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 91 | initramfs.spec | initramfs | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 92 | initscripts.spec | initscripts | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 93 | inotify-tools.spec | inotify-tools | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 94 | iotop.spec | iotop | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 95 | iproute2.spec | iproute2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 96 | iptables.spec | iptables | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 97 | iputils.spec | iputils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 98 | itstool.spec | itstool | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 99 | jc.spec | jc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 100 | json-glib.spec | json-glib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 101 | jsoncpp.spec | jsoncpp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 102 | kafka.spec | kafka | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 103 | kubernetes-dashboard.spec | kubernetes-dashboard | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 104 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 105 | lasso.spec | lasso | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 106 | libbpf.spec | libbpf | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 107 | libcap-ng.spec | libcap-ng | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 108 | libcap.spec | libcap | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 109 | libclc.spec | libclc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 110 | libdaemon.spec | libdaemon | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 111 | libdnet.spec | libdnet | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 112 | libldb.spec | libldb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 113 | libmbim.spec | libmbim | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 114 | libmodulemd.spec | libmodulemd | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 115 | libmspack.spec | libmspack | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 116 | libnetfilter_conntrack.spec | libnetfilter_conntrack | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 117 | libnftnl.spec | libnftnl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 118 | libnvme.spec | libnvme | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 119 | libpsl.spec | libpsl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 120 | libpwquality.spec | libpwquality | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 121 | librepo.spec | librepo | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 122 | libselinux-python3.spec | libselinux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 123 | libselinux.spec | libselinux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 124 | libsemanage.spec | libsemanage | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 125 | libsepol.spec | libsepol | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 126 | libsolv.spec | libsolv | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 127 | libsoup.spec | libsoup | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 128 | libssh2.spec | libssh2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 129 | libtalloc.spec | libtalloc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 130 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 131 | libtdb.spec | libtdb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 132 | libteam.spec | libteam | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 133 | libtevent.spec | libtevent | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 134 | libtraceevent.spec | libtraceevent | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 135 | libtracefs.spec | libtracefs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 136 | libvirt.spec | libvirt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 137 | libxcb.spec | libxcb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 138 | libxcrypt.spec | libxcrypt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 139 | libxml2.spec | libxml2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 140 | lighttpd.spec | lighttpd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 141 | linux-esx.spec | linux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 142 | linux-rt.spec | linux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 143 | linux.spec | linux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 144 | linuxptp.spec | linuxptp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 145 | lldb.spec | lldb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 146 | llvm.spec | llvm | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 147 | lttng-tools.spec | lttng-tools | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 148 | lttng-ust.spec | lttng-ust | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 149 | lvm2.spec | lvm2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 150 | lxcfs.spec | lxcfs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 151 | lzo.spec | lzo | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 152 | mdadm.spec | mdadm | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 153 | mercurial.spec | mercurial | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 154 | mesa.spec | mesa | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 155 | meson.spec | meson | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 156 | minimal.spec | minimal | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 157 | minimal.spec | minimal | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 158 | mkinitcpio.spec | mkinitcpio | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 159 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 160 | mozjs.spec | mozjs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 161 | msr-tools.spec | msr-tools | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 162 | net-snmp.spec | net-snmp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 163 | net-tools.spec | net-tools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 164 | netkit-telnet.spec | netkit-telnet | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 165 | nfs-utils.spec | nfs-utils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 166 | nftables.spec | nftables | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 167 | nginx.spec | nginx | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 168 | nicstat.spec | nicstat | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 169 | ninja-build.spec | ninja-build | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 170 | nodejs.spec | nodejs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 171 | ntp.spec | ntp | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 172 | ntpsec.spec | ntpsec | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 173 | ntpsec.spec | ntpsec | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 174 | nvme-cli.spec | nvme-cli | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 175 | openipmi.spec | openipmi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 176 | openscap.spec | openscap | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 177 | openssh.spec | openssh | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 178 | openssl-fips-provider.spec | openssl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 179 | openssl.spec | openssl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 180 | openvswitch.spec | openvswitch | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 181 | ostree.spec | ostree | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 182 | pam_tacplus.spec | pam_tacplus | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 183 | pandoc.spec | pandoc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 184 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 185 | pgbackrest.spec | pgbackrest | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 186 | photon-os-installer.spec | photon-os-installer | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 187 | photon-release.spec | photon-release | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 188 | photon-repos.spec | photon-repos | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 189 | photon-upgrade.spec | photon-upgrade | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 190 | podman.spec | podman | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 191 | policycoreutils.spec | policycoreutils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 192 | postgresql10.spec | postgresql | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 193 | postgresql13.spec | postgresql | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 194 | postgresql14.spec | postgresql | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 195 | postgresql15.spec | postgresql | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 196 | postgresql16.spec | postgresql | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 197 | postgresql17.spec | postgresql | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 198 | powershell.spec | powershell | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 199 | procps-ng.spec | procps-ng | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 200 | protobuf.spec | protobuf | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 201 | pth.spec | pth | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 202 | pycurl.spec | pycurl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 203 | python-CacheControl.spec | python-CacheControl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 204 | python-ConcurrentLogHandler.spec | python-ConcurrentLogHandler | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 205 | python-Js2Py.spec | python-Js2Py | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 206 | python-M2Crypto.spec | python-M2Crypto | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 207 | python-PyHamcrest.spec | python-PyHamcrest | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 208 | python-PyJWT.spec | python-PyJWT | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 209 | python-PyNaCl.spec | python-PyNaCl | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 210 | python-PyYAML.spec | python-PyYAML | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 211 | python-Pygments.spec | python-Pygments | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 212 | python-Twisted.spec | python-Twisted | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 213 | python-alabaster.spec | python-alabaster | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 214 | python-altgraph.spec | python-altgraph | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 215 | python-appdirs.spec | python-appdirs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 216 | python-argparse.spec | python-argparse | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 217 | python-asn1crypto.spec | python-asn1crypto | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 218 | python-atomicwrites.spec | python-atomicwrites | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 219 | python-attrs.spec | python-attrs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 220 | python-automat.spec | python-automat | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 221 | python-autopep8.spec | python-autopep8 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 222 | python-babel.spec | python-babel | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 223 | python-backports.ssl_match_hostname.spec | python-backports.ssl_match_hostname | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 224 | python-backports.ssl_match_hostname.spec | python-backports.ssl_match_hostname | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 225 | python-backports_abc.spec | python-backports_abc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 226 | python-bcrypt.spec | python-bcrypt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 227 | python-binary.spec | python-binary | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 228 | python-boto.spec | python-boto | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 229 | python-boto3.spec | python-boto3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 230 | python-botocore.spec | python-botocore | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 231 | python-cachetools.spec | python-cachetools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 232 | python-cassandra-driver.spec | python-cassandra-driver | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 233 | python-certifi.spec | python-certifi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 234 | python-cffi.spec | python-cffi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 235 | python-chardet.spec | python-chardet | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 236 | python-charset-normalizer.spec | python-charset-normalizer | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 237 | python-click.spec | python-click | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 238 | python-configobj.spec | python-configobj | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 239 | python-configparser.spec | python-configparser | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 240 | python-constantly.spec | python-constantly | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 241 | python-coverage.spec | python-coverage | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 242 | python-cqlsh.spec | python-cqlsh | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 243 | python-cryptography.spec | python-cryptography | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 244 | python-daemon.spec | python-daemon | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 245 | python-dateutil.spec | python-dateutil | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 246 | python-decorator.spec | python-decorator | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 247 | python-deepmerge.spec | python-deepmerge | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 248 | python-defusedxml.spec | python-defusedxml | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 249 | python-distlib.spec | python-distlib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 250 | python-distro.spec | python-distro | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 251 | python-dnspython.spec | python-dnspython | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 252 | python-docopt.spec | python-docopt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 253 | python-docutils.spec | python-docutils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 254 | python-ecdsa.spec | python-ecdsa | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 255 | python-email-validator.spec | python-email-validator | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 256 | python-etcd.spec | python-etcd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 257 | python-ethtool.spec | python-ethtool | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 258 | python-filelock.spec | python-filelock | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 259 | python-flit-core.spec | python-flit-core | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 260 | python-fuse.spec | python-fuse | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 261 | python-geomet.spec | python-geomet | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 262 | python-gevent.spec | python-gevent | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 263 | python-google-auth.spec | python-google-auth | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 264 | python-graphviz.spec | python-graphviz | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 265 | python-greenlet.spec | python-greenlet | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 266 | python-hatch-fancy-pypi-readme.spec | python-hatch-fancy-pypi-readme | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 267 | python-hatch-vcs.spec | python-hatch-vcs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 268 | python-hatchling.spec | python-hatchling | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 269 | python-hyperlink.spec | python-hyperlink | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 270 | python-hypothesis.spec | python-hypothesis | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 271 | python-idna.spec | python-idna | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 272 | python-imagesize.spec | python-imagesize | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 273 | python-importlib-metadata.spec | python-importlib-metadata | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 274 | python-incremental.spec | python-incremental | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 275 | python-iniconfig.spec | python-iniconfig | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 276 | python-iniparse.spec | python-iniparse | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 277 | python-ipaddress.spec | python-ipaddress | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 278 | python-jinja2.spec | python-jinja2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 279 | python-jmespath.spec | python-jmespath | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 280 | python-jsonpatch.spec | python-jsonpatch | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 281 | python-jsonpointer.spec | python-jsonpointer | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 282 | python-jsonschema.spec | python-jsonschema | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 283 | python-kubernetes.spec | python-kubernetes | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 284 | python-linux-procfs.spec | python-linux-procfs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 285 | python-lockfile.spec | python-lockfile | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 286 | python-lockfile.spec | python-lockfile | 200 |  | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 287 | python-looseversion.spec | python-looseversion | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 288 | python-lxml.spec | python-lxml | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 289 | python-mako.spec | python-mako | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 290 | python-markupsafe.spec | python-markupsafe | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 291 | python-mistune.spec | python-mistune | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 292 | python-mock.spec | python-mock | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 293 | python-more-itertools.spec | python-more-itertools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 294 | python-msgpack.spec | python-msgpack | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 295 | python-ndg-httpsclient.spec | python-ndg-httpsclient | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 296 | python-netaddr.spec | python-netaddr | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 297 | python-netifaces.spec | python-netifaces | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 298 | python-networkx.spec | python-networkx | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 299 | python-nocasedict.spec | python-nocasedict | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 300 | python-nocaselist.spec | python-nocaselist | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 301 | python-ntplib.spec | python-ntplib | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 302 | python-numpy.spec | python-numpy | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 303 | python-oauthlib.spec | python-oauthlib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 304 | python-packaging.spec | python-packaging | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 305 | python-pam.spec | python-pam | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 306 | python-paramiko.spec | python-paramiko | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 307 | python-pathspec.spec | python-pathspec | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 308 | python-pbr.spec | python-pbr | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 309 | python-pexpect.spec | python-pexpect | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 310 | python-pg8000.spec | python-pg8000 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 311 | python-pika.spec | python-pika | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 312 | python-pkgconfig.spec | python-pkgconfig | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 313 | python-platformdirs.spec | python-platformdirs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 314 | python-pluggy.spec | python-pluggy | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 315 | python-ply.spec | python-ply | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 316 | python-portalocker.spec | python-portalocker | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 317 | python-prettytable.spec | python-prettytable | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 318 | python-prometheus_client.spec | python-prometheus_client | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 319 | python-prompt_toolkit.spec | python-prompt_toolkit | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 320 | python-psutil.spec | python-psutil | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 321 | python-psycopg2.spec | python-psycopg2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 322 | python-ptyprocess.spec | python-ptyprocess | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 323 | python-py.spec | python-py | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 324 | python-pyOpenSSL.spec | python-pyOpenSSL | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 325 | python-pyasn1-modules.spec | python-pyasn1-modules | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 326 | python-pyasn1.spec | python-pyasn1 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 327 | python-pycodestyle.spec | python-pycodestyle | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 328 | python-pycparser.spec | python-pycparser | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 329 | python-pycryptodome.spec | python-pycryptodome | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 330 | python-pycryptodomex.spec | python-pycryptodomex | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 331 | python-pydantic.spec | python-pydantic | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 332 | python-pyflakes.spec | python-pyflakes | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 333 | python-pygobject.spec | python-pygobject | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 334 | python-pyinstaller-hooks-contrib.spec | python-pyinstaller-hooks-contrib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 335 | python-pyinstaller.spec | python-pyinstaller | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 336 | python-pyjsparser.spec | python-pyjsparser | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 337 | python-pyjsparser.spec | python-pyjsparser | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 338 | python-pyparsing.spec | python-pyparsing | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 339 | python-pyrsistent.spec | python-pyrsistent | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 340 | python-pyserial.spec | python-pyserial | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 341 | python-pytest.spec | python-pytest | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 342 | python-pytz-deprecation-shim.spec | python-pytz-deprecation-shim | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 343 | python-pytz.spec | python-pytz | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 344 | python-pyudev.spec | python-pyudev | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 345 | python-pyvim.spec | python-pyvim | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 346 | python-pyvmomi.spec | python-pyvmomi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 347 | python-pywbem.spec | python-pywbem | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 348 | python-requests-oauthlib.spec | python-requests-oauthlib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 349 | python-requests-toolbelt.spec | python-requests-toolbelt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 350 | python-requests-unixsocket.spec | python-requests-unixsocket | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 351 | python-requests.spec | python-requests | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 352 | python-resolvelib.spec | python-resolvelib | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 353 | python-rsa.spec | python-rsa | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 354 | python-ruamel-yaml.spec | python-ruamel-yaml | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 355 | python-s3transfer.spec | python-s3transfer | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 356 | python-schedutils.spec | python-schedutils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 357 | python-scp.spec | python-scp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 358 | python-scramp.spec | python-scramp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 359 | python-semantic-version.spec | python-semantic-version | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 360 | python-service_identity.spec | python-service_identity | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 361 | python-setuptools-rust.spec | python-setuptools-rust | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 362 | python-setuptools_scm.spec | python-setuptools_scm | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 363 | python-simplejson.spec | python-simplejson | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 364 | python-six.spec | python-six | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 365 | python-snowballstemmer.spec | python-snowballstemmer | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 366 | python-sortedcontainers.spec | python-sortedcontainers | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 367 | python-sphinx.spec | python-sphinx | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 368 | python-sphinxcontrib-applehelp.spec | python-sphinxcontrib-applehelp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 369 | python-sphinxcontrib-devhelp.spec | python-sphinxcontrib-devhelp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 370 | python-sphinxcontrib-htmlhelp.spec | python-sphinxcontrib-htmlhelp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 371 | python-sphinxcontrib-jsmath.spec | python-sphinxcontrib-jsmath | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 372 | python-sphinxcontrib-qthelp.spec | python-sphinxcontrib-qthelp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 373 | python-sphinxcontrib-serializinghtml.spec | python-sphinxcontrib-serializinghtml | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 374 | python-sqlalchemy.spec | python-sqlalchemy | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 375 | python-systemd.spec | python-systemd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 376 | python-terminaltables.spec | python-terminaltables | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 377 | python-terminaltables.spec | python-terminaltables | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 378 | python-toml.spec | python-toml | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 379 | python-tornado.spec | python-tornado | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 380 | python-typing-extensions.spec | python-typing-extensions | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 381 | python-tzlocal.spec | python-tzlocal | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 382 | python-ujson.spec | python-ujson | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 383 | python-urllib3.spec | python-urllib3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 384 | python-vcversioner.spec | python-vcversioner | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 385 | python-versioningit.spec | python-versioningit | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 386 | python-virtualenv.spec | python-virtualenv | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 387 | python-wcwidth.spec | python-wcwidth | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 388 | python-webob.spec | python-webob | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 389 | python-websocket-client.spec | python-websocket-client | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 390 | python-werkzeug.spec | python-werkzeug | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 391 | python-wheel.spec | python-wheel | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 392 | python-wrapt.spec | python-wrapt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 393 | python-xmltodict.spec | python-xmltodict | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 394 | python-yamlloader.spec | python-yamlloader | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 395 | python-zipp.spec | python-zipp | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 396 | python-zmq.spec | python-zmq | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 397 | python-zope.event.spec | python-zope.event | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 398 | python-zope.interface.spec | python-zope.interface | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 399 | python3-gcovr.spec | python3-gcovr | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 400 | python3-pip.spec | python3-pip | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 401 | python3-pyroute2.spec | python3-pyroute2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 402 | python3-setuptools.spec | python3-setuptools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 403 | python3.spec | python3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 404 | qemu.spec | qemu | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 405 | rabbitmq-server.spec | rabbitmq-server | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 406 | rdma-core.spec | rdma-core | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 407 | redis.spec | redis | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 408 | rng-tools.spec | rng-tools | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 409 | rpm-ostree.spec | rpm-ostree | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 410 | rpm.spec | rpm | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 411 | rpmdevtools.spec | rpmdevtools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 412 | rsyslog.spec | rsyslog | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 413 | rt-tests.spec | rt-tests | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 414 | ruby.spec | ruby | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 415 | rubygem-activesupport.spec | rubygem-activesupport | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 416 | rubygem-addressable.spec | rubygem-addressable | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 417 | rubygem-async-http.spec | rubygem-async-http | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 418 | rubygem-async-io.spec | rubygem-async-io | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 419 | rubygem-async-io.spec | rubygem-async-io | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 420 | rubygem-async-pool.spec | rubygem-async-pool | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 421 | rubygem-async.spec | rubygem-async | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 422 | rubygem-aws-eventstream.spec | rubygem-aws-eventstream | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 423 | rubygem-aws-partitions.spec | rubygem-aws-partitions | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 424 | rubygem-aws-sdk-core.spec | rubygem-aws-sdk-core | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 425 | rubygem-aws-sdk-kms.spec | rubygem-aws-sdk-kms | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 426 | rubygem-aws-sdk-s3.spec | rubygem-aws-sdk-s3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 427 | rubygem-aws-sdk-sqs.spec | rubygem-aws-sdk-sqs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 428 | rubygem-aws-sigv4.spec | rubygem-aws-sigv4 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 429 | rubygem-backports.spec | rubygem-backports | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 430 | rubygem-builder.spec | rubygem-builder | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 431 | rubygem-bundler.spec | rubygem-bundler | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 432 | rubygem-concurrent-ruby.spec | rubygem-concurrent-ruby | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 433 | rubygem-console.spec | rubygem-console | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 434 | rubygem-cool-io.spec | rubygem-cool-io | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 435 | rubygem-declarative.spec | rubygem-declarative | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 436 | rubygem-dig_rb.spec | rubygem-dig_rb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 437 | rubygem-digest-crc.spec | rubygem-digest-crc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 438 | rubygem-domain_name.spec | rubygem-domain_name | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 439 | rubygem-faraday-net_http.spec | rubygem-faraday-net_http | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 440 | rubygem-faraday.spec | rubygem-faraday | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 441 | rubygem-ffi-compiler.spec | rubygem-ffi-compiler | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 442 | rubygem-ffi.spec | rubygem-ffi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 443 | rubygem-fiber-annotation.spec | rubygem-fiber-annotation | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 444 | rubygem-fiber-local.spec | rubygem-fiber-local | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 445 | rubygem-fiber-storage.spec | rubygem-fiber-storage | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 446 | rubygem-fluent-plugin-concat.spec | rubygem-fluent-plugin-concat | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 447 | rubygem-fluent-plugin-gcs.spec | rubygem-fluent-plugin-gcs | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 448 | rubygem-fluent-plugin-kubernetes_metadata_filter.spec | rubygem-fluent-plugin-kubernetes_metadata_filter | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 449 | rubygem-fluent-plugin-remote_syslog.spec | rubygem-fluent-plugin-remote_syslog | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 450 | rubygem-fluent-plugin-s3.spec | rubygem-fluent-plugin-s3 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 451 | rubygem-fluent-plugin-systemd.spec | rubygem-fluent-plugin-systemd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 452 | rubygem-fluent-plugin-vmware-loginsight.spec | rubygem-fluent-plugin-vmware-loginsight | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 453 | rubygem-fluentd.spec | rubygem-fluentd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 454 | rubygem-google-apis-core.spec | rubygem-google-apis-core | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 455 | rubygem-google-apis-iamcredentials_v1.spec | rubygem-google-apis-iamcredentials_v1 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 456 | rubygem-google-apis-storage_v1.spec | rubygem-google-apis-storage_v1 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 457 | rubygem-google-cloud-core.spec | rubygem-google-cloud-core | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 458 | rubygem-google-cloud-env.spec | rubygem-google-cloud-env | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 459 | rubygem-google-cloud-errors.spec | rubygem-google-cloud-errors | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 460 | rubygem-google-cloud-storage.spec | rubygem-google-cloud-storage | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 461 | rubygem-google-logging-utils.spec | rubygem-google-logging-utils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 462 | rubygem-googleauth.spec | rubygem-googleauth | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 463 | rubygem-highline.spec | rubygem-highline | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 464 | rubygem-hpricot.spec | rubygem-hpricot | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 465 | rubygem-http-accept.spec | rubygem-http-accept | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 466 | rubygem-http-cookie.spec | rubygem-http-cookie | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 467 | rubygem-http-form_data.spec | rubygem-http-form_data | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 468 | rubygem-http-parser.spec | rubygem-http-parser | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 469 | rubygem-http.spec | rubygem-http | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 470 | rubygem-http_parser.rb.spec | rubygem-http_parser.rb | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 471 | rubygem-httpclient.spec | rubygem-httpclient | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 472 | rubygem-i18n.spec | rubygem-i18n | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 473 | rubygem-io-endpoint.spec | rubygem-io-endpoint | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 474 | rubygem-io-event.spec | rubygem-io-event | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 475 | rubygem-io-stream.spec | rubygem-io-stream | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 476 | rubygem-jmespath.spec | rubygem-jmespath | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 477 | rubygem-jsonpath.spec | rubygem-jsonpath | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 478 | rubygem-jwt.spec | rubygem-jwt | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 479 | rubygem-kubeclient.spec | rubygem-kubeclient | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 480 | rubygem-libxml-ruby.spec | rubygem-libxml-ruby | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 481 | rubygem-llhttp-ffi.spec | rubygem-llhttp-ffi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 482 | rubygem-lru_redux.spec | rubygem-lru_redux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 483 | rubygem-metrics.spec | rubygem-metrics | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 484 | rubygem-mime-types-data.spec | rubygem-mime-types-data | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 485 | rubygem-mime-types.spec | rubygem-mime-types | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 486 | rubygem-mini_mime.spec | rubygem-mini_mime | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 487 | rubygem-mini_portile2.spec | rubygem-mini_portile2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 488 | rubygem-msgpack.spec | rubygem-msgpack | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 489 | rubygem-multi_json.spec | rubygem-multi_json | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 490 | rubygem-mustache.spec | rubygem-mustache | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 491 | rubygem-net-http.spec | rubygem-net-http | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 492 | rubygem-netrc.spec | rubygem-netrc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 493 | rubygem-nio4r.spec | rubygem-nio4r | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 494 | rubygem-nokogiri.spec | rubygem-nokogiri | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 495 | rubygem-oj.spec | rubygem-oj | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 496 | rubygem-optimist.spec | rubygem-optimist | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 497 | rubygem-os.spec | rubygem-os | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 498 | rubygem-protocol-hpack.spec | rubygem-protocol-hpack | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 499 | rubygem-protocol-http.spec | rubygem-protocol-http | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 500 | rubygem-protocol-http1.spec | rubygem-protocol-http1 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 501 | rubygem-protocol-http2.spec | rubygem-protocol-http2 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 502 | rubygem-public_suffix.spec | rubygem-public_suffix | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 503 | rubygem-rbvmomi.spec | rubygem-rbvmomi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 504 | rubygem-rdiscount.spec | rubygem-rdiscount | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 505 | rubygem-recursive-open-struct.spec | rubygem-recursive-open-struct | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 506 | rubygem-remote_syslog_sender.spec | rubygem-remote_syslog_sender | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 507 | rubygem-representable.spec | rubygem-representable | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 508 | rubygem-rest-client.spec | rubygem-rest-client | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 509 | rubygem-retriable.spec | rubygem-retriable | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 510 | rubygem-ronn.spec | rubygem-ronn | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 511 | rubygem-rubyzip.spec | rubygem-rubyzip | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 512 | rubygem-serverengine.spec | rubygem-serverengine | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 513 | rubygem-sigdump.spec | rubygem-sigdump | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 514 | rubygem-signet.spec | rubygem-signet | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 515 | rubygem-strptime.spec | rubygem-strptime | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 516 | rubygem-syslog_protocol.spec | rubygem-syslog_protocol | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 517 | rubygem-systemd-journal.spec | rubygem-systemd-journal | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 518 | rubygem-terminal-table.spec | rubygem-terminal-table | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 519 | rubygem-thread_safe.spec | rubygem-thread_safe | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 520 | rubygem-timers.spec | rubygem-timers | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 521 | rubygem-traces.spec | rubygem-traces | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 522 | rubygem-trailblazer-option.spec | rubygem-trailblazer-option | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 523 | rubygem-trollop.spec | rubygem-trollop | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 524 | rubygem-tzinfo-data.spec | rubygem-tzinfo-data | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 525 | rubygem-tzinfo.spec | rubygem-tzinfo | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 526 | rubygem-uber.spec | rubygem-uber | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 527 | rubygem-unf.spec | rubygem-unf | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 528 | rubygem-unf_ext.spec | rubygem-unf_ext | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 529 | rubygem-unicode-display_width.spec | rubygem-unicode-display_width | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 530 | rubygem-unicode-emoji.spec | rubygem-unicode-emoji | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 531 | rubygem-webrick.spec | rubygem-webrick | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 532 | rubygem-yajl-ruby.spec | rubygem-yajl-ruby | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 533 | runc.spec | runc | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 534 | runit.spec | runit | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 535 | rust.spec | rust | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 536 | samba-client.spec | samba-client | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 537 | scons.spec | scons | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 538 | selinux-policy.spec | selinux-policy | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 539 | selinux-python.spec | selinux-python | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 540 | semodule-utils.spec | semodule-utils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 541 | sendmail.spec | sendmail | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 542 | setools.spec | setools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 543 | sg3_utils.spec | sg3_utils | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 544 | shim-signed.spec | shim-signed | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 545 | spirv-headers.spec | spirv-headers | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 546 | spirv-llvm-translator.spec | spirv-llvm-translator | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 547 | spirv-tools.spec | spirv-tools | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 548 | squid.spec | squid | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 549 | sssd.spec | sssd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 550 | stalld.spec | stalld | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 551 | stig-hardening.spec | stig-hardening | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 552 | stig-hardening.spec | stig-hardening | 200 |  | Info: Source0 contains a VMware internal url address. | Source0 points to a VMware internal URL. Provide a public upstream URL if available. |
| 553 | strace.spec | strace | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 554 | stunnel.spec | stunnel | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 555 | suricata.spec | suricata | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 556 | sysdig.spec | sysdig | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 557 | syslog-ng.spec | syslog-ng | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 558 | systemd.spec | systemd | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 559 | systemtap.spec | systemtap | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 560 | tcpdump.spec | tcpdump | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 561 | tdnf.spec | tdnf | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 562 | tdnf.spec | tdnf | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 563 | telegraf.spec | telegraf | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 564 | tinycdb.spec | tinycdb | pinned |  | vendor-pinned (subrelease 90) | Review warning and take appropriate action. |
| 565 | toybox.spec | toybox | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 566 | tpm2-pkcs11.spec | tpm2-pkcs11 | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 567 | tpm2-pytss.spec | tpm2-pytss | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 568 | trace-cmd.spec | trace-cmd | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 569 | tuna.spec | tuna | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 570 | tuned.spec | tuned | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 571 | util-linux.spec | util-linux | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 572 | uwsgi.spec | uwsgi | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 573 | vim.spec | vim | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 574 | vulkan-loader.spec | vulkan-loader | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 575 | xcb-proto.spec | xcb-proto | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 576 | xmlto.spec | xmlto | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 577 | xorg-applications.spec | xorg-applications | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |
| 578 | xorg-fonts.spec | xorg-fonts | pinned |  | vendor-pinned (subrelease 91) | Review warning and take appropriate action. |

