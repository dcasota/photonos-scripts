# PRN incomplete-entry analysis — photon-4.0

**Source PRN:** `photonos-urlhealth-4.0_202605171523.prn` (PS-side, 2026-05-17 15:23 UTC, run 25991871716).

**Total data rows:** 1,034
**Complete:** 705 (68%)
**Archived:** 1 (out of scope)
**Incomplete:** 328 (32%)

## Root-cause categories

| Category | Count | Definition |
|---|---|---|
| `no_update_url` — tag detected, no URL constructed | 141 | PS found a newer version, but couldn't re-substitute `%{version}` into the Source0 template to produce a valid `UpdateURL`. |
| "Manufacturer may changed version packaging format" | 77 | URL rewrite produced a candidate URL, but its HEAD probe returned non-200. Upstream renamed the archive or moved its path. |
| `no_sha` — URL set, hash missing | 37 | URL accepted HEAD but the body download/sha512 step failed (timeout, mirror redirect, server-side gating). |
| `no_update_available` — no tags found at all | 30 | Tag detection ran but returned 0 results (or never ran because Source0 had no host). |
| Info: VMware internal URL | 14 | Source0 points at `packages.broadcom.com/photon/photon_sources/...` — by design, no external upstream to probe. |
| Repo isn't maintained anymore | 14 | Explicit marker in the lookup table for abandoned upstreams. Diagnostic, not a bug. |
| Source0 seems invalid | 6 | Source0 is a bare filename like `%{name}-%{version}.tar.gz` with no URL — nothing to probe. |
| Cannot detect correlating tags | 5 | Tag list returned values, but none matched the expected version pattern (custom regex or replace-prefix didn't catch). |
| Duplicate spec | 1 | `python-pycodestyle.spec` flagged as duplicate of `python-pam.spec`. |
| UrlHealth 404 | 1 | Source0 itself is now a dead link. |

## Drill-down per category

### Category 1 — `no_update_url` (141)

By host pattern:

| Subcount | Pattern | Sample specs |
|---|---|---|
| 30 | GitHub (no clean `archive/refs/tags` rewrite) | `cereal`, `cgroup-utils`, `check`, `cpulimit`, `dbxtool`, +25 |
| 22 | Unparseable / bare Source0 | `argon2`, `calico-bgp-daemon`, `calico-bird`, `containers-common`, +18 |
| 18 | RubyGems (no rewrite template) | `rubygem-dig_rb`, `rubygem-fluent-plugin-remote_syslog`, +16 |
| 13 | SourceForge | `cppunit`, `dejavu-fonts`, `docbook-xsl`, `expect`, `fakeroot-ng`, +8 |
| 9 | CPAN/MetaCPAN | `perl-Canary-Stability`, `perl-common-sense`, `perl-Config-IniFiles`, +6 |
| 5 | x.org / freedesktop | `gst-plugins-bad`, `lshw`, `pkg-config`, `proto`, `xorg-fonts` |
| 4 | apache.org | `apache-tomcat9`, `apr-util`, `commons-httpclient`, `xml-security-c` |
| 4 | postgresql.org | `postgresql10/13/14/15` |
| 4 | files.pythonhosted.org | `python-boto`, `python-jinja2`, `python-semantic-version`, `python-sphinxcontrib-jsmath` |
| 4 | ftp.gnu.org | `autogen`, `gcc-12`, `gcc-aarch64-linux-gnu`, `gcc` |
| 3 | kernel.org | `ipvsadm`, `linux`, `syslinux` |
| 3 | PyPI | `python-appdirs`, `python-backports_abc`, `python-msgpack` |
| 22 | one-offs | `bzip2`, `e-cap`, `ImageMagick`, `intltool`, `mpfr`, ... |

### Category 2 — Packaging-format warning (77)

By host:

| Subcount | Host | Sample specs |
|---|---|---|
| 22 | github.com | `clang`, `cronie`, `efivar`, `glog`, +18 |
| 18 | ftp.x.org | `font-util`, `libfontenc`, `libpciaccess`, `libXau`, +14 |
| 6 | bare Source0 | `iputils`, `libfastjson`, `lxcfs`, `perftest`, +2 |
| 3 | downloads.sourceforge.net | `libtirpc`, `scons`, `tcl` |
| 2 | freedesktop.org | `fontconfig`, `ModemManager` |
| 2 | kernel.org | `kexec-tools`, `libcap` |
| 2 | releases.llvm.org | `lldb`, `llvm` |
| 2 | ftp.mozilla.org | `mozjs`, `nss` |
| 2 | cpan.metacpan.org | `perl-List-MoreUtils`, `perl-URI` |
| 2 | files.pythonhosted.org | `python-filelock`, `python-more-itertools` |
| others | ... | `apparmor`, `expat`, `bridge-utils`, ... |

### Category 3 — `no_sha` (37)

By URL host:

| Subcount | Host | Sample specs |
|---|---|---|
| 9 | gitlab.freedesktop.org | `cairo`, `libmbim`, `libqmi`, `libX11`, ... |
| 8 | git.kernel.org | `blktrace`, `ethtool`, `fio`, `i2c-tools`, ... |
| 8 | downloads.sourceforge.net | `hdparm`, `ivykis`, `libusb`, `nfs-utils`, ... |
| 5 | sourceforge.net | `atftp`, `openipmi`, `procps-ng`, `tboot`, ... |
| 2 | prdownloads.sourceforge.net | `e2fsprogs`, `psmisc` |
| 5 | one-offs | `autofs`, `cmocka`, `libaio`, `python-pygobject`, `wayland-protocols` |

### Category 4 — `no_update_available` (30)

By Source0 host:

| Subcount | Host | Sample specs |
|---|---|---|
| 6 | bare Source0 (no host) | `cscope`, `log4cpp`, `open-sans-fonts`, `perl-IPC-Run`, ... |
| 5 | github.com (API hit rate-limited or repo gone) | `apache-maven`, `chromium`, `erlang`, `libevent`, ... |
| 4 | netfilter.org (non-standard release pattern) | `iptables`, `libnetfilter_cthelper`, `libnetfilter_cttimeout`, `libnetfilter_queue` |
| 15 | one-offs | `dwarves`, `eventlog`, `gptfdisk`, `gstreamer-plugins-base`, `lasso`, `libdaemon`, `lzo`, `nmap`, ... |

## Cross-cutting observations

- **GitHub archive-URL synthesis** accounts for the largest single block of failures: **52 specs** (30 in cat 1 + 22 in cat 2) where the lookup-table substitution from PS's Source0Lookup didn't yield a working `archive/refs/tags/<tag>.tar.gz` URL.
- **X.Org / freedesktop** forms a coherent block (~30 specs across cats 1+2+3): the `https://ftp.x.org/pub/individual/lib/` layout has moved files and the lookup hasn't been updated.
- **SourceForge** appears in 4 categories (~28 specs total): the platform redirects multiple ways (`prdownloads.`, `downloads.`, `sourceforge.net/projects/<p>/files/...`), and rewrite templates often don't survive a version bump.
- **22 specs** under "no_update_url / unparseable" have bare `%{name}-%{version}.tar.gz` Source0 — intentional internal builds (calico, c-rest-engine, etc.) overlapping with the unmaintained / VMware-internal categories.

## Actionable cleanup buckets (by leverage)

| Fix once → unlocks N rows | What |
|---|---|
| Update GitHub `archive/refs/tags` template in Source0Lookup | ~30-50 specs |
| Update X.Org `pub/individual/lib/` template | ~30 specs |
| Add SourceForge `/projects/<p>/files/<a>` rewrite logic | ~28 specs |
| Add RubyGems update template (`https://rubygems.org/gems/<n>-<v>.gem`) | 18 specs |
| Add CPAN MetaCPAN release pattern | 9 specs |
| Apache release-mirror handling | 4 specs |

Cleaning up just GitHub + X.Org + SourceForge would push photon-4.0's complete-rate from **68% → ~76%**.
