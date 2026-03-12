# ADR-0005: RPM Spec Standard Compliance (4.20.x Current, 6.0.x Forward)

**Status**: Accepted
**Date**: 2026-03-12
**Deciders**: upstream-source-code-dependency-scanner maintainers

---

## Context

The scanner parses RPM spec files to extract dependency directives (`Requires:`, `Conflicts:`, `Provides:`, etc.) and build a dependency graph. The authoritative reference for spec file syntax is the RPM project documentation. Photon OS currently ships RPM 4.x (covered by the [4.20.x docs](https://rpm.org/docs/4.20.x/manual/spec.html)), but RPM 6.0.x is the next major release and Photon OS 6.0 or a future branch may adopt it.

This ADR records which RPM specification versions the scanner targets, what the normative rules are for dependency directives under each, and what forward-compatibility work is required for 6.0.x.

---

## Decision Drivers

1. **Correctness**: The scanner's parser must match the RPM runtime's interpretation of dependency directives exactly.
2. **Forward compatibility**: Photon OS branches will eventually adopt RPM 6.0.x; the scanner must not silently produce wrong output when that happens.
3. **Minimal over-parsing**: The scanner should not implement features it cannot validate (e.g., full macro expansion), but must correctly handle everything in the directive-level grammar.

---

## Decision

### Normative Reference: RPM 4.20.x (Current)

The scanner's spec parser is implemented against the [RPM 4.20.x Spec File Format](https://rpm.org/docs/4.20.x/manual/spec.html) as the current normative standard. All dependency directives and their syntax rules are drawn from this version.

#### Runtime Dependency Directives (4.20.x)

Per [spec.html#dependencies](https://rpm.org/docs/4.20.x/manual/spec.html#dependencies):

| Directive | Semantics | Since |
|-----------|-----------|-------|
| `Requires:` | Strong forward dependency; orders installs/erasures | RPM 2.0 |
| `Requires(qualifier):` | Scriptlet-scoped dependency with install-time ordering | RPM 2.0 |
| `Provides:` | Declares capabilities; `name = [epoch:]version-release` auto-added | RPM 2.0 |
| `Conflicts:` | Inverse of Requires; prevents co-installation | RPM 2.0 |
| `Obsoletes:` | Declares package replacement; alters upgrade behavior | RPM 2.0 |
| `Recommends:` | Weak forward dependency (depsolver attempts to satisfy) | RPM 4.13 |
| `Suggests:` | Very weak forward dependency (shown as option) | RPM 4.13 |
| `Supplements:` | Weak reverse dependency | RPM 4.13 |
| `Enhances:` | Very weak reverse dependency | RPM 4.13 |

#### Build-Time Dependency Directives (4.20.x)

| Directive | Semantics | Since |
|-----------|-----------|-------|
| `BuildRequires:` | Resolved before building; becomes Requires in SRPM | RPM 2.0 |
| `BuildConflicts:` | Cannot be installed during build | RPM 4.0 |
| `BuildPreReq:` | **Obsolete** -- do not use | deprecated |

#### Ordering and Constraint Directives (4.20.x)

| Directive | Semantics | Since |
|-----------|-----------|-------|
| `OrderWithRequires:` | Ordering hint only; does not create a hard dependency | RPM 4.9 |
| `Prereq:` | **Obsolete** -- do not use | deprecated |

#### `Requires(qualifier):` Qualifiers (4.20.x)

Per [spec.html#requires](https://rpm.org/docs/4.20.x/manual/spec.html#requires), accepted qualifiers are:

| Qualifier | Behavior | Notes |
|-----------|----------|-------|
| `pre` | Must be present before install; strong ordering hint | Install-time only |
| `post` | Must be present after install; strong ordering hint | Install-time only |
| `preun` | Must be present before erase; strong ordering hint | |
| `postun` | Must be present after erase; strong ordering hint | |
| `pretrans` | Must be present before transaction starts; cannot be satisfied by added packages | Install-time only |
| `posttrans` | Must be present at end of transaction; cannot be removed during transaction | Install-time only |
| `verify` | Relates to `%verify` scriptlet; does not affect transaction ordering | |
| `interp` | Scriptlet interpreter dep; strong ordering hint for breaking loops | Usually auto-added |
| `meta` | Must NOT affect transaction ordering; for meta-packages and sub-package cross-deps | Since RPM 4.16 |

**Key rule**: `meta` contradicts any ordered qualifier. `pre` + `verify` is valid; `pre` + `meta` is not. Multiple qualifiers are comma-separated.

**Key pitfall**: Dependencies qualified as install-time only (`pretrans`, `pre`, `post`, `posttrans`) can be removed after the install transaction completes. `Requires(pre):` is NOT equivalent to the deprecated `PreReq:`.

#### Version Constraint Syntax (4.20.x)

Per [dependencies.html#versioning](https://rpm.org/docs/4.20.x/manual/dependencies.html#versioning):

```
capability [operator version]
```

- Operators: `=`, `<`, `>`, `<=`, `>=`
- Full version syntax: `[epoch:]version[-release]`
- Epoch is optional, defaults to 0; neither version nor release may contain `-`
- Spaces are required around the operator
- Version ordering uses `rpmvercmp()`: segmented strcmp with digit/alpha boundaries

#### Boolean Dependencies (4.20.x)

Per [boolean_dependencies.html](https://rpm.org/docs/4.20.x/manual/boolean_dependencies.html):

Boolean expressions are supported in all dependency types (since RPM 4.13). Always enclosed in parentheses. Operators:

| Operator | Since | Example |
|----------|-------|---------|
| `and` | 4.13 | `Requires: (pkgA and pkgB)` |
| `or` | 4.13 | `Requires: (pkgA or pkgB)` |
| `if` | 4.13 | `Recommends: (myPkg-langCZ if langsupportCZ)` |
| `if else` | 4.13 | `Requires: (mariaDB if mariaDB else sqlite)` |
| `with` | 4.14 | `Requires: (pkgA-foo with pkgA-bar)` |
| `without` | 4.14 | `Requires: (pkgA-foo without pkgA-bar)` |
| `unless` | 4.14 | `Conflicts: (driverA unless driverB)` |
| `unless else` | 4.14 | `Conflicts: (SDL1 unless SDL2 else SDL2)` |

**Important**: `Provides:` cannot contain boolean expressions.

**Scanner status**: Boolean dependency parsing is NOT currently implemented. The scanner captures the raw text of boolean expressions as-is. This is correct for the scanner's purpose (detecting *missing* directives from source analysis), since source-derived dependencies are always simple `name [op version]` form. See forward-compatibility note below.

#### Architecture and OS Directives (4.20.x)

| Directive | Semantics |
|-----------|-----------|
| `ExcludeArch:` | Package not buildable on listed architectures |
| `ExclusiveArch:` | Package only buildable on listed architectures |
| `ExcludeOS:` | Package not buildable on listed OSes |
| `ExclusiveOS:` | Package only buildable on listed OSes |
| `BuildArch:` | Target architecture; `noarch` for platform-independent |

**Note**: `BuildArch` causes spec parsing to recurse from the start, expanding macros twice. The scanner does not perform macro expansion, so this is not a concern.

#### Automatic Dependency Generation (4.20.x)

Per [more_dependencies.html](https://rpm.org/docs/4.20.x/manual/more_dependencies.html#automatic-dependencies):

RPM auto-generates `Requires:` for shared libraries (via ldd) and `Provides:` for sonames. Per-package control via `AutoReqProv:`, `AutoReq:`, `AutoProv:` (values: `1`/`0` or `yes`/`no`).

**Scanner impact**: The scanner operates on spec file text, not on built RPMs. Auto-generated dependencies are invisible to the scanner by design -- the scanner detects *missing manual declarations* that auto-generation does not cover (e.g., Go module imports).

---

### Forward Reference: RPM 6.0.x (Future)

The scanner must be prepared for [RPM 6.0.x](https://rpm.org/docs/6.0.x/manual/spec.html) adoption in future Photon OS branches.

#### What Is Unchanged in 6.0.x

After comparing the full spec.html, dependencies.html, more_dependencies.html, and boolean_dependencies.html pages between 4.20.x and 6.0.x, the following are **identical**:

1. **All dependency directive names and syntax** -- `Requires:`, `Provides:`, `Conflicts:`, `Obsoletes:`, `Recommends:`, `Suggests:`, `Supplements:`, `Enhances:`, `BuildRequires:`, `BuildConflicts:`, `OrderWithRequires:` -- same tags, same semantics, same form.
2. **`Requires(qualifier):` qualifiers** -- same 9 qualifiers (`pre`, `post`, `preun`, `postun`, `pretrans`, `posttrans`, `verify`, `interp`, `meta`), same combination rules, same install-time-only semantics.
3. **Version constraint syntax** -- `[epoch:]version[-release]` with operators `=`, `<`, `>`, `<=`, `>=`; `rpmvercmp()` algorithm unchanged.
4. **Boolean dependency operators** -- same 8 operators (`and`, `or`, `if`, `if else`, `with`, `without`, `unless`, `unless else`), same nesting restrictions.
5. **Weak dependency semantics** -- same forward/reverse, weak/very-weak grid.
6. **Architecture/OS directives** -- `ExcludeArch:`, `ExclusiveArch:`, `ExcludeOS:`, `ExclusiveOS:`, `BuildArch:` unchanged.
7. **`%package` subpackage syntax** -- identical, including `-n` override.
8. **Auto-dependency generation** -- same `AutoReqProv`/`AutoReq`/`AutoProv` mechanism.
9. **Obsolete directives** -- `Prereq:`, `BuildPreReq:`, `BuildRoot:` remain deprecated/ignored.

#### What Changed in 6.0.x (Editorial and Non-Dependency)

| Change | 4.20.x | 6.0.x | Scanner Impact |
|--------|--------|-------|----------------|
| `%caps` directive in `%files` | Not documented | `%caps(cap_net_raw=p)` documented | None -- scanner does not parse `%files` |
| Typo fixes | "undesireable", "dependnecy" | "undesirable", "dependency" | None |
| `%changelog` section | Separate link | Inline `#changelog-section` anchor | None |
| `%patch` syntax | `%patch1` removed since 4.20 | Same | None |
| Build scriptlet phrasing | "possible being stored" | "possibly being stored" | None |

#### Forward-Compatibility Actions Required

| # | Action | Priority | Rationale |
|---|--------|----------|-----------|
| FC-1 | No parser changes needed for 6.0.x dependency directives | -- | Directive grammar is identical |
| FC-2 | Monitor RPM 6.0.x release notes for any new dependency types | Low | None announced as of 2026-03-12 |
| FC-3 | Consider boolean dependency decomposition if Photon specs adopt them | Low | Currently no Photon specs use boolean deps; scanner captures raw text |
| FC-4 | Consider `%generate_buildrequires` output parsing | Low | Dynamic BuildRequires from unpacked sources; not relevant for runtime dep scanning |
| FC-5 | Validate `meta` qualifier handling on RPM 6.0.x runtime | Medium | `meta` (since 4.16) may see wider use in Photon 6.0; scanner preserves it but should verify tdnf behavior |

---

## Considered Options

### Option 1: Target 4.20.x Only (Chosen for Current, with 6.0.x Forward Reference)

Parse against 4.20.x spec. Document 6.0.x differences. No code changes needed since the dependency grammar is identical.

### Option 2: Target 6.0.x as Primary

Premature -- Photon OS has not adopted RPM 6.0.x yet. Would require testing against a runtime that doesn't exist in the build environment.

### Option 3: Abstract RPM Version Behind a Config Switch

Over-engineering -- the dependency directive grammar is identical between versions. A config switch would add complexity for zero functional difference.

---

## Decision Outcome

**Chosen: Option 1**. The scanner targets RPM 4.20.x as the normative standard. RPM 6.0.x is documented as a forward reference. Since the dependency directive grammar is identical between the two versions, no code changes are required for 6.0.x compatibility. The scanner's existing parser is already 6.0.x-compatible for all dependency-related functionality.

### Consequences

**Positive**:
- Scanner is grounded in authoritative RPM specification
- Forward compatibility is documented and requires no immediate code changes
- All dependency directive types, qualifiers, operators, and syntax rules are captured in SDD

**Negative**:
- Boolean dependency decomposition is deferred (raw text capture only)
- If RPM 6.0.x introduces new dependency types post-release, a parser update will be needed

**Neutral**:
- `%generate_buildrequires` is intentionally out of scope (runtime deps only, not dynamic build deps)

---

## References

### RPM 4.20.x (Current -- Normative)

- [Spec File Format](https://rpm.org/docs/4.20.x/manual/spec.html) -- full preamble tags, dependency syntax, sections
- [Dependencies Basics](https://rpm.org/docs/4.20.x/manual/dependencies.html) -- Provides, Requires, Conflicts, Obsoletes, weak deps, versioning, `rpmvercmp()`
- [More on Dependencies](https://rpm.org/docs/4.20.x/manual/more_dependencies.html) -- boolean deps, arch-specific deps, scriptlet deps, auto-deps, interpreter modules
- [Boolean Dependencies](https://rpm.org/docs/4.20.x/manual/boolean_dependencies.html) -- operators, nesting rules, semantics
- [Architecture Dependencies](https://rpm.org/docs/4.20.x/manual/arch_dependencies.html) -- `%{?_isa}` suffix
- [Installation Order](https://rpm.org/docs/4.20.x/manual/tsort.html) -- transaction ordering from deps
- [Automatic Dependency Generation](https://rpm.org/docs/4.20.x/manual/dependency_generators.html) -- file attributes, generators

### RPM 6.0.x (Future -- Forward Reference)

- [Spec File Format](https://rpm.org/docs/6.0.x/manual/spec.html) -- same structure, editorial fixes, `%caps` addition
- [Dependencies Basics](https://rpm.org/docs/6.0.x/manual/dependencies.html) -- identical to 4.20.x
- [More on Dependencies](https://rpm.org/docs/6.0.x/manual/more_dependencies.html) -- identical to 4.20.x
- [Boolean Dependencies](https://rpm.org/docs/6.0.x/manual/boolean_dependencies.html) -- identical to 4.20.x
