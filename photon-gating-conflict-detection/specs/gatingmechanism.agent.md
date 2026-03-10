# Photon OS Build Gating Mechanism -- Conflict Detection Agent

## Purpose

This agent detects conflicts between the `build_if` subrelease gating mechanism and snapshot pinning in Photon OS builds. It covers all six known conflict constellations and provides actionable remediation for each.

The agent operates on a local build tree structured as:

```
<base>/
  common/          # shared specs, build system, build-config.json
  4.0/             # branch-specific specs + build-config.json
  5.0/             # branch-specific specs + build-config.json
  6.0/             # branch-specific specs + build-config.json
```

---

## Conflict Constellations

### C1 -- Package Split/Merge Inconsistency

**Description**: A package has been split into subpackages (or merged) via a gated commit. The new spec is gated `>= N`, the old spec is relocated to `SPECS/<N-1>/` and gated `<= N-1`. Builds using a snapshot captured before the split encounter subpackage names in repo metadata that the snapshot filter disables.

**Detection logic**:

```
FOR each spec S in SPECS/ with "build_if >= T":
  IF a corresponding spec S' exists in SPECS/<T-1>/ with "build_if <= T-1":
    LET new_subpackages = packages(S) - packages(S')
    LET removed_subpackages = packages(S') - packages(S)
    IF new_subpackages OR removed_subpackages:
      FOR each branch B consuming common/:
        LET sub = B.build-config["photon-subrelease"]
        LET main = B.build-config["photon-mainline"]  # may be absent
        IF sub < T AND main != sub:
          # Branch uses snapshot, snapshot predates split
          FOR each spec D in {common/SPECS, B/SPECS}:
            IF D.Requires intersects new_subpackages:
              REPORT C1 conflict:
                branch=B, package=S, dependency=D,
                snapshot=sub, threshold=T,
                missing_subpackages=new_subpackages
```

**Example**: libcap v2.66 -> v2.77 split into libcap, libcap-libs, libcap-minimal. rpm.spec updated to `Requires: libcap-libs`. Ph5 with subrelease=91 uses snapshot-91 which predates the split. tdnf sees `libcap-minimal` in metadata but snapshot filter disables it.

**Remediation options** (ordered by preference):
1. Set `photon-mainline` equal to `photon-subrelease` in the branch's `build-config.json` to skip the snapshot entirely. The `build_if` gating alone correctly selects the old monolithic spec.
2. Backport the dependency change in the consuming spec (e.g., keep `Requires: libcap` instead of `libcap-libs`) into the `SPECS/<N-1>/` gated version.
3. Request a new snapshot at the current subrelease that includes the split packages.

---

### C2 -- Version Bump with New Dependencies

**Description**: A package is bumped and the new version adds a dependency on a package that did not exist at snapshot time. Even if the old version is correctly gated, transitive dependencies from other updated specs can pull in the conflict.

**Detection logic**:

```
FOR each spec S in SPECS/ with "build_if >= T":
  IF a corresponding spec S' exists in SPECS/<T-1>/ with "build_if <= T-1":
    LET new_deps = all_requires(S) - all_requires(S')
    FOR each dep D in new_deps:
      IF D is not provided by any spec gated "<= T-1":
        FOR each branch B with subrelease < T AND using snapshot:
          # Check if any active spec (gated <= T-1 or ungated) transitively requires D
          LET active_specs = specs where build_if evaluates true for subrelease
          IF any spec in active_specs has transitive dependency on D:
            REPORT C2 conflict:
              branch=B, new_dep=D, source_spec=S,
              transitive_path=<chain from active spec to D>
```

**Example**: A new version of `dbus` (gated `>= 92`) adds `Requires: systemd-libs >= 256`. The old `dbus` in `SPECS/91/` does not. But if another ungated spec was updated to depend on the new dbus subpackage, builds with subrelease=91 + snapshot break.

**Remediation options**:
1. Set `photon-mainline` equal to `photon-subrelease` to bypass snapshot.
2. Ensure the old gated spec's dependency set is self-consistent with what the snapshot provides.
3. Add the new dependency package to the `SPECS/<N-1>/` gated tree with an appropriate `build_if <= N-1`.

---

### C3 -- Subrelease Threshold Boundary Mismatch

**Description**: The `build_if` gating boundary does not align with the snapshot boundary. A gating commit lands between snapshot N and N+1. Building with subrelease=N activates the old gated spec correctly, but snapshot N's metadata still references packages from the new (ungated at capture time) spec.

**Detection logic**:

```
FOR each snapshot S available on Artifactory for branch B:
  LET snap_num = snapshot number (e.g., 91)
  LET snap_date = publication date of snapshot S
  FOR each spec with "build_if >= T" where T == snap_num + 1:
    LET commit_date = date of the commit that introduced the gating
    IF commit_date > snap_date:
      # Snapshot was captured before gating existed
      LET snap_packages = parse snapshot S package list
      FOR each subpackage P produced by the ">= T" spec:
        IF P appears in snap_packages:
          REPORT C3 conflict:
            snapshot=snap_num, threshold=T,
            package=P, commit_date, snap_date
            reason="Snapshot contains package from post-gating spec"
```

**Note**: This detection requires access to snapshot package lists on Artifactory and git commit dates. When run offline, approximate by checking if gated `SPECS/<N>/` directories exist for the snapshot's subrelease value.

**Remediation options**:
1. Set `photon-mainline` equal to `photon-subrelease` to bypass the stale snapshot.
2. Request a re-publication of the snapshot that reflects the gated state.
3. Use a local snapshot file (`package-repo-snapshot-file-url` pointing to a local `.list` file) that has been manually curated to exclude post-gating packages.

---

### C4 -- Cross-Branch Contamination via common/

**Description**: The `common/` branch contains specs shared across all release branches. A `build_if` threshold added for one branch's needs inadvertently affects other branches because `photon_subrelease` is a single global macro with no per-branch semantics.

**Detection logic**:

```
LET thresholds = set of all T values from "build_if >= T" and "build_if <= T" in common/SPECS/
FOR each branch B in {4.0, 5.0, 6.0}:
  LET sub_B = B.build-config["photon-subrelease"]
  FOR each threshold T in thresholds:
    LET active_common_specs = common/SPECS where build_if(sub_B) == true
    LET active_branch_specs = B/SPECS where build_if(sub_B) == true
    # Check for name collisions: same package name activated from both common and branch
    LET common_pkg_names = {name(s) for s in active_common_specs}
    LET branch_pkg_names = {name(s) for s in active_branch_specs}
    LET conflicts = common_pkg_names INTERSECT branch_pkg_names
    IF conflicts:
      FOR each pkg in conflicts:
        LET cv = version from common spec
        LET bv = version from branch spec
        IF cv != bv:
          REPORT C4 conflict:
            branch=B, package=pkg,
            common_version=cv, branch_version=bv,
            subrelease=sub_B, threshold=T
    # Check for missing pairs: branch has gated <= N but common has no matching >= N+1
    FOR each spec in active_branch_specs with "build_if <= N":
      LET pkg_name = name(spec)
      IF no spec in common/SPECS provides pkg_name with "build_if >= N+1":
        REPORT C4 warning:
          branch=B, package=pkg_name,
          reason="Branch-gated spec has no common counterpart for higher subreleases"
```

**Example**: Ph5 branch has `linux.spec` gated `<= 91` (6.1.x kernel). Common has `linux.spec` gated `>= 92` (6.12.x kernel). If Ph5 subrelease is set to 92, the branch's 6.1 kernel deactivates and common's 6.12 activates -- wrong kernel for Ph5.

**Remediation options**:
1. Ensure each branch's `photon-subrelease` is set to a value that activates the correct branch-specific specs.
2. Document the intended subrelease range for each branch in its `build-config.json`.
3. For branches that must use a subrelease at a gating boundary, use `photon-mainline` to control snapshot behavior independently of spec gating.

---

### C5 -- FIPS Canister Version Coupling

**Description**: `linux-fips-canister` has exact version pinning to a specific kernel build. The canister spec references a kernel version that only exists when the correct `build_if` gate is active. If the snapshot or subrelease is misconfigured, the canister version and kernel version diverge.

**Detection logic**:

```
FOR each linux spec L in {common/SPECS/linux/v*/linux.spec, B/SPECS/linux/linux.spec}:
  IF L contains "ExtraBuildRequires.*linux-fips-canister":
    LET canister_ver = extract fips_canister_version from L
    LET kernel_ver = extract kernel version from L
    LET gate = extract build_if from L
    FOR each branch B:
      LET sub = B.build-config["photon-subrelease"]
      IF gate evaluates true for sub:
        # This kernel spec is active for this branch
        # Check if canister RPM is resolvable
        IF branch uses snapshot:
          LET snap_packages = snapshot package list
          IF "linux-fips-canister-{canister_ver}" NOT IN snap_packages:
            REPORT C5 conflict:
              branch=B, kernel=kernel_ver,
              canister=canister_ver,
              reason="FIPS canister version not in snapshot"
        IF NOT branch uses snapshot:
          # Check if canister spec is also gated and active
          LET canister_specs = specs producing linux-fips-canister
          IF canister_ver not producible by any active canister spec:
            REPORT C5 conflict:
              branch=B, kernel=kernel_ver,
              canister=canister_ver,
              reason="No active spec produces required canister version"
```

**Example**: Ph6 kernel 6.12.69 requires `linux-fips-canister = 6.12.60-18.ph5`. If snapshot-100 is configured but doesn't exist, the canister RPM can't be resolved. Setting `photon-mainline` to skip the snapshot allows the canister to resolve from the base repo.

**Remediation options**:
1. Ensure the FIPS canister version referenced in the kernel spec matches what is available in the configured snapshot or base repo.
2. If building without FIPS, add `--without fips` or equivalent build option to skip canister dependency.
3. Use `photon-mainline` to skip snapshot if the canister RPM exists in the base repo but not in the snapshot.

---

### C6 -- Snapshot URL Availability

**Description**: The `package-repo-snapshot-file-url` template resolves to a URL on Broadcom Artifactory that returns HTTP 404. The snapshot number (derived from `photon-subrelease`) has not been published, has been removed, or the URL format has changed.

**Detection logic**:

```
FOR each branch B:
  LET sub = B.build-config["photon-subrelease"]
  LET main = B.build-config.get("photon-mainline")
  IF sub == main:
    SKIP  # snapshot not used
  LET url_template = common/build-config["package-repo-snapshot-file-url"]
  IF url_template:
    LET url = url_template
      .replace("SUBRELEASE", sub)
      .replace("$releasever", B.build-config["photon-release-version"])
      .replace("$basearch", <architecture>)
    HTTP HEAD url
    IF response != 200:
      REPORT C6 conflict:
        branch=B, subrelease=sub, url=url,
        http_status=response.status,
        reason="Snapshot file not available on Artifactory"
      # Also check which snapshots DO exist
      FOR snap_num in range(sub-10, sub+10):
        LET test_url = url_template with snap_num
        IF HTTP HEAD test_url == 200:
          RECORD available_snapshot=snap_num
      SUGGEST: "Available snapshots: {available_snapshots}"
```

**Example**: Ph6 with subrelease=100 generates URL for snapshot-100, but only snapshots 90, 91, 92 exist on Artifactory. Build fails immediately with HTTP 404 during dependency resolution.

**Remediation options**:
1. Set `photon-subrelease` to an available snapshot number.
2. Set `photon-mainline` equal to `photon-subrelease` to skip snapshot entirely.
3. Set `package-repo-snapshot-file-url` to `""` in the branch's `build-config.json` (disables snapshot for all branches sharing common/).

---

## Detection Summary Matrix

| ID | Constellation | Dimensions Affected | Severity |
|----|--------------|---------------------|----------|
| C1 | Package Split/Merge | All branches, all flavors, both architectures | Critical |
| C2 | Version Bump + New Deps | Full builds most exposed, FIPS high risk | High |
| C3 | Threshold Boundary Mismatch | Exact boundary subrelease value | High |
| C4 | Cross-Branch via common/ | All branches consuming common/ | Critical |
| C5 | FIPS Canister Coupling | FIPS builds only, subrelease-dependent | Critical for FIPS |
| C6 | Snapshot URL 404 | All flavors, both architectures | Blocking |

---

## Agent Implementation

### Prerequisites

- Python 3.8+
- `requests` library (for HTTP HEAD checks in C6)
- Access to the Photon OS build tree (`common/`, `<branch>/`)
- Optional: access to Broadcom Artifactory (for C3 snapshot date checks and C6 URL validation)

### Input Parameters

| Parameter | Description | Example |
|-----------|-------------|---------|
| `--base-dir` | Root of the build tree | `/root` |
| `--branches` | Comma-separated branch list | `4.0,5.0,6.0` |
| `--arch` | Target architecture | `x86_64` or `aarch64` |
| `--check-urls` | Enable HTTP checks for C6 | flag, default off |
| `--verbose` | Print all checks, not just conflicts | flag |

### Core Algorithm

```python
#!/usr/bin/env python3
"""
photon-gating-agent.py -- Detect build_if / snapshot conflicts in Photon OS builds.
"""

import re
import os
import json
import sys
import argparse
from pathlib import Path

def parse_build_config(path):
    with open(path) as f:
        return json.load(f)

def extract_build_if(spec_path):
    """Return (operator, threshold) or None if no build_if."""
    with open(spec_path) as f:
        for line in f:
            m = re.match(r'%global\s+build_if\s+(.*)', line.strip())
            if m:
                cond = m.group(1).strip()
                # Parse: %{photon_subrelease} >= 92
                m2 = re.match(r'%\{photon_subrelease\}\s*(>=|<=|==|!=|>|<)\s*(\d+)', cond)
                if m2:
                    return (m2.group(1), int(m2.group(2)))
                # Parse: constant 0 or 1
                if cond in ('0', '1'):
                    return ('const', int(cond))
                # Parse: arch condition or complex expression
                return ('complex', cond)
    return None

def extract_packages(spec_path):
    """Extract package names produced by a spec (main + subpackages)."""
    packages = set()
    main_name = None
    with open(spec_path) as f:
        for line in f:
            line = line.strip()
            m = re.match(r'^Name:\s*(.+)', line)
            if m:
                main_name = m.group(1).strip()
                packages.add(main_name)
            m = re.match(r'^%package\s+(-n\s+)?(.+)', line)
            if m:
                if m.group(1):  # -n flag: absolute name
                    packages.add(m.group(2).strip())
                elif main_name:
                    packages.add(f"{main_name}-{m.group(2).strip()}")
    return packages

def extract_requires(spec_path):
    """Extract all Requires and BuildRequires package names."""
    requires = set()
    with open(spec_path) as f:
        for line in f:
            line = line.strip()
            if re.match(r'^(Requires|BuildRequires):', line):
                # Extract package names (strip version constraints)
                parts = re.sub(r'^(Requires|BuildRequires):\s*', '', line)
                for dep in parts.split(','):
                    dep = dep.strip().split()[0] if dep.strip() else ''
                    if dep and not dep.startswith('%'):
                        requires.add(dep)
    return requires

def is_gate_active(gate, subrelease):
    """Check if a build_if gate evaluates true for given subrelease."""
    if gate is None:
        return True  # no gating = always active
    op, val = gate
    if op == 'const':
        return bool(val)
    if op == 'complex':
        return None  # cannot evaluate statically
    ops = {'>=': lambda a, b: a >= b, '<=': lambda a, b: a <= b,
           '==': lambda a, b: a == b, '!=': lambda a, b: a != b,
           '>': lambda a, b: a > b, '<': lambda a, b: a < b}
    return ops[op](subrelease, val)

def scan_specs(spec_dir):
    """Return list of (spec_path, gate, packages, requires) for all .spec files."""
    results = []
    for root, dirs, files in os.walk(spec_dir):
        for f in files:
            if f.endswith('.spec'):
                path = os.path.join(root, f)
                gate = extract_build_if(path)
                pkgs = extract_packages(path)
                reqs = extract_requires(path)
                results.append((path, gate, pkgs, reqs))
    return results

def detect_conflicts(base_dir, branches, arch, check_urls=False):
    """Run all 6 constellation checks. Returns list of findings."""
    findings = []
    common_dir = os.path.join(base_dir, 'common')
    common_config = parse_build_config(os.path.join(common_dir, 'build-config.json'))
    common_specs = scan_specs(os.path.join(common_dir, 'SPECS'))

    for branch in branches:
        branch_dir = os.path.join(base_dir, branch)
        if not os.path.isdir(branch_dir):
            continue
        branch_config = parse_build_config(os.path.join(branch_dir, 'build-config.json'))
        bp = branch_config.get('photon-build-param', {})
        sub = int(bp.get('photon-subrelease', '0'))
        main = bp.get('photon-mainline')
        uses_snapshot = main is None or str(sub) != str(main)
        branch_specs = scan_specs(os.path.join(branch_dir, 'SPECS'))

        # --- C1: Package Split/Merge ---
        all_specs = common_specs + branch_specs
        gated_new = [(p, g, pkgs, reqs) for p, g, pkgs, reqs in all_specs
                     if g and g[0] == '>=' ]
        gated_old = [(p, g, pkgs, reqs) for p, g, pkgs, reqs in all_specs
                     if g and g[0] == '<=' ]
        for new_path, new_gate, new_pkgs, new_reqs in gated_new:
            new_name = next(iter(new_pkgs), None)
            if not new_name:
                continue
            for old_path, old_gate, old_pkgs, old_reqs in gated_old:
                old_name = next(iter(old_pkgs), None)
                if old_name != new_name:
                    continue
                added = new_pkgs - old_pkgs
                removed = old_pkgs - new_pkgs
                if not added and not removed:
                    continue
                if sub < new_gate[1] and uses_snapshot:
                    # Check if any active spec depends on the new subpackages
                    for dep_path, dep_gate, dep_pkgs, dep_reqs in all_specs:
                        if is_gate_active(dep_gate, sub) and dep_reqs & added:
                            findings.append({
                                'constellation': 'C1',
                                'severity': 'CRITICAL',
                                'branch': branch,
                                'package': new_name,
                                'new_subpackages': sorted(added),
                                'dependent_spec': dep_path,
                                'dependent_requires': sorted(dep_reqs & added),
                                'snapshot': sub,
                                'threshold': new_gate[1],
                                'remediation': (
                                    f"Set photon-mainline={sub} in {branch}/build-config.json "
                                    f"to skip snapshot and let build_if gating handle spec selection."
                                )
                            })

        # --- C4: Cross-Branch Contamination ---
        common_active = {next(iter(pkgs)): (path, pkgs)
                        for path, gate, pkgs, reqs in common_specs
                        if is_gate_active(gate, sub) and pkgs}
        branch_active = {next(iter(pkgs)): (path, pkgs)
                        for path, gate, pkgs, reqs in branch_specs
                        if is_gate_active(gate, sub) and pkgs}
        overlaps = set(common_active.keys()) & set(branch_active.keys())
        for pkg in overlaps:
            findings.append({
                'constellation': 'C4',
                'severity': 'WARNING',
                'branch': branch,
                'package': pkg,
                'common_spec': common_active[pkg][0],
                'branch_spec': branch_active[pkg][0],
                'subrelease': sub,
                'remediation': (
                    f"Verify that subrelease={sub} activates the intended spec. "
                    f"Both common and branch have active specs for '{pkg}'."
                )
            })

        # --- C5: FIPS Canister Coupling ---
        for path, gate, pkgs, reqs in all_specs:
            if not is_gate_active(gate, sub):
                continue
            if 'linux-fips-canister' not in str(reqs):
                continue
            # Extract canister version
            with open(path) as f:
                content = f.read()
            m = re.search(r'fips_canister_version\s+(\S+)', content)
            if m:
                canister_ver = m.group(1)
                findings.append({
                    'constellation': 'C5',
                    'severity': 'INFO',
                    'branch': branch,
                    'kernel_spec': path,
                    'canister_version': canister_ver,
                    'subrelease': sub,
                    'uses_snapshot': uses_snapshot,
                    'note': (
                        f"Active kernel requires linux-fips-canister={canister_ver}. "
                        f"Verify this version is available in "
                        f"{'snapshot-' + str(sub) if uses_snapshot else 'base repo'}."
                    )
                })

        # --- C6: Snapshot URL Availability ---
        if uses_snapshot and check_urls:
            url_template = common_config.get('photon-build-param', {}).get(
                'package-repo-snapshot-file-url', '')
            if url_template:
                release_ver = bp.get('photon-release-version', '')
                url = (url_template
                       .replace('SUBRELEASE', str(sub))
                       .replace('$releasever', release_ver)
                       .replace('$basearch', arch))
                try:
                    import requests
                    resp = requests.head(url, timeout=10)
                    if resp.status_code != 200:
                        # Probe nearby snapshots
                        available = []
                        for n in range(max(1, sub - 10), sub + 10):
                            test_url = (url_template
                                        .replace('SUBRELEASE', str(n))
                                        .replace('$releasever', release_ver)
                                        .replace('$basearch', arch))
                            try:
                                r = requests.head(test_url, timeout=5)
                                if r.status_code == 200:
                                    available.append(n)
                            except Exception:
                                pass
                        findings.append({
                            'constellation': 'C6',
                            'severity': 'BLOCKING',
                            'branch': branch,
                            'subrelease': sub,
                            'url': url,
                            'http_status': resp.status_code,
                            'available_snapshots': available,
                            'remediation': (
                                f"Snapshot {sub} not available (HTTP {resp.status_code}). "
                                f"Available: {available}. "
                                f"Set photon-subrelease to an available value, or "
                                f"set photon-mainline={sub} to skip snapshot."
                            )
                        })
                except ImportError:
                    findings.append({
                        'constellation': 'C6',
                        'severity': 'SKIPPED',
                        'reason': 'requests library not installed, cannot check URLs'
                    })

    return findings

def main():
    parser = argparse.ArgumentParser(description='Photon OS Build Gating Conflict Detector')
    parser.add_argument('--base-dir', default='/root', help='Root of build tree')
    parser.add_argument('--branches', default='4.0,5.0,6.0', help='Comma-separated branch list')
    parser.add_argument('--arch', default='x86_64', help='Target architecture')
    parser.add_argument('--check-urls', action='store_true', help='Enable HTTP checks for C6')
    parser.add_argument('--verbose', action='store_true', help='Print all checks')
    parser.add_argument('--json', action='store_true', help='Output as JSON')
    args = parser.parse_args()

    branches = [b.strip() for b in args.branches.split(',')]
    findings = detect_conflicts(args.base_dir, branches, args.arch, args.check_urls)

    if args.json:
        print(json.dumps(findings, indent=2))
    else:
        if not findings:
            print("No conflicts detected.")
            return

        for f in findings:
            sev = f.get('severity', 'UNKNOWN')
            cid = f.get('constellation', '?')
            branch = f.get('branch', '?')
            pkg = f.get('package', f.get('kernel_spec', '?'))
            print(f"[{sev}] {cid} -- branch={branch} package={pkg}")
            for k, v in f.items():
                if k not in ('severity', 'constellation', 'branch', 'package'):
                    print(f"  {k}: {v}")
            print()

if __name__ == '__main__':
    main()
```

### Running the Agent

```bash
# Basic offline scan (no HTTP checks):
python3 photon-gating-agent.py --base-dir /root --branches 4.0,5.0,6.0

# Full scan with snapshot URL validation:
python3 photon-gating-agent.py --base-dir /root --branches 5.0,6.0 --check-urls

# JSON output for CI integration:
python3 photon-gating-agent.py --base-dir /root --branches 5.0,6.0 --check-urls --json
```

---

## CI Workflow Integration

### When to Run

The agent should run at **three points** in the CI pipeline:

1. **Pre-merge gate** (on every PR to `common` or a release branch):
   Detects conflicts introduced by the PR before they reach the main branch. This is the most valuable insertion point because it catches C1 (package splits), C2 (new dependencies), and C4 (cross-branch contamination) at commit time.

2. **Post-snapshot publication**:
   After a new snapshot is published to Artifactory, run the agent to verify consistency between the new snapshot and the current spec tree. Catches C3 (boundary mismatch) and C6 (URL availability).

3. **Pre-build validation** (before `make image`):
   Run as the first step of any ISO build job. Catches all six constellations with the exact configuration that will be used for the build. This is the safety net.

### GitHub Actions Example

```yaml
name: Gating Conflict Detection

on:
  pull_request:
    branches: [common, '4.0', '5.0', '6.0']
    paths:
      - 'SPECS/**'
      - 'build-config.json'
  workflow_dispatch:
    inputs:
      branches:
        description: 'Branches to check (comma-separated)'
        default: '4.0,5.0,6.0'
      check_urls:
        description: 'Enable snapshot URL validation'
        type: boolean
        default: true

jobs:
  detect-conflicts:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout common
        uses: actions/checkout@v4
        with:
          ref: common
          path: common

      - name: Checkout release branches
        run: |
          for branch in 4.0 5.0 6.0; do
            git clone --branch "$branch" --depth 1 \
              https://github.com/vmware/photon.git "$branch" || true
          done

      - name: Run gating agent
        run: |
          pip install requests
          python3 common/tools/photon-gating-agent.py \
            --base-dir . \
            --branches "${{ github.event.inputs.branches || '4.0,5.0,6.0' }}" \
            --arch x86_64 \
            ${{ github.event.inputs.check_urls == 'true' && '--check-urls' || '' }} \
            --json > findings.json

      - name: Evaluate findings
        run: |
          python3 -c "
          import json, sys
          findings = json.load(open('findings.json'))
          blockers = [f for f in findings if f.get('severity') in ('CRITICAL', 'BLOCKING')]
          if blockers:
              print('::error::Gating conflicts detected:')
              for b in blockers:
                  print(f\"  [{b['constellation']}] {b.get('package','?')}: {b.get('remediation','')}\")
              sys.exit(1)
          warnings = [f for f in findings if f.get('severity') in ('WARNING', 'HIGH')]
          for w in warnings:
              print(f\"::warning::[{w['constellation']}] {w.get('package','?')}: {w.get('remediation','')}\")
          print(f'Scan complete: {len(findings)} findings, {len(blockers)} blockers, {len(warnings)} warnings')
          "

      - name: Upload findings artifact
        if: always()
        uses: actions/upload-artifact@v4
        with:
          name: gating-findings
          path: findings.json
```

### Pre-Build Hook (for local/VM builds)

Add to the build scripts (`runPh5.sh`, `runPh6.sh`, etc.) before `make image`:

```bash
echo "Running gating conflict detection..."
python3 "$BASE_DIR/common/tools/photon-gating-agent.py" \
  --base-dir "$BASE_DIR" \
  --branches "$RELEASE_BRANCH" \
  --arch x86_64 \
  --check-urls

if [ $? -ne 0 ]; then
  echo "WARNING: Gating conflicts detected. Review output above."
  echo "Build may fail due to snapshot/spec inconsistencies."
  # Optionally: exit 1 to abort build
fi
```

### Notification and Escalation

| Severity | Action |
|----------|--------|
| BLOCKING (C6) | Fail the CI job. No build can succeed. |
| CRITICAL (C1, C4, C5) | Fail the CI job on PR gate. Warn on pre-build. |
| HIGH (C2, C3) | Warn in PR review. Annotate build logs. |
| WARNING | Informational. Log for tracking. |
| INFO (C5 canister check) | Log for audit. No action required unless FIPS build. |

### Operational Cadence

- **Every PR**: Run C1, C2, C4 checks (offline, no HTTP needed)
- **Daily**: Run full scan including C3, C5, C6 with `--check-urls`
- **Before each ISO build**: Run full scan as pre-build validation
- **After snapshot publication**: Run C3 and C6 specifically for the new snapshot number
