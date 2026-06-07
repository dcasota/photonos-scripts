# Photon OS URL Health Issues - branch 3.0

**Source file:** photonos-urlhealth-3.0_202606071901.prn

**Total packages analyzed:** 919

**Total packages with issues:** 138

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 13

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 3 | Source URL unreachable (UrlHealth=0) | 12 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 19 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 40 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 35 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 32 | Low-Medium |

---

## 3. Source URL Unreachable (UrlHealth=0)

| # | Spec | Name | Modified Source0 | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | PyPAM.spec | PyPAM | `http://www.pangalactic.org/PyPAM/PyPAM-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 2 | cdrkit.spec | cdrkit | `http://gd.tuwien.ac.at/utils/schilling/cdrtoolscdrkit-1.1.11.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 3 | dhcp.spec | dhcp | `ftp://ftp.isc.org/isc/dhcp/${version}/%{name}-%{version}.tar.gz` | Warning: repo isn't maintained anymore. See https://www.isc.org/dhcp_migration/ | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 4 | fcgi.spec | fcgi | `http://fastcgi.com/dist/fcgi-%{version}.tar.gz` | Warning: repo isn't maintained anymore. See https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/%{version}.tar.gz . | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 5 | filesystem.spec | filesystem | `filesystem-1.1.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 6 | finger.spec | finger | `ftp://ftp.uk.linux.org/pub/linux/Networking/netkit/bsd-finger-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 7 | iptraf.spec | iptraf | `ftp://iptraf.seul.org/pub/iptraf/iptraf-3.0.1.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 8 | libassuan.spec | libassuan | `ftp://ftp.gnupg.org/gcrypt/libassuan/libassuan-2.5.1.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 9 | ndsend.spec | ndsend | `%{name}-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 10 | openjdk11_aarch64.spec | openjdk11 | `http://www.java.net/download/openjdk/jdk/jdk11/openjdk-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 11 | sqlite2.spec | sqlite2 | `ftp://ftp.za.freebsd.org/openbsd/distfiles/sqlite-%{version}.tar.gz` | Warning: Cannot detect correlating tags from the repo provided. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 12 | ulogd.spec | ulogd | `http://ftp.netfilter.org/pub/ulogd/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | PyYAML.spec | PyYAML | Warning: PyYAML.spec Source0 version 5.4.1 is higher than detected latest version 5.3.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | hawkey.spec | hawkey | Warning: hawkey.spec Source0 version 2017.1 is higher than detected latest version 0.6.4-1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | icu.spec | icu | Warning: icu.spec Source0 version 67.1 is higher than detected latest version 58-1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | ipxe.spec | ipxe | Warning: ipxe.spec Source0 version 20180717 is higher than detected latest version 2.0.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.10.1alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 2.3.6 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | lightwave.spec | lightwave | Warning: lightwave.spec Source0 version 1.3.1.34 is higher than detected latest version 1.3.1-7 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.18 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | motd.spec | motd | Warning: motd.spec Source0 version 0.1.3 is higher than detected latest version 0.1.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | netmgmt.spec | netmgmt | Warning: netmgmt.spec Source0 version 1.2.0 is higher than detected latest version 1.0.4 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | openssl.spec | openssl | Warning: openssl.spec Source0 version 1.0.2zl is higher than detected latest version 4.0.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 1 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | perl-Module-ScanDeps.spec | perl-Module-ScanDeps | Warning: perl-Module-ScanDeps.spec Source0 version 1.25 is higher than detected latest version 0.92 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | sysdig.spec | sysdig | Warning: sysdig.spec Source0 version 0.30.2 is higher than detected latest version 0.1.104 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 16 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 17 | thin-provisioning-tools.spec | thin-provisioning-tools | Warning: thin-provisioning-tools.spec Source0 version 0.7.0 is higher than detected latest version 0.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 18 | urw-fonts.spec | urw-fonts | Warning: urw-fonts.spec Source0 version 1.0.7pre44 is higher than detected latest version 1.0.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 19 | xorg-fonts.spec | xorg-fonts | Warning: xorg-fonts.spec Source0 version 7.7 is higher than detected latest version 1.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | apr.spec | apr | `https://github.com/apache/apr/archive/refs/tags/1.6.5.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | ca-certificates-nxtgn-openssl.spec | ca-certificates | `http://anduin.linuxfromscratch.org/BLFS/othercertdata-nxtgn-openssl.txt` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | cairo.spec | cairo | `https://gitlab.freedesktop.org/cairo/cairo/-/archive/1.16.0/cairo-1.16.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | cassandra.spec | cassandra | `https://github.com/apache/cassandra/archive/refs/tags/cassandra-3.11.12.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | cyrus-sasl.spec | cyrus-sasl | `https://github.com/cyrusimap/cyrus-sasl/archive/refs/tags/cyrus-sasl-2.1.26.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | dbus.spec | dbus | `http://dbus.freedesktop.org/releases/dbus/dbus-1.13.8.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | eventlog.spec | eventlog | `https://www.balabit.com/downloads/files/eventlog/0.2/eventlog_0.2.12.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | geoip-api-c.spec | geoip-api-c | `https://github.com/maxmind/geoip-api-c/releases/download/v1.6.12/GeoIP-1.6.12.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | git.spec | git | `https://www.kernel.org/pub/software/scm/git/git-2.39.4.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | json_spirit.spec | json_spirit | `https://www.codeproject.com/KB/recipes/JSON_Spirit/json_spirit_v4.08.zip` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | kmod.spec | kmod | `https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-25.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | libX11.spec | libX11 | `https://gitlab.freedesktop.org/xorg/lib/libx11/-/archive/libX11-1.8.5/libx11-libX11-1.8.5.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | libdaemon.spec | libdaemon | `https://0pointer.de/lennart/projects/libdaemon/libdaemon-0.14.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | liblogging.spec | liblogging | `https://github.com/rsyslog/liblogging/archive/refs/tags/v1.0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | llvm.spec | llvm | `https://github.com/llvm/llvm-project/releases/download/llvmorg-10.0.1/llvm-10.0.1.src.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | lzo.spec | lzo | `https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | net-snmp.spec | net-snmp | `https://github.com/net-snmp/net-snmp/archive/refs/tags/v5.8.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | netkit-telnet.spec | netkit-telnet | `https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/0.17/netkit-telnet-debian-0.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | nodejs-10.24.0.spec | nodejs | `https://nodejs.org/download/release/v10.24.0/node-v10.24.0.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | nodejs-8.17.0.spec | nodejs | `https://nodejs.org/download/release/v8.17.0/node-v8.17.0.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | nodejs-9.11.2.spec | nodejs | `https://nodejs.org/download/release/v9.11.2/node-v9.11.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | nxtgn-openssl.spec | nxtgn-openssl | `https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1w.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | open-isns.spec | open-isns | `https://github.com/open-iscsi/open-isns/archive/refs/tags/v0.100.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | openresty.spec | openresty | `https://github.com/openresty/openresty/archive/refs/tags/v1.21.4.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | pciutils.spec | pciutils | `https://www.kernel.org/pub/software/utils/pciutils/pciutils-3.6.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | perl-URI.spec | perl-URI | `https://github.com/libwww-perl/URI/archive/refs/tags/v5.09.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | perl-libintl.spec | perl-libintl | `https://github.com/gflohr/libintl-perl/archive/refs/tags/v1.29.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | powershell.spec | powershell | `https://github.com/PowerShell/PowerShell/archive/refs/tags/v7.2.24.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | pygobject.spec | pygobject | `https://gitlab.gnome.org/GNOME/pygobject/-/archive/3.30.1/pygobject-3.30.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | python-antlrpythonruntime.spec | python-antlrpythonruntime | `https://www.antlr3.org/download/Python/antlr_python_runtime-3.1.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 33 | repmgr.spec | repmgr | `https://github.com/EnterpriseDB/repmgr/archive/refs/tags/v5.2.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 34 | rpm.spec | rpm | `https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-4.14.3-release.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 35 | sg3_utils.spec | sg3_utils | `https://github.com/hreinecke/sg3_utils/archive/refs/tags/v1.43.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 36 | tiptop.spec | tiptop | `https://files.inria.fr/pacap/tiptop/tiptop-2.3.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 37 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2023c.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 38 | utf8proc.spec | utf8proc | `https://github.com/JuliaStrings/utf8proc/archive/refs/tags/v2.2.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 39 | xorg-applications.spec | xorg-applications | `https://www.x.org/archive/individual/util/bdftopcf-7.7.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 40 | yarn.spec | yarn | `https://github.com/yarnpkg/yarn/archive/refs/tags/v1.21.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | Linux-PAM.spec | Linux-PAM | 1.7.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | ModemManager.spec | ModemManager | 1.24.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | apparmor.spec | apparmor | 4.1.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | bridge-utils.spec | bridge-utils | 1.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | clang.spec | clang | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | commons-daemon.spec | commons-daemon | 1.6.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | expat.spec | expat | 20000512 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | fontconfig.spec | fontconfig | 2.18.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | govmomi.spec | govmomi | 0.54.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | iputils.spec | iputils | 20250605 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | kbd.spec | kbd | 2.10.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | kexec-tools.spec | kexec-tools | 20080324 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | leveldb.spec | leveldb | 1.23 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | libcap.spec | libcap | 20071031 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | libfastjson.spec | libfastjson | 1.2304.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | lldb.spec | lldb | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | nss.spec | nss | 3.124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | openjdk10.spec | openjdk10 | +9 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | pgaudit.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | pth.spec | pth | 23.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | python-pyvmomi.spec | python-pyvmomi | 9.1.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | autoconf213.spec | autoconf213 | 200 |  | Info: Source0 contains a static version number. | Review warning and take appropriate action. |
| 2 | bluez-tools.spec | bluez-tools | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 3 | c-rest-engine.spec | c-rest-engine | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 4 | copenapi.spec | copenapi | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 5 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 6 | cve-check-tool.spec | cve-check-tool | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 7 | dbus-python.spec | dbus-python | 200 | 1.4.0 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 8 | etcd-3.3.27.spec | etcd | 200 | 3.6.12 | Info: Source0 contains a static version number. | Review warning and take appropriate action. |
| 9 | findutils.spec | findutils | 200 | 4.10.0 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 10 | font-util.spec | font-util | 200 | 1.4.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 11 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 12 | http-parser.spec | http-parser | 200 | 2.9.4 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 13 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 14 | libXau.spec | libXau | 200 | 1.0.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 15 | libXdcmp.spec | libXdmcp | 200 | 1.1.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 16 | libXfont2.spec | libXfont2 | 200 | 2.0.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 17 | libfontenc.spec | libfontenc | 200 | 1.1.9 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 18 | libgsystem.spec | libgsystem | 404 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 19 | libsepol.spec | libsepol | 404 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 20 | libslirp.spec | libslirp | 200 | 2.5.20200525 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 21 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 22 | lightstep-tracer-cpp.spec | lightstep-tracer-cpp | 404 | 0.38 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 23 | likewise-open.spec | likewise-open | 404 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 24 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 25 | python-atomicwrites.spec | python-atomicwrites | 200 | 1.4.1 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 26 | python-ipaddr.spec | python-ipaddr | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 27 | python-lockfile.spec | python-lockfile | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 28 | python-pycodestyle.spec | python-pycodestyle | 200 | 2.14.0 | Warning: duplicate of python-pam.spec | This spec may be a duplicate. Consider consolidating with the referenced spec. |
| 29 | python-subprocess32.spec | python-subprocess32 | 200 | 3.5.4 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 30 | python-terminaltables.spec | python-terminaltables | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 31 | util-macros.spec | util-macros | 200 | 1.20.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 32 | xtrans.spec | xtrans | 200 | 1.6.0 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |

