# Plan: Populating the RPM Dependency Graph Using tdnf Built-in Features

**Date:** March 10, 2026

---

## Analysis: tdnf Built-in Features for RPM Dependency Graph Population

### What tdnf Already Provides

After reviewing the source code (`client/api.c`, `solv/tdnfquery.c`, `tools/cli/lib/api.c`, `include/tdnftypes.h`), tdnf has **rich built-in capabilities** that eliminate the need to parse `.spec` files manually:

#### 1. `tdnf repoquery` -- The Primary Tool

This is the most important command. It queries both installed and available packages from configured repositories and supports:

- **10 dependency key types** (defined in `REPOQUERY_DEP_KEY` enum):
  - `--provides` / `--requires` / `--requires-pre` / `--recommends` / `--suggests` / `--supplements` / `--enhances` / `--conflicts` / `--obsoletes` / `--depends` (union of requires + recommends + suggests + supplements + enhances)

- **Reverse dependency queries** via `--whatrequires`, `--whatprovides`, `--whatobsoletes`, `--whatconflicts`, `--whatrecommends`, `--whatsuggests`, `--whatsupplements`, `--whatenhances`, `--whatdepends` (the `pppszWhatKeys` field in `TDNF_REPOQUERY_ARGS`)

- **JSON output** (`--json`): Every query result can be serialized to JSON with NEVRA, Repo, Dependencies, FileList, ChangeLogs, and Source package fields

- **Custom query format** (`--qf`): Format strings like `%{name}\t%{requires}\t%{provides}` with escape-sequence support

- **Scope filters**: `--installed`, `--available`, `--upgrades`, `--downgrades`, `--extras`, `--duplicates`, `--userinstalled`

- **Architecture filters**: `--arch`

- **Source package queries**: `--source`

- **File list**: `--list` returns all files owned by a package

#### 2. `tdnf provides` -- Reverse Capability Lookup

Given a file path or capability string, returns all packages that provide it. Useful for resolving implicit dependencies.

#### 3. `tdnf check` / `tdnf check-local` -- Dependency Verification

Uses the libsolv solver to verify that all packages satisfy their dependency constraints. This is the same SAT solver that powers `tdnf install/update`. It can detect broken dependency chains -- exactly what the QUBO formulation's constraint term penalizes.

#### 4. The libsolv Layer (`solv/`)

tdnf delegates all dependency resolution to **libsolv** (the OpenSUSE SAT-solver library). The `solv/` directory shows:
- `tdnfquery.c`: `SolvApplyDepsFilter()` can filter packages by any of the 8 dependency key IDs (`SOLVABLE_PROVIDES`, `SOLVABLE_REQUIRES`, `SOLVABLE_CONFLICTS`, etc.)
- `tdnfpackage.c`: `SolvGetDependenciesFromId()` extracts dependency strings for any key type
- `simplequery.c`: Functions like `SolvFindAvailablePkgByName()`, `SolvFindInstalledPkgByName()`, `SolvFindHighestAvailable()`
- The Pool object (`pSack->pPool`) contains the **complete dependency graph** already materialized from repository metadata

#### 5. Repository Metadata (repodata)

tdnf downloads and caches `primary.xml.gz` (package metadata), `filelists.xml.gz`, and `other.xml.gz` from each configured repo. The libsolv pool ingests these into a binary `.solv` cache in `cachedir`. This means **the full dependency graph of every available package is already computed and cached locally** -- no spec-file parsing needed.

---

## Implementation Plan

### Step 1: Configure tdnf to Point at the Target Repository

On a Photon OS system (the self-hosted runner), configure `/etc/yum.repos.d/` to enable all relevant Photon 6.0 repositories:

```bash
# Ensure repo metadata is fresh
tdnf clean all
tdnf makecache
```

This populates the libsolv pool with all ~1500+ packages from the Photon 6.0 repos.

### Step 2: Extract Complete Dependency Data via `tdnf repoquery --json`

A single command dumps the full dependency graph for every available package:

```bash
# All packages, all dependency types, JSON output
tdnf repoquery --available --json \
  --requires --provides --conflicts --obsoletes \
  --recommends --suggests --supplements --enhances \
  > all-packages-deps.json
```

However, `tdnf repoquery` only outputs one dependency type at a time per invocation when not using `--qf`. The practical approach is either:

**Option A -- Multiple invocations per dependency type:**
```bash
for depkey in requires provides conflicts obsoletes recommends suggests; do
  tdnf repoquery --available --json --${depkey} '*' > deps-${depkey}.json
done
```

**Option B -- Custom query format in single pass:**
```bash
tdnf repoquery --available --qf '%{name}\t%{arch}\t%{evr}\t%{requires}\t%{provides}\t%{conflicts}\t%{obsoletes}' '*' > deps-all.tsv
```

**Option C -- Python script using `tdnf repoquery --json` with per-package iteration:**
```python
import subprocess, json

# Get list of all available packages
result = subprocess.run(
    ["tdnf", "repoquery", "--available", "--json"],
    capture_output=True, text=True
)
packages = json.loads(result.stdout)

# For each package, query its requires
for pkg in packages:
    nevra = f"{pkg['Name']}-{pkg['Evr']}.{pkg['Arch']}"
    req_result = subprocess.run(
        ["tdnf", "repoquery", "--available", "--json", "--requires", nevra],
        capture_output=True, text=True
    )
    pkg['Requires'] = json.loads(req_result.stdout)
```

### Step 3: Build the Directed Acyclic Graph

A Python script (`build_dep_graph.py`, ~200 lines) processes the JSON output:

1. **Node creation**: One node per unique package name (collapsing NEVRA to name for the QUBO model, or keeping NEVRA for fine-grained analysis)

2. **Edge creation from Requires**: For each package P that has `Requires: Q`, resolve Q through the `Provides` index to find which package(s) satisfy it. Create a directed edge `Q_provider -> P`. This is exactly what libsolv already computes internally via `pool_createwhatprovides()`.

3. **Edge creation from BuildRequires**: This is the one gap -- `tdnf repoquery` operates on **binary RPM metadata** from the repo, which contains `Requires` (runtime) but **not** `BuildRequires` (build-time). BuildRequires are only in the `.spec` files or source RPMs. Two approaches:
   - **Use `tdnf repoquery --source --requires`**: Query source packages (`.src.rpm`) in the repo, which contain BuildRequires as their Requires field
   - **Supplement from SPECS**: Parse `BuildRequires` from `.spec` files in the photon build tree for packages where source RPMs are not available

4. **Edge creation from Conflicts/Obsoletes**: These create "anti-edges" in the graph -- constraints that prevent co-installation. Important for the QUBO formulation's constraint term.

### Step 4: Reverse Dependency Queries for Cost Vector

Use `--whatrequires` to compute the fan-out (reverse dependency count) for each package:

```bash
# For each crypto-critical package, find all packages that depend on it
tdnf repoquery --available --json --whatrequires openssl-libs
tdnf repoquery --available --json --whatrequires gnutls
tdnf repoquery --available --json --whatrequires nss
```

The fan-out count directly feeds the cost vector $c_i$ in the QUBO formulation: packages with high reverse dependency counts are more expensive to migrate because their migration affects more downstream consumers.

### Step 5: Export to QUBO-Ready Format

The final output is `dependency-graph.json`:

```json
{
  "nodes": [
    {"name": "openssl", "nevra": "openssl-3.3.0-1.ph6.x86_64", "repo": "photon-updates",
     "requires": ["glibc", "zlib", "krb5"],
     "provides": ["openssl", "openssl-libs", "libssl.so.3()(64bit)"],
     "reverse_dep_count": 247,
     "build_requires": ["perl", "glibc-devel", "zlib-devel"]
    }
  ],
  "edges": [
    {"from": "glibc", "to": "openssl", "type": "requires"},
    {"from": "openssl", "to": "curl", "type": "requires"}
  ]
}
```

### Step 6: Validate Graph Integrity via `tdnf check`

Run `tdnf check` to verify that the extracted graph is consistent with the solver's view. Any solver problems (broken deps, conflicts) are exactly the issues the QUBO migration planner must handle.

---

## Key Advantage Over Spec-File Parsing

Using `tdnf repoquery` instead of parsing `.spec` files gives us:

| Aspect | `.spec` parsing | `tdnf repoquery` |
|---|---|---|
| Dependency resolution | Raw strings, macros unexpanded | Fully resolved by libsolv |
| Provides mapping | Must build manually | `pool_createwhatprovides()` already computed |
| Virtual provides | Cannot resolve | Automatically resolved |
| Rich deps (if/unless) | Must parse RPM boolean syntax | Handled by libsolv |
| Sub-packages | Must parse `%package` sections | Each sub-package is a separate entry |
| Consistency | May differ from built RPMs | Matches exactly what `tdnf install` sees |
| BuildRequires | Native | Requires `--source` or spec supplement |

---

## The One Gap: BuildRequires

`tdnf repoquery --source --requires` should retrieve BuildRequires from source RPMs if the source repo is enabled. If source RPMs are not available in the repo, fall back to parsing `.spec` files from the photon build tree. This is the only case where direct spec parsing is necessary.

---

## Deliverables

| Deliverable | Description | LOC |
|---|---|---|
| `extract_deps.sh` | Shell script invoking `tdnf repoquery` for all dependency types | ~50 |
| `build_dep_graph.py` | Python script building DAG from tdnf JSON output | ~200 |
| `validate_graph.sh` | Run `tdnf check` and cross-reference with extracted graph | ~30 |
| `spec_buildrequires.py` | Fallback parser for BuildRequires from `.spec` files (gap filler) | ~100 |

**Total: ~380 lines of code**, replacing the original plan's ~100-line spec parser with a much more robust and complete graph.
