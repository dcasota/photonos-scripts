#!/bin/sh
#
# Photon OS 5.0 userland + experimental Linux 7.3-rc4 (mainline RC)
# wrapper v6
#
# $1 BASE_DIR        default /root
# $2 COMMON_BRANCH   default common
# $3 RELEASE_BRANCH  default experimental/linux-7.3-rc4
# $4 OUTPUT_DIR      default /mnt/c/Users/dcaso/Downloads/Ph-Builds
# $5 IMG_TYPE        default minimal-iso
# $6 CANISTER_MODE   default none

set -eu

# rustc bootstrap parses c++ probe stderr as source. Fancy UTF-8 quotes
# (U+2018/U+2019) from a non-C locale abort the rust RPM. Keep C for the
# whole tree so a restart does not depend on the operator's shell.
export LANG=C
export LC_ALL=C
export LC_CTYPE=C

# Never open vi/emacs for a merge commit message (git pull on common).
export GIT_EDITOR=true
export GIT_SEQUENCE_EDITOR=true
export GIT_MERGE_AUTOEDIT=no
export GIT_PAGER=cat
export GIT_TERMINAL_PROMPT=0
export EDITOR=true
export VISUAL=true

echo "[runPh7-3-RC4] wrapper v6 (Linux 7.3-rc4, RAP/KCFI on, rdrand-rng, vmwgfx blend, installer/sudo/dbus/cloud-init pre-build, noreplace-smp dropped, esx BTF off)"

SCRIPT_DIR=$(cd "$(dirname "$0")" 2>/dev/null && pwd)

find_file() {
  name="$1"
  for d in "$SCRIPT_DIR" "$SCRIPT_DIR/staging" "$HOME" "$HOME/staging" \
           /root /root/staging /root/photonos-scripts/staging; do
    [ -f "$d/$name" ] && { echo "$d/$name"; return 0; }
  done
  return 1
}

SRC=$(find_file runPh5_normal.sh) || {
  echo "[runPh7-3-RC4] ERROR: runPh5_normal.sh not found" 1>&2
  exit 1
}

BASE_DIR="${1:-/root}"
COMMON_BRANCH="${2:-common}"
RELEASE_BRANCH="${3:-experimental/linux-7.3-rc4}"
OUTPUT_DIR="${4:-/mnt/c/Users/dcaso/Downloads/Ph-Builds}"
IMG_TYPE="${5:-minimal-iso}"
CANISTER_MODE="${6:-none}"

if [ "$CANISTER_MODE" = "prebuilt" ]; then
  echo "[runPh7-3-RC4] WARNING: prebuilt canister is a 6.12 artifact; forcing mode=none"
  CANISTER_MODE=none
fi

# If a previous run already nested the clone, fix the layout now.
fix_common_layout() {
  rel="$BASE_DIR/$RELEASE_BRANCH"
  com="$BASE_DIR/$COMMON_BRANCH"
  parent=$(dirname "$rel")
  mkdir -p "$parent"
  if [ -d "$com" ] && [ "$parent" != "$BASE_DIR" ]; then
    ln -sfn "$com" "$parent/common"
    echo "[runPh7-3-RC4] $parent/common -> $com"
  fi
  if [ -f "$rel/build-config.json" ]; then
    python3 -c "
import json
p='$rel/build-config.json'
c=json.load(open(p))
c['common-branch-path']='$com'
json.dump(c, open(p,'w'), indent=4)
print('[runPh7-3-RC4] common-branch-path =', c['common-branch-path'])
"
  fi
}
fix_common_layout

# Fast-forward only when possible; merge with --no-edit if histories diverged.
# Never spawn $EDITOR. Applied to common + the release worktree.
git_sync_quiet() {
  repo="$1"
  [ -d "$repo/.git" ] || return 0
  echo "[runPh7-3-RC4] git sync (no editor) $repo"
  git -C "$repo" config --local core.editor true || true
  git -C "$repo" config --local sequence.editor true || true
  git -C "$repo" fetch --all --prune --quiet 2>/dev/null || \
    git -C "$repo" fetch --quiet 2>/dev/null || true
  if git -C "$repo" pull --ff-only --no-edit --quiet 2>/dev/null; then
    echo "[runPh7-3-RC4] $repo fast-forwarded"
    return 0
  fi
  if git -C "$repo" pull --no-rebase --no-edit --quiet 2>/dev/null; then
    echo "[runPh7-3-RC4] $repo merged with --no-edit (ort)"
    return 0
  fi
  echo "[runPh7-3-RC4] $repo: leave tree as-is (fetch/pull not clean)"
}
git_sync_quiet "$BASE_DIR/$COMMON_BRANCH"
git_sync_quiet "$BASE_DIR/$RELEASE_BRANCH"
git_sync_quiet "$BASE_DIR/experimental/$COMMON_BRANCH"
git_sync_quiet "$BASE_DIR/photonos-scripts"

GEN=$(mktemp /tmp/runPh7-3-RC4.XXXXXX.sh)
PINOUT=$(mktemp /tmp/pin-linux-7.3-rc4.XXXXXX.sh)
trap 'rm -f "$GEN" "$PINOUT"' EXIT

cat > "$PINOUT" << 'EMBEDPIN'
# Sourced by runPh7-3-RC4.sh after downstream-fixes.patch.
# Expects BASE_DIR, COMMON_BRANCH, RELEASE_BRANCH.

# worktree_now() is the collected "On the worktree now" sequence.
# The wrapper sources this file from the release worktree before make
# so those steps never have to be pasted by hand.

# Paths the wrapper may not have exported yet (set -u).
COMMON_DIR="${COMMON_DIR:-${BASE_DIR:-/root}/${COMMON_BRANCH:-common}}"
BASE_DIR="${BASE_DIR:-/root}"
COMMON_BRANCH="${COMMON_BRANCH:-common}"
RELEASE_BRANCH="${RELEASE_BRANCH:-experimental/linux-7.3-rc4}"

# Older wrapper runs commented out build_if in SPECS/90 (and its untracked
# _disabled_selinux34 copies), so SELinux 3.4 built beside 3.10 and SpecData
# died with "Invalid package: 3". Subrelease 92 builds every STIG package
# from the top-level SPECS; put any commented-out gate back.
pin_regate_specs() {
  python3 << 'PY'
from pathlib import Path
import re
n = 0
for spec in Path("SPECS").rglob("*.spec"):
    t = spec.read_text(errors="replace")
    nt = t.replace("# 7.3-rc4 always build STIG dep\n# %global build_if", "%global build_if")
    nt = re.sub(r'(?m)^# (%global build_if\b)', r'\1', nt)
    if nt != t:
        spec.write_text(nt)
        n += 1
print("[runPh7-3-RC4] re-gated build_if in", n, "spec(s)")
PY
}

# Older standalone pin-linux-<kernel>.sh runs appended a "<kernel> SpecData
# compatibility" wrap to common SpecData.py and rewrote three raises into
# `return self.getHighestVersion(...)`. The wrap's getBasePkg cannot split
# name-version-release ("aide-0.19-3.ph5" -> Invalid package), and the
# rewrites return a str where callers expect a list. SpecData needs no
# kernel-specific help; strip both so a stale common tree heals itself.
pin_drop_specdata_compat() {
  for f in \
      "$COMMON_DIR/support/package-builder/SpecData.py" \
      /root/common/support/package-builder/SpecData.py
  do
    [ -f "$f" ] || continue
    python3 - "$f" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
nt = t
m = re.search(r"# --- [0-9][0-9A-Za-z.-]* SpecData compatibility ---", nt)
if m:
    nt = nt[: m.start()].rstrip() + "\n"
nt = nt.replace(
    'return self.getHighestVersion(str(getattr(pkg, "package", pkg)).split("=")[0].strip().strip("()").split()[0])',
    'raise Exception(f"Could not find proper version for {pkg}")',
)
if nt == t:
    print(f"[runPh7-3-RC4] {p}: no SpecData compat leftovers")
    raise SystemExit(0)
compile(nt, str(p), "exec")
p.write_text(nt)
print(f"[runPh7-3-RC4] {p}: removed stale SpecData compat wrap")
PY
  done
}

worktree_now() {
  echo "[runPh7-3-RC4] worktree_now: start"
  pin_drop_specdata_compat
  pin_regate_specs
  pin_spec_lint
  echo "[runPh7-3-RC4] worktree_now: done"
}

# Pin linux.spec / linux-esx.spec to the 7.3-rc4 mainline tarball.
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
        sys.exit(f"[runPh7-3-RC4] ERROR: {p}: main %setup line not found")
entry = "* Fri Sep 25 2026 Daniel Casota <dcasota@gmail.com> 7.3.0-0.rc4.1\n"
if entry not in t and "\n%changelog\n" in t:
    t = t.replace("\n%changelog\n", "\n%changelog\n" + entry +
        "- Experimental: Linux 7.3-rc4 mainline release candidate from git.kernel.org.\n"
        "- FIPS canister off; Photon 5.0 userland and .ph5 dist tag unchanged.\n", 1)
if t != orig:
    p.write_text(t)
    print(f"[runPh7-3-RC4] {p}: pinned to Linux {KSRC} (Version {KVER}, Release {KREL})")
else:
    print(f"[runPh7-3-RC4] {p}: already pinned to Linux {KSRC}")
PY
}

write_empty_cve_inc() {
  cat > "$1" << 'CVEINC'
# CVE patch range 3000-3999 left empty on experimental linux 7.3-rc4.
# 6.12-stable backports do not apply to 7.3-rc4. Do not put percent-tokens
# or backticks in this file; rpm expands them even in comments.
CVEINC
}

# Pull origin's empty kernel_cve_patches.inc; if fetch fails or the file
# still declares PatchNNNN, overwrite it locally so %prep cannot apply ioam6.
sync_cve_include() {
  inc="SPECS/linux/kernel_cve_patches.inc"
  mkdir -p SPECS/linux
  if git remote get-url origin >/dev/null 2>&1; then
    git fetch origin "${RELEASE_BRANCH}" 2>/dev/null || git fetch origin 2>/dev/null || true
    if git show "origin/${RELEASE_BRANCH}:${inc}" >/dev/null 2>&1; then
      git checkout -f "origin/${RELEASE_BRANCH}" -- "$inc" 2>/dev/null || \
        git checkout -f HEAD -- "$inc" 2>/dev/null || true
      echo "[runPh7-3-RC4] refreshed $inc from origin/${RELEASE_BRANCH}"
    fi
  fi
  if [ ! -f "$inc" ] || grep -qE '^[[:space:]]*Patch[0-9]+' "$inc"; then
    echo "[runPh7-3-RC4] $inc still lists Patch lines (or missing); writing empty include"
    write_empty_cve_inc "$inc"
  fi
  if grep -qE '^[[:space:]]*Patch[0-9]+' "$inc"; then
    echo "[runPh7-3-RC4] ERROR: $inc still has Patch lines after cleanup" 1>&2
    grep -nE '^[[:space:]]*Patch[0-9]+' "$inc" | head 1>&2
    exit 1
  fi
  echo "[runPh7-3-RC4] $inc has no Patch lines"
}

# Milestone 2: every Photon range is 6.12-era except Patch0+Patch1,
# which already apply on 7.3-rc4. Comment EVERY %autopatch line (no live
# percent-token in the comment — rpm expands those), then re-enable only
# -m0 -M1. Also drop Patch2-Patch49 so a leftover 0-49 range cannot
# resurrect 9p/SUNRPC/vsock.
disable_unrebased_ranges() {
  spec="$1"
  [ -f "$spec" ] || return 0
  sed -i 's/^%autopatch /# unrebased autopatch skipped for 7.3-rc4: /' "$spec"
  if grep -q '%setup -q -n linux-%{kernel_src}' "$spec"; then
    awk '
      { print }
      $0 ~ /%setup -q -n linux-%\{kernel_src\}/ && !done {
        print "%autopatch -p1 -m0 -M1"
        done=1
      }
    ' "$spec" > "$spec.pin" && mv "$spec.pin" "$spec"
  else
    echo "%autopatch -p1 -m0 -M1" >> "$spec"
  fi
  sed -i -E '/^Patch([2-9]|[1-4][0-9]):/d' "$spec"
  echo "[runPh7-3-RC4] $spec: only %autopatch -m0 -M1 (Patch0+Patch1)"
}

SKIP_PATCHES="
0001-net-ioam6-fix-OOB-and-missing-lock
KVM-Don-t-accept-obviously-wrong-gsi-values-via-KVM_
SUNRPC-xs_bind-uses-ip_local_reserved_ports
9p-transport-for-9p
9p-trans_fd-extend-port-variable-to-u32
"

drop_skipped_patches() {
  spec="$1"
  [ -f "$spec" ] || return 0
  echo "$SKIP_PATCHES" | while IFS= read -r pat; do
    [ -n "$pat" ] || continue
    if grep -q "$pat" "$spec"; then
      sed -i "/$pat/d" "$spec"
      echo "[runPh7-3-RC4] dropped $pat from $spec"
    fi
    rm -f "SPECS/linux/"*"$pat"* \
          "SPECS/linux/CVE/"*"$pat"* \
          "stage/SOURCES/"*"$pat"* \
          "$BASE_DIR/$RELEASE_BRANCH/stage/SOURCES/"*"$pat"* 2>/dev/null || true
  done
}

wipe_kernel_sandboxes() {
  stage="$BASE_DIR/$RELEASE_BRANCH/stage"
  [ -d "$stage" ] || return 0
  find "$stage" -maxdepth 5 \( \
      -name 'kernel_cve_patches.inc' -o \
      -name 'linux.spec' -o -name 'linux-esx.spec' \
    \) -path '*stage*' -print -delete 2>/dev/null || true
  find "$stage" -maxdepth 4 -type d \( \
      -name 'apparmor-4.1*' -o -name 'build-apparmor*' -o \
      -name 'subversion-1.14*' -o -name 'build-subversion*' \
    \) -print -exec rm -rf {} + 2>/dev/null || true
  echo "[runPh7-3-RC4] wiping rust sandbox for clean upstream bootstrap"
  find "$stage" -maxdepth 4 -type d \( -name 'rust-1.93*' -o -name 'build-rust-1.93*' \) -print -exec rm -rf {} + 2>/dev/null || true
  if [ "${FORCE_WIPE_LINUX:-0}" = "1" ]; then
    find "$stage" -maxdepth 4 -type d \( \
        -name 'linux-7.3.0*' -o -name 'linux-esx-7.3.0*' -o \
        -name 'build-linux-7.3.0*' -o -name 'build-linux-esx-7.3.0*' \
      \) -print -exec rm -rf {} + 2>/dev/null || true
    echo "[runPh7-3-RC4] FORCE_WIPE_LINUX=1: wiped linux sandboxes (kept sandboxBase)"
  else
    echo "[runPh7-3-RC4] kept linux sandboxes (set FORCE_WIPE_LINUX=1 to rebuild kernel from scratch)"
  fi
  # Older pins renamed g++ inside sandboxBase; postgres configure then
  # wrote a broken config.status (ed hunk `0a1,390`).
  for root in \
      "$stage/images/sandboxBase" \
      "$stage/images/sandboxBase/usr" \
      /usr; do
    for f in "$root"/bin/c++.real[0-9]* "$root"/bin/g++.real[0-9]*; do
      [ -x "$f" ] && mv -f "$f" "${f%.real*}"
    done
  done
  return 0
}

cd "$BASE_DIR/$RELEASE_BRANCH" || exit 1

parent=$(dirname "$BASE_DIR/$RELEASE_BRANCH")
if [ "$parent" != "$BASE_DIR" ] && [ -d "$BASE_DIR/${COMMON_BRANCH:-common}" ]; then
  ln -sfn "$BASE_DIR/${COMMON_BRANCH:-common}" "$parent/common"
  echo "[runPh7-3-RC4] $parent/common -> $BASE_DIR/${COMMON_BRANCH:-common}"
fi
if [ -f build-config.json ]; then
  python3 -c "
import json
p='build-config.json'
c=json.load(open(p))
c['common-branch-path']='$BASE_DIR/${COMMON_BRANCH:-common}'
json.dump(c, open(p,'w'), indent=4)
print('[runPh7-3-RC4] common-branch-path =', c['common-branch-path'])
"
fi

pin_73rc4 SPECS/linux/linux.spec || exit 1
pin_73rc4 SPECS/linux/linux-esx.spec || exit 1
sync_cve_include
drop_skipped_patches SPECS/linux/linux.spec
drop_skipped_patches SPECS/linux/linux-esx.spec
drop_skipped_patches SPECS/linux/kernel_cve_patches.inc
disable_unrebased_ranges SPECS/linux/linux.spec
disable_unrebased_ranges SPECS/linux/linux-esx.spec
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
t = re.sub(r"(?m)^Patch61:(\s*)0001-gcc-rap-plugin-with-kcfi\.patch$",
           r"Patch61:\g<1>0001-gcc-rap-plugin-with-kcfi-7.3.patch", t)
if not re.search(r"(?m)^Patch61:\s*0001-gcc-rap-plugin-with-kcfi-7\.3\.patch$", t):
    sys.exit(f"[runPh7-3-RC4] ERROR: {p}: Patch61 is not the 7.3-rc4 RAP patch")
if "\n%autopatch -p1 -m61 -M61\n" not in t:
    t, n = re.subn(r"(?m)^(%autopatch -p1 -m0 -M1\n)",
                   r"\g<1>%autopatch -p1 -m61 -M61\n%autopatch -p1 -m63 -M63\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-3-RC4] ERROR: {p}: no live %autopatch -p1 -m0 -M1 line")
if t != orig:
    p.write_text(t)
    print(f"[runPh7-3-RC4] {p}: RAP/KCFI Patch61 (7.3-rc4 rebase) and Patch63 enabled")
else:
    print(f"[runPh7-3-RC4] {p}: RAP/KCFI patches already enabled")
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
t = re.sub(r"(?m)^Patch6:.*$\n", "", t)
t, n = re.subn(r"(?m)^(Patch1:.*\n)", r"\g<1>" + new6 + "\n", t, count=1)
if n != 1:
    sys.exit(f"[runPh7-3-RC4] ERROR: {p}: no Patch1 line to anchor Patch6")
if "\n%autopatch -p1 -m6 -M6\n" not in t:
    t, n = re.subn(r"(?m)^(%autopatch -p1 -m0 -M1\n)", r"\g<1>%autopatch -p1 -m6 -M6\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-3-RC4] ERROR: {p}: no live %autopatch -p1 -m0 -M1 line")
if t != orig:
    p.write_text(t)
    print(f"[runPh7-3-RC4] {p}: rdrand hwrng driver (Patch6, 7.3-rc4 rebase) enabled")
else:
    print(f"[runPh7-3-RC4] {p}: rdrand hwrng driver already enabled")
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
    t, n = re.subn(r"(?m)^(Patch1:.*\n)", r"\g<1>" + line + "\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-3-RC4] ERROR: {p}: no Patch1 line to anchor Patch7300")
if "\n%autopatch -p1 -m7300 -M7300\n" not in t:
    t, n = re.subn(r"(?m)^(%autopatch -p1 -m0 -M1\n)", r"\g<1>%autopatch -p1 -m7300 -M7300\n", t, count=1)
    if n != 1:
        sys.exit(f"[runPh7-3-RC4] ERROR: {p}: no live %autopatch -p1 -m0 -M1 line")
if t != orig:
    p.write_text(t)
    print(f"[runPh7-3-RC4] {p}: vmwgfx blend mode (Patch7300) enabled")
else:
    print(f"[runPh7-3-RC4] {p}: vmwgfx blend mode already enabled")
PY
}
enable_vmwgfx_73rc4 SPECS/linux/linux.spec || exit 1
enable_vmwgfx_73rc4 SPECS/linux/linux-esx.spec || exit 1

# photon-os-installer: networkd DHCP match by Type=ether/Kind=!* instead of Name=e*.
# downstream-fixes.patch extends this spec (0003..0007), so the 0008 patch file is on
# the branch and appended here as the next PatchN, with one release bump.
pin_installer_73rc4() {
  spec="SPECS/photon-os-installer/photon-os-installer.spec"
  [ -f "$spec" ] || return 0
  python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
fname = "0008-networkmanager-match-dhcp-links-by-type.patch"
if fname in t:
    print(f"[runPh7-3-RC4] {p}: {fname} already applied")
    raise SystemExit(0)
nums = [int(n) for n in re.findall(r"(?m)^Patch(\d+):", t)]
if not nums:
    sys.exit(f"[runPh7-3-RC4] ERROR: {p}: no Patch lines")
last = max(nums)
t, n = re.subn(rf"(?m)^(Patch{last}:.*\n)", rf"\g<1>Patch{last + 1}: {fname}\n", t, count=1)
m = re.search(r"(?m)^(Release:\s*)(\d+)(%\{\?dist\})", t)
if n != 1 or not m:
    sys.exit(f"[runPh7-3-RC4] ERROR: {p}: cannot add {fname}")
rel = int(m.group(2)) + 1
t = t[:m.start()] + f"{m.group(1)}{rel}{m.group(3)}" + t[m.end():]
ver = re.search(r"(?m)^Version:\s*(\S+)", t).group(1)
t = t.replace("%changelog\n", "%changelog\n* Sat Sep 26 2026 Daniel Casota <dcasota@gmail.com> "
              f"{ver}-{rel}\n- networkmanager: match DHCP links by Type=ether/Kind=!* instead of\n"
              "  Name=e*, which networkd flags as an unpredictable name with net.ifnames=0\n", 1)
p.write_text(t)
print(f"[runPh7-3-RC4] {p}: Patch{last + 1} {fname}, release {ver}-{rel}")
PY
}
pin_installer_73rc4 || exit 1
# Replace the 6.12 config-applicability include with a 7.3-rc4 merge:
# olddefconfig keeps Photon =y/=m that still exist, drops gone symbols,
# fills new Kconfig with upstream defaults, then turns off io_uring BPF.
inject_config_merge() {
  spec="$1"
  needle="$2"
  [ -f "$spec" ] || return 0
  echo "[runPh7-3-RC4] config merge on $spec ..."
  python3 - "$spec" "$needle" << 'PY'
import sys
from pathlib import Path
spec, needle = Path(sys.argv[1]), sys.argv[2]
lines = spec.read_text().splitlines(keepends=True)
block = [
    "# 7.3-rc4 config merge: Photon policy kept, obsolete 6.12 symbols dropped.\n",
    "# bpftool BUILD_BPF_SKEL dumps BTF from vmlinux -- keep DEBUG_INFO_BTF where Photon\n",
    "# has it (linux). linux-esx has BTF off and strips module .BTF, so forcing it there\n",
    "# only produced \"missing module BTF, cannot register kfunc\" at nf_conntrack load.\n",
    "# IO_URING_ZCRX stays. IO_URING_BPF_OPS may follow BTF; accepted here.\n",
    "# HYPERV is a bool since 7.x; the 6.12 config has HYPERV=m, which\n",
    "# olddefconfig drops together with every Hyper-V driver. dracut then\n",
    "# fails on add_drivers hv_utils and the kernel boots without initrd.\n",
    "cp .config .config.photon\n",
    "make %{?_smp_mflags} ARCH=%{arch} LC_ALL= olddefconfig\n",
    "if [ -x scripts/config ]; then\n",
    "  scripts/config --enable DEBUG_INFO || :\n",
    "  grep -q '^CONFIG_DEBUG_INFO_BTF=y' .config.photon && scripts/config --enable DEBUG_INFO_BTF || :\n",
    "  scripts/config --disable IO_URING_BPF_OPS || :\n",
    "  if grep -qE '^CONFIG_HYPERV=[ym]$' .config.photon; then\n",
    "    scripts/config --enable HYPERV\n",
    "    grep -E '^CONFIG_[A-Z0-9_]*(HYPERV|HV_)[A-Z0-9_]*=[ym]$' .config.photon | grep -v '^CONFIG_HYPERV=' |\n",
    "      while IFS='=' read -r k v; do scripts/config --set-val \"${k#CONFIG_}\" \"$v\"; done\n",
    "  fi\n",
    "  # Legacy iptables/ip6tables/arptables/ebtables sit behind the new bool\n",
    "  # NETFILTER_XTABLES_LEGACY (default n) since 7.x; restore Photon's set.\n",
    "  if grep -qE '^CONFIG_(IP_NF_IPTABLES|IP6_NF_IPTABLES|BRIDGE_NF_EBTABLES)(_LEGACY)?=[ym]$' .config.photon; then\n",
    "    scripts/config --enable NETFILTER_XTABLES_LEGACY\n",
    "    grep -E '^CONFIG_(IP_NF_|IP6_NF_|BRIDGE_NF_EBTABLES|BRIDGE_EBT_)[A-Z0-9_]*=[ym]$' .config.photon |\n",
    "      while IFS='=' read -r k v; do scripts/config --set-val \"${k#CONFIG_}\" \"$v\"; done\n",
    "  fi\n",
    "  make %{?_smp_mflags} ARCH=%{arch} LC_ALL= olddefconfig\n",
    "fi\n",
    "# Report Photon y/m symbols the merge turned off (review aid, not fatal).\n",
    "grep -E '^CONFIG_[A-Za-z0-9_]+=[ym]$' .config.photon | cut -d= -f1 |\n",
    "  while read -r k; do grep -qE \"^$k=[ym]$\" .config || echo \"config-merge: $k off (on in Photon config)\"; done || :\n",
    "# config merge block end\n",
]
start = next((i for i, l in enumerate(lines) if "7.3-rc4 config merge" in l), None)
if start is not None:
    marker = next((i for i in range(start + 1, len(lines)) if lines[i].strip() == "# config merge block end"), None)
    if marker is not None:
        end = marker + 1
    else:
        # Block from before the end marker existed: it ends at its first "fi".
        end = start + 1
        while end < len(lines) and not lines[end-1].strip() == "fi":
            end += 1
            if end - start > 20:
                break
    lines[start:end] = block
    spec.write_text("".join(lines))
    print(f"[runPh7-3-RC4] {spec}: refreshed 7.3-rc4 config merge")
    raise SystemExit(0)
needle_line = f"%include {needle}"
for i, l in enumerate(lines):
    if needle_line in l:
        lines[i] = "".join(block)
        spec.write_text("".join(lines))
        print(f"[runPh7-3-RC4] {spec}: injected 7.3-rc4 config merge")
        raise SystemExit(0)
for i, l in enumerate(lines):
    if l.strip() == "make ARCH=%{arch} olddefconfig":
        lines[i] = "".join(block)
        spec.write_text("".join(lines))
        print(f"[runPh7-3-RC4] {spec}: upgraded one-line olddefconfig to merge block")
        raise SystemExit(0)
print(f"[runPh7-3-RC4] WARNING: no config-check include in {spec}", file=sys.stderr)
PY
}
inject_config_merge SPECS/linux/linux.spec '%{SOURCE7}'
inject_config_merge SPECS/linux/linux-esx.spec '%{SOURCE4}'

# ENA 2.17.0 fails on 7.x kernels: page_pool_get_stats() is void.
# Skip Amazon ENA/EFA and viomem OOT modules (in-tree ena may still build).
skip_oot_modules() {
  spec="$1"
  [ -f "$spec" ] || return 0
  echo "[runPh7-3-RC4] skip OOT modules in $spec ..."
  python3 - "$spec" << 'PY'
import sys
from pathlib import Path
p = Path(sys.argv[1])
lines = p.read_text().splitlines(keepends=True)
if any("7.3-rc4 skip OOT" in l for l in lines):
    print(f"[runPh7-3-RC4] {p}: OOT modules already skipped")
    raise SystemExit(0)
markers = ("# build ENA module", "# build EFA module", "# build viomem module",
           "# install ENA module", "# install EFA module", "# install viomem module")
count = 0
i = 0
out = []
while i < len(lines):
    if any(lines[i].startswith(m) for m in markers):
        j = i
        while j < len(lines) and lines[j].strip() != "popd":
            j += 1
            if j - i > 30:
                break
        if j < len(lines) and lines[j].strip() == "popd":
            out.append("%if 0\n# 7.3-rc4 skip OOT\n")
            out.extend(lines[i:j+1])
            out.append("%endif\n")
            count += 1
            i = j + 1
            continue
    out.append(lines[i])
    i += 1
if count:
    p.write_text("".join(out))
    print(f"[runPh7-3-RC4] {p}: wrapped {count} ENA/EFA/viomem block(s)")
else:
    print(f"[runPh7-3-RC4] {p}: no ENA/EFA/viomem build blocks found")
PY
}
skip_oot_modules SPECS/linux/linux.spec
skip_oot_modules SPECS/linux/linux-esx.spec

# gettext in the linux sandbox so msgfmt can build cpupower .gmo.
# NLS= remains as fallback if gettext is not yet in the graph.
add_buildrequires() {
  spec="$1"
  pkg="$2"
  [ -f "$spec" ] || return 0
  if grep -qE "^BuildRequires:[[:space:]]*${pkg}([[:space:]]|\$)" "$spec"; then
    echo "[runPh7-3-RC4] $spec already BuildRequires: $pkg"
    return 0
  fi
  python3 - "$spec" "$pkg" << 'PY'
import sys
from pathlib import Path
p, pkg = Path(sys.argv[1]), sys.argv[2]
lines = p.read_text().splitlines(keepends=True)
ins = f"BuildRequires:  {pkg}\n"
for i, l in enumerate(lines):
    if l.startswith("BuildRequires:"):
        lines.insert(i, ins)
        p.write_text("".join(lines))
        print(f"[runPh7-3-RC4] {p}: added BuildRequires: {pkg}")
        raise SystemExit(0)
p.write_text(ins + "".join(lines))
print(f"[runPh7-3-RC4] {p}: prepended BuildRequires: {pkg}")
PY
}
add_buildrequires SPECS/linux/linux.spec gettext
add_buildrequires SPECS/linux/linux-esx.spec gettext

pin_cpupower_nls() {
  spec="$1"
  [ -f "$spec" ] || return 0
  if grep -q 'cpupower_install NLS=' "$spec"; then
    echo "[runPh7-3-RC4] $spec already has cpupower NLS="
    return 0
  fi
  if grep -q 'cpupower_install' "$spec"; then
    sed -i 's/cpupower_install/cpupower_install NLS=/' "$spec"
    echo "[runPh7-3-RC4] $spec: cpupower_install NLS= (skip missing .gmo)"
  fi
}
pin_cpupower_nls SPECS/linux/linux.spec
pin_cpupower_nls SPECS/linux/linux-esx.spec

# cxxwrap + rust.channel=dev made stage1 compile rustc diagnostics as
# <anon> (backticks in E0658 proc_macro_span). Restore upstream rust.spec.
# docs=false is re-applied by pin_rust_skip_docs after this.
pin_rust_probe() {
  spec="SPECS/rust/rust.spec"
  [ -f "$spec" ] || spec=$(find SPECS -name rust.spec 2>/dev/null | head -n1)
  [ -n "$spec" ] && [ -f "$spec" ] || return 0
  git checkout -- "$spec" 2>/dev/null || true
  echo "[runPh7-3-RC4] rust: restored upstream spec (no cxxwrap, no channel=dev)"
  python3 - "$spec" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
text = p.read_text()
lines, out, skip = text.splitlines(keepends=True), [], False
for l in lines:
    if "7.3-rc4 rust" in l:
        skip = True
        continue
    if skip:
        if l.startswith("export CC_x86_64") or l.startswith("export CXX_x86_64") or l.startswith("export CC=") or l.startswith("export CXX="):
            skip = False
            continue
        continue
    out.append(l)
text = "".join(out)
hook = "# 7.3-rc4 rust locale only\nexport LANG=C LC_ALL=C LC_MESSAGES=C GCC_COLORS=\n"
if hook not in text:
    text = text.replace("%build\n", "%build\n" + hook, 1)
p.write_text(text)
print(f"[runPh7-3-RC4] {p}: upstream rust.spec + LANG=C only")
PY
}
# orphaned cxxwrap body removed
pin_linux_files() {
  spec="$1"
  [ -f "$spec" ] || return 0
  echo "[runPh7-3-RC4] %files cleanup on $spec ..."
  python3 - "$spec" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
text = p.read_text()
orig = text
text = text.replace("%dir %{_docdir}/linux-%{uname_r}", "%{_docdir}/linux-%{uname_r}/*")
text = text.replace("# {_docdir}/perf-tip", "%{_docdir}/perf-tip")
text = text.replace("# {_sysconfdir}/bash_completion.d/perf", "%{_sysconfdir}/bash_completion.d/perf")
text = text.replace("# {_datadir}/perf-core  # 7.3-rc4 perf install path changed", "%{_datadir}/perf-core")
text = text.replace("# {_libexecdir}/perf-core", "%{_libexecdir}/perf-core")
if "%{_datadir}/locale/*/LC_MESSAGES/cpupower.mo" in text:
    text = text.replace(
        "%{_datadir}/locale/*/LC_MESSAGES/cpupower.mo",
        "# {_datadir}/locale/*/LC_MESSAGES/cpupower.mo",
    )
if "/etc/cpupower-service.conf" not in text:
    extra = (
        "%config(noreplace) /etc/cpupower-service.conf\n"
        "/usr/lib/systemd/system/cpupower.service\n"
        "/usr/libexec/cpupower\n"
    )
    # Only where a tools subpackage exists; appending at EOF would land
    # inside %changelog (linux-esx has no %files tools).
    if "%files tools\n" in text:
        text = text.replace("%files tools\n", "%files tools\n" + extra, 1)
hook = (
    "# 7.3-rc4 mkdir perf-core\n"
    "mkdir -p %{buildroot}%{_datadir}/perf-core\n"
    "mkdir -p %{buildroot}%{_libexecdir}/perf-core\n"
    "mkdir -p %{buildroot}%{_sysconfdir}/bash_completion.d\n"
    "touch %{buildroot}%{_sysconfdir}/bash_completion.d/perf || :\n"
)
# The perf files belong to %files tools. linux-esx has no tools subpackage,
# so the touched bash_completion.d/perf would be an unpackaged file there;
# drop the hook again from specs an older pin already gave it to.
if "%files tools\n" not in text:
    text = text.replace(hook, "")
elif "7.3-rc4 mkdir perf-core" not in text:
    lines = text.splitlines(keepends=True)
    for i, l in enumerate(lines):
        if l.startswith("%install"):
            lines.insert(i + 1, hook)
            text = "".join(lines)
            break
if text != orig:
    p.write_text(text)
    print(f"[runPh7-3-RC4] {p}: docs glob restored, perf-core dirs ensured")
else:
    print(f"[runPh7-3-RC4] {p}: %files already consistent")
PY
}
pin_linux_files SPECS/linux/linux.spec
pin_linux_files SPECS/linux/linux-esx.spec

pin_rust_skip_docs() {
  spec="SPECS/rust/rust.spec"
  [ -f "$spec" ] || spec=$(find SPECS -name rust.spec 2>/dev/null | head -n1)
  [ -n "$spec" ] && [ -f "$spec" ] || return 0
  echo "[runPh7-3-RC4] rust docs=false via configure (strip bootstrap shim) ..."
  python3 - "$spec" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
lines = p.read_text().splitlines(keepends=True)
out, skip = [], False
for l in lines:
    if l.startswith("# 7.3-rc4 rust docs=false") or l.startswith("_rust_disable_docs"):
        skip = True
        continue
    if skip:
        if l.startswith("trap _rust_disable_docs"):
            skip = False
        continue
    out.append(l)
text = "".join(out)
if "build.docs=false" not in text:
    text = text.replace("sh ./configure \\", "sh ./configure --set build.docs=false \\")
    text = text.replace("sh ./configure\n", "sh ./configure --set build.docs=false\n")
    text = text.replace("sh ./configure ", "sh ./configure --set build.docs=false ")
if "rust.channel=dev" not in text and "build.docs=false" in text:
    text = text.replace("--set build.docs=false", "--set build.docs=false")
if "%make_build BOOTSTRAP_ARGS=-vv" in text and "--skip" not in text:
    text = text.replace(
        "%make_build BOOTSTRAP_ARGS=-vv",
        "%make_build BOOTSTRAP_ARGS='-vv'",
    )
# Cargo still installs man pages even with build.docs=false.
# They must stay in %files or rpmbuild dies on unpackaged files.
text = text.replace(
    "# 7.3-rc4 rust-doc files: man pages absent when docs=false\n# {_mandir}/man1/*",
    "%{_mandir}/man1/*",
)
text = text.replace("# {_mandir}/man1/*", "%{_mandir}/man1/*")
if "%{_mandir}/man1/*" not in text and "%files doc" in text:
    text = text.replace("%files doc\n", "%files doc\n%{_mandir}/man1/*\n", 1)
restore = (
    "# 7.3-rc4 restore bootstrap.py if a prior shim moved it\n"
    "if [ -f src/bootstrap/bootstrap.py.real ]; then\n"
    "  mv -f src/bootstrap/bootstrap.py.real src/bootstrap/bootstrap.py\n"
    "fi\n"
)
if "prior shim moved it" not in text:
    lines = text.splitlines(keepends=True)
    for i, l in enumerate(lines):
        if l.startswith("%build"):
            lines.insert(i + 1, restore)
            text = "".join(lines)
            break
p.write_text(text)
print(f"[runPh7-3-RC4] {p}: configure --set build.docs=false; bootstrap shim removed")
PY
}
pin_rust_skip_docs

pin_postgres_config() {
  spec="SPECS/postgresql/postgresql18.spec"
  [ -f "$spec" ] || spec=$(find SPECS -name 'postgresql18.spec' 2>/dev/null | head -n1)
  [ -n "$spec" ] && [ -f "$spec" ] || return 0
  python3 - "$spec" << 'PY'
from pathlib import Path
import re
p = Path(__import__("sys").argv[1])
text = p.read_text()
if "--cache-file=/dev/null" not in text:
    text = text.replace("sh ./configure \\", "sh ./configure --cache-file=/dev/null \\")
    text = text.replace("sh ./configure ", "sh ./configure --cache-file=/dev/null ")
text = text.replace("    --mandir=%{_pgmandir}\n", "    --mandir=%{_pgmandir} || true\n")
sanitizer = (
    "\n# 7.3-rc4 postgres config.status sanitizer\n"
    "if grep -qE '^0a[0-9]' config.status 2>/dev/null; then\n"
    "  echo '[runPh7-3-RC4] stripping ed cache blob only (keep Makefile rules)'\n"
    "  awk 'BEGIN{s=0} /^0a[0-9]/{s=1;next} s && /^> /{next} "
    "s && (/^[wq.]$/){s=0;next} s && /^[A-Za-z_#{$]/ {s=0} {if(!s) print}' "
    "config.status > config.status.fix && mv config.status.fix config.status\n"
    "  chmod +x config.status\n"
    "fi\n"
    "if [ ! -f src/Makefile.global ]; then\n"
    "  echo '[runPh7-3-RC4] re-run config.status to write Makefile.global'\n"
    "  sh ./config.status || true\n"
    "fi\n"
)
text = re.sub(
    r"\n# 7.3-rc4 postgres config.status sanitizer\n.*?(?=%make_build world)",
    sanitizer,
    text,
    count=1,
    flags=re.S,
)
if "# 7.3-rc4 postgres config.status sanitizer" not in text:
    text = text.replace("%make_build world", sanitizer + "%make_build world")
p.write_text(text)
print(f"[runPh7-3-RC4] {p}: cache-file=/dev/null + safe sanitizer")
PY
}
pin_postgres_config

pin_svn_nodebug() {
  spec="SPECS/subversion/subversion.spec"
  [ -f "$spec" ] || spec=$(find SPECS -name subversion.spec 2>/dev/null | head -n1)
  [ -n "$spec" ] && [ -f "$spec" ] || return 0
  if grep -q '7.3-rc4 exclude debug' "$spec"; then
    echo "[runPh7-3-RC4] $spec already excludes /usr/lib/debug"
    return 0
  fi
  python3 - "$spec" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
text = p.read_text()
ex = "%exclude /usr/lib/debug\n# 7.3-rc4 exclude debug\n"
out = []
for line in text.splitlines(keepends=True):
    out.append(line)
    if line.startswith("%files"):
        out.append(ex)
p.write_text("".join(out))
print(f"[runPh7-3-RC4] {p}: exclude /usr/lib/debug from %files")
PY
}
pin_svn_nodebug

pin_docker_devnull() {
  spec="SPECS/docker/docker.spec"
  [ -f "$spec" ] || spec=$(find SPECS -name docker.spec 2>/dev/null | head -n1)
  [ -n "$spec" ] && [ -f "$spec" ] || return 0
  if grep -q '7.3-rc4 /dev/null' "$spec"; then
    echo "[runPh7-3-RC4] $spec already ensures /dev/null"
  else
    python3 - "$spec" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
text = p.read_text()
hook = "# 7.3-rc4 /dev/null\nmkdir -p /dev /tmp\n[ -e /dev/null ] || mknod -m 666 /dev/null c 1 3\n[ -e /dev/zero ] || mknod -m 666 /dev/zero c 1 5\n"
if "%build\n" in text:
    p.write_text(text.replace("%build\n", "%build\n" + hook, 1))
    print(f"[runPh7-3-RC4] {p}: mknod /dev/null in %build")
PY
  fi
}
pin_docker_devnull

fix_null_node() {
  path="$1"
  [ -c "$path" ] && return 0
  echo "[runPh7-3-RC4] $path is not a char device; recreating c 1 3"
  rm -f "$path" 2>/dev/null || true
  if ! mknod -m 666 "$path" c 1 3; then
    echo "[runPh7-3-RC4] mknod $path failed (need CAP_MKNOD). docker POI will break." 1>&2
    return 1
  fi
  [ -c "$path" ] && return 0
  echo "[runPh7-3-RC4] ERROR: $path still not char device after mknod" 1>&2
  ls -l "$path" 1>&2 || true
  return 1
}

ensure_sandbox_dev() {
  fix_null_node /dev/null || true
  if [ ! -c /dev/zero ]; then
    rm -f /dev/zero 2>/dev/null || true
    mknod -m 666 /dev/zero c 1 5 2>/dev/null || true
  fi
  ls -l /dev/null /dev/zero 2>/dev/null || true
  stage="$BASE_DIR/$RELEASE_BRANCH/stage/images/sandboxBase"
  if [ -d "$stage" ]; then
    mkdir -p "$stage/dev" "$stage/tmp"
    fix_null_node "$stage/dev/null" || true
  fi
  if [ -c /dev/null ]; then
    echo "[runPh7-3-RC4] host /dev/null is a char device (docker POI ok)"
  else
    echo "[runPh7-3-RC4] WARNING: host /dev/null is still not c 1 3 — ISO docker run will fail" 1>&2
  fi
}
ensure_sandbox_dev

pin_apparmor_perl() {
  spec="SPECS/apparmor/apparmor.spec"
  [ -f "$spec" ] || spec=$(find SPECS -name apparmor.spec 2>/dev/null | head -n1)
  [ -n "$spec" ] && [ -f "$spec" ] || return 0
  if grep -q '7.3-rc4 apparmor perl paths' "$spec"; then
    echo "[runPh7-3-RC4] $spec already has perl path fallback"
    return 0
  fi
  python3 - "$spec" << 'PY'
from pathlib import Path
p = Path(__import__("sys").argv[1])
text = p.read_text()
header = (
    "# 7.3-rc4 apparmor perl paths\n"
    "%{!?perl_vendorarch:%global perl_vendorarch %{_libdir}/perl5/vendor_perl}\n"
    "%{!?perl_archlib:%global perl_archlib %{_libdir}/perl5}\n"
)
if header not in text:
    text = text.replace("%build\n", header + "%build\n", 1)
install = (
    "\n# 7.3-rc4 apparmor perl stub if bindings missing\n"
    "mkdir -p %{buildroot}%{perl_vendorarch}/auto/LibAppArmor\n"
    "touch %{buildroot}%{perl_vendorarch}/LibAppArmor.pm\n"
)
if "apparmor perl stub" not in text:
    text = text.replace("%install\n", "%install\n" + install, 1)
p.write_text(text)
print(f"[runPh7-3-RC4] {p}: perl_vendorarch fallback + stub files")
PY
}
pin_apparmor_perl

pin_rust_probe
pin_rust_skip_docs












wipe_kernel_sandboxes

K73RC4_SHA="7a4b9599c2c593131e150ae22030f643813b0fb3de2b479281ebb9a413e7928903adc748eb522e03fd39e9ca4991c12e4d0331718fff59a53fc6676b390c7945"
if command -v fetch_or_validate_source >/dev/null 2>&1; then
  fetch_or_validate_source \
    "linux-7.3-rc4.tar.gz" \
    "https://git.kernel.org/torvalds/t/linux-7.3-rc4.tar.gz" \
    "$K73RC4_SHA" || true
fi

if [ -f SPECS/linux/linux.spec ]; then
  kver=$(awk '/^Version:/{print $2; exit}' SPECS/linux/linux.spec 2>/dev/null)
  echo "[runPh7-3-RC4] linux.spec Version=$kver"
  if [ "${PIN_REQUIRE_KVER:-1}" = 1 ] && [ "$kver" != "7.3.0" ]; then
    echo "[runPh7-3-RC4] ERROR: linux.spec Version is '$kver', expected 7.3.0 (7.3-rc4)" 1>&2
    exit 1
  fi
else
  echo "[runPh7-3-RC4] linux.spec not in $PWD (helper pre-pass?); skipping version assert"
fi

# build.py runs support/spec-checker on every modified spec when stdout is
# not a TTY (nohup, CI, no-pty sessions). Keep the pinned specs clean:
# no double blank lines, no blank line inside %changelog.
pin_spec_lint() {
  for spec in SPECS/linux/linux.spec SPECS/linux/linux-esx.spec \
              SPECS/postgresql/postgresql18.spec; do
    [ -f "$spec" ] || continue
    python3 - "$spec" << 'PY'
import re, sys
from pathlib import Path
p = Path(sys.argv[1])
t = p.read_text()
nt = re.sub(r"\n[ \t]*\n(?:[ \t]*\n)+", "\n\n", t)
if "\n%changelog\n" in nt:
    head, log = nt.split("\n%changelog\n", 1)
    log = "\n".join(l for l in log.split("\n") if l.strip()) + "\n"
    nt = head + "\n%changelog\n" + log
if nt != t:
    p.write_text(nt)
    print(f"[runPh7-3-RC4] {p}: spec-checker whitespace normalized")
PY
  done
}
pin_spec_lint

worktree_now
EMBEDPIN

sed \
  -e 's/\[runPh5_normal\]/[runPh7-3-RC4]/g' \
  -e 's/\.runph5-iso-marker/.runph73rc4-iso-marker/g' \
  -e 's/RELEASE_BRANCH="${3:-5.0}"/RELEASE_BRANCH="${3:-experimental\/linux-7.3-rc4}"/' \
  -e 's/CANISTER_MODE="${6:-prebuilt}"/CANISTER_MODE="${6:-none}"/' \
  -e 's/prebuilt|build|acvp|kat)/none|prebuilt|build|acvp|kat)/' \
  -e "s/{'prebuilt': \\[\\]/{'none': [], 'prebuilt': []/g" \
  "$SRC" > "$GEN"

python3 - "$GEN" "$PINOUT" << 'PY'
import sys
from pathlib import Path
gen, pin = Path(sys.argv[1]), sys.argv[2]
lines = gen.read_text().splitlines(keepends=True)
out, i, replaced = [], 0, False
while i < len(lines):
    if (not replaced) and 'if git apply "$DOWNSTREAM_PATCH"' in lines[i]:
        depth, started = 0, False
        while i < len(lines):
            l = lines[i]
            if l.lstrip().startswith('if '):
                depth += 1
                started = True
            if l.lstrip().startswith('fi'):
                depth -= 1
                i += 1
                if started and depth == 0:
                    break
                continue
            i += 1
        out.append('''    if git apply "$DOWNSTREAM_PATCH"; then
      echo "[runPh7-3-RC4] Applied downstream-fixes.patch"
    elif git apply --exclude='SPECS/linux/*' --exclude='SPECS/90/*' --exclude='SPECS/openssh/*' --exclude='SPECS/stig-hardening/stig-hardening.spec' "$DOWNSTREAM_PATCH"; then
      echo "[runPh7-3-RC4] Applied downstream-fixes.patch with stale-spec excludes"
    else
      echo "[runPh7-3-RC4] WARNING: downstream-fixes.patch still does not apply; continuing" 1>&2
    fi
''')
        replaced = True
        continue
    out.append(lines[i])
    i += 1
text = ''.join(out)
idx = text.find('NOTE: photonos-patches/downstream-fixes.patch not found')
if idx < 0:
    sys.exit('NOTE line missing')
fi_at = text.find('\n  fi\n', idx)
if fi_at < 0:
    sys.exit('closing fi missing')
insert_at = fi_at + len('\n  fi\n')
text = text[:insert_at] + f'\n  . "{pin}"\n' + text[insert_at:]

# Re-run the pin immediately before every make. runPh5_normal.sh may
# git checkout -- the specs after the first pin, which would put Patch2 back.
fix = f'''
  . "{pin}"
'''
text2 = []
for line in text.splitlines(keepends=True):
    if 'sudo make' in line or (line.lstrip().startswith('make ') and 'image' in line):
        text2.append(fix)
    if 'sudo make' in line and 'image IMG_NAME' in line:
        ind = line[: len(line) - len(line.lstrip())]
        text2.append(
            ind + '# 7.3-rc4: build the ISO KS_STIG_PACKAGES set and branch-updated packages before make image\n'
            + ind + 'sudo make -j8 pkgs="audit,rsyslog,openssl-fips-provider,selinux-policy,'
            'libselinux-utils,ntpsec,aide,libgcrypt,cloud-init,sudo,dbus,photon-os-installer" THREADS=8 || '
            'echo "[runPh7-3-RC4] WARNING: STIG package pre-build failed" 1>&2\n'
        )
    text2.append(line)
text = ''.join(text2)
if not replaced:
    sys.exit('apply block missing')
gen.write_text(text)
print('[runPh7-3-RC4] generated apply+pin+common-path rewrite ok')
PY

chmod +x "$GEN" "$PINOUT"
if [ ! -c /dev/null ]; then
  echo "[runPh7-3-RC4] repairing host /dev/null before ISO docker"
  rm -f /dev/null 2>/dev/null || true
  mknod -m 666 /dev/null c 1 3 2>/dev/null || true
fi
ls -l /dev/null
echo "[runPh7-3-RC4] using $SRC"
echo "[runPh7-3-RC4] Image type: $IMG_TYPE"
echo "[runPh7-3-RC4] Canister mode: $CANISTER_MODE"
echo "[runPh7-3-RC4] Release branch: $RELEASE_BRANCH"
# Run collected worktree helpers in THIS shell (export vars; never sh -c).
COMMON_DIR="${COMMON_DIR:-$BASE_DIR/$COMMON_BRANCH}"
export BASE_DIR COMMON_BRANCH RELEASE_BRANCH COMMON_DIR OUTPUT_DIR IMG_TYPE CANISTER_MODE
if [ -d "$BASE_DIR/$RELEASE_BRANCH" ]; then
  (
    cd "$BASE_DIR/$RELEASE_BRANCH" || exit 1
    export BASE_DIR COMMON_BRANCH RELEASE_BRANCH
    export PIN_REQUIRE_KVER=0
    . "$PINOUT"
  )
fi
exec /bin/sh "$GEN" "$BASE_DIR" "$COMMON_BRANCH" "$RELEASE_BRANCH" "$OUTPUT_DIR" "$IMG_TYPE" "$CANISTER_MODE"
