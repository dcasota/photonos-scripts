# Photon OS URL Health Issues - branch 5.0

**Source file:** photonos-urlhealth-5.0_202606210533.prn

**Total packages analyzed:** 1761

**Total packages with issues:** 123

**Vendor-pinned subrelease (frozen for a Photon sub-release) — informational, not an issue:** 718

**VMware-internal Source0 URL (not publicly resolvable) — informational, not an issue:** 15

## Summary

| # | Issue Category | Count | Severity |
|---|---|---|---|
| 1 | Source URL blank / macro unresolved (UrlHealth=blank) | 2 | High |
| 2 | URL substitution unfinished | 1 | High |
| 3 | Source URL unreachable (UrlHealth=0) | 3 | High |
| 5 | Version comparison anomaly (UpdateAvailable contains Warning) | 18 | Medium |
| 6 | Source healthy (UrlHealth=200) but UpdateAvailable and UpdateURL blank | 32 | Medium |
| 7 | Update version detected but UpdateURL/HealthUpdateURL blank (packaging format changed) | 34 | Medium |
| 8 | Other warnings (VMware internal URL, unmaintained repo, etc.) | 33 | Low-Medium |

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
| 1 | log4cplus.spec | log4cplus | `https://github.com/log4cplus/log4cplus/releases/download/%{release_tag}/%{name}-` | `` | Fix the Source0 URL pattern. The version/name substitution is incomplete -- check for nested or malformed macros. |

---

## 3. Source URL Unreachable (UrlHealth=0)

| # | Spec | Name | Modified Source0 | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | 7zip.spec | 7zip | `%{name}-%{version}.tar.gz` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 2 | cdrkit.spec | cdrkit | `http://gd.tuwien.ac.at/utils/schilling/cdrtoolscdrkit-1.1.11.tar.gz` | Warning: Source0 seems invalid and no other Official source has been found. | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |
| 3 | filesystem.spec | filesystem | `clock` |  | URL is unreachable. Check if the domain/host is still active. Find an alternative mirror or upstream source. |

---

## 5. Version Comparison Anomaly

| # | Spec | Name | Version Warning | Fix Suggestion |
|---|---|---|---|---|
| 1 | apparmor.spec | apparmor | Warning: apparmor.spec Source0 version 4.1.6 is higher than detected latest version 4.1.0 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 2 | containers-common.spec | containers-common | Warning: containers-common.spec Source0 version 4 is higher than detected latest version 1.0.1 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 3 | dnsmasq.spec | dnsmasq | Warning: dnsmasq.spec Source0 version 2.92rel2 is higher than detected latest version 2.93 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 4 | dracut.spec | dracut | Warning: dracut.spec Source0 version 109 is higher than detected latest version 059 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 5 | fribidi.spec | fribidi | Warning: fribidi.spec Source0 version 1.0.12 is higher than detected latest version 0.19.5 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 6 | fuse-overlayfs-snapshotter.spec | fuse-overlayfs-snapshotter | Warning: fuse-overlayfs-snapshotter.spec Source0 version 2.1.7 is higher than detected latest version 1.17 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 7 | ibmtpm.spec | ibmtpm | Warning: ibmtpm.spec Source0 version 20240802.183 is higher than detected latest version 2024-08-02 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 8 | libmspack.spec | libmspack | Warning: libmspack.spec Source0 version 0.11alpha is higher than detected latest version 1.11 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 9 | linux-esx.spec | linux | Warning: linux-esx.spec Source0 version 6.12.92 is higher than detected latest version 6.1.176 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 10 | linux.spec | linux | Warning: linux.spec Source0 version 6.12.92-acvp} is higher than detected latest version 6.1.176 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 11 | lshw.spec | lshw | Warning: lshw.spec Source0 version B.02.20 is higher than detected latest version 02.20 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 12 | mdadm.spec | mdadm | Warning: mdadm.spec Source0 version 4.6 is higher than detected latest version 4.4 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 13 | pcstat.spec | pcstat | Warning: pcstat.spec Source0 version 2.0 is higher than detected latest version 0.0.2 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 14 | perl-libintl.spec | perl-libintl | Warning: perl-libintl.spec Source0 version 1.37 is higher than detected latest version 1.36 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 15 | proto.spec | proto | Warning: proto.spec Source0 version 7.7 is higher than detected latest version 7.0.31 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 16 | re2.spec | re2 | Warning: re2.spec Source0 version 20220601 is higher than detected latest version 2025-11-05 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 17 | syslinux.spec | syslinux | Warning: syslinux.spec Source0 version 6.04 is higher than detected latest version 6.03 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |
| 18 | systemd.spec | systemd | Warning: systemd.spec Source0 version 257.13 is higher than detected latest version 256 . | Version comparison heuristic may be confused by version format (date-based, alpha suffixes, etc.). Verify manually. |

---

## 6. Source Healthy but No Update Info (UrlHealth=200, UpdateAvailable=blank)

| # | Spec | Name | Modified Source0 | Fix Suggestion |
|---|---|---|---|---|
| 1 | WALinuxAgent.spec | WALinuxAgent | `https://github.com/Azure/WALinuxAgent/archive/refs/tags/v2.15.0.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 2 | abseil-cpp.spec | abseil-cpp | `https://github.com/abseil/abseil-cpp/releases/download/20230125.3/abseil-cpp-20230125.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 3 | docker-compose.spec | docker-compose | `https://github.com/docker/compose/archive/refs/tags/v5.1.4.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 4 | dovecot-pigeonhole.spec | dovecot-pigeonhole | `https://pigeonhole.dovecot.org/releases/2.3/dovecot-2.3-pigeonhole-0.5.21.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 5 | dovecot.spec | dovecot | `https://dovecot.org/releases/2.3/dovecot-2.3.21.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 6 | doxygen.spec | doxygen | `https://github.com/doxygen/doxygen/archive/refs/tags/Release_1.9.5.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 7 | expat.spec | expat | `https://github.com/libexpat/libexpat/releases/download/R_2.8.1/expat-2.8.1.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 8 | fuse3.spec | fuse3 | `https://github.com/libfuse/libfuse/releases/download/fuse-3.3.18.2/fuse-3.3.18.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 9 | gdk-pixbuf.spec | gdk-pixbuf | `https://github.com/GNOME/gdk-pixbuf/archive/refs/tags/2.42.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 10 | ipcalc.spec | ipcalc | `https://gitlab.com/ipcalc/ipcalc/-/archive/1.0.2/ipcalc-1.0.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 11 | iptraf-ng.spec | iptraf-ng | `https://github.com/iptraf-ng/iptraf-ng/archive/refs/tags/v1.2.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 12 | isa-l.spec | isa-l | `https://github.com/intel/isa-l/archive/refs/tags/v2.31.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 13 | libbsd.spec | libbsd | `https://libbsd.freedesktop.org/releases/libbsd-0.12.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 14 | libcap-ng.spec | libcap-ng | `https://github.com/stevegrubb/libcap-ng/archive/refs/tags/v0.8.3.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 15 | libdisplay-info.spec | libdisplay-info | `https://gitlab.freedesktop.org/emersion/libdisplay-info/-/archive/0.3.0/libdisplay-info-0.3.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 16 | libfastjson.spec | libfastjson | `https://github.com/rsyslog/libfastjson/archive/refs/tags/v1.2304.0.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 17 | libgudev.spec | libgudev | `https://github.com/GNOME/libgudev/archive/refs/tags/237.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 18 | libnss-ato.spec | libnss-ato | `https://github.com/donapieppo/libnss-ato/archive/refs/tags/v20240514.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 19 | log4cpp.spec | log4cpp | `https://netix.dl.sourceforge.net/project/log4cpp/log4cpp-1.1.x%20%28new%29/log4cpp-1.1/log4cpp-1.1.6` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 20 | man-db.spec | man-db | `https://gitlab.com/man-db/man-db/-/archive/2.11.1/man-db-2.11.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 21 | mpfr.spec | mpfr | `http://www.mpfr.org/mpfr-4.2.2/mpfr-4.2.2.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 22 | ndctl.spec | ndctl | `https://github.com/pmem/ndctl/archive/refs/tags/v74.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 23 | open-sans-fonts.spec | open-sans-fonts | `https://ftp.debian.org/debian/pool/main/f/fonts-open-sans/fonts-open-sans_1.10.orig.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 24 | openjdk25.spec | openjdk | `https://github.com/openjdk/jdk25u/archive/refs/tags/jdk-25.0.2-ga.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 25 | pgbouncer.spec | pgbouncer | `https://github.com/pgbouncer/pgbouncer/archive/refs/tags/pgbouncer_1.17.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 26 | python3-gcovr.spec | python3-gcovr | `https://github.com/gcovr/gcovr/archive/refs/tags/5.2.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 27 | python3-hatchling.spec | python3-hatchling | `https://github.com/pypa/hatch/releases/download/hatchling-v1.29.0/hatchling-1.29.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 28 | rsyslog.spec | rsyslog | `https://github.com/rsyslog/rsyslog/archive/refs/tags/v8.2602.0.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 29 | rust.spec | rust | `https://github.com/rust-lang/rust/archive/refs/tags/1.93.1.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 30 | shadow.spec | shadow | `https://github.com/shadow-maint/shadow/archive/refs/tags/4.13.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 31 | tzdata.spec | tzdata | `https://data.iana.org/time-zones/releases/tzdata2024b.tar.gz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |
| 32 | usbutils.spec | usbutils | `https://www.kernel.org/pub/linux/utils/usb/usbutils/usbutils-015.tar.xz` | Source URL works but update detection found no newer version. May be correct or the version detection pattern does not match upstream release naming. Verify manually. |

---

## 7. Update Version Detected but Update URL Not Constructed (Packaging Format Changed)

| # | Spec | Name | Update Available | Warning | Fix Suggestion |
|---|---|---|---|---|---|
| 1 | cronie.spec | cronie | 4.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 2 | dos2unix.spec | dos2unix | 7.5.6 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 3 | efivar.spec | efivar | 39 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 4 | fontconfig.spec | fontconfig | 2.18.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 5 | glog.spec | glog | 0.7.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 6 | govmomi.spec | govmomi | 0.54.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 7 | kbd.spec | kbd | 2.10.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 8 | libtirpc.spec | libtirpc | 1-3-7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 9 | libunwind.spec | libunwind | 4.0.10 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 10 | libxml2.spec | libxml2 | 7.3 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 11 | lxcfs.spec | lxcfs | 7.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 12 | mm-common.spec | mm-common | 1.0.7 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 13 | mozjs.spec | mozjs | 152.0.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 14 | ncurses.spec | ncurses | 6.6.20260620 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 15 | nss.spec | nss | 3.125 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 16 | open-vm-tools.spec | open-vm-tools | 2013.09.16-1328054 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 17 | openssh.spec | openssh | .9.9.P2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 18 | perl-List-MoreUtils.spec | perl-List-MoreUtils | 1.400.002 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 19 | perl-URI.spec | perl-URI | 5.36 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 20 | pgaudit16.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 21 | pgaudit17.spec | pgaudit | 18.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 22 | polkit.spec | polkit | 124 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 23 | popt.spec | popt | 1.19- | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 24 | python-google-auth.spec | python-google-auth | 1946 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 25 | python-pyvmomi.spec | python-pyvmomi | 9.1.0.0 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 26 | python-vcs-versioning.spec | python-vcs-versioning | 9.2.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 27 | qemu.spec | qemu | /9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 28 | scons.spec | scons | 4.10.1 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 29 | spirv-headers.spec | spirv-headers | 1.5.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 30 | spirv-tools.spec | spirv-tools | 2026.2 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 31 | tcl.spec | tcl | 9.0.4 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 32 | unixODBC.spec | unixODBC | 2.3.14 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 33 | vulkan-tools.spec | vulkan-tools | 1.4.354 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |
| 34 | wayland-protocols.spec | wayland-protocols | 1.49 | Warning: Manufacturer may changed version packaging format. | Upstream changed version/packaging format. Update the Source0 URL pattern in the spec to match the new release naming convention. |

---

## 8. Other Warnings

| # | Spec | Name | UrlHealth | UpdateAvailable | Warning | Fix Suggestion |
|---|---|---|---|---|---|---|
| 1 | alternatives.spec | alternatives | 404 | 1.33 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 2 | cloud-network-setup.spec | cloud-network-setup | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 3 | crash.spec | crash | 200 | 9.0.2 | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 4 | heapster.spec | heapster | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 5 | http-parser.spec | http-parser | 200 | (same version) | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 6 | icu.spec | icu | 200 | 78.3 | Info: Packaging format .tgz has changed to .zip | Review warning and take appropriate action. |
| 7 | kubernetes-dashboard.spec | kubernetes-dashboard | 200 | 7.14.0 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 8 | libXScrnSaver.spec | libXScrnSaver | 200 | 1.2.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 9 | libXau.spec | libXau | 200 | 1.0.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 10 | libXcomposite.spec | libXcomposite | 200 | 0.4.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 11 | libXdamage.spec | libXdamage | 200 | 1.1.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 12 | libXdmcp.spec | libXdmcp | 200 | 1.1.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 13 | libXext.spec | libXext | 200 | 1.3.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 14 | libXfixes.spec | libXfixes | 200 | 6.0.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 15 | libXfont2.spec | libXfont2 | 200 | 2.0.7 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 16 | libXi.spec | libXi | 200 | 1.8.3 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 17 | libXrandr.spec | libXrandr | 200 | 1.5.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 18 | libXrender.spec | libXrender | 200 | 0.9.12 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 19 | libXt.spec | libXt | 200 | 1.3.1 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 20 | libXtst.spec | libXtst | 200 | 1.2.5 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 21 | libdrm.spec | libdrm | 200 | 200-0-1-20020822 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 22 | libfontenc.spec | libfontenc | 200 | 1.1.9 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 23 | libpciaccess.spec | libpciaccess | 200 | 0.19 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |
| 24 | libslirp.spec | libslirp | 200 | 2.5.20200525 | Info: Packaging format .tar.gz has changed to .tar.xz | Review warning and take appropriate action. |
| 25 | libtar.spec | libtar | 200 | (same version) | Warning: repo isn't maintained anymore. See https://sources.debian.org/patches/libtar | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 26 | motd.spec | motd | 200 |  | Warning: Cannot detect correlating tags from the repo provided. | Tag detection failed. Check if upstream uses a different tagging convention. |
| 27 | pcre.spec | pcre | 200 |  | Warning: Source0 seems invalid and no other Official source has been found. | Source0 URL appears invalid and no official source found. Find the correct upstream URL. |
| 28 | python-pycodestyle.spec | python-pycodestyle | 200 | 2.14.0 | Warning: duplicate of python-pam.spec | This spec may be a duplicate. Consider consolidating with the referenced spec. |
| 29 | python-terminaltables.spec | python-terminaltables | 200 | 3.1.10 | Warning: repo isn't maintained anymore. | Upstream repo is no longer maintained. Consider finding a fork, alternative, or mark package as archived. |
| 30 | python3-Pygments.spec | python3-Pygments | 404 | 2.20.0 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 31 | python3-trove-classifiers.spec | python3-trove-classifiers | 404 | 2026.6.1.19 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 32 | python3-wheel.spec | python3-wheel | 404 | 0.47.0 | Warning: Manufacturer may changed version packaging format. | Manufacturer may have changed version packaging format. Verify the download URL pattern still works with current releases. |
| 33 | util-macros.spec | util-macros | 200 | 1.20.2 | Info: Packaging format .tar.bz2 has changed to .tar.xz | Review warning and take appropriate action. |

