# Photon OS URL Health Issues - branch 4.0

**Source file:** photonos-urlhealth-4.0_202606050254.prn

**Total packages analyzed:** 1032

**Total packages with issues:** 162

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 14

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 2 | High |
| 2 | URL substitution unfinished | 1 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 40 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 18 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 36 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 47 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 18 | Low-Medium |

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
| 1 | dhcp.spec | dhcp | `ftp://ftp.isc.org/isc/dhcp/${version}/%{name}-%{version}.tar.gz` | `` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |

---

## 3. Source URL Unreachable (UrlHealth=0)

| # | Spec | Name | Modified Source0 | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | PyPAM.spec | PyPAM | `http://www.pangalactic.org/PyPAM/PyPAM-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 2 | cdrkit.spec | cdrkit | `http://cdrkit.orgcdrkit-1.1.11.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 3 | cpulimit.spec | cpulimit | `https://github.com/opsengine/cpulimit/archive/refs/tags/cpulimit-1.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 4 | dcerpc.spec | dcerpc | `dcerpc-%{version}.tar.gz` | Warning: Cannot detect correlating tags from the repo provided. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 5 | fcgi.spec | fcgi | `http://fastcgi.com/dist/fcgi-%{version}.tar.gz` | Warning: repo isn't maintained anymore. See https://github.com/FastCGI-Archives/fcgi2/archive/refs/tags/%{version}.tar.gz . | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 6 | filesystem.spec | filesystem | `filesystem-1.1.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 7 | finger.spec | finger | `ftp://ftp.uk.linux.org/pub/linux/Networking/netkit/bsd-finger-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 8 | font-util.spec | font-util | `http://ftp.x.org/pub/individual/font/font-util-1.3.2.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 9 | hyper-v.spec | hyper-v | `%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 10 | libICE.spec | libICE | `https://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.xz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 11 | libSM.spec | libSM | `https://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.xz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 12 | libXScrnSaver.spec | libXScrnSaver | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 13 | libXau.spec | libXau | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 14 | libXcomposite.spec | libXcomposite | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 15 | libXcursor.spec | libXcursor | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 16 | libXdamage.spec | libXdamage | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 17 | libXdmcp.spec | libXdmcp | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 18 | libXext.spec | libXext | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 19 | libXfixes.spec | libXfixes | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 20 | libXfont2.spec | libXfont2 | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 21 | libXi.spec | libXi | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 22 | libXrandr.spec | libXrandr | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 23 | libXrender.spec | libXrender | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 24 | libXt.spec | libXt | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 25 | libXtst.spec | libXtst | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 26 | libdaemon.spec | libdaemon | `http://0pointer.de/lennart/projects/libdaemon/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 27 | libfontenc.spec | libfontenc | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 28 | libpciaccess.spec | libpciaccess | `http://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 29 | libxshmfence.spec | libxshmfence | `https://ftp.x.org/pub/individual/lib/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 30 | lightstep-tracer-cpp.spec | lightstep-tracer-cpp | `https://github.com/lightstep/lightstep-tracer-cpp/archive/refs/tags/v0.19.0.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 31 | ndsend.spec | ndsend | `%{name}-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 32 | proto.spec | proto | `http://ftp.x.org/pub/individual/proto/xproto-%{xproto_ver}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 33 | python-daemon.spec | python-daemon | `https://pagure.io/python-daemon/archive/release/2.3.2/python-daemon-release/2.3.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 34 | python-ruamel-yaml.spec | python-ruamel-yaml | `https://files.pythonhosted.org/packages/ruamel.yaml-0.16.12.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 35 | sendmail.spec | sendmail | `https://ftp.sendmail.org/snapshots/sendmail.8.18.0.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 36 | ulogd.spec | ulogd | `http://ftp.netfilter.org/pub/ulogd/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 37 | util-macros.spec | util-macros | `http://ftp.x.org/pub/individual/util/%{name}-%{version}.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 38 | xorg-applications.spec | xorg-applications | `http://ftp.x.org/pub/individual/app/bdftopcf-1.1.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 39 | xorg-fonts.spec | xorg-fonts | `http://ftp.x.org/pub/individual/font/encodings-1.0.4.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 40 | xtrans.spec | xtrans | `https://ftp.x.org/pub/individual/lib/xtrans-1.4.0.tar.bz2` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | dnsmasq.spec | dnsmasq | Warning: dnsmasq.spec Source0 version 2.92rel2 is higher than detected latest version 2.93 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | dtb-raspberrypi.spec | dtb-raspberrypi | Warning: dtb-raspberrypi.spec Source0 version 5.10.4.2021.01.07 is higher than detected latest version 1.20230405 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | etcd.spec | etcd | Warning: etcd.spec Source0 version 3.5.30 is higher than detected latest version 0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | gst-plugins-bad.spec | gst-plugins-bad | Warning: gst-plugins-bad.spec Source0 version 1.26.11 is higher than detected latest version 1.19.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.10.1alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 20201005 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | linux.spec | linux | Warning: linux.spec Source0 version 5.10.258-acvp} is higher than detected latest version 5.10.258 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.18 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | nasm.spec | nasm | Warning: nasm.spec Source0 version 2.16.01 is higher than detected latest version 2.09.09 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | netmgmt.spec | netmgmt | Warning: netmgmt.spec Source0 version 1.2.0 is higher than detected latest version 1.0.4 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 1 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | socat.spec | socat | Warning: socat.spec Source0 version 2.0.0.b9 is higher than detected latest version 1.8.1.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | subversion.spec | subversion | Warning: subversion.spec Source0 version 1.14.2 is higher than detected latest version 0.13.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 16 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 17 | tmux.spec | tmux | Warning: tmux.spec Source0 version 3.1b is higher than detected latest version 3.6 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 18 | urw-fonts.spec | urw-fonts | Warning: urw-fonts.spec Source0 version 1.0.7pre44 is higher than detected latest version 1.0.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | ddclient.spec | ddclient | `https://github.com/ddclient/ddclient/releases/download/v3.9.0/ddclient-3.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | docker.spec | docker | `https://github.com/moby/moby/archive/refs/tags/docker-v24.0.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | erlang.spec | erlang | `https://github.com/erlang/otp/archive/refs/tags/OTP-27.3.4.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | eventlog.spec | eventlog | `https://www.balabit.com/downloads/files/eventlog/0.2/eventlog_0.2.12.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | fail2ban.spec | fail2ban | `https://github.com/fail2ban/fail2ban/archive/refs/tags/1.0.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | fribidi.spec | fribidi | `https://github.com/fribidi/fribidi/archive/refs/tags/v1.0.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | git-lfs.spec | git-lfs | `https://github.com/git-lfs/git-lfs/archive/refs/tags/v3.2.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | git.spec | git | `https://www.kernel.org/pub/software/scm/git/git-2.43.7.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | json_spirit.spec | json_spirit | `https://www.codeproject.com/KB/recipes/JSON_Spirit/json_spirit_v4.08.zip` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | kafka.spec | kafka | `https://github.com/apache/kafka/archive/refs/tags/3.9.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | lasso.spec | lasso | `https://dev.entrouvert.org/lasso/lasso-2.9.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | liblogging.spec | liblogging | `https://github.com/rsyslog/liblogging/archive/refs/tags/v1.0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | libnetfilter_cthelper.spec | libnetfilter_cthelper | `https://www.netfilter.org/projects/libnetfilter_cthelper/files/libnetfilter_cthelper-1.0.0.tar.bz2` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | librdkafka.spec | librdkafka | `https://github.com/confluentinc/librdkafka/archive/refs/tags/v1.5.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | libteam.spec | libteam | `https://github.com/jpirko/libteam/archive/refs/tags/v1.31.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | lzo.spec | lzo | `https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | netkit-telnet.spec | netkit-telnet | `https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/0.17/netkit-telnet-debian-0.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | open-isns.spec | open-isns | `https://github.com/open-iscsi/open-isns/archive/refs/tags/v0.101.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | open-vm-tools.spec | open-vm-tools | `https://github.com/vmware/open-vm-tools/archive/refs/tags/stable-13.0.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | perftest.spec | perftest | `https://github.com/linux-rdma/perftest/archive/refs/tags/4.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | perl-CGI.spec | perl-CGI | `https://github.com/leejo/CGI.pm/archive/refs/tags/v4.50.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | perl-IPC-Run.spec | perl-IPC-Run | `https://metacpan.org/pod/IPC::Run` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | pgaudit13.spec | pgaudit | `https://github.com/pgaudit/pgaudit/archive/refs/tags/1.5.1.5.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | photon-os-container-builder.spec | photon-os-container-builder | `https://github.com/vmware-samples/photon-os-container-builder/archive/refs/tags/v0.1.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | protobuf-c.spec | protobuf-c | `https://github.com/protobuf-c/protobuf-c/archive/refs/tags/v1.5.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | pycurl.spec | pycurl | `https://github.com/pycurl/pycurl/archive/refs/tags/REL_7.43.0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | rpm.spec | rpm | `https://github.com/rpm-software-management/rpm/archive/refs/tags/rpm-4.16.1.3-release.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | runc.spec | runc | `https://github.com/opencontainers/runc/archive/refs/tags/v1.2.9.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | sysdig.spec | sysdig | `https://github.com/draios/sysdig/archive/refs/tags/0.34.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 33 | sysstat.spec | sysstat | `https://github.com/sysstat/sysstat/archive/refs/tags/v12.7.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 34 | tiptop.spec | tiptop | `https://files.inria.fr/pacap/tiptop/tiptop-2.3.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 35 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2023c.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 36 | u-boot.spec | u-boot | `https://github.com/u-boot/u-boot/archive/refs/tags/v2020.07.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | ModemManager.spec | ModemManager | 1.24.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | apparmor.spec | apparmor | 4.1.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | bridge-utils.spec | bridge-utils | 1.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | clang.spec | clang | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | dbus-python.spec | dbus-python | 1.4.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | dos2unix.spec | dos2unix | 7.5.6 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | expat.spec | expat | 20000512 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | fontconfig.spec | fontconfig | 2.18.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | govmomi.spec | govmomi | 0.54.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | icu.spec | icu | 78.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | iputils.spec | iputils | 20250605 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | kexec-tools.spec | kexec-tools | 20080324 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | leveldb.spec | leveldb | 1.23 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | libcap.spec | libcap | 20071031 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | libdrm.spec | libdrm | 200-0-1-20020822 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | libfastjson.spec | libfastjson | 1.2304.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | libslirp.spec | libslirp | 2.5.20200525 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | lldb.spec | lldb | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | llvm.spec | llvm | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | mesa.spec | mesa | 20090313 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | mm-common.spec | mm-common | 1.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | mozjs.spec | mozjs | 151.0.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | ncurses.spec | ncurses | 6.6.20260530 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | nss.spec | nss | 3.124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | pgaudit14.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | pgaudit15.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 36 | pixman.spec | pixman | 0.46.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 37 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 38 | pth.spec | pth | 23.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 39 | python-filelock.spec | python-filelock | 3.29.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 40 | python-pyvmomi.spec | python-pyvmomi | 9.1.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 41 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 42 | spirv-headers.spec | spirv-headers | 1.5.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 43 | spirv-tools.spec | spirv-tools | 2026.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 44 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 45 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 46 | vulkan-tools.spec | vulkan-tools | 1.4.352 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 47 | wayland-protocols.spec | wayland-protocols | 1.48 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | bluez-tools.spec | bluez-tools | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 2 | c-rest-engine.spec | c-rest-engine | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 3 | cloud-network-setup.spec | cloud-network-setup | 200 | 0.2.3 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 4 | copenapi.spec | copenapi | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 5 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 6 | cve-check-tool.spec | cve-check-tool | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 7 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 8 | http-parser.spec | http-parser | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 9 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 10 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 11 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 12 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 13 | python-argparse.spec | python-argparse | 200 | 140 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 14 | python-atomicwrites.spec | python-atomicwrites | 200 | 1.4.1 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 15 | python-ipaddr.spec | python-ipaddr | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 16 | python-lockfile.spec | python-lockfile | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 17 | python-pycodestyle.spec | python-pycodestyle | 200 | 2.14.0 | Warning: duplicate of python-pam.spec | This spec may be a duplicate. Consider consolidating with the referenced spec. |
| 18 | sqlite2.spec | sqlite2 | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |

