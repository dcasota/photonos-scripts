---
agent: security-auditor
---

# Audit Scanner Security

## Mission

Perform a comprehensive security audit of the upstream-source-code-dependency-scanner C codebase. Map all findings to MITRE CWE, OWASP Top 10, NIST 800-53, and NIST AI RMF frameworks. Produce a structured audit report.

## Step-by-Step Workflow

### 1. Enumerate the attack surface

**Read and catalog all source files:**

- `src/*.c` -- all implementation files
- `src/*.h` -- all header files (especially `graph.h` for buffer size constants)
- `CMakeLists.txt` -- build configuration and compiler flags
- `data/*.csv` -- input data files (assess parsing security)
- `tests/` -- test coverage assessment

### 2. Analyze command injection vectors (MITRE ATT&CK T1059, CWE-78)

Check for OS command injection:

- Search for `system()` calls -- flag as CRITICAL if found
- Search for `popen()` calls -- flag as HIGH if user input reaches them
- Verify `fork()/execlp()` is used for all subprocess execution (tarball extraction)
- Verify arguments to `execlp()` are not constructed from user input via string concatenation
- Check all string formatting that constructs file paths or commands

**OWASP**: A03:2021 Injection
**NIST 800-53**: SI-10 (Information Input Validation)

### 3. Analyze path traversal vectors (CWE-22)

Check for directory traversal:

- Verify `--branch` argument is validated (reject `..`)
- Verify `--output-dir` argument is validated (reject `..`)
- Verify all constructed file paths use bounded `snprintf` and reject `..` components
- Verify tarball extraction cannot write outside the extraction directory
- Check for symlink following in directory traversal

**OWASP**: A01:2021 Broken Access Control
**NIST 800-53**: SI-10 (Information Input Validation)

### 4. Analyze buffer overflow vectors (CWE-120)

Check for buffer overflows:

- Verify all string copies use bounded operations (`strncpy`, `snprintf`)
- Verify `MAX_*_LEN` constants in `graph.h` are consistently enforced
- Check for off-by-one errors in string termination
- Verify `fgets()` or similar bounded reads are used for file input
- Check for format string vulnerabilities (CWE-134)

**OWASP**: A03:2021 Injection
**NIST 800-53**: SI-16 (Memory Protection)

### 5. Analyze integer overflow vectors (CWE-190)

Check for integer overflows:

- Verify `realloc()` size calculations cannot overflow (especially `dwNodeCap * 2 * sizeof(GraphNode)`)
- Verify graph capacity doubling is checked: `if (newCap < oldCap) /* overflow */`
- Verify loop counters and array indices are bounds-checked
- Check for signed/unsigned comparison issues

**OWASP**: A04:2021 Insecure Design
**NIST 800-53**: SI-16 (Memory Protection)

### 6. Analyze temporary file security (CWE-377)

Check for insecure temp files:

- Verify `mkstemp()` is used (not `mktemp()` or `tmpnam()`)
- Verify temp files are created with restrictive permissions
- Verify temp directories are cleaned up after use
- Check for TOCTOU race conditions between check and use

**OWASP**: A04:2021 Insecure Design
**NIST 800-53**: SC-18 (Mobile Code)

### 7. Assess NIST AI RMF applicability

For any current or planned ML-based analysis features:

- **GOVERN 1.1**: Document legal and regulatory requirements for AI-based dependency analysis
- **MAP 1.5**: Identify risks if ML models are used for dependency prediction (hallucinated dependencies, missed critical deps)
- **MEASURE 2.6**: Define verification procedures for AI-generated dependency suggestions
- **MANAGE 2.4**: Track AI system risks over the scanner's lifecycle

### 8. Produce the audit report

Structure the report as:

1. **Executive Summary**: Total findings by severity
2. **Attack Surface Map**: Files analyzed, entry points, trust boundaries
3. **Findings Table**: Each row = (ID, Severity, CWE, OWASP, NIST 800-53, File, Line, Description, Remediation)
4. **Framework Compliance Matrix**: CWE → OWASP → NIST 800-53 → NIST AI RMF mapping
5. **Positive Controls**: Security measures already in place (hardening that works)
6. **Recommendations**: Prioritized remediation actions

## Quality Checklist

- [ ] All `.c` and `.h` files in `src/` were analyzed
- [ ] Every finding has file path and line number or function name
- [ ] Every finding is mapped to at least one CWE
- [ ] Every finding is mapped to an OWASP Top 10 (2021) category
- [ ] Every finding is mapped to a NIST 800-53 control
- [ ] NIST AI RMF considerations are addressed (even if "not applicable" is the finding)
- [ ] MITRE ATT&CK technique IDs are referenced for injection findings
- [ ] Severity uses CVSS 3.1 scale (Critical/High/Medium/Low/Info)
- [ ] No false positives -- every finding is a genuine concern
- [ ] Positive security controls are acknowledged (defense-in-depth already in place)
- [ ] Remediation recommendations are specific and actionable
- [ ] Report includes an executive summary with totals by severity
