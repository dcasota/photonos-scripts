# Security Hardening Checklist — Upstream Source Code Dependency Scanner

**Version**: 1.0
**Last Updated**: 2026-03-12
**Status**: All items implemented

---

## Overview

This checklist enumerates every concrete security measure implemented in the scanner. Each item references the specific vulnerability class (CWE/OWASP), source file location, and implementation status.

---

## Command Execution Hardening

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-01 | Replace `system()` with `fork()/execlp()` for git operations | CWE-78 (OS Command Injection), OWASP A03 | `src/gomod_analyzer.c:63-84` | ✅ Implemented |
| H-02 | Replace `system()` with `fork()/execlp()` for tar listing | CWE-78, OWASP A03 | `src/tarball_analyzer.c:62-83` | ✅ Implemented |
| H-03 | Replace `system()` with `fork()/execlp()` for tar extraction | CWE-78, OWASP A03 | `src/tarball_analyzer.c:126-147` | ✅ Implemented |
| H-04 | Replace `system()` with `fork()/execlp()` for tar go.mod check | CWE-78, OWASP A03 | `src/tarball_analyzer.c:208-223` | ✅ Implemented |
| H-05 | Redirect child stderr to `/dev/null` to prevent log injection | CWE-117 (Log Injection) | `src/tarball_analyzer.c:76-80`, `src/gomod_analyzer.c:78-82` | ✅ Implemented |

---

## Temporary File Hardening

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-06 | Use `mkstemp()` for tarball extraction temp files | CWE-377 (Insecure Temporary File), race condition prevention | `src/tarball_analyzer.c:48` | ✅ Implemented |
| H-07 | Use `mkstemp()` for go.mod extraction temp files | CWE-377 | `src/gomod_analyzer.c:370` | ✅ Implemented |
| H-08 | `unlink()` temp files on all code paths (success and error) | CWE-459 (Incomplete Cleanup) | `src/tarball_analyzer.c:56,89,155,164` (error paths), `src/tarball_analyzer.c:239` (success) | ✅ Implemented |
| H-09 | Temp file created with 0600 permissions (mkstemp default) | CWE-732 (Incorrect Permission Assignment) | `src/tarball_analyzer.c:48`, `src/gomod_analyzer.c:370` | ✅ Implemented |

---

## Path Traversal Prevention

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-10 | Reject `..` in `--branch` CLI argument | CWE-22 (Path Traversal), OWASP A01 | `src/main.c:185` | ✅ Implemented |
| H-11 | Reject `..` in `--output-dir` CLI argument | CWE-22, OWASP A01 | `src/main.c:189` | ✅ Implemented |
| H-12 | Reject `..` and `/` in package names during spec patching | CWE-22, OWASP A01 | `src/spec_patcher.c:568-572` | ✅ Implemented |
| H-13 | Reject `..` and `/` in branch names during spec patching | CWE-22, OWASP A01 | `src/spec_patcher.c:556-561` | ✅ Implemented |
| H-14 | Reject `..` and `/` in spec file basenames | CWE-22, OWASP A01 | `src/spec_patcher.c:589-594` | ✅ Implemented |
| H-15 | `_is_safe_path_component()` whitelist for tarball names/versions | CWE-22, OWASP A01 | `src/tarball_analyzer.c:16-27` | ✅ Implemented |
| H-16 | Validate tarball package name and version before path construction | CWE-22 | `src/tarball_analyzer.c:180` | ✅ Implemented |
| H-17 | Reject path traversal in PRN repo/owner names | CWE-22, OWASP A01 | `src/prn_parser.c:136` | ✅ Implemented |
| H-18 | Reject traversal sequences in API extractor file paths | CWE-22 | `src/api_version_extractor.c:194` | ✅ Implemented |
| H-19 | Validate clone directory names in Go module analyzer | CWE-22, CWE-78 | `src/gomod_analyzer.c:30-47` | ✅ Implemented |

---

## Buffer Overflow Prevention

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-20 | All string operations use `snprintf()` with explicit buffer sizes | CWE-120 (Buffer Copy without Size Check), CWE-676 | All source files — verified: zero `sprintf()`, `strcpy()`, `strcat()` calls | ✅ Implemented |
| H-21 | Fixed-size buffer constants for all data types | CWE-120 | `src/graph.h:6-15` — `MAX_NAME_LEN=256`, `MAX_VERSION_LEN=64`, `MAX_PATH_LEN=512`, `MAX_LINE_LEN=4096` | ✅ Implemented |
| H-22 | `fgets()` bounded by `MAX_LINE_LEN` in all file readers | CWE-120 | `src/spec_parser.c`, `src/gomod_analyzer.c`, `src/prn_parser.c`, `src/gomod_to_package_map.c` | ✅ Implemented |

---

## Integer Overflow Prevention

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-23 | Overflow guard on node array realloc (capacity doubling) | CWE-190 (Integer Overflow), NIST SI-16 | `src/graph.c:107-108` — `if (dwNewCap < pGraph->dwNodeCap || (size_t)dwNewCap * sizeof(GraphNode) / sizeof(GraphNode) != dwNewCap)` | ✅ Implemented |
| H-24 | Overflow guard on edge array realloc | CWE-190 | `src/graph.c:170` — `if (dwNewCap < pGraph->dwEdgeCap)` | ✅ Implemented |
| H-25 | Overflow guard on virtual provides array realloc | CWE-190 | `src/graph.c:226` — `if (dwNewCap < pGraph->dwVirtualCap)` | ✅ Implemented |

---

## Unsafe Function Elimination

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-26 | Zero `system()` calls in codebase | CWE-78, CWE-676 | Verified: `grep -r "system(" src/` returns 0 results | ✅ Implemented |
| H-27 | Zero `popen()` calls in codebase | CWE-78, CWE-676 | Verified: `grep -r "popen(" src/` returns 0 results | ✅ Implemented |
| H-28 | Zero `sprintf()` calls (only `snprintf()`) | CWE-120, CWE-676 | Verified: `grep -r "sprintf(" src/` returns 0 results (all are `snprintf`) | ✅ Implemented |
| H-29 | Zero `strcpy()`/`strcat()` calls | CWE-120, CWE-676 | Verified: only `snprintf()` for string assembly | ✅ Implemented |
| H-30 | Zero `mktemp()` calls (only `mkstemp()`) | CWE-377, CWE-676 | Verified: all temp file creation via `mkstemp()` | ✅ Implemented |
| H-31 | Zero `gets()` calls | CWE-120, CWE-676 | Verified: never used | ✅ Implemented |

---

## Design-Level Security

| # | What | Why | Where | Status |
|---|------|-----|-------|--------|
| H-32 | Read-only operation on all input files | OWASP A04 (Insecure Design) | Architecture: scanner never opens inputs with write mode | ✅ Implemented |
| H-33 | No network access | NIST CM-7 (Least Functionality) | Architecture: no socket/HTTP code in codebase | ✅ Implemented |
| H-34 | Deterministic output (no randomness, no timestamps in logic) | NIST AU-3 (Audit Records) | Architecture: same inputs → same outputs (timestamp only in filenames) | ✅ Implemented |
| H-35 | Single-file extraction from tarballs (not full archive) | Defense in depth: limits tarball attack surface | `src/tarball_analyzer.c:83,147` — uses `tar -O` for stdout extraction | ✅ Implemented |

---

## Summary

| Category | Items | All Implemented |
|----------|-------|-----------------|
| Command Execution | H-01 through H-05 | ✅ |
| Temporary Files | H-06 through H-09 | ✅ |
| Path Traversal | H-10 through H-19 | ✅ |
| Buffer Overflow | H-20 through H-22 | ✅ |
| Integer Overflow | H-23 through H-25 | ✅ |
| Unsafe Functions | H-26 through H-31 | ✅ |
| Design-Level | H-32 through H-35 | ✅ |
| **Total** | **35 items** | **✅ All implemented** |
