---
agent: gating-detector
---

# Detect Gating Conflicts

## Mission

Run a complete gating conflict scan across the Photon OS build tree. Produce a dual-format report (human markdown + machine JSON) covering all 6 constellations.

## Step-by-Step Workflow

### 1. Read and understand the context

**ALWAYS start by reading:**

- `common/build-config.json` -- snapshot URL template, base repo URL
- `<branch>/build-config.json` for each branch -- subrelease, mainline, release version
- All `.spec` files with `build_if` directives in `common/SPECS/` and `<branch>/SPECS/`

### 2. Run Phase 0: Inventory

Produce `gating-inventory.json` before any detection:

- Catalog every gated spec with its gate operator, threshold, packages, and requires
- Map all `SPECS/<N>/` relocated directories
- Record each branch's subrelease, mainline, and snapshot usage status

### 3. Run Phase 1: Detection (C1-C6)

For each constellation:

- **C1**: Compare package sets between new specs (`SPECS/`) and old specs (`SPECS/<N>/`). Check if any active spec depends on subpackages that don't exist in the old version.
- **C2**: Compare requires sets. Check for new dependencies not satisfiable at the old subrelease.
- **C3**: If snapshot dates are available, check if gating commits postdate the snapshot.
- **C4**: Check for name collisions between common/ and branch specs at each branch's subrelease.
- **C5**: For each active kernel spec, verify FIPS canister version is available.
- **C6**: If `--check-urls` is set, HTTP HEAD the resolved snapshot URL.

### 4. Run Phase 2: Traceability

For every finding, trace the full blast radius:

```
spec -> subpackages -> consuming specs -> branches -> snapshots -> ISO flavors
```

### 5. Produce output

- `findings.md` -- human-readable, organized by severity (BLOCKING > CRITICAL > HIGH > WARNING > INFO)
- `findings.json` -- machine-readable, conforming to `gating-findings-schema.json`

## Quality Checklist

Before finalizing:

- [ ] Phase 0 inventory was produced first
- [ ] All 6 constellations were checked
- [ ] Every finding has at least one spec file path reference
- [ ] Every finding includes branch name and subrelease value
- [ ] Every C1 finding lists specific missing subpackages
- [ ] Every C5 finding includes exact canister version string
- [ ] Every C6 finding includes HTTP status code and URL
- [ ] Every remediation suggestion specifies which build-config.json keys to change
- [ ] Traceability matrix covers: branch, architecture, flavor (minimal/full/FIPS)
- [ ] Dual output produced (markdown + JSON)
