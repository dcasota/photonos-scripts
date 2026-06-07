# Photon OS URL Health Issues - branch master

**Source file:** photonos-urlhealth-master_202606071937.prn

**Total packages analyzed:** 1090

**Total packages with issues:** 115

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 15

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 2 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 4 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 12 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 16 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 41 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 40 | Low-Medium |

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
| 3 | nss.spec | nss | `https://ftp.mozilla.org/pub/security/nss/releases/NSS_3_98_RTM/src/nss-3.101.2.tar.gz` | Warning: Manufacturer may changed version packaging format. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 4 | sendmail.spec | sendmail | `https://ftp.sendmail.org/snapshots/sendmail.8.18.0.2.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | dtb-raspberrypi.spec | dtb-raspberrypi | Warning: dtb-raspberrypi.spec Source0 version 6.1.10.2023.02.28 is higher than detected latest version 1.20230405 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | gst-plugins-bad.spec | gst-plugins-bad | Warning: gst-plugins-bad.spec Source0 version 1.21.3 is higher than detected latest version 1.19.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.10.1alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | libnss-ato.spec | libnss-ato | Warning: libnss-ato.spec Source0 version 20240514 is higher than detected latest version 0.2.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | linux.spec | linux | Warning: linux.spec Source0 version 6.1.83-acvp} is higher than detected latest version 6.1.175 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.19 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 1 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | xorg-fonts.spec | xorg-fonts | Warning: xorg-fonts.spec Source0 version 7.7 is higher than detected latest version 1.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | filesystem.spec | filesystem | `http://www.linuxfromscratch.org` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | iotop.spec | iotop | `http://guichaz.free.fr/iotop/files/iotop-0.6.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | lasso.spec | lasso | `https://dev.entrouvert.org/lasso/lasso-2.8.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | libbsd.spec | libbsd | `https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | libdaemon.spec | libdaemon | `https://0pointer.de/lennart/projects/libdaemon/libdaemon-0.14.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.3` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | lzo.spec | lzo | `https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | monitoring-plugins.spec | monitoring-plugins | `https://github.com/monitoring-plugins/monitoring-plugins/archive/refs/tags/v2.3.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | netkit-telnet.spec | netkit-telnet | `https://salsa.debian.org/debian/netkit-telnet/-/archive/debian/0.17/netkit-telnet-debian-0.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | perl-Clone.spec | perl-Clone | `https://cpan.metacpan.org/modules/by-module/Clone/Clone-0.46.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | perl-Data-Dump.spec | perl-Data-Dump | `https://cpan.metacpan.org/modules/by-module/Data/Data-Dump-1.25.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | perl-IPC-Run.spec | perl-IPC-Run | `https://metacpan.org/pod/IPC::Run` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | perl-WWW-Curl.spec | perl-WWW-Curl | `https://github.com/szbalint/WWW--Curl/archive/refs/tags/4.17.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2022g.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | xorg-applications.spec | xorg-applications | `https://www.x.org/archive/individual/util/bdftopcf-7.7.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | ModemManager.spec | ModemManager | 1.24.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | clang.spec | clang | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | dos2unix.spec | dos2unix | 7.5.6 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | expat.spec | expat | 20000512 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | fontconfig.spec | fontconfig | 2.18.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | govmomi.spec | govmomi | 0.54.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | haproxy.spec | haproxy | 3.3.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | iputils.spec | iputils | 20250605 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | kbd.spec | kbd | 2.10.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | kexec-tools.spec | kexec-tools | 20080324 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | libcap.spec | libcap | 20071031 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | libfastjson.spec | libfastjson | 1.2304.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | lldb.spec | lldb | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | llvm.spec | llvm | 22.1.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | mozjs.spec | mozjs | 151.0.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | pgaudit13.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | pgaudit14.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | pgaudit15.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | pgaudit16.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | pth.spec | pth | 23.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | python-filelock.spec | python-filelock | 3.29.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | python-google-auth.spec | python-google-auth | 1946 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 35 | python-pyvmomi.spec | python-pyvmomi | 9.1.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 36 | spirv-headers.spec | spirv-headers | 1.5.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 37 | spirv-tools.spec | spirv-tools | 2026.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 38 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 39 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 40 | vulkan-tools.spec | vulkan-tools | 1.4.353 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 41 | wayland-protocols.spec | wayland-protocols | 1.49 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

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
| 9 | icu.spec | icu | 200 | 78.3 | Info: Packaging format .tgz has changed to .zip | Review warning and take appropriate action. |
| 10 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 11 | libXScrnSaver.spec | libXScrnSaver | 200 | 1.2.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 12 | libXau.spec | libXau | 200 | 1.0.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 13 | libXcomposite.spec | libXcomposite | 200 | 0.4.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 14 | libXdamage.spec | libXdamage | 200 | 1.1.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 15 | libXdmcp.spec | libXdmcp | 200 | 1.1.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 16 | libXext.spec | libXext | 200 | 1.3.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 17 | libXfixes.spec | libXfixes | 200 | 6.0.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 18 | libXfont2.spec | libXfont2 | 200 | 2.0.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 19 | libXi.spec | libXi | 200 | 1.8.3 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 20 | libXrandr.spec | libXrandr | 200 | 1.5.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 21 | libXrender.spec | libXrender | 200 | 0.9.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 22 | libXt.spec | libXt | 200 | 1.3.1 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 23 | libXtst.spec | libXtst | 200 | 1.2.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 24 | libdrm.spec | libdrm | 200 | 200-0-1-20020822 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 25 | libfontenc.spec | libfontenc | 200 | 1.1.9 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 26 | libpciaccess.spec | libpciaccess | 200 | 0.19 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 27 | libslirp.spec | libslirp | 200 | 2.5.20200525 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 28 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 29 | mesa.spec | mesa | 200 | 20090313 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 30 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 31 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 32 | python-argparse.spec | python-argparse | 200 | 140 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 33 | python-atomicwrites.spec | python-atomicwrites | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 34 | python-ipaddr.spec | python-ipaddr | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 35 | python-lockfile.spec | python-lockfile | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 36 | python-pycodestyle.spec | python-pycodestyle | 200 | 2.14.0 | Warning: duplicate of python-pam.spec | This spec may be a duplicate. Consider consolidating with the referenced spec. |
| 37 | python-terminaltables.spec | python-terminaltables | 200 | 3.1.10 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 38 | scons.spec | scons | 404 | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 39 | util-macros.spec | util-macros | 200 | 1.20.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 40 | xtrans.spec | xtrans | 200 | 1.6.0 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |

