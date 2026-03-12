# Feature Requirement Document: Security Hardening

**Feature ID**: FRD-security
**Related PRD Requirements**: REQ-7
**Status**: Implemented
**Last Updated**: 2026-03-12

---

## 1. Feature Overview

### Purpose

Harden all external input handling and process execution in the scanner against injection, traversal, and resource exhaustion attacks. The scanner processes untrusted inputs (spec files, tarballs, upstream source code) and invokes external tools (git, tar), making it a target for supply-chain attacks if not properly hardened.

### Value Proposition

The scanner runs in CI pipelines with access to branch repositories and source archives. A compromised tarball or malicious spec file could exploit shell injection, path traversal, or TOCTOU race conditions to gain unauthorized access. Security hardening prevents these attack vectors at the implementation level.

### Success Criteria

- Zero `system()` calls in the entire codebase -- all external process execution uses `fork()/execlp()`
- All temporary files created with `mkstemp()` -- no predictable file paths
- Path traversal validation on all user-supplied directory and file names
- Integer overflow guards on all `realloc()` operations for graph arrays
- Bounds-checked buffer operations throughout (no unbounded `strcpy`, `strcat`, `sprintf`)

---

## 2. Functional Requirements

### 2.1 Process Execution: fork()/execlp() Instead of system()

**Description**: All external command execution must use `fork()/execlp()` to avoid shell injection vulnerabilities inherent in `system()`.

**Reference**: [OWASP A03:2021 -- Injection](https://owasp.org/Top10/A03_2021-Injection/), [CWE-78: Improper Neutralization of Special Elements used in an OS Command](https://cwe.mitre.org/data/definitions/78.html)

**Affected components**:
- `gomod_analyzer.c`: `_git_show_to_file()` uses `fork()/execlp("git", ...)`
- `tarball_analyzer.c`: `tarball_extract_file()` uses `fork()/execlp("tar", ...)`

**Pattern**:
```c
pid_t pid = fork();
if (pid == 0) {
    /* child */
    execlp("git", "git", "-C", pszCloneDir, "show", szRefArg, NULL);
    _exit(127);
}
/* parent: waitpid(pid, ...) */
```

**Acceptance Criteria**:
- No `system()`, `popen()`, or `exec*p()` with shell string anywhere in the codebase
- All `execlp()` calls pass arguments as discrete parameters, never as concatenated shell strings
- Child processes redirect stderr to `/dev/null` when output is not needed
- Parent always calls `waitpid()` and checks exit status
- `_exit(127)` used in child (not `exit()`) to avoid flushing parent's stdio buffers

### 2.2 Temporary File Safety: mkstemp()

**Description**: All temporary files must be created with `mkstemp()` to prevent predictable file paths and TOCTOU race conditions.

**Reference**: [CWE-377: Insecure Temporary File](https://cwe.mitre.org/data/definitions/377.html)

**Affected components**:
- `gomod_analyzer.c`: `mkstemp("/tmp/gomod-XXXXXX")`
- `tarball_analyzer.c`: `mkstemp("/tmp/tarball-extract-XXXXXX")`

**Acceptance Criteria**:
- No `tmpnam()`, `tempnam()`, `mktemp()`, or hardcoded temp file paths
- Template string includes at least 6 `X` characters
- File descriptor from `mkstemp()` is closed or used directly (no reopen by name)
- Temp files are always `unlink()`ed after use, even on error paths
- No temp file persists after the scanner exits

### 2.3 Path Traversal Validation

**Description**: All user-supplied paths (branch names, output directories, file names from tarballs) must be validated to prevent directory traversal attacks.

**Reference**: [OWASP A01:2021 -- Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/), [CWE-22: Improper Limitation of a Pathname to a Restricted Directory](https://cwe.mitre.org/data/definitions/22.html)

**Validation rules**:
- Branch name must not contain `..` (checked in `main.c`)
- Output directory must not contain `..` (checked in `main.c`)
- File paths extracted from tarballs must not contain `..` components
- Package names used in path construction must not contain `/` or `..`

**Acceptance Criteria**:
- `--branch "../../etc/passwd"` is rejected with an error message
- `--output-dir "../../../tmp/evil"` is rejected
- Tarball entries containing `../` path components are skipped during extraction
- Scanner exits with non-zero status on path traversal attempts

### 2.4 Integer Overflow Guards

**Description**: Dynamic array growth (`realloc`) for graph nodes, edges, and virtual provides must guard against integer overflow that could lead to undersized allocations and buffer overflows.

**Reference**: [CWE-190: Integer Overflow or Wraparound](https://cwe.mitre.org/data/definitions/190.html)

**Guard pattern**:
```c
if (pGraph->dwNodeCount >= pGraph->dwNodeCap) {
    uint32_t dwNewCap = pGraph->dwNodeCap * 2;
    if (dwNewCap < pGraph->dwNodeCap) {  /* overflow check */
        return -1;
    }
    if (dwNewCap > UINT32_MAX / sizeof(GraphNode)) {  /* allocation size overflow */
        return -1;
    }
    GraphNode *pNew = realloc(pGraph->pNodes, dwNewCap * sizeof(GraphNode));
    if (!pNew) return -1;
    ...
}
```

**Acceptance Criteria**:
- All `realloc` operations in `graph.c` check for capacity overflow before multiplication
- Allocation size (`count * sizeof(element)`) is checked for overflow
- `realloc` failure (returns NULL) is handled gracefully (no use-after-free)
- Initial capacities (`INITIAL_NODE_CAP = 2048`, `INITIAL_EDGE_CAP = 16384`) are reasonable defaults

### 2.5 Bounds-Checked Buffer Operations

**Description**: All string operations use bounds-checked variants to prevent buffer overflows.

**Rules**:
- Use `snprintf()` instead of `sprintf()`
- Use `strncpy()` + explicit null-termination instead of `strcpy()`
- All fixed-size buffers use `#define` constants from `graph.h` (`MAX_NAME_LEN`, `MAX_PATH_LEN`, etc.)
- `MAX_LINE_LEN = 4096` for line-reading buffers

**Acceptance Criteria**:
- No unbounded `strcpy()`, `strcat()`, `sprintf()` in the codebase
- All `snprintf()` calls pass the buffer size parameter
- String truncation is preferred over buffer overflow
- `fgets()` with explicit size parameter for line reading

---

## 3. Security Reference Matrix

| Threat | OWASP | CWE | Mitigation | Component |
|--------|-------|-----|------------|-----------|
| Shell injection via tarball names | A03:Injection | CWE-78 | `fork()/execlp()` | tarball_analyzer.c, gomod_analyzer.c |
| Predictable temp file paths | -- | CWE-377 | `mkstemp()` | gomod_analyzer.c, tarball_analyzer.c |
| Directory traversal via branch name | A01:Broken Access Control | CWE-22 | `strstr(pszBranch, "..")` check | main.c |
| Integer overflow on realloc | -- | CWE-190 | Overflow check before multiplication | graph.c |
| Buffer overflow on long paths | -- | CWE-120 | `snprintf()`, `MAX_*_LEN` constants | All source files |
| TOCTOU on temp files | -- | CWE-367 | `mkstemp()` (atomic create+open) | gomod_analyzer.c |

---

## 4. Edge Cases

- **Malicious tarball filenames**: A tarball entry named `../../../../etc/cron.d/backdoor` is blocked by path traversal validation during tar listing parse.
- **Very long package names**: Names exceeding `MAX_NAME_LEN` (256) are truncated by `snprintf()`, not overflowed.
- **Concurrent scanner instances**: `mkstemp()` ensures unique temp files even when multiple scanner instances run in parallel.
- **Fork failure**: `fork()` returning `-1` (out of process slots) causes the specific analysis step to be skipped; scanning continues.
- **Execlp failure**: If `git` or `tar` is not installed, `execlp()` fails and the child `_exit(127)`s; parent detects non-zero exit and skips the package.
- **realloc returning NULL**: On memory exhaustion, the graph operation fails gracefully without corrupting existing data.

---

## 5. Dependencies

**Depends On**: None (security patterns are cross-cutting)

**Depended On By**: FRD-gomod-analysis (uses fork/execlp, mkstemp), FRD-tarball-analysis (uses fork/execlp, mkstemp), all features that construct file paths
