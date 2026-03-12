---
agent: spec-patcher
---

# Generate Patched Spec Files

## Mission

Take the deduplicated patch sets from conflict-detector and produce patched `.spec` files in `SPECS_DEPFIX/`. Every patched spec must be syntactically valid with no duplicate directives.

## Step-by-Step Workflow

### 1. Validate patch sets

Before writing any files:

- For each `SpecPatchSet` in the graph:
  - Verify the source spec file path exists and is readable
  - Verify each patch has non-empty `szDirective` and `szValue`
  - Verify no patch duplicates an existing directive in the original spec
  - Verify no two patches in the set have identical `(directive, value)` pairs
- Log warnings for any rejected patches (with reason)
- Report total validated patches per package

### 2. Create output directory structure

```
SPECS_DEPFIX/
└── {branch}/
    └── {package}/
        └── {name}.spec
```

- Create `SPECS_DEPFIX/{branch}/` if it does not exist
- Create per-package subdirectories as needed

### 3. Generate patched specs

For each validated `SpecPatchSet`:

1. **Read** the original spec from `SPECS/{package}/{name}.spec`
2. **Copy** the entire content as the patch base
3. **Insert** new directives in the correct locations:
   - `Requires:` → after the last existing `Requires:` in the target section
   - `Conflicts:` → after the last existing `Conflicts:` in the target section
   - `Provides:` → after the last existing `Provides:` in the target section
   - For subpackage patches, insert in the correct `%package` section
4. **Annotate** each added line with a comment:
   ```
   # Added by depscanner: <evidence>
   Requires: <package-name>
   ```
5. **Add changelog entry**:
   ```
   * <date> Dependency Scanner <depscanner@photon.vmware.com> <version>-<release>
   - Auto-patched: added <N> missing dependency declarations
   - Source: upstream-source-code-dependency-scanner
   ```
6. **Write** to `SPECS_DEPFIX/{branch}/{package}/{name}.spec`

### 4. Verify output

After writing all patched specs:

- Re-read each patched file and verify:
  - File is non-empty
  - No duplicate `Requires:` entries exist
  - No duplicate `Conflicts:` entries exist
  - No duplicate `Provides:` entries exist
  - All patches from the input set are present
  - The `%changelog` entry was added
- Report total: files written, directives added, any verification failures

## Quality Checklist

- [ ] No original spec files in `SPECS/` or `SPECS_NEW/` were modified
- [ ] All patched specs are written to `SPECS_DEPFIX/{branch}/{package}/`
- [ ] No patched spec contains duplicate dependency directives
- [ ] Every added directive has an evidence comment
- [ ] Every patched spec has a `%changelog` entry
- [ ] Directives are inserted in the correct spec section
- [ ] Directive ordering follows RPM conventions
- [ ] Output file count matches the number of packages with valid patches
- [ ] All patched specs can be re-parsed without errors
