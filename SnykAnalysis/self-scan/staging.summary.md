# staging self-scan summary

Scan date: 2026-05-11
Branch: snyk-self-scan-20260511

All findings are within `install-sizes-calc/C-based/tdnf-size-estimate`, a fork of upstream tdnf.

## Counts

| Phase     | Total | Warning | Note |
|-----------|-------|---------|------|
| Baseline  | 15    | 7       | 8    |
| Iter 1    | 13    | 6       | 7    |
| Accepted  | 13    | -       | -    |
| Open      | 0     | -       | -    |

## Per-finding outcomes

| Rule | Location | Outcome |
|------|----------|---------|
| cpp/DerefNull | client/config.c:74 | HARD-FIX (guarded strrchr return before *end = 0) |
| cpp/DoubleFree | client/config.c:275 | HARD-FIX (set value = NULL after free) |
| cpp/DoubleFree | client/config.c:284 | HARD-FIX (set value = NULL after free) |
| cpp/IntegerOverflow | client/varsdir.c:70 | HARD-FIX (strnlen + zero-check; residual FP on post-patch line) |
| cpp/InsecureStorage | history/history.c:213 | DESIGN-DECISION (transaction history db) |
| cpp/PT | tools/config/main.c:233 | DESIGN-DECISION (CLI rename target) |
| cpp/PT | tools/config/main.c:238 | DESIGN-DECISION (CLI unlink target) |
| cpp/PT | tools/config/main.c:452 | DESIGN-DECISION (CLI unlink target) |
| cpp/UnsafeFunctionStringHandling | common/strings.c:283 | FALSE-POSITIVE (dest pre-sized) |
| cpp/UnsafeFunctionStringHandling | common/strings.c:353 | FALSE-POSITIVE (dest pre-sized) |
| cpp/UnsafeFunctionStringHandling | common/strings.c:359 | FALSE-POSITIVE (dest pre-sized) |
| cpp/UnsafeFunctionStringHandling | solv/tdnfpackage.c:1862 | FALSE-POSITIVE (caller-sized prv_pkgname) |
| python/NoHardcodedCredentials/test | pytests/tests/test_auth.py:18 | FALSE-POSITIVE (test fixture) |
| python/SSLVerificationBypass/test | pytests/conftest.py:237 | FALSE-POSITIVE (test fixture) |
| python/ssl~wrap_socket~without~protocol/test | pytests/conftest.py:74 | FALSE-POSITIVE (test fixture) |

## Build verification

`gcc -fsyntax-only` with the cmake macros defined (HISTORY_DB_DIR, SYSTEM_LIBDIR, SYSCONFDIR, LOCALSTATEDIR) compiles both client/config.c and client/varsdir.c cleanly with no warnings or errors.
