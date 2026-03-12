# ADR-0001: C11 as Implementation Language

**Date**: 2026-03-12
**Status**: Accepted

## Context

The upstream-source-code-dependency-scanner must parse RPM spec files, analyze Go modules and Python projects, build a dependency graph with potentially 10,000+ edges across 7 Photon branches, detect conflicts, and generate patched spec files. The implementation language choice directly impacts performance, memory control, deployment complexity, and integration with the Photon OS native toolchain.

Photon OS is a minimal Linux distribution optimized for cloud and container workloads. Its native build toolchain is GCC with glibc, and the `json-c` library is available as a first-class system package (`json-c-devel`). The scanner runs both as a CLI tool on developer workstations and within GitHub Actions CI pipelines, where it must complete a full 7-branch scan within a 120-minute timeout.

## Decision Drivers

- **Performance**: Must process 10,000+ dependency edges efficiently; full 7-branch scans within 120 minutes
- **Memory control**: Graph structures with thousands of nodes and edges require predictable memory layout
- **Deployment simplicity**: Should produce a single static binary with no runtime dependencies beyond libc and json-c
- **Photon OS native toolchain**: Should build with the standard Photon OS GCC/cmake toolchain without additional package installation
- **Security**: Implementation must support hardened patterns (no shell injection, bounded buffers, overflow guards)

## Considered Options

### Option 1: C11 with json-c

Implement in C11 using the `json-c` library for JSON output and the POSIX API for filesystem operations and subprocess management.

**Pros**:
- Maximum performance: zero-overhead abstractions, direct memory layout control
- Single binary deployment with no interpreter or runtime required
- `json-c-devel` is a native Photon OS package (`tdnf install json-c-devel`)
- Full control over subprocess execution (`fork()/execlp()`) for security hardening
- Builds with standard `gcc` and `cmake` already on Photon OS
- Predictable memory usage: fixed-size structs with `MAX_*_LEN` bounds

**Cons**:
- Higher development effort: manual memory management, no garbage collection
- Must implement bounds-checking manually (no built-in buffer overflow protection)
- String handling requires careful use of `snprintf`/`strncpy` throughout
- Smaller developer pool familiar with secure C coding practices

### Option 2: Python 3 with standard library

Implement in Python using the standard library (`json`, `os`, `subprocess`, `re`, `tarfile`).

**Pros**:
- Rapid development: high-level string processing, native JSON support
- Large ecosystem of parsing libraries (e.g., `rpm-python` for spec parsing)
- Easier to maintain and extend
- Built-in memory safety (no buffer overflows)

**Cons**:
- Significantly slower for graph operations on 10,000+ edges (50-100x slower than C for tight loops)
- Python interpreter required at runtime (adds ~50MB to deployment)
- `subprocess.run(shell=True)` is the default pattern -- easy to introduce injection
- GIL limits parallelism for CPU-bound graph analysis
- Photon OS minimal images may not include Python by default

### Option 3: Go with standard library

Implement in Go using the standard library (`encoding/json`, `os`, `os/exec`, `regexp`, `archive/tar`).

**Pros**:
- Good performance (10-20x slower than C, but acceptable for most workloads)
- Built-in memory safety, goroutines for parallelism
- Single static binary deployment
- Strong standard library for JSON, HTTP, and archive handling

**Cons**:
- Go toolchain is not part of the Photon OS base image (requires `tdnf install go`)
- Binary size is larger (~10-20MB vs ~100KB for C)
- Less control over memory layout for graph structures
- Go's `os/exec` is safe by default but less flexible than `fork()/execlp()`
- Circular dependency: the scanner analyzes Go packages but would itself be a Go package

## Decision Outcome

**Chosen**: Option 1 -- C11 with json-c.

The scanner operates on performance-critical data structures (dependency graphs with 10,000+ edges) and must complete within CI timeout constraints across 7 branches. C11 provides the necessary performance, memory control, and direct POSIX API access for security-hardened subprocess execution.

The fixed-size struct approach (`MAX_NAME_LEN = 256`, `MAX_PATH_LEN = 512`, etc.) in `graph.h` provides predictable memory usage without dynamic string allocation complexity. The `json-c` library provides JSON output with minimal overhead and is a native Photon OS package.

## Consequences

### Positive

- Graph operations on 10,000+ edges complete in milliseconds
- Single binary (~100KB) with no runtime dependencies beyond libc and json-c
- `fork()/execlp()` provides injection-proof subprocess execution by design
- Builds on Photon OS with only `gcc`, `cmake`, and `json-c-devel` (all standard packages)
- Fixed-size buffers prevent unbounded memory growth

### Negative

- Higher development effort for secure string handling
- Must manually implement bounds checking throughout the codebase
- Memory leaks require careful `graph_free()` implementation
- Developer must be proficient in secure C coding practices
- No built-in regex library (must use POSIX `regex.h` or simple string matching)

## References

- PRD: `specs/prd.md` -- Constraints: "Language: C11 with json-c"
- `src/graph.h` -- Buffer size constants and data structures
- `CMakeLists.txt` -- Build configuration
- REQ-7: Security Hardening requirements
