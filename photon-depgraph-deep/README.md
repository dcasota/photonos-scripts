# photon-depgraph-deep

A granular dependency graph scanner for [VMware Photon OS](https://github.com/vmware/photon) that detects missing RPM dependency declarations by analyzing upstream source code and generates patched spec files with the missing `Requires:`/`Provides:` lines.

## The Problem: Hidden API Dependencies

RPM spec files in Photon OS declare package dependencies (`Requires:`, `BuildRequires:`, etc.), but these declarations frequently miss implicit dependencies that exist in the upstream source code. When one package is upgraded independently, the undeclared coupling can break at runtime.

### The Docker Constellation (Issue [vmware/photon#1640](https://github.com/vmware/photon/issues/1640))

The canonical example: Photon OS 5.0 updated Docker Engine from 24.x to 29.2.1 but shipped docker-compose at v2.20.2. Users saw:

```
docker compose version
Error response from daemon: client version 1.43 is too old. Minimum supported API version is 1.44
```

**Why the existing dependency graph missed it:**

- `docker-compose.spec` declares **zero** runtime `Requires:` -- only `BuildRequires: go, ca-certificates`
- `docker.spec`'s engine subpackage declares `Requires: containerd, systemd, ...` but has no `Provides: docker-api`
- The dependency graph showed docker-compose as a completely isolated node

**What was actually happening in the source code:**

```
compose/go.mod:  require github.com/docker/docker v24.0.5-dev    --> client API 1.43
moby/daemon/config/config.go:  defaultMinAPIVersion = "1.44"      --> server minimum
```

Docker Engine v29 raised its minimum supported API from 1.24 to 1.44, rejecting the compose binary compiled against client API 1.43. A proper `Requires: docker-engine >= 25.0` in docker-compose.spec would have flagged the incompatibility at install time via `tdnf`/`rpm`.

## How photon-depgraph-deep Solves This

The scanner runs in three phases:

| Phase | Input | Action | Output |
|-------|-------|--------|--------|
| **1. Spec Parsing** | `vmware/photon` SPECS/ | Parse all `.spec` files with EVR extraction, virtual provides, version constraints, subpackage tracking | Base dependency graph (nodes + edges) |
| **2. Upstream Analysis** | `photon-upstreams/{branch}/clones/` | Parse `go.mod`, `setup.cfg`/`pyproject.toml`, API version constants from source | Inferred dependency edges with evidence |
| **3. Conflict Detection & Patching** | Phase 1 vs Phase 2 diff | Find declarations missing from specs, generate patched specs | `SPECS_DEPFIX/`, `depfix-manifest.json` |

Phase 2 uses the upstream source clones already produced by the [package-report.yml](../.github/workflows/package-report.yml) workflow (stored in `photon-upstreams/{branch}/clones/`). If those clones are not available, the scanner still works in Phase 1-only mode.

## Building

Requirements: `cmake >= 3.10`, `gcc`, `libjson-c-dev` (or `json-c-devel` on Photon OS).

```bash
# On Photon OS
tdnf install -y cmake gcc json-c-devel

# Build
cd photon-depgraph-deep
mkdir -p build && cd build
cmake ..
make -j$(nproc)
```

## Usage

```
photon-depgraph-deep [OPTIONS]

Options:
  --specs-dir DIR       Path to vmware/photon SPECS/ directory (required)
  --upstreams-dir DIR   Path to photon-upstreams/{branch}/ directory
  --output-dir DIR      Output directory (default: ./output)
  --data-dir DIR        Data directory with CSV mappings (default: ./data)
  --branch NAME         Branch name (default: 5.0)
  --json                Write enriched dependency graph JSON
  --patch-specs         Generate patched spec files in SPECS_DEPFIX/
  --help                Show this help
```

### Example: Full scan with spec patching

```bash
./build/photon-depgraph-deep \
  --specs-dir /path/to/vmware/photon/SPECS \
  --upstreams-dir /path/to/photon-upstreams/photon-5.0 \
  --output-dir ./output \
  --data-dir ./data \
  --branch 5.0 \
  --json \
  --patch-specs
```

### Example: Phase 1 only (no upstreams needed)

```bash
./build/photon-depgraph-deep \
  --specs-dir /path/to/vmware/photon/SPECS \
  --output-dir ./output \
  --branch 5.0 \
  --json
```

## Output

```
output/
  dependency-graph-5.0-deep-20260312.json     # Enriched dependency graph
  depfix-manifest-5.0-20260312.json           # Manifest of all patched specs
  SPECS_DEPFIX/
    5.0/
      docker-compose/
        docker-compose.spec                   # +Requires: docker >= 28.0
      docker/
        docker.spec                           # +Requires: containerd >= 2.0
      containerd/
        containerd.spec                       # +Requires: cni >= 1.0
      python3-paramiko/
        python-paramiko.spec                  # +Requires: cryptography >= 0.0
      ...
```

### Patched spec example

The scanner copies the original spec and inserts a clearly marked block:

```spec
# --- begin depgraph-deep additions (auto-generated) ---
# Source: go.mod: github.com/docker/docker v28.5.2
Requires:       docker >= 28.0
# Source: go.mod: github.com/containerd/containerd/v2 v2.2.1
Requires:       containerd >= 2.0
# --- end depgraph-deep additions ---
```

A `%changelog` entry is also appended documenting each addition.

### Manifest JSON

The `depfix-manifest-*.json` lists every patched spec with full evidence:

```json
{
  "metadata": {
    "specs_scanned": 2011,
    "specs_patched": 41
  },
  "patched_specs": [
    {
      "package": "docker-compose",
      "original_spec": "SPECS/docker-compose/docker-compose.spec",
      "patched_spec": "SPECS_DEPFIX/5.0/docker-compose/docker-compose.spec",
      "additions": [
        {
          "type": "Requires",
          "value": "docker >= 28.0",
          "source": "go.mod",
          "evidence": "go.mod: github.com/docker/docker v28.5.2",
          "severity": "critical"
        }
      ]
    }
  ],
  "severity_summary": { "critical": 119, "important": 0, "informational": 0 }
}
```

## Data Files

| File | Purpose |
|------|---------|
| `data/gomod-package-map.csv` | Maps Go module paths to Photon package names (e.g., `github.com/docker/docker,docker`) |
| `data/api-version-patterns.csv` | Patterns for extracting API version constants from source files |

These files can be extended to cover additional package ecosystems.

## CI Workflow

The [depgraph-deep-scan.yml](../.github/workflows/depgraph-deep-scan.yml) workflow runs on the self-hosted runner and:

1. Builds the scanner from source
2. Sparse-clones `vmware/photon` SPECS per branch
3. Runs all three phases using `photon-upstreams` clones
4. Uploads JSON files and `SPECS_DEPFIX/` as a GitHub Actions artifact
5. Generates a Job Summary with per-branch statistics

Default configuration uses `/mnt/d/Users/Public/photon-upstreams` for the upstream clones directory.

## Validated Results (Photon 5.0)

On the Photon 5.0 branch (2011 packages):

- **190 inferred edges** added beyond the 9923 spec-declared edges
- **262 virtual provides** extracted from source constants
- **41 spec files patched** with missing declarations
- **Docker constellation detected**: `docker-compose` -> `docker >= 28.0`, `containerd >= 2.0`, `docker-buildx`
- Go packages: `containerd`, `calico`, `flannel`, `kubernetes`, `coredns`, `etcd`, `telegraf`, `podman`, `nerdctl`, etc.
- Python packages: `paramiko` -> `cryptography`, `prettytable` -> `wcwidth`, `jsonschema` -> `attrs`, etc.
