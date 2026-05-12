# ADR-0008: Photon-only build target

**Status**: Accepted
**Date**: 2026-05-12

## Context

The script today only runs on the self-hosted Photon runner. Downstream consumers also live on Photon. A multi-platform port (Debian/Ubuntu/RHEL/macOS) would force portability shims around `tdnf install`, locale defaults, file-system case-sensitivity, and PCRE2 ABI differences across distros.

## Decision

**Photon 5 and 6 only.** Build instructions, CI, and dependency installation use `tdnf` and assume the Photon-specific RPMs (`libcurl-devel`, `pcre2-devel`, `json-c-devel`, `pthread`, `libarchive-devel`).

## Rationale

- Bit-identical parity is the priority (ADR-0006). Different libc versions (musl, alpine, glibc 2.31 vs 2.39) can flip `strverscmp` or `qsort` stability.
- The runner is Photon; the consumers are Photon; the script's institutional knowledge about Photon SPEC layout is wired into ~200 hooks. Nothing else exists.
- A future cross-platform port can happen after retirement once parity has been proven; that's a separate ADR.

## Consequences

- `CMakeLists.txt` invokes `find_package(PkgConfig REQUIRED)` and `pkg_check_modules(...)` against Photon-RPM packages.
- No `#ifdef __linux__` / `__FreeBSD__` blocks; we target one OS family.
- CI runs only on the self-hosted Photon runner; no cross-OS test matrix in v1.
- Documentation says "Photon 5+" in README.

## Considered alternatives

- **Multi-distro Linux**: deferred. Documented as an out-of-scope item in PRD §2.
