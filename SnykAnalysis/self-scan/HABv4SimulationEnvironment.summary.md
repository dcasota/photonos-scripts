# HABv4SimulationEnvironment self-scan summary

Scan date: 2026-05-11
Branch: snyk-self-scan-20260511

## Counts

| Phase     | Total | Warning | Note |
|-----------|-------|---------|------|
| Baseline  | 17    | 13      | 4    |
| Iter 1    | 15    | 11      | 4    |
| Accepted  | 15    | -       | -    |
| Open      | 0     | -       | -    |

## Per-finding outcomes

| Rule | Location (baseline) | Outcome |
|------|---------------------|---------|
| cpp/ClearTextLogging | ISOCreator.c:815 | FALSE-POSITIVE (GPG_KEY_EMAIL literal) |
| cpp/ClearTextLogging | habv4_keys.c:255 | FALSE-POSITIVE (GPG_KEY_EMAIL literal) |
| cpp/CommandInjection | ISOCreator.c:360 (run_cmd) | DESIGN-DECISION (root CLI, validated inputs) |
| cpp/CommandInjection | ISOCreator.c:1590 | DESIGN-DECISION |
| cpp/CommandInjection | ISOCreator.c:1831 | DESIGN-DECISION |
| cpp/CommandInjection | ISOCreator.c:1926 | DESIGN-DECISION |
| cpp/CommandInjection | ISOCreator.c:1975 | DESIGN-DECISION |
| cpp/CommandInjection | ISOCreator.c:1994 | DESIGN-DECISION |
| cpp/CommandInjection | ISOCreator.c:2073 | DESIGN-DECISION |
| cpp/CommandInjection | ISOCreator.c:480 | HARD-FIX (added whitelist sanitizer on openssl notAfter output before passing to `date -d`) |
| cpp/CommandInjection | habv4_common.c:307 | HARD-FIX (same whitelist sanitizer) |
| cpp/CommandInjection | rpm_secureboot_patcher.c:110 | FALSE-POSITIVE (popen helper; callers feed only mkdtemp + readdir paths) |
| cpp/CommandInjection | rpm_secureboot_patcher.c:1239 | FALSE-POSITIVE (`rm -rf <mkdtemp result>`) |
| cpp/PT | ISOCreator.c:1214 | DESIGN-DECISION (CLI/env source) |
| cpp/PT | ISOCreator.c:1313 | DESIGN-DECISION (CLI/env source) |
| cpp/UnsafeFunctionStringHandling | rpm_secureboot_patcher.c:236 | HARD-FIX (snprintf-bound replaces strcpy) |
| cpp/UnsafeFunctionStringHandling | rpm_secureboot_patcher.c:238 | HARD-FIX (snprintf-bound replaces strcpy) |

## Build verification

`make` in `HABv4SimulationEnvironment/src` rebuilds PhotonOS-HABv4Emulation-ISOCreator cleanly (only pre-existing `strdup_safe` unused-function warning remains).
