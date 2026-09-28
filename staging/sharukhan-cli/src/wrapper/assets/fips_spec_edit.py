#!/usr/bin/env python3
# fips_spec_edit.py <spec> <manifest.json> <lkcm_version>
#
# Enable the ported FIPS canister series in a kernel spec that the derived
# wrapper has pinned (FIPS off, every %autopatch commented out as
# "# unrebased autopatch skipped for <kernel>: -p1 -mA -MB").
#
# The manifest (exported next to the files it names, verified by a replay of
# %prep) says, per spec number, which file a PatchN/SourceN line must name,
# which 6.12 patches are dropped, and which %autopatch ranges apply. Nothing
# here knows a kernel version: the only inputs are the spec, the manifest and
# the LKCM version string.
#
# Canister pins get the two-macro override shape (a 0/1 flag plus a value
# macro), because Photon's SpecParser neither sees a %{!?...} guard nor can a
# conditional test a version string:
#   canister_stamp_real=1 + fips_certified_override=<NEVR>  (canister_build)
#   canister_equivalent=1 + fips_canister_override=<NEVR>   (canister_usage)
# Without them the defaults name what this tree itself produces: linux builds
# the canister at its own Version-Release, stamps that kernel (there is no
# certified 7.x canister to claim), and linux-esx links linux's canister.
#
# Idempotent; any unexpected shape is an error, never a guess.
import json, re, sys
from pathlib import Path

spec, manifest, lkcm = Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3]
tag = "[fips]"
m = json.loads(manifest.read_text())
t = spec.read_text()
orig = t
flavour = "linux-esx" if spec.name == "linux-esx.spec" else "linux"
extra = m.get("flavours", {}).get(flavour, {})
m["patches"] = {**m["patches"], **extra.get("patches", {})}
m["autopatch"] = m["autopatch"] + extra.get("autopatch", [])

NAME = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._+-]*$")
def fail(msg):
    sys.exit(f"{tag} ERROR: {spec}: {msg}")

if not re.fullmatch(r"\d+\.\d+", lkcm):
    fail(f"lkcm_version {lkcm!r} is not <major>.<minor>")
for kind in ("patches", "sources"):
    for k, v in m[kind].items():
        if not k.isdigit():
            fail(f"manifest {kind} key {k!r} is not a number")
        f = v.get("file")
        if f is not None and not NAME.fullmatch(f):
            fail(f"manifest {kind}[{k}] file {f!r} is not a plain file name")
        if kind == "sources" and not NAME.fullmatch(v.get("installs", "")):
            fail(f"manifest sources[{k}] has no plain installs name")
for k in m["dropped"]:
    if not k.isdigit() or k in m["patches"]:
        fail(f"manifest drops {k!r}, which is not a number or is also listed as a patch")
ranges = m.get("autopatch")
if not ranges or any(len(r) != 2 or not all(isinstance(x, int) for x in r) or r[0] > r[1] for r in ranges):
    fail("manifest has no valid autopatch ranges")
for k, v in m["patches"].items():
    if v.get("file") and not any(a <= int(k) <= b for a, b in ranges):
        fail(f"Patch{k} is in no autopatch range and would never apply")
for k in m["dropped"]:
    if not any(a <= int(k) <= b for a, b in ranges):
        fail(f"dropped Patch{k} is outside every range; the drop is meaningless")

# --- FIPS on (x86_64 only; aarch64 has no canister) --------------------------
arch = t.split("%ifarch aarch64", 1)
if len(arch) != 2:
    fail("no %ifarch aarch64 block")
x86, rest = arch
x86 = re.sub(r"(?m)^%global fips 0$", "%global fips 1", x86, count=1)
if not re.search(r"(?m)^%global fips 1$", x86):
    fail("x86_64 %global fips line not found")
t = x86 + "%ifarch aarch64" + rest
t = re.sub(r"(?m)^(%global lkcm_version )\S+$", r"\g<1>" + lkcm, t, count=1)
if flavour == "linux" and not re.search(r"(?m)^%global lkcm_version " + re.escape(lkcm) + "$", t):
    fail("%global lkcm_version not found")

# --- PatchN lines ------------------------------------------------------------
def patch_line_re(n):
    return re.compile(r"(?m)^Patch%d:(\s*)(\S+)$" % n)

for k in sorted(m["dropped"], key=int):
    t = re.sub(r"(?m)^Patch%d:\s*\S+\n" % int(k), "", t)

wanted = {int(k): v["file"] for k, v in m["patches"].items() if v.get("file")}
for n in sorted(wanted):
    f = wanted[n]
    if flavour == "linux-esx" and n >= 11000:
        continue  # linux-esx cannot build a canister; it links linux's
    r = patch_line_re(n)
    if r.search(t):
        t = r.sub(lambda mo: f"Patch{n}:{mo.group(1)}{f}", t, count=1)
        continue
    # A new number goes after the highest listed patch below it in the same
    # hundred-block (10101..10199 and so on), which keeps it inside the
    # right %if block.
    below = [p for p in wanted if p < n and p // 100 == n // 100 and patch_line_re(p).search(t)]
    if not below:
        fail(f"Patch{n}: no PatchN line of its block to anchor after")
    a = patch_line_re(max(below)).search(t)
    t = t[:a.end()] + f"\nPatch{n}: {f}" + t[a.end():]

# canister_build and canister_usage patch lines exist in linux.spec; linux-esx
# carries only the common range and must not gain canister_build lines.
if flavour == "linux-esx":
    for n in list(wanted):
        if n >= 11000 and patch_line_re(n).search(t):
            fail(f"linux-esx carries canister_build Patch{n}")

# --- SourceN lines and their %prep installs -----------------------------------
for k, v in sorted(m["sources"].items(), key=lambda x: int(x[0])):
    n, f, inst = int(k), v["file"], v["installs"]
    r = re.compile(r"(?m)^Source%d:(\s*)(\S+)$" % n)
    if not r.search(t):
        if flavour == "linux-esx" and n >= 11000:
            continue
        fail(f"Source{n} line not found")
    t = r.sub(lambda mo: f"Source{n}:{mo.group(1)}{f}", t, count=1)
    if f == inst:
        continue
    # The file name differs from the name the kernel tree expects: every
    # "cp|install [-m MODE] %{SOURCEn} <dir>/" must name the target.
    pat = re.compile(r"(?m)^((?:cp|install)(?: -m \d+)? %\{SOURCE" + str(n) + r"\} )(\S+/)$")
    hits = pat.findall(t)
    if not hits:
        pat2 = re.compile(r"(?m)^(?:cp|install)(?: -m \d+)? %\{SOURCE" + str(n) + r"\} \S+/" + re.escape(inst) + "$")
        if not pat2.search(t):
            fail(f"no %prep install of Source{n} to rename to {inst}")
    t = pat.sub(lambda mo: mo.group(1) + mo.group(2) + inst, t)

# --- %autopatch ranges ---------------------------------------------------------
# Restore each range where the wrapper commented it out (same position, same
# %if block), matching on the range start; the manifest's end wins.
skipped = re.compile(r"(?m)^# unrebased autopatch skipped for [^:]+: -p1 -m(\d+) -M(\d+)$")
for a, b in ranges:
    live = re.compile(r"(?m)^%%autopatch -p1 -m%d -M(\d+)$" % a)
    if live.search(t):
        t = live.sub(f"%autopatch -p1 -m{a} -M{b}", t)
        continue
    hit = [mo for mo in skipped.finditer(t) if int(mo.group(1)) == a]
    if not hit:
        if flavour == "linux-esx" and a >= 11000:
            continue
        fail(f"no %autopatch line for the range starting at {a}")
    for mo in reversed(hit):
        t = t[:mo.start()] + f"%autopatch -p1 -m{a} -M{b}" + t[mo.end():]

# --- canister pins with overrides ------------------------------------------------
ver = re.search(r"(?m)^Version:\s*(\S+)$", t)
rel = re.search(r"(?m)^Release:\s*([0-9][0-9a-z.]*)", t)
if not ver or not rel:
    fail("Version/Release not found")
if flavour == "linux":
    own = f"{ver.group(1)}-{rel.group(1)}%{{?dist}}"
else:
    lx = (spec.parent / "linux.spec").read_text()
    lv = re.search(r"(?m)^Version:\s*(\S+)$", lx)
    lr = re.search(r"(?m)^Release:\s*([0-9][0-9a-z.]*)", lx)
    if not lv or not lr:
        fail("linux.spec Version/Release not found (linux-esx links linux's canister)")
    own = f"{lv.group(1)}-{lr.group(1)}%{{?dist}}"

cert = re.compile(r"(?m)^%define fips_certified_kernel_version \S+$")
cert_block = ("%if 0%{?canister_stamp_real}\n"
              "%define fips_certified_kernel_version %{fips_certified_override}\n"
              "%else\n"
              f"%define fips_certified_kernel_version {own}\n"
              "%endif")
if "%{fips_certified_override}" not in t:
    if flavour == "linux":
        if len(cert.findall(t)) != 1:
            fail("expected one fips_certified_kernel_version definition")
        t = cert.sub(cert_block, t)
else:
    t = re.sub(r"(?m)^(%define fips_certified_kernel_version )(?!%\{fips_certified_override\})\S+$",
               r"\g<1>" + own, t)

pin = re.compile(r"(?m)^%define fips_canister_version \S+$")
pin_block = ("%if 0%{?canister_equivalent}\n"
             "%define fips_canister_version %{fips_canister_override}\n"
             "%else\n"
             f"%define fips_canister_version {own}\n"
             "%endif")
if "%{fips_canister_override}" not in t:
    if len(pin.findall(t)) != 1:
        fail("expected one fips_canister_version definition")
    t = pin.sub(pin_block, t)
else:
    t = re.sub(r"(?m)^(%define fips_canister_version )(?!%\{fips_canister_override\})\S+$",
               r"\g<1>" + own, t)

# --- what the kernel pin says about FIPS ------------------------------------------
# The pin writes a FIPS-off header and changelog line for every build; in a
# canister build they would be false.
t = t.replace("FIPS/canister OFF.", f"FIPS canister ON (LKCM {lkcm} port).", 1)
t = t.replace("- FIPS canister off;",
              f"- FIPS canister on (LKCM {lkcm} port, built from this tree, not CMVP validated);", 1)

# --- kernel config ------------------------------------------------------------
# 7.x replaced CRYPTO_MANAGER_DISABLE_TESTS (self-tests on unless set) with
# CRYPTO_SELFTESTS (off unless set), and CRYPTO_FIPS depends on it. The config
# merge's olddefconfig therefore drops CRYPTO_FIPS, and the jitterentropy
# settings that go with it, from Photon's config. Put them back after the
# merge and fail the build if any does not hold.
CFG_BEGIN = "# FIPS kernel config (7.x): CRYPTO_SELFTESTS and Photon's crypto settings\n"
CFG_END = "# FIPS kernel config end\n"
cfg_block = (CFG_BEGIN +
    "%if 0%{?fips}\n"
    "scripts/config --enable CRYPTO_SELFTESTS\n"
    "make %{?_smp_mflags} ARCH=%{arch} LC_ALL= olddefconfig\n"
    "grep -E '^CONFIG_CRYPTO_(FIPS|JITTERENTROPY)[A-Z0-9_]*=' .config.photon |\n"
    "  while IFS='=' read -r k v; do scripts/config --set-val \"${k#CONFIG_}\" \"$v\"; done\n"
    "grep -E '^# CONFIG_CRYPTO_JITTERENTROPY_[A-Z0-9_]* is not set$' .config.photon |\n"
    "  while read -r _ k _; do scripts/config --disable \"${k#CONFIG_}\"; done\n"
    "make %{?_smp_mflags} ARCH=%{arch} LC_ALL= olddefconfig\n"
    "for k in CRYPTO_SELFTESTS CRYPTO_FIPS; do\n"
    "  grep -q \"^CONFIG_$k=y$\" .config || { echo \"FIPS config: CONFIG_$k is not y\" >&2; exit 1; }\n"
    "done\n"
    "grep -E '^(# )?CONFIG_CRYPTO_(FIPS|JITTERENTROPY)[A-Z0-9_]*[= ]' .config.photon |\n"
    "  while IFS= read -r l; do grep -qxF \"$l\" .config || { echo \"FIPS config: lost '$l'\" >&2; exit 1; }; done\n"
    "%endif\n" + CFG_END)
if CFG_BEGIN in t:
    i = t.index(CFG_BEGIN); j = t.index(CFG_END, i) + len(CFG_END)
    t = t[:i] + cfg_block + t[j:]
else:
    anchor = "# config merge block end\n"
    if t.count(anchor) != 1:
        fail("expected exactly one config merge block (the wrapper's inject_config_merge)")
    if ".config.photon" not in t:
        fail("the config merge does not keep .config.photon")
    t = t.replace(anchor, anchor + cfg_block, 1)

if t != orig:
    spec.write_text(t)
    print(f"{tag} {spec}: FIPS canister series {lkcm} enabled ({len(wanted)} patches, "
          f"{len(m['dropped'])} dropped, canister {own})")
else:
    print(f"{tag} {spec}: FIPS canister series {lkcm} already enabled")
