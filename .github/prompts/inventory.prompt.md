---
agent: gating-detector
---

# Build Tree Inventory (Phase 0)

## Mission

Produce a comprehensive `gating-inventory.json` capturing the complete state of the Photon OS build tree before any conflict detection runs. This is the ground-truth document that all subsequent analysis depends on.

## Step-by-Step Workflow

### 1. Scan branch configurations

```
FOR each branch in {4.0, 5.0, 6.0}:
  READ <branch>/build-config.json
  EXTRACT:
    - photon-subrelease (string -> int)
    - photon-mainline (string or absent)
    - photon-release-version
    - photon-dist-tag
    - photon-docker-image
  COMPUTE:
    - uses_snapshot = (mainline is absent) OR (subrelease != mainline)
```

### 2. Scan common configuration

```
READ common/build-config.json
EXTRACT:
  - package-repo-url
  - package-repo-snapshot-file-url (template)
  - photon-build-type
  - full-package-list-file
```

### 3. Inventory all spec files

```
FOR each spec_dir in {common/SPECS/, <branch>/SPECS/ for each branch}:
  WALK directory tree recursively
  FOR each .spec file:
    EXTRACT:
      - Name: field
      - Version: field
      - Release: field
      - build_if condition (if present): operator + threshold
      - All %package subpackage declarations -> package names
      - All Requires: dependencies
      - All BuildRequires: dependencies
      - All ExtraBuildRequires: dependencies
    RECORD: (file_path, name, version, release, gate, packages[], requires[], buildrequires[])
```

### 4. Map relocated directories

```
FOR each SPECS/<N>/ directory found:
  RECORD: (directory_path, threshold_value=N, spec_count, spec_names[])
  CROSS-REFERENCE: which SPECS/<N>/ specs have counterparts in SPECS/ (the >=N+1 versions)
```

### 5. Produce output

Save as `gating-inventory.json`:

```json
{
  "timestamp": "ISO-8601",
  "base_dir": ".",
  "common": {
    "snapshot_url_template": "...",
    "package_repo_url": "..."
  },
  "branches": [
    {
      "name": "5.0",
      "subrelease": 91,
      "mainline": 91,
      "release_version": "5.0",
      "uses_snapshot": false,
      "spec_count": 142,
      "gated_spec_count": 38
    }
  ],
  "gated_specs": [
    {
      "path": "5.0/SPECS/libcap/libcap.spec",
      "name": "libcap",
      "version": "2.77",
      "gate": ">= 92",
      "packages": ["libcap", "libcap-libs", "libcap-minimal", "libcap-devel", "libcap-doc"],
      "requires": ["libcap-minimal", "libcap-libs"]
    }
  ],
  "relocated_dirs": [
    {
      "path": "5.0/SPECS/91/",
      "threshold": 91,
      "spec_count": 15,
      "specs": ["libcap", "rpm", "dbus", "docker", ...]
    }
  ]
}
```

## Quality Checklist

- [ ] All three branches scanned (4.0, 5.0, 6.0)
- [ ] Common branch scanned
- [ ] Every .spec file processed (no skips due to parse errors)
- [ ] All SPECS/<N>/ directories discovered and mapped
- [ ] Cross-references between old/new spec pairs established
- [ ] JSON output is valid and parseable
