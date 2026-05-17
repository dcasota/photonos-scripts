# PRN incomplete-entry analysis — photon-5.0 (normal SPECS/, excluding SPECS/91)

**Source PRN:** `photonos-urlhealth-5.0_202605171536.prn` (PS-side, 2026-05-17 15:36 UTC, run 25991871716).

**Scope:** rows from `SPECS/<package>/<package>.spec` (the default subrelease layout). Rows from `SPECS/91/` are partitioned to a separate doc (`photon-5.0-SPECS-91.md`) and excluded here. Partitioning rule: row is in this doc iff its `warning` does not contain `subrelease 91` and `UrlHealth` is not literal `pinned`.

**Total rows in 5.0 PRN:** 1,113
**SPECS/91 rows (split out):** 16
**Normal rows (this doc):** 1,097
  - Complete: **682** (62%)
  - Archived: 1
  - Incomplete: **414** (38%)

## Root-cause categories

| Category | Count |
|---|---|
| `no_update_url` | 232 |
| `warn_packaging_format` ("Manufacturer may changed version packaging format") | 76 |
| `no_sha` | 36 |
| `no_update_available` | 35 |
| `info_vmware_internal` | 16 |
| `warn_unmaintained` | 11 |
| `warn_cannot_correlate_tags` | 4 |
| `warn_source0_invalid` | 3 |
| `warn_duplicate_of` | 1 |

## Drill-down

### `no_update_url` (232) by host

| Subcount | Host | Sample specs |
|---|---|---|
| 48 | github.com | argon2, backward-cpp, calico-bgp-daemon, calico-libnetwork, ... +44 |
| 46 | rubygems | rubygem-builder, rubygem-declarative, rubygem-dig_rb, rubygem-digest-crc, ... +42 |
| 22 | cpan/metacpan | perl-Canary-Stability, perl-common-sense, perl-Config-IniFiles, perl-Data-Validate-IP, ... +18 |
| 19 | (no-host) | calico-bird, containers-common, iputils, libfastjson, ... +15 |
| 16 | sourceforge | cppunit, docbook-xsl, expect, hdparm, ... +12 |
| 14 | pypi/pythonhosted | python-appdirs, python-backports_abc, python-boto, python-hatchling, ... +10 |
| 8 | kernel.org | blktrace, bridge-utils, ipvsadm, kmod, ... +4 |
| 7 | ftp.postgresql.org | postgresql10/13/14/15, ... +3 |
| 6 | x.org/freedesktop | dbus, gst-plugins-bad, lshw, pkg-config, ... +2 |
| 5 | repmgr.org | repmgr13/14/15/16/17 |
| 4 | archive.apache.org | apache-tomcat10, apache-tomcat9, apr-util, commons-httpclient |
| 4 | *.gnu.org | autogen, bison, gcc, libunwind |
| 3 | ftp.gnome.org | atk, GConf, gnome-common |
| 3 | sourceware.org | bzip2, debugedit, elfutils |
| 3 | releases.pagure.org | libaio, mlocate, rpmdevtools |
| 2 | www.netfilter.org | ebtables, libnfnetlink |
| 23 | one-offs | asciidoc3, duktape, go, intltool, libgssglue, libmspack, ltrace, mc, mpfr, password-store, squid, strace, xerces-c, zsh, ... |

### `warn_packaging_format` (76) by host

| Subcount | Host | Sample specs |
|---|---|---|
| 27 | github.com | clang, cronie, efivar, glog, ... +23 |
| 24 | x.org/freedesktop | dbus-python, fontconfig, kbd, libdrm, ... +20 |
| 5 | sourceforge | expat, libtirpc, rng-tools, scons, ... +1 |
| 3 | (no-host) | lxcfs, python-configparser, python-pyparsing |
| 3 | cpan/metacpan | perl-IPC-Run, perl-List-MoreUtils, perl-URI |
| 2 | kernel.org | kexec-tools, libcap |
| 2 | ftp.mozilla.org | mozjs, nss |
| 2 | pypi/pythonhosted | python-filelock, python-more-itertools |
| 8 | one-offs | libxml2, mesa, mm-common, ncurses, openssh, popt, qemu, unixODBC |

### `no_sha` (36) by URL host

| Subcount | Host | Sample specs |
|---|---|---|
| 14 | sourceforge | atftp, cpulimit, e2fsprogs, gnu-efi, ... +10 |
| 10 | kernel.org | autofs, ethtool, fio, i2c-tools, ... +6 |
| 8 | gitlab.* | cairo, libmbim, libqmi, libX11, ... +4 |
| 4 | one-offs | cmocka, libmd, python-pygobject, wayland-protocols |

### `no_update_available` (35) by Source0 host

| Subcount | Host | Sample specs |
|---|---|---|
| 6 | (no-host) | filesystem, hyper-v, nftables, open-sans-fonts, ... +2 |
| 5 | github.com | apache-maven, chromium, erlang, libclc, ... +1 |
| 4 | x.org/freedesktop | gstreamer-plugins-base, libbsd, netkit-telnet, xorg-applications |
| 4 | www.netfilter.org | iptables, libnetfilter_cthelper, libnetfilter_cttimeout, libnetfilter_queue |
| 3 | sourceforge | cscope, gptfdisk, log4cpp |
| 3 | pypi/pythonhosted | python-docutils, python-setuptools_scm, python-zope.event |
| 10 | one-offs | dwarves, eventlog, fakeroot, iotop, lasso, libdaemon, libmnl, lzo, nmap, repmgr18 |

## Comparison vs photon-4.0

| Metric | 4.0 | 5.0 normal |
|---|---|---|
| Total | 1,034 | 1,097 |
| Complete | 705 (68%) | 682 (62%) |
| `no_update_url` | 141 | 232 |
| `warn_packaging_format` | 77 | 76 |
| `no_sha` | 37 | 36 |
| `no_update_available` | 30 | 35 |

**5.0 has more total packages** but **fewer in absolute "complete" terms** — driven primarily by a doubled `no_update_url` count (141 → 232, +91 specs). Largest deltas:

- **+18 GitHub** (30 → 48) — more new specs use GitHub Source0 without matching lookup-table rewrite
- **+28 RubyGems** (18 → 46) — significant Ruby spec inflow with no upstream-version handler
- **+13 CPAN** (9 → 22) — Perl spec inflow
- **+11 PyPI/pythonhosted** (3 → 14)
- **+1-3 each** across SourceForge, postgresql, x.org

## Actionable cleanup buckets

| Fix once → unlocks N rows (5.0 normal) | What |
|---|---|
| GitHub `archive/refs/tags` template fix | ~48 specs |
| RubyGems update template | ~46 specs |
| CPAN MetaCPAN release pattern | ~22 specs |
| X.Org `pub/individual/lib/` template + packaging-format aliases | ~30 specs (cats 1+2) |
| SourceForge `/projects/<p>/files/<a>` rewrite | ~35 specs (cats 1+3) |
| PyPI/pythonhosted host handling | ~17 specs |

These same five fixes also account for the bulk of 4.0's incompletes. Source0Lookup is shared across branches, so fixing once benefits all.
