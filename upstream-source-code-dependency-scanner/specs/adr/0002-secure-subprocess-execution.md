# ADR-0002: Secure Subprocess Execution via fork/execlp

**Date**: 2026-03-12
**Status**: Accepted

## Context

The upstream-source-code-dependency-scanner must invoke external programs to extract source tarballs (`.tar.gz`) for Go module analysis. Tarball file paths are derived from user-supplied input (package names and versions from spec files), creating a potential OS command injection vector if shell interpolation is used.

The scanner processes tarballs from multiple sources:
- `photon_sources/1.0/` -- current release source tarballs
- `SOURCES_NEW/` -- latest version source tarballs

File names follow patterns like `{package}-{version}.tar.gz` where both package name and version come from RPM spec parsing. A malicious or malformed spec file could inject shell metacharacters (`;`, `|`, `` ` ``, `$()`) into these values if they reach a shell interpreter.

## Decision Drivers

- **CWE-78**: Prevent OS Command Injection -- the #1 concern for C programs that invoke external tools
- **OWASP A03:2021 Injection**: Industry standard requires elimination of injection vectors
- **Defense in depth**: Even if input validation catches most cases, the execution mechanism must be inherently safe
- **Auditability**: Security reviewers must be able to verify the absence of injection with high confidence
- **Performance**: Subprocess execution must not add unnecessary overhead

## Considered Options

### Option 1: fork()/execlp() with explicit arguments

Use the POSIX `fork()` + `execlp()` pattern where each argument is passed as a separate C string, bypassing the shell entirely.

```c
pid_t pid = fork();
if (pid == 0) {
    execlp("tar", "tar", "-xzf", pszTarballPath, "-C", pszTempDir, NULL);
    _exit(127);
}
waitpid(pid, &status, 0);
```

**Pros**:
- **Injection-proof by construction**: No shell is invoked; arguments are passed directly to `execve()` via the kernel
- Shell metacharacters (`;`, `|`, `` ` ``, `$()`) have no special meaning
- Full control over the child process (signal handling, resource limits, environment)
- Auditors can verify safety by confirming no `system()`/`popen()` calls exist

**Cons**:
- More verbose code (fork, exec, waitpid boilerplate)
- Must handle fork failure, exec failure, and child signal delivery manually
- Cannot use shell features (globbing, piping) -- must do these programmatically

### Option 2: system() with input sanitization

Use `system()` with careful sanitization of all input strings before interpolation into the command.

```c
/* Sanitize, then: */
char cmd[1024];
snprintf(cmd, sizeof(cmd), "tar -xzf '%s' -C '%s'", pszSanitized, pszTempDir);
system(cmd);
```

**Pros**:
- Less code: single function call
- Can use shell features (globbing, piping, redirection) if needed
- Familiar pattern for developers

**Cons**:
- **Fundamentally unsafe**: Even with sanitization, edge cases exist (e.g., filenames with single quotes)
- Sanitization is a deny-list approach -- must anticipate every dangerous character
- CWE-78 explicitly warns against this pattern
- Shell interpretation adds overhead and unpredictability
- Code reviewers must verify sanitization logic is complete (difficult to prove)

### Option 3: posix_spawn() with explicit arguments

Use `posix_spawn()` which provides a higher-level API than fork/exec but still bypasses the shell.

```c
posix_spawn_file_actions_t actions;
posix_spawn_file_actions_init(&actions);
char *argv[] = {"tar", "-xzf", pszTarballPath, "-C", pszTempDir, NULL};
posix_spawn(&pid, "/usr/bin/tar", &actions, NULL, argv, environ);
```

**Pros**:
- Injection-proof (no shell involved)
- Slightly more concise than fork/exec
- Handles file descriptor inheritance more cleanly

**Cons**:
- Less portable across older systems
- Less flexible than fork/exec for complex child setup
- Still requires manual waitpid and error handling
- Less familiar to many C developers than the fork/exec pattern

## Decision Outcome

**Chosen**: Option 1 -- `fork()/execlp()` with explicit arguments.

This approach is injection-proof by construction. The kernel's `execve()` syscall takes an argument vector, not a shell command string. Shell metacharacters have no special meaning because no shell is involved. This eliminates CWE-78 at the architectural level rather than relying on input sanitization.

The additional boilerplate code is a worthwhile tradeoff for provable security. Code reviewers can verify the absence of injection by a simple search: if `system()` and `popen()` appear nowhere in the codebase, command injection is structurally impossible.

## Consequences

### Positive

- CWE-78 (OS Command Injection) is eliminated by design, not by sanitization
- OWASP A03:2021 Injection is fully addressed for subprocess execution
- Security audit is simplified: absence of `system()`/`popen()` is easy to verify
- No dependency on shell behavior or availability (works in minimal containers)
- Child process inherits only explicitly configured environment

### Negative

- More verbose subprocess code (~15 lines vs. 2 for `system()`)
- Cannot use shell features (piping, redirection, globbing) without implementing them
- Must handle `EINTR` on `waitpid()` and `ENOMEM` on `fork()` explicitly
- Developer must understand POSIX process model (fork semantics, exec variants)

## References

- CWE-78: Improper Neutralization of Special Elements used in an OS Command -- https://cwe.mitre.org/data/definitions/78.html
- OWASP A03:2021 Injection -- https://owasp.org/Top10/A03_2021-Injection/
- NIST 800-53 SI-10: Information Input Validation
- PRD: `specs/prd.md` -- REQ-7: "No system() or shell interpolation"
- `src/tarball_analyzer.c` -- Tarball extraction implementation
