# Photon OS URL Health Issues - branch 3.0

**Source file:** photonos-urlhealth-3.0_202607260654.prn

**Total packages analyzed:** 919

**Total packages with issues:** 154

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 13

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 8 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 13 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 15 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 53 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 33 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 32 | Low-Medium |

---

## 1. Source URL Blank / Macro Unresolved (UrlHealth=blank)

The Source0 URL contains unexpanded RPM macros or is empty.

| # | Spec | Name | Source0 Original | Fix Suggestion |
|---|---|---|---|---|
| 1 | aufs-util.spec | aufs-util | `%{name}-%{version}.tar.gz` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 2 | iptables.spec | iptables | `http://www.netfilter.org/projects/iptables/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 3 | libmnl.spec | libmnl | `http://netfilter.org/projects/libmnl/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 4 | libnetfilter_conntrack.spec | libnetfilter_conntrack | `http://www.netfilter.org/projects/%{name}/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 5 | libnetfilter_cttimeout.spec | libnetfilter_cttimeout | `http://www.netfilter.org/projects/%{name}/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 6 | libnetfilter_queue.spec | libnetfilter_queue | `http://www.netfilter.org/projects/%{name}/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 7 | libnfnetlink.spec | libnfnetlink | `http://www.netfilter.org/projects/%{name}/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 8 | libnftnl.spec | libnftnl | `https://netfilter.org/projects/libnftnl/files/%{name}-%{version}.tar.bz2` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |

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
| 9 | libdaemon.spec | libdaemon | `http://0pointer.de/lennart/projects/libdaemon/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 10 | ndsend.spec | ndsend | `%{name}-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 11 | openjdk11_aarch64.spec | openjdk11 | `http://www.java.net/download/openjdk/jdk/jdk11/openjdk-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 12 | sqlite2.spec | sqlite2 | `ftp://ftp.za.freebsd.org/openbsd/distfiles/sqlite-%{version}.tar.gz` | Warning: Cannot detect correlating tags from the repo provided. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 13 | ulogd.spec | ulogd | `http://ftp.netfilter.org/pub/ulogd/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | PyYAML.spec | PyYAML | Warning: PyYAML.spec Source0 version 5.4.1 is higher than detected latest version 5.3.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | git.spec | git | Warning: git.spec Source0 version 2.39.4 is higher than detected latest version 2.25.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | hawkey.spec | hawkey | Warning: hawkey.spec Source0 version 2017.1 is higher than detected latest version 0.6.4-1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | less.spec | less | Warning: less.spec Source0 version 530 is higher than detected latest version 339 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 2.3.6 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | lightwave.spec | lightwave | Warning: lightwave.spec Source0 version 1.3.1.34 is higher than detected latest version 1.3.1-7 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | motd.spec | motd | Warning: motd.spec Source0 version 0.1.3 is higher than detected latest version 0.1.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | netmgmt.spec | netmgmt | Warning: netmgmt.spec Source0 version 1.2.0 is higher than detected latest version 1.0.4 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | ntp.spec | ntp | Warning: ntp.spec Source0 version 4.2.8p16 is higher than detected latest version 4.2.7 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | openresty.spec | openresty | Warning: openresty.spec Source0 version 1.21.4.3 is higher than detected latest version 1.0.15.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 1 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 3.61 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | urw-fonts.spec | urw-fonts | Warning: urw-fonts.spec Source0 version 1.0.7pre44 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | xorg-fonts.spec | xorg-fonts | Warning: xorg-fonts.spec Source0 version 7.7 is higher than detected latest version 1.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | XML-Parser.spec | XML-Parser | `https://github.com/toddr/XML-Parser/archive/refs/tags/2.44.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | ca-certificates-nxtgn-openssl.spec | ca-certificates | `http://anduin.linuxfromscratch.org/BLFS/othercertdata-nxtgn-openssl.txt` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | clang.spec | clang | `https://github.com/llvm/llvm-project/releases/download/llvmorg-10.0.1/clang-10.0.1.src.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | dbus-python.spec | dbus-python | `http://dbus.freedesktop.org/releases/dbus-python/dbus-python-1.2.16.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | docker-pycreds.spec | docker-pycreds | `https://github.com/shin-/dockerpy-creds/archive/refs/tags/0.3.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | dotnet-runtime.spec | dotnet-runtime | `https://github.com/dotnet/runtime/archive/refs/tags/v6.0.36.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | elasticsearch.spec | elasticsearch | `https://github.com/elastic/elasticsearch/archive/refs/tags/v6.8.15.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | elfutils.spec | elfutils | `https://sourceware.org/elfutils/ftp/0.176/elfutils-0.176.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | elixir.spec | elixir | `https://github.com/elixir-lang/elixir/archive/v1.13.4/elixir-1.13.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | eventlog.spec | eventlog | `https://www.balabit.com/downloads/files/eventlog/0.2/eventlog_0.2.12.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | expat.spec | expat | `https://github.com/libexpat/libexpat/releases/download/R_2.2.9/expat-2.2.9.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | gnuplot.spec | gnuplot | `https://github.com/gnuplot/gnuplot/archive/refs/tags/5.4.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | google-compute-engine.spec | google-compute-engine | `https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/v20180905.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | iana-etc.spec | iana-etc | `https://github.com/Mic92/iana-etc/releases/download/2.30/iana-etc-2.30.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | ipxe.spec | ipxe | `https://github.com/ipxe/ipxe/archive/refs/tags/v20180717.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | json_spirit.spec | json_spirit | `https://www.codeproject.com/KB/recipes/JSON_Spirit/json_spirit_v4.08.zip` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | kubernetes-dns.spec | kubernetes-dns | `https://github.com/kubernetes/dns/archive/refs/tags/1.22.23.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | libestr.spec | libestr | `https://github.com/rsyslog/libestr/archive/refs/tags/v0.1.11.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | libmetalink.spec | libmetalink | `https://github.com/metalink-dev/libmetalink/releases/download/release-0.1.3/libmetalink-0.1.3.tar.bz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | libmspack.spec | libmspack | `https://github.com/kyz/libmspack/archive/refs/tags/v0.10.1alpha.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | libnl.spec | libnl | `https://github.com/thom311/libnl/archive/refs/tags/libnl3.4.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | libpcap.spec | libpcap | `https://github.com/the-tcpdump-group/libpcap/archive/refs/tags/libpcap-1.9.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | libpwquality.spec | libpwquality | `https://github.com/libpwquality/libpwquality/releases/download/libpwquality-1.4.2/libpwquality-1.4.2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | librepo.spec | librepo | `https://github.com/rpm-software-management/librepo/archive/refs/tags/1.10.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | libxslt.spec | libxslt | `https://github.com/GNOME/libxslt/archive/refs/tags/v1.1.34.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | lvm2.spec | lvm2 | `https://github.com/lvmteam/lvm2/archive/refs/tags/v2.03.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | lzo.spec | lzo | `https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | netkit-telnet.spec | netkit-telnet | `https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/0.17/netkit-telnet-debian-0.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | nmap.spec | nmap | `https://nmap.org/dist/nmap-7.91.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | nodejs-10.24.0.spec | nodejs | `https://nodejs.org/download/release/v10.24.0/node-v10.24.0.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 33 | nodejs-8.17.0.spec | nodejs | `https://nodejs.org/download/release/v8.17.0/node-v8.17.0.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 34 | nodejs-9.11.2.spec | nodejs | `https://nodejs.org/download/release/v9.11.2/node-v9.11.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 35 | nss-altfiles.spec | nss-altfiles | `https://github.com/aperezdc/nss-altfiles/archive/refs/tags/v2.23.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 36 | nxtgn-openssl.spec | nxtgn-openssl | `https://github.com/openssl/openssl/archive/refs/tags/OpenSSL_1_1_1w.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 37 | openssl.spec | openssl | `http://www.openssl.org/source/openssl-1.0.2zl.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 38 | perftest.spec | perftest | `https://github.com/linux-rdma/perftest/archive/refs/tags/4.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 39 | perl-File-Which.spec | perl-File-Which | `https://github.com/uperl/File-Which/archive/refs/tags/v1.22.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 40 | perl-Path-Class.spec | perl-Path-Class | `https://github.com/kenahoo/Path-Class/archive/refs/tags/v0.37.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 41 | python-antlrpythonruntime.spec | python-antlrpythonruntime | `https://www.antlr3.org/download/Python/antlr_python_runtime-3.1.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 42 | redis.spec | redis | `https://github.com/redis/redis/archive/refs/tags/6.2.16.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 43 | rootlesskit.spec | rootlesskit | `https://github.com/rootless-containers/rootlesskit/archive/refs/tags/v1.0.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 44 | shadow.spec | shadow | `https://github.com/shadow-maint/shadow/archive/refs/tags/4.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 45 | slirp4netns.spec | slirp4netns | `https://github.com/rootless-containers/slirp4netns/archive/refs/tags/v1.2.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 46 | sqlite.spec | sqlite | `https://github.com/sqlite/sqlite/archive/refs/tags/version-3.35.5.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 47 | tiptop.spec | tiptop | `https://files.inria.fr/pacap/tiptop/tiptop-2.3.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 48 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2023c.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 49 | valgrind.spec | valgrind | `https://sourceware.org/pub/valgrind/valgrind-3.15.0.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 50 | wireshark.spec | wireshark | `https://github.com/wireshark/wireshark/archive/refs/tags/wireshark-3.6.20.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 51 | wrapt.spec | wrapt | `https://github.com/GrahamDumpleton/wrapt/archive/refs/tags/1.14.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 52 | xinetd.spec | xinetd | `https://github.com/xinetd-org/xinetd/archive/refs/tags/xinetd-2.3.15.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 53 | xorg-applications.spec | xorg-applications | `https://www.x.org/archive/individual/util/bdftopcf-7.7.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | Linux-PAM.spec | Linux-PAM | 1.7.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | ModemManager.spec | ModemManager | 1.24.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | apparmor.spec | apparmor | 4.1.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | bridge-utils.spec | bridge-utils | 1.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | commons-daemon.spec | commons-daemon | 1.6.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | fontconfig.spec | fontconfig | 2.18.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | govmomi.spec | govmomi | 0.55.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | iputils.spec | iputils | 20250605 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | kbd.spec | kbd | 2.10.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | leveldb.spec | leveldb | 1.23 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | libfastjson.spec | libfastjson | 1.2304.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | lldb.spec | lldb | 22.1.8 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | llvm.spec | llvm | 22.1.8 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | lshw.spec | lshw | 02.20 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | nss.spec | nss | 3.126 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | openjdk10.spec | openjdk10 | +9 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | perl-YAML.spec | perl-YAML | 1.320.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | pgaudit.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | pth.spec | pth | 23.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

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
| 7 | etcd-3.3.27.spec | etcd | 200 | 3.7.1 | Info: Source0 contains a static version number. | Review warning and take appropriate action. |
| 8 | findutils.spec | findutils | 200 | 4.11.0 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 9 | font-util.spec | font-util | 200 | 1.4.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 10 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 11 | http-parser.spec | http-parser | 200 | 2.9.4 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 12 | icu.spec | icu | 200 | 78.3 | Info: Packaging format .tgz has changed to .zip | Review warning and take appropriate action. |
| 13 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 14 | libXau.spec | libXau | 200 | 1.0.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 15 | libXdcmp.spec | libXdmcp | 200 | 1.1.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 16 | libXfont2.spec | libXfont2 | 200 | 2.0.8 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
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

