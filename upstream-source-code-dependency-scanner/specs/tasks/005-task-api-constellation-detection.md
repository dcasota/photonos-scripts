# Task 005: API Constellation Detection

**Complexity**: High
**Dependencies**: 004
**Status**: Complete
**Requirement**: REQ-5 (API Version Constellation Detection), REQ-10 (Virtual Provides)
**Feature**: FRD-api-constellation, FRD-virtual-provides
**ADR**: ADR-0003

---

## Description

Implement Docker SDK-to-API version mapping and cross-version conflict detection. This task covers three related capabilities:

### 1. Docker SDK/API Version Mapping

Map Go module SDK versions (e.g., `github.com/docker/docker v28.5.1`) to REST API versions (e.g., `API 1.52`) using `docker-api-version-map.csv`. Generate `Provides: docker-api = 1.52` and `Provides: docker-api-min = 1.24` virtual provides.

### 2. Lower-Bound Conflicts

When a consumer's required API version exceeds what older engines provide, generate:
```
Conflicts: docker-engine < 28.3
```
Evidence: `go.mod docker SDK v28.5.1 → API 1.52, requires engine >= 28.3`

### 3. Upper-Bound Conflicts (Cross-Version)

When the latest version's required API exceeds the current engine's maximum API, generate:
```
Conflicts: docker-engine > 29
```
This detects API incompatibilities between current and future versions — the signature cross-version constellation check.

### 4. Virtual Provides Resolution

Detect when the docker package should declare `Provides: docker-api = 1.52` but does not, and generate a patch to add it.

## Implementation Details

- **Source files**: `src/conflict_detector.c` (phase 3 of `conflict_detect()`), `src/api_version_extractor.c`, `src/virtual_provides.c`
- **Data file**: `data/docker-api-version-map.csv` → `DockerSdkApiMap`
- **Key functions**:
  - `docker_sdk_to_api_version()` — SDK version → API version
  - `docker_api_to_min_engine()` — API version → minimum engine version
  - `extract_docker_sdk_version()` — parse SDK version from edge evidence
  - `version_compare()` — numeric version comparison
- **ConflictRecord**: Written to `conflicts_detected[]` in manifest with `type`, `consumer`, `provider`, `required_api`, `provided_range`, `status`

## Acceptance Criteria

- [ ] `docker SDK v28.5.1` maps to `API 1.52` correctly
- [ ] `Provides: docker-api = 1.52` generated for docker package when missing
- [ ] `Provides: docker-api-min = 1.24` generated for docker package when missing
- [ ] `Conflicts: docker-engine < 28.3` generated for consumers requiring API 1.52
- [ ] `Conflicts: docker-engine > 29` generated when latest API exceeds current engine max
- [ ] Broken API compatibility detected when `clientAPI < serverMinAPI`
- [ ] ConflictRecord includes full provenance: consumer, provider, required API, provided range
- [ ] All Conflicts patches are globally deduplicated via `add_patch_to_set()`
- [ ] No false positives: non-docker edges are not processed

## Testing Requirements

- [ ] Scan 5.0 branch with docker-api-version-map.csv — verify `docker-api = 1.52` provides
- [ ] Verify `docker-compose` gets `Conflicts: docker-engine < X` patch
- [ ] Verify cross-version detection: consumer requiring API > engine max
- [ ] Verify `ConflictRecord.szStatus` is `"BROKEN"` when API incompatible
- [ ] Verify `ConflictRecord.szStatus` is `"ok"` when API is within range
- [ ] Verify no duplicate `Conflicts:` entries in patched specs
- [ ] Validate `conflicts_detected` array in JSON manifest
