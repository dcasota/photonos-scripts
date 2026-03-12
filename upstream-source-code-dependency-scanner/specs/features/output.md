# Feature Requirement Document: Dual-Format Output

**Feature ID**: FRD-output
**Related PRD Requirements**: REQ-8
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Produce machine-readable and human-actionable output from every scan: a JSON manifest summarizing findings, an enriched dependency graph JSON for visualization and further analysis, and patched spec files in `SPECS_DEPFIX/` with changelog entries for direct integration into branch repositories.

### Value Proposition

Scan results must be consumable by multiple downstream systems: CI dashboards (JSON manifest), graph visualization tools (dependency graph JSON), and package maintainers (patched spec files). Dual-format output ensures all stakeholders can consume findings in their preferred format.

### Success Criteria

- [SC-7] JSON manifest validates against `depfix-manifest-schema.json`
- Manifest filename follows convention: `depfix-manifest-{branch}-{timestamp}.json`
- Dependency graph JSON includes all nodes, edges, virtual provides, and conflicts
- Patched spec files in `SPECS_DEPFIX/{branch}/{package}/` are syntactically valid RPM specs
- Changelog entries include timestamp, author, and list of added directives

---

## 2. Functional Requirements

### 2.1 JSON Manifest

**Description**: Write a summary manifest JSON file capturing the scan metadata, statistics, and per-package findings.

**Implementation**: `manifest_write()` in `manifest_writer.h`.

**Filename**: `depfix-manifest-{branch}-{timestamp}.json` (e.g., `depfix-manifest-5.0-20260312T140000.json`)

**Schema fields**:

```json
{
  "version": "1.0",
  "branch": "5.0",
  "timestamp": "2026-03-12T14:00:00Z",
  "summary": {
    "specs_scanned": 4400,
    "specs_patched": 44,
    "nodes": 5200,
    "edges_declared": 12000,
    "edges_inferred": 850,
    "virtual_provides": 12,
    "issues_detected": 145
  },
  "findings": [
    {
      "package": "docker-compose",
      "spec_path": "SPECS/docker-compose/docker-compose.spec",
      "additions": [
        {
          "directive": "Requires",
          "value": "docker >= 28.0",
          "source": "gomod",
          "severity": "critical",
          "evidence": "go.mod: github.com/docker/docker v28.5.1"
        }
      ]
    }
  ]
}
```

**Acceptance Criteria**:
- JSON is well-formed and parseable by any JSON parser
- Uses json-c library for generation (project dependency)
- Timestamp is ISO 8601 format
- Each finding includes all patch additions with directive, value, source, severity, and evidence
- File is written to the output directory specified by `--output-dir`

### 2.2 Enriched Dependency Graph JSON

**Description**: Write the full dependency graph (nodes, edges, virtual provides, conflicts) as a JSON file for downstream visualization and analysis tools.

**Implementation**: `json_output_write()` in `json_output.h`.

**Filename**: `dependency-graph-{branch}-deep-{timestamp}.json`

**Activation**: Only written when `--json` flag is provided.

**Schema structure**:

```json
{
  "metadata": {
    "branch": "5.0",
    "timestamp": "2026-03-12T14:00:00Z"
  },
  "nodes": [
    {
      "id": 0,
      "name": "docker-compose",
      "version": "2.32.4",
      "is_latest": false,
      "is_subpackage": false,
      "spec_path": "SPECS/docker-compose/docker-compose.spec",
      "build_arch": "",
      "exclusive_arch": "x86_64 aarch64"
    }
  ],
  "edges": [
    {
      "from": 0,
      "to": 42,
      "type": "Requires",
      "source": "gomod",
      "target_name": "docker",
      "constraint_op": ">=",
      "constraint_ver": "28.5.1",
      "qualifier": "",
      "evidence": "go.mod: github.com/docker/docker v28.5.1"
    }
  ],
  "virtual_provides": [
    {
      "name": "docker-api",
      "version": "1.52",
      "provider": "docker",
      "source": "api_constant",
      "evidence": "client/client.go: DefaultVersion = \"1.52\""
    }
  ],
  "conflicts": [
    {
      "type": "lower-bound-conflict",
      "consumer": "docker-compose",
      "provider": "docker-engine",
      "required_api": "1.52",
      "status": "missing-conflicts-directive"
    }
  ]
}
```

**Acceptance Criteria**:
- All graph nodes are serialized with all metadata fields
- All graph edges include type, source, constraint, qualifier, and evidence
- Virtual provides include provider node reference
- Conflict records include type, consumer, provider, and status
- Node `bIsLatest` flag is serialized as `is_latest` boolean

### 2.3 Patched Spec Files (SPECS_DEPFIX)

**Description**: Generate patched copies of spec files with missing directives added and changelog entries injected.

**Implementation**: `spec_patch_all()` and `spec_patch_file()` in `spec_patcher.h`.

**Output directory**: `{output_dir}/SPECS_DEPFIX/{branch}/{package}/{package}.spec`

**Activation**: Only written when `--patch-specs` flag is provided.

**Patch insertion rules**:
1. New `Requires:` directives are added after the last existing `Requires:` line in the appropriate section
2. New `Conflicts:` directives are added after the last existing `Conflicts:` line
3. New `Provides:` directives are added after the last existing `Provides:` line
4. If no existing directive of that type exists, the new directive is added after the `Version:` line

**Acceptance Criteria**:
- Patched spec is a valid RPM spec (all original content preserved, new lines added)
- Original spec file is never modified (read-only constraint from PRD)
- Patched spec path is recorded in `SpecPatchSet.szPatchedPath`
- Directory structure `SPECS_DEPFIX/{branch}/{package}/` is created as needed

### 2.4 Changelog Injection

**Description**: Each patched spec file receives a new `%changelog` entry documenting the added directives.

**Format**:
```
%changelog
* Wed Mar 12 2026 depfix-scanner <depfix@photon.vmware.com> - {version}-{release}
- [depfix] Added Requires: docker >= 28.0 (source: gomod, severity: critical)
- [depfix] Added Conflicts: docker-engine < 28.3 (source: gomod, severity: critical)
```

**Acceptance Criteria**:
- Changelog entry is prepended to existing `%changelog` section
- Date format matches RPM changelog convention (`%a %b %d %Y`)
- Each added directive is listed as a separate changelog bullet
- Source provenance and severity are included in each bullet
- If no `%changelog` section exists, one is created at the end of the spec

---

## 3. Data Model

### Output Files

| Output | Filename Pattern | Condition | Format |
|--------|-----------------|-----------|--------|
| Manifest | `depfix-manifest-{branch}-{timestamp}.json` | Always | JSON |
| Graph | `dependency-graph-{branch}-deep-{timestamp}.json` | `--json` flag | JSON |
| Patched specs | `SPECS_DEPFIX/{branch}/{pkg}/{pkg}.spec` | `--patch-specs` flag | RPM spec |

### SpecPatchSet Fields (output-relevant)

| Field | Type | Description |
|-------|------|-------------|
| `szSpecPath` | char[512] | Path to original spec file |
| `szPatchedPath` | char[512] | Path to patched output spec file |
| `szPackageName` | char[256] | Package name |
| `dwAdditionCount` | uint32_t | Number of directives added |
| `pAdditions` | SpecPatch* | Linked list of additions |

---

## 4. Edge Cases

- **No issues found**: Manifest is still written with `issues_detected: 0` and empty `findings` array. No patched specs are generated.
- **Output directory doesn't exist**: Created with `mkdir(pszOutputDir, 0755)` in `main.c`.
- **Timestamp collision**: Two scans in the same second produce files with identical names. In practice, CI runs are serialized per branch.
- **Very large graph**: JSON output for a 7-branch scan may be several MB. json-c handles this without issues.
- **Spec file with no %changelog**: A new `%changelog` section is appended at the end of the file.
- **Read-only original spec**: If the original spec file is unreadable, the patch is skipped and an error is logged.
- **Multiple subpackage sections**: Directives are added to the correct section (`%package devel` additions go in the devel section, not the main preamble).

---

## 5. Dependencies

**Depends On**: FRD-deduplication (patched specs contain only deduplicated entries), FRD-spec-parsing (original spec paths), FRD-api-constellation (conflict records), json-c library

**Depended On By**: FRD-ci-integration (CI workflow uploads output artifacts)
