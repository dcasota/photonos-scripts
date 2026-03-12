# Security Compliance Matrix — Upstream Source Code Dependency Scanner

**Version**: 1.0
**Last Updated**: 2026-03-12
**Status**: Complete

---

## 1. OWASP Top 10 2021 Mapping

| OWASP ID | Category | Scanner Relevance | Controls Implemented | Status |
|----------|----------|-------------------|---------------------|--------|
| **A01:2021** | Broken Access Control | Path traversal allows writing outside output directory | Path traversal validation on `--branch` (`main.c:185`), `--output-dir` (`main.c:189`), package names (`spec_patcher.c:556-589`), tarball components (`tarball_analyzer.c:16-27`), PRN entries (`prn_parser.c:136`), API extractor paths (`api_version_extractor.c:194`) | ✅ Implemented |
| **A03:2021** | Injection | Command injection via `system()` with untrusted filenames | All external process execution uses `fork()/execlp()` with explicit argument lists (`gomod_analyzer.c:63-84`, `tarball_analyzer.c:62-83,126-147`). Zero `system()` or `popen()` calls. | ✅ Implemented |
| **A04:2021** | Insecure Design | No threat model; no defense-in-depth | Comprehensive threat model (`specs/security/threat-model.md`), STRIDE analysis per input, defense-in-depth with multiple validation layers | ✅ Implemented |
| **A06:2021** | Vulnerable and Outdated Components | Dependency on `json-c` library | json-c is actively maintained; scanner uses latest stable release; no other external runtime dependencies | ✅ Implemented |
| **A08:2021** | Software and Data Integrity Failures | Modified CSV data files redirect dependency mapping | Data files version-controlled in git; scanner is deterministic (same inputs → same outputs) | ✅ Implemented |

---

## 2. MITRE CWE Mapping

| CWE ID | Name | Scanner Context | Mitigation | Source Location |
|--------|------|----------------|------------|-----------------|
| **CWE-22** | Improper Limitation of a Pathname to a Restricted Directory (Path Traversal) | Attacker-controlled paths in branch names, package names, tarball entries, PRN entries | `strstr(input, "..")` rejection; `_is_safe_path_component()` whitelist validation; `/` rejection in package names | `main.c:185,189`, `spec_patcher.c:556-589`, `tarball_analyzer.c:16-27,180`, `prn_parser.c:136`, `api_version_extractor.c:194` |
| **CWE-78** | Improper Neutralization of Special Elements used in an OS Command (OS Command Injection) | External commands (git, tar) executed with untrusted arguments | `fork()/execlp()` bypasses shell entirely; arguments passed as separate strings, never concatenated into a command string | `gomod_analyzer.c:63-84`, `tarball_analyzer.c:62-83,126-147,208-223` |
| **CWE-120** | Buffer Copy without Checking Size of Input (Classic Buffer Overflow) | Spec files, go.mod, CSV files may contain arbitrarily long lines | All buffers are fixed-size with `MAX_*_LEN` constants; all string operations use `snprintf()` with explicit size; `fgets()` bounded by `MAX_LINE_LEN` (4096) | All source files; key constants in `graph.h:6-15` |
| **CWE-190** | Integer Overflow or Wraparound | `realloc()` capacity doubling can overflow `uint32_t` | Overflow detection: `if (dwNewCap < pGraph->dwNodeCap)` catches wraparound; size multiplication overflow check via division verification | `graph.c:107-108,170,226` |
| **CWE-377** | Insecure Temporary File | Predictable temp file names enable symlink attacks (TOCTOU) | `mkstemp()` creates files with unique names and `0600` permissions atomically; all temp files `unlink()`ed after use | `gomod_analyzer.c:370`, `tarball_analyzer.c:48` |
| **CWE-676** | Use of Potentially Dangerous Function | `system()`, `sprintf()`, `strcpy()`, `strcat()`, `gets()`, `mktemp()` | None of these functions appear in the codebase; replaced with safe alternatives: `fork()/execlp()`, `snprintf()`, `mkstemp()` | Codebase-wide (verified by `grep`) |

---

## 3. NIST 800-53 Rev. 5 Mapping

| Control ID | Control Name | Family | Scanner Implementation | Evidence |
|-----------|-------------|--------|----------------------|----------|
| **SI-10** | Information Input Validation | System and Information Integrity | All 6 input types validated: spec files (bounded parsing), go.mod (bounded parsing), tarballs (safe path validation), PRN (traversal rejection), CSV (field validation), CLI (traversal rejection) | `main.c:183-190`, `tarball_analyzer.c:16-27`, `prn_parser.c:136`, `spec_parser.c` (bounded `fgets`) |
| **SI-16** | Memory Protection | System and Information Integrity | Fixed-size buffers prevent heap/stack corruption; integer overflow guards on dynamic allocation; `snprintf()` prevents buffer overruns | `graph.h` (MAX_* constants), `graph.c:107-108` (overflow check), all files (snprintf) |
| **SC-18** | Mobile Code | System and Communications Protection | No dynamic code execution; no `eval()`, `dlopen()`, or script interpretation; all logic is compiled C with fixed behavior | Architecture: compiled C binary, no plugins, no dynamic loading |
| **CM-7** | Least Functionality | Configuration Management | Scanner has minimal functionality: parse inputs, detect conflicts, write outputs. No network access, no file modification of inputs, no privilege escalation. Single-purpose design. | `main.c` (CLI has only 10 options), no socket/network code in entire codebase |
| **AU-3** | Content of Audit Records | Audit and Accountability | Every detected issue includes evidence trail: source file, module path, version, and analysis type | `manifest_writer.c` (evidence field in every addition), `conflict_detector.c` (ConflictRecord with full provenance) |
| **SA-15** | Development Process, Standards, and Tools | System and Services Acquisition | Secure coding standards: no unsafe functions, bounded buffers, defense-in-depth validation | This compliance matrix, `specs/security/hardening-checklist.md` |

---

## 4. NIST AI RMF 1.0 (Forward-Looking)

> **Note**: The current scanner does not use ML/AI. These mappings are forward-looking for potential future additions (e.g., ML-based dependency resolution, automated version compatibility prediction).

| Function | Category | Applicability | Future Consideration |
|----------|----------|---------------|---------------------|
| **MAP-1** | Context and Use Case | If ML analysis is added | Define ML model scope: which dependency decisions are ML-assisted vs. rule-based; document training data provenance |
| **MAP-3** | AI Actor Roles | If ML analysis is added | Designate human-in-the-loop for ML-suggested dependency changes; no auto-patching from ML output without review |
| **MEASURE-2** | Output Validation | Applicable now (rule-based output validation) | Current: JSON schema validation, deduplication, evidence trails. Future: ML confidence scores, explain ability for ML-suggested dependencies |
| **MANAGE-1** | Risk Management | If ML analysis is added | Monitor ML model drift on dependency resolution accuracy; A/B testing against rule-based baseline |

---

## 5. MITRE ATLAS (Forward-Looking)

> **Note**: These mappings apply if ML-based dependency analysis is added in the future.

| Technique | ID | Relevance | Recommended Control |
|-----------|-----|-----------|-------------------|
| Craft Adversarial Data | AML.T0043 | If ML model trained on go.mod/spec data, adversarial packages could poison training | Input validation (already implemented), training data provenance tracking, anomaly detection on training set changes |
| Poison Training Data | AML.T0020 | Malicious upstream could submit packages designed to skew ML dependency predictions | Human review of ML training data updates; version-controlled training datasets |
| Evade ML Model | AML.T0015 | Adversary crafts dependency declarations that evade ML detection | Dual validation: ML suggestions + rule-based checks; never rely solely on ML output |
| Discover ML Model | AML.T0044 | Adversary probes scanner to learn ML decision boundaries | Rate limiting on CI runs; model versioning; output normalization to prevent information leakage |

---

## 6. Compliance Summary

| Framework | Coverage | Status |
|-----------|----------|--------|
| OWASP Top 10 2021 | A01, A03, A04, A06, A08 mapped | ✅ Complete |
| MITRE CWE | CWE-22, CWE-78, CWE-120, CWE-190, CWE-377, CWE-676 mapped | ✅ Complete |
| NIST 800-53 Rev. 5 | SI-10, SI-16, SC-18, CM-7, AU-3, SA-15 mapped | ✅ Complete |
| NIST AI RMF 1.0 | MAP-1, MAP-3, MEASURE-2, MANAGE-1 (forward-looking) | ⏳ Future |
| MITRE ATLAS | AML.T0043, AML.T0020, AML.T0015, AML.T0044 (forward-looking) | ⏳ Future |
