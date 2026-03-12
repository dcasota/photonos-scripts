# Feature Requirement Document: API Version Constellation Detection

**Feature ID**: FRD-api-constellation
**Related PRD Requirements**: REQ-5, REQ-10
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Detect Docker SDK-to-API version mismatches across the Photon package ecosystem by extracting API version constants from source code, mapping SDK versions to REST API versions, and generating `Conflicts:` directives when version incompatibilities are found.

### Value Proposition

Docker ecosystem packages (docker-compose, docker-buildx, containerd, etc.) depend on specific Docker SDK versions that imply minimum and maximum REST API versions. When a consumer uses SDK v28.5.1 (API 1.52) but the installed docker-engine only supports up to API 1.47, silent runtime failures occur. Constellation detection converts these implicit version contracts into explicit `Conflicts:` directives.

### Success Criteria

- [SC-2] Docker API version extraction produces correct `docker-api = 1.52` virtual provide
- [SC-3] Cross-version detection generates both `Conflicts: docker-engine < 28.3` and `Conflicts: docker-engine > 29` where applicable
- Docker SDK-to-API mapping is driven by `docker-api-version-map.csv`
- API version patterns are configurable via `api-version-patterns.csv`
- Virtual provides (`docker-api`, `docker-api-min`, `containerd-api`) are added to the graph

---

## 2. Functional Requirements

### 2.1 Docker SDK-to-API Version Mapping

**Description**: Load a CSV mapping Docker SDK versions to their corresponding REST API versions.

**CSV format** (`docker-api-version-map.csv`):
```
sdk_min,sdk_max,api_version
28.0,28.5,1.47
28.5.1,28.99,1.52
29.0,29.99,1.53
```

**API functions**:
- `docker_sdk_map_load()`: Load the CSV
- `docker_sdk_to_api_version()`: Forward lookup (SDK → API)
- `docker_api_to_min_engine()`: Reverse lookup (API → minimum engine version)

**Acceptance Criteria**:
- SDK version `28.5.1` maps to API version `1.52`
- API version `1.44` reverse-maps to minimum engine `25.0`
- Supports up to `MAX_SDK_MAP_ENTRIES` (64) entries
- Graceful fallback when CSV is not available

### 2.2 API Version Pattern Extraction

**Description**: Extract API version constants from upstream source code files by applying regex-like patterns defined in `api-version-patterns.csv`.

**CSV format** (`api-version-patterns.csv`):
```
package,file_path,pattern,provide_type,virtual_name
docker,client/client.go,DefaultVersion.*"([0-9]+\.[0-9]+)",provides,docker-api
containerd,api/services/version/version.go,Version.*=.*"([0-9]+\.[0-9]+)",provides,containerd-api
```

**Implementation**: `api_version_extract()` in `api_version_extractor.h`.

**Acceptance Criteria**:
- Scans the specified file in each clone directory for the pattern
- Extracts the version string from the first capture group
- Creates a `VirtualProvide` entry: e.g., `docker-api = 1.52` provided by the docker node
- Uses PRN map to resolve clone directories when package name differs from clone name
- Supports up to `MAX_PATTERN_ENTRIES` (128) patterns

### 2.3 Virtual Provides

**Description**: API version constants are represented as `VirtualProvide` entries in the graph, enabling version-based conflict detection.

**Virtual provide types**:

| Virtual Name | Example | Description |
|-------------|---------|-------------|
| `docker-api` | `docker-api = 1.52` | Docker REST API version provided by docker-engine |
| `docker-api-min` | `docker-api-min = 1.24` | Minimum API version still supported |
| `containerd-api` | `containerd-api = 1.7` | containerd API version |

**Acceptance Criteria**:
- Virtual provides are added to `pGraph->pVirtuals` array
- Each entry records: name, version, provider node index, source, evidence
- `virtual_resolve_edges()` resolves unresolved edges by matching against virtual provides
- Summary reports virtual provide count

### 2.4 Lower-Bound Conflict Detection

**Description**: When a consumer requires a Docker API version newer than what the current engine provides, generate a `Conflicts: docker-engine < X` directive.

**Logic**:
1. For each gomod edge targeting `docker` (or `docker-engine`), extract the SDK version from the constraint
2. Map SDK version → API version using `docker_sdk_to_api_version()`
3. Map API version → minimum engine version using `docker_api_to_min_engine()`
4. Generate: `Conflicts: docker-engine < {min_engine_version}`

**Example**: docker-compose requires `github.com/docker/docker v28.5.1` → SDK 28.5.1 → API 1.52 → `Conflicts: docker-engine < 28.3` (engine 28.3+ supports API 1.52)

**Acceptance Criteria**:
- Correct `Conflicts:` directive generated with `CONSTRAINT_LT` operator
- Evidence string includes SDK version, API version, and minimum engine version
- Patch severity is `SEVERITY_CRITICAL`
- Only generated when the consumer's required API exceeds the provider's minimum

### 2.5 Upper-Bound Conflict Detection (Cross-Version)

**Description**: When the latest version of a consumer SDK requires an API version that exceeds the current engine's maximum supported API, generate a `Conflicts: docker-engine > X` directive.

**Logic**:
1. Find the latest version node (`bIsLatest = 1`) for the consumer
2. Extract its SDK version and map to API version
3. Find the current engine node (`bIsLatest = 0`) and its maximum supported API (from virtual provides)
4. If the latest consumer's API > current engine's max API: `Conflicts: docker-engine > {max_engine_version}`

**Example**: docker-compose (latest) requires SDK v29.0 → API 1.53, but current docker-engine provides `docker-api = 1.52` → `Conflicts: docker-engine > 29` (version 29+ breaks current API compatibility)

**Acceptance Criteria**:
- Cross-version detection only fires when both current and latest nodes exist
- Uses `bIsLatest` flag to distinguish current vs. latest nodes
- Generates `Conflicts:` with `CONSTRAINT_GT` operator
- Evidence string documents the cross-version API mismatch

---

## 3. Data Model

### VirtualProvide Fields

| Field | Type | Max Size | Description |
|-------|------|----------|-------------|
| `szName` | char[] | 256 | Virtual provide name (e.g., `docker-api`) |
| `szVersion` | char[] | 64 | Version string (e.g., `1.52`) |
| `dwProviderIdx` | uint32_t | -- | Graph node index of the provider |
| `nSource` | EdgeSource | -- | `EDGE_SRC_API_CONSTANT` |
| `szEvidence` | char[] | 512 | Source file and pattern match details |

### ConflictRecord Fields

| Field | Type | Description |
|-------|------|-------------|
| `szType` | char[256] | `"lower-bound-conflict"` or `"upper-bound-conflict"` |
| `szConsumer` | char[256] | Package consuming the API |
| `szProvider` | char[256] | Package providing the API (e.g., `docker-engine`) |
| `szRequiredApi` | char[64] | API version required by consumer |
| `szProvidedRange` | char[512] | API version range provided by engine |

---

## 4. Edge Cases

- **SDK version not in mapping**: If a consumer's Docker SDK version is not in `docker-api-version-map.csv`, the conflict check is skipped for that edge (no false positive).
- **No virtual provides found**: If API version extraction finds no constants (pattern didn't match), virtual provides array is empty and cross-version detection is skipped.
- **Same API version**: If consumer and provider have the same API version, no conflict is generated.
- **Multiple consumers**: Each consumer (docker-compose, docker-buildx, calico, etc.) is checked independently; each may generate its own `Conflicts:` directive.
- **Missing docker-engine node**: If docker-engine is not in the graph (not a Photon package), upper-bound detection has no reference point and is skipped.
- **Pre-API packages**: Older Docker SDK versions that predate the API versioning scheme are treated as `CONSTRAINT_NONE` and skipped.

---

## 5. Dependencies

**Depends On**: FRD-spec-parsing (nodes must exist), FRD-gomod-analysis (SDK version edges come from gomod), FRD-dual-version (cross-version detection needs both current and latest nodes), `docker-api-version-map.csv`, `api-version-patterns.csv`

**Depended On By**: FRD-deduplication (API conflict patches participate in dedup), FRD-output (conflicts written to manifest and JSON)
