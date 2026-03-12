# upstream-source-code-dependency-scanner

A granular dependency graph scanner for [VMware Photon OS](https://github.com/vmware/photon) that detects missing RPM dependency declarations by analyzing upstream source code and generates patched spec files with the missing `Requires:`, `Provides:`, and `Conflicts:` lines.

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

Docker Engine v29 raised its minimum supported API from 1.24 to 1.44, rejecting the compose binary compiled against client API 1.43.

## How the Scanner Solves This

The scanner runs in three phases:

| Phase | Input | Action | Output |
|-------|-------|--------|--------|
| **1. Spec Parsing** | `vmware/photon` SPECS/ | Parse all `.spec` files with EVR extraction, virtual provides, version constraints, subpackage tracking | Base dependency graph (nodes + edges) |
| **2. Upstream Analysis** | `photon-upstreams/{branch}/clones/` | Parse `go.mod`, `setup.cfg`/`pyproject.toml`, API version constants from source | Inferred dependency edges with evidence |
| **3. Conflict Detection & Patching** | Phase 1 vs Phase 2 diff | Find missing declarations, detect API conflicts, generate patched specs | `SPECS_DEPFIX/`, `depfix-manifest.json` |

Phase 2 uses the upstream source clones produced by the [package-report.yml](../.github/workflows/package-report.yml) workflow (stored in `photon-upstreams/{branch}/clones/`). The package-to-clone mapping is derived from the PRN package report files (`photonos-urlhealth-{branch}_*.prn`) which contain the authoritative Source0 URL for each spec, eliminating the need for hardcoded mappings.

## Building

Requirements: `cmake >= 3.10`, `gcc`, `libjson-c-dev` (or `json-c-devel` on Photon OS).

```bash
# On Photon OS
tdnf install -y cmake gcc json-c-devel

cd upstream-source-code-dependency-scanner
mkdir -p build && cd build
cmake ..
make -j$(nproc)
```

## Usage

```
upstream-dep-scanner [OPTIONS]

Options:
  --specs-dir DIR       Path to vmware/photon SPECS/ directory (required)
  --upstreams-dir DIR   Path to photon-upstreams/{branch}/ directory
  --output-dir DIR      Output directory (default: ./output)
  --data-dir DIR        Data directory with CSV mappings (default: ./data)
  --branch NAME         Branch name (default: 5.0)
  --prn-file FILE       PRN package report file (for package->clone mapping)
  --json                Write enriched dependency graph JSON
  --patch-specs         Generate patched spec files in SPECS_DEPFIX/
  --help                Show this help
```

### Example: Full scan with PRN mapping and spec patching

```bash
./build/upstream-dep-scanner \
  --specs-dir /path/to/photon-5.0/SPECS \
  --upstreams-dir /path/to/photon-upstreams/photon-5.0 \
  --prn-file /path/to/photonos-urlhealth-5.0_YYYYMMDD.prn \
  --output-dir ./output \
  --data-dir ./data \
  --branch 5.0 \
  --json \
  --patch-specs
```

### Example: Phase 1 only (no upstreams needed)

```bash
./build/upstream-dep-scanner \
  --specs-dir /path/to/photon-5.0/SPECS \
  --output-dir ./output \
  --branch 5.0 \
  --json
```

## Output

```
output/
  dependency-graph-5.0-deep-YYYYMMDD.json     # Enriched dependency graph
  depfix-manifest-5.0-YYYYMMDD.json           # Manifest of all patched specs
  SPECS_DEPFIX/
    5.0/
      docker-compose/
        docker-compose.spec                   # +Conflicts: docker-engine < 28.3
      docker-buildx/
        docker-buildx.spec                    # +Conflicts: docker-engine < 27.2
      calico/
        calico.spec                           # +Conflicts: docker-engine < 27.2
      python3-paramiko/
        python-paramiko.spec                  # +Requires: cryptography >= 0.0
      ...
```

### Patched spec example

The scanner copies the original spec and inserts a clearly marked block:

```spec
# --- begin upstream-dep-scanner additions (auto-generated) ---
# Source: go.mod docker SDK v28.5.1 -> API 1.51, requires engine >= 28.3
Conflicts:      docker-engine < 28.3
# Source: go.mod: github.com/docker/docker v28.5.1
Requires:       docker >= 28.0
# --- end upstream-dep-scanner additions ---
```

### Manifest JSON

The `depfix-manifest-*.json` lists every patched spec with full evidence, plus detected API-level conflicts:

```json
{
  "metadata": {
    "scanner": "upstream-dep-scanner",
    "specs_scanned": 2006,
    "specs_patched": 44
  },
  "patched_specs": [...],
  "conflicts_detected": [
    {
      "type": "docker-api",
      "consumer": "docker-compose",
      "consumer_version": "2.40.3",
      "provider": "docker-engine",
      "provider_version": "29.2.1",
      "required_api": "1.51 (from SDK v28.5.1)",
      "provided_range": "1.40..1.54",
      "status": "ok"
    }
  ],
  "severity_summary": { "critical": 154, "important": 0, "informational": 0 }
}
```

## Data Files

| File | Purpose |
|------|---------|
| `data/gomod-package-map.csv` | Maps Go module paths to Photon package names |
| `data/api-version-patterns.csv` | Patterns for extracting API version constants from source |
| `data/docker-api-version-map.csv` | Maps Docker SDK versions to REST API versions (for conflict detection) |

## CI Workflow

The [upstream-source-code-dependency-scanner.yml](../.github/workflows/upstream-source-code-dependency-scanner.yml) workflow runs on the self-hosted runner and:

1. Builds the scanner from source
2. Uses branch repos from `workingDir/photon-{branch}/SPECS` (with sparse clone fallback)
3. Loads PRN package report files for authoritative package-to-clone mapping
4. Runs all three phases using `photon-upstreams` clones
5. Generates a **Findings Summary** highlighting API conflicts and constraint violations
6. Uploads JSON files and `SPECS_DEPFIX/` as a GitHub Actions artifact

Default configuration uses `/mnt/d/Users/Public` as the working directory containing both the branch repos and `photon-upstreams`.

## Validated Results (Photon 5.0)

On the Photon 5.0 branch with PRN-based clone mapping:

- **315 PRN-derived** package-to-clone mappings loaded
- **209 inferred edges** beyond the 9790 spec-declared edges
- **266 virtual provides** including `docker-api = 1.54`, `docker-api-min = 1.40`, `containerd-api`
- **44 spec files patched** with missing declarations
- **Conflicts detected**: docker-compose, docker-buildx, kapacitor, nerdctl, podman, cri-tools, telegraf, calico
- Go packages: containerd, calico, flannel, kubernetes, coredns, etcd, telegraf, podman, nerdctl, etc.
- Python packages: paramiko -> cryptography, prettytable -> wcwidth, jsonschema -> attrs, etc.
