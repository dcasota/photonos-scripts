# Reference copy of the Python generator that derives runPh7-3-RC4.sh from
# runPh7-2-7.sh. Kept here only as the source for the Rust port described in
# specs/research/2026-09-27-kernel-wrapper-generator.md; paths are the
# maintainer host's (/root/runPh7-2-7.sh in, /root/runPh7-3-RC4.sh out).
# Usage: python3 tools/make-73rc4.py [OUTPUT]
import re
from pathlib import Path

src = Path("/root/runPh7-2-7.sh").read_text()
t = src

def rep(a, b, count=1):
    global t
    n = t.count(a)
    assert n == count, (n, count, a[:80])
    t = t.replace(a, b)

# --- header -------------------------------------------------------------
rep("""# Photon OS 5.0 userland + experimental Linux 7.2.7
# wrapper v4 — always rewires common-branch-path before make
""", """# Photon OS 5.0 userland + experimental Linux 7.3-rc4 (mainline RC)
# wrapper v8
""")
rep("# $3 RELEASE_BRANCH  default experimental/linux-7.2.7",
    "# $3 RELEASE_BRANCH  default experimental/linux-7.3-rc4")
rep('echo "[runPh7-2-7] wrapper v13 + Hyper-V and legacy iptables config restore + BTF only where Photon has it + perf hook only with tools subpackage + installer initrd list restore (STIG)"',
    'echo "[runPh7-2-7] wrapper v8 (Linux 7.3-rc4, RAP/KCFI on, rdrand-rng, vmwgfx blend, installer/sudo/dbus/cloud-init pre-build, noreplace-smp dropped, esx BTF off, STIG initrd restore, ansible log flush)"')

# --- branch / temp names -------------------------------------------------
rep('RELEASE_BRANCH="${3:-experimental/linux-7.2.7}"', 'RELEASE_BRANCH="${3:-experimental/linux-7.3-rc4}"')
rep('RELEASE_BRANCH="${RELEASE_BRANCH:-experimental/linux-7.2.7}"', 'RELEASE_BRANCH="${RELEASE_BRANCH:-experimental/linux-7.3-rc4}"')
rep("PINOUT=$(mktemp /tmp/pin-linux-7.2.7.XXXXXX.sh)", "PINOUT=$(mktemp /tmp/pin-linux-7.3-rc4.XXXXXX.sh)")
rep(r"""-e 's/RELEASE_BRANCH="${3:-5.0}"/RELEASE_BRANCH="${3:-experimental\/linux-7.2.7}"/' """ + "\\\n",
    r"""-e 's/RELEASE_BRANCH="${3:-5.0}"/RELEASE_BRANCH="${3:-experimental\/linux-7.3-rc4}"/' """ + "\\\n")
rep(r"-e 's/\.runph5-iso-marker/.runph727-iso-marker/g' " + "\\\n",
    r"-e 's/\.runph5-iso-marker/.runph73rc4-iso-marker/g' " + "\\\n")

# --- kernel pin: replace pin_727 with pin_73rc4 ------------------------------
start = t.index("pin_727() {\n")
end = t.index("\n}\n", start) + 3
new_pin = r'''# Pin linux.spec / linux-esx.spec to the 7.3-rc4 mainline tarball.
# RPM versions cannot contain "-": Version 7.3.0, Release 0.rc4.N, and the
# tarball directory (linux-7.3-rc4) lives in %define kernel_src. %prep blanks
# EXTRAVERSION (-rc4) so the kernel names itself 7.3.0 + CONFIG_LOCALVERSION
# (-%{release}), which equals uname_r = %{version}-%{release}. Idempotent.
pin_73rc4() {
  spec="$1"
  [ -f "$spec" ] || return 1
  python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
orig = t
KSRC, KVER, KREL = "7.3-rc4", "7.3.0", "0.rc4.1"
hdr = ("# experimental/linux-7.3-rc4 (Photon 5 userland)\n"
       "# Upstream Linux 7.3-rc4 (mainline release candidate), FIPS/canister OFF.\n"
       "# Only Patch0+Patch1 apply; 6.12-era Photon patch ranges are skipped.\n")
t = re.sub(r"(?s)\A# experimental/linux-[^\n]*\n(?:#[^\n]*\n){0,2}", "", t)
t = hdr + t
t = t.replace("%global fips 1", "%global fips 0", 1) if "%global fips 1" in t.split("%ifarch aarch64")[0] else t
t = re.sub(r"(?m)^Version:(\s*)\S+", r"Version:\g<1>" + KVER, t, count=1)
t = re.sub(r"(?m)^Release:(\s*)[^%\s]+", r"Release:\g<1>" + KREL, t, count=1)
if re.search(r"(?m)^%define kernel_src ", t):
    t = re.sub(r"(?m)^%define kernel_src .*$", "%define kernel_src " + KSRC, t)
else:
    t = re.sub(r"(?m)^(Version:.*\n)", r"\g<1>%define kernel_src " + KSRC + "\n", t, count=1)
t = re.sub(r"(?m)^Source0:(\s*)\S+", r"Source0:\g<1>https://git.kernel.org/torvalds/t/linux-%{kernel_src}.tar.gz", t, count=1)
t = t.replace("-n linux-%{version}", "-n linux-%{kernel_src}")
# noreplace-smp (UP lock-prefix patching) was removed in the 7.3 cycle; 7.3 would log it as an
# unknown parameter and hand it to init. Lock prefixes are always kept now.
t = re.sub(r" noreplace-smp(?=[ \n])", "", t)
mark = "# 7.3-rc4: blank EXTRAVERSION so uname -r equals uname_r\n"
if mark not in t:
    t, n = re.subn(r"(?m)^(%setup -q -n linux-%\{kernel_src\}\n)",
                   r"\g<1>" + mark + "sed -i 's/^EXTRAVERSION = .*/EXTRAVERSION =/' Makefile\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: main %setup line not found")
entry = "* Fri Sep 25 2026 Daniel Casota <dcasota@gmail.com> 7.3.0-0.rc4.1\n"
if entry not in t and "\n%changelog\n" in t:
    t = t.replace("\n%changelog\n", "\n%changelog\n" + entry +
        "- Experimental: Linux 7.3-rc4 mainline release candidate from git.kernel.org.\n"
        "- FIPS canister off; Photon 5.0 userland and .ph5 dist tag unchanged.\n", 1)
if t != orig:
    p.write_text(t)
    print(f"[runPh7-2-7] {p}: pinned to Linux {KSRC} (Version {KVER}, Release {KREL})")
else:
    print(f"[runPh7-2-7] {p}: already pinned to Linux {KSRC}")
PY
}
'''
t = t[:start] + new_pin + t[end:]
rep("pin_727 SPECS/linux/linux.spec SPECS/linux/linux.spec.7.2.7.patch\npin_727 SPECS/linux/linux-esx.spec SPECS/linux/linux-esx.spec.7.2.7.patch\n",
    "pin_73rc4 SPECS/linux/linux.spec || exit 1\npin_73rc4 SPECS/linux/linux-esx.spec || exit 1\n")

# --- %autopatch placement follows the pinned %setup line -----------------------
rep("sed -i 's/^%autopatch /# unrebased autopatch skipped for 7.2.7: /' \"$spec\"",
    "sed -i 's/^%autopatch /# unrebased autopatch skipped for 7.3-rc4: /' \"$spec\"")
rep("if grep -q '%setup -q -n linux-%{version}' \"$spec\"; then",
    "if grep -q '%setup -q -n linux-%{kernel_src}' \"$spec\"; then")
rep(r"$0 ~ /%setup -q -n linux-%\{version\}/ && !done {",
    r"$0 ~ /%setup -q -n linux-%\{kernel_src\}/ && !done {")

# --- 7.3-rc4 only: RAP/KCFI Secure patches ---------------------------------
rep("disable_unrebased_ranges SPECS/linux/linux-esx.spec\n",
    """disable_unrebased_ranges SPECS/linux/linux-esx.spec
# RAP/KCFI ("Secure" range) for the generic linux flavor: Patch61 points at the
# 7.3-rc4 rebase in secure/ on the experimental/linux-7.3-rc4 branch, Patch63 (PAX
# tasklet fix) applies as is. Patch62 (objtool: return error) stays off: it no longer
# applies, and RAP builds emit objtool "no-cfi indirect call!" notes it would make fatal.
# Runs after disable_unrebased_ranges, which comments out every %autopatch each pass.
enable_rap_73rc4() {
  spec="$1"
  [ -f "$spec" ] || return 0
  python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
orig = t
t = re.sub(r"(?m)^Patch61:(\\s*)0001-gcc-rap-plugin-with-kcfi\\.patch$",
           r"Patch61:\\g<1>0001-gcc-rap-plugin-with-kcfi-7.3.patch", t)
if not re.search(r"(?m)^Patch61:\\s*0001-gcc-rap-plugin-with-kcfi-7\\.3\\.patch$", t):
    sys.exit(f"[runPh7-2-7] ERROR: {p}: Patch61 is not the 7.3-rc4 RAP patch")
if "\\n%autopatch -p1 -m61 -M61\\n" not in t:
    t, n = re.subn(r"(?m)^(%autopatch -p1 -m0 -M1\\n)",
                   r"\\g<1>%autopatch -p1 -m61 -M61\\n%autopatch -p1 -m63 -M63\\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: no live %autopatch -p1 -m0 -M1 line")
if t != orig:
    p.write_text(t)
    print(f"[runPh7-2-7] {p}: RAP/KCFI Patch61 (7.3-rc4 rebase) and Patch63 enabled")
else:
    print(f"[runPh7-2-7] {p}: RAP/KCFI patches already enabled")
PY
}
enable_rap_73rc4 SPECS/linux/linux.spec || exit 1
# rdrand hwrng driver (Patch6) for both flavors: systemd's 10-rdrand-rng.conf loads
# rdrand-rng and both configs set HW_RANDOM_RDRAND=m. disable_unrebased_ranges deletes
# Patch2-Patch49, so re-add Patch6 pointing at the 7.3-rc4 rebase in vmw/ and apply it.
enable_rdrand_73rc4() {
  spec="$1"
  [ -f "$spec" ] || return 0
  python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
orig = t
new6 = "Patch6: 0001-hwrng-rdrand-Add-RNG-driver-based-on-x86-rdrand-inst-7.3.patch"
t = re.sub(r"(?m)^Patch6:.*$\\n", "", t)
t, n = re.subn(r"(?m)^(Patch1:.*\\n)", r"\\g<1>" + new6 + "\\n", t, count=1)
if n != 1:
    sys.exit(f"[runPh7-2-7] ERROR: {p}: no Patch1 line to anchor Patch6")
if "\\n%autopatch -p1 -m6 -M6\\n" not in t:
    t, n = re.subn(r"(?m)^(%autopatch -p1 -m0 -M1\\n)", r"\\g<1>%autopatch -p1 -m6 -M6\\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: no live %autopatch -p1 -m0 -M1 line")
if t != orig:
    p.write_text(t)
    print(f"[runPh7-2-7] {p}: rdrand hwrng driver (Patch6, 7.3-rc4 rebase) enabled")
else:
    print(f"[runPh7-2-7] {p}: rdrand hwrng driver already enabled")
PY
}
enable_rdrand_73rc4 SPECS/linux/linux.spec || exit 1
enable_rdrand_73rc4 SPECS/linux/linux-esx.spec || exit 1
# vmwgfx blend mode (Patch7300) for both flavors: 7.3's DRM core warns for every plane
# with alpha formats but no blend mode property; the patch declares PREMULTI.
enable_vmwgfx_73rc4() {
  spec="$1"
  [ -f "$spec" ] || return 0
  python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
orig = t
line = "Patch7300: 0001-drm-vmwgfx-declare-premultiplied-blend-mode-7.3.patch"
if line not in t:
    t, n = re.subn(r"(?m)^(Patch1:.*\\n)", r"\\g<1>" + line + "\\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: no Patch1 line to anchor Patch7300")
if "\\n%autopatch -p1 -m7300 -M7300\\n" not in t:
    t, n = re.subn(r"(?m)^(%autopatch -p1 -m0 -M1\\n)", r"\\g<1>%autopatch -p1 -m7300 -M7300\\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: no live %autopatch -p1 -m0 -M1 line")
if t != orig:
    p.write_text(t)
    print(f"[runPh7-2-7] {p}: vmwgfx blend mode (Patch7300) enabled")
else:
    print(f"[runPh7-2-7] {p}: vmwgfx blend mode already enabled")
PY
}
enable_vmwgfx_73rc4 SPECS/linux/linux.spec || exit 1
enable_vmwgfx_73rc4 SPECS/linux/linux-esx.spec || exit 1

# photon-os-installer fixes whose patch files are on the branch. downstream-fixes.patch
# extends this spec (0003..0007), so each is appended here as the next PatchN, with
# its own release bump and changelog entry, in order. Idempotent per patch.
#   0008  networkd DHCP match by Type=ether/Kind=!* instead of Name=e*
#   0009  flush the ansible log before copying it (STIG log lost its PLAY RECAP)
pin_installer_73rc4() {
  spec="SPECS/photon-os-installer/photon-os-installer.spec"
  [ -f "$spec" ] || return 0
  python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
fixes = [
    ("0008-networkmanager-match-dhcp-links-by-type.patch", "Sat Sep 26 2026",
     "- networkmanager: match DHCP links by Type=ether/Kind=!* instead of\\n"
     "  Name=e*, which networkd flags as an unpredictable name with net.ifnames=0\\n"),
    ("0009-installer-flush-ansible-log-before-copying.patch", "Sun Sep 27 2026",
     "- installer: flush the ansible log before copying it, so the STIG log\\n"
     "  keeps its PLAY RECAP\\n"),
]
for fname, date, entry in fixes:
    if fname in t:
        print(f"[runPh7-2-7] {p}: {fname} already applied")
        continue
    nums = [int(n) for n in re.findall(r"(?m)^Patch(\\d+):", t)]
    if not nums:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: no Patch lines")
    last = max(nums)
    t, n = re.subn(rf"(?m)^(Patch{last}:.*\\n)", rf"\\g<1>Patch{last + 1}: {fname}\\n", t, count=1)
    m = re.search(r"(?m)^(Release:\\s*)(\\d+)(%\\{\\?dist\\})", t)
    if n != 1 or not m:
        sys.exit(f"[runPh7-2-7] ERROR: {p}: cannot add {fname}")
    rel = int(m.group(2)) + 1
    t = t[:m.start()] + f"{m.group(1)}{rel}{m.group(3)}" + t[m.end():]
    ver = re.search(r"(?m)^Version:\\s*(\\S+)", t).group(1)
    t = t.replace("%changelog\\n", f"%changelog\\n* {date} Daniel Casota <dcasota@gmail.com> "
                  f"{ver}-{rel}\\n" + entry, 1)
    print(f"[runPh7-2-7] {p}: Patch{last + 1} {fname}, release {ver}-{rel}")
p.write_text(t)
PY
}
pin_installer_73rc4 || exit 1
""")

# --- sandbox wipe names --------------------------------------------------
rep("""        -name 'linux-7.2.7*' -o -name 'linux-esx-7.2.7*' -o \\
        -name 'build-linux-7.2.7*' -o -name 'build-linux-esx-7.2.7*' \\""",
    """        -name 'linux-7.3.0*' -o -name 'linux-esx-7.3.0*' -o \\
        -name 'build-linux-7.3.0*' -o -name 'build-linux-esx-7.3.0*' \\""")

# --- kernel tarball fetch ------------------------------------------------
rep('K727_SHA="9a7ee3e35e1e4eea44fd2fadce7b51deb9cae8b1e19ed4d8dc1e59d2e310ffa6dae508a9b0919d2d3cd29d00ca79fd473e7540a3cfb1124e56c4de091915a9d9"',
    'K73RC4_SHA="7a4b9599c2c593131e150ae22030f643813b0fb3de2b479281ebb9a413e7928903adc748eb522e03fd39e9ca4991c12e4d0331718fff59a53fc6676b390c7945"')
rep('''    "linux-7.2.7.tar.xz" \\
    "https://cdn.kernel.org/pub/linux/kernel/v7.x/linux-7.2.7.tar.xz" \\
    "$K727_SHA" || true''',
    '''    "linux-7.3-rc4.tar.gz" \\
    "https://git.kernel.org/torvalds/t/linux-7.3-rc4.tar.gz" \\
    "$K73RC4_SHA" || true''')

# --- version assert --------------------------------------------------------
rep('''  if [ "${PIN_REQUIRE_KVER:-1}" = 1 ] && [ "$kver" != "7.2.7" ]; then
    echo "[runPh7-2-7] ERROR: linux.spec Version is '$kver', expected 7.2.7" 1>&2''',
    '''  if [ "${PIN_REQUIRE_KVER:-1}" = 1 ] && [ "$kver" != "7.3.0" ]; then
    echo "[runPh7-2-7] ERROR: linux.spec Version is '$kver', expected 7.3.0 (7.3-rc4)" 1>&2''')

# --- version-neutral cleanup of legacy leftovers ------------------------
rep("""# Older standalone pin-linux-7.2.7.sh runs appended a "7.2.7 SpecData
# compatibility" wrap to common SpecData.py and rewrote three raises into""",
    """# Older standalone pin-linux-<kernel>.sh runs appended a "<kernel> SpecData
# compatibility" wrap to common SpecData.py and rewrote three raises into""")
rep("""# rewrites return a str where callers expect a list. SpecData needs no
# 7.2.7 help; strip both so a stale common tree heals itself.""",
    """# rewrites return a str where callers expect a list. SpecData needs no
# kernel-specific help; strip both so a stale common tree heals itself.""")
rep("""import sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
nt = t
marker = "# --- 7.2.7 SpecData compatibility ---"
if marker in nt:
    nt = nt[: nt.index(marker)].rstrip() + "\\n"
""", """import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
nt = t
m = re.search(r"# --- [0-9][0-9A-Za-z.-]* SpecData compatibility ---", nt)
if m:
    nt = nt[: m.start()].rstrip() + "\\n"
""")
rep('print(f"[runPh7-2-7] {p}: removed stale 7.2.7 SpecData compat wrap")',
    'print(f"[runPh7-2-7] {p}: removed stale SpecData compat wrap")')
rep("""    [ -x "$root/bin/c++.real727" ] && mv -f "$root/bin/c++.real727" "$root/bin/c++"
    [ -x "$root/bin/g++.real727" ] && mv -f "$root/bin/g++.real727" "$root/bin/g++"
""", """    for f in "$root"/bin/c++.real[0-9]* "$root"/bin/g++.real[0-9]*; do
      [ -x "$f" ] && mv -f "$f" "${f%.real*}"
    done
""")
rep("# ENA 2.17.0 fails on 7.2.7: page_pool_get_stats() is void.",
    "# ENA 2.17.0 fails on 7.x kernels: page_pool_get_stats() is void.")
t = t.replace("7.2.7", "7.3-rc4")
assert "7.2.7" not in t and "727" not in t, [l for l in t.splitlines() if "7.2.7" in l or "727" in l][:5]

# --- 7.3-rc4 only: pre-build cloud-init with the STIG set ------------------
# minimal Requires cloud-init. make image does not rebuild an install-only dependency whose
# older RPM (26.2-2 from the seed) is already in stage/RPMS, and with that RPM gone it does
# not schedule it at all, so the branch's cloud-init 26.2-3 (vmware/photon#1676) must be built
# explicitly before the image, like the STIG packages.
rep("""            ind + '# 7.3-rc4: build the ISO KS_STIG_PACKAGES set before make image\\n'""",
    """            ind + '# 7.3-rc4: build the ISO KS_STIG_PACKAGES set and branch-updated packages before make image\\n'""")
rep("""            'libselinux-utils,ntpsec,aide,libgcrypt" THREADS=8 || '""",
    """            'libselinux-utils,ntpsec,aide,libgcrypt,cloud-init,sudo,dbus,photon-os-installer" THREADS=8 || '""")

# --- log prefix and remaining script-name references --------------------
t = t.replace("runPh7-2-7", "runPh7-3-RC4")

import sys
out = Path(sys.argv[1] if len(sys.argv) > 1 else "/root/runPh7-3-RC4.sh")
out.write_text(t)
out.chmod(0o755)
print("wrote", out)
