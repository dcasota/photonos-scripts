#!/usr/bin/env python3
"""
Photon OS Gating Conflict Detection Agent

Scans build trees for conflicts between build_if subrelease gating and
snapshot pinning. Detects 6 conflict constellations (C1-C6).

Usage:
  python3 photon-gating-agent.py --base-dir /root --branches 5.0,6.0 --arch x86_64
"""

import argparse
import json
import os
import re
import sys
import hashlib
from collections import defaultdict
from datetime import datetime, timezone

try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    HAS_REQUESTS = False

try:
    import jsonschema
    HAS_JSONSCHEMA = True
except ImportError:
    HAS_JSONSCHEMA = False


def parse_args():
    p = argparse.ArgumentParser(description="Photon OS Gating Conflict Detection")
    p.add_argument("--base-dir", required=True, help="Root directory containing branch checkouts")
    p.add_argument("--branches", default="4.0,5.0,6.0", help="Comma-separated branch names")
    p.add_argument("--arch", default="x86_64", help="Target architecture")
    p.add_argument("--check-urls", action="store_true", help="Enable HTTP probing of snapshot URLs (C6)")
    p.add_argument("--phase", choices=["inventory", "detect", "all"], default="all")
    p.add_argument("--inventory", help="Path to existing inventory JSON (skip Phase 0)")
    p.add_argument("--output", help="Output path for inventory JSON")
    p.add_argument("--json-output", default="findings.json", help="JSON findings output")
    p.add_argument("--md-output", default="findings.md", help="Markdown findings output")
    p.add_argument("--schema", help="Path to JSON schema for validation")
    return p.parse_args()


# ---------------------------------------------------------------------------
# Spec Parsing
# ---------------------------------------------------------------------------

BUILD_IF_RE = re.compile(
    r'%\{?global\}?\s+build_if\s+(.*)', re.IGNORECASE
)
SUBRELEASE_GATE_RE = re.compile(
    r'%\{photon_subrelease\}\s*(<=|>=|<|>|==|!=)\s*(\d+)'
)
NAME_RE = re.compile(r'^Name:\s*(.+)', re.MULTILINE | re.IGNORECASE)
VERSION_RE = re.compile(r'^Version:\s*(.+)', re.MULTILINE | re.IGNORECASE)
RELEASE_RE = re.compile(r'^Release:\s*(.+)', re.MULTILINE | re.IGNORECASE)
SUBPKG_RE = re.compile(r'^%package\s+(?:-n\s+)?(.+)', re.MULTILINE | re.IGNORECASE)
REQUIRES_RE = re.compile(r'^(?:Build)?Requires:\s*(.+)', re.MULTILINE | re.IGNORECASE)
PROVIDES_RE = re.compile(r'^Provides:\s*(.+)', re.MULTILINE | re.IGNORECASE)


def parse_spec(spec_path):
    """Parse a .spec file and extract gating, package names, deps."""
    try:
        with open(spec_path, "r", errors="replace") as f:
            content = f.read()
    except (IOError, OSError):
        return None

    result = {
        "path": spec_path,
        "name": None,
        "version": None,
        "release": None,
        "build_if_raw": None,
        "gate_op": None,
        "gate_threshold": None,
        "gate_disabled": False,
        "subpackages": [],
        "requires": [],
        "build_requires": [],
        "provides": [],
        # per_subpackage["<full-pkg-name>"] = {requires, build_requires, provides}
        # Allows find_consumers to attribute a Requires line to the actual
        # subpackage that declared it inside its %package block, not to the
        # main spec package. Honoured by find_consumers when present.
        "per_subpackage": {},
    }

    first_line = content.split("\n")[0] if content else ""
    m = BUILD_IF_RE.search(first_line)
    if not m:
        for line in content.split("\n")[:10]:
            m = BUILD_IF_RE.search(line)
            if m:
                break

    if m:
        raw = m.group(1).strip()
        result["build_if_raw"] = raw
        if raw == "0":
            result["gate_disabled"] = True
        else:
            gm = SUBRELEASE_GATE_RE.search(raw)
            if gm:
                result["gate_op"] = gm.group(1)
                result["gate_threshold"] = int(gm.group(2))

    nm = NAME_RE.search(content)
    if nm:
        result["name"] = nm.group(1).strip()

    vm = VERSION_RE.search(content)
    if vm:
        result["version"] = vm.group(1).strip()

    rm = RELEASE_RE.search(content)
    if rm:
        result["release"] = rm.group(1).strip()

    for sm in SUBPKG_RE.finditer(content):
        subname = sm.group(1).strip()
        if "%{name}" in subname or "%{" not in subname:
            result["subpackages"].append(subname)

    for rq in re.finditer(r'^Requires:\s*(.+)', content, re.MULTILINE | re.IGNORECASE):
        dep = rq.group(1).strip().split()[0]
        dep = re.sub(r'%\{name\}', result["name"] or "", dep)
        dep = re.sub(r'%\{version\}.*', "", dep)
        if dep and not dep.startswith("%"):
            result["requires"].append(dep)

    for br in re.finditer(r'^BuildRequires:\s*(.+)', content, re.MULTILINE | re.IGNORECASE):
        dep = br.group(1).strip().split()[0]
        dep = re.sub(r'%\{name\}', result["name"] or "", dep)
        if dep and not dep.startswith("%"):
            result["build_requires"].append(dep)

    for pv in PROVIDES_RE.finditer(content):
        prov = pv.group(1).strip().split()[0]
        prov = re.sub(r'%\{name\}', result["name"] or "", prov)
        if prov and not prov.startswith("%"):
            result["provides"].append(prov)

    # ---- Subpackage-scoped pass (option 3) ----
    # Walk the spec line-by-line tracking the current %package scope so each
    # Requires/BuildRequires/Provides line is attributed to the *subpackage*
    # that declared it, not to the main package. The flat arrays above remain
    # populated for backward compatibility.
    base_name = result["name"] or ""

    def _resolve_subpkg_full_name(raw_name, has_dash_n):
        # Resolve %{name} macro and apply RPM's <name>-<sub> vs -n <literal>
        # naming rule. Empty input => main package.
        if not raw_name:
            return base_name
        resolved = raw_name.replace("%{name}", base_name)
        if has_dash_n:
            return resolved
        if "%{name}" in raw_name:
            return resolved
        return f"{base_name}-{resolved}" if base_name else resolved

    def _clean_dep(raw):
        d = raw.strip().split()[0]
        d = re.sub(r'%\{name\}', base_name, d)
        d = re.sub(r'%\{version\}.*', "", d)
        if d and not d.startswith("%"):
            return d
        return None

    if base_name:
        result["per_subpackage"][base_name] = {
            "requires": [], "build_requires": [], "provides": [],
        }
    current_scope = base_name
    package_directive_re = re.compile(r'^%package\s+(-n\s+)?(.+)$', re.IGNORECASE)
    for line in content.split("\n"):
        sm = package_directive_re.match(line)
        if sm:
            has_n = bool(sm.group(1))
            raw_sub = sm.group(2).strip()
            full = _resolve_subpkg_full_name(raw_sub, has_n)
            current_scope = full
            if full and full not in result["per_subpackage"]:
                result["per_subpackage"][full] = {
                    "requires": [], "build_requires": [], "provides": [],
                }
            continue
        if not current_scope:
            continue
        rm = re.match(r'^Requires:\s*(.+)', line, re.IGNORECASE)
        if rm:
            d = _clean_dep(rm.group(1))
            if d:
                result["per_subpackage"][current_scope]["requires"].append(d)
            continue
        bm = re.match(r'^BuildRequires:\s*(.+)', line, re.IGNORECASE)
        if bm:
            d = _clean_dep(bm.group(1))
            if d:
                result["per_subpackage"][current_scope]["build_requires"].append(d)
            continue
        pm = re.match(r'^Provides:\s*(.+)', line, re.IGNORECASE)
        if pm:
            d = _clean_dep(pm.group(1))
            if d:
                result["per_subpackage"][current_scope]["provides"].append(d)
            continue

    return result


def is_active(spec, subrelease):
    """Check if a spec is active for the given subrelease."""
    if spec.get("gate_disabled"):
        return False
    op = spec.get("gate_op")
    threshold = spec.get("gate_threshold")
    if op is None or threshold is None:
        return True  # no gate = always active
    if op == "<=":
        return subrelease <= threshold
    if op == ">=":
        return subrelease >= threshold
    if op == "<":
        return subrelease < threshold
    if op == ">":
        return subrelease > threshold
    if op == "==":
        return subrelease == threshold
    if op == "!=":
        return subrelease != threshold
    return True


def full_package_names(spec):
    """Return all package names produced by a spec (main + subpackages)."""
    names = []
    base = spec.get("name")
    if base:
        names.append(base)
        for sub in spec.get("subpackages", []):
            if sub.startswith("-"):
                names.append(f"{base}{sub}")
            elif "%{name}" in sub:
                names.append(sub.replace("%{name}", base))
            else:
                names.append(f"{base}-{sub}")
    return names


# ---------------------------------------------------------------------------
# Phase 0: Inventory
# ---------------------------------------------------------------------------

def scan_specs(spec_dir, prefix=""):
    """Recursively find and parse all .spec files under spec_dir.

    Excludes numeric top-level subdirs (e.g. SPECS/91/, SPECS/92/) because
    those are gated subrelease overlays scanned independently into
    ``branch.gated_subdirs[N]``. Including them in the regular scan would
    place the same spec into both buckets and cause find_consumers to
    self-match the gated copy against the mainline package (the
    tdnf-python false positive in run 25541029522).
    """
    specs = []
    if not os.path.isdir(spec_dir):
        return specs
    for root, dirs, files in os.walk(spec_dir, followlinks=False):
        if root == spec_dir:
            # Top-level only: drop numeric dirs (gated subrelease overlays).
            dirs[:] = [d for d in dirs if not d.isdigit()]
        for fn in files:
            if fn.endswith(".spec"):
                path = os.path.join(root, fn)
                parsed = parse_spec(path)
                if parsed:
                    rel = os.path.relpath(path, spec_dir)
                    parsed["rel_path"] = rel
                    parsed["location"] = prefix
                    specs.append(parsed)
    return specs


def build_inventory(base_dir, branches, common_dir):
    """Phase 0: Build complete inventory of all specs across all branches."""
    inventory = {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "base_dir": base_dir,
        "branches": {},
        "common": {
            "specs": [],
            "config": {},
        },
    }

    # Common specs
    common_spec_dir = os.path.join(common_dir, "SPECS")
    if os.path.isdir(common_spec_dir):
        inventory["common"]["specs"] = scan_specs(common_spec_dir, "common/SPECS")

    common_cfg_path = os.path.join(common_dir, "build-config.json")
    if os.path.isfile(common_cfg_path):
        with open(common_cfg_path) as f:
            inventory["common"]["config"] = json.load(f)

    for branch in branches:
        branch_dir = os.path.join(base_dir, branch)
        if not os.path.isdir(branch_dir):
            continue

        cfg_path = os.path.join(branch_dir, "build-config.json")
        config = {}
        if os.path.isfile(cfg_path):
            with open(cfg_path) as f:
                config = json.load(f)

        params = config.get("photon-build-param", {})
        subrelease_str = params.get("photon-subrelease", "")
        mainline_str = params.get("photon-mainline", "")

        try:
            subrelease = int(subrelease_str)
        except (ValueError, TypeError):
            subrelease = None

        try:
            mainline = int(mainline_str) if mainline_str else None
        except (ValueError, TypeError):
            mainline = None

        uses_snapshot = mainline is None or (subrelease != mainline)

        spec_dir = os.path.join(branch_dir, "SPECS")
        branch_specs = scan_specs(spec_dir, f"{branch}/SPECS") if os.path.isdir(spec_dir) else []

        # Separate gated subdirs (e.g. SPECS/91/)
        gated_subdirs = {}
        if os.path.isdir(spec_dir):
            for entry in os.listdir(spec_dir):
                try:
                    n = int(entry)
                    subdir = os.path.join(spec_dir, entry)
                    if os.path.isdir(subdir):
                        gated_subdirs[n] = scan_specs(subdir, f"{branch}/SPECS/{entry}")
                except ValueError:
                    pass

        inventory["branches"][branch] = {
            "config": config,
            "subrelease": subrelease,
            "mainline": mainline,
            "uses_snapshot": uses_snapshot,
            "release_version": params.get("photon-release-version", branch),
            "dist_tag": params.get("photon-dist-tag", ""),
            "specs": branch_specs,
            "gated_subdirs": {str(k): v for k, v in gated_subdirs.items()},
            "common_specs": inventory["common"]["specs"],
        }

    return inventory


# ---------------------------------------------------------------------------
# Phase 1: Detection
# ---------------------------------------------------------------------------

def make_finding(constellation, severity, package, branch, subrelease, description,
                 spec_paths=None, missing_subpackages=None, remediation=None, **extra):
    fid = f"{constellation}-{branch}-{package}".replace("/", "-").replace(" ", "-")
    h = hashlib.sha256(fid.encode()).hexdigest()[:8]
    finding = {
        "id": f"{fid}-{h}",
        "constellation": constellation,
        "severity": severity,
        "package": package,
        "branch": branch,
        "subrelease": subrelease,
        "description": description,
        "spec_paths": spec_paths or [],
        "remediation": remediation or {},
    }
    if missing_subpackages:
        finding["missing_subpackages"] = missing_subpackages
    finding.update(extra)
    return finding


def detect_c1_package_split(inventory, findings):
    """C1: Package split/merge -- new subpackages not in old spec."""
    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        if subrelease is None:
            continue

        main_specs = branch.get("specs", [])
        gated_subdirs = branch.get("gated_subdirs", {})

        # Build lookup of gated-subdir specs by package name
        old_specs_by_name = {}
        for subdir_key, subdir_specs in gated_subdirs.items():
            for spec in subdir_specs:
                if spec.get("name"):
                    old_specs_by_name[spec["name"]] = spec

        for spec in main_specs:
            name = spec.get("name")
            if not name or not spec.get("gate_op"):
                continue

            old = old_specs_by_name.get(name)
            if not old:
                continue

            new_subs = set(full_package_names(spec))
            old_subs = set(full_package_names(old))
            added = new_subs - old_subs
            removed = old_subs - new_subs

            if not added and not removed:
                continue

            # With subrelease activating OLD spec: does anything depend on NEW subpackages?
            if is_active(old, subrelease) and not is_active(spec, subrelease):
                if added:
                    # Check if any other spec requires the new subpackages
                    consumers = find_consumers(
                        added, main_specs + branch.get("common_specs", []),
                        target_pkg=name, subrelease=subrelease)
                    if consumers:
                        findings.append(make_finding(
                            "C1", "CRITICAL", name, branch_name, subrelease,
                            f"Package {name} split: new subpackages {sorted(added)} "
                            f"required by {sorted(consumers)} but only old monolithic "
                            f"spec active at subrelease {subrelease}",
                            spec_paths=[spec["path"], old["path"]],
                            missing_subpackages=sorted(added),
                            consumers=sorted(consumers),
                            remediation={
                                "action": "Set photon-mainline = photon-subrelease to bypass snapshot",
                                "config_keys": ["photon-mainline"],
                            }
                        ))
                    else:
                        findings.append(make_finding(
                            "C1", "WARNING", name, branch_name, subrelease,
                            f"Package {name} split: new subpackages {sorted(added)} "
                            f"not active at subrelease {subrelease}, but no consumers found",
                            spec_paths=[spec["path"], old["path"]],
                            missing_subpackages=sorted(added),
                            remediation={
                                "action": "Monitor -- no immediate impact",
                                "config_keys": ["photon-mainline"],
                            }
                        ))

            if removed and is_active(spec, subrelease) and not is_active(old, subrelease):
                consumers = find_consumers(
                    removed, main_specs + branch.get("common_specs", []),
                    target_pkg=name, subrelease=subrelease)
                if consumers:
                    findings.append(make_finding(
                        "C1", "HIGH", name, branch_name, subrelease,
                        f"Package {name} merge: subpackages {sorted(removed)} "
                        f"removed in new spec but required by {sorted(consumers)}",
                        spec_paths=[spec["path"], old["path"]],
                        missing_subpackages=sorted(removed),
                        consumers=sorted(consumers),
                        remediation={
                            "action": "Update consumer specs to use new package names",
                            "config_keys": ["photon-mainline"],
                        }
                    ))


def find_consumers(package_names, all_specs, target_pkg=None, subrelease=None):
    """Find specs (or subpackages) that Require/BuildRequire any of the given names.

    Defenses against the self-referential false positive class seen on
    5.0/tdnf in run 25541029522:
      - target_pkg: skip specs whose top-level name matches (self-match)
      - subrelease: skip specs gated off at this subrelease
      - per-subpackage attribution: when ``spec["per_subpackage"]`` is
        present, walk it instead of the flat requires arrays so a match
        is attributed to the exact subpackage that declared the Requires
        (e.g. ``tdnf-pytests`` rather than just ``tdnf``).

    Returns a set of consumer names. With per_subpackage data, those are
    full subpackage names; otherwise it falls back to the spec's main
    package name.
    """
    consumers = set()
    for spec in all_specs:
        if target_pkg is not None and spec.get("name") == target_pkg:
            continue
        if subrelease is not None and not is_active(spec, subrelease):
            continue
        per_sub = spec.get("per_subpackage") or {}
        if per_sub:
            for sub_name, sub_data in per_sub.items():
                # Skip the target package itself even if represented as a
                # subpackage entry under the same name.
                if target_pkg is not None and sub_name == target_pkg:
                    continue
                deps = (sub_data.get("requires") or []) + \
                       (sub_data.get("build_requires") or [])
                for dep in deps:
                    clean = dep.split(">=")[0].split("<=")[0] \
                               .split(">")[0].split("<")[0].strip()
                    if clean in package_names:
                        consumers.add(sub_name)
                        break
            continue
        # Fallback: legacy flat-arrays path (for inventories produced by
        # older versions of parse_spec without per_subpackage data).
        all_deps = (spec.get("requires") or []) + (spec.get("build_requires") or [])
        for dep in all_deps:
            clean = dep.split(">=")[0].split("<=")[0] \
                       .split(">")[0].split("<")[0].strip()
            if clean in package_names:
                consumers.add(spec.get("name", spec.get("path", "?")))
                break
    return consumers


def detect_c2_version_bump_deps(inventory, findings):
    """C2: Version bump with new/changed dependencies."""
    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        if subrelease is None:
            continue

        main_specs = branch.get("specs", [])
        gated_subdirs = branch.get("gated_subdirs", {})

        old_specs_by_name = {}
        for subdir_key, subdir_specs in gated_subdirs.items():
            for spec in subdir_specs:
                if spec.get("name"):
                    old_specs_by_name[spec["name"]] = spec

        for spec in main_specs:
            name = spec.get("name")
            if not name or not spec.get("gate_op"):
                continue

            old = old_specs_by_name.get(name)
            if not old:
                continue

            new_reqs = set(spec.get("requires", []))
            old_reqs = set(old.get("requires", []))
            new_breqs = set(spec.get("build_requires", []))
            old_breqs = set(old.get("build_requires", []))

            added_reqs = new_reqs - old_reqs
            added_breqs = new_breqs - old_breqs

            if not added_reqs and not added_breqs:
                continue

            # Only flag if OLD spec is active (so new deps don't exist yet)
            if is_active(old, subrelease) and not is_active(spec, subrelease):
                all_added = added_reqs | added_breqs
                # Check if any of the added deps are gated subpackages from other specs
                for added_dep in all_added:
                    clean = added_dep.split(">=")[0].split("<=")[0].strip()
                    # Check if this dep comes from a gated spec that's also inactive
                    for other in main_specs:
                        if other.get("name") == name:
                            continue
                        other_pkgs = set(full_package_names(other))
                        if clean in other_pkgs and not is_active(other, subrelease):
                            findings.append(make_finding(
                                "C2", "HIGH", name, branch_name, subrelease,
                                f"Package {name} (old spec active at subrelease {subrelease}) "
                                f"new version adds dependency on '{clean}' which comes from "
                                f"{other.get('name')} (gated >= {other.get('gate_threshold')}, inactive)",
                                spec_paths=[spec["path"], old["path"], other["path"]],
                                remediation={
                                    "action": "Set photon-mainline = photon-subrelease to bypass snapshot",
                                    "config_keys": ["photon-mainline"],
                                }
                            ))


def detect_c3_snapshot_boundary(inventory, findings):
    """C3: Subrelease threshold boundary mismatch -- snapshot predates gating commit."""
    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        mainline = branch.get("mainline")
        uses_snapshot = branch.get("uses_snapshot", True)

        if subrelease is None:
            continue

        # If mainline == subrelease, snapshot is bypassed -- no C3 risk
        if mainline is not None and mainline == subrelease:
            continue

        main_specs = branch.get("specs", [])
        gated_subdirs = branch.get("gated_subdirs", {})

        # Collect all gated specs where the threshold == subrelease
        # These are exactly at the boundary -- highest risk
        boundary_specs = []
        for spec in main_specs:
            t = spec.get("gate_threshold")
            if t is not None and t == subrelease:
                boundary_specs.append(spec)

        # Also check common specs
        for spec in branch.get("common_specs", []):
            t = spec.get("gate_threshold")
            if t is not None and t == subrelease:
                boundary_specs.append(spec)

        if boundary_specs and uses_snapshot:
            pkg_names = sorted(set(s.get("name", "?") for s in boundary_specs))
            findings.append(make_finding(
                "C3", "HIGH", f"boundary-{subrelease}", branch_name, subrelease,
                f"Branch {branch_name} uses subrelease={subrelease} with snapshot enabled. "
                f"{len(boundary_specs)} specs have gating threshold exactly at {subrelease}: "
                f"{pkg_names[:10]}{'...' if len(pkg_names) > 10 else ''}. "
                f"If the snapshot was captured before these gating commits, "
                f"the snapshot metadata will be inconsistent with active specs.",
                spec_paths=[s["path"] for s in boundary_specs[:5]],
                remediation={
                    "action": f"Set photon-mainline={subrelease} to bypass snapshot",
                    "config_keys": ["photon-mainline"],
                }
            ))


def detect_c4_cross_branch(inventory, findings):
    """C4: Cross-branch contamination via common/ specs."""
    common_specs = inventory.get("common", {}).get("specs", [])
    gated_common = [s for s in common_specs if s.get("gate_op") is not None]

    if not gated_common:
        return

    # Group common gated specs by threshold
    thresholds = defaultdict(list)
    for spec in gated_common:
        t = spec.get("gate_threshold")
        if t is not None:
            thresholds[t].append(spec)

    # Check each branch against common gated specs
    branch_names = list(inventory["branches"].keys())
    for i, b1_name in enumerate(branch_names):
        b1 = inventory["branches"][b1_name]
        sr1 = b1.get("subrelease")
        if sr1 is None:
            continue

        for j, b2_name in enumerate(branch_names):
            if j <= i:
                continue
            b2 = inventory["branches"][b2_name]
            sr2 = b2.get("subrelease")
            if sr2 is None:
                continue

            if sr1 == sr2:
                continue

            # Different subreleases sharing common gated specs
            for threshold, specs in thresholds.items():
                active_b1 = [s for s in specs if is_active(s, sr1)]
                active_b2 = [s for s in specs if is_active(s, sr2)]

                if set(s["path"] for s in active_b1) != set(s["path"] for s in active_b2):
                    diff_names = sorted(set(
                        s.get("name", "?") for s in active_b1
                    ).symmetric_difference(
                        s.get("name", "?") for s in active_b2
                    ))
                    if diff_names:
                        findings.append(make_finding(
                            "C4", "WARNING", f"common-threshold-{threshold}",
                            f"{b1_name}+{b2_name}", f"{sr1}/{sr2}",
                            f"Branches {b1_name} (subrelease={sr1}) and {b2_name} "
                            f"(subrelease={sr2}) share common/ specs with gating threshold "
                            f"{threshold} but activate different spec sets: {diff_names}",
                            spec_paths=[s["path"] for s in (active_b1 + active_b2)[:4]],
                            remediation={
                                "action": "Ensure each branch has correct photon-subrelease for its kernel",
                                "config_keys": ["photon-subrelease"],
                            }
                        ))


def detect_c5_fips_canister(inventory, findings):
    """C5: FIPS canister version coupling."""
    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        if subrelease is None:
            continue

        all_specs = branch.get("specs", []) + branch.get("common_specs", [])

        # Find kernel specs that reference fips canister
        for spec in all_specs:
            if not is_active(spec, subrelease):
                continue
            name = spec.get("name", "")
            if "linux" not in name.lower():
                continue

            # Check BuildRequires for fips canister
            for dep in spec.get("build_requires", []):
                if "fips" in dep.lower() and "canister" in dep.lower():
                    findings.append(make_finding(
                        "C5", "WARNING", name, branch_name, subrelease,
                        f"Kernel spec {name} has FIPS canister dependency: {dep}. "
                        f"Verify canister RPM availability matches kernel version.",
                        spec_paths=[spec["path"]],
                        canister_version=dep,
                        remediation={
                            "action": "Verify FIPS canister RPM exists in base repo for this kernel version",
                            "config_keys": ["photon-mainline"],
                        }
                    ))


def detect_c3_upgrade_conflict(inventory, findings, check_urls=False):
    """C3 variant: When snapshot is bypassed (mainline==subrelease), the remote repo
    contains newer package versions. The build system runs 'tdnf upgrade' before
    'tdnf install', which upgrades packages to their latest version from remote.
    If a locally-built package (from old gated spec) pins an exact version
    (e.g. libcap-devel-2.66 Requires: libcap = 2.66), the upgrade step may
    pull libcap-2.77 from remote, breaking the exact version dependency."""
    if not check_urls or not HAS_REQUESTS:
        return

    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        mainline = branch.get("mainline")
        if subrelease is None:
            continue

        # Only applies when snapshot is bypassed
        if mainline is None or mainline != subrelease:
            continue

        main_specs = branch.get("specs", [])
        gated_subdirs = branch.get("gated_subdirs", {})

        old_specs_by_name = {}
        for subdir_key, subdir_specs in gated_subdirs.items():
            for spec in subdir_specs:
                if spec.get("name"):
                    old_specs_by_name[spec["name"]] = spec

        inactive_new_by_name = {}
        for spec in main_specs:
            name = spec.get("name")
            if not name:
                continue
            if spec.get("gate_op") and not is_active(spec, subrelease):
                inactive_new_by_name[name] = spec

        # For each package with old+new gated specs where old is active:
        # If the new version exists in the remote repo, tdnf upgrade will
        # pull it, breaking locally-built packages that pin the old version.
        for name, new_spec in inactive_new_by_name.items():
            old_spec = old_specs_by_name.get(name)
            if not old_spec:
                continue

            old_v = old_spec.get("version", "")
            new_v = new_spec.get("version", "")
            if old_v == new_v:
                continue

            # Find ungated specs that pin the old version via exact deps
            for consumer in main_specs:
                cname = consumer.get("name")
                if not cname or consumer.get("gate_op") is not None:
                    continue
                all_deps = consumer.get("requires", []) + consumer.get("build_requires", [])
                for dep in all_deps:
                    clean = dep.split(">=")[0].split("<=")[0].split(">")[0].split("<")[0].strip()
                    if clean == name or clean == f"{name}-devel":
                        findings.append(make_finding(
                            "C3", "CRITICAL", cname, branch_name, subrelease,
                            f"Snapshot bypassed (mainline={mainline}), but remote repo "
                            f"contains {name}-{new_v} (newer than locally-built {name}-{old_v}). "
                            f"The 'tdnf upgrade' step before install will pull {name}-{new_v} "
                            f"from remote, then {cname}'s dependency on {clean} (pinned to "
                            f"old version) cannot be satisfied. This affects systemd, "
                            f"and any other ungated package depending on gated packages.",
                            spec_paths=[consumer["path"], old_spec["path"], new_spec["path"]],
                            remediation={
                                "action": f"Use a snapshot that contains {name}-{old_v}, "
                                          f"OR upgrade to subrelease {new_spec.get('gate_threshold')} "
                                          f"to use {name}-{new_v} consistently",
                                "config_keys": ["photon-subrelease", "photon-mainline"],
                            }
                        ))
                        break


def detect_c6_snapshot_url(inventory, findings, arch="x86_64", check_urls=False):
    """C6: Snapshot URL availability."""
    common_cfg = inventory.get("common", {}).get("config", {})
    url_template = common_cfg.get("photon-build-param", {}).get(
        "package-repo-snapshot-file-url", "")

    if not url_template:
        return

    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        mainline = branch.get("mainline")
        release_ver = branch.get("release_version", branch_name)

        if subrelease is None:
            continue

        # If mainline == subrelease, snapshot is bypassed
        if mainline is not None and mainline == subrelease:
            continue

        url = url_template
        url = url.replace("$releasever", str(release_ver))
        url = url.replace("$basearch", arch)
        url = url.replace("SUBRELEASE", str(subrelease))

        finding_data = {
            "url": url,
            "http_status": None,
        }

        if check_urls and HAS_REQUESTS:
            try:
                resp = requests.head(url, timeout=15, allow_redirects=True)
                finding_data["http_status"] = resp.status_code
                if resp.status_code == 404:
                    # Probe nearby snapshots
                    available = []
                    for probe in range(max(subrelease - 5, 80), subrelease + 5):
                        probe_url = url_template.replace("$releasever", str(release_ver))
                        probe_url = probe_url.replace("$basearch", arch)
                        probe_url = probe_url.replace("SUBRELEASE", str(probe))
                        try:
                            pr = requests.head(probe_url, timeout=10, allow_redirects=True)
                            if pr.status_code == 200:
                                available.append(probe)
                        except Exception:
                            pass

                    findings.append(make_finding(
                        "C6", "BLOCKING", f"snapshot-{subrelease}",
                        branch_name, subrelease,
                        f"Snapshot {subrelease} not found (HTTP {resp.status_code}) "
                        f"for branch {branch_name} at {url}",
                        spec_paths=[],
                        available_snapshots=available,
                        remediation={
                            "action": f"Set photon-subrelease to an available snapshot "
                                      f"({available}) or set photon-mainline={subrelease} to bypass",
                            "config_keys": ["photon-subrelease", "photon-mainline"],
                        },
                        **finding_data,
                    ))
                elif resp.status_code == 200:
                    pass  # OK
                else:
                    findings.append(make_finding(
                        "C6", "HIGH", f"snapshot-{subrelease}",
                        branch_name, subrelease,
                        f"Snapshot {subrelease} returned HTTP {resp.status_code} "
                        f"for branch {branch_name} at {url}",
                        spec_paths=[],
                        remediation={
                            "action": "Check Artifactory access and snapshot publication status",
                            "config_keys": ["photon-subrelease"],
                        },
                        **finding_data,
                    ))
            except requests.RequestException as e:
                findings.append(make_finding(
                    "C6", "HIGH", f"snapshot-{subrelease}",
                    branch_name, subrelease,
                    f"Cannot reach snapshot URL for branch {branch_name}: {e}",
                    spec_paths=[],
                    remediation={
                        "action": "Check network access to Broadcom Artifactory",
                        "config_keys": ["photon-subrelease"],
                    },
                    **finding_data,
                ))
        else:
            # Without URL check, just flag branches using snapshots
            if branch.get("uses_snapshot", True):
                findings.append(make_finding(
                    "C6", "WARNING", f"snapshot-{subrelease}",
                    branch_name, subrelease,
                    f"Branch {branch_name} uses snapshot {subrelease} "
                    f"(URL checking disabled, cannot verify availability). URL: {url}",
                    spec_paths=[],
                    remediation={
                        "action": "Run with --check-urls to verify snapshot availability",
                        "config_keys": ["photon-subrelease", "photon-mainline"],
                    },
                    **finding_data,
                ))


def detect_ungated_deps_on_gated_packages(inventory, findings):
    """
    Extra detection: ungated specs that depend on packages produced by gated specs.
    This catches the systemd case (ungated, depends on gated libcap/dbus/Linux-PAM).
    """
    for branch_name, branch in inventory["branches"].items():
        subrelease = branch.get("subrelease")
        mainline = branch.get("mainline")
        if subrelease is None:
            continue

        # If snapshot is bypassed, no conflict
        if mainline is not None and mainline == subrelease:
            continue

        main_specs = branch.get("specs", [])
        gated_subdirs = branch.get("gated_subdirs", {})

        # Build map: for each gated spec pair, figure out which packages are
        # ONLY available from the active old spec vs the inactive new spec
        # The key insight: at subrelease N with snapshot N, tdnf may see
        # metadata from BOTH old and new specs, but the snapshot filter
        # disables packages not in the snapshot.

        # Collect NEW gated specs (>= threshold) that are INACTIVE
        inactive_new_specs = {}
        for spec in main_specs:
            name = spec.get("name")
            if not name:
                continue
            if spec.get("gate_op") and not is_active(spec, subrelease):
                inactive_new_specs[name] = spec

        # Collect packages that exist ONLY in new specs (inactive) and not in old
        old_by_name = {}
        for subdir_key, subdir_specs in gated_subdirs.items():
            for spec in subdir_specs:
                if spec.get("name"):
                    old_by_name[spec["name"]] = spec

        new_only_packages = set()
        for name, new_spec in inactive_new_specs.items():
            old_spec = old_by_name.get(name)
            new_pkgs = set(full_package_names(new_spec))
            old_pkgs = set(full_package_names(old_spec)) if old_spec else set()
            new_only_packages.update(new_pkgs - old_pkgs)

        if not new_only_packages:
            continue

        # Now find ungated specs whose deps overlap with new_only_packages
        for spec in main_specs:
            name = spec.get("name")
            if not name:
                continue
            # Skip gated specs -- they'll be handled by C1/C2
            if spec.get("gate_op") is not None:
                continue

            all_deps = set(spec.get("requires", []) + spec.get("build_requires", []))
            clean_deps = set()
            for d in all_deps:
                clean = d.split(">=")[0].split("<=")[0].split(">")[0].split("<")[0].strip()
                clean_deps.add(clean)

            conflict_deps = clean_deps & new_only_packages
            if conflict_deps:
                # This ungated spec depends on packages only in inactive new specs
                # With a stale snapshot, tdnf may see these in metadata but can't install
                findings.append(make_finding(
                    "C1", "CRITICAL", name, branch_name, subrelease,
                    f"Ungated package {name} depends on {sorted(conflict_deps)} "
                    f"which only exist in new gated specs (inactive at subrelease {subrelease}). "
                    f"With a stale snapshot, tdnf sees these in metadata but the snapshot "
                    f"filter disables them, causing Solv errors.",
                    spec_paths=[spec["path"]],
                    missing_subpackages=sorted(conflict_deps),
                    remediation={
                        "action": f"Set photon-mainline={subrelease} to bypass snapshot",
                        "config_keys": ["photon-mainline"],
                    }
                ))

        # Also check: ungated specs depending on gated packages where the
        # version changed (even if subpackage names are the same).
        # With snapshot, tdnf may try to install the old version but the spec
        # tree says new version -- metadata inconsistency.
        gated_packages_version_mismatch = {}
        for name, new_spec in inactive_new_specs.items():
            old_spec = old_by_name.get(name)
            if old_spec:
                new_v = new_spec.get("version", "")
                old_v = old_spec.get("version", "")
                if new_v != old_v:
                    for pkg in full_package_names(old_spec):
                        gated_packages_version_mismatch[pkg] = {
                            "old_version": old_v,
                            "new_version": new_v,
                            "package_base": name,
                        }

        for spec in main_specs:
            name = spec.get("name")
            if not name or spec.get("gate_op") is not None:
                continue

            all_deps = set(spec.get("requires", []) + spec.get("build_requires", []))
            clean_deps = set()
            for d in all_deps:
                clean = d.split(">=")[0].split("<=")[0].split(">")[0].split("<")[0].strip()
                clean_deps.add(clean)

            mismatched = clean_deps & set(gated_packages_version_mismatch.keys())
            if mismatched:
                # Deduplicate by base package
                bases = set()
                for m in mismatched:
                    info = gated_packages_version_mismatch[m]
                    bases.add(info["package_base"])

                for base in bases:
                    info = gated_packages_version_mismatch.get(base, {})
                    findings.append(make_finding(
                        "C3", "HIGH", name, branch_name, subrelease,
                        f"Ungated package {name} depends on {base} which has "
                        f"version mismatch across gating boundary: "
                        f"old={info.get('old_version')} (active) vs "
                        f"new={info.get('new_version')} (inactive). "
                        f"Snapshot metadata may be inconsistent.",
                        spec_paths=[spec["path"]],
                        remediation={
                            "action": f"Set photon-mainline={subrelease} to bypass snapshot",
                            "config_keys": ["photon-mainline"],
                        }
                    ))


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

def severity_rank(s):
    return {"BLOCKING": 0, "CRITICAL": 1, "HIGH": 2, "WARNING": 3}.get(s, 99)


def generate_json_output(inventory, findings, args=None):
    findings_sorted = sorted(findings, key=lambda f: severity_rank(f.get("severity", "")))
    branches_scanned = list(inventory["branches"].keys())
    timestamp = datetime.now(timezone.utc).isoformat()

    total_specs = sum(b.get("spec_count", 0) for b in inventory["branches"].values())
    total_gated = sum(len(b.get("gated_subdirs", [])) for b in inventory["branches"].values())

    blockers = [f for f in findings_sorted if f.get("severity") in ("BLOCKING", "CRITICAL")]

    metadata = {
        "timestamp": timestamp,
        "base_dir": args.base_dir if args else ".",
        "branches_scanned": branches_scanned,
        "arch": args.arch if args else "x86_64",
        "agent_version": "1.0.0",
        "check_urls_enabled": args.check_urls if args else False,
        "total_specs_scanned": total_specs,
        "total_gated_specs": total_gated,
    }

    summary = {
        "total_findings": len(findings),
        "by_severity": {},
        "by_constellation": {},
        "branches_affected": list(set(f.get("branch", "") for f in findings_sorted)),
        "build_can_proceed": len(blockers) == 0,
    }
    for f in findings:
        sev = f.get("severity", "UNKNOWN")
        summary["by_severity"][sev] = summary["by_severity"].get(sev, 0) + 1
        con = f.get("constellation", "?")
        summary["by_constellation"][con] = summary["by_constellation"].get(con, 0) + 1

    traceability = []
    for f in findings_sorted:
        traceability.append({
            "finding_id": f.get("id", ""),
            "blast_radius": {
                "spec": f.get("package", ""),
                "subpackages": f.get("missing_subpackages", []),
                "consuming_specs": f.get("consumers", []),
                "branches": [f.get("branch", "")],
                "snapshots": [int(s) for s in str(f.get("subrelease", 0)).split("/") if s.isdigit()],
                "architectures": [args.arch if args else "x86_64"],
            },
        })

    return {
        "metadata": metadata,
        "inventory_ref": args.inventory or "gating-inventory.json" if args else "gating-inventory.json",
        "findings": findings_sorted,
        "traceability": traceability,
        "summary": summary,
    }


def generate_md_output(findings_doc):
    lines = []
    lines.append("# Gating Conflict Detection Findings\n")
    metadata = findings_doc.get("metadata", {})
    summary = findings_doc.get("summary", {})
    lines.append(f"**Scan time**: {metadata.get('timestamp', 'N/A')}\n")
    lines.append(f"**Total findings**: {summary.get('total_findings', 0)}\n")
    lines.append(f"**Branches scanned**: {', '.join(metadata.get('branches_scanned', []))}\n")

    lines.append("\n## Summary by Severity\n")
    lines.append("| Severity | Count |")
    lines.append("|----------|-------|")
    for sev in ["BLOCKING", "CRITICAL", "HIGH", "WARNING"]:
        count = summary.get("by_severity", {}).get(sev, 0)
        if count > 0:
            lines.append(f"| {sev} | {count} |")

    lines.append("\n## Summary by Constellation\n")
    lines.append("| Constellation | Count | Description |")
    lines.append("|--------------|-------|-------------|")
    desc_map = {
        "C1": "Package split/merge inconsistency",
        "C2": "Version bump with new dependencies",
        "C3": "Subrelease threshold boundary mismatch",
        "C4": "Cross-branch contamination via common/",
        "C5": "FIPS canister version coupling",
        "C6": "Snapshot URL availability",
    }
    for con in ["C1", "C2", "C3", "C4", "C5", "C6"]:
        count = summary.get("by_constellation", {}).get(con, 0)
        if count > 0:
            lines.append(f"| {con} | {count} | {desc_map.get(con, '')} |")

    lines.append("\n## Findings\n")
    for f in findings_doc.get("findings", []):
        sev = f.get("severity", "?")
        icon = {"BLOCKING": "🔴", "CRITICAL": "🟠", "HIGH": "🟡", "WARNING": "⚪"}.get(sev, "⚪")
        lines.append(f"### {icon} [{f.get('constellation')}] {f.get('package')} ({f.get('branch')})\n")
        lines.append(f"**Severity**: {sev}  ")
        lines.append(f"**ID**: `{f.get('id')}`  ")
        lines.append(f"**Subrelease**: {f.get('subrelease')}\n")
        lines.append(f"{f.get('description', '')}\n")

        if f.get("spec_paths"):
            lines.append("**Spec files**:")
            for p in f["spec_paths"]:
                lines.append(f"- `{p}`")
            lines.append("")

        if f.get("missing_subpackages"):
            lines.append(f"**Missing subpackages**: {', '.join(f['missing_subpackages'])}\n")

        if f.get("consumers"):
            lines.append(f"**Affected consumers**: {', '.join(f['consumers'])}\n")

        rem = f.get("remediation", {})
        if rem.get("action"):
            lines.append(f"**Remediation**: {rem['action']}\n")

        lines.append("---\n")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    args = parse_args()
    base_dir = os.path.abspath(args.base_dir)
    branches = [b.strip() for b in args.branches.split(",") if b.strip()]

    common_dir = os.path.join(base_dir, "common")
    if not os.path.isdir(common_dir):
        print(f"WARNING: common/ directory not found at {common_dir}", file=sys.stderr)

    # Phase 0: Inventory
    if args.inventory and os.path.isfile(args.inventory):
        print(f"Loading existing inventory from {args.inventory}")
        with open(args.inventory) as f:
            inventory = json.load(f)
    else:
        print(f"Phase 0: Building inventory for branches {branches} ...")
        inventory = build_inventory(base_dir, branches, common_dir)
        print(f"  Branches: {list(inventory['branches'].keys())}")
        for bn, bd in inventory["branches"].items():
            print(f"    {bn}: subrelease={bd.get('subrelease')}, "
                  f"mainline={bd.get('mainline')}, "
                  f"uses_snapshot={bd.get('uses_snapshot')}, "
                  f"specs={len(bd.get('specs', []))}, "
                  f"gated_subdirs={list(bd.get('gated_subdirs', {}).keys())}")
        print(f"  Common specs: {len(inventory.get('common', {}).get('specs', []))}")

    if args.output:
        # Strip non-serializable data for JSON output
        inv_out = json.loads(json.dumps(inventory, default=str))
        with open(args.output, "w") as f:
            json.dump(inv_out, f, indent=2)
        print(f"Inventory written to {args.output}")

    if args.phase == "inventory":
        return

    # Phase 1: Detection
    print(f"\nPhase 1: Running conflict detection ...")
    findings = []

    print("  C1: Package split/merge ...")
    detect_c1_package_split(inventory, findings)

    print("  C2: Version bump with new dependencies ...")
    detect_c2_version_bump_deps(inventory, findings)

    print("  C3: Subrelease threshold boundary ...")
    detect_c3_snapshot_boundary(inventory, findings)

    print("  C4: Cross-branch contamination via common/ ...")
    detect_c4_cross_branch(inventory, findings)

    print("  C5: FIPS canister version coupling ...")
    detect_c5_fips_canister(inventory, findings)

    print("  C3+: Upgrade conflict (snapshot bypass) ...")
    detect_c3_upgrade_conflict(inventory, findings, check_urls=args.check_urls)

    print("  C6: Snapshot URL availability ...")
    detect_c6_snapshot_url(inventory, findings, arch=args.arch, check_urls=args.check_urls)

    print("  Extra: Ungated deps on gated packages ...")
    detect_ungated_deps_on_gated_packages(inventory, findings)

    # Deduplicate by ID
    seen = set()
    deduped = []
    for f in findings:
        fid = f.get("id")
        if fid not in seen:
            seen.add(fid)
            deduped.append(f)
    findings = deduped

    # Output
    findings_doc = generate_json_output(inventory, findings, args=args)

    with open(args.json_output, "w") as f:
        json.dump(findings_doc, f, indent=2)
    print(f"\nJSON findings written to {args.json_output}")

    md_content = generate_md_output(findings_doc)
    with open(args.md_output, "w") as f:
        f.write(md_content)
    print(f"Markdown findings written to {args.md_output}")

    # Summary
    print(f"\n{'='*60}")
    print(f"SCAN COMPLETE")
    print(f"{'='*60}")
    blockers = [f for f in findings if f.get("severity") in ("BLOCKING", "CRITICAL")]
    warnings = [f for f in findings if f.get("severity") in ("HIGH", "WARNING")]
    print(f"Total findings: {len(findings)}")
    print(f"  BLOCKING/CRITICAL: {len(blockers)}")
    print(f"  HIGH/WARNING: {len(warnings)}")

    if blockers:
        print(f"\nBLOCKERS/CRITICAL:")
        for b in blockers:
            d = b['description']
            # Soft cap for terminal readability; word-boundary ellipsis instead
            # of a mid-word slice. Full text is always preserved in findings.json
            # and findings.md, so the line cap here is purely cosmetic.
            if len(d) > 180:
                cut = d.rfind(' ', 0, 180)
                d = (d[:cut] if cut > 0 else d[:180]) + ' ...'
            print(f"  [{b['constellation']}] {b['branch']}/{b['package']}: {d}")

    if not blockers:
        print("\nNo blocking findings. Build can proceed.")


if __name__ == "__main__":
    main()
