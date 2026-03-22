# ADR-0004: Security Hardening (OWASP / MITRE ATT&CK)

**Status**: Accepted
**Date**: 2026-03-22

## Context

The tool processes untrusted CSV input from scan files and writes to a local database. It must be robust against common attack vectors.

## Decision

Apply defense-in-depth across all input processing and output generation.

## Mitigations

| MITRE Technique | Threat | Mitigation |
|-----------------|--------|------------|
| T1190 — Exploit Public-Facing Application | SQL Injection via CSV fields | All queries use `sqlite3_bind_*` parameterized statements |
| T1083 — File and Directory Discovery | Path traversal via crafted filenames | `realpath()` + prefix check; reject `..` in filenames |
| T1203 — Exploitation for Client Execution | Buffer overflow via long CSV fields | Fixed-size buffers with `snprintf`; MAX_FIELD_LEN=8192; no `sprintf`/`gets`/`strcpy` |
| T1499 — Endpoint Denial of Service | Resource exhaustion via huge files | MAX_FILE_SIZE=50MB; MAX_IMPORT_FILES=10,000; MAX_ROWS_PER_FILE=100,000 |
| T1005 — Data from Local System | Memory disclosure | All `malloc` checked for NULL; `memset` on sensitive buffers before free |
| — | XML injection in .docx output | `secure_xml_escape()` on all user-derived text |
| — | Integer overflow in size calculations | Explicit overflow checks before allocation |

## Compiler Flags

```
-Wall -Wextra -Werror -fstack-protector-strong -D_FORTIFY_SOURCE=2 -pie -fPIE -Wl,-z,relro,-z,now
```

## Verification

- Unit tests with malformed/oversized input
- Valgrind memcheck on full import+report cycle
- security-auditor droid review per phase
