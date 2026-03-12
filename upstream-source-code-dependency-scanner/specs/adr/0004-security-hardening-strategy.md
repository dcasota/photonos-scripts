# ADR-0004: Comprehensive Security Hardening Strategy

**Date**: 2026-03-12
**Status**: Accepted

## Context

The upstream-source-code-dependency-scanner processes untrusted input from multiple sources: RPM spec files, Go module files, Python project files, source tarballs, CSV data files, and command-line arguments. Each of these input vectors represents a potential attack surface. A compromised or malformed input could lead to command injection, buffer overflow, path traversal, or denial of service.

The scanner runs in two contexts:
1. **Developer workstations**: Direct CLI invocation with local filesystem access
2. **GitHub Actions CI**: Automated execution on shared runners processing potentially untrusted contributions

Both contexts require defense-in-depth security hardening that cannot rely on perimeter controls alone.

## Decision Drivers

- **CWE-22**: Path traversal through malicious package names or tarball contents
- **CWE-78**: OS command injection through shell metacharacters in file paths
- **CWE-120**: Buffer overflow through oversized input fields
- **CWE-190**: Integer overflow in graph capacity calculations
- **CWE-377**: Insecure temporary file creation enabling TOCTOU attacks
- **OWASP A01:2021**: Broken Access Control (unauthorized file access)
- **OWASP A03:2021**: Injection (command and format string injection)
- **OWASP A04:2021**: Insecure Design (missing security controls)
- **OWASP A06:2021**: Vulnerable and Outdated Components (json-c dependency)
- **NIST 800-53 SI-10**: Information Input Validation
- **NIST 800-53 SI-16**: Memory Protection
- **NIST 800-53 SC-18**: Mobile Code (subprocess execution)
- **NIST AI RMF**: Future considerations for ML-based dependency analysis

## Considered Options

### Option 1: Comprehensive defense-in-depth hardening

Apply multiple layers of security controls at every input boundary, every memory operation, and every subprocess invocation:

1. **Input validation at boundaries**: Reject `..` in all user-supplied paths, validate branch names, limit field lengths
2. **Injection-proof execution**: Use `fork()/execlp()` exclusively; ban `system()`/`popen()`
3. **Bounded buffers**: Fixed-size structs with `MAX_*_LEN` constants; all copies use `snprintf`/`strncpy`
4. **Integer overflow guards**: Check capacity calculations before `realloc()`
5. **Secure temp files**: Use `mkstemp()` exclusively; clean up in all code paths
6. **Minimal privileges**: Scanner never needs write access to SPECS/ or source directories

**Pros**: Every attack vector is addressed with a specific control. Multiple layers mean a single bypass does not compromise security.

**Cons**: Higher development complexity. Performance cost of validation at every boundary.

### Option 2: Input sanitization at entry points only

Sanitize all inputs once at the CLI argument parsing stage, then trust internal data throughout.

**Pros**: Simpler code in internal functions. Lower performance overhead.

**Cons**: Internal data corruption or logic errors bypass the single sanitization layer. Does not defend against bugs within the scanner itself.

### Option 3: Sandbox execution via seccomp/landlock

Run the scanner in a kernel-enforced sandbox that restricts filesystem access and syscalls.

**Pros**: Kernel-level enforcement is very strong. Even if the scanner has vulnerabilities, the sandbox limits impact.

**Cons**: Requires seccomp/landlock setup (complex, Linux-specific). May break legitimate operations. Does not prevent logic errors within the allowed syscall set.

## Decision Outcome

**Chosen**: Option 1 -- Comprehensive defense-in-depth hardening, with elements of Option 3 as a future enhancement.

Defense-in-depth provides the most complete protection by applying security controls at every layer. Each control addresses a specific CWE and maps to industry frameworks.

### Control Implementation Matrix

| Control | CWE | OWASP | NIST 800-53 | Implementation |
|---------|-----|-------|-------------|----------------|
| Path traversal rejection | CWE-22 | A01 | SI-10 | `strstr(path, "..")` check on all user-supplied paths in `main()` |
| fork()/execlp() only | CWE-78 | A03 | SI-10, SC-18 | Ban `system()`/`popen()`; tarball extraction via fork/exec |
| Bounded buffer copies | CWE-120 | A03 | SI-16 | `MAX_*_LEN` constants in `graph.h`; `snprintf()` everywhere |
| Integer overflow guards | CWE-190 | A04 | SI-16 | Check `newCap < oldCap` before `realloc()` in graph growth |
| mkstemp() temp files | CWE-377 | A04 | SC-18 | All temp files via `mkstemp()`; cleanup in all code paths |
| Format string safety | CWE-134 | A03 | SI-10 | No user data as format strings; always use explicit format |
| Return value checking | CWE-252 | A04 | SI-10 | All `malloc`/`fopen`/`stat` return values checked |
| NULL pointer guards | CWE-476 | A04 | SI-16 | All pointer parameters validated at function entry |

### NIST AI RMF Considerations

For potential future ML-based dependency analysis features:

| RMF Function | Control | Application |
|--------------|---------|-------------|
| GOVERN 1.1 | Legal/regulatory compliance | Ensure ML models do not introduce licensing conflicts in dependency suggestions |
| MAP 1.5 | Risk identification | Identify risks of hallucinated dependencies (false positives from ML prediction) |
| MEASURE 2.6 | Verification | All ML-suggested dependencies must pass the same validation as rule-based findings |
| MANAGE 2.4 | Risk tracking | Monitor ML model drift and false positive rates over scanner releases |

**Decision**: ML-based features, if added, must produce output in the same `SpecPatch` format and undergo the same deduplication and validation pipeline. No ML output bypasses the conflict-detector's quality rubric.

## Consequences

### Positive

- CWE-22 (path traversal) eliminated by input validation at all entry points
- CWE-78 (command injection) eliminated by architectural decision (no shell invocation)
- CWE-120 (buffer overflow) mitigated by fixed-size buffers and bounded copies
- CWE-190 (integer overflow) mitigated by overflow checks before realloc
- CWE-377 (insecure temp files) eliminated by mkstemp() usage
- OWASP A01, A03, A04, A06 addressed with specific controls
- NIST 800-53 SI-10, SI-16, SC-18 controls implemented
- Security audit (via security-auditor agent) can verify controls by checking for absence of banned patterns
- Future ML features have a clear security integration path

### Negative

- Higher development effort for every new function (must add validation boilerplate)
- Fixed-size buffers waste memory for short strings (e.g., `MAX_NAME_LEN = 256` for a 10-char name)
- Overflow checks add marginal CPU overhead to graph growth operations
- mkstemp() cleanup requires careful error handling (must clean up in all return paths)
- Developers must maintain the security control matrix as new features are added

## References

- CWE-22: Path Traversal -- https://cwe.mitre.org/data/definitions/22.html
- CWE-78: OS Command Injection -- https://cwe.mitre.org/data/definitions/78.html
- CWE-120: Buffer Copy without Checking Size -- https://cwe.mitre.org/data/definitions/120.html
- CWE-190: Integer Overflow -- https://cwe.mitre.org/data/definitions/190.html
- CWE-377: Insecure Temporary File -- https://cwe.mitre.org/data/definitions/377.html
- OWASP Top 10 (2021) -- https://owasp.org/Top10/
- NIST SP 800-53 Rev. 5 -- https://csrc.nist.gov/pubs/sp/800-53/r5/upd1/final
- NIST AI RMF 1.0 -- https://www.nist.gov/artificial-intelligence/risk-management-framework
- PRD: `specs/prd.md` -- REQ-7: Security Hardening
- ADR-0002: `specs/adr/0002-secure-subprocess-execution.md`
- `src/graph.h` -- Buffer size constants
- `src/main.c` -- Path traversal validation in argument parsing
