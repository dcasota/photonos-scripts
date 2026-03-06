---
agent: gating-detector
---

# Build Traceability Matrix

## Mission

For each `build_if` gated spec in the build tree, produce a full traceability chain showing the blast radius of a single gating change across all dimensions.

## Traceability Chain

For each gated spec S:

```
S (spec)
  -> subpackages produced by S
    -> specs that Require/BuildRequire those subpackages
      -> branches where those consuming specs are active
        -> snapshots used by those branches
          -> ISO flavors that include those packages
            -> architectures built
```

## Output Format

### Human-Readable (traceability.md)

```markdown
## libcap (SPECS/libcap/libcap.spec)

Gate: >= 92 | Packages: libcap, libcap-libs, libcap-minimal, libcap-devel, libcap-doc

| Subpackage | Consumed By | Branches | Snapshots | Flavors | Arch |
|-----------|-------------|----------|-----------|---------|------|
| libcap-libs | rpm.spec (Requires) | 5.0, 6.0 | 91, 92 | minimal, full, fips | x86_64, aarch64 |
| libcap-minimal | (none direct) | - | - | - | - |
| libcap-devel | (build-time only) | 5.0, 6.0 | 91, 92 | full | x86_64, aarch64 |

**Blast radius if snapshot predates split**: Ph5 with snapshot-91 cannot resolve libcap-libs.
rpm-4.18.2-9 (gated >= 92) depends on libcap-libs, but Ph5 with subrelease=91 builds
rpm-4.18.2-8 (gated <= 91) which depends on monolithic libcap. However, if the snapshot
metadata references the split packages, tdnf encounters disabled packages -> Solv error.
```

### Machine-Readable (traceability.json)

```json
[
  {
    "spec": "SPECS/libcap/libcap.spec",
    "gate": ">= 92",
    "subpackages": ["libcap", "libcap-libs", "libcap-minimal", "libcap-devel", "libcap-doc"],
    "consumers": [
      {
        "subpackage": "libcap-libs",
        "consuming_spec": "SPECS/rpm/rpm.spec",
        "relationship": "Requires",
        "consuming_spec_gate": ">= 92"
      }
    ],
    "blast_radius": {
      "branches": ["5.0", "6.0"],
      "snapshots_affected": [91],
      "architectures": ["x86_64", "aarch64"],
      "flavors": ["minimal", "full", "fips"]
    }
  }
]
```

## Process

1. **Build the forward dependency graph**: spec -> packages -> consuming specs
2. **Build the reverse dependency graph**: package -> which specs produce it -> which gate
3. **Cross-reference with branch configs**: which branches activate which specs
4. **Cross-reference with snapshots**: which snapshots contain which packages
5. **Determine flavor impact**: check if affected packages appear in minimal, full, or FIPS package lists

## Quality Checklist

- [ ] Every gated spec in the inventory has a traceability entry
- [ ] All subpackages are listed (not just the main package)
- [ ] Consumer relationships specify the type (Requires, BuildRequires, ExtraBuildRequires)
- [ ] Blast radius includes all dimensions (branch, snapshot, arch, flavor)
- [ ] Both human and machine formats produced
