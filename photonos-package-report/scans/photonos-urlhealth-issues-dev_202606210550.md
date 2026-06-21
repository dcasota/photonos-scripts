# Photon OS URL Health Issues - branch dev

**Source file:** photonos-urlhealth-dev_202606210550.prn

**Total packages analyzed:** 1090

**Total packages with issues:** 142

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 15

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 2 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 5 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 15 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 44 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 37 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 39 | Low-Medium |

---

## 1. Source URL Blank / Macro Unresolved (UrlHealth=blank)

The Source0 URL contains unexpanded RPM macros or is empty.

| # | Spec | Name | Source0 Original | Fix Suggestion |
|---|---|---|---|---|
| 1 | chromium.spec | chromium | `https://github.com/chromium/chromium/archive/%{name}-%{version}.tar.gz` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |
| 2 | raspberrypi-firmware.spec | raspberrypi-firmware | `%{name}-%{version}.tar.gz` | Verify Source0 URL macro expansion. The %{version} or %{name} macro may not resolve. Provide a direct URL or fix the macro. |

---

## 3. Source URL Unreachable (UrlHealth=0)

| # | Spec | Name | Modified Source0 | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | cdrkit.spec | cdrkit | `http://gd.tuwien.ac.at/utils/schilling/cdrtoolscdrkit-1.1.11.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 2 | finger.spec | finger | `ftp://ftp.uk.linux.org/pub/linux/Networking/netkit/bsd-finger-%{version}.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 3 | libdaemon.spec | libdaemon | `http://0pointer.de/lennart/projects/libdaemon/%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 4 | nss.spec | nss | `https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_98_RTM/src/nss-3.101.2.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 5 | sendmail.spec | sendmail | `https://ftp.sendmail.org/snapshots/sendmail.8.18.0.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | apr-util.spec | apr-util | Warning: apr-util.spec Source0 version 1.6.3 is higher than detected latest version 1.2.12 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | dtb-raspberrypi.spec | dtb-raspberrypi | Warning: dtb-raspberrypi.spec Source0 version 6.1.10.2023.02.28 is higher than detected latest version 1.20230405 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | gst-plugins-bad.spec | gst-plugins-bad | Warning: gst-plugins-bad.spec Source0 version 1.21.3 is higher than detected latest version 1.19.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.10.1alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | libtraceevent.spec | libtraceevent | Warning: libtraceevent.spec Source0 version 1.6.3 is higher than detected latest version 1.5.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | linux.spec | linux | Warning: linux.spec Source0 version 6.1.83-acvp} is higher than detected latest version 6.1.176 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.19 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | termshark.spec | termshark | Warning: termshark.spec Source0 version 2.4.0 is higher than detected latest version 2.0.3 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | tuned.spec | tuned | Warning: tuned.spec Source0 version 2.21.0 is higher than detected latest version 0.1.3 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | unbound.spec | unbound | Warning: unbound.spec Source0 version 1.21.0 is higher than detected latest version 0.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | wireshark.spec | wireshark | Warning: wireshark.spec Source0 version 4.2.7 is higher than detected latest version 2.2.17 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | xorg-fonts.spec | xorg-fonts | Warning: xorg-fonts.spec Source0 version 7.7 is higher than detected latest version 1.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | abseil-cpp.spec | abseil-cpp | `https://github.com/abseil/abseil-cpp/releases/download/20230125.3/abseil-cpp-20230125.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | apache-tomcat.spec | apache-tomcat | `https://github.com/apache/tomcat/archive/refs/tags/10.1.19.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | chrpath.spec | chrpath | `https://codeberg.org/pere/chrpath/archive/release-0.16.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | cmocka.spec | cmocka | `https://git.cryptomilk.org/projects/cmocka.git/snapshot/cmocka-1.1.5.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | cni.spec | cni | `https://github.com/containernetworking/plugins/archive/refs/tags/v1.1.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | cronie.spec | cronie | `https://github.com/cronie-crond/cronie/archive/refs/tags/cronie-1.6.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | docbook-xml.spec | docbook-xml | `https://github.com/docbook/docbook/archive/refs/tags/4.5.zip` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | docker-pycreds.spec | docker-pycreds | `https://github.com/shin-/dockerpy-creds/archive/refs/tags/0.4.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | dwarves.spec | dwarves | `http://fedorapeople.org/~acme/dwarves/dwarves-1.24.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | expat.spec | expat | `https://github.com/libexpat/libexpat/releases/download/R_2.6.0/expat-2.6.0.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | fail2ban.spec | fail2ban | `https://github.com/fail2ban/fail2ban/archive/refs/tags/1.0.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | filesystem.spec | filesystem | `http://www.linuxfromscratch.org` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | google-compute-engine.spec | google-compute-engine | `https://github.com/GoogleCloudPlatform/compute-image-packages/archive/refs/tags/v20191210.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | iana-etc.spec | iana-etc | `https://github.com/Mic92/iana-etc/releases/download/2.30/iana-etc-2.30.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | icu.spec | icu | `https://github.com/unicode-org/icu/releases/download/release-73-1/icu4c-73_1-src.tgz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | json-glib.spec | json-glib | `https://github.com/GNOME/json-glib/archive/refs/tags/1.6.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | kafka.spec | kafka | `https://github.com/apache/kafka/archive/refs/tags/3.4.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | kbd.spec | kbd | `https://github.com/legionus/kbd/archive/refs/tags/2.2.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | libbsd.spec | libbsd | `https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | libmd.spec | libmd | `https://archive.hadrons.org/software/libmd/libmd-1.1.0.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | libnss-ato.spec | libnss-ato | `https://github.com/donapieppo/libnss-ato/archive/refs/tags/v20240514.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | libpcap.spec | libpcap | `https://github.com/the-tcpdump-group/libpcap/archive/refs/tags/libpcap-1.10.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | libxcb.spec | libxcb | `https://gitlab.freedesktop.org/xorg/lib/libxcb/-/archive/libxcb-1.15/libxcb-libxcb-1.15.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | libyang.spec | libyang | `https://github.com/CESNET/libyang/archive/refs/tags/v2.1.55.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | lzo.spec | lzo | `https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | nano.spec | nano | `https://ftpmirror.gnu.org/nano/nano-8.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | netkit-telnet.spec | netkit-telnet | `https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/0.17/netkit-telnet-debian-0.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | nginx-ingress.spec | nginx-ingress | `https://github.com/nginxinc/kubernetes-ingress/archive/refs/tags/v2.4.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | perl-Clone.spec | perl-Clone | `https://cpan.metacpan.org/modules/by-module/Clone/Clone-0.46.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 33 | perl-Data-Dump.spec | perl-Data-Dump | `https://cpan.metacpan.org/modules/by-module/Data/Data-Dump-1.25.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 34 | perl-IPC-Run.spec | perl-IPC-Run | `https://metacpan.org/pod/IPC::Run` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 35 | perl-Object-Accessor.spec | perl-Object-Accessor | `https://github.com/jib/object-accessor/archive/refs/tags/0.48.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 36 | shadow.spec | shadow | `https://github.com/shadow-maint/shadow/archive/refs/tags/4.13.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 37 | shared-mime-info.spec | shared-mime-info | `https://gitlab.freedesktop.org/xdg/shared-mime-info/-/archive/2.2/shared-mime-info-2.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 38 | snoopy.spec | snoopy | `https://github.com/a2o/snoopy/archive/refs/tags/snoopy-2.5.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 39 | syslinux.spec | syslinux | `https://www.kernel.org/pub/linux/utils/boot/syslinux/Testing/6.04/syslinux-6.04-pre1.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 40 | tmux.spec | tmux | `https://github.com/tmux/tmux/archive/refs/tags/3.5.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 41 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2022g.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 42 | xinetd.spec | xinetd | `https://github.com/xinetd-org/xinetd/archive/refs/tags/xinetd-2.3.15.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 43 | xorg-applications.spec | xorg-applications | `https://www.x.org/archive/individual/util/bdftopcf-7.7.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 44 | xz.spec | xz | `https://github.com/tukaani-project/xz/archive/refs/tags/v5.4.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | ModemManager.spec | ModemManager | 1.24.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | aide.spec | aide | 0.14.2. | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | clang.spec | clang | 22.1.8 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | dos2unix.spec | dos2unix | 7.5.6 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | fontconfig.spec | fontconfig | 2.18.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | govmomi.spec | govmomi | 0.54.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | haproxy.spec | haproxy | 3.4.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | iputils.spec | iputils | 20250605 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | libfastjson.spec | libfastjson | 1.2304.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | lldb.spec | lldb | 22.1.8 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | llvm.spec | llvm | 22.1.8 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | mm-common.spec | mm-common | 1.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | mozjs.spec | mozjs | 152.0.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | pgaudit13.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | pgaudit14.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | pgaudit15.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | pgaudit16.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | pth.spec | pth | 23.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | python-google-auth.spec | python-google-auth | 1946 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | python-pyvmomi.spec | python-pyvmomi | 9.1.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | spirv-headers.spec | spirv-headers | 1.5.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | spirv-tools.spec | spirv-tools | 2026.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 36 | vulkan-tools.spec | vulkan-tools | 1.4.354 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 37 | wayland-protocols.spec | wayland-protocols | 1.49 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | bluez-tools.spec | bluez-tools | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 2 | cloud-network-setup.spec | cloud-network-setup | 200 | 0.2.3 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 3 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 4 | cve-check-tool.spec | cve-check-tool | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 5 | dbus-python.spec | dbus-python | 200 | 1.4.0 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 6 | dhcp.spec | dhcp | 200 | (same version) | Warning: repo isn't maintained anymore. See https://www.isc.org/dhcp_migration/ | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 7 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 8 | http-parser.spec | http-parser | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 9 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 10 | libXScrnSaver.spec | libXScrnSaver | 200 | 1.2.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 11 | libXau.spec | libXau | 200 | 1.0.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 12 | libXcomposite.spec | libXcomposite | 200 | 0.4.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 13 | libXdamage.spec | libXdamage | 200 | 1.1.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 14 | libXdmcp.spec | libXdmcp | 200 | 1.1.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 15 | libXext.spec | libXext | 200 | 1.3.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 16 | libXfixes.spec | libXfixes | 200 | 6.0.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 17 | libXfont2.spec | libXfont2 | 200 | 2.0.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 18 | libXi.spec | libXi | 200 | 1.8.3 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 19 | libXrandr.spec | libXrandr | 200 | 1.5.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 20 | libXrender.spec | libXrender | 200 | 0.9.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 21 | libXt.spec | libXt | 200 | 1.3.1 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 22 | libXtst.spec | libXtst | 200 | 1.2.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 23 | libdrm.spec | libdrm | 200 | 200-0-1-20020822 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 24 | libfontenc.spec | libfontenc | 200 | 1.1.9 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 25 | libpciaccess.spec | libpciaccess | 200 | 0.19 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 26 | libslirp.spec | libslirp | 200 | 2.5.20200525 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 27 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 28 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 29 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 30 | pcstat.spec | pcstat | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 31 | python-argparse.spec | python-argparse | 200 | 140 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 32 | python-atomicwrites.spec | python-atomicwrites | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 33 | python-ipaddr.spec | python-ipaddr | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 34 | python-lockfile.spec | python-lockfile | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 35 | python-pycodestyle.spec | python-pycodestyle | 200 | 2.14.0 | Warning: duplicate of python-pam.spec | This spec may be a duplicate. Consider consolidating with the referenced spec. |
| 36 | python-terminaltables.spec | python-terminaltables | 200 | 3.1.10 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 37 | scons.spec | scons | 404 | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 38 | util-macros.spec | util-macros | 200 | 1.20.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 39 | xtrans.spec | xtrans | 200 | 1.6.0 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |

