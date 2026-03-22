# Security Review Prompt

Use this prompt with the `security-auditor` droid:

```
Review all C source files in src/ for security vulnerabilities.

Reference: specs/adr/0004-security-hardening.md

Check for:
1. SQL injection (any string concatenation in queries)
2. Buffer overflow (sprintf, gets, strcpy, strcat usage)
3. Path traversal (unvalidated file paths)
4. Integer overflow (unchecked arithmetic before allocation)
5. NULL dereference (unchecked malloc/realloc)
6. Memory leaks (unmatched malloc/free)
7. XML injection (unescaped user data in XML output)
8. Compiler hardening flags in Makefile

Report findings with severity, file, line, and fix recommendation.
```
