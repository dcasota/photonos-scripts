#!/usr/bin/env python3
"""Regenerate src/embedded/canister-equivalent.patch against the current tree.

The embedded patch layers on top of the installer variant patch, so its context
lines carry whatever kernel Release the variant patch produces. Every time the
kernel moves - upstream bumped 6.12.107-8 -> -11 on 2026-09-11, and the two
canister PRs then take it to -13 - the patch stops applying and the equivalent
build dies at [inject:embedded[release]:canister-equivalent] seconds after it
starts:

    sharukhan: embedded patch canister-equivalent no longer applies to the
    release tree. It layers on top of the variant patch, so either that changed
    or the tree moved under both.

It had been retargeted by hand three times before this script existed (releases
1 -> 4 -> 8 -> 11). Hand-editing a diff is how you get context that applies but
means something else, so: regenerate from the real tree, never edit the .patch.

What the patch has to express, and why it cannot just be checked in as a spec:

  1. fips_canister_version becomes overridable - canister_equivalent=1 plus
     fips_canister_override=<NEVR> - so phase B can link the canister phase A
     just built instead of the published pin.
  2. fips_certified_kernel_version becomes overridable the same way, via
     canister_stamp_real=1 plus fips_certified_override=<NEVR>, so a newly
     created canister stamps the kernel it was really built from rather than
     inheriting a certification it does not carry.
  3. Both use a 0/1 flag plus a separate value macro, wrapped in %if, rather
     than the bang-question guard form. Photon's SpecParser is stricter than
     rpm: _isDefinition() matches only a line STARTING with %define/%global, so
     a guarded definition never reaches self.defs and
     ExtraBuildRequiresSansSnapshot keeps the macro literal - the build then
     asks tdnf for a package whose name still contains "%{fips_canister_version}".
     And the version cannot ride in the %if either: _isConditionTrue() eval()s
     the expanded text after lstrip("0"), which is a NameError for a version
     string.

Usage:  tools/regen-canister-equivalent.py [--variant <patch>] [--check]

--check regenerates into a temp file and diffs against the committed patch,
exiting non-zero if they differ. Use it to find out that the patch has gone
stale BEFORE spending an hour discovering it mid-build.
"""
import argparse, os, re, subprocess, sys, tempfile, shutil

REPO = "/root/5.0"
HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PATCH_OUT = os.path.join(HERE, "src/embedded/canister-equivalent.patch")
DEFAULT_VARIANT = "/root/photon-mc/variant-patches/poi-2.8.patch"


def sh(cwd, *args, check=True):
    r = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    if check and r.returncode != 0:
        sys.exit(f"{' '.join(args)}: rc={r.returncode}\n{r.stderr}")
    return r.stdout


def version_of(path):
    """The Version: from a spec.

    Read, never hardcoded. The first version of this script wrote a literal
    6.12.107 into the changelog entries while taking Release from the tree, so
    the moment upstream moved to 6.12.109 it emitted

        ERROR in linux.spec: Changelog & Release version mismatch
                             6.12.107-4 != 6.12.109-4

    and build.py refused the spec before compiling anything - the same
    derive-never-hardcode rule this script exists to enforce, broken by the
    script itself.
    """
    with open(path) as f:
        for line in f:
            if line.startswith("Version:"):
                return line.split(None, 1)[1].strip()
    sys.exit(f"{path}: no Version:")


def release_of(path):
    """The numeric Release: from a spec, without rpm conditionals or dist tag."""
    with open(path) as f:
        for line in f:
            if line.startswith("Release:"):
                return int(re.match(r"Release:\s+(\d+)", line).group(1))
    sys.exit(f"{path}: no Release:")


def edit_linux_spec(path, ver, old_rel, new_rel, date):
    s = open(path).read()

    # 1. fips_certified_kernel_version, overridable.
    old_cert = """# This is the last certified canister version
# Remove below line when building a new canister
%define fips_certified_kernel_version 6.12.60-18.ph5
"""
    new_cert = """# This is the last certified canister version, stamped into fips_integrity.c.
# A build that creates a NEW canister must stamp the kernel it was really built
# from rather than inherit a certification it does not carry, so
# canister_stamp_real=1 plus fips_certified_override=<NEVR> replaces it. Same
# two-macro shape as fips_canister_version below, for the same parser reasons.
%if 0%{?canister_stamp_real}
%define fips_certified_kernel_version %{fips_certified_override}
%else
%define fips_certified_kernel_version 6.12.60-18.ph5
%endif
"""
    if old_cert not in s:
        sys.exit("linux.spec: the fips_certified_kernel_version block is not "
                 "where this script expects it; the spec changed shape upstream "
                 "and this script must be updated, not worked around.")
    s = s.replace(old_cert, new_cert, 1)

    # 2. fips_canister_version, overridable.
    old_can = "%define fips_canister_version 6.12.60-18.2.ph5\n"
    new_can = """# Which canister this build links.
#
# Default: the published, certified one. A build that has just created an
# equivalent canister from the kernel under test overrides it with
# canister_equivalent=1 plus fips_canister_override=<NEVR>.
#
# Two macros rather than one, and an %%if rather than a bang-question guard,
# because Photon's own SpecParser is stricter than rpm:
#   - _isDefinition() matches only a line STARTING with %%define/%%global, so
#     a guard of the bang-question form never reaches self.defs and
#     ExtraBuildRequiresSansSnapshot keeps the macro literal;
#   - _isConditionTrue() eval()s the expanded text after lstrip("0"), which is
#     fine for a 0/1 flag and a NameError for a version string.
# So the flag is what %%if tests, and the version rides in a second macro.
%if 0%{?canister_equivalent}
%define fips_canister_version %{fips_canister_override}
%else
%define fips_canister_version 6.12.60-18.2.ph5
%endif
"""
    if old_can not in s:
        sys.exit("linux.spec: the fips_canister_version define is not where "
                 "this script expects it.")
    s = s.replace(old_can, new_can, 1)

    # 3. Release bump + changelog. A spec change gets both, and the changelog
    #    must stay in descending order or check_spec rejects it.
    s = s.replace(f"Release:        {old_rel}%", f"Release:        {new_rel}%", 1)
    entry = f"""* {date} Daniel Casota <dcasota@gmail.com> {ver}-{new_rel}
- Let a build link a canister other than the published one, so a kernel with no
  official canister at its own level can be covered by an equivalent one built
  locally. canister_equivalent=1 plus fips_canister_override=<NEVR> selects it;
  with neither set the published pin is used and nothing changes.
- Same for fips_certified_kernel_version via canister_stamp_real=1 plus
  fips_certified_override=<NEVR>, so a newly created canister stamps the kernel
  it was really built from instead of inheriting a certification it does not
  carry.
- Both wrap a plain definition in a conditional on a 0/1 flag, rather than
  using the bang-question guard form. rpm expands that guard correctly, but
  Photon's SpecParser._isDefinition() matches only a line STARTING with a
  definition directive, so the guard never reaches self.defs and
  ExtraBuildRequiresSansSnapshot keeps the macro unexpanded - the build then
  asks tdnf for a package whose name still contains the macro reference. The
  version cannot be tested by the conditional either: _isConditionTrue() runs
  eval() on the expanded text after lstrip("0"), which is a NameError for a
  version string. Hence a 0/1 flag plus a separate value macro.
"""
    s = s.replace("%changelog\n", "%changelog\n" + entry, 1)
    open(path, "w").write(s)


def edit_esx_spec(path, ver, old_rel, new_rel, date):
    s = open(path).read()

    # The same override pair as linux.spec. linux-esx never CREATES a canister
    # (canister_build is hardcoded 0 for it, finding #43) - it only links one -
    # and it is the flavour every matrix row actually boots. A phase B that
    # taught only linux.spec about the local canister would relink linux and
    # leave linux-esx pinned to the published one, shipping a kernel that never
    # consumed the canister under test while every build check passed.
    old_can = "%define fips_canister_version 6.12.60-18.2.ph5\n"
    new_can = """# Which canister this build links.
#
# Default: the published, certified one. A build that has just created an
# equivalent canister from the kernel under test overrides it with
# canister_equivalent=1 plus fips_canister_override=<NEVR>.
#
# Two macros rather than one, and an %%if rather than a bang-question guard,
# because Photon's own SpecParser is stricter than rpm:
#   - _isDefinition() matches only a line STARTING with %%define/%%global, so
#     a guard of the bang-question form never reaches self.defs and
#     ExtraBuildRequiresSansSnapshot keeps the macro literal;
#   - _isConditionTrue() eval()s the expanded text after lstrip("0"), which is
#     fine for a 0/1 flag and a NameError for a version string.
# So the flag is what %%if tests, and the version rides in a second macro.
%if 0%{?canister_equivalent}
%define fips_canister_version %{fips_canister_override}
%else
%define fips_canister_version 6.12.60-18.2.ph5
%endif
"""
    if old_can not in s:
        sys.exit("linux-esx.spec: the fips_canister_version define is not where "
                 "this script expects it.")
    s = s.replace(old_can, new_can, 1)

    s = s.replace(f"Release:        {old_rel}%", f"Release:        {new_rel}%", 1)
    entry = f"""* {date} Daniel Casota <dcasota@gmail.com> {ver}-{new_rel}
- Accept the same canister_equivalent / fips_canister_override pair as
  linux.spec, so this flavour - the one the ISO actually boots - can link a
  locally built canister too. It never builds one; it only links.
"""
    s = s.replace("%changelog\n", "%changelog\n" + entry, 1)
    open(path, "w").write(s)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", default=DEFAULT_VARIANT)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--date", default=None, help="changelog date, e.g. 'Thu Sep 11 2026'")
    a = ap.parse_args()

    if not os.path.exists(a.variant):
        sys.exit(f"{a.variant}: not found - run `sharukhan variant-patches` first")

    date = a.date or subprocess.run(
        ["date", "-u", "+%a %b %d %Y"], capture_output=True, text=True).stdout.strip()

    tmp = tempfile.mkdtemp(prefix="regen-caneq-")
    tree = os.path.join(tmp, "t")
    try:
        sh(REPO, "git", "worktree", "add", "-f", "-q", "--detach", tree, "origin/5.0")
        sh(tree, "git", "apply", a.variant)
        # Commit the variant state so `git diff` below is the EMBEDDED delta
        # alone. Diffing against origin/5.0 instead would fold the variant
        # patch's own Release bump into the embedded patch, which then applies
        # on top of itself and conflicts - the first draft of this script did
        # exactly that and produced "11 -> 14" where the truth is "13 -> 14".
        sh(tree, "git", "add", "-A")
        sh(tree, "git", "-c", "user.email=x@y", "-c", "user.name=x",
           "commit", "-q", "-m", "variant baseline")

        linux = os.path.join(tree, "SPECS/linux/linux.spec")
        esx = os.path.join(tree, "SPECS/linux/linux-esx.spec")
        lrel, erel = release_of(linux), release_of(esx)
        print(f"  variant patch leaves linux at {version_of(linux)}-{lrel}, "
              f"linux-esx at {version_of(esx)}-{erel}")

        lver, ever = version_of(linux), version_of(esx)
        edit_linux_spec(linux, lver, lrel, lrel + 1, date)
        edit_esx_spec(esx, ever, erel, erel + 1, date)
        print(f"  embedded patch takes linux to -{lrel+1}, linux-esx to -{erel+1}")

        diff = sh(tree, "git", "diff", "--", "SPECS/linux/linux.spec",
                  "SPECS/linux/linux-esx.spec", check=False)
        # Strip the index lines: they carry blob hashes that churn on every
        # base move and would make the patch look changed when it is not.
        diff = "\n".join(l for l in diff.splitlines()
                         if not l.startswith("index ") and not l.startswith("diff --git")) + "\n"

        if a.check:
            cur = open(PATCH_OUT).read()
            if cur == diff:
                print("  up to date")
                return 0
            print("  STALE: the committed patch does not match a regeneration")
            return 1

        checker = "/root/common/support/spec-checker/check_spec.py"
        if os.path.exists(checker):
            r = subprocess.run([sys.executable, checker, linux, esx],
                               capture_output=True, text=True)
            if r.returncode != 0:
                sys.exit("the regenerated specs do not pass check_spec:\n"
                         + (r.stdout or "") + (r.stderr or ""))
            print("  check_spec: exit 0")

        open(PATCH_OUT, "w").write(diff)
        print(f"  wrote {PATCH_OUT} ({len(diff.splitlines())} lines)")
        return 0
    finally:
        subprocess.run(["git", "-C", REPO, "worktree", "remove", "--force", tree],
                       capture_output=True)
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
