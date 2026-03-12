# Task 007: Security Hardening — All 10 CVE-Class Fixes

**Complexity**: High
**Dependencies**: 001-006
**Status**: Complete
**Requirement**: REQ-7 (Security Hardening)
**Feature**: FRD-security
**ADR**: ADR-0004

---

## Description

Implement comprehensive security hardening across all scanner modules to eliminate 10 classes of vulnerabilities. Every external input path (spec files, go.mod, tarballs, PRN files, CSV data, CLI arguments) is hardened.

### CVE-Class Fixes

| # | Vulnerability Class | CWE | Fix | Location |
|---|---------------------|-----|-----|----------|
| 1 | Command injection via `system()` | CWE-78 | Replace with `fork()/execlp()` | `gomod_analyzer.c:63`, `tarball_analyzer.c:62,126` |
| 2 | Predictable temp file names | CWE-377 | Use `mkstemp()` instead of `mktemp()`/hardcoded paths | `gomod_analyzer.c:370`, `tarball_analyzer.c:48` |
| 3 | Path traversal in branch names | CWE-22 | Reject `..` in `--branch` and `--output-dir` | `main.c:183-190` |
| 4 | Path traversal in package names | CWE-22 | Reject `..` and `/` in package names during patching | `spec_patcher.c:556-589` |
| 5 | Path traversal in tarball paths | CWE-22 | `_is_safe_path_component()` validation | `tarball_analyzer.c:16-27,180` |
| 6 | Path traversal in PRN entries | CWE-22 | Reject `..` in repo/owner names | `prn_parser.c:136` |
| 7 | Path traversal in API extractor | CWE-22 | Reject traversal sequences in file paths | `api_version_extractor.c:194` |
| 8 | Integer overflow on realloc | CWE-190 | Overflow check: `dwNewCap < pGraph->dwNodeCap` | `graph.c:107-108` |
| 9 | Buffer overflow via unchecked strings | CWE-120 | Use `snprintf()` everywhere, bounded `MAX_*_LEN` constants | All source files |
| 10 | Unsafe `fread`/`fgets` bounds | CWE-120 | All reads use `MAX_LINE_LEN` bounds | `spec_parser.c`, `gomod_analyzer.c`, `prn_parser.c` |

## Implementation Details

### Fix 1: system() → fork()/execlp()

```c
// BEFORE (vulnerable):
// char cmd[1024]; sprintf(cmd, "git -C %s show ...", dir); system(cmd);

// AFTER (hardened):
pid_t pid = fork();
if (pid == 0) {
    execlp("git", "git", "-C", pszCloneDir, "show", szRefArg, NULL);
    _exit(127);
}
waitpid(pid, &status, 0);
```

### Fix 2: mkstemp() for temp files

```c
// mkstemp() creates file with 0600 permissions, returns fd
snprintf(szTmpPath, sizeof(szTmpPath), "/tmp/tarball-extract-XXXXXX");
int nFd = mkstemp(szTmpPath);
// ... use file ...
unlink(szTmpPath);  // always clean up
```

### Fix 8: Integer overflow guard

```c
uint32_t dwNewCap = pGraph->dwNodeCap * 2;
if (dwNewCap < pGraph->dwNodeCap ||  // overflow check
    (size_t)dwNewCap * sizeof(GraphNode) / sizeof(GraphNode) != dwNewCap)
{
    return (uint32_t)-1;  // refuse to allocate
}
```

## Acceptance Criteria

- [ ] Zero calls to `system()`, `popen()`, `mktemp()` in entire codebase
- [ ] All external process execution uses `fork()/execlp()` with explicit argument lists
- [ ] All temp files created with `mkstemp()` and cleaned up in all code paths
- [ ] Path traversal rejected in all user-supplied inputs: branch, output-dir, package names, PRN entries, spec paths
- [ ] Integer overflow detected before `realloc()` in `graph_add_node()`, `graph_add_edge()`, `graph_add_virtual()`
- [ ] All string operations use `snprintf()` with bounded buffers (no `sprintf()`, `strcat()`, `strcpy()`)
- [ ] All `fgets()`/`fread()` calls use `MAX_LINE_LEN` or equivalent bounds

## Testing Requirements

- [ ] Attempt `--branch "../../../etc"` — verify rejection
- [ ] Attempt tarball with `name="../../../etc/passwd"` — verify `_is_safe_path_component()` rejects
- [ ] Verify no `system()` calls: `grep -r "system(" src/` returns zero results
- [ ] Verify no `sprintf()` calls: `grep -r "sprintf(" src/` returns zero results (only `snprintf`)
- [ ] Run with extremely large spec set — verify no integer overflow crash
- [ ] Verify temp file cleanup: `ls /tmp/tarball-extract-*` empty after scan
- [ ] Run under AddressSanitizer (`-fsanitize=address`) — zero findings
