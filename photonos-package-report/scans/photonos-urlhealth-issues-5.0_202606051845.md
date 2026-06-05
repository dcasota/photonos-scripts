# Photon OS URL Health Issues - branch 5.0

**Source file:** photonos-urlhealth-5.0_202606051845.prn

**Total packages analyzed:** 1660

**Total packages with issues:** 156

**Vendor-pinned subrelease (frozen for a Photon sub-release) — informational, not an issue:** 614

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 15

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 2 | High |
| 2 | URL substitution unfinished | 3 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 39 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 24 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 39 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 39 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 10 | Low-Medium |

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
| 1 | cdrkit.spec | cdrkit | `http://gd.tuwien.ac.at/utils/schilling/cdrtoolscdrkit-1.1.11.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 2 | filesystem.spec | filesystem | `clock` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 3 | font-util.spec | font-util | `http://ftp.x.org/pub/individual/font/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 4 | hyper-v.spec | hyper-v | `%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 5 | libICE.spec | libICE | `https://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.xz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 6 | libSM.spec | libSM | `https://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.xz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 7 | libXScrnSaver.spec | libXScrnSaver | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 8 | libXau.spec | libXau | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 9 | libXcomposite.spec | libXcomposite | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 10 | libXcursor.spec | libXcursor | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 11 | libXdamage.spec | libXdamage | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 12 | libXdmcp.spec | libXdmcp | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 13 | libXext.spec | libXext | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 14 | libXfixes.spec | libXfixes | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 15 | libXfont2.spec | libXfont2 | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 16 | libXi.spec | libXi | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 17 | libXrandr.spec | libXrandr | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 18 | libXrender.spec | libXrender | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 19 | libXt.spec | libXt | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 20 | libXtst.spec | libXtst | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 21 | libfontenc.spec | libfontenc | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 22 | libpciaccess.spec | libpciaccess | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 23 | libxshmfence.spec | libxshmfence | `https://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 24 | procps-ng.spec | procps-ng | `https://sourceforge.net/projects/procps-ng/files/Production/procps-4.0.6.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 25 | proto.spec | proto | `http://ftp.x.org/pub/individual/proto/xproto-%{xproto_ver}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 26 | python-installer.spec | python-installer | `https://github.com/pypa/installer/archive/refs/tags/installer-0.7.0.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 27 | python-ruamel-yaml.spec | python-ruamel-yaml | `https://files.pythonhosted.org/packages/ruamel.yaml-0.19.1.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 28 | python3-Pygments.spec | python3-Pygments | `https://github.com/pygments/pygments/archive/refs/tags/pygments-2.19.2.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 29 | python3-iniconfig.spec | python3-iniconfig | `https://github.com/RonnyPfannschmidt/iniconfig/archive/refs/tags/iniconfig-2.3.0.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 30 | python3-iniparse.spec | python3-iniparse | `http://iniparse.googlecode.com/files/iniparse-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 31 | python3-legacy-cgi.spec | python3-legacy-cgi | `legacy_cgi-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 32 | python3-markupsafe.spec | python3-markupsafe | `https://github.com/pallets/markupsafe/archive/refs/tags/markupsafe-3.0.3.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 33 | python3-roman-numerals.spec | python3-roman-numerals | `roman_numerals-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 34 | python3-trove-classifiers.spec | python3-trove-classifiers | `https://github.com/pypa/trove-classifiers/archive/refs/tags/trove-classifiers-2026.1.14.14.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 35 | python3-wheel.spec | python3-wheel | `https://github.com/pypa/wheel/archive/refs/tags/wheel-0.46.3.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 36 | repmgr18.spec | repmgr | `https://repmgr.org/download/%{srcname}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 37 | util-macros.spec | util-macros | `http://ftp.x.org/pub/individual/util/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 38 | wal2json18.spec | wal2json | `https://github.com/eulerto/wal2json/archive/refs/tags/wal2json-2.6.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 39 | xtrans.spec | xtrans | `https://ftp.x.org/pub/individual/lib/xtrans-1.6.0.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | apparmor.spec | apparmor | Warning: apparmor.spec Source0 version 4.1.6 is higher than detected latest version 4.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | dnsmasq.spec | dnsmasq | Warning: dnsmasq.spec Source0 version 2.92rel2 is higher than detected latest version 2.93 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | dracut.spec | dracut | Warning: dracut.spec Source0 version 109 is higher than detected latest version 059 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | glibmm.spec | glibmm | Warning: glibmm.spec Source0 version 2.74.0 is higher than detected latest version 2.68.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | ibmtpm.spec | ibmtpm | Warning: ibmtpm.spec Source0 version 20240802.183 is higher than detected latest version 2024-08-02 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.11alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 20240514 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | linux-esx.spec | linux | Warning: linux-esx.spec Source0 version 6.12.92 is higher than detected latest version 6.1.175 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | linux.spec | linux | Warning: linux.spec Source0 version 6.12.92-acvp} is higher than detected latest version 6.1.175 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | llvm.spec | llvm | Warning: llvm.spec Source0 version 22.1.0 is higher than detected latest version 19.1.6 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.20 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | mdadm.spec | mdadm | Warning: mdadm.spec Source0 version 4.6 is higher than detected latest version 4.4 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | memcached.spec | memcached | Warning: memcached.spec Source0 version 1.6.22 is higher than detected latest version 1.4.16 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | mesa.spec | mesa | Warning: mesa.spec Source0 version 25.3.6 is higher than detected latest version 24.0.7 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 16 | mysql.spec | mysql | Warning: mysql.spec Source0 version 8.4.9 is higher than detected latest version 5.5.43 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 17 | openresty.spec | openresty | Warning: openresty.spec Source0 version 1.21.4.3 is higher than detected latest version 1.19.9.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 18 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 2.0 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 19 | perl-DBI.spec | perl-DBI | Warning: perl-DBI.spec Source0 version 1.647 is higher than detected latest version 1.611.93 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 20 | python3-setuptools.spec | python3-setuptools | Warning: python3-setuptools.spec Source0 version 80.9.0 is higher than detected latest version 56.0.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 21 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 22 | snappy.spec | snappy | Warning: snappy.spec Source0 version 1.1.9 is higher than detected latest version 1.1.6 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 23 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 24 | systemd.spec | systemd | Warning: systemd.spec Source0 version 257.13 is higher than detected latest version 256 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | bzip2.spec | bzip2 | `https://github.com/libarchive/bzip2/archive/refs/tags/bzip2-1.0.8.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | calico-bird.spec | calico-bird | `https://github.com/projectcalico/bird/archive/refs/tags/v0.3.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | calico-libnetwork.spec | calico-libnetwork | `https://github.com/projectcalico/libnetwork-plugin/archive/refs/tags/v1.1.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | chrony.spec | chrony | `https://github.com/mlichvar/chrony/archive/refs/tags/4.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | cups.spec | cups | `https://github.com/OpenPrinting/cups/archive/refs/tags/v2.4.18.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | distcc.spec | distcc | `https://github.com/distcc/distcc/releases/download/v3.4/distcc-3.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | dovecot-pigeonhole.spec | dovecot-pigeonhole | `https://pigeonhole.dovecot.org/releases/2.3/dovecot-2.3-pigeonhole-0.5.21.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | dovecot.spec | dovecot | `https://dovecot.org/releases/2.3/dovecot-2.3.21.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | erlang.spec | erlang | `https://github.com/erlang/otp/archive/refs/tags/OTP-27.3.4.11.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | fuse3.spec | fuse3 | `https://github.com/libfuse/libfuse/releases/download/fuse-3.3.18.2/fuse-3.3.18.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | gtk-doc.spec | gtk-doc | `https://github.com/GNOME/gtk-doc/archive/refs/tags/1.33.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | httpd-mod_jk.spec | httpd-mod_jk | `https://github.com/apache/tomcat-connectors/archive/refs/tags/JK_1.2.48.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | iana-etc.spec | iana-etc | `https://github.com/Mic92/iana-etc/releases/download/20260529/iana-etc-20260529.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | kmod.spec | kmod | `https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-34.1.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | lasso.spec | lasso | `https://dev.entrouvert.org/lasso/lasso-2.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | leveldb.spec | leveldb | `https://github.com/google/leveldb/archive/refs/tags/v1.23.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | libbsd.spec | libbsd | `https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | libcap.spec | libcap | `https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.77.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | libdisplay-info.spec | libdisplay-info | `https://gitlab.freedesktop.org/emersion/libdisplay-info/-/archive/0.3.0/libdisplay-info-0.3.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | libnl.spec | libnl | `https://github.com/thom311/libnl/archive/refs/tags/libnl3.7.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | librdkafka.spec | librdkafka | `https://github.com/confluentinc/librdkafka/archive/refs/tags/v1.8.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.6` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | lz4.spec | lz4 | `https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | openjdk11.spec | openjdk | `https://github.com/openjdk/jdk11u/archive/refs/tags/jdk-11.0.30.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | openjdk25.spec | openjdk | `https://github.com/openjdk/jdk25u/archive/refs/tags/jdk-25.0.2-ga.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | perl-Module-ScanDeps.spec | perl-Module-ScanDeps | `https://github.com/rschupp/Module-ScanDeps/archive/refs/tags/1.37.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | perl-Object-Accessor.spec | perl-Object-Accessor | `https://github.com/jib/object-accessor/archive/refs/tags/0.48.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | pixman.spec | pixman | `https://xorg.freedesktop.org/archive/individual/lib/pixman-0.42.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | polkit.spec | polkit | `https://www.freedesktop.org/software/polkit/releases/polkit-121.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | python-dateutil.spec | python-dateutil | `https://github.com/dateutil/dateutil/archive/refs/tags/2.8.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | python-schedutils.spec | python-schedutils | `https://git.kernel.org/pub/scm/libs/python/python-schedutils/python-schedutils.git/snapshot/python-s` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 33 | python3-hatchling.spec | python3-hatchling | `https://github.com/pypa/hatch/releases/download/hatchling-v1.29.0/hatchling-1.29.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 34 | repmgr16.spec | repmgr | `https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v5.5.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 35 | rpcsvc-proto.spec | rpcsvc-proto | `https://github.com/thkukuk/rpcsvc-proto/archive/refs/tags/v1.4.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 36 | s3fs-fuse.spec | s3fs-fuse | `https://github.com/s3fs-fuse/s3fs-fuse/archive/refs/tags/v1.97.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 37 | tmux.spec | tmux | `https://github.com/tmux/tmux/archive/refs/tags/3.5.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 38 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2024b.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 39 | vulkan-tools.spec | vulkan-tools | `https://github.com/KhronosGroup/Vulkan-Tools/archive/refs/tags/sdk-1.3.231.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | dos2unix.spec | dos2unix | 7.5.6 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | erofs-utils.spec | erofs-utils | 20190826 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | expat.spec | expat | 20000512 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | fontconfig.spec | fontconfig | 2.18.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | govmomi.spec | govmomi | 0.54.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | icu.spec | icu | 78.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | kexec-tools.spec | kexec-tools | 20080324 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | libdrm.spec | libdrm | 200-0-1-20020822 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | libslirp.spec | libslirp | 2.5.20200525 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | libunwind.spec | libunwind | 4.0.10 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | mozjs.spec | mozjs | 151.0.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | ncurses.spec | ncurses | 6.6.20260530 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | nss.spec | nss | 3.124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | perl-IPC-Run.spec | perl-IPC-Run | 20260402 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | pgaudit15.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | pgaudit16.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | pgaudit17.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | python-filelock.spec | python-filelock | 3.29.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | python-google-auth.spec | python-google-auth | 1946 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | python-pyvmomi.spec | python-pyvmomi | 9.1.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | python-vcs-versioning.spec | python-vcs-versioning | 9.2.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | qemu.spec | qemu | /9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | spirv-headers.spec | spirv-headers | 1.5.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 36 | spirv-tools.spec | spirv-tools | 2026.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 37 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 38 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 39 | wayland-protocols.spec | wayland-protocols | 1.48 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | cloud-network-setup.spec | cloud-network-setup | 200 | 0.2.3 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 2 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 3 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 4 | http-parser.spec | http-parser | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 5 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 6 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 7 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 8 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 9 | python-pycodestyle.spec | python-pycodestyle | 200 | 2.14.0 | Warning: duplicate of python-pam.spec | This spec may be a duplicate. Consider consolidating with the referenced spec. |
| 10 | python-terminaltables.spec | python-terminaltables | 200 | 3.1.10 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |

